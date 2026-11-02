#!/usr/bin/env python3
"""Scores the Space Age models against their Factorio sprites: compare.py's silhouette overlap
(intersection over union of the sprite's and the render's outlines) for every direction the
sprite has, and both average colours.

    python tools/models/space_score.py [names...] [--jobs=6] [--out=DIR]

Writes DIR/<name>-<dir>.png (the compare.py panels) and DIR/scores.json, and prints a table.
DIR defaults to the git-ignored art-src/compare/space/: the panels show Factorio's art, so they
are never committed. Sprite numbers come from gallery.py (and space_sprites.py through it).
"""

import json
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import gallery  # noqa: E402
import space_sprites  # noqa: E402

DIRS = ("N", "E", "S", "W")
SA = "data/space-age/graphics/entity/"

# The families this script covers, in a fixed order.
FAMILIES = {
    "V01 Vulcanus machines": ["foundry", "big-mining-drill"],
    "V03 Volcanic rocks": ["big-volcanic-rock", "big-volcanic-rock-hot", "huge-volcanic-rock", "huge-volcanic-rock-hot"],
    "V04 Chimneys": ["vulcanus-chimney", "vulcanus-chimney-faded", "vulcanus-chimney-cold", "vulcanus-chimney-short",
                     "vulcanus-chimney-truncated"],
    "V05 Ashland lichen": ["ashland-lichen-tree", "ashland-lichen-tree-flaming"],
    "V06 Sulfuric acid geyser": ["sulfuric-acid-geyser"],
    "F01 Fulgora machines": ["electromagnetic-plant", "recycler"],
    "F02 Lightning": ["lightning-rod", "lightning-collector"],
    "F03 Tesla turret": ["tesla-turret"],
    "F04 Mech armour look": ["character-mech-armor"],
    "F05 Ruins": ["fulgoran-ruin-tiny", "fulgoran-ruin-small", "fulgoran-ruin-medium", "fulgoran-ruin-stonehenge",
                  "fulgoran-ruin-big", "fulgoran-ruin-huge", "fulgoran-ruin-colossal", "fulgoran-ruin-vault",
                  "fulgoran-ruin-attractor", "fulgora-sunk-ruin-big", "fulgora-sunk-ruin-medium-tall"],
    "F06 Fulgurite": ["fulgurite", "fulgurite-small"],
    "F07 Scrap": ["scrap"],
    "G01 Gleba machines": ["biochamber", "agricultural-tower", "heating-tower", "biolab", "captive-biter-spawner"],
    "G02 Rocket turret": ["rocket-turret"],
    "G03 Capture robot": ["capture-robot"],
    "G04 Stack inserter": ["stack-inserter", "inserter-arm-stack-upper", "inserter-arm-stack-hand-open",
                           "inserter-arm-stack-hand-closed"],
    "G05 Gleba plants": sorted(gallery.GLEBA_PLANTS) + ["tree-plant"],
    "Q01 Aquilo machines": ["cryogenic-plant", "fusion-reactor", "fusion-generator"],
    "Q03 Icebergs": ["lithium-iceberg-big", "lithium-iceberg-huge"],
    "Q04 Brine and vents": ["lithium-brine", "fluorine-vent"],
    "S01 Space platform": ["space-platform-hub", "cargo-bay", "thruster", "asteroid-collector"],
    "S02 Crusher": ["crusher", "crusher-east"],
    "S03 Asteroids": ["%s-%s-asteroid" % (s, k) for k in ("metallic", "carbonic", "oxide", "promethium")
                      for s in ("small", "medium", "big", "huge")],
}

# Directions besides north for sprites that gallery.py shows only one way: (direction, args).
EXTRA = {
    "fusion-generator": [(d, [SA + "fusion-generator/%s/fusion-generator-%s.png" % (n, n), "--frame=%dx%d" % (w, h),
                              "--line=3", "--shift=%g,%g" % sh, "--rot=%d" % (90 * i),
                              "--stretch=1.346"])
                         for i, (d, n, w, h, sh) in enumerate((("N", "north", 244, 376, (-2, -2)),
                                                               ("E", "east", 370, 230, (0, -1)),
                                                               ("S", "south", 252, 360, (0, 6)),
                                                               ("W", "west", 370, 240, (-0.5, -4))))],
    # The platform sheet has the four directions side by side, north first.
    "stack-inserter": [(d, [SA + "stack-inserter/stack-inserter-platform.png", "--frame=105x79", "--line=4",
                            "--index=%d" % i, "--shift=1.5,6.5", "--rot=%d" % (90 * i)])
                       for i, d in enumerate(DIRS)],
    # Mech armour: mech-idle's first frame for each direction (8 directions of 22 frames, north
    # first, clockwise: east is the third), with its mask.
    "character-mech-armor": [(d, [SA + "mech-armor/mech-idle.png", "--frame=142x176", "--line=11", "--index=%d" % (44 * i),
                                  "--shift=1,-25.5", "--anchor=0", "--rot=%d" % (90 * i),
                                  "--layer=" + os.path.join(gallery.FACTORIO, SA, "mech-armor/mech-idle-mask.png")
                                  + "|134x150|%d|11|0.5,-32" % (44 * i)])
                             for i, d in enumerate(DIRS)],
}


