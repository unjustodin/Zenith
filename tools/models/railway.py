"""Railway buildings: rail supports and ramps (elevated rails), signals, train stops, the gate.

Each is matched to its Factorio sprite with compare.py; the track itself is in rails.py.
"""

import math

from mathutils import Matrix

import kit
from kit import Part, T, model, rng
from rails import DECK_HALF, ELEVATION, GAUGE, PLATE_Z, TIE_HALF, TIE_STEP, TIE_WIDTH, Track, track_on

kit.MATERIALS.update({
    "lamp_green": ("5cff4a", 0.3, 0.0, "40ff30", 2.5),
    # Lit lenses (anim_lit_* parts, shown by the signal's state), Factorio's lights' colours.
    "lamp_yellow": ("ffb03a", 0.3, 0.0, "ff8000", 2.5),
    "lamp_red_lit": ("ff4a3a", 0.3, 0.0, "ff0000", 2.5),
    "lamp_blue": ("8a9aff", 0.3, 0.0, "6666ff", 2.5),
    "lamp_green_off": ("1f3a1c", 0.3, 0.0, None, 0),
    "lamp_yellow_off": ("4a3d16", 0.3, 0.0, None, 0),
    "lamp_red_off": ("4a1a14", 0.3, 0.0, None, 0),
    "glass_amber": ("d8762a", 0.25, 0.1, None, 0),
    "paint_signal_red": ("8a3a2a", 0.6, 0.35, None, 0),
    "paint_stop": ("c8402a", 0.55, 0.3, None, 0),
    "stone_block": ("857a68", 0.95, 0.0, None, 0),  # the supports' dressed stone, brown-grey
    "lamp_stop": ("ffd6a0", 0.3, 0.0, "ffc070", 2.0),
})


# ---------------------------------------------------------------------------------------------
# Rail supports and ramps (elevated-rails mod)

def stone_foundation(p, w, d, h, r, steps=3):
    """A tiered foundation of dressed stone blocks, like the supports' bases: each tier a little
    smaller, with blocks of slightly different heights round its edge. Returns its top."""
    z = 0.0
    for k in range(steps):
        inset = 0.18 * k
        th = h / steps
        hw, hd = w / 2 - inset, d / 2 - inset
        p.slab(-hw + 0.3, -hd + 0.3, z, hw - 0.3, hd - 0.3, z + th * 0.96, "stone_block")
        for side in range(4):
            length = 2 * (hw if side % 2 == 0 else hd)
            n = max(2, round(length / 0.55))
            for i in range(n):
                t0 = -length / 2 + length * i / n + 0.02
                t1 = -length / 2 + length * (i + 1) / n - 0.02
                top = z + th * r.uniform(0.82, 1.0)
                dp = 0.34
                if side == 0:
                    p.slab(t0, -hd, z, t1, -hd + dp, top, "stone_block", bevel=0.04)
                elif side == 1:
                    p.slab(hw - dp, t0, z, hw, t1, top, "stone_block", bevel=0.04)
                elif side == 2:
                    p.slab(t0, hd - dp, z, t1, hd, top, "stone_block", bevel=0.04)
                else:
                    p.slab(-hw, t0, z, -hw + dp, t1, top, "stone_block", bevel=0.04)
        z += th
    return z


def arch_plate(p, y, half_w, z0, z1, thick=0.1):
    """A red plate across x at `y` with a round arch cut out of its foot."""
    pts = [(-half_w, z0), (-0.5, z0)]
    for i in range(1, 8):
        a = math.pi * i / 8
        pts.append((-0.5 * math.cos(a), z0 + 0.35 + 0.5 * math.sin(a) * 0.8))
    pts += [(0.5, z0), (half_w, z0), (half_w, z1), (-half_w, z1)]
    m = T(0, y + thick / 2, 0) @ Matrix.Rotation(math.radians(90), 4, "X")
    p.prism(pts, 0.0, thick, "paint_rail_red", bevel=0.015, matrix=m)


