"""Small 3D models for items on belts, on the ground and in inserter hands.

    python tools/models/items.py [names...]              # write client/assets/models/items/<item>.glb
    python tools/models/items.py --list                  # the items with a recipe here
    python tools/models/items.py [names...] --preview out.png   # icon | model sheet (not for the repo)
    godot --headless --path client --import              # then import, as after any .glb change

Thousands of items can be in view on a busy bus, so every model is a few dozen triangles
(item_kit.py) with its colours in the vertices, and the client draws one MultiMesh per item type
(client/scripts/world/item_cards.gd). Shapes follow Factorio's item icons: a plate is a bevelled
slab, a gear a toothed ring, a science pack its flask, and a building's item its entity in
miniature, as the icons draw them. Colours are picked once from the icon in the player's Factorio
install (median colour of the right part of the icon), never at runtime, and only the numbers
end up in the .glb. Items without a recipe keep their icon card in the client.

Sizes: about a quarter of a tile across (a belt lane is half a tile, items sit a quarter tile
apart), resting on y = 0, centred, facing north. The client gives each item a slight random yaw.
"""

import argparse
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

from item_kit import (Icon, bevel_box, box, circle, cylinder_x, cylinder_z, extrude, find_factorio,  # noqa: E402
                      hexcol, merge, mix, prism, ring, rock, scale, shade_by_height, write_glb)

OUT_DIR = os.path.join(REPO, "client", "assets", "models", "items")
MAX_TRIS = 220

_factorio = None
_icons = {}


def icon(name):
    if name not in _icons:
        _icons[name] = Icon(_factorio, name)
    return _icons[name]


def has_icon(name):
    try:
        icon(name)
        return True
    except FileNotFoundError:
        return False


def picture(name, n=1):
    """Belts draw an ore's variation pictures (iron-ore-1 ...), not its icon: sample those."""
    return icon("%s-%d" % (name, n)) if has_icon("%s-%d" % (name, n)) else icon(name)


# Hue bands (degrees) for picking painted parts out of an icon.
RED, ORANGE, YELLOW, GREEN, CYAN, BLUE, PURPLE, PINK = (
    (345, 15), (15, 40), (40, 65), (75, 160), (160, 200), (200, 255), (255, 300), (300, 345))
GOLD = (30, 60)


# --- families -----------------------------------------------------------------------------------

def ore(name, seed=0, size=0.14, lumps=3):
    """A few chunky lumps, as an ore's belt picture shows them."""
    ic = picture(name)
    col = ic.pick(lum=(0.15, 0.75))
    spots = [(-0.06, -0.035), (0.06, -0.04), (0.0, 0.06), (0.07, 0.07)][:lumps]
    parts = []
    for i, (x, z) in enumerate(spots):
        s = size * (1.0 - 0.12 * i)
        parts.append(rock(s * 1.1, s * 0.65, s, col, seed * 7 + i + 1, points=14, round_=True).move(x, 0, z))
    return merge(*parts)


def lump(name, sx=0.2, sy=0.13, sz=0.18, seed=1, points=12, **pick):
    ic = icon(name)
    return rock(sx, sy, sz, ic.pick(**(pick or {"lum": (0.15, 0.85)})), seed, points=points, round_=True)


def crystals(name, n=5, seed=3, height=0.14, **pick):
    """Pointed crystals (sulfur, bioflux, tungsten ore)."""
    import random
    rnd = random.Random(seed)
    col = picture(name).pick(**(pick or {"sat": (0.3, 1.0), "lum": (0.2, 0.9)}))
    parts = []
    for i in range(n):
        h = height * rnd.uniform(0.6, 1.0)
        c = prism(0.035, h, 5, scale(col, rnd.uniform(0.85, 1.1)), r_top=0.0, smooth=False, start=rnd.random())
        c = prism(0.035, h * 0.6, 5, scale(col, rnd.uniform(0.85, 1.1)), smooth=False, start=rnd.random()) + \
            prism(0.035, h * 0.4, 5, scale(col, 1.15), r_top=0.0, smooth=False).move(0, h * 0.6, 0)
        c = c.rot_z(rnd.uniform(-25, 25)).rot_x(rnd.uniform(-25, 25))
        a = 2 * math.pi * i / n
        r = 0.0 if i == 0 else 0.06
        parts.append(c.move(r * math.cos(a), 0.01, r * math.sin(a)))
    m = merge(*parts)
    lo, _ = m.bounds()
    return m.move(0, -lo[1], 0)


def plate(name, sx=0.27, sy=0.035, sz=0.21, bevel=0.012, **pick):
    ic = icon(name)
    col = ic.pick(**(pick or {"lum": (0.1, 0.6)}))
    top = ic.pick(lum=(0.3, 0.8))
    return bevel_box(sx, sy, sz, bevel, col, top=top)


def disc(name, r=0.12, h=0.035, n=12):
    ic = icon(name)
    return prism(r, h, n, ic.pick(lum=(0.1, 0.7)), cap=ic.pick(lum=(0.4, 0.9)))


def beam(name, length=0.28, w=0.13, h=0.09, channel=False):
    """Steel plate (an I-beam) and tungsten plate (a channel), lying along x."""
    ic = icon(name)
    col = ic.pick(lum=(0.3, 0.9))
    dark = ic.pick(lum=(0.0, 0.35))
    t = 0.018
    if channel:
        return merge(box(length, t, w, col, x=0),
                     box(length, h, t, col, z=-w / 2 + t / 2),
                     box(length, h, t, col, z=w / 2 - t / 2),
                     box(length * 0.98, t * 0.4, w - 2 * t, dark, y=t))
    return merge(box(length, t, w, col), box(length, h - 2 * t, t, dark, y=t),
                 box(length, t, w, col, y=h - t))


def gear(name, r=0.13, h=0.045, teeth=8):
    ic = icon(name)
    col = ic.pick(lum=(0.2, 0.8))
    top = ic.pick(lum=(0.55, 0.95))
    outer = []
    for i in range(teeth * 3):
        a = 2 * math.pi * (i - 0.5) / (teeth * 3)
        rr = r if (i % 3) in (1, 2) else r * 0.76
        outer.append((rr * math.cos(a), rr * math.sin(a)))
    inner = circle(r * 0.38, teeth * 3, start=-math.pi / (teeth * 3))
    return ring(outer, inner, h, col, top=top)


