#!/usr/bin/env python3
"""Measures each Nauvis tree's trunk and main limbs from Factorio's own trunk sprite and writes
tree_trunks.py, which trees.py builds the trunks from. Run with the venv's Python (numpy, scipy,
scikit-image, pillow):

    python tools/models/nature/fit_trunks.py [--factorio DIR] [--debug DIR]

For each tree (variation a, the trunk layer, positioned by the prototype's shift as
client/data/sprite_projection.json has it) the trunk's mask (alpha over half) is opened with a
small disk, which takes the thin twigs off and leaves the trunk, its forks and the main limbs. Its
skeleton, pruned of short spurs, is walked from the point nearest the tree's position: the longest
way up is the trunk, every other way a limb from where it leaves. Each way is sampled every
SAMPLE tiles as (x, up, r): x east and up the screen from the tree's position, r half the width
there (a round limb draws as wide as it is from any side). Below the crown the camera sees the
trunk's front, in the plane through the tree's position, so trees.py puts them there.

Also writes the bark's colours from the same pixels (the wide trunk only): `BARK` the dark (the
grooves), mid and light (the ridges) thirds by brightness, and `BASE` the colour of the lowest
fifth (moss and soil on tree-09's foot). Numbers only: nothing of the image is kept. --debug
draws the measured strands over the sprite into DIR (Factorio's art: keep it in art-src/).
"""

import argparse
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from skimage.morphology import disk, skeletonize

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
ENTRIES = os.path.join(REPO, "client", "data", "sprite_projection.json")
OUT = os.path.join(HERE, "tree_trunks.py")
TREES = ["tree-0%d" % i for i in (1, 2, 3, 4, 5, 7, 8, 9)]
DEAD = ["dead-dry-hairy-tree", "dead-grey-trunk", "dead-tree-desert", "dry-hairy-tree", "dry-tree"]
OPEN_PX = 4       # twigs thinner than about 2 * OPEN_PX pixels (HR) go
SPUR = 1.6        # a skeleton branch shorter than this many times the width it leaves from is a spur
MIN_LIMB = 0.35   # tiles: shorter limbs are left to the procedural twigs
SAMPLE = 0.18     # tiles between samples along a strand


def layer_of(entry, word):
    for layer in entry["cells"][0]:
        if word is None or word in layer["file"]:
            return layer
    return None