def support_frame(p, top, base, half_w=0.95, half_d=0.75, foot=1.12):
    """The red riveted steel frame of a rail support: legs splayed out onto the foundation, arched
    plates, coil springs at the corners, and the cradle the deck sits in (track running north)."""
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.beam((sx * foot, sy * (half_d + 0.2), base), (sx * half_w, sy * half_d, top - 0.6), 0.22, 0.12,
                   "paint_rail_red", bevel=0.02)
            p.box((sx * foot, sy * (half_d + 0.2), base + 0.06), (0.34, 0.34, 0.12), "paint_rail_red", bevel=0.03)
            for k in range(5):
                p.cyl((sx * (half_w - 0.05), sy * (half_d - 0.28), top - 0.55 + k * 0.07), 0.08, 0.04, "steel_light",
                      segs=10)
            p.cyl((sx * (half_w - 0.05), sy * (half_d - 0.28), top - 0.38), 0.04, 0.5, "steel", segs=8)
    for sy in (-1, 1):
        arch_plate(p, sy * half_d - (0.1 if sy > 0 else 0.0), half_w + 0.08, base + 0.05, top - 0.6)
        for i in range(8):
            x = -half_w + 2 * half_w * i / 7
            p.bolt((x, sy * (half_d + 0.01), top - 0.68), axis="Y", radius=0.022)
    for sx in (-1, 1):
        p.slab(sx * half_w - 0.06, -half_d, top - 0.75, sx * half_w + 0.06, half_d, top - 0.55, "paint_rail_red",
               bevel=0.015)
        # Cradle beams along the track, under the deck's girders.
        p.slab(sx * (DECK_HALF - 0.09), -1.3, top - 0.16, sx * (DECK_HALF + 0.09), 1.3, top, "paint_rail_red", bevel=0.02)
        p.slab(sx * (DECK_HALF - 0.12), -0.55, top - 0.55, sx * (DECK_HALF + 0.12), 0.55, top - 0.16, "paint_rail_red",
               bevel=0.02)
    for y in (-1.1, -0.4, 0.4, 1.1):
        p.beam((-DECK_HALF, y, top - 0.1), (DECK_HALF, y, top - 0.1), 0.06, 0.06, "steel")


