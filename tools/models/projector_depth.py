#!/usr/bin/env python3
"""Depth maps of each model as Factorio's camera sees it, so the client projects the game's
sprite only onto the surfaces that camera actually sees.

    python tools/models/projector_depth.py [names...]

The sprite is projected along Factorio's view (client/shaders/factorio_material.gdshaderinc), so
without a test every surface behind another one gets the same sprite pixels: the roboport's
cables land on the body behind them, a tank's front paints its back. The per-vertex visibility
bake.py stores can't see a cable's shadow in the middle of a big face; this per-pixel map can.

For every model with a sprite projection entry (client/data/sprite_projection.json, except the
vehicles' 64-frame ones), and every direction the entry has (one for single and variation
entries), the model's triangles are rasterised in projector space: x across, "up" the screen
(with the entry's north-south `stretch`), and for each pixel the frontmost surface's distance
towards the camera ("closeness", tiles). The shader compares a fragment's own closeness with the
map's: anything clearly behind takes the procedural material instead of the sprite.

Output (derived from our own models only, so it's committed):
    client/data/projector_depth.json    {name: {"ppt", "size": [w, h], "cells": [[ax, ay], ...]}}
                                        `cells`: pixel position of the projector origin (x 0,
                                        up 0) per direction cell, cells side by side
    client/data/projector_depth/<name>.bin   zlib-compressed float16 closeness, row-major, h x w;
                                        EMPTY where nothing is drawn

Plain Python: numpy, trimesh (reads the .glb files with their node transforms).
"""

import json
import math
import os
import sys
import zlib

import numpy as np
import trimesh

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
MODELS = os.path.join(REPO, "client", "assets", "models")
DATA = os.path.join(REPO, "client", "data")
ENTRIES = os.path.join(DATA, "sprite_projection.json")
OUT_JSON = os.path.join(DATA, "projector_depth.json")
OUT_DIR = os.path.join(DATA, "projector_depth")

PPT = 32          # pixels per tile: half the HR sprites', fine enough for cables and rails
PAD = 2
EMPTY = -100.0
SIN, COS = math.sin(math.radians(48.0)), math.cos(math.radians(48.0))


def load_triangles(path):
    """(T, 3, 3) triangles in model space, glTF axes (x east, y up, z south), every node except
    `anim_upright_*` ones (they don't turn with the model, and wear a projection of their own)."""
    scene = trimesh.load(path, force="scene")
    tris = []
    for node in scene.graph.nodes_geometry:
        if str(node).startswith("anim_upright"):
            continue
        transform, geom = scene.graph[node]
        mesh = scene.geometry[geom]
        v = trimesh.transformations.transform_points(mesh.vertices, transform)
        tris.append(v[mesh.faces])
    return np.concatenate(tris) if tris else np.zeros((0, 3, 3))


def projector(tris, direction, stretch):
    """(x, up, closeness) per corner, for the model turned to face `direction` (0-3), as the
    shader does it."""
    a = -direction * math.pi / 2
    c, s = math.cos(a), math.sin(a)
    x, y, z = tris[..., 0], tris[..., 1], tris[..., 2]
    px, pz = x * c + z * s, -x * s + z * c
    return np.stack([px, y * COS - pz * SIN * stretch, y * SIN + pz * COS], axis=-1)


