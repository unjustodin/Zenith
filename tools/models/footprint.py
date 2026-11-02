"""Every model's ground extent against its entity's boxes in Factorio's prototypes.

    python tools/models/footprint.py [names...] [--dump data-raw-dump.json] [--all] [--json out.json]

A model's east-west and north-south extent (its .glb's bounds, client/assets/models) is compared
with the north-facing entity's collision box and selection box from `factorio --dump-data` (read
from --dump, or made with icon_index.dump from the install when that file is missing). A model is
listed when an axis is more than 10% smaller than the smaller box or 10% bigger than the larger:
`small` reads as shrunk on its tiles, `big` spills onto its neighbours. Space Age's entities come
first (names defined under the install's space-age/prototypes). Without --all only listed models
are printed.

Some models are meant to be thinner than their box (poles, pipes, lamps, the thin parts of a
tileset) or to overhang it (turret barrels, trees' crowns, nozzles): judge against the sprite, not
the box. Variant models (`-east`, `-input`, `-curve-left`, belt and rail pieces) are matched to
their prototype; models drawn unturned for east and west (FACING_MODELS) swap the box's axes.
Plain Python: numpy and trimesh, no Blender.
"""

import argparse
import glob
import json
import os
import re
import sys

import trimesh

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
MODELS = os.path.join(REPO, "client", "assets", "models")
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, "tools"))

from specs import SPECS  # noqa: E402

TOLERANCE = 0.10
# Suffixes of variant models, longest first; "-east"/"-west" models face that way unturned.
SUFFIXES = ["-curve-left", "-curve-right", "-input", "-output", "-north", "-east", "-south", "-west",
            "-rich", "-sparse", "-ne", "-corpse-1", "-corpse-2", "-corpse-3"]
TURNED = ("-east", "-west")


def factorio_data():
    for base in (r"C:\Program Files (x86)\Steam\steamapps\common\Factorio\data",
                 os.path.expanduser("~/.steam/steam/steamapps/common/Factorio/data"),
                 r"C:\Program Files\Factorio\data"):
        if os.path.isdir(base):
            return base
    return None


def space_age_names():
    data = factorio_data()
    names = set()
    if data is None:
        return names
    paths = glob.glob(os.path.join(data, "space-age", "prototypes", "entity", "**", "*.lua"), recursive=True)
    for mod in ("recycler", "elevated-rails", "quality"):  # 2.1 split these out of Space Age
        paths += glob.glob(os.path.join(data, mod, "**", "*.lua"), recursive=True)
    for path in paths:
        with open(path, encoding="utf-8", errors="replace") as f:
            names.update(re.findall(r'\bname\s*=\s*"([a-z0-9-]+)"', f.read()))
    return names


def boxes(raw):
    """Prototype name -> (type, collision box, selection box), for everything with a box."""
    out = {}
    for ptype, protos in raw.items():
        if not isinstance(protos, dict):
            continue
        for name, p in protos.items():
            if not isinstance(p, dict) or "selection_box" not in p and "collision_box" not in p:
                continue
            if name not in out or ptype not in ("item", "recipe"):
                out[name] = (ptype, p.get("collision_box"), p.get("selection_box"))
    return out


def box_size(box):
    if not box:
        return None
    if isinstance(box, dict):
        (x0, y0), (x1, y1) = (box["left_top"]["x"], box["left_top"]["y"]), (box["right_bottom"]["x"], box["right_bottom"]["y"])
    else:
        (x0, y0), (x1, y1) = box[0], box[1]  # a third element is an orientation
    return abs(x1 - x0), abs(y1 - y0)


def prototype_of(model, known):
    turned = model.endswith(TURNED)
    spec = SPECS.get(model, {})
    if spec.get("base") in known:
        return spec["base"], turned
    if model in known:
        return model, False
    for suffix in SUFFIXES:
        if model.endswith(suffix) and model[:-len(suffix)] in known:
            return model[:-len(suffix)], suffix in TURNED
    return None, False


def extent(path):
    """(east-west, north-south, height) of a model: glTF x east, y up, z south."""
    scene = trimesh.load(path, force="scene")
    lo, hi = scene.bounds
    return hi[0] - lo[0], hi[2] - lo[2], hi[1] - lo[1]


def verdict(size, coll, sel):
    """'small', 'big' or '' per axis: outside [0.9 x the smaller box, 1.1 x the larger]."""
    out = []
    for k in range(2):
        sides = [b[k] for b in (coll, sel) if b and b[k] > 0]
        if not sides:
            out.append("")
            continue
        if size[k] < min(sides) * (1 - TOLERANCE):
            out.append("small")
        elif size[k] > max(sides) * (1 + TOLERANCE):
            out.append("big")
        else:
            out.append("")
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("names", nargs="*")
    ap.add_argument("--dump", default=os.path.join(REPO, "art-src", "data-raw-dump.json"))
    ap.add_argument("--all", action="store_true", help="print every model, not only those outside the tolerance")
    ap.add_argument("--json", help="write every row here")
    a = ap.parse_args(argv)
    if os.path.exists(a.dump):
        with open(a.dump, encoding="utf-8") as f:
            raw = json.load(f)
    else:
        import icon_index
        raw = icon_index.dump(os.path.dirname(factorio_data()))
        with open(a.dump, "w", encoding="utf-8") as f:
            json.dump(raw, f)
    known = boxes(raw)
    space = space_age_names()
    names = a.names or sorted(os.path.basename(p)[:-4] for p in glob.glob(os.path.join(MODELS, "*.glb")))
    rows = []
    for model in names:
        proto, turned = prototype_of(model, known)
        if proto is None:
            continue
        ptype, coll, sel = known[proto]
        coll, sel = box_size(coll), box_size(sel)
        if turned:
            coll = coll and (coll[1], coll[0])
            sel = sel and (sel[1], sel[0])
        w, d, h = extent(os.path.join(MODELS, model + ".glb"))
        v = verdict((w, d), coll, sel)
        rows.append({"model": model, "prototype": proto, "type": ptype, "space_age": proto in space,
                     "size": [round(w, 2), round(d, 2)], "height": round(h, 2),
                     "collision": coll and [round(c, 2) for c in coll], "selection": sel and [round(c, 2) for c in sel],
                     "ew": v[0], "ns": v[1]})
    rows.sort(key=lambda r: (not r["space_age"], r["model"]))
    if a.json:
        with open(a.json, "w", encoding="utf-8") as f:
            json.dump(rows, f, indent=1)
    shown = [r for r in rows if a.all or r["ew"] or r["ns"]]
    print("| model | type | Space Age | model E-W x N-S | collision | selection | E-W | N-S |")
    print("|---|---|---|---|---|---|---|---|")
    for r in shown:
        fmt = lambda b: "%.2f x %.2f" % tuple(b) if b else "-"
        print("| %s | %s | %s | %s | %s | %s | %s | %s |" % (r["model"], r["type"], "yes" if r["space_age"] else "",
              fmt(r["size"]), fmt(r["collision"]), fmt(r["selection"]), r["ew"], r["ns"]))
    print("\n%d models matched to a prototype, %d outside +-%d%% (%d of them Space Age)" % (
        len(rows), sum(1 for r in rows if r["ew"] or r["ns"]), TOLERANCE * 100,
        sum(1 for r in rows if (r["ew"] or r["ns"]) and r["space_age"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