@model("rail-support")
def rail_support():
    """The elevated rail's support (elevated-rail-pylon), track running north: a stepped mound of
    dressed stone nearly four tiles across, a red riveted box frame on it with arches in its
    faces and legs splayed to the mound's corners, coil springs on its top, and red uprights
    carrying the cradle under the deck: two long beams along the track joined by bent steel rungs."""
    p = Part()
    r = rng(17)
    # The mound: three chamfered tiers, each a ring of blocks round a solid core.
    z = 0.0
    for half, th in ((2.0, 0.45), (1.65, 0.4), (1.3, 0.4)):
        c = half * 0.38
        octagon = [(-half + c, -half), (half - c, -half), (half, -half + c), (half, half - c),
                   (half - c, half), (-half + c, half), (-half, half - c), (-half, -half + c)]
        p.prism([(x * 0.9, y * 0.9) for x, y in octagon], z, z + th * 0.97, "stone_block")
        for k in range(8):
            (ax, ay), (bx, by) = octagon[k], octagon[(k + 1) % 8]
            length = math.hypot(bx - ax, by - ay)
            n = max(1, round(length / 0.6))
            ang = math.atan2(by - ay, bx - ax)
            for i in range(n):
                t = (i + 0.5) / n
                top = z + th * r.uniform(0.82, 1.0)
                m = T(ax + (bx - ax) * t, ay + (by - ay) * t, z) @ Matrix.Rotation(ang, 4, "Z")
                p.box((0, 0.18, (top - z) / 2), (length / n - 0.04, 0.36, top - z), "stone_block", bevel=0.04,
                      matrix=m)
        z += th
    # Box frame: arched plates on all four faces, a riveted band round the top.
    hw, hd, z0, z1 = 1.12, 0.95, z - 0.05, 2.45
    for sy in (-1, 1):
        arch_plate(p, sy * hd - (0.1 if sy > 0 else 0.0), hw, z0, z1)
        for i in range(9):
            p.bolt((-hw + 2 * hw * i / 8, sy * (hd + 0.01), z1 - 0.1), axis="Y", radius=0.022)
    for sx in (-1, 1):
        q = Part()
        arch_plate(q, -0.05, hd, z0, z1)
        q.transform(Matrix.Rotation(math.radians(90), 4, "Z"))
        q.transform(T(sx * hw, 0, 0))
        p.add_part(q)
    p.slab(-hw - 0.06, -hd - 0.06, z1 - 0.2, hw + 0.06, hd + 0.06, z1, "paint_rail_red", bevel=0.02)
    # Legs from the box's corners down to the mound's corners.
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.beam((sx * (hw - 0.05), sy * (hd - 0.05), z1 - 0.2), (sx * 1.5, sy * 1.45, 0.4), 0.24, 0.14,
                   "paint_rail_red", bevel=0.02)
            p.box((sx * 1.5, sy * 1.45, 0.45), (0.36, 0.36, 0.12), "paint_rail_red", bevel=0.03)
    # Springs on the frame's top, red uprights from them to the cradle.
    top, cw = 4.55, 1.0
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * cw, sy * 0.55
            for k in range(7):
                p.cyl((x, y, z1 + 0.06 + k * 0.08), 0.1, 0.045, "steel_light", segs=10)
            p.cyl((x, y, z1 + 0.3), 0.045, 0.6, "steel", segs=8)
            p.slab(x - 0.09, y - 0.09, z1 + 0.6, x + 0.09, y + 0.09, top - 0.2, "paint_rail_red", bevel=0.02)
        # Cradle beams along the track, and a cross beam under each end.
        p.slab(sx * cw - 0.1, -1.75, top - 0.28, sx * cw + 0.1, 1.75, top, "paint_rail_red", bevel=0.02)
        p.beam((sx * cw, -0.55, z1 + 0.7), (sx * cw, 0.55, top - 0.3), 0.08, 0.06, "paint_rail_red")
    for sy in (-1, 1):
        p.slab(-cw, sy * 1.55 - 0.08, top - 0.32, cw, sy * 1.55 + 0.08, top - 0.16, "paint_rail_red", bevel=0.015)
    # Bent steel rungs between the beams.
    for y in (-1.5, -0.5, 0.5, 1.5):
        p.pipe([(-cw, y, top - 0.05), (-0.6, y, top - 0.2), (0.6, y, top - 0.2), (cw, y, top - 0.05)], 0.035,
               "steel", segs=6)
    return p


RAMP_LEN = 16.0


def ramp_height(y):
    """Track height along a ramp at y (Blender, north +): ground at the south end (-8), the
    elevated deck at the north end (+8), level for the first and last few tiles."""
    t = min(max((y + 8.0) / RAMP_LEN, 0.0), 1.0)
    t = min(max((t - 0.04) / 0.8, 0.0), 1.0)
    # Nearly straight, easing in at the foot and out at the top, as the sprites' side views.
    return ELEVATION * (0.4 * t + 0.6 * t * t * (3 - 2 * t))


