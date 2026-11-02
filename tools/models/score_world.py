"""Scores models against Factorio's sprites in every cell of their sprite_projection.json entry
(each direction, each of a vehicle's 64 or a signal's 16 rotation frames, each ore variation),
in one Blender run, with compare.py's silhouette overlap.

    blender --background --factory-startup --python tools/models/score_world.py -- NAME...
        [--step=N] [--out=DIR] [--json=PATH] [--glb=PATH]

`--step` scores every N-th rotation frame (default 1: all of them). Cells are read from
client/data/sprite_projection.json as the client projects them: a direction cell turns the model
90 degrees a step, a rotation cell 360 / cells, a variation cell not at all; rails ("projection":
"top") are seen straight down. compare.py's three-panel pictures go to DIR (default
art-src/score/), which hold Factorio's art and must never be committed.

Per model it prints the mean and lowest overlap and the mean colours of the sprite and the
render (first cell) with their distance in RGB 0-255. (models-power's score.py does the same for
direction cells; this one adds rotation, variation and top-down cells.)
"""

import contextlib
import io
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import compare  # noqa: E402
import placement  # noqa: E402

FACTORIO = os.environ.get("FACTORIO", r"C:\Program Files (x86)\Steam\steamapps\common\Factorio")
ENTRIES = os.path.join(REPO, "client", "data", "sprite_projection.json")


def layer_spec(layer):
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


OFFSETS = placement.offsets()  # the client's per-direction offsets (rail signals)


def run_cell(name, entry, i, png, glb=None):
    first, *rest = entry["cells"][i]
    path, frame, index, line, shift = layer_spec(first).split("|")
    args = [png, name, "--sprite=" + path, "--frame=" + frame, "--index=" + index, "--line=" + line,
            "--shift=" + shift, "--scale=%g" % first.get("scale", 0.5), "--rot=%g" % cell_turn(entry, i),
            "--anchor=%g" % entry.get("anchor", compare.FACTORIO_ANCHOR_Z),
            "--stretch=%g" % entry.get("stretch", 1.0), "--zoom=1", "--shadowless=1"]
    if entry.get("projection") == "top":
        args.append("--pitch=90")
    if name in OFFSETS:
        args.append("--offset=%g,%g" % tuple(OFFSETS[name][i % len(OFFSETS[name])]))
    if glb:
        args.append("--glb=" + glb)
    args += ["--layer=" + layer_spec(l) for l in rest]
    sys.argv = ["blender", "--"] + args
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        compare.main()
    m = re.search(r"sprite (\S+)\s+model (\S+)\s+silhouette overlap ([\d.]+)", buf.getvalue())
    if not m:
        return {"cell": i, "error": (buf.getvalue().strip().splitlines() or ["no output"])[-1]}
    return {"cell": i, "iou": float(m.group(3)), "sprite": m.group(1), "model": m.group(2)}


def colour_gap(a, b):
    if not (a.startswith("#") and b.startswith("#")):
        return -1
    ca = [int(a[k:k + 2], 16) for k in (1, 3, 5)]
    cb = [int(b[k:k + 2], 16) for k in (1, 3, 5)]
    return round(sum((x - y) ** 2 for x, y in zip(ca, cb)) ** 0.5)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir, json_path, step, glb, names = os.path.join(REPO, "art-src", "score"), None, 1, None, []
    for arg in argv:
        if arg.startswith("--out="):
            out_dir = os.path.abspath(arg.split("=", 1)[1])
        elif arg.startswith("--json="):
            json_path = os.path.abspath(arg.split("=", 1)[1])
        elif arg.startswith("--step="):
            step = int(arg.split("=", 1)[1])
        elif arg.startswith("--glb="):
            glb = os.path.abspath(arg.split("=", 1)[1])
        else:
            names.append(arg)
    entries = json.load(open(ENTRIES, encoding="utf-8"))
    os.makedirs(out_dir, exist_ok=True)
    results = {}
    for name in names:
        entry = entries.get(name)
        if entry is None:
            print("score: %-36s no sprite_projection entry" % name)
            continue
        n = len(entry["cells"])
        picks = range(0, n, step) if entry.get("mode") == "rotation" else range(n)
        rows = [run_cell(name, entry, i, os.path.join(out_dir, "%s-%02d.png" % (name, i)), glb) for i in picks]
        good = [r for r in rows if "iou" in r]
        mean = sum(r["iou"] for r in good) / max(1, len(good))
        worst = min((r["iou"] for r in good), default=0.0)
        first = good[0] if good else {"sprite": "-", "model": "-"}
        gap = round(sum(colour_gap(r["sprite"], r["model"]) for r in good) / max(1, len(good)))
        results[name] = {"mean": round(mean, 3), "min": round(worst, 3), "colour_gap": gap,
                         "sprite": first["sprite"], "model": first["model"], "cells": rows}
        print("score: %-36s mean %.3f  min %.3f  cells %d  colour %s vs %s (gap %d)%s" % (
            name, mean, worst, len(good), first["sprite"], first["model"], gap,
            "  ERRORS %d" % (len(rows) - len(good)) if len(good) < len(rows) else ""))
        sys.stdout.flush()
    if json_path:
        old = json.load(open(json_path, encoding="utf-8")) if os.path.exists(json_path) else {}
        old.update(results)
        with open(json_path, "w", encoding="utf-8") as f:
            json.dump(old, f, indent=1)
    return 0


if __name__ == "__main__":
    code = main()
    sys.stdout.flush()
    sys.exit(code)