def circuit(name, board_hue):
    """A board in its colour with three gold traces, as the circuit icons draw them."""
    ic = icon(name)
    board = ic.pick(hue=board_hue, sat=(0.45, 1.0), lum=(0.2, 0.8))
    gold = ic.pick(hue=GOLD, sat=(0.3, 1.0), val=(0.55, 1.0))
    edge = scale(board, 0.6)
    m = bevel_box(0.27, 0.03, 0.22, 0.008, edge, top=board)
    for i, z in enumerate((-0.06, 0.0, 0.06)):
        w = 0.15 - 0.02 * i
        m = m + box(w, 0.008, 0.018, gold, x=-0.03, y=0.03, z=z)
        m = m + prism(0.018, 0.01, 6, gold, smooth=False).move(-0.03 + w / 2 + 0.01, 0.03, z)
    return m


def processor(name):
    """Quantum processor: a dark chip on a purple frame with gold pins."""
    ic = icon(name)
    frame = ic.pick(hue=PURPLE, sat=(0.3, 1.0))
    gold = ic.pick(hue=GOLD, sat=(0.3, 1.0), val=(0.5, 1.0))
    chip = ic.pick(lum=(0.0, 0.2))
    return merge(box(0.26, 0.02, 0.26, gold), bevel_box(0.22, 0.035, 0.22, 0.01, frame),
                 bevel_box(0.12, 0.05, 0.12, 0.01, chip))


def coil(name, turns=3, h=0.02):
    """Copper cable: a flat spiral, drawn as rings."""
    ic = icon(name)
    col = ic.pick(sat=(0.3, 1.0), lum=(0.2, 0.9))
    top = ic.pick(sat=(0.2, 1.0), lum=(0.6, 1.0))
    m = None
    for i in range(turns):
        ro = 0.13 - i * 0.04
        m = merge(m, ring(circle(ro, 9), circle(ro - 0.022, 9), h, col, top=top))
    return m


def stick(name, length=0.3, r=0.022):
    ic = icon(name)
    return cylinder_x(r, length, 6, ic.pick(lum=(0.2, 0.85)), cap=ic.pick(lum=(0.5, 1.0))).rot_y(30)


def brick(name, sx=0.24, sy=0.09, sz=0.15, bevel=0.012, **pick):
    ic = icon(name)
    return bevel_box(sx, sy, sz, bevel, ic.pick(**(pick or {"lum": (0.1, 0.7)})), top=ic.pick(lum=(0.4, 0.95)))


def cube(name, s=0.18, bevel=0.012, **pick):
    return brick(name, s, s * 0.9, s, bevel, **pick)


def logs(name):
    ic = icon(name)
    bark = ic.pick(hue=(10, 45), lum=(0.15, 0.6))
    end = ic.pick(hue=(20, 50), val=(0.6, 1.0))
    r = 0.045
    l1 = cylinder_x(r, 0.26, 6, bark, cap=end, smooth=False)
    return merge(l1.move(0, 0, -r), l1.move(0.01, 0, r), l1.rot_y(8).move(0, r * 1.6, 0)).rot_y(60)


def battery(name):
    ic = icon(name)
    body = ic.pick(sat=(0.0, 0.25), lum=(0.15, 0.7))
    red = ic.pick(hue=RED, sat=(0.5, 1.0))
    blue = ic.pick(hue=BLUE, sat=(0.4, 1.0))
    return merge(bevel_box(0.24, 0.13, 0.15, 0.02, body, top=scale(body, 1.15)),
                 prism(0.025, 0.02, 8, red, smooth=False).move(-0.05, 0.13, 0),
                 prism(0.025, 0.02, 8, blue, smooth=False).move(0.05, 0.13, 0))


def supercapacitor(name):
    ic = icon(name)
    body = ic.pick(hue=BLUE, sat=(0.2, 1.0))
    top = ic.pick(region=(0.2, 0.0, 0.8, 0.35), lum=(0.2, 0.8))
    return merge(prism(0.1, 0.16, 12, body, cap=top),
                 prism(0.025, 0.02, 6, ic.pick(hue=ORANGE, sat=(0.4, 1.0)), smooth=False).move(-0.04, 0.16, 0),
                 prism(0.025, 0.02, 6, ic.pick(hue=PINK, sat=(0.3, 1.0)), smooth=False).move(0.04, 0.16, 0))


def superconductor(name):
    ic = icon(name)
    blue = ic.pick(hue=BLUE, sat=(0.3, 1.0))
    copper = ic.pick(hue=ORANGE, sat=(0.3, 1.0))
    tube = cylinder_x(0.035, 0.24, 8, blue, cap=copper)
    return merge(tube.move(0, 0, -0.04), tube.move(0, 0, 0.04), tube.move(0, 0.055, 0).rot_y(4))


def engine(name):
    ic = icon(name)
    body = ic.pick(lum=(0.2, 0.7))
    light = ic.pick(lum=(0.6, 0.95))
    m = bevel_box(0.2, 0.1, 0.16, 0.02, body, top=light)
    for i in range(3):
        m = m + box(0.03, 0.04, 0.17, light, x=-0.06 + 0.06 * i, y=0.1)
    return m + cylinder_x(0.035, 0.08, 8, light).move(0.13, 0.03, 0.03)


def electric_engine(name):
    ic = icon(name)
    body = ic.pick(sat=(0.0, 0.3), lum=(0.2, 0.7))
    red = ic.pick(hue=RED, sat=(0.5, 1.0))
    m = cylinder_x(0.085, 0.2, 10, body, cap=scale(body, 1.2))
    m = m + cylinder_x(0.09, 0.02, 10, red).move(-0.07, -0.005, 0) + cylinder_x(0.09, 0.02, 10, red).move(0.07, -0.005, 0)
    return m + cylinder_x(0.018, 0.05, 6, scale(body, 1.3)).move(0.12, 0.065, 0)


