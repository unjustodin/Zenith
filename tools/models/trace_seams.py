"""Traces the dark plate seams on the crash site's yellow plating from Factorio's sprites, for
crash_site.py to cut as grooves (writes tools/models/crash_seams.py, numbers only).

    python tools/models/trace_seams.py [--debug DIR]

A seam is a thin line darker than the plates either side (a black top-hat on the luminance, at
least REL darker than its surroundings) lying among the yellow paint. The lines are thinned to a
pixel, traced into polylines and simplified, then written in screen tiles from the entity's
position (x right, up), as crash_site.py's OUTLINES are. `--debug` saves each sprite with its
traced lines (Factorio's art: keep it out of the repo, e.g. in art-src/).
"""

import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi
from skimage.measure import approximate_polygon
from skimage.morphology import disk, remove_small_objects, skeletonize

HERE = os.path.dirname(os.path.abspath(__file__))
FACTORIO = os.environ.get("FACTORIO", r"C:\Program Files (x86)\Steam\steamapps\common\Factorio")
G = os.path.join(FACTORIO, "data", "base", "graphics", "entity", "crash-site-spaceship")
PPT = 64          # high-resolution sprites: 64 pixels a tile
REL = 0.25        # how much darker than its surroundings a seam pixel is
MIN_LEN = 10      # pixels: shorter lines are rivets, scratches and grime
TOL = 2.5         # pixels: polyline simplification (the seams are straight runs with corners)

# (sprite, shift in pixels / 32) from crash-site.lua, as gallery.py and sprite_projection.py.
SPRITES = {"spaceship": ("spaceship.png", (-13, 34))}
for _n, _s in (("big-1", (-7, -8)), ("big-2", (-13, -7)), ("medium-1", (-14, -4)), ("medium-2", (-15, 8)),
               ("medium-3", (-30, 4)), ("small-1", (-9, -1)), ("small-2", (-8, 16)), ("small-3", (5, -1)),
               ("small-4", (1, -3)), ("small-5", (-6, -6)), ("small-6", (10, 9))):
    SPRITES[_n] = ("spaceship-wreck-%s.png" % _n, _s)


def seam_mask(rgba, bridge=False):
    a = rgba.astype(np.float64) / 255.0
    rgb, alpha = a[..., :3], a[..., 3]
    lum = rgb @ np.array([0.299, 0.587, 0.114])
    mx, mn = rgb.max(-1), rgb.min(-1)
    sat = (mx - mn) / np.maximum(mx, 1e-6)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    yellow = (alpha > 0.9) & (sat > 0.3) & (mx > 0.16) & (r > b * 1.5) & (g > b * 1.3) & (g > r * 0.6) & (g < r * 1.15)
    closed = ndi.grey_closing(lum, footprint=disk(3))   # dark features narrower than about 5 px
    hat = closed - lum
    near = ndi.uniform_filter(yellow.astype(float), 11) > 0.3
    m = (hat / np.maximum(closed, 0.08) > REL) & (hat > 0.05) & near & (alpha > 0.9)
    # Rivet heads catch the light and break the ship's long seams into dashes: bridge gaps of a few
    # pixels (on the small wrecks that joins seams to the dark edges round them instead).
    if bridge:
        m = ndi.binary_closing(m, structure=disk(2)) & (alpha > 0.9)
    m = remove_small_objects(m, max_size=12)
    return remove_small_objects(skeletonize(m), max_size=MIN_LEN, connectivity=2)


def trace(sk):
    """Polylines (row, col) along a one-pixel skeleton, split at its junctions."""
    pts = set(zip(*np.nonzero(sk)))

    def nb(p):
        y, x = p
        return [(y + dy, x + dx) for dy in (-1, 0, 1) for dx in (-1, 0, 1) if (dy or dx) and (y + dy, x + dx) in pts]
    nodes = {p for p in pts if len(nb(p)) != 2}
    used, lines = set(), []

    def walk(a, b):
        path, prev, cur = [a, b], a, b
        while cur not in nodes:
            nxt = [q for q in nb(cur) if q != prev and (min(cur, q), max(cur, q)) not in used]
            if not nxt:
                break
            used.add((min(cur, nxt[0]), max(cur, nxt[0])))
            prev, cur = cur, nxt[0]
            path.append(cur)
        return path
    for start in sorted(nodes) + sorted(pts):   # nodes first, then loops without any
        for q in nb(start):
            e = (min(start, q), max(start, q))
            if e not in used:
                used.add(e)
                lines.append(walk(start, q))
    return lines


def seams(name, debug=None):
    f, (shx, shy) = SPRITES[name]
    img = Image.open(os.path.join(G, f)).convert("RGBA")
    w, h = img.size
    sx0, sy0 = shx / 32, shy / 32

    def scr(px, py):
        return (round((px - w / 2) / PPT + sx0, 3), round(-((py - h / 2) / PPT + sy0), 3))
    out = []
    for line in trace(seam_mask(np.asarray(img), bridge=name == "spaceship")):
        if len(line) < MIN_LEN:
            continue
        poly = approximate_polygon(np.array([(x + 0.5, y + 0.5) for y, x in line], float), TOL)
        out.append([scr(x, y) for x, y in poly])
    if debug:
        canvas = Image.new("RGBA", img.size, (0, 0, 0, 255))
        canvas.paste(img, (0, 0), img)
        d = ImageDraw.Draw(canvas)
        for line in out:
            d.line([(w / 2 + (x - sx0) * PPT, h / 2 - (u + sy0) * PPT) for x, u in line], fill=(0, 255, 255, 255))
        canvas.save(os.path.join(debug, "seams-%s.png" % name))
    return out


def main(argv):
    debug = argv[argv.index("--debug") + 1] if "--debug" in argv else None
    if debug:
        os.makedirs(debug, exist_ok=True)
    lines = ['"""The dark plate seams on the crash site\'s sprites, traced by trace_seams.py (screen tiles',
             'from the entity\'s position, x right, up; one polyline a list). Generated: don\'t edit."""', "",
             "SEAMS = {"]
    for name in SPRITES:
        found = seams(name, debug)
        print("%-10s %4d seams" % (name, len(found)))
        lines.append("    %r: [" % name)
        for poly in found:
            lines.append("        [%s]," % ", ".join("(%g, %g)" % q for q in poly))
        lines.append("    ],")
    lines.append("}")
    with open(os.path.join(HERE, "crash_seams.py"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main(sys.argv[1:])
