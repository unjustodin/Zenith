#!/usr/bin/env python3
"""Fast silhouette fits against Factorio's sprites, without Blender: the model's triangles are
projected with compare.py's camera and filled in, and compared with the sprite's alpha in every
direction score_proto.py knows for it.

    python tools/models/fit.py NAME [--glb PATH] [--dump raw.json] [--fit scale,untaper,shift]
        [--extra sx,sy,sz,untaper,dx,dz] [--png OUT.png]

Prints the overlap (IoU) per direction for the model as it is, or with --extra applied (scale
about the origin, widening towards the top, then a shift, in tiles; y is up, z south as in
glTF). --fit searches those numbers (the named groups only) for the best mean overlap; fold them
into the model's recipe (wube_recipes.py `scale`, `untaper`, `shift`) or its build function, then
check with score_proto.py, which renders with Blender. Numbers agree with compare.py's to about 0.01.
--png writes the sprite and model masks side by side per direction (git-ignored places only).
"""

import argparse
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import score_proto as score  # noqa: E402

PITCH = math.radians(48.0)


def parse(args):
    opts = {"index": "0", "line": "0", "shift": "0,0", "scale": "0.5", "rot": "0", "anchor": "0.3",
            "stretch": "1"}
    layers = []
    for a in args:
        k, v = a[2:].split("=", 1)
        if k == "layer":
            layers.append(v)
        else:
            opts[k] = v
    first = "|".join((opts["sprite"], opts["frame"], opts["index"], opts["line"], opts["shift"]))
    return opts, [first] + layers


_SHEETS = {}


def sheet(path):
    if path not in _SHEETS:
        _SHEETS[path] = np.asarray(Image.open(path).convert("RGBA"), dtype=np.float32) / 255.0
    return _SHEETS[path]