@model("rail-ramp")
def rail_ramp():
    """A ramp from ground track (south end) up to the elevated deck (north end), 16 tiles long:
    the track on steel girders carried by red trusses over a stone embankment, a support frame
    under the top. A ramp faces its high end."""
    p = Part()
    r = rng(23)
    # Ground track over the first two tiles, on ballast.
    q = Part()
    track_on(q, Track("straight"), seed=3)
    p.add_part(q, T(0, -7.0, 0))
    n = 40
    ys = [-6.0 + 14.0 * i / n for i in range(n + 1)]
    for y0, y1 in zip(ys, ys[1:]):
        z0, z1 = ramp_height(y0), ramp_height(y1)
        for side in (-1, 1):
            p.beam((side * GAUGE, y0, z0 + PLATE_Z + 0.045), (side * GAUGE, y1, z1 + PLATE_Z + 0.045), 0.05, 0.095,
                   "steel_rail")
            if max(z0, z1) > 0.35:
                p.beam((side * DECK_HALF, y0, z0 - 0.12), (side * DECK_HALF, y1, z1 - 0.12), 0.14, 0.3, "steel_dark")
                if min(z0, z1) > 2.5:  # the sprites' railing only runs along the high end
                    p.beam((side * (DECK_HALF + 0.12), y0, z0 + 0.42), (side * (DECK_HALF + 0.12), y1, z1 + 0.42), 0.06,
                           0.05, "paint_rail_red")
    y = -6.0 + TIE_STEP / 2
    while y < 8.0:
        z = ramp_height(y)
        slope = math.degrees(math.atan2(ramp_height(y + 0.05) - ramp_height(y - 0.05), 0.1))
        p.box((0, 0, 0), (TIE_HALF * 2, TIE_WIDTH, 0.055), "wood_tie", bevel=0.012,
              matrix=T(0, y, z + 0.08) @ Matrix.Rotation(math.radians(slope), 4, "X"))
        for side in (-1, 1):
            p.box((side * GAUGE, y, z + 0.115), (0.16, 0.22, 0.02), "steel_dark")
        y += TIE_STEP
    # Ballast under the low end of the slope.
    p.prism([(-1.1, -6.0), (1.1, -6.0), (0.9, -3.5), (-0.9, -3.5)], 0.0, 0.07, "stone_ballast")
    # Stone embankment under the deck, in blocks, as high as the deck allows.
    y = -4.0
    while y < 8.0:
        top = min(1.35, ramp_height(y + 0.5) - 0.45)
        if top > 0.15:
            p.slab(-1.7, y + 0.01, 0.0, 1.7, y + 0.99, top * r.uniform(0.95, 1.0), "stone_block", bevel=0.025)
        y += 1.0
    # Low stone walls flank the track where it is still near the ground, as the sprites' base runs
    # the ramp's whole length, and a red buffer housing stands either side of the foot.
    y = -7.4
    while y < -4.0:
        for side in (-1, 1):
            top = 0.45 + 0.25 * (y + 7.4) / 3.4
            p.slab(side * 0.98, y + 0.01, 0.0, side * 1.7, y + 0.99, top * r.uniform(0.9, 1.0), "stone_block", bevel=0.025)
        y += 1.0
    for side in (-1, 1):
        p.slab(side * 0.95, -7.95, 0.0, side * 1.6, -7.35, 0.55, "paint_rail_red", bevel=0.04)
        p.cyl((side * 1.27, -7.75, 0.62), 0.12, 0.25, "steel", segs=10, axis="Y")
        p.cyl((side * 1.27, -7.95, 0.62), 0.16, 0.05, "steel_light", segs=10, axis="Y")
    # Red trusses from the embankment up to the deck, every two tiles, with diagonals.
    y = -1.0
    while y < 6.0:
        z = ramp_height(y) - 0.25
        if z > 1.9:
            for side in (-1, 1):
                p.beam((side * 1.5, y, 1.55), (side * DECK_HALF, y, z), 0.2, 0.12, "paint_rail_red", bevel=0.02)
                p.beam((side * 1.4, y - 0.9, 1.6), (side * DECK_HALF, y + 0.9, ramp_height(y + 0.9) - 0.3), 0.08, 0.06,
                       "paint_rail_red")
            p.beam((-DECK_HALF, y, z - 0.1), (DECK_HALF, y, z - 0.1), 0.12, 0.14, "paint_rail_red")
        y += 2.0
    q = Part()
    support_frame(q, ELEVATION - 0.34, 1.6)
    p.add_part(q, T(0, 6.9, 0))
    return p


# ---------------------------------------------------------------------------------------------
# Signals and train stops

SIG_H = 0.46      # lamp housing height
SIG_PITCH = 0.43  # lamps' spacing along the track
SIG_X = (-0.08, 0.24)


def lens_matrix(y):
    """Where a rail signal lamp's lens sits: high on its housing's south face, tilted up."""
    return T(sum(SIG_X) / 2, y - 0.13, SIG_H - 0.14) @ Matrix.Rotation(math.radians(-35), 4, "X")