def flask(name, round_bottom=False):
    """A science pack: a glass flask of coloured liquid with a white neck and cap."""
    ic = icon(name)
    liquid = ic.pick(region=(0.1, 0.4, 0.9, 1.0), sat=(0.35, 1.0), lum=(0.15, 0.85))
    if liquid == ic.pick(region=(0.1, 0.4, 0.9, 1.0), lum=(0.15, 0.85)):
        liquid = ic.pick(region=(0.1, 0.45, 0.9, 1.0), lum=(0.2, 0.8))  # grey and white packs
    glass = ic.pick(region=(0.3, 0.0, 0.7, 0.35), lum=(0.5, 1.0))
    cap = ic.pick(region=(0.3, 0.0, 0.7, 0.2), lum=(0.3, 0.9))
    if round_bottom:
        body = prism(0.06, 0.035, 10, liquid, r_top=0.1) + prism(0.1, 0.085, 10, liquid, r_top=0.04).move(0, 0.035, 0)
        y = 0.12
    else:
        body = prism(0.105, 0.025, 10, liquid, r_top=0.1) + prism(0.1, 0.1, 10, liquid, r_top=0.035).move(0, 0.025, 0)
        y = 0.125
    return merge(body, prism(0.035, 0.05, 8, glass).move(0, y, 0), prism(0.045, 0.02, 8, cap).move(0, y + 0.05, 0))


def magazine(name, stripe_hue):
    """Firearm magazines: a curved black clip with a coloured edge."""
    ic = icon(name)
    black = ic.pick(lum=(0.0, 0.4))
    stripe = ic.pick(hue=stripe_hue, sat=(0.4, 1.0), val=(0.4, 1.0))
    m = None
    for i, a in enumerate((-20, 0, 20)):
        seg = merge(box(0.09, 0.05, 0.12, black), box(0.09, 0.05, 0.025, stripe, z=0.07))
        seg = seg.move(0, 0, -0.18).rot_y(a).move(0, 0, 0.18)
        m = merge(m, seg)
    return m.move(0, 0, -0.02)


def shells(name, case_hue=RED):
    """Shotgun shells: two cartridges with brass bases."""
    ic = icon(name)
    case = ic.pick(hue=case_hue, sat=(0.4, 1.0))
    brass = ic.pick(hue=GOLD, sat=(0.3, 1.0), val=(0.5, 1.0))
    one = merge(cylinder_x(0.045, 0.14, 8, case, cap=scale(case, 0.8)), cylinder_x(0.048, 0.04, 8, brass).move(-0.07, -0.003, 0))
    return merge(one.move(0, 0, -0.05), one.rot_y(180).move(0.02, 0, 0.05))


def bullet(name, tip=None):
    """Cannon shells, rockets: a cylinder with a pointed nose, lying."""
    ic = icon(name)
    body = ic.pick(lum=(0.2, 0.8))
    nose = ic.pick(hue=tip, sat=(0.3, 1.0)) if tip else ic.pick(lum=(0.5, 1.0))
    m = prism(0.045, 0.17, 8, body) + prism(0.045, 0.08, 8, nose, r_top=0.0).move(0, 0.17, 0)
    return m.move(0, -0.125, 0).rot_z(-90).move(0, 0.045, 0)


def module(name):
    """Modules: a coloured case with three lamps."""
    ic = icon(name)
    case = ic.pick(sat=(0.3, 1.0), lum=(0.1, 0.6), region=(0.0, 0.4, 1.0, 1.0))
    lamp = ic.pick(region=(0.2, 0.0, 0.9, 0.4), sat=(0.3, 1.0), val=(0.5, 1.0))
    m = bevel_box(0.24, 0.05, 0.2, 0.012, scale(case, 0.75), top=case)
    for i in range(3):
        m = m + prism(0.025, 0.025, 6, lamp, smooth=False).move(-0.06 + 0.06 * i, 0.05, -0.05)
    return m


def fuel_cell(name):
    ic = icon(name)
    metal = ic.pick(sat=(0.0, 0.25), lum=(0.3, 0.9))
    glow = ic.pick(sat=(0.4, 1.0), val=(0.4, 1.0))
    return merge(prism(0.1, 0.03, 10, metal), prism(0.085, 0.1, 10, glow).move(0, 0.03, 0),
                 prism(0.1, 0.03, 10, metal).move(0, 0.13, 0))


def canister(name, glow_hue=None):
    """Rocket fuel, nuclear fuel: a metal canister with a lit window, lying."""
    ic = icon(name)
    metal = ic.pick(sat=(0.0, 0.3), lum=(0.2, 0.8))
    glow = ic.pick(hue=glow_hue, sat=(0.4, 1.0), val=(0.4, 1.0)) if glow_hue else ic.pick(sat=(0.4, 1.0), val=(0.4, 1.0))
    return merge(cylinder_x(0.06, 0.24, 8, metal), cylinder_x(0.062, 0.1, 8, glow).move(0.02, -0.002, 0))


def hexes(name):
    """Low density structure: three copper hexagon frames."""
    ic = icon(name)
    col = ic.pick(hue=ORANGE, sat=(0.2, 1.0))
    one = ring(circle(0.07, 6), circle(0.05, 6), 0.03, col, top=scale(col, 1.15))
    return merge(one.move(-0.06, 0, -0.035), one.move(0.06, 0, -0.035), one.move(0, 0, 0.07))


def frame(name):
    """Flying robot frame: a ring with a rotor."""
    ic = icon(name)
    ringc = ic.pick(hue=BLUE, sat=(0.2, 1.0))
    metal = ic.pick(sat=(0.0, 0.2), lum=(0.2, 0.8))
    return merge(ring(circle(0.12, 10), circle(0.095, 10), 0.05, ringc),
                 prism(0.02, 0.05, 6, metal), box(0.2, 0.012, 0.035, metal, y=0.035).rot_y(30))


def fiber(name):
    ic = icon(name)
    return cylinder_x(0.07, 0.24, 10, ic.pick(lum=(0.2, 0.8)), cap=ic.pick(lum=(0.0, 0.3))).rot_y(-25)


def scrap(name):
    ic = picture(name)
    rust = ic.pick(hue=(0, 35), sat=(0.3, 1.0))
    blue = ic.pick(hue=BLUE, sat=(0.3, 1.0))
    grey = ic.pick(sat=(0.0, 0.2), lum=(0.2, 0.7))
    return merge(box(0.16, 0.06, 0.12, rust).rot_y(15).move(-0.03, 0, 0.03),
                 box(0.09, 0.08, 0.08, blue).rot_y(-10).move(0.06, 0, -0.04),
                 cylinder_x(0.025, 0.12, 6, grey).rot_y(60).move(0.02, 0.05, 0.02))


def egg(name, r=0.1, **pick):
    ic = picture(name)
    col = ic.pick(**(pick or {"lum": (0.2, 0.85)}))
    return merge(prism(r * 0.7, r * 0.5, 10, col, r_top=r), prism(r, r * 0.9, 10, col, r_top=r * 0.4).move(0, r * 0.5, 0))


