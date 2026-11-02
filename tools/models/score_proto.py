#!/usr/bin/env python3
"""Scores models against Factorio's sprites in every direction the sprite has: silhouette
overlap (IoU of the model's and the sprite's alpha, from tools/models/compare.py) and the
difference of their average colours.

    python tools/models/score_proto.py [names...] [--jobs 4] [--dump raw.json] [--out DIR] [--only-dirs N,E]

Each model's sprite layers are read from Factorio's own prototypes (`factorio --dump-data`,
cached with --dump), not typed in by hand: for every direction, the non-shadow, non-glow layers
of its picture, first frame, seen by the client's projection camera (anchor and stretch from
client/data/sprite_projection.json). Belts and undergrounds pick their rows as the client picks models
(model_library.gd). The table goes to stdout and OUT/scores.json; every comparison picture to
OUT/<name>-<dir>.png (default art-src/score/, git-ignored: they contain Factorio's art).

A model with no entry in PICTURES falls back to gallery.py's single north comparison.
"""

import argparse
import concurrent.futures
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, "tools"))

BLENDER = os.environ.get("BLENDER", r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe")
FACTORIO = os.environ.get("FACTORIO", r"C:\Program Files (x86)\Steam\steamapps\common\Factorio")
DIRS = ("north", "east", "south", "west")
STRETCH = 1.346  # 1 / sin 48 degrees
PROJECTION = json.load(open(os.path.join(REPO, "client", "data", "sprite_projection.json"), encoding="utf-8"))

# Model -> (prototype type, prototype name, picture key path). Keys are tried in order.
PICTURES = {}
for _n in ("wooden-chest", "iron-chest", "steel-chest"):
    PICTURES[_n] = ("container", _n, ["picture"])
for _n in ("passive-provider-chest", "active-provider-chest", "storage-chest", "buffer-chest", "requester-chest"):
    PICTURES[_n] = ("logistic-container", _n, ["animation", "robot_door.animation"])
for _n in ("burner-inserter", "inserter", "long-handed-inserter", "fast-inserter", "bulk-inserter", "stack-inserter"):
    PICTURES[_n] = ("inserter", _n, ["platform_picture"])
for _n in ("burner-mining-drill", "electric-mining-drill"):
    PICTURES[_n] = ("mining-drill", _n, ["graphics_set.animation"])
for _n in ("stone-furnace", "steel-furnace"):
    PICTURES[_n] = ("furnace", _n, ["graphics_set.animation"])
for _n in ("assembling-machine-1", "assembling-machine-2", "assembling-machine-3"):
    PICTURES[_n] = ("assembling-machine", _n, ["graphics_set.animation"])
for _n in ("arithmetic-combinator", "decider-combinator", "selector-combinator"):
    PICTURES[_n] = (_n, _n, ["sprites"])
for _n in ("one-way-valve", "overflow-valve", "top-up-valve"):
    PICTURES[_n] = ("valve", _n, ["animations"])
# Models drawn unturned, one per direction (model_library.gd model_name and PICTURES): each is
# compared with its own direction's picture as it is.
VARIANTS = {"burner-mining-drill": {dn: "burner-mining-drill" + sfx for dn, sfx in
                                    zip(DIRS, ("", "-east", "-south", "-west"))}}
for _n in ("one-way-valve", "overflow-valve", "top-up-valve"):  # circuits.py valve()
    VARIANTS[_n] = {dn: _n + sfx for dn, sfx in zip(DIRS, ("", "-east", "-south", "-west"))}
# The inserters' platforms: a model per direction too (wube_recipes.py INSERTER_FITS).
for _n in ("burner-inserter", "inserter", "long-handed-inserter", "fast-inserter", "bulk-inserter", "stack-inserter"):
    VARIANTS[_n] = {dn: _n + sfx for dn, sfx in zip(DIRS, ("", "-east", "-south", "-west"))}
for _n in ("pumpjack", "chemical-plant"):
    VARIANTS[_n] = {dn: _n + sfx for dn, sfx in zip(DIRS, ("", "-east", "-south", "-west"))}
# The pumpjack: its base (the pipes and motor, four pictures) under the beam's layer (one for all).
PICTURES["pumpjack"] = ("mining-drill", "pumpjack", ["base_picture", "graphics_set.animation"])
PICTURES["chemical-plant"] = ("assembling-machine", "chemical-plant", ["graphics_set.animation"])


def model_of(name, dn):
    return VARIANTS.get(name, {}).get(dn, name)


PICTURES.update({
    "lab": ("lab", "lab", ["off_animation"]),
    "constant-combinator": ("constant-combinator", "constant-combinator", ["sprites"]),
    "power-switch": ("power-switch", "power-switch", ["power_on_animation"]),
    "programmable-speaker": ("programmable-speaker", "programmable-speaker", ["sprite"]),
    "small-lamp": ("lamp", "small-lamp", ["picture_off"]),
    "display-panel": ("display-panel", "display-panel", ["sprites"]),
    "splitter": ("splitter", "splitter", ["structure_patch", "structure"]),
    "lane-splitter": ("lane-splitter", "lane-splitter", ["structure_patch", "structure"]),
    "market": ("market", "market", ["picture"]),
    "loader": ("loader", "loader", ["structure.direction_in"]),
    "loader-1x1": ("loader-1x1", "loader-1x1", ["structure.direction_in"]),
    "underground-belt-input": ("underground-belt", "underground-belt", ["structure.direction_in"]),
    "underground-belt-output": ("underground-belt", "underground-belt", ["structure.direction_out"]),
})

# Belt sheet rows (belt_animation_set, 0-based) per direction: straight, left curve (items turn
# left into that direction: travelling east then north is west_to_north, row 6), right curve.
BELT_ROWS = {
    "transport-belt": {"north": 2, "east": 0, "south": 3, "west": 1},
    "transport-belt-curve-left": {"north": 6, "east": 5, "south": 9, "west": 10},
    "transport-belt-curve-right": {"north": 4, "east": 8, "south": 11, "west": 7},
}
_SPLIT = {"north": [(-0.5, 0), (0.5, 0)], "south": [(-0.5, 0), (0.5, 0)],
          "east": [(0, -0.5), (0, 0.5)], "west": [(0, -0.5), (0, 0.5)]}
UNDER_BELTS = {"underground-belt": {d: [(0, 0)] for d in DIRS}, "splitter": _SPLIT,
               "lane-splitter": {d: [(0, 0)] for d in DIRS}, "loader-1x1": {d: [(0, 0)] for d in DIRS}}
# Factorio's belt sheet puts the entity's position this high above the belt's ground (fitted over
# the straight belt and both curves with fit.py, the anchor and stretch left free: 0.17-0.18, 1.29-1.34).
BELT_ANCHOR = 0.18
# Models turned more than their direction (model_library.gd turn_dir).
EXTRA_TURN = {"underground-belt-output": 180}


def get_path(obj, path):
    for k in path.split("."):
        if not isinstance(obj, dict) or k not in obj:
            return None
        obj = obj[k]
    return obj


def sized(obj):
    if "size" in obj and "width" not in obj:
        sz = obj["size"]
        w, h = (sz, sz) if isinstance(sz, (int, float)) else sz
        obj = dict(obj, width=w, height=h)
    return obj


def layers_of(obj, d):
    """The drawable layers of a sprite/animation (4-way or not) for direction index d."""
    if obj is None:
        return []
    if isinstance(obj, dict):
        obj = sized(obj)
    if isinstance(obj, list):
        return [l for o in obj for l in layers_of(o, d)]
    if DIRS[d] in obj:
        return layers_of(obj[DIRS[d]], d)
    if "layers" in obj:
        return layers_of(obj["layers"], d)
    if "sheets" in obj:
        return [l for s in obj["sheets"] for l in layers_of({"sheet": s}, d)]
    if "sheet" in obj:
        s = sized(dict(obj["sheet"]))
        frames = s.get("frames", 4)
        s["x"] = s.get("x", 0) + (d % frames) * s["width"]
        return layers_of(s, d)
    if any(k in obj for k in DIRS):  # a 4-way picture without this direction
        return []
    if obj.get("draw_as_shadow") or obj.get("draw_as_glow") or obj.get("draw_as_light"):
        return []
    if obj.get("blend_mode") in ("additive", "additive-soft", "multiplicative"):
        return []
    if "stripes" in obj:
        st = obj["stripes"][0]
        obj = dict(obj, filename=st["filename"], x=st.get("x", 0), y=st.get("y", 0))
    if "filenames" in obj:
        obj = dict(obj, filename=obj["filenames"][0])
    if "filename" not in obj:
        return []
    return [obj]


def file_of(path):
    m = re.match(r"__([a-z0-9_-]+)__/(.+)", path)
    mod, rest = m.group(1), m.group(2)
    return os.path.join(FACTORIO, "data", mod, rest)


def compare_args(layers):
    """compare.py arguments for a stack of layers (the first is --sprite)."""
    out = []
    scale = layers[0].get("scale", 1)
    for i, l in enumerate(layers):
        sh = l.get("shift") or [0, 0]
        if isinstance(sh, dict):
            sh = [sh.get("x", 0), sh.get("y", 0)]
        shift = "%g,%g" % (sh[0] * 32, sh[1] * 32)
        frame = "%dx%d" % (l["width"], l["height"])
        at = "@%d,%d" % (l.get("x", 0), l.get("y", 0))
        if i == 0:
            out += ["--sprite=" + file_of(l["filename"]), "--frame=" + frame, "--index=" + at,
                    "--shift=" + shift, "--scale=%g" % scale]
        else:
            out.append("--layer=%s|%s|%s|0|%s|%g" % (file_of(l["filename"]), frame, at, shift, l.get("scale", 1)))
    return out


def jobs_for(name, raw):
    """[(direction, compare.py arguments)] for one model."""
    if name in BELT_ROWS:
        belt = sized(raw["transport-belt"]["transport-belt"]["belt_animation_set"]["animation_set"])
        w, h = belt["width"], belt["height"]
        return [(dn, ["--sprite=" + file_of(belt["filename"]), "--frame=%dx%d" % (w, h),
                      "--index=@0,%d" % (row * h), "--scale=%g" % belt.get("scale", 1), "--rot=%d" % (90 * DIRS.index(dn))])
                for dn, row in BELT_ROWS[name].items()]
    if name not in PICTURES:
        import gallery
        if name not in gallery.BUILDINGS:
            return []
        sheet, *rest = gallery.BUILDINGS[name]
        return [("north", ["--sprite=" + os.path.join(FACTORIO, sheet), *rest])]
    ptype, pname, keys = PICTURES[name]
    proto = raw[ptype][pname]
    belt = sized(raw["transport-belt"]["transport-belt"]["belt_animation_set"]["animation_set"])
    out = []
    for d, dn in enumerate(DIRS):
        # Undergrounds, splitters and loaders are drawn over a plain belt (two for a splitter).
        layers = [dict(belt, y=belt["height"] * BELT_ROWS["transport-belt"][dn], shift=[dx, dy])
                  for dx, dy in UNDER_BELTS.get(ptype, {}).get(dn, [])]
        for k in keys:
            layers += layers_of(get_path(proto, k), d)
        # Parts drawn as working visualisations that are always on (the electric drill's head).
        for vis in get_path(proto, "graphics_set.working_visualisations") or []:
            if vis.get("always_draw") and "light" not in vis:
                layers += layers_of(vis.get(DIRS[d] + "_animation") or vis.get("animation"), d)
        if not layers:
            continue
        rot = 0 if name in VARIANTS else (90 * d + EXTRA_TURN.get(name, 0)) % 360
        args = compare_args(layers) + ["--rot=%d" % rot]
        if out and args[:-1] == out[0][1][:-1]:
            # Same picture in every direction (not rotatable): north is enough.
            break
        out.append((dn, args))
    return out


def camera_args(name):
    """The client's projection camera for this model (sprite_projection.json). Models without
    an entry are scored at true proportions (Factorio draws tiles square: stretch 1.346, as
    sprite_projection.py TRUE_PROPORTIONS); flat belts sit on the ground."""
    if name in BELT_ROWS or name.startswith("underground-belt-"):
        return ["--anchor=%g" % BELT_ANCHOR, "--stretch=%g" % STRETCH]
    if name.endswith("-valve"):
        return ["--anchor=0.375", "--stretch=%g" % STRETCH]  # drawn like the pipe kit (PIPE_FIT)
    if name not in PROJECTION:
        return ["--anchor=0.3", "--stretch=%g" % STRETCH]  # not projected: true proportions
    e = PROJECTION[name]
    return ["--anchor=%g" % e.get("anchor", 0.3), "--stretch=%g" % e.get("stretch", 1)]


def run(name, dn, args, out_dir):
    png = os.path.join(out_dir, "%s-%s.png" % (name, dn))
    cmd = [BLENDER, "--background", "--factory-startup", "--python", "tools/models/compare.py", "--", png,
           model_of(name, dn)] + camera_args(name) + args
    r = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True)
    m = re.search(r"sprite (#\w+|-)\s+model (#\w+|-)\s+silhouette overlap ([\d.]+)", r.stdout)
    if not m:
        tail = (r.stderr or r.stdout).strip().splitlines()[-2:]
        return name, dn, None, None, None, " / ".join(tail)
    return name, dn, float(m.group(3)), m.group(1), m.group(2), None