# Parts left out of the comparison: the picture shows the machine idle, when the thruster's flame
# and exhaust plume (anim_glow_*) are dark and no strike's sparks (anim_lit_strike) are drawn on a
# lightning rod or collector.
HIDE = {"thruster": "anim_glow", "lightning-rod": "anim_lit_strike", "lightning-collector": "anim_lit_strike"}


def runs(name):
    """[(direction, compare.py argument list)] for every direction the sprite has."""
    out = _runs(name)
    if name in HIDE:
        out = [(d, list(args) + ["--hide=" + HIDE[name]]) for d, args in out]
    return out


def _runs(name):
    if name in EXTRA:
        return EXTRA[name]
    entry = space_sprites.ENTRIES.get(name)
    if entry and entry.get("mode") == "direction":
        return [(DIRS[k], space_sprites.compare_args(name, gallery.FACTORIO, k)) for k in range(4)]
    if name in gallery.BUILDINGS:
        return [("N", gallery.BUILDINGS[name])]
    return []


def score(name, direction, args, out_dir):
    out = os.path.join(out_dir, "%s-%s.png" % (name, direction))
    sheet, *rest = args
    sprite = sheet if os.path.isabs(sheet) else os.path.join(gallery.FACTORIO, sheet)
    cmd = [gallery.BLENDER, "--background", "--factory-startup", "--python", "tools/models/compare.py", "--", out, name,
           "--sprite=" + sprite, *rest]
    run = subprocess.run(cmd, cwd=gallery.REPO, capture_output=True, text=True)
    m = re.search(r"sprite (\S+)\s+model (\S+)\s+silhouette overlap ([\d.]+)", run.stdout)
    if not m:
        tail = (run.stderr or run.stdout).strip().splitlines()[-2:]
        return {"error": " / ".join(tail)}
    return {"iou": float(m.group(3)), "sprite": m.group(1), "model": m.group(2)}


def colour_gap(a, b):
    if not (a.startswith("#") and b.startswith("#")):
        return None
    ca = [int(a[i:i + 2], 16) for i in (1, 3, 5)]
    cb = [int(b[i:i + 2], 16) for i in (1, 3, 5)]
    return round(sum(abs(x - y) for x, y in zip(ca, cb)) / 3)


def main(argv):
    jobs, out_dir, names = 6, os.path.join(gallery.REPO, "art-src", "compare", "space"), []
    for a in argv:
        if a.startswith("--jobs="):
            jobs = int(a[7:])
        elif a.startswith("--out="):
            out_dir = os.path.abspath(a[6:])
        else:
            names.append(a)
    os.makedirs(out_dir, exist_ok=True)
    family_of = {n: f for f, ns in FAMILIES.items() for n in ns}
    names = names or list(family_of)
    tasks = [(n, d, args) for n in names for d, args in runs(n)]
    missing = [n for n in names if not runs(n)]
    with ThreadPoolExecutor(jobs) as pool:
        results = list(pool.map(lambda t: (t[0], t[1], score(t[0], t[1], t[2], out_dir)), tasks))
    path = os.path.join(out_dir, "scores.json")
    table = {}
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            table = json.load(f)
    for n, d, r in results:
        table.setdefault(n, {})[d] = r
    with open(path, "w", encoding="utf-8") as f:
        json.dump(table, f, indent=1, sort_keys=True)
    for n in names:
        if n in missing:
            print("%-34s no sprite comparison" % n)
            continue
        cells = []
        for d in DIRS:
            r = table.get(n, {}).get(d)
            if r is None:
                continue
            if "error" in r:
                cells.append("%s err" % d)
            else:
                cells.append("%s %.2f (colour off %s)" % (d, r["iou"], colour_gap(r["sprite"], r["model"])))
        print("%-34s %s" % (n, "  ".join(cells)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