def fruit(name, r=0.1, n=10):
    ic = picture(name)
    col = ic.pick(sat=(0.3, 1.0), lum=(0.15, 0.85))
    return merge(prism(r * 0.6, r * 0.45, n, scale(col, 0.85), r_top=r), prism(r, r * 0.95, n, col, r_top=r * 0.3).move(0, r * 0.45, 0))


def mound(name, r=0.12, h=0.08, **pick):
    """Powders and mash: a low heap."""
    ic = picture(name)
    col = ic.pick(**(pick or {"lum": (0.2, 0.9)}))
    return prism(r, h * 0.55, 9, scale(col, 0.9), r_top=r * 0.7, smooth=False) + \
        prism(r * 0.7, h * 0.45, 9, col, r_top=r * 0.15, smooth=False).move(0, h * 0.55, 0)


def capsule(name, **pick):
    ic = icon(name)
    col = ic.pick(**(pick or {"sat": (0.2, 1.0), "lum": (0.2, 0.85)}))
    metal = ic.pick(sat=(0.0, 0.2), lum=(0.3, 0.9))
    return merge(rock(0.17, 0.14, 0.15, col, 5, points=14, round_=True), prism(0.025, 0.03, 6, metal).move(0, 0.13, 0))


def pack(name):
    """Repair pack: a spanner and a screwdriver crossed."""
    ic = icon(name)
    metal = ic.pick(sat=(0.0, 0.2), lum=(0.4, 1.0))
    handle = ic.pick(hue=YELLOW, sat=(0.4, 1.0))
    return merge(box(0.26, 0.02, 0.035, metal).rot_y(35),
                 box(0.11, 0.03, 0.04, handle, x=0.06).rot_y(-35), box(0.13, 0.015, 0.015, metal, x=-0.06).rot_y(-35))


# --- buildings in miniature --------------------------------------------------------------------

def belt(name, tier_hue):
    """A belt piece: dark rubber with two painted chevrons and steel side rails."""
    ic = icon(name)
    paint = ic.pick(hue=tier_hue, sat=(0.45, 1.0), val=(0.45, 1.0))
    rubber = ic.pick(sat=(0.0, 0.35), lum=(0.05, 0.4))
    rail = ic.pick(sat=(0.0, 0.3), lum=(0.45, 0.9))
    m = merge(box(0.22, 0.04, 0.26, rubber), box(0.025, 0.055, 0.26, rail, x=-0.12), box(0.025, 0.055, 0.26, rail, x=0.12))
    for z in (-0.07, 0.05):
        m = m + chevron(paint, 0.15, 0.035).move(0, 0.04, z)
    return m


def chevron(col, w, t):
    """A ">" pointing north (the way the belt runs), w wide, bars t thick, at y = 0."""
    arm = w / 2 / math.cos(math.radians(35))
    return merge(box(arm, 0.006, t, col).rot_y(35).move(-w / 4, 0, 0.0),
                 box(arm, 0.006, t, col).rot_y(-35).move(w / 4, 0, 0.0))


def underground(name, tier_hue):
    ic = icon(name)
    paint = ic.pick(hue=tier_hue, sat=(0.45, 1.0), val=(0.45, 1.0))
    metal = ic.pick(sat=(0.0, 0.3), lum=(0.2, 0.8))
    m = merge(box(0.26, 0.04, 0.22, scale(metal, 0.7)), bevel_box(0.24, 0.13, 0.12, 0.03, metal, z=-0.05))
    return m + chevron(paint, 0.12, 0.03).move(0, 0.04, 0.04)


def splitter(name, tier_hue):
    ic = icon(name)
    paint = ic.pick(hue=tier_hue, sat=(0.45, 1.0), val=(0.45, 1.0))
    metal = ic.pick(sat=(0.0, 0.3), lum=(0.2, 0.8))
    return merge(box(0.3, 0.04, 0.2, scale(metal, 0.6)), bevel_box(0.3, 0.09, 0.07, 0.015, metal),
                 chevron(paint, 0.09, 0.025).move(-0.08, 0.04, 0.04), chevron(paint, 0.09, 0.025).move(0.08, 0.04, 0.04))


def inserter(name, hue=None):
    """Inserters: a round base, a two-part arm in the inserter's colour, a grabber."""
    ic = icon(name)
    paint = ic.pick(hue=hue, sat=(0.35, 1.0), val=(0.3, 1.0)) if hue else ic.pick(lum=(0.2, 0.7))
    base = ic.pick(sat=(0.0, 0.3), lum=(0.1, 0.6))
    m = prism(0.08, 0.035, 8, base, cap=scale(base, 1.2))
    m = m + box(0.03, 0.14, 0.03, paint).rot_z(-30).move(0, 0.03, 0)
    m = m + box(0.14, 0.025, 0.025, paint, x=0.07).move(0.07, 0.13, 0)
    return m + box(0.03, 0.03, 0.06, base, x=0.21, y=0.11)


def chest(name, band_hue=None):
    """Chests: a box with a lid; logistic chests have a coloured band."""
    ic = icon(name)
    body = ic.pick(lum=(0.15, 0.75))
    lid = ic.pick(region=(0.0, 0.0, 1.0, 0.4), lum=(0.3, 0.9))
    m = merge(bevel_box(0.22, 0.13, 0.18, 0.01, body, top=lid), box(0.23, 0.02, 0.19, scale(body, 0.75), y=0.09))
    if band_hue:
        m = m + box(0.225, 0.03, 0.185, ic.pick(hue=band_hue, sat=(0.35, 1.0)), y=0.03)
    return m


def machine(name, w=0.26, h=0.15, d=0.26, top_region=(0.0, 0.0, 1.0, 0.45), hue=None, inset=None):
    """A building's item as its entity in miniature: a box in its body colour, its top as the
    icon shows it, and an optional painted part."""
    ic = icon(name)
    body = ic.pick(lum=(0.15, 0.7))
    top = ic.pick(region=top_region, lum=(0.35, 0.95))
    m = bevel_box(w, h, d, 0.02, body, top=top)
    if hue:
        m = m + box(w * 0.6, 0.01, d * 0.6, ic.pick(hue=hue, sat=(0.35, 1.0), val=(0.3, 1.0)), y=h)
    if inset:
        m = m + bevel_box(w * 0.55, inset, d * 0.55, 0.01, scale(top, 1.1), y=h)
    return m


