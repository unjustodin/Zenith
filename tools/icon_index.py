#!/usr/bin/env python3
"""Writes client/data/icons.json: which picture (or layered pictures) is each item's, fluid's,
virtual signal's, recipe's, technology's and entity's icon, read from Factorio's own prototype data.

    python tools/icon_index.py [--factorio DIR] [--check]

Icon files aren't named after their prototypes ("stone-wall" is wall.png, barrels are three
tinted layers), so guessing a file from the name misses some. This runs `factorio --dump-data`
(a few seconds, no game window, a throwaway write-data folder; the built-in mods Space Age,
Quality and Elevated rails are on by default) and keeps only file names and numbers: the client
loads the pictures from the player's own install at runtime (item_icons.gd). --check also
reports any icon file missing from the install, and writes nothing.

Technologies' bonus icons are layered too (the picture with a badge in its corner), and some are
defined outside the technology.lua files the client could read.

Entities are listed only when no item has their name (a straight rail is placed by "rail", rocks
and ruins have no item at all).

Format: {"item"|"fluid"|"virtual-signal"|"recipe"|"technology"|"entity": {name: [layer, ...]}} where a layer is
[file, icon_size, tint or null, scale or null, shift or null]; file is relative to Factorio's
data folder ("base/graphics/icons/wall.png"), tint [r, g, b, a] in 0..1, shift [x, y]. Layers are
composed as Factorio does (item_icons.gd). Recipes are listed only when their icon isn't the item
or fluid of the same name.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
OUT = os.path.join(REPO, "client", "data", "icons.json")
FACTORIO = r"C:\Program Files (x86)\Steam\steamapps\common\Factorio"
# Every prototype type that is an item (data.raw has one table per type).
ITEM_TYPES = ["item", "ammo", "armor", "blueprint", "blueprint-book", "capsule", "copy-paste-tool",
              "deconstruction-item", "gun", "item-with-entity-data", "item-with-inventory", "item-with-label",
              "item-with-tags", "module", "rail-planner", "repair-tool", "selection-tool", "space-platform-starter-pack",
              "spidertron-remote", "tool", "upgrade-item"]


def dump(factorio):
    exe = os.path.join(factorio, "bin", "x64", "factorio.exe")
    if not os.path.exists(exe):
        exe = os.path.join(factorio, "bin", "x64", "factorio")
    with tempfile.TemporaryDirectory() as tmp:
        config = os.path.join(tmp, "config.ini")
        with open(config, "w") as f:
            f.write("[path]\nread-data=%s\nwrite-data=%s\n" % (os.path.join(factorio, "data"), tmp))
        subprocess.run([exe, "--config", config, "--dump-data"], check=True, stdout=subprocess.DEVNULL)
        with open(os.path.join(tmp, "script-output", "data-raw-dump.json"), encoding="utf-8") as f:
            return json.load(f)


def file_of(path):
    m = re.match(r"__([a-z0-9_-]+)__/(.+)", path)
    return "%s/%s" % (m.group(1), m.group(2)) if m else path


def tint_of(t):
    if t is None:
        return None
    if isinstance(t, list):
        t = dict(zip("rgba", t))
    c = [float(t.get(k, 1.0 if k == "a" else 0.0)) for k in "rgba"]
    if max(c[:3]) > 1.0:  # 0..255 colours
        c = [v / 255.0 for v in c[:3]] + [c[3] if c[3] <= 1.0 else c[3] / 255.0]
    return [round(v, 4) for v in c]


def shift_of(s):
    if s is None:
        return None
    if isinstance(s, dict):
        return [s.get("x", 0), s.get("y", 0)]
    return list(s)


def layers(proto):
    if proto.get("icons"):
        out = []
        for l in proto["icons"]:
            out.append([file_of(l["icon"]), int(l.get("icon_size", 64)), tint_of(l.get("tint")), l.get("scale"),
                        shift_of(l.get("shift"))])
        return out
    if proto.get("icon"):
        return [[file_of(proto["icon"]), int(proto.get("icon_size", 64)), None, None, None]]
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--factorio", default=os.environ.get("FACTORIO", FACTORIO))
    parser.add_argument("--check", action="store_true", help="report missing icons, write nothing")
    args = parser.parse_args()
    raw = dump(args.factorio)
    index = {"item": {}, "fluid": {}, "virtual-signal": {}, "recipe": {}, "technology": {}, "entity": {}}
    missing = []
    for t in ITEM_TYPES:
        for name, proto in raw.get(t, {}).items():
            index["item"][name] = layers(proto)
    for kind in ("fluid", "virtual-signal", "technology"):
        for name, proto in raw.get(kind, {}).items():
            index[kind][name] = layers(proto)
    # Every prototype type with a collision box is an entity type.
    for t, protos in raw.items():
        if not isinstance(protos, dict) or not any(isinstance(p, dict) and "collision_box" in p for p in protos.values()):
            continue
        for name, proto in protos.items():
            if name not in index["item"] and isinstance(proto, dict) and (proto.get("icon") or proto.get("icons")):
                index["entity"][name] = layers(proto)
    for name, proto in raw.get("recipe", {}).items():
        own = layers(proto)
        if own is None:
            # Without its own icon a recipe shows its main product's (the only result's).
            results = proto.get("results") or []
            main = proto.get("main_product") or (results[0].get("name") if len(results) == 1 else None)
            if main and main != name:
                own = index["item"].get(main) or index["fluid"].get(main)
        if own is not None and own != index["item"].get(name) and own != index["fluid"].get(name):
            index["recipe"][name] = own
    for kind, entries in index.items():
        for name, ls in list(entries.items()):
            if not ls:
                missing.append("%s %s: no icon in its prototype" % (kind, name))
                del entries[name]
                continue
            for l in ls:
                if not os.path.exists(os.path.join(args.factorio, "data", l[0])):
                    missing.append("%s %s: %s not in the install" % (kind, name, l[0]))
    counts = ", ".join("%s: %d" % (k, len(v)) for k, v in index.items())
    layered = sum(1 for v in index.values() for ls in v.values() if len(ls) > 1)
    print("%s (%d layered)" % (counts, layered))
    for m in missing:
        print("missing:", m)
    if args.check:
        return 1 if missing else 0
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("{\n")
        kinds = list(index)
        for i, kind in enumerate(kinds):
            f.write('"%s": {\n' % kind)
            names = sorted(index[kind])
            for j, name in enumerate(names):
                f.write("  %s: %s%s\n" % (json.dumps(name), json.dumps(index[kind][name], separators=(",", ":")),
                                          "," if j < len(names) - 1 else ""))
            f.write("}%s\n" % ("," if i < len(kinds) - 1 else ""))
        f.write("}\n")
    print("wrote", os.path.relpath(OUT, REPO))
    return 0


if __name__ == "__main__":
    sys.exit(main())