def load(factorio, layer):
    im = Image.open(os.path.join(factorio, "data", layer["file"])).convert("RGBA")
    w, h = layer["frame"]
    i = layer.get("index", 0)
    cols = layer.get("line") or im.width // w
    x, y = (i % cols) * w, (i // cols) * h
    return np.asarray(im.crop((x, y, x + w, y + h))).astype(np.float64) / 255.0


def neighbours(p, on):
    y, x = p
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if (dy or dx) and 0 <= y + dy < on.shape[0] and 0 <= x + dx < on.shape[1] and on[y + dy, x + dx]:
                yield (y + dy, x + dx)


def strands(thick, root_px):
    """Ways along the skeleton of `thick` from the skeleton point nearest root_px (x, y): the longest
    way up first, then each other way from where it leaves one already taken. Pixel paths."""
    skel = skeletonize(thick)
    ys, xs = np.nonzero(skel)
    if not len(ys):
        return [], skel
    d2 = (xs - root_px[0]) ** 2 + (ys - root_px[1]) ** 2
    root = (ys[d2.argmin()], xs[d2.argmin()])
    # Breadth-first from the root: every skeleton pixel's parent and distance.
    parent = {root: None}
    dist = {root: 0.0}
    queue = [root]
    for p in queue:
        for q in neighbours(p, skel):
            if q not in parent:
                parent[q] = p
                dist[q] = dist[p] + (1.414 if (q[0] != p[0] and q[1] != p[1]) else 1.0)
                queue.append(q)
    children = {}
    for q, p in parent.items():
        if p is not None:
            children.setdefault(p, []).append(q)
    ends = [p for p in parent if p not in children]

    def path(end):
        out = [end]
        while parent[out[-1]] is not None:
            out.append(parent[out[-1]])
        return out[::-1]
    # Trunk: the way reaching highest (the sprite's top is the tree's top); ties by length.
    best = min(ends, key=lambda e: (e[0], -dist[e]))
    taken = set(path(best))
    out = [path(best)]
    # Then the other ways, longest first, each from where it leaves those already taken.
    for end in sorted(ends, key=lambda e: -dist[e]):
        if end in taken:
            continue
        way = path(end)
        k = max(i for i, p in enumerate(way) if p in taken)
        way = way[k:]
        out.append(way)
        taken.update(way)
    return out, skel


def fit(factorio, entry, debug=None, name=""):
    layer = layer_of(entry, "trunk")
    rgba = load(factorio, layer)
    ppt = 32.0 / layer.get("scale", 0.5)
    h, w = rgba.shape[:2]
    sx, sy = (v / 32.0 for v in layer.get("shift", (0, 0)))
    # The tree's position in the picture: the frame's centre is the position plus the shift.
    pos_px = (w / 2 - sx * ppt, h / 2 - sy * ppt)
    mask = rgba[..., 3] > 0.5
    thick = ndimage.binary_opening(mask, structure=disk(OPEN_PX))
    lab, n = ndimage.label(thick)
    if n > 1:
        sizes = ndimage.sum(thick, lab, range(1, n + 1))
        thick = lab == (1 + int(np.argmax(sizes)))
    edt = ndimage.distance_transform_edt(thick)
    ways, skel = strands(thick, (pos_px[0], pos_px[1] - 0.3 * ppt))

    def to_tiles(p):
        y, x = p
        return (x + 0.5 - pos_px[0]) / ppt, (pos_px[1] - (y + 0.5)) / ppt
    out = []
    for i, way in enumerate(ways):
        length = sum(np.hypot(a[0] - b[0], a[1] - b[1]) for a, b in zip(way, way[1:])) / ppt
        r0 = edt[way[0]] / ppt
        if i and (length < MIN_LIMB or length < SPUR * r0):
            continue
        # Ways that don't climb are the skeleton running out into the root flare, which trees.py
        # builds as the trunk's foot.
        if i and to_tiles(way[-1])[1] < to_tiles(way[0])[1] + 0.25:
            continue
        step = max(1, int(SAMPLE * ppt))
        picks = list(range(0, len(way), step))
        if picks[-1] != len(way) - 1:
            picks.append(len(way) - 1)
        pts = []
        for k in picks:
            x, up = to_tiles(way[k])
            # The skeleton's end stops short of the tip by its radius: a strand ends in a point.
            r = edt[way[k]] / ppt
            pts.append((round(x, 3), round(up, 3), round(r, 3)))
        out.append(pts)
    # Bark colours from the wide trunk's pixels (no thin twigs, no soft edge).
    core = thick & (edt > 2)
    px = rgba[core & (rgba[..., 3] > 0.95)][:, :3]
    lum = px @ np.array([0.2126, 0.7152, 0.0722])
    thirds = np.array_split(px[np.argsort(lum)], 3)
    hexes = ["#%02x%02x%02x" % tuple(int(round(c * 255)) for c in t.mean(axis=0)) for t in thirds]
    ys = np.nonzero(core)[0]
    low = core & (np.arange(h)[:, None] > ys.min() + (ys.max() - ys.min()) * 0.8)
    base = rgba[low & (rgba[..., 3] > 0.95)][:, :3].mean(axis=0)
    base_hex = "#%02x%02x%02x" % tuple(int(round(c * 255)) for c in base)
    if debug:
        im = Image.fromarray((rgba * 255).astype(np.uint8)).convert("RGBA")
        bg = Image.new("RGBA", im.size, (40, 60, 30, 255))
        bg.alpha_composite(im)
        dr = ImageDraw.Draw(bg)
        cols = [(255, 0, 0), (0, 255, 255), (255, 255, 0), (255, 0, 255), (0, 255, 0), (255, 128, 0)]
        for i, pts in enumerate(out):
            for (x, up, r) in pts:
                cx, cy = pos_px[0] + x * ppt, pos_px[1] - up * ppt
                dr.ellipse((cx - r * ppt, cy - r * ppt, cx + r * ppt, cy + r * ppt), outline=cols[i % len(cols)])
        dr.ellipse((pos_px[0] - 3, pos_px[1] - 3, pos_px[0] + 3, pos_px[1] + 3), fill=(255, 255, 255))
        bg = bg.resize((bg.width * 2, bg.height * 2), Image.NEAREST)
        bg.save(os.path.join(debug, name + ".png"))
    return out, hexes, base_hex


def colours(factorio, entry):
    """Dead and dry trees: one picture, all wood. The dark, mid and light thirds of its wood."""
    layer = layer_of(entry, None)
    rgba = load(factorio, layer)
    mask = ndimage.binary_erosion(rgba[..., 3] > 0.95, iterations=1)
    px = rgba[mask][:, :3]
    lum = px @ np.array([0.2126, 0.7152, 0.0722])
    thirds = np.array_split(px[np.argsort(lum)], 3)
    return ["#%02x%02x%02x" % tuple(int(round(c * 255)) for c in t.mean(axis=0)) for t in thirds]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--factorio", default=os.environ.get(
        "FACTORIO", r"C:\Program Files (x86)\Steam\steamapps\common\Factorio"))
    ap.add_argument("--debug", help="draw the strands over the sprites into this folder (keep it in art-src/)")
    args = ap.parse_args()
    if args.debug:
        os.makedirs(args.debug, exist_ok=True)
    entries = json.load(open(ENTRIES, encoding="utf-8"))
    lines = ['"""Each Nauvis tree\'s trunk as Factorio\'s trunk sprite draws it (variation a), measured by',
             "fit_trunks.py: `STRANDS` are the trunk (first) and its main limbs, each a list of (x, up, r) in",
             "tiles, x east and up the screen from the tree's position, r the half width there; a limb starts",
             "on the strand it leaves. `BARK` the bark's dark, mid and light colours (sRGB), `BASE` the colour",
             "of its lowest fifth. Numbers only; nothing of the image is kept.\"\"\"", "", "STRANDS = {"]
    bark_lines, base_lines = ["BARK = {"], ["BASE = {"]
    for name in TREES:
        ways, hexes, base = fit(args.factorio, entries[name], args.debug, name)
        print("%-8s %d strands (%s), bark %s, base %s" % (name, len(ways), " ".join(str(len(s)) for s in ways),
                                                         " ".join(hexes), base))
        lines.append("    %r: [" % name)
        for s in ways:
            lines.append("        [%s]," % ", ".join("(%g, %g, %g)" % p for p in s))
        lines.append("    ],")
        bark_lines.append("    %r: (%s)," % (name, ", ".join(repr(x) for x in hexes)))
        base_lines.append("    %r: %r," % (name, base))
    for name in DEAD:
        hexes = colours(args.factorio, entries[name])
        print("%-20s wood %s" % (name, " ".join(hexes)))
        bark_lines.append("    %r: (%s)," % (name, ", ".join(repr(x) for x in hexes)))
    lines.append("}")
    bark_lines.append("}")
    base_lines.append("}")
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines + [""] + bark_lines + [""] + base_lines) + "\n")
    print("wrote", OUT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