def furnace(name):
    ic = icon(name)
    stone = ic.pick(lum=(0.25, 0.85), sat=(0.0, 0.45))
    fire = ic.pick(hue=(15, 50), sat=(0.6, 1.0), val=(0.7, 1.0))
    m = prism(0.15, 0.17, 4, stone, r_top=0.07, smooth=False, start=math.pi / 4)
    return m + box(0.06, 0.04, 0.01, fire, y=0.015, z=0.095)


def pole(name, wood=False):
    ic = icon(name)
    post = ic.pick(hue=ORANGE, sat=(0.3, 1.0)) if wood else ic.pick(lum=(0.2, 0.7))
    metal = ic.pick(sat=(0.0, 0.25), lum=(0.4, 0.95))
    w = 0.03 if wood else 0.05
    m = prism(w * 0.9, 0.24, 4, post, r_top=w * 0.6, smooth=False, start=math.pi / 4)
    return m + box(0.16, 0.02, 0.025, metal if wood else post, y=0.22) + box(0.06, 0.02, 0.06, scale(metal, 0.7))


def pipe(name, to_ground=False):
    ic = icon(name)
    col = ic.pick(lum=(0.2, 0.8))
    rim = ic.pick(lum=(0.5, 0.95))
    length = 0.18 if to_ground else 0.26
    m = cylinder_x(0.055, length, 8, col, cap=scale(col, 0.6))
    m = m + cylinder_x(0.068, 0.025, 8, rim).move(-length / 2 + 0.012, -0.013, 0) + cylinder_x(0.068, 0.025, 8, rim).move(length / 2 - 0.012, -0.013, 0)
    if to_ground:
        m = m.move(0.03, 0, 0) + box(0.06, 0.12, 0.13, scale(col, 0.85), x=-0.08)
    return m


def rail(name):
    ic = icon(name)
    steel = ic.pick(sat=(0.0, 0.2), lum=(0.5, 1.0))
    wood = ic.pick(hue=(20, 60), sat=(0.3, 1.0))
    m = None
    for x in (-0.09, 0.0, 0.09):
        m = merge(m, box(0.04, 0.02, 0.26, wood, x=x))
    return m + box(0.28, 0.025, 0.025, steel, y=0.02, z=-0.07) + box(0.28, 0.025, 0.025, steel, y=0.02, z=0.07)


def panel(name):
    """Solar panel: a flat dark-blue panel on a short stand."""
    ic = icon(name)
    cells = ic.pick(hue=BLUE, sat=(0.15, 1.0), lum=(0.0, 0.7))
    frame_col = ic.pick(sat=(0.0, 0.2), lum=(0.4, 0.95))
    return merge(box(0.28, 0.03, 0.28, frame_col), box(0.26, 0.012, 0.26, cells, y=0.03))


def accumulator(name):
    ic = icon(name)
    body = ic.pick(lum=(0.15, 0.7))
    cap = ic.pick(lum=(0.5, 1.0))
    m = box(0.26, 0.03, 0.26, scale(body, 0.7))
    for x in (-0.065, 0.065):
        for z in (-0.065, 0.065):
            m = m + prism(0.05, 0.15, 8, body, cap=cap).move(x, 0.03, z)
    return m


def lamp(name):
    ic = icon(name)
    metal = ic.pick(lum=(0.1, 0.6))
    glass = ic.pick(lum=(0.7, 1.0))
    return merge(prism(0.07, 0.06, 8, metal), prism(0.055, 0.06, 8, glass, r_top=0.03).move(0, 0.06, 0))


def turret(name):
    ic = icon(name)
    body = ic.pick(lum=(0.2, 0.75))
    m = merge(box(0.24, 0.05, 0.24, scale(body, 0.8)), prism(0.08, 0.08, 8, body).move(0, 0.05, 0))
    return m + cylinder_z(0.02, 0.14, 6, scale(body, 0.6)).move(0, 0.08, -0.08)


def wall(name):
    ic = icon(name)
    return bevel_box(0.24, 0.16, 0.14, 0.02, ic.pick(lum=(0.2, 0.7)), top=ic.pick(lum=(0.5, 0.95)))


def tile(name):
    ic = icon(name)
    return bevel_box(0.25, 0.04, 0.25, 0.008, ic.pick(lum=(0.1, 0.7)), top=ic.pick(lum=(0.35, 0.9)))


def hazard(name):
    ic = icon(name)
    m = bevel_box(0.25, 0.04, 0.25, 0.008, ic.pick(sat=(0.0, 0.3), lum=(0.0, 0.5)))
    stripe = ic.pick(hue=(30, 60), sat=(0.5, 1.0))
    for k in (-0.05, 0.05):
        m = m + box(0.2 - abs(k) * 1.4, 0.004, 0.04, stripe, y=0.04).rot_y(45).move(k, 0, k)
    return m


def robot(name):
    ic = icon(name)
    body = ic.pick(lum=(0.2, 0.8))
    paint = ic.pick(sat=(0.3, 1.0), val=(0.3, 1.0))
    return merge(rock(0.16, 0.08, 0.2, body, 9, points=12, round_=True), box(0.18, 0.015, 0.04, paint, y=0.05))


def combinator(name):
    ic = icon(name)
    body = ic.pick(lum=(0.15, 0.7))
    light = ic.pick(sat=(0.3, 1.0), val=(0.5, 1.0))
    return merge(bevel_box(0.2, 0.1, 0.24, 0.015, body, top=scale(body, 1.25)),
                 box(0.06, 0.008, 0.06, light, y=0.1, z=-0.04))


def wagon(name):
    ic = icon(name)
    body = ic.pick(lum=(0.2, 0.75))
    return merge(box(0.12, 0.03, 0.27, scale(body, 0.5)), bevel_box(0.14, 0.09, 0.27, 0.015, body, y=0.03))


# --- the catalogue ------------------------------------------------------------------------------

TIERS = {"": YELLOW, "fast-": RED, "express-": BLUE, "turbo-": GREEN}