def lamp_unit(p, y, lens):
    """One lamp of a rail signal, as the sprite draws it: an upright cast housing on the
    sleepers, its lens high on the south face towards the trains coming from the south, a
    bracket from its west side down to a round bolted foot by the rail, a lug on the east."""
    x0, x1 = SIG_X
    xc = (x0 + x1) / 2
    p.slab(x0, y - 0.16, 0.0, x1, y + 0.16, SIG_H - 0.08, "steel_dark", bevel=0.04)
    p.slab(x0 + 0.02, y - 0.15, SIG_H - 0.1, x1 - 0.02, y + 0.15, SIG_H, "steel_dark", bevel=0.05)
    # Lens on the south face's top, tilted up, in a steel rim.
    tilt = lens_matrix(y)
    p.box((0, -0.02, 0), (0.26, 0.04, 0.2), "steel", bevel=0.015, matrix=tilt)
    p.box((0, -0.045, 0), (0.18, 0.012, 0.14), lens, matrix=tilt)
    # Bracket west to the foot, and the east lug.
    p.beam((x0 + 0.02, y, 0.2), (-0.33, y + 0.1, 0.03), 0.13, 0.05, "steel_light", bevel=0.01)
    p.cyl((-0.33, y + 0.1, 0.025), 0.075, 0.05, "steel_light", segs=12, bevel=0.01)
    p.cyl((-0.33, y + 0.1, 0.055), 0.03, 0.012, "soot", segs=8)
    p.beam((x1 - 0.02, y - 0.06, 0.12), (0.3, y - 0.16, 0.03), 0.09, 0.04, "steel_light", bevel=0.01)
    p.cyl((0.3, y - 0.16, 0.02), 0.055, 0.04, "steel_light", segs=10, bevel=0.01)


@model("rail-signal")
def rail_signal():
    """Factorio 2.0's rail signal: three lamp housings in a row along the track, bolted to the
    sleepers beside the rail, green at the north end. The game lights one for the block's state
    (`st`): each lit lens is a part of its own (`anim_lit_green`, ...) over the dark one."""
    p = Part()
    parts = [p]
    for y, lens, colour, lit in ((SIG_PITCH, "lamp_green_off", "green", "lamp_green"), (0.0, "lamp_yellow_off", "yellow", "lamp_yellow"),
                                 (-SIG_PITCH, "lamp_red_off", "red", "lamp_red_lit")):
        lamp_unit(p, y, lens)
        light = Part("anim_lit_" + colour)
        light.box((0, -0.052, 0), (0.19, 0.014, 0.15), lit, matrix=lens_matrix(y))
        parts.append(light)
    # Fitted over the sprite's 16 frames, which don't turn about one point exactly.
    for q in parts:
        q.transform(T(-0.05, 0, 0))
    return parts