def colour_diff(a, b):
    if not a or not b or a == "-" or b == "-":
        return None
    ca = [int(a[i:i + 2], 16) for i in (1, 3, 5)]
    cb = [int(b[i:i + 2], 16) for i in (1, 3, 5)]
    return round(sum((x - y) ** 2 for x, y in zip(ca, cb)) ** 0.5)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("names", nargs="*")
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--dump", help="data-raw-dump.json to read (or write, if missing)")
    ap.add_argument("--out", default=os.path.join(REPO, "art-src", "score"))
    ap.add_argument("--only-dirs", default="", help="e.g. north,east")
    a = ap.parse_args()
    if a.dump and os.path.exists(a.dump):
        raw = json.load(open(a.dump, encoding="utf-8"))
    else:
        import icon_index
        raw = icon_index.dump(FACTORIO)
        if a.dump:
            json.dump(raw, open(a.dump, "w", encoding="utf-8"))
    os.makedirs(a.out, exist_ok=True)
    names = a.names or sorted(set(PICTURES) | set(BELT_ROWS))
    only = set(filter(None, a.only_dirs.split(",")))
    work = [(n, dn, args) for n in names for dn, args in jobs_for(n, raw) if not only or dn in only]
    results = {}
    with concurrent.futures.ThreadPoolExecutor(a.jobs) as pool:
        for name, dn, iou, sc, mc, err in pool.map(lambda w: run(w[0], w[1], w[2], a.out), work):
            results.setdefault(name, {})[dn] = {"iou": iou, "sprite": sc, "model": mc,
                                                "colour_diff": colour_diff(sc, mc), "error": err}
    path = os.path.join(a.out, "scores.json")
    old = json.load(open(path)) if os.path.exists(path) else {}
    for n, r in results.items():
        old.setdefault(n, {}).update(r)
    json.dump(old, open(path, "w"), indent=1, sort_keys=True)
    print("| model | N | E | S | W | min | colour (sprite / model, diff) |")
    print("|---|---|---|---|---|---|---|")
    for n in names:
        r = results.get(n, {})
        ious = [r[d]["iou"] for d in DIRS if d in r and r[d]["iou"] is not None]
        cells = ["%.2f" % r[d]["iou"] if d in r and r[d]["iou"] is not None else ("err" if d in r else "") for d in DIRS]
        c = r.get("north") or next(iter(r.values()), {})
        print("| %s | %s | %s | %s |" % (n, " | ".join(cells), "%.2f" % min(ious) if ious else "-",
                                         "%s / %s, %s" % (c.get("sprite"), c.get("model"), c.get("colour_diff")) if c else "-"))
        for d in DIRS:
            if d in r and r[d]["error"]:
                print("    %s %s: %s" % (n, d, r[d]["error"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