RECIPES = {
    # Nauvis raw resources and intermediates
    "iron-ore": lambda: ore("iron-ore", 1),
    "copper-ore": lambda: ore("copper-ore", 2),
    "coal": lambda: ore("coal", 3),
    "stone": lambda: ore("stone", 4),
    "uranium-ore": lambda: ore("uranium-ore", 5),
    "iron-plate": lambda: plate("iron-plate"),
    "copper-plate": lambda: plate("copper-plate"),
    "steel-plate": lambda: beam("steel-plate", channel=True).rot_y(25),
    "iron-gear-wheel": lambda: gear("iron-gear-wheel"),
    "iron-stick": lambda: stick("iron-stick"),
    "copper-cable": lambda: coil("copper-cable"),
    "electronic-circuit": lambda: circuit("electronic-circuit", GREEN),
    "advanced-circuit": lambda: circuit("advanced-circuit", RED),
    "processing-unit": lambda: circuit("processing-unit", BLUE),
    "stone-brick": lambda: brick("stone-brick"),
    "wood": lambda: logs("wood"),
    "plastic-bar": lambda: brick("plastic-bar", 0.25, 0.07, 0.13, 0.025, lum=(0.3, 0.9)),
    "sulfur": lambda: crystals("sulfur"),
    "battery": lambda: battery("battery"),
    "engine-unit": lambda: engine("engine-unit"),
    "electric-engine-unit": lambda: electric_engine("electric-engine-unit"),
    "solid-fuel": lambda: cube("solid-fuel"),
    "rocket-fuel": lambda: canister("rocket-fuel", ORANGE),
    "nuclear-fuel": lambda: canister("nuclear-fuel", GREEN),
    "low-density-structure": lambda: hexes("low-density-structure"),
    "flying-robot-frame": lambda: frame("flying-robot-frame"),
    "uranium-235": lambda: lump("uranium-235", sat=(0.3, 1.0)),
    "uranium-238": lambda: lump("uranium-238", seed=2, sat=(0.3, 1.0)),
    "uranium-fuel-cell": lambda: fuel_cell("uranium-fuel-cell"),
    "depleted-uranium-fuel-cell": lambda: fuel_cell("depleted-uranium-fuel-cell"),
    "explosives": lambda: cube("explosives", 0.17),
    "landfill": lambda: lump("landfill", 0.24, 0.12, 0.22, seed=4, points=16),
    "concrete": lambda: tile("concrete"),
    "refined-concrete": lambda: tile("refined-concrete"),
    "hazard-concrete": lambda: hazard("hazard-concrete"),
    "refined-hazard-concrete": lambda: hazard("refined-hazard-concrete"),
    "repair-pack": lambda: pack("repair-pack"),
    "satellite": lambda: machine("satellite", 0.2, 0.14, 0.2),
    # Science packs
    "automation-science-pack": lambda: flask("automation-science-pack"),
    "logistic-science-pack": lambda: flask("logistic-science-pack"),
    "military-science-pack": lambda: flask("military-science-pack"),
    "chemical-science-pack": lambda: flask("chemical-science-pack"),
    "production-science-pack": lambda: flask("production-science-pack"),
    "utility-science-pack": lambda: flask("utility-science-pack"),
    "space-science-pack": lambda: flask("space-science-pack"),
    "metallurgic-science-pack": lambda: flask("metallurgic-science-pack", True),
    "electromagnetic-science-pack": lambda: flask("electromagnetic-science-pack", True),
    "agricultural-science-pack": lambda: flask("agricultural-science-pack", True),
    "cryogenic-science-pack": lambda: flask("cryogenic-science-pack", True),
    "promethium-science-pack": lambda: flask("promethium-science-pack", True),
    # Ammunition and capsules
    "firearm-magazine": lambda: magazine("firearm-magazine", YELLOW),
    "piercing-rounds-magazine": lambda: magazine("piercing-rounds-magazine", RED),
    "uranium-rounds-magazine": lambda: magazine("uranium-rounds-magazine", GREEN),
    "shotgun-shell": lambda: shells("shotgun-shell"),
    "piercing-shotgun-shell": lambda: shells("piercing-shotgun-shell", GREEN),
    "cannon-shell": lambda: bullet("cannon-shell"),
    "explosive-cannon-shell": lambda: bullet("explosive-cannon-shell", RED),
    "uranium-cannon-shell": lambda: bullet("uranium-cannon-shell", GREEN),
    "explosive-uranium-cannon-shell": lambda: bullet("explosive-uranium-cannon-shell", GREEN),
    "artillery-shell": lambda: bullet("artillery-shell"),
    "rocket": lambda: bullet("rocket", YELLOW),
    "explosive-rocket": lambda: bullet("explosive-rocket", RED),
    "grenade": lambda: capsule("grenade", lum=(0.2, 0.8)),
    "cluster-grenade": lambda: capsule("cluster-grenade", lum=(0.2, 0.8)),
    "poison-capsule": lambda: capsule("poison-capsule"),
    "slowdown-capsule": lambda: capsule("slowdown-capsule"),
    "defender-capsule": lambda: capsule("defender-capsule"),
    "distractor-capsule": lambda: capsule("distractor-capsule"),
    "destroyer-capsule": lambda: capsule("destroyer-capsule"),
    "flamethrower-ammo": lambda: canister("flamethrower-ammo", RED),
    # Modules
    **{"%s-module%s" % (k, t): (lambda k=k, t=t: module("%s-module%s" % (k, t)))
       for k in ("speed", "efficiency", "productivity") for t in ("", "-2", "-3")},
    # Logistics
    **{"%stransport-belt" % t: (lambda t=t, h=h: belt("%stransport-belt" % t, h)) for t, h in TIERS.items()},
    **{"%sunderground-belt" % t: (lambda t=t, h=h: underground("%sunderground-belt" % t, h)) for t, h in TIERS.items()},
    **{"%ssplitter" % t: (lambda t=t, h=h: splitter("%ssplitter" % t, h)) for t, h in TIERS.items()},
    "burner-inserter": lambda: inserter("burner-inserter"),
    "inserter": lambda: inserter("inserter", YELLOW),
    "long-handed-inserter": lambda: inserter("long-handed-inserter", RED),
    "fast-inserter": lambda: inserter("fast-inserter", BLUE),
    "bulk-inserter": lambda: inserter("bulk-inserter", GREEN),
    "stack-inserter": lambda: inserter("stack-inserter"),
    "wooden-chest": lambda: chest("wooden-chest"),
    "iron-chest": lambda: chest("iron-chest"),
    "steel-chest": lambda: chest("steel-chest"),
    "active-provider-chest": lambda: chest("active-provider-chest", PURPLE),
    "passive-provider-chest": lambda: chest("passive-provider-chest", RED),
    "storage-chest": lambda: chest("storage-chest", YELLOW),
    "buffer-chest": lambda: chest("buffer-chest", GREEN),
    "requester-chest": lambda: chest("requester-chest", BLUE),
    "pipe": lambda: pipe("pipe"),
    "pipe-to-ground": lambda: pipe("pipe-to-ground", True),
    "rail": lambda: rail("rail"),
    "small-electric-pole": lambda: pole("small-electric-pole", wood=True),
    "medium-electric-pole": lambda: pole("medium-electric-pole"),
    "big-electric-pole": lambda: pole("big-electric-pole"),
    "substation": lambda: machine("substation", 0.2, 0.18, 0.2),
    "small-lamp": lambda: lamp("small-lamp"),
    "stone-wall": lambda: wall("wall") if not has_icon("stone-wall") else wall("stone-wall"),
    "gate": lambda: machine("gate", 0.26, 0.12, 0.12, hue=YELLOW),
    "constant-combinator": lambda: combinator("constant-combinator"),
    "arithmetic-combinator": lambda: combinator("arithmetic-combinator"),
    "decider-combinator": lambda: combinator("decider-combinator"),
    "selector-combinator": lambda: combinator("selector-combinator"),
    "logistic-robot": lambda: robot("logistic-robot"),
    "construction-robot": lambda: robot("construction-robot"),
    # Production and power
    "stone-furnace": lambda: furnace("stone-furnace"),
    "steel-furnace": lambda: machine("steel-furnace", 0.24, 0.17, 0.24),
    "electric-furnace": lambda: machine("electric-furnace", 0.26, 0.17, 0.26),
    "burner-mining-drill": lambda: machine("burner-mining-drill", 0.24, 0.16, 0.24),
    "electric-mining-drill": lambda: machine("electric-mining-drill", 0.27, 0.14, 0.27, inset=0.06),
    "assembling-machine-1": lambda: machine("assembling-machine-1", 0.27, 0.15, 0.27, inset=0.03),
    "assembling-machine-2": lambda: machine("assembling-machine-2", 0.27, 0.15, 0.27, hue=BLUE, inset=0.03),
    "assembling-machine-3": lambda: machine("assembling-machine-3", 0.27, 0.15, 0.27, hue=YELLOW, inset=0.03),
    "oil-refinery": lambda: machine("oil-refinery", 0.28, 0.16, 0.28, inset=0.06),
    "chemical-plant": lambda: machine("chemical-plant", 0.26, 0.15, 0.26, inset=0.06),
    "centrifuge": lambda: machine("centrifuge", 0.24, 0.17, 0.24, hue=GREEN),
    "lab": lambda: machine("lab", 0.26, 0.13, 0.26, hue=CYAN, inset=0.04),
    "beacon": lambda: machine("beacon", 0.24, 0.12, 0.24, inset=0.06),
    "radar": lambda: machine("radar", 0.24, 0.12, 0.24, inset=0.06),
    "boiler": lambda: machine("boiler", 0.28, 0.13, 0.2),
    "steam-engine": lambda: machine("steam-engine", 0.28, 0.13, 0.17),
    "steam-turbine": lambda: machine("steam-turbine", 0.28, 0.13, 0.17),
    "solar-panel": lambda: panel("solar-panel"),
    "accumulator": lambda: accumulator("accumulator"),
    "offshore-pump": lambda: machine("offshore-pump", 0.18, 0.12, 0.24),
    "pump": lambda: machine("pump", 0.16, 0.12, 0.24),
    "storage-tank": lambda: machine("storage-tank", 0.27, 0.12, 0.27, inset=0.04),
    "pumpjack": lambda: machine("pumpjack", 0.26, 0.15, 0.26),
    "gun-turret": lambda: turret("gun-turret"),
    "laser-turret": lambda: turret("laser-turret"),
    "flamethrower-turret": lambda: turret("flamethrower-turret"),
    "roboport": lambda: machine("roboport", 0.27, 0.16, 0.27, inset=0.04),
    "train-stop": lambda: pole("train-stop"),
    "rail-signal": lambda: pole("rail-signal"),
    "rail-chain-signal": lambda: pole("rail-chain-signal"),
    "locomotive": lambda: wagon("locomotive"),
    "cargo-wagon": lambda: wagon("cargo-wagon"),
    "fluid-wagon": lambda: wagon("fluid-wagon"),
    "heat-pipe": lambda: pipe("heat-pipe"),
    "nuclear-reactor": lambda: machine("nuclear-reactor", 0.27, 0.15, 0.27, hue=GREEN),
    "heat-exchanger": lambda: machine("heat-boiler", 0.28, 0.13, 0.2),
    # Space Age
    "tungsten-ore": lambda: crystals("tungsten-ore", sat=(0.15, 1.0), lum=(0.15, 0.85)),
    "tungsten-carbide": lambda: extrude([(0.13, 0.0), (-0.08, 0.11), (-0.08, -0.11)], 0.05,
                                        icon("tungsten-carbide").pick(lum=(0.2, 0.8)),
                                        top=icon("tungsten-carbide").pick(lum=(0.4, 0.9))),
    "tungsten-plate": lambda: beam("tungsten-plate", channel=True).rot_y(25),
    "calcite": lambda: ore("calcite", 6),
    "holmium-ore": lambda: ore("holmium-ore", 7),
    "holmium-plate": lambda: plate("holmium-plate"),
    "scrap": lambda: scrap("scrap"),
    "ice": lambda: cube("ice", 0.18),
    "carbon": lambda: extrude(circle(0.12, 6), 0.08, icon("carbon").pick(lum=(0.1, 0.6)), top=icon("carbon").pick(lum=(0.3, 0.9))),
    "lithium": lambda: ore("lithium", 8, lumps=4, size=0.1),
    "lithium-plate": lambda: disc("lithium-plate"),
    "carbon-fiber": lambda: fiber("carbon-fiber"),
    "supercapacitor": lambda: supercapacitor("supercapacitor"),
    "superconductor": lambda: superconductor("superconductor"),
    "quantum-processor": lambda: processor("quantum-processor"),
    "metallic-asteroid-chunk": lambda: lump("metallic-asteroid-chunk", 0.24, 0.17, 0.22, seed=11),
    "carbonic-asteroid-chunk": lambda: lump("carbonic-asteroid-chunk", 0.24, 0.17, 0.22, seed=12),
    "oxide-asteroid-chunk": lambda: lump("oxide-asteroid-chunk", 0.24, 0.17, 0.22, seed=13),
    "promethium-asteroid-chunk": lambda: lump("promethium-asteroid-chunk", 0.24, 0.17, 0.22, seed=14),
    "bioflux": lambda: crystals("bioflux", seed=5),
    "biosulfur": lambda: crystals("biosulfur", seed=6),
    "nutrients": lambda: mound("nutrients"),
    "spoilage": lambda: mound("spoilage", 0.11, 0.07, sat=(0.0, 1.0), lum=(0.1, 0.8)),
    "yumako-mash": lambda: mound("yumako-mash", sat=(0.3, 1.0), lum=(0.2, 0.9)),
    "jelly": lambda: cube("jelly", 0.17, sat=(0.3, 1.0)),
    "yumako": lambda: fruit("yumako"),
    "jellynut": lambda: fruit("jellynut", 0.09),
    "iron-bacteria": lambda: lump("iron-bacteria-1", 0.22, 0.08, 0.14, seed=21, sat=(0.2, 1.0)),
    "copper-bacteria": lambda: lump("copper-bacteria-1", 0.22, 0.08, 0.14, seed=22, sat=(0.2, 1.0)),
    "pentapod-egg": lambda: egg("pentapod-egg", 0.1, sat=(0.3, 1.0)),
    "biter-egg": lambda: egg("biter-egg", 0.1),
    "yumako-seed": lambda: egg("yumako-seed", 0.05),
    "jellynut-seed": lambda: egg("jellynut-seed", 0.05),
    "tree-seed": lambda: egg("tree-seed", 0.05),
    "bioplastic": lambda: brick("bioplastic", 0.25, 0.07, 0.13, 0.025, lum=(0.3, 0.9)),
    "space-platform-foundation": lambda: tile("space-platform-foundation"),
    "foundation": lambda: tile("foundation"),
    "ice-platform": lambda: tile("ice-platform"),
    "fusion-power-cell": lambda: fuel_cell("fusion-power-cell"),
    "railgun-ammo": lambda: bullet("railgun-ammo"),
    "tesla-ammo": lambda: canister("tesla-ammo", CYAN),
    "thruster-fuel": None,  # a fluid
}
RECIPES = {k: v for k, v in RECIPES.items() if v is not None}