def layer(spec, ppt, scale):
    path, frame, index, line, shift, *own = spec.split("|")
    fw, fh = (int(v) for v in frame.split("x"))
    s = sheet(path)
    if index.startswith("@"):
        x, y = (int(v) for v in index[1:].split(","))
    else:
        index, line = int(index), int(line)
        if line <= 0:
            line = max(1, s.shape[1] // fw)
        x, y = (index % line) * fw, (index // line) * fh
    f = s[y:y + fh, x:x + fw]
    if own and abs(float(own[0]) - scale) > 1e-6:
        k = float(own[0]) / scale
        rows = np.minimum((np.arange(int(round(f.shape[0] * k))) / k).astype(int), f.shape[0] - 1)
        cols = np.minimum((np.arange(int(round(f.shape[1] * k))) / k).astype(int), f.shape[1] - 1)
        f = f[rows][:, cols]
    sx, sy = (float(v) * ppt / 32.0 for v in shift.split(","))
    return f, (sx, sy)


def padded(layers, lo_x, lo_y, hi_x, hi_y, share=0.15):
    """The stacked frames' bounds grown by a margin on each side the picture doesn't touch."""
    pad = share * max(hi_x - lo_x, hi_y - lo_y)
    touch = {"l": False, "t": False, "r": False, "b": False}
    for f, (ox, oy) in layers:
        a = f[..., 3] > 0.5
        x0, y0 = ox - f.shape[1] / 2, oy - f.shape[0] / 2
        touch["l"] |= abs(x0 - lo_x) < 1 and a[:, 0].any()
        touch["t"] |= abs(y0 - lo_y) < 1 and a[0, :].any()
        touch["r"] |= abs(x0 + f.shape[1] - hi_x) < 1 and a[:, -1].any()
        touch["b"] |= abs(y0 + f.shape[0] - hi_y) < 1 and a[-1, :].any()
    return (lo_x - (0 if touch["l"] else pad), lo_y - (0 if touch["t"] else pad),
            hi_x + (0 if touch["r"] else pad), hi_y + (0 if touch["b"] else pad))


def sprite_mask(specs, ppt, scale):
    """The stacked sprite's silhouette (shadows left out, as compare.py) and its centre's offset."""
    layers = [layer(s, ppt, scale) for s in specs]
    lo_x = min(o[0] - f.shape[1] / 2 for f, o in layers)
    lo_y = min(o[1] - f.shape[0] / 2 for f, o in layers)
    hi_x = max(o[0] + f.shape[1] / 2 for f, o in layers)
    hi_y = max(o[1] + f.shape[0] / 2 for f, o in layers)
    lo_x, lo_y, hi_x, hi_y = padded(layers, lo_x, lo_y, hi_x, hi_y)  # as compare.py
    w, h = int(math.ceil(hi_x - lo_x)), int(math.ceil(hi_y - lo_y))
    canvas = np.zeros((h, w, 4), dtype=np.float32)
    for f, (ox, oy) in layers:
        x0, y0 = int(round(ox - f.shape[1] / 2 - lo_x)), int(round(oy - f.shape[0] / 2 - lo_y))
        region = canvas[y0:y0 + f.shape[0], x0:x0 + f.shape[1]]
        a = f[..., 3:4]
        region[..., :3] = f[..., :3] * a + region[..., :3] * (1 - a)
        region[..., 3:4] = a + region[..., 3:4] * (1 - a)
    shadow = (canvas[..., :3].max(axis=2) <= 6 / 255) & (canvas[..., 3] < 0.97)
    return (canvas[..., 3] > 0.5) & ~shadow, ((lo_x + hi_x) / 2, (lo_y + hi_y) / 2)


def load_mesh(path, faces=40000):
    import trimesh
    scene = trimesh.load(path, force="scene")
    mesh = scene.to_geometry() if hasattr(scene, "to_geometry") else scene.dump(concatenate=True)
    if len(mesh.faces) > faces:
        try:
            mesh = mesh.simplify_quadric_decimation(face_count=faces)
        except Exception:  # noqa: BLE001  (no simplifier: use every triangle)
            pass
    return np.asarray(mesh.vertices, dtype=np.float64), np.asarray(mesh.faces)


def transform(v, extra):
    """glTF vertices with (sx, sy, sz, untaper, dx, dz) applied."""
    sx, sy, sz, untaper, dx, dz = extra
    v = v * np.array([sx, sy, sz])
    if untaper:
        height = max(v[:, 1].max(), 1e-6)
        grow = 1.0 + untaper * np.clip(v[:, 1], 0, None) / height
        v = v * np.stack([grow, np.ones_like(grow), grow], axis=1)
    return v + np.array([dx, 0.0, dz])


def model_mask(v, faces, opts, shape, centre, ppt):
    """The model's silhouette in the sprite's pixel frame (compare.py's camera)."""
    rot = math.radians(float(opts["rot"]))
    # glTF (x, y up, z south) -> Blender (x, y north, z up), turned clockwise by rot.
    bx, by, bz = v[:, 0], -v[:, 2], v[:, 1]
    c, s = math.cos(-rot), math.sin(-rot)
    x, y = c * bx - s * by, s * bx + c * by
    up = y * float(opts["stretch"]) * math.sin(PITCH) + bz * math.cos(PITCH)
    h, w = shape
    cx = centre[0] / ppt
    cy = -centre[1] / ppt + float(opts["anchor"]) * math.cos(PITCH)
    col = w / 2 + (x - cx) * ppt
    row = h / 2 - (up - cy) * ppt
    img = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(img)
    pts = np.stack([col, row], axis=1)[faces]
    for tri in pts.tolist():
        draw.polygon([tuple(p) for p in tri], fill=255)
    return np.asarray(img) > 127


def prepare(name, raw, glb):
    jobs = []
    for dn, args in score.jobs_for(name, raw):
        opts, specs = parse(score.camera_args(name) + args)
        scale = float(opts["scale"])
        ppt = 32.0 / scale
        mask, centre = sprite_mask(specs, ppt, scale)
        # A model per direction (score_proto.VARIANTS) brings its own mesh.
        own = load_mesh(os.path.join(os.path.dirname(glb), score.model_of(name, dn) + ".glb"))             if name in score.VARIANTS else None
        jobs.append((dn, opts, mask, centre, ppt, own))
    return jobs, load_mesh(glb)


def ious(jobs, mesh, extra):
    out = {}
    for dn, opts, mask, centre, ppt, own in jobs:
        v, faces = own or mesh
        m = model_mask(transform(v, extra), faces, opts, mask.shape, centre, ppt)
        out[dn] = (mask & m).sum() / max(1, (mask | m).sum())
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("name")
    ap.add_argument("--glb")
    ap.add_argument("--dump")
    ap.add_argument("--fit", default="")
    ap.add_argument("--extra", default="1,1,1,0,0,0")
    ap.add_argument("--png")
    a = ap.parse_args()
    raw = json.load(open(a.dump, encoding="utf-8")) if a.dump else __import__("icon_index").dump(score.FACTORIO)
    glb = a.glb or os.path.join(REPO, "client", "assets", "models", a.name + ".glb")
    jobs, mesh = prepare(a.name, raw, glb)
    extra = [float(x) for x in a.extra.split(",")]
    r = ious(jobs, mesh, extra)
    print("as given: " + "  ".join("%s %.3f" % kv for kv in r.items()) + "  mean %.3f" % np.mean(list(r.values())))
    groups = set(filter(None, a.fit.split(",")))
    if groups:
        from scipy.optimize import minimize
        free = [i for i, g in enumerate(("scale",) * 3 + ("untaper",) + ("shift",) * 2) if g in groups]

        def cost(p):
            e = list(extra)
            for i, val in zip(free, p):
                e[i] = val
            r = ious(jobs, mesh, e)
            vals = list(r.values())
            return -(0.7 * np.mean(vals) + 0.3 * min(vals))

        steps = np.array([0.05 if i < 3 else 0.05 if i == 3 else 0.03 for i in free])
        sim = [np.array([extra[i] for i in free])]
        sim += [sim[0] + np.eye(len(free))[k] * steps[k] for k in range(len(free))]
        res = minimize(cost, sim[0], method="Nelder-Mead",
                       options={"initial_simplex": np.array(sim), "xatol": 0.003, "fatol": 0.0005, "maxiter": 300})
        for i, val in zip(free, res.x):
            extra[i] = float(val)
        r = ious(jobs, mesh, extra)
        print("fitted:   " + "  ".join("%s %.3f" % kv for kv in r.items()) + "  mean %.3f" % np.mean(list(r.values())))
        print("extra = " + ",".join("%.3f" % x for x in extra))
    if a.png:
        tiles = []
        for dn, opts, mask, centre, ppt, own in jobs:
            v, faces = own or mesh
            m = model_mask(transform(v, extra), faces, opts, mask.shape, centre, ppt)
            rgb = np.zeros(mask.shape + (3,), np.uint8)
            rgb[mask] = (60, 200, 230)
            rgb[m] = (230, 60, 40)
            rgb[mask & m] = (200, 200, 200)
            tiles.append(Image.fromarray(rgb).resize((rgb.shape[1] * 3, rgb.shape[0] * 3), Image.NEAREST))
        W = sum(t.width for t in tiles) + 8 * len(tiles)
        out = Image.new("RGB", (W, max(t.height for t in tiles)), (30, 30, 30))
        x = 0
        for t in tiles:
            out.paste(t, (x, 0))
            x += t.width + 8
        out.save(a.png)
    return 0


if __name__ == "__main__":
    sys.exit(main())
