#!/usr/bin/env python3
"""fit.py's fast silhouette overlap (no Blender) over every cell of a model's
client/data/sprite_projection.json entry, as score_world.py scores them: each direction, each of
a vehicle's 64 or a signal's 16 rotation frames.

    python tools/models/fit_cells.py NAME... [--glb PATH] [--step N] [--extra sx,sy,sz,untaper,dx,dz]
        [--offsets] [--png OUT.png]

--offsets fits a ground offset (east, south in tiles, before the model is turned) per cell: for
models whose sprite frames aren't drawn about one point (rail signals), and prints the table the
client applies. Numbers agree with score_world.py's to about 0.01.
"""

import argparse
import json
import math
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import fit  # noqa: E402
import placement  # noqa: E402

FACTORIO = fit.score.FACTORIO
ENTRIES = os.path.join(REPO, "client", "data", "sprite_projection.json")


def layer_spec(layer):
    """As score_world.py (which needs Blender to import)."""
    path = os.path.join(FACTORIO, "data", layer["file"])
    w, h = layer["frame"]
    sx, sy = layer.get("shift", (0, 0))
    index = "@%d,%d" % tuple(layer["xy"]) if "xy" in layer else str(layer.get("index", 0))
    return "%s|%dx%d|%s|%d|%g,%g" % (path, w, h, index, layer.get("line", 0), sx, sy)


def cell_turn(entry, i):
    mode = entry.get("mode")
    if mode == "direction":
        return 90.0 * i
    if mode == "rotation":
        return 360.0 * i / len(entry["cells"])
    return 0.0


def spec(layer):
    s = layer_spec(layer)
    return s + "|%g" % layer["scale"] if "scale" in layer else s


def jobs(name, step=1, stretch=None):
    """[(cell, camera, sprite mask, its centre, pixels a tile, the client's offset)]."""
    entry = json.load(open(ENTRIES, encoding="utf-8"))[name]
    placed = placement.offsets().get(name)
    n = len(entry["cells"])
    picks = range(0, n, step) if entry.get("mode") == "rotation" else range(n)
    out = []
    for i in picks:
        cell = entry["cells"][i]
        scale = cell[0].get("scale", 0.5)
        opts = {"rot": cell_turn(entry, i), "anchor": entry.get("anchor", 0.3),
                "stretch": stretch or entry.get("stretch", 1.0)}
        ppt = 32.0 / scale
        specs = [spec(l) for l in cell]
        mask, centre = fit.sprite_mask(specs, ppt, scale)
        off = tuple(placed[i % len(placed)]) if placed else (0.0, 0.0)
        out.append((i, opts, mask, centre, ppt, off))
    return out


def iou(job, v, faces, off=None):
    """Overlap in one cell, the model moved by `off` (east, south in its own frame, before it is
    turned: as the client) or else by the client's own offset for that cell."""
    i, opts, mask, centre, ppt, placed = job
    dx, dz = placed if off is None else off
    m = fit.model_mask(v + np.array([dx, 0.0, dz]), faces, opts, mask.shape, centre, ppt)
    return (mask & m).sum() / max(1, (mask | m).sum()), m


def fit_offset(job, v, faces, start=(0.0, 0.0)):
    best = (iou(job, v, faces, start)[0], start)
    for span in (0.4, 0.15, 0.05, 0.02):
        cx, cz = best[1]
        for ax in np.linspace(-span, span, 9):
            for az in np.linspace(-span, span, 9):
                o = (cx + ax, cz + az)
                s = iou(job, v, faces, o)[0]
                if s > best[0] + 1e-6:
                    best = (s, o)
    return best


def fit_extra(js, v0, faces, extra, groups):
    """fit.py's search (scale, untaper, shift) over these cells: best 0.7 mean + 0.3 lowest."""
    from scipy.optimize import minimize
    free = [i for i, g in enumerate(("scale",) * 3 + ("untaper",) + ("shift",) * 2) if g in groups]

    def cost(p):
        e = list(extra)
        for i, val in zip(free, p):
            e[i] = val
        v = fit.transform(v0, e)
        vals = [iou(j, v, faces)[0] for j in js]
        return -(0.7 * np.mean(vals) + 0.3 * min(vals))

    steps = np.array([0.05 if i < 4 else 0.03 for i in free])
    sim = [np.array([extra[i] for i in free])]
    sim += [sim[0] + np.eye(len(free))[k] * steps[k] for k in range(len(free))]
    res = minimize(cost, sim[0], method="Nelder-Mead",
                   options={"initial_simplex": np.array(sim), "xatol": 0.003, "fatol": 0.0005, "maxiter": 200})
    out = list(extra)
    for i, val in zip(free, res.x):
        out[i] = float(val)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("names", nargs="+")
    ap.add_argument("--glb")
    ap.add_argument("--step", type=int, default=1)
    ap.add_argument("--extra", default="1,1,1,0,0,0")
    ap.add_argument("--offsets", action="store_true")
    ap.add_argument("--fit", default="", help="groups to fit: scale, untaper, shift (as fit.py)")
    ap.add_argument("--faces", type=int, default=40000)
    ap.add_argument("--stretch", type=float, help="try another projection stretch than the entry's")
    ap.add_argument("--png")
    a = ap.parse_args()
    for name in a.names:
        extra = [float(x) for x in a.extra.split(",")]
        glb = a.glb or os.path.join(REPO, "client", "assets", "models", name + ".glb")
        v0, faces = fit.load_mesh(glb, a.faces)
        js = jobs(name, a.step, a.stretch)
        if a.fit:
            extra = fit_extra(js, v0, faces, extra, set(a.fit.split(",")))
            print("%-28s extra = %s" % (name, ",".join("%.3f" % x for x in extra)))
        v = fit.transform(v0, extra)
        rows, masks = [], []
        for job in js:
            if a.offsets:
                s, off = fit_offset(job, v, faces)
                rows.append((job[0], s, off))
                masks.append((job, iou(job, v, faces, off)[1]))
            else:
                s, m = iou(job, v, faces)
                rows.append((job[0], s, None))
                masks.append((job, m))
        vals = [r[1] for r in rows]
        print("%-28s mean %.3f  min %.3f  cells %d" % (name, np.mean(vals), min(vals), len(vals)))
        print("   " + " ".join("%d:%.2f" % (r[0], r[1]) for r in rows))
        if a.offsets:
            print('   for PLACEMENT_OFFSETS: "%s": [%s],' % (name, ", ".join("[%.3f, %.3f]" % r[2] for r in rows)))
        if a.png:
            tiles = []
            for (i, opts, mask, centre, ppt, placed), m in masks:
                rgb = np.zeros(mask.shape + (3,), np.uint8)
                rgb[mask] = (60, 200, 230)
                rgb[m] = (230, 60, 40)
                rgb[mask & m] = (200, 200, 200)
                tiles.append(Image.fromarray(rgb).resize((rgb.shape[1] * 2, rgb.shape[0] * 2), Image.NEAREST))
            cols = min(8, len(tiles))
            tw = max(t.width for t in tiles) + 6
            th = max(t.height for t in tiles) + 6
            out = Image.new("RGB", (tw * cols, th * ((len(tiles) + cols - 1) // cols)), (30, 30, 30))
            for k, t in enumerate(tiles):
                out.paste(t, ((k % cols) * tw, (k // cols) * th))
            path = a.png if len(a.names) == 1 else a.png.replace(".png", "-%s.png" % name)
            out.save(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