def build(name):
    mesh = RECIPES[name]()
    lo, hi = mesh.bounds()
    mesh = mesh.move(-(lo[0] + hi[0]) / 2, -lo[1], -(lo[2] + hi[2]) / 2)
    return shade_by_height(mesh, low=0.7)


# --- preview ------------------------------------------------------------------------------------

def render(mesh, size=160, yaw=0.0, pitch=45.0):
    """A quick software render from Factorio's angle (looking north-ish and down), flat lit,
    painter's algorithm: enough to compare a model with its icon."""
    import numpy as np
    from PIL import Image, ImageDraw

    m = mesh.rot_y(yaw)
    p = m.pos.copy()
    a = math.radians(pitch)
    # View from the south, above: screen x = x, screen y = -(y cos a) + z sin a, depth = ...
    sx = p[..., 0]
    sy = -p[..., 1] * math.cos(a) + p[..., 2] * math.sin(a)
    depth = p[..., 2] * math.cos(a) + p[..., 1] * math.sin(a)
    light = np.array([-0.4, 0.8, 0.45])
    light /= np.linalg.norm(light)
    n = m.nrm.mean(axis=1)
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
    view = np.array([0.0, math.sin(a), math.cos(a)])
    shade = 0.45 + 0.65 * np.clip(n @ light, 0, 1)
    col = np.clip(m.col.mean(axis=1) * shade[:, None], 0, 1)
    order = np.argsort(depth.mean(axis=1))
    img = Image.new("RGBA", (size, size), (60, 60, 60, 255))
    d = ImageDraw.Draw(img)
    k = size / 0.36
    for i in order:
        if n[i] @ view < -0.05:
            continue
        pts = [(size / 2 + sx[i, j] * k, size * 0.62 + sy[i, j] * k) for j in range(3)]
        d.polygon(pts, fill=tuple(int(c * 255) for c in col[i]) + (255,))
    return img