@model("rail-chain-signal")
def rail_chain_signal():
    """The chain signal, as Factorio 2.0's sprite: a squat red-brown lantern at the signal's
    position whose rounded top is a grid of amber glass cells, and east of it (away from the
    rail) a red cabinet with a grille on a base plate along the track, a copper cable between
    them. Its glass lights green, yellow, red or blue for the state (`anim_lit_*` parts)."""
    p = Part()
    # Lantern: a red frame box, the amber glass block on it with a dark grid.
    lx0, lx1, ly0, ly1 = -0.17, 0.15, -0.12, 0.2
    p.slab(lx0, ly0, 0.0, lx1, ly1, 0.12, "paint_signal_red", bevel=0.02)
    p.slab(lx0 + 0.02, ly0 + 0.02, 0.12, lx1 - 0.02, ly1 - 0.02, 0.33, "glass_amber", bevel=0.05)
    for k in range(1, 4):
        x = lx0 + (lx1 - lx0) * k / 4
        p.slab(x - 0.008, ly0 + 0.01, 0.12, x + 0.008, ly1 - 0.01, 0.405, "paint_signal_red")
        y = ly0 + (ly1 - ly0) * k / 4
        p.slab(lx0 + 0.01, y - 0.008, 0.12, lx1 - 0.01, y + 0.008, 0.405, "paint_signal_red")
    p.slab(lx0 + 0.01, ly0 + 0.01, 0.2, lx1 - 0.01, ly1 - 0.01, 0.215, "paint_signal_red")
    p.cyl(((lx0 + lx1) / 2, ly0 + 0.005, 0.3), 0.05, 0.02, "lamp_green_off", segs=10, axis="Y")
    parts = [p]
    for colour, lit in (("green", "lamp_green"), ("yellow", "lamp_yellow"), ("red", "lamp_red_lit"), ("blue", "lamp_blue")):
        light = Part("anim_lit_" + colour)
        light.slab(lx0 + 0.016, ly0 + 0.016, 0.125, lx1 - 0.016, ly1 - 0.016, 0.334, lit, bevel=0.05)
        light.cyl(((lx0 + lx1) / 2, ly0 + 0.0, 0.3), 0.055, 0.025, lit, segs=10, axis="Y")
        parts.append(light)
    # Base plate along the track, the cabinet with its grille on it.
    p.slab(0.17, -0.3, 0.0, 0.55, 0.4, 0.05, "paint_signal_red", bevel=0.015)
    p.slab(0.22, -0.18, 0.05, 0.5, 0.2, 0.4, "paint_signal_red", bevel=0.03)
    for k in range(3):
        p.slab(0.27, -0.19, 0.1 + k * 0.055, 0.45, -0.18, 0.13 + k * 0.055, "steel_light")
    for y in (-0.25, 0.35):
        p.cyl((0.36, y, 0.05), 0.025, 0.02, "steel_light", segs=8)
    p.pipe([(0.25, 0.2, 0.32), (0.2, 0.3, 0.15), (0.13, 0.22, 0.08)], 0.018, "copper_dull", segs=6)
    # Fitted over the sprite's 16 frames, which don't turn about one point exactly.
    for q in parts:
        q.transform(T(-0.18, 0, 0))
    return parts


