#!/usr/bin/env python3
"""Measures each Nauvis tree's crown from Factorio's own sprite and writes tree_crowns.py, which
trees.py builds the leaf-card crowns from. Run with the venv's Python (numpy, scipy, pillow):

    python tools/models/nature/fit_crowns.py [--factorio DIR]

For each tree (variation a, leaves frame 0, positioned by the prototype's shift as
client/data/sprite_projection.json has it) the leaves' mask (alpha over half) is covered by
disks, largest first: each disk is the largest circle that fits in what is still uncovered
(scipy's distance transform), shrunk a little so neighbours overlap, until what is left is
thinner than MIN_R. Factorio's camera is an orthographic view 48 degrees down (a point z up and y
north shows 0.669 z + 0.743 y up the sprite; 0.669^2 + 0.743^2 = 1), so a sphere of radius r
draws as a disk of radius r: each disk is a lump of leaves trees.py places in 3D, spread north
and south of the trunk without moving where it shows.

Also writes each leaf layer's mean colour in thirds by brightness (dark, mid, light), after the
prototype's mean tint, for the cards' shades. Numbers only: nothing of the image is kept.
"""

import argparse
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
ENTRIES = os.path.join(REPO, "client", "data", "sprite_projection.json")
OUT = os.path.join(HERE, "tree_crowns.py")
# tree-06, the weeping swamp tree, hangs its leaves in strands (trees.tree_06), not lumps.
TREES = ["tree-0%d" % i for i in (1, 2, 3, 4, 5, 7, 8, 9)]
MIN_R = 0.28  # tiles: thinner wisps are left to the cards' ragged edges
MAX_DISKS = 14


def leaves_layer(entry):
    for layer in entry["cells"][0]:
        if "leaves" in layer["file"]:
            return layer
    return None


def load(factorio, layer):
    im = Image.open(os.path.join(factorio, "data", layer["file"])).convert("RGBA")
    w, h = layer["frame"]
    i = layer.get("index", 0)
    cols = layer.get("line") or im.width // w  # `line`: frames per row of the sheet
    x, y = (i % cols) * w, (i // cols) * h
    return np.asarray(im.crop((x, y, x + w, y + h))).astype(np.float64) / 255.0


def fit(factorio, entry):
    layer = leaves_layer(entry)
    rgba = load(factorio, layer)
    ppt = 32.0 / layer.get("scale", 0.5)
    h, w = rgba.shape[:2]
    sx, sy = (v / 32.0 for v in layer.get("shift", (0, 0)))
    mask = rgba[..., 3] > 0.5
    # Small holes between leaves aren't gaps in the crown.
    mask = ndimage.binary_closing(mask, iterations=3)
    left = mask.copy()
    disks = []
    yy, xx = np.mgrid[0:h, 0:w]
    while len(disks) < MAX_DISKS:
        dist = ndimage.distance_transform_edt(left)
        r = dist.max()
        if r / ppt < MIN_R:
            break
        py, px = np.unravel_index(dist.argmax(), dist.shape)
        disks.append((px, py, r))
        # Shrunk, so the next disks overlap this one instead of leaving seams.
        left &= (xx - px) ** 2 + (yy - py) ** 2 > (r * 0.75) ** 2
    out = []
    for px, py, r in disks:
        x = sx + (px + 0.5 - w / 2) / ppt
        up = -(sy + (py + 0.5 - h / 2) / ppt)
        out.append((round(x, 3), round(up, 3), round(r / ppt, 3)))
    covered = np.zeros_like(mask)
    for px, py, r in disks:
        covered |= (xx - px) ** 2 + (yy - py) ** 2 <= r ** 2
    iou = (covered & mask).sum() / max(1, (covered | mask).sum())
    # Leaf shades: the sprite's opaque leaf pixels, tinted as the game tints them (the mean of the
    # prototype's colours), split into thirds by brightness.
    tint = np.array(layer.get("tint", (1.0, 1.0, 1.0))[:3])
    px = rgba[rgba[..., 3] > 0.9][:, :3] * tint
    lum = px @ np.array([0.2126, 0.7152, 0.0722])
    order = np.argsort(lum)
    thirds = np.array_split(px[order], 3)
    shades = ["#%02x%02x%02x" % tuple(int(round(min(1.0, c) * 255)) for c in t.mean(axis=0)) for t in thirds]
    return out, iou, shades


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--factorio", default=os.environ.get(
        "FACTORIO", r"C:\Program Files (x86)\Steam\steamapps\common\Factorio"))
    args = ap.parse_args()
    entries = json.load(open(ENTRIES, encoding="utf-8"))
    lines = ['"""Each Nauvis tree\'s crown as Factorio\'s sprite draws it (variation a), measured by',
             "fit_crowns.py: `DISKS` are (x, up, r) in tiles, x east and up the screen from the tree's",
             "position, each a lump of leaves of radius r; `SHADES` the leaves' dark, mid and light colour",
             '(sRGB, after the prototype\'s mean tint). Numbers only; nothing of the image is kept."""',
             "", "DISKS = {"]
    shades_lines = ["SHADES = {"]
    for name in TREES:
        disks, iou, shades = fit(args.factorio, entries[name])
        print("%-8s %2d disks, cover %.2f, shades %s" % (name, len(disks), iou, " ".join(shades)))
        lines.append("    %r: [%s]," % (name, ", ".join("(%g, %g, %g)" % d for d in disks)))
        shades_lines.append("    %r: (%s)," % (name, ", ".join(repr(s) for s in shades)))
    lines.append("}")
    shades_lines.append("}")
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines + [""] + shades_lines) + "\n")
    print("wrote", OUT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