def preview(names, out):
    from PIL import Image, ImageDraw

    s, cols = 128, 6
    rows = (len(names) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * s * 2, rows * (s + 14)), (40, 40, 40, 255))
    d = ImageDraw.Draw(sheet)
    for i, name in enumerate(names):
        x, y = (i % cols) * s * 2, (i // cols) * (s + 14)
        try:
            ic = Image.open(picture(name).path if name in ("iron-ore", "copper-ore", "coal", "stone", "uranium-ore") else icon(name).path).convert("RGBA")
            h = ic.height
            sheet.alpha_composite(ic.crop((0, 0, h, h)).resize((s, s)), (x, y))
        except FileNotFoundError:
            pass
        sheet.alpha_composite(render(build(name), s, yaw=15), (x + s, y))
        d.text((x + 2, y + s), name[:36], fill=(255, 255, 255, 255))
    sheet.save(out)


def main():
    global _factorio
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("names", nargs="*")
    ap.add_argument("--factorio", help="Factorio's install folder (default: found, or $FACTORIO)")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--preview", help="write an icon | model sheet here instead (shows Factorio's icons: keep it out of the repo)")
    args = ap.parse_args()
    if args.list:
        print("\n".join(sorted(RECIPES)))
        return 0
    _factorio = args.factorio or find_factorio()
    if not _factorio:
        print("Factorio not found: pass --factorio DIR or set FACTORIO", file=sys.stderr)
        return 1
    names = args.names or sorted(RECIPES)
    unknown = [n for n in names if n not in RECIPES]
    if unknown:
        print("no recipe for: %s" % ", ".join(unknown), file=sys.stderr)
        return 1
    if args.preview:
        preview(names, args.preview)
        print("wrote %s" % args.preview)
        return 0
    os.makedirs(OUT_DIR, exist_ok=True)
    failed = 0
    for name in names:
        try:
            mesh = build(name)
        except FileNotFoundError as e:
            print("%-32s skipped: %s" % (name, e))
            continue
        lo, hi = mesh.bounds()
        tris = write_glb(os.path.join(OUT_DIR, name + ".glb"), mesh, name)
        size = hi - lo
        bad = []
        if tris > MAX_TRIS:
            bad.append("%d triangles > %d" % (tris, MAX_TRIS))
        if max(size[0], size[2]) > 0.34 or size[1] > 0.3:
            bad.append("too big")
        failed += bool(bad)
        print("%-32s %4d tris  %.2f x %.2f x %.2f%s" % (name, tris, size[0], size[1], size[2],
                                                       ("  FAIL " + "; ".join(bad)) if bad else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