@model("train-stop")
def train_stop():
    """The train stop, facing north (trains stop going north on the track two tiles west of it),
    as Factorio 2.0's north picture at true ground proportions (the owner chose the north view:
    the four pictures disagree on where the tower stands). Its lower half and the pieces by the
    track are in the rail overlay (`train-stop-ground.png`). A rusty lattice tower at the
    footprint's south edge carries a grey head and a flat box girder reaching west over the track
    to a signal box with two round lamps, on a knee brace; cables run from the head to the tip. On
    the ground: a finned cabinet and a rusty box west of the tower's foot, a dark machine east of
    it, a cable rack with five brackets along the track and low signal boxes beside the rails.
    The name board's colour mask is left to the station's default."""
    p = Part()
    # Lattice tower: four corner posts with X bracing on every face.
    x0, x1, y0, y1, h = -0.29, 0.13, -1.21, -0.79, 3.95
    corners = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    p.slab(x0 - 0.07, y0 - 0.06, 0.0, x1 + 0.07, y1 + 0.06, 0.12, "rust_brown", bevel=0.02)
    for x, y in corners:
        p.beam((x, y, 0.05), (x, y, h), 0.07, 0.07, "rust_brown")
    for i in range(4):
        (ax, ay), (bx, by) = corners[i], corners[(i + 1) % 4]
        z = 0.15
        while z < h - 0.3:
            p.beam((ax, ay, z), (bx, by, z + 0.42), 0.04, 0.03, "rust_brown")
            p.beam((bx, by, z), (ax, ay, z + 0.42), 0.04, 0.03, "rust_brown")
            p.beam((ax, ay, z), (bx, by, z), 0.04, 0.03, "rust_brown")
            z += 0.42
    # Knee brace from the tower's west side up under the girder.
    p.beam((-0.27, -1.0, 2.9), (-0.85, -1.0, 4.05), 0.2, 0.18, "steel", bevel=0.03)
    # Head: the grey housing on the tower's top, the girder running west from it.
    hy0, hy1 = -1.27, -0.73
    p.slab(-0.4, hy0, 3.9, 0.2, hy1, 4.62, "steel", bevel=0.04)
    p.slab(-0.36, hy0 + 0.04, 4.62, 0.16, hy1 - 0.04, 4.76, "steel_light", bevel=0.03)
    p.slab(-2.0, hy0 + 0.02, 4.05, -0.4, hy1 - 0.02, 4.17, "steel", bevel=0.02)
    p.slab(-2.0, hy0 + 0.02, 4.3, -0.4, hy1 - 0.02, 4.38, "steel", bevel=0.02)
    x = -0.45
    while x > -1.95:  # web of the girder
        p.beam((x, hy0 + 0.06, 4.15), (x - 0.25, hy0 + 0.06, 4.32), 0.05, 0.04, "rust_brown")
        p.beam((x, hy1 - 0.06, 4.15), (x - 0.25, hy1 - 0.06, 4.32), 0.05, 0.04, "rust_brown")
        x -= 0.25
    # Signal box at the tip, its two lamps facing south down the track.
    p.slab(-2.42, hy0, 3.98, -1.6, hy1, 4.36, "steel", bevel=0.04)
    for lx in (-2.18, -1.85):
        p.cyl((lx, hy0 - 0.005, 4.15), 0.1, 0.04, "steel_black", segs=12, axis="Y")
        p.cyl((lx, hy0 - 0.02, 4.15), 0.065, 0.02, "lamp_stop", segs=10, axis="Y")
    p.slab(-2.42, hy0 + 0.05, 4.36, -2.3, hy1 - 0.05, 4.46, "steel_dark")
    # Cables from the head's top to the tip.
    for y in (hy0 + 0.1, hy1 - 0.1):
        p.beam((0.0, y, 4.74), (-2.36, y, 4.42), 0.02, 0.02, "steel_light")
    # Finned cabinet west of the tower, a rusty box in front of it, a dark machine east of it.
    p.slab(-0.79, -0.22, 0.0, -0.4, 0.18, 0.5, "steel", bevel=0.03)
    for k in range(5):
        p.slab(-0.76, -0.18 + k * 0.08, 0.5, -0.43, -0.14 + k * 0.08, 0.6, "steel_light", bevel=0.01)
    p.slab(-0.86, -0.89, 0.0, -0.34, -0.52, 0.33, "rust_brown", bevel=0.03)
    p.slab(0.13, -0.4, 0.0, 0.7, -0.04, 0.22, "steel_dark", bevel=0.03)
    p.slab(0.17, -0.34, 0.22, 0.6, -0.1, 0.36, "steel_black", bevel=0.04)
    # Cable rack along the track: a low tray with five brackets, its cable bending to the cabinet.
    p.slab(-1.37, -1.15, 0.0, -1.05, 0.75, 0.05, "rust_brown")
    for y in (0.62, 0.2, -0.21, -0.63, -1.05):
        p.slab(-1.36, y - 0.06, 0.05, -1.06, y + 0.06, 0.08, "steel_light")
        for x in (-1.33, -1.09):
            p.slab(x - 0.03, y - 0.05, 0.05, x + 0.03, y + 0.05, 0.2, "steel_light")
    p.pipe([(-1.2, -1.1, 0.12), (-1.2, 0.55, 0.12), (-1.1, 0.75, 0.15), (-0.85, 0.2, 0.25), (-0.79, 0.0, 0.3)],
           0.03, "steel_dark", segs=6)
    # Low signal boxes beside the rails, cabled to the rack.
    for bx0, bx1, by0, by1, bh in ((-2.84, -2.64, 0.12, 0.32, 0.3), (-2.56, -2.32, 0.12, 0.32, 0.3),
                                   (-1.75, -1.49, 0.0, 0.2, 0.25), (-1.83, -1.49, -0.89, -0.3, 0.2),
                                   (-2.5, -2.22, -0.92, -0.75, 0.1)):
        p.slab(bx0, by0, 0.0, bx1, by1, bh, "steel", bevel=0.02)
    p.pipe([(-2.45, 0.32, 0.28), (-2.4, 0.65, 0.25), (-1.6, 0.67, 0.25), (-1.3, 0.62, 0.15)], 0.03, "steel_dark", segs=6)
    p.pipe([(-1.62, 0.2, 0.22), (-1.6, 0.55, 0.3), (-1.4, 0.6, 0.15)], 0.03, "steel_dark", segs=6)
    return p