def rasterise(proj, origin, size):
    """Max closeness per pixel. proj: (T, 3, 3) of (x, up, closeness); origin: the pixel of
    (x 0, up 0); size: (w, h)."""
    w, h = size
    depth = np.full((h, w), EMPTY, dtype=np.float32)
    px = origin[0] + proj[..., 0] * PPT
    py = origin[1] - proj[..., 1] * PPT
    cl = proj[..., 2]
    # Drop triangles seen edge-on: they cover nothing.
    e1x, e1y = px[:, 1] - px[:, 0], py[:, 1] - py[:, 0]
    e2x, e2y = px[:, 2] - px[:, 0], py[:, 2] - py[:, 0]
    area = e1x * e2y - e1y * e2x
    keep = np.abs(area) > 1e-6
    for t in np.nonzero(keep)[0]:
        x0, x1 = int(math.floor(px[t].min())), int(math.ceil(px[t].max()))
        y0, y1 = int(math.floor(py[t].min())), int(math.ceil(py[t].max()))
        x0, y0 = max(x0, 0), max(y0, 0)
        x1, y1 = min(x1, w - 1), min(y1, h - 1)
        if x1 < x0 or y1 < y0:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        dx, dy = gx - px[t, 0], gy - py[t, 0]
        inv = 1.0 / area[t]
        b1 = (dx * e2y[t] - dy * e2x[t]) * inv
        b2 = (e1x[t] * dy - e1y[t] * dx) * inv
        b0 = 1.0 - b1 - b2
        # A little slack so pixels whose centre misses a thin part still get it.
        inside = (b0 >= -0.02) & (b1 >= -0.02) & (b2 >= -0.02)
        if not inside.any():
            continue
        d = b0 * cl[t, 0] + b1 * cl[t, 1] + b2 * cl[t, 2]
        region = depth[y0:y1 + 1, x0:x1 + 1]
        np.maximum(region, np.where(inside, d, EMPTY), out=region)
    return depth


def build(name, entry):
    path = os.path.join(MODELS, name + ".glb")
    if not os.path.exists(path):
        return None
    tris = load_triangles(path)
    if len(tris) == 0:
        return None
    stretch = float(entry.get("stretch", 1.0))
    directions = range(4) if entry.get("mode") == "direction" else range(1)
    projs = [projector(tris, d, stretch) for d in directions]
    lo = np.min([p[..., :2].reshape(-1, 2).min(axis=0) for p in projs], axis=0)
    hi = np.max([p[..., :2].reshape(-1, 2).max(axis=0) for p in projs], axis=0)
    cw = int(math.ceil((hi[0] - lo[0]) * PPT)) + 2 * PAD
    ch = int(math.ceil((hi[1] - lo[1]) * PPT)) + 2 * PAD
    cells, maps = [], []
    for i, p in enumerate(projs):
        origin = (i * cw + PAD - lo[0] * PPT, PAD + hi[1] * PPT)
        cells.append([round(origin[0], 3), round(origin[1], 3)])
        maps.append(rasterise(p, (PAD - lo[0] * PPT, PAD + hi[1] * PPT), (cw, ch)))
    image = np.concatenate(maps, axis=1)
    return {"ppt": PPT, "size": [int(image.shape[1]), int(image.shape[0])], "cells": cells}, image


def main(argv):
    entries = json.load(open(ENTRIES, encoding="utf-8"))
    names = argv or sorted(n for n, e in entries.items() if e.get("mode") != "rotation" and "." not in n)
    meta = json.load(open(OUT_JSON, encoding="utf-8")) if os.path.exists(OUT_JSON) else {}
    os.makedirs(OUT_DIR, exist_ok=True)
    for name in names:
        if name not in entries or entries[name].get("mode") == "rotation" or "." in name:
            print("%-30s skipped (no entry, or a vehicle's frames round the turn)" % name)
            continue
        out = build(name, entries[name])
        if out is None:
            meta.pop(name, None)
            continue
        info, image = out
        with open(os.path.join(OUT_DIR, name + ".bin"), "wb") as f:
            f.write(zlib.compress(image.astype(np.float16).tobytes(), 9))
        meta[name] = info
        print("%-30s %4d x %-4d %d cell(s)" % (name, info["size"][0], info["size"][1], len(info["cells"])))
    with open(OUT_JSON, "w", encoding="utf-8", newline="\n") as f:
        f.write("{\n")
        items = sorted(meta.items())
        for k, (name, info) in enumerate(items):
            f.write("  %s: %s%s\n" % (json.dumps(name), json.dumps(info, separators=(", ", ": ")),
                                      "," if k + 1 < len(items) else ""))
        f.write("}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
