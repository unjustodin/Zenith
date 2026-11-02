"""Scores models against Factorio's sprites in every direction the sprite has, in one Blender run.

    blender --background --factory-startup --python tools/models/score.py -- NAME... [--out=DIR] [--json=PATH]
        [--stretch=S] [--anchor=Z] [--pitch=DEG] [--glb=PATH]   (override the entry's, to try a fit)

For each name in tools/models/sprite_projection.py's BUILDINGS it runs compare.py once per cell
(north, east, south, west for directional entities) with the cell's layers and the entry's
anchor and stretch, as the client projects it. Prints a table of the silhouette overlap
(intersection over union of the sprite's and the render's alpha) and the mean colours, and saves
compare.py's three-panel pictures (and `.diff.png`, where the silhouettes disagree) in DIR (default art-src/score/), which hold Factorio's art and
must never be committed.
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
import sprite_projection as sp  # noqa: E402

FACTORIO = os.environ.get("FACTORIO", sp.FACTORIO)
DIRS = ("N", "E", "S", "W")


def layer_spec(layer):
    path = os.path.join(FACTORIO, "data", layer["file"])
    w, h = layer["frame"]
    sx, sy = layer.get("shift", (0, 0))
    return "%s|%dx%d|%s|%d|%g,%g" % (path, w, h, layer.get("index", 0), layer.get("line", 0), sx, sy)


def cells(name):
    entry = sp.BUILDINGS[name]
    out = entry["cells"]
    directional = entry.get("mode") == "direction"
    for i, layers in enumerate(out):
        yield (DIRS[i] if directional else "-"), (90 * i if directional else 0), layers, entry


def score(name, out_dir, overrides=None):
    rows = []
    for label, rot, layers, entry in cells(name):
        png = os.path.join(out_dir, "%s-%s.png" % (name, label))
        first, *rest = layers
        args = [png, name, "--sprite=" + layer_spec(first).split("|")[0],
                "--frame=%dx%d" % tuple(first["frame"]), "--index=%s" % first.get("index", 0),
                "--line=%d" % first.get("line", 0), "--shift=%g,%g" % tuple(first.get("shift", (0, 0))),
                "--scale=%g" % first.get("scale", 0.5), "--rot=%d" % rot,
                "--anchor=%g" % entry.get("anchor", sp.BUILDING_ANCHOR),
                "--stretch=%g" % entry.get("stretch", 1.0), "--diff=" + png[:-4] + ".diff.png"]
        args += ["--layer=" + layer_spec(l) for l in rest]
        # Parts the client keeps facing north wear their own picture in every direction.
        upright = sp.BUILDINGS.get(name + ".upright")
        if upright:
            args += ["--keep-upright=1"] + ["--layer=" + layer_spec(l) for l in upright["cells"][0]]
        args += ["--%s=%s" % kv for kv in (overrides or {}).items()]
        sys.argv = ["blender", "--"] + args
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            compare.main()
        text = buf.getvalue()
        m = re.search(r"sprite (\S+)\s+model (\S+)\s+silhouette overlap ([\d.]+)", text)
        if not m:
            rows.append({"dir": label, "error": text.strip().splitlines()[-1:] or "no output"})
            continue
        rows.append({"dir": label, "iou": float(m.group(3)), "sprite": m.group(1), "model": m.group(2)})
    return rows


def colour_gap(a, b):
    if not (a.startswith("#") and b.startswith("#")):
        return -1
    ca = [int(a[i:i + 2], 16) for i in (1, 3, 5)]
    cb = [int(b[i:i + 2], 16) for i in (1, 3, 5)]
    return round(sum((x - y) ** 2 for x, y in zip(ca, cb)) ** 0.5)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = os.path.join(REPO, "art-src", "score")
    json_path = None
    overrides = {}
    names = []
    for arg in argv:
        if arg.startswith("--out="):
            out_dir = os.path.abspath(arg.split("=", 1)[1])
        elif arg.split("=", 1)[0] in ("--stretch", "--anchor", "--pitch", "--glb"):
            k, v = arg[2:].split("=", 1)
            overrides[k] = v
        elif arg.startswith("--json="):
            json_path = os.path.abspath(arg.split("=", 1)[1])
        else:
            names.append(arg)
    os.makedirs(out_dir, exist_ok=True)
    results = {}
    for name in names:
        if name not in sp.BUILDINGS:
            print("score: %-32s no sprite_projection entry" % name)
            continue
        rows = score(name, out_dir, overrides)
        results[name] = rows
        cols = "  ".join("%s %.2f" % (r["dir"], r["iou"]) if "iou" in r else "%s ERR" % r["dir"] for r in rows)
        gaps = [colour_gap(r["sprite"], r["model"]) for r in rows if "iou" in r]
        worst = min((r["iou"] for r in rows if "iou" in r), default=0)
        first = next((r for r in rows if "iou" in r), {"sprite": "-", "model": "-"})
        print("score: %-32s min %.2f  %s  colour %s vs %s (gap %s)" % (
            name, worst, cols, first["sprite"], first["model"], max(gaps, default=-1)))
        sys.stdout.flush()
    if json_path:
        with open(json_path, "w", encoding="utf-8") as f:
            json.dump(results, f, indent=1)
    return 0


if __name__ == "__main__":
    code = main()
    sys.stdout.flush()
    sys.exit(code)