# ---------------------------------------------------------------------------------------------
# Gate

def _clip(poly, y0, y1, z0, z1):
    """Sutherland-Hodgman: a polygon [(y, z), ...] clipped to the rectangle."""
    for axis, lim, keep_above in ((0, y0, True), (0, y1, False), (1, z0, True), (1, z1, False)):
        out = []
        for i, a in enumerate(poly):
            b = poly[(i + 1) % len(poly)]
            ina = a[axis] >= lim if keep_above else a[axis] <= lim
            inb = b[axis] >= lim if keep_above else b[axis] <= lim
            if ina:
                out.append(a)
            if ina != inb:
                t = (lim - a[axis]) / (b[axis] - a[axis])
                out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
        poly = out
        if not poly:
            break
    return poly


GATE_H = 1.2
GATE_BOTTOM, GATE_TOP = 0.34, 0.11  # half widths of the door's tapered section


@model("gate")
def gate():
    """Factorio's gate, facing north: it stands in a north-south wall (the "vertical" gate; turned
    east it is the horizontal one). A steel frame on the ground and the door (`anim_gate_door`,
    pivot on the ground): a tapered slab with hazard stripes and steel caps that sinks into the
    ground to open (anim.gd)."""
    frame = Part()
    for sx in (-1, 1):
        frame.slab(sx * 0.36, -0.5, 0.0, sx * 0.47, 0.5, 0.14, "steel", bevel=0.02)
        frame.slab(sx * 0.4, -0.18, 0.0, sx * 0.5, 0.18, 0.3, "steel_dark", bevel=0.03)
        for y in (-0.35, 0.35):
            frame.bolt((sx * 0.415, y, 0.14), radius=0.025)
    frame.slab(-0.36, -0.5, 0.0, 0.36, 0.5, 0.015, "soot")
    door = Part("anim_gate_door")
    profile = [(-GATE_BOTTOM, 0.0), (GATE_BOTTOM, 0.0), (GATE_TOP, GATE_H), (-GATE_TOP, GATE_H)]
    to_y = T(0, 0.49, 0) @ Matrix.Rotation(math.radians(90), 4, "X")
    door.prism(profile, 0.0, 0.98, "hazard", bevel=0.01, matrix=to_y)
    # Black stripes on both sloped faces: diagonal bands clipped to the face, just proud of it.
    slope = (GATE_BOTTOM - GATE_TOP) / GATE_H
    for side in (-1, 1):
        for k in range(-5, 6):
            c = -0.6 + k * 0.3
            band = [(c, 0.0), (c + 0.15, 0.0), (c + 0.15 + GATE_H * 0.9, GATE_H), (c + GATE_H * 0.9, GATE_H)]
            band = _clip(band, -0.48, 0.48, 0.02, GATE_H - 0.02)
            if len(band) < 3:
                continue
            pts = [(side * (GATE_BOTTOM - slope * z + 0.005), y, z) for y, z in band]
            if side < 0:
                pts.reverse()
            door.poly(pts, "hazard_black")
    for y in (-0.33, 0.0, 0.33):
        door.slab(-0.13, y - 0.12, GATE_H - 0.02, 0.13, y + 0.12, GATE_H + 0.06, "steel", bevel=0.015)
        door.slab(-0.1, y - 0.09, GATE_H + 0.06, 0.1, y + 0.09, GATE_H + 0.075, "hazard")
    for sy in (-1, 1):
        y = sy * 0.49
        nose = T(0, y + (0.0 if sy > 0 else 0.06), 0) @ Matrix.Rotation(math.radians(90), 4, "X")
        door.prism([(-0.1, 0.0), (0.1, 0.0), (0.06, 0.32), (-0.06, 0.32)], 0.0, 0.06, "steel_black", matrix=nose)
    return [frame, door]
