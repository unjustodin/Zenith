"""Oil processing: pumpjack, oil refinery, chemical plant.

Each model is matched to Factorio's HR sprite with compare.py (see client/assets/models/README.md,
"Matching a sprite"). Many parts are placed straight from where they show in the sprite: Factorio's
camera shows a point (x, y, z) at x tiles right and UP_Y * y + COS_P * z tiles up the screen, so
picking a depth y for a part gives its height from its screen height (`zs`), and a part on known
height gives its depth (`ys`).
"""

import math

from mathutils import Matrix

from detail import panel, rivet_line
from kit import Part, R, T, model

SIN_P, COS_P = math.sin(math.radians(48)), math.cos(math.radians(48))
# Factorio's sprites draw the ground's north-south distances at full length (sprite_projection.py
# TRUE_PROPORTIONS): a point (x, y, z) shows at x tiles right and STRETCH * SIN_P * y + COS_P * z up.
STRETCH = 1.0 / SIN_P
UP_Y = STRETCH * SIN_P

# (x, y, z) -> (x, z, y): turns a prism drawn in the x-y plane into the x-z plane, extruded
# along y, for profiles seen from the south (the horse head).
XZ = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))


def zs(u, y):
    """Height of a point at depth `y` that shows `u` tiles up the screen in the sprite."""
    return (u - UP_Y * y) / COS_P


def ys(u, z):
    """Depth of a point at height `z` that shows `u` tiles up the screen in the sprite."""
    return (u - COS_P * z) / UP_Y


def flange(p, center, radius, axis, mat="steel_dark", depth=0.06):
    p.cyl(center, radius, depth, mat, segs=12, axis=axis, bevel=0.01)


# ---------------------------------------------------------------------------------------------
# Pumpjack.

PJ_WEIGHT = (-90, 40)  # the counterweights' arc (degrees about the crank shaft, 0 east), as frame 0 shows them
PJ_Y = -0.2  # the walking beam's plane: over the middle of the samson post and the wellhead
PJ_FACINGS = ("", "-east", "-south", "-west")
PJ_THICK, PJ_DROP = 1.3, 0.04


def _pumpjack_upright():
    """The beam, samson post, gearbox, cranks and wellhead: Factorio draws them as one layer
    (pumpjack-horsehead.png) facing the same way in every direction, so every direction's model
    has them as they are, `anim_upright_*` parts the client keeps facing north. The frame stands
    still, the beam rocks in step with the crank. Everything stands on the ground no further
    south than the picture's bottom edge (about y = -0.05)."""
    p = Part("anim_upright_still")
    y0 = PJ_Y
    # Skid under the samson post and the gearbox, and the dark footing in front of it that every
    # direction's base picture draws.
    p.slab(-0.25, -0.05, 0.0, 1.15, 0.6, 0.08, "steel_black", bevel=0.02)
    for x0, y0_, x1, y1 in ((-0.25, -0.55, 0.0, -0.05), (0.0, -0.22, 0.45, -0.05), (0.45, -0.35, 1.22, -0.05),
                            (0.55, -0.55, 0.95, -0.3), (1.0, -0.45, 1.22, -0.3), (-1.65, -0.45, -0.9, -0.02)):
        p.slab(x0, y0_, 0.0, x1, y1, 0.02, "soot")
    for x in (-0.1, 0.75):
        p.slab(x - 0.12, -0.55, 0.0, x + 0.12, -0.3, 0.08, "steel_black", bevel=0.02)

    # Samson post: two A-frames (south and north) leaning in to a bearing housing on top.
    fy_ = y0 - 0.16  # front of the housing
    hz0, hz1 = zs(0.9, fy_), zs(1.2, fy_)
    # The north frame's feet stand further in: from the camera its legs hide behind the south's.
    for sy, fy, (fw, fe) in ((-1, -0.05, (-0.24, 0.72)), (1, 0.5, (-0.1, 0.58))):
        ty = y0 + sy * 0.1
        p.beam((fw, fy, 0.06), (-0.06, ty, hz0 + 0.05), 0.12, 0.1, "paint_green", up=(0, sy, 0.2))
        p.beam((fe, fy, 0.06), (0.3, ty, hz0 + 0.05), 0.12, 0.1, "paint_green", up=(0, sy, 0.2))
        p.beam((-0.18, fy - sy * 0.03, 0.6), (0.64, fy - sy * 0.03, 0.6), 0.05, 0.05, "paint_green")
        p.beam((-0.17, fy - sy * 0.03, 0.65), (0.52, y0 + sy * 0.25, 1.45), 0.05, 0.05, "paint_green")
        for x in (fw, fe):  # the feet's bolted shoes
            p.slab(x - 0.09, fy - 0.07, 0.0, x + 0.09, fy + 0.07, 0.09, "olive_dark", bevel=0.015)
            p.bolt((x - 0.05, fy - 0.075, 0.05), axis="Y")
            p.bolt((x + 0.05, fy - 0.075, 0.05), axis="Y")
    # The north frame is cross-braced with plates: they fill the dark gaps in the sprite.
    p.prism([(-0.22, 0.0), (0.7, 0.0), (0.32, hz0), (-0.2, hz0)], 0.45, 0.49, "olive_dark", matrix=XZ)
    p.slab(-0.14, fy_, hz0, 0.36, y0 + 0.16, hz1, "paint_green", bevel=0.03)
    p.slab(-0.1, fy_ - 0.01, hz0 + 0.05, 0.32, fy_ + 0.01, hz1 - 0.05, "olive_steel", bevel=0.01)
    # The housing's front plate is bolted at its corners, a yellow-lit rim along its top.
    for x in (-0.06, 0.28):
        for z in (hz0 + 0.09, hz1 - 0.09):
            p.bolt((x, fy_ - 0.015, z), axis="Y")
    p.slab(-0.14, fy_ - 0.02, hz1 - 0.04, 0.36, fy_ + 0.02, hz1, "hazard", bevel=0.01)
    # Saddle bearing just above the housing, an arch over it, a block up to the beam.
    piv = (0.1, y0, zs(1.27, fy_))
    arch = Part()
    arch.ring_band((0, 0), 0.17, 0.27, -0.13, 0.13, 0, 180, "paint_green", segs=8, bevel=0.015)
    p.add_part(arch, T(*piv) @ R("X", 90))
    p.slab(-0.17, y0 - 0.13, hz1 - 0.02, 0.37, y0 + 0.13, piv[2], "paint_green", bevel=0.02)
    p.cyl(piv, 0.08, 0.34, "steel_light", segs=10, axis="Y")

    # Gearbox: tall and narrow, a darker sump at the bottom, a pulley on its south face; the
    # crank shaft runs through it to a pillow block on the north.
    gx0, gx1, gy0, gy1 = 0.46, 1.09, -0.05, 0.2
    p.slab(gx0 - 0.03, gy0 - 0.03, 0.06, gx1 + 0.03, gy1 + 0.03, zs(0.15, gy0), "olive_dark", bevel=0.02)
    p.slab(gx0, gy0, zs(0.15, gy0), gx1, gy1, zs(0.77, gy0), "paint_green", bevel=0.06)
    p.slab(gx0 - 0.01, gy0 - 0.01, zs(0.75, gy0), gx1 + 0.01, gy1 + 0.01, zs(0.79, gy0), "olive_steel")
    rivet_line(p, (gx0 + 0.05, gy0 - 0.005, zs(0.72, gy0)), (gx1 - 0.05, gy0 - 0.005, zs(0.72, gy0)), 6, "Y")
    pz = zs(0.46, gy0)
    p.cyl((0.62, gy0 - 0.03, pz), 0.2, 0.05, "steel_dark", segs=14, axis="Y", bevel=0.01)
    p.cyl((0.62, gy0 - 0.06, pz), 0.06, 0.03, "steel_light", segs=8, axis="Y")

    # Cranks either side of the gearbox, counterweights pointing east; they turn about the
    # crank shaft. The pitman arms come up from the crank pins to the beam's east end.
    sx, sz = 0.88, 1.28
    cys = (-0.45, -0.05)
    p.slab(0.75, 0.04, 0.06, 1.0, 0.16, sz - 0.15, "paint_green", bevel=0.03)
    p.cyl((sx, (cys[0] + cys[1]) / 2, sz), 0.07, cys[1] - cys[0], "steel", segs=8, axis="Y")
    weight = Part()
    weight.ring_band((0.0, 0.0), 0.12, 0.58, -0.035, 0.035, PJ_WEIGHT[0], PJ_WEIGHT[1], "paint_red", segs=8, bevel=0.01)
    crank = Part("anim_upright_spin_crank", pivot=(sx, y0, sz))
    for cy in cys:
        crank.add_part(weight, T(sx, cy, sz) @ R("X", 90))
        crank.cyl((sx, cy, sz), 0.1, 0.09, "steel", segs=10, axis="Y")
    ez = zs(1.53, y0 - 0.1) - 0.02  # bottom of the beam's east end
    for cy in cys:
        p.beam((1.25, cy + (0.04 if cy < y0 else -0.04), sz), (1.25, y0 + (-0.09 if cy < y0 else 0.09), ez),
               0.05, 0.05, "steel_dark")
    p.beam((1.25, y0 - 0.1, ez), (1.25, y0 + 0.1, ez), 0.07, 0.07, "steel_dark")

    # Wellhead under the horse head: a green christmas tree with valve arms on a squat drum, a
    # flow line east, a riser with a handwheel valve.
    wx, wy = -1.46, 0.18
    p.cyl((wx - 0.02, wy, 0.15), 0.18, 0.3, "paint_green", segs=14, bevel=0.03)
    p.cyl((wx - 0.02, wy, 0.31), 0.2, 0.04, "olive_dark", segs=14)
    p.bolts_ring((wx - 0.02, wy, 0.335), 0.15, 8)
    p.cyl((wx, wy, 0.6), 0.08, 0.45, "paint_green", segs=10)
    for z in (0.5, 0.72):
        p.cyl((wx, wy, z), 0.11, 0.07, "paint_green", segs=10, bevel=0.015)
    p.cyl((wx, wy, 0.86), 0.05, 0.08, "steel", segs=8)
    p.tube((wx, wy, 0.5), (wx, wy - 0.3, 0.5), 0.05, "paint_green", segs=8)
    p.cyl((wx, wy - 0.3, 0.5), 0.08, 0.04, "paint_green", segs=10, axis="Y")
    fz = zs(0.38, 0.0)
    p.pipe([(wx + 0.1, wy, 0.3), (wx + 0.1, 0.0, fz), (-0.62, 0.0, fz), (-0.62, 0.0, 0.05)], 0.09, "iron_rust", segs=8)
    for x in (-1.2, -0.75):
        flange(p, (x, 0.0, fz), 0.12, "X", "rust_brown", 0.05)
    p.cyl((-1.02, 0.0, zs(0.5, 0.0)), 0.08, 0.35, "paint_green", segs=8)
    p.slab(-1.12, -0.1, zs(0.6, 0.0), -0.92, 0.1, zs(0.8, 0.0), "paint_green", bevel=0.02)
    p.pipe([(-0.92, 0.0, zs(0.7, 0.0)), (-0.8, 0.0, zs(0.7, 0.0)), (-0.76, 0.0, zs(0.85, 0.0))], 0.035,
           "paint_green", segs=6)
    # A tall green riser on the east with a handwheel valve near the ground and a hooked vent on top.
    hy = -0.15
    top = zs(0.82, hy)
    p.cyl((-0.75, hy, top / 2), 0.05, top, "paint_green", segs=8)
    p.pipe([(-0.75, hy, top), (-0.7, hy, top + 0.12), (-0.6, hy, top + 0.08)], 0.035, "steel", segs=6)
    p.cyl((-0.75, hy, zs(0.12, hy)), 0.09, 0.08, "paint_green", segs=10)
    p.cyl((-0.76, hy - 0.08, zs(0.07, hy - 0.08)), 0.09, 0.02, "steel_light", segs=10, axis="Y")
    p.cyl((-0.76, hy - 0.09, zs(0.07, hy - 0.08)), 0.02, 0.03, "steel_light", segs=6, axis="Y")
    # The polished rod, hanging from the horse head into the wellhead.
    p.cyl((-1.53, y0, 2.0), 0.022, 2.1, "steel_light", segs=6)

    # The walking beam and horse head: they rock about the saddle bearing.
    beam = Part("anim_upright_rock_beam", pivot=piv)
    west = (-1.02, y0, zs(1.86, y0))
    east = (1.36, y0, zs(1.65, y0))
    beam.beam((west[0], y0, west[2] - 0.07), (east[0], y0, east[2] - 0.07), 0.16, 0.36, "paint_green", bevel=0.02)
    beam.beam((west[0], y0, west[2] + 0.115), (east[0], y0, east[2] + 0.115), 0.1, 0.02, "hazard")
    for t in (0.28, 0.5, 0.72):
        x = west[0] + (east[0] - west[0]) * t
        z = west[2] + (east[2] - west[2]) * t
        beam.box((x, y0, z), (0.04, 0.18, 0.24), "olive_steel")
    beam.slab(0.0, y0 - 0.1, piv[2] + 0.02, 0.2, y0 + 0.1, zs(1.62, y0 - 0.1), "paint_green", bevel=0.02)
    # The saddle bearing's cap shows over the beam.
    beam.cyl((piv[0] + 0.02, y0, zs(1.95, y0) - 0.22), 0.15, 0.24, "paint_green", segs=10, axis="Y")
    # Horse head: a plate with an arced west face, its outline taken from the sprite.
    yf_ = y0 - 0.11
    outline = [(-0.97, 1.96), (-1.25, 2.0), (-1.45, 1.97), (-1.49, 1.87), (-1.49, 1.5), (-1.46, 1.04),
               (-1.25, 1.04), (-1.12, 1.35), (-0.97, 1.67)]
    head = [(x, zs(u, yf_)) for x, u in outline]
    beam.prism(head, y0 - 0.11, y0 + 0.11, "paint_green", bevel=0.02, matrix=XZ)
    for z in (zs(1.85, yf_), zs(1.45, yf_)):
        beam.cyl((-1.3, yf_ - 0.005, z), 0.05, 0.01, "soot", segs=8, axis="Y")
    return [p, beam, crank]


def _ground_pipe(p, pts, r, mat="iron_rust", dive=(False, False), flanges=(), z=None):
    """A pipe lying on the ground through screen points (x, u): where its centre line shows in
    the sprite. `dive` turns an end down into the ground (the sprites' elbows that go under);
    `flanges` are (x, u, axis) collars on it. A point (x, u, z) stands at that height instead,
    over the ground point its u gives. The main pipes (`r` 0.06 or more, read from their lit
    tops) are drawn PJ_THICK times as thick and PJ_DROP lower: the sprite's pipes carry a dark
    underside and shadow that belong to their silhouette."""
    drop = 0.0
    if r >= 0.06:
        r, drop = r * PJ_THICK, PJ_DROP
    gz = r + 0.035 if z is None else z  # its collars stand on the ground
    pts = [(x, u - drop, *rest) for x, u, *rest in pts]
    flanges = [(x, u - drop, axis) for x, u, axis in flanges]
    q = [(x, ys(u, gz), (rest[0] if rest else gz)) for x, u, *rest in pts]
    if dive[0]:
        q.insert(0, (q[0][0], q[0][1], 0.0))
    if dive[1]:
        q.append((q[-1][0], q[-1][1], 0.0))
    p.pipe(q, r, mat, segs=8)
    for x, u, axis in flanges:
        flange(p, (x, ys(u, gz), gz), r + 0.035, axis, "rust_brown", 0.05)
        for k in range(4):  # the collar's bolts
            a = math.radians(45 + 90 * k)
            off = {"X": (0, math.cos(a), math.sin(a)), "Y": (math.cos(a), 0, math.sin(a))}[axis]
            p.bolt((x + off[0] * (r + 0.02), ys(u, gz) + off[1] * (r + 0.02), gz + off[2] * (r + 0.02)),
                   radius=0.015, axis=axis)


def _motor(p, box, drum, facing, legs=()):
    """The red motor-pump: a dark housing with a red top (`box`: x0, y0, x1, y1, z1), the grille
    drum on the side the pumpjack faces (`drum`: centre, radius, depth), its bolted outlet
    flange, and green pump `legs` ((x, y, z0, z1)) in front."""
    x0, y0, x1, y1, z1 = box
    p.slab(x0, y0, 0.0, x1, y1, z1 - 0.12, "steel_dark", bevel=0.03)
    p.slab(x0 - 0.01, y0 - 0.01, z1 - 0.14, x1 + 0.01, y1 + 0.01, z1, "paint_red", bevel=0.03)
    panel(p, (x0, y0, 0.08), (x1, y1, z1 - 0.16), "-y", "olive_dark", margin=0.05, rivet="steel_light")
    for x, y in ((x0 + 0.05, y0 + 0.05), (x1 - 0.05, y0 + 0.05), (x0 + 0.05, y1 - 0.05), (x1 - 0.05, y1 - 0.05)):
        p.bolt((x, y, z1 + 0.005))
    (cx, cy, cz), r, depth = drum
    axis = "Y" if facing % 2 == 0 else "X"
    out = {0: (0, 1, 0), 1: (1, 0, 0), 2: (0, -1, 0), 3: (-1, 0, 0)}[facing]
    p.cyl((cx, cy, cz), r, depth, "rust_brown", segs=20, axis=axis, bevel=0.02)
    face = (cx + out[0] * depth / 2, cy + out[1] * depth / 2, cz)
    p.cyl(face, r * 0.85, 0.02, "steel_dark", segs=20, axis=axis)
    p.cyl(face, r * 0.35, 0.05, "brass", segs=12, axis=axis)
    # The grille's teeth round its rim.
    for k in range(16):
        a = 2 * math.pi * k / 16
        c, s = math.cos(a) * r * 0.92, math.sin(a) * r * 0.92
        off = (s, 0, c) if axis == "Y" else (0, s, c)
        p.box((face[0] + off[0], face[1] + off[1], face[2] + off[2]), (0.04, 0.04, 0.04), "steel_light")
    for x, y, z0, z1 in legs:
        p.cyl((x, y, (z0 + z1) / 2), 0.12, z1 - z0, "iron_rust", segs=12)
        p.cyl((x, y, z1), 0.14, 0.05, "rust_brown", segs=12)
        p.cyl((x, y, z0 + 0.05), 0.14, 0.05, "rust_brown", segs=12)


def _pumpjack_base(p, facing):
    """The ground pipes and the motor of one direction, traced from its picture in
    pumpjack-base.png: Factorio routes them differently every way round. Points are where the
    pipes' centre lines show on screen (x, u)."""
    if facing == 0:
        # North: the motor in the north-east corner, its drum to the north edge (the output).
        _ground_pipe(p, [(-0.55, -0.69), (1.29, -0.69), (1.4, -0.6), (1.4, 0.85), (1.32, 0.9)], 0.09,
                     flanges=[(-0.39, -0.69, "X"), (0.45, -0.69, "X"), (1.12, -0.69, "X"), (1.4, 0.0, "Y")])
        _ground_pipe(p, [(-0.55, -0.69), (-0.6, -0.86), (-0.72, -1.0), (-0.9, -1.1), (-1.05, -1.14)], 0.08,
                     dive=(False, True), flanges=[(-0.68, -0.96, "X")])
        _ground_pipe(p, [(-0.24, -0.69), (-0.24, -1.1)], 0.04, dive=(False, True))
        _ground_pipe(p, [(1.3, 0.92), (1.6, 0.95), (1.62, 1.2), (1.48, 1.22)], 0.059)
        _ground_pipe(p, [(0.66, 0.7), (-0.49, 0.7), (-0.49, -0.28), (-0.6, -0.42), (-1.28, -0.42), (-1.33, -0.48)],
                     0.07, dive=(False, True), flanges=[(0.45, 0.7, "X"), (-0.49, 0.3, "Y"), (-1.0, -0.42, "X")])
        _ground_pipe(p, [(-0.6, -0.02), (-1.48, -0.02), (-1.55, -0.24), (-1.55, -0.4), (-1.44, -0.4)], 0.022, mat="steel")
        _ground_pipe(p, [(-0.17, 1.11), (-1.38, 1.11), (-1.47, 1.0), (-1.47, 0.45), (-1.36, 0.3), (-1.08, 0.32)],
                     0.075, dive=(False, True), flanges=[(-0.9, 1.11, "X"), (-1.47, 0.75, "Y")])
        _ground_pipe(p, [(-1.33, 1.05), (-1.33, 0.62), (-1.0, 0.52), (-0.75, 0.52), (-0.72, 0.45)], 0.06, dive=(False, True))
        _ground_pipe(p, [(-0.55, 1.28), (-0.2, 1.28)], 0.025, mat="steel")
        _ground_pipe(p, [(-0.55, 1.28), (-0.55, 0.0)], 0.025, mat="steel")
        # The north run climbs over to the motor.
        y = ys(1.17, 0.085)
        p.pipe([(-0.17, y, 0.085), (-0.17, y, zs(1.42, y)), (0.55, y, zs(1.42, y))], 0.07, "iron_rust", segs=8)
        flange(p, (0.2, y, zs(1.42, y)), 0.1, "X", "rust_brown", 0.05)
        _motor(p, (0.48, 0.83, 1.5, 1.3, 0.8), ((1.0, 1.36, 0.52), 0.38, 0.14), 0,
               legs=[(0.77, 0.75, 0.0, 0.93), (1.06, 0.75, 0.0, 0.93)])
    elif facing == 1:
        # East: the motor in the south-east corner, its drum to the east edge.
        _ground_pipe(p, [(-1.52, 0.62), (-1.3, 0.7), (-1.05, 0.85), (-0.97, 1.0), (-0.97, 1.42), (-0.9, 1.52), (0.2, 1.52),
                         (0.32, 1.38), (0.45, 1.3), (0.72, 1.3), (0.81, 1.17), (0.81, 0.98), (0.7, 0.8), (0.38, 0.7)],
                     0.08, dive=(True, True),
                     flanges=[(-0.7, 1.52, "X"), (-0.08, 1.52, "X"), (0.55, 1.3, "X"), (0.81, 1.08, "Y"), (-0.97, 1.1, "Y")])
        _ground_pipe(p, [(0.33, 0.97), (-0.55, 0.97), (-0.6, 0.88), (-0.6, -0.62), (-0.55, -0.75)], 0.07,
                     dive=(True, False), flanges=[(-0.4, 0.97, "X"), (0.05, 0.97, "X"), (-0.6, 0.2, "Y"), (-0.6, -0.4, "Y")])
        _ground_pipe(p, [(-0.3, -0.15), (-0.3, 0.08), (-0.55, 0.08), (-0.55, -0.53), (0.82, -0.53)], 0.03, mat="steel")
        _ground_pipe(p, [(-1.4, -1.05), (-1.42, -0.95), (-1.3, -0.87), (0.2, -0.87), (0.35, -0.94), (0.45, -1.05),
                         (0.6, -1.05), (0.7, -0.9), (0.82, -0.8)], 0.085, dive=(True, False),
                     flanges=[(-1.05, -0.87, "X"), (-0.3, -0.87, "X")])
        _ground_pipe(p, [(0.82, -0.65), (0.55, -0.6), (0.38, -0.68), (0.33, -0.83)], 0.075)
        _ground_pipe(p, [(-1.08, -0.83), (-1.08, -1.12), (-0.39, -1.12), (-0.37, -1.37), (0.95, -1.37), (0.95, -1.2)],
                     0.03, mat="steel")
        _ground_pipe(p, [(-1.55, -0.25), (-1.55, -0.38), (-1.38, -0.38)], 0.03, mat="steel")
        _ground_pipe(p, [(-1.38, -0.52), (-0.95, -0.52)], 0.03, mat="steel")
        _motor(p, (0.81, -1.34, 1.15, -0.75, 0.55), ((1.3, -0.97, 0.28), 0.27, 0.3), 1)
        for z in (0.18, 0.38):
            p.cyl((0.88, -1.345, z), 0.03, 0.02, "lamp_green", segs=8, axis="Y")
    elif facing == 2:
        # South: the motor in the south-west corner, its drum to the south edge.
        y = ys(1.45, 0.1)
        _ground_pipe(p, [(-1.2, 1.06), (-1.2, 1.35), (-1.08, 1.45), (-0.6, 1.45), (-0.42, 1.45, 0.5),
                         (0.42, 1.45, 0.5),
                         (0.58, 1.45), (0.85, 1.45), (0.92, 1.3), (0.92, 0.96)], 0.09, dive=(True, True),
                     flanges=[(-0.6, 1.45, "X"), (0.58, 1.45, "X"), (-1.2, 1.3, "Y"), (0.92, 1.2, "Y")])
        for x in (-0.1, 0.1):
            flange(p, (x, y, 0.5), 0.15, "X", "rust_brown", 0.1)
        _ground_pipe(p, [(-1.15, 0.75), (-1.05, 0.92), (-0.85, 0.96), (-0.55, 0.96), (-0.5, 0.85), (-0.5, -0.2)],
                     0.08, dive=(True, True), flanges=[(-0.85, 0.96, "X"), (-0.5, 0.3, "Y")])
        _ground_pipe(p, [(-0.6, -0.6), (-0.12, -0.6), (-0.05, -0.72), (-0.05, -0.86)], 0.06, mat="steel")
        _ground_pipe(p, [(-0.05, -0.86), (1.45, -0.86), (1.54, -0.78), (1.54, 0.95), (1.47, 1.0), (1.41, 0.93)], 0.045,
                     mat="steel")
        _ground_pipe(p, [(-0.5, -0.86), (1.4, -0.86)], 0.07, flanges=[(0.3, -0.86, "X"), (0.95, -0.86, "X")])
        _ground_pipe(p, [(1.38, 0.62), (1.38, -0.72), (1.41, -0.84)], 0.075, dive=(True, False),
                     flanges=[(1.38, 0.5, "Y"), (1.38, -0.6, "Y")])
        _ground_pipe(p, [(-0.3, -1.0), (1.3, -1.0)], 0.06, dive=(True, True))
        _ground_pipe(p, [(-1.6, -0.22), (-1.6, -0.38), (-1.42, -0.38)], 0.025, mat="steel")
        _motor(p, (-1.48, -1.25, -0.58, -0.95, 1.2), ((-0.93, -1.3, 0.5), 0.44, 0.16), 2)
        p.slab(-1.4, -1.2, 1.2, -0.62, -0.8, 1.26, "rust_light", bevel=0.02)
    else:
        # West: the motor in the north-west corner, its drum to the west edge.
        _ground_pipe(p, [(-0.53, 1.44), (0.72, 1.44), (0.84, 1.3), (0.95, 1.2), (1.3, 1.2), (1.42, 1.1), (1.42, 0.2)],
                     0.08, dive=(False, True),
                     flanges=[(0.55, 1.44, "X"), (1.1, 1.2, "X"), (1.42, 1.0, "Y"), (1.42, 0.45, "Y")])
        _ground_pipe(p, [(-0.46, 1.16), (-0.25, 1.1), (-0.05, 0.92), (0.5, 0.92), (0.58, 0.78), (0.5, 0.65),
                         (-0.38, 0.63), (-0.47, 0.5), (-0.47, -0.12)], 0.075, dive=(False, True),
                     flanges=[(0.0, 0.92, "X"), (-0.47, 0.25, "Y")])
        _ground_pipe(p, [(-1.17, 0.56), (-1.17, -0.31)], 0.035, mat="steel")
        _ground_pipe(p, [(-1.15, -0.31), (-1.15, -0.9)], 0.09)
        _ground_pipe(p, [(-1.15, -0.31), (-1.15, -1.05), (-1.05, -1.2), (-0.9, -1.15), (-0.8, -0.95), (0.55, -0.92),
                         (0.7, -1.15), (0.92, -1.22), (1.02, -1.05), (1.02, -0.42)], 0.075, dive=(False, True),
                     flanges=[(-0.5, -0.92, "X"), (0.42, -0.92, "X"), (1.02, -0.6, "Y")])
        _ground_pipe(p, [(-1.39, -0.42), (0.04, -0.42), (0.1, -0.5), (0.1, -0.69), (0.9, -0.69)], 0.045, mat="steel")
        _ground_pipe(p, [(1.29, 0.06), (1.29, -0.72)], 0.03, mat="steel")
        _ground_pipe(p, [(1.0, 0.12), (1.29, 0.12)], 0.025, mat="steel")
        _motor(p, (-1.0, 0.58, -0.53, 1.13, 1.09), ((-1.25, 0.92, 0.5), 0.29, 0.45), 3)
        p.slab(-0.95, 0.55, 0.0, -0.6, 0.62, 0.62, "olive_dark", bevel=0.02)


def pumpjack(facing=0):
    """Factorio's pumpjack facing north, east, south or west: a green walking beam on a tall
    A-frame samson post, its horse head over the wellhead on the west, a tall gearbox on the east
    with red counterweighted cranks either side driving the beam through pitman arms; rusty pipes
    run round the ground to a red motor-pump on the output side.

    Only the ground pipes and the motor change with the direction, and Factorio draws them as
    four separate renders (pumpjack-base.png), so each direction is a model of its own
    (pumpjack, -east, -south, -west; model_library.gd FACING_MODELS picks it, PICTURES keeps it
    unturned) with the same upright parts (`_pumpjack_upright`)."""
    p = Part()
    _pumpjack_base(p, facing)
    return [p] + _pumpjack_upright()


for _i, _suffix in enumerate(PJ_FACINGS):
    model("pumpjack" + _suffix)(lambda f=_i: pumpjack(f))


# ---------------------------------------------------------------------------------------------
# Chemical plant.

CP_BELL = 0.4
CP_PULL = (0.0, 1.0)  # the chimney; the vent, pump and pipes behind
CP_NB = (-1.0, 1.1, 1.35, 0.85)


def _chemical_plant_north():
    """The north picture (chemical-plant-north-base.png): the yellow domed tank on the west, the
    tub on the east, the chimney and vent behind. Every pipe connection is a flared bell on the
    ground (`bell`), as all four pictures draw them.

    The chimney, vent, pump and pipes behind stand nearer the middle and higher than the north
    picture suggests (`pulled`: the north view is the same)."""
    p = Part()
    # Everything stands back from the edges at the ground (the base is smaller than the
    # footprint and the tanks sit on narrower plinths), as the east, south and west pictures show.
    p.slab(-0.95, -1.45, 0.0, 1.25, 0.9, 0.12, "steel_dark", bevel=0.03)
    # A low machinery block along the north edge, behind the tanks, between the input bells.
    p.slab(CP_NB[0], 0.85, 0.4, CP_NB[1], CP_NB[2], CP_NB[3], "steel_dark", bevel=0.04)
    # East: the tub, its window, the orange rim and a yellow pump housing on the lid.
    tx, ty, tr = 0.62, -0.1, 0.75
    p.cyl((tx, ty, 0.55), tr, 0.62, "steel_dark", segs=24, bevel=0.03)
    p.cyl((tx, ty, 0.13), tr - 0.15, 0.26, "steel_black", segs=20)
    p.cyl((tx, ty, 0.88), tr + 0.03, 0.1, "hazard", segs=24, bevel=0.02)
    p.cyl((tx, ty, 0.95), tr - 0.1, 0.06, "steel", segs=24)
    p.ring_band((tx, ty), tr - 0.01, tr + 0.01, 0.2, 0.62, 225, 315, "glass_dark", segs=6)
    p.slab(0.2, -0.25, 0.95, 0.9, 0.3, 1.3, "hazard", bevel=0.04)
    p.cyl((0.55, 0.0, 1.38), 0.18, 0.16, "steel", segs=12)
    p.tube((0.0, 0.02, 1.12), (1.2, 0.02, 1.12), 0.1, "hazard", segs=10)
    # West: the yellow tank with its dome.
    # Its front comes down to the ground well forward: the sprite is yellow down to there.
    lx, ly, lr = -0.8, 0.0, 0.65
    p.cyl((lx, ly, 0.89), lr, 0.88, "hazard", segs=22, bevel=0.03)
    p.cyl((lx, ly, 0.23), lr - 0.3, 0.46, "steel_black", segs=18)
    p.sphere((lx, ly, 1.33), lr, "hazard", segs=22, rings=8, hemisphere=True)
    for z in (0.7, 1.3):
        p.cyl((lx, ly, z), lr + 0.02, 0.06, "rust_brown", segs=22)
    p.cyl((lx - 0.1, ly + 0.15, 1.98), 0.14, 0.12, "steel", segs=10)
    p.pipe([(-0.95, -0.5, 1.6), (-0.55, -0.62, 1.4), (-0.3, -0.62, 1.0)], 0.16, "hazard", segs=10)
    # Behind: the chimney and the vent elbow. Like the refinery's columns they stand nearer the
    # middle and higher than the north picture suggests (`pulled`: the north view is the same).
    body, p = p, Part()
    # Behind: the chimney and the vent elbow.
    p.cyl((-0.48, 0.75, 2.0), 0.17, 2.0, "steel", segs=14)
    for z in (1.55, 2.2):
        p.cyl((-0.48, 0.75, z), 0.2, 0.06, "rust_brown", segs=14)
    p.cyl((-0.48, 0.75, 2.97), 0.19, 0.08, "steel_dark", segs=14)
    p.cyl((-0.48, 0.75, 3.0), 0.13, 0.02, "soot", segs=12)
    pulled(body, p, CP_PULL[0], [(-0.48, 0.75, 0.17)], z0=1.0)
    p = Part()
    p.pipe([(-0.08, 0.85, 1.0), (-0.08, 0.85, 2.35), (0.05, 0.75, 2.6)], 0.11, "steel_light", segs=10)
    # A pipe from beside the chimney across the top of the west tank and down into it.
    p.pipe([(-0.2, 0.55, 1.6), (-0.2, 0.55, 1.87), (-0.95, 0.55, 1.87), (-0.95, 0.3, 1.75)], 0.13, "steel_light", segs=10)
    for x in (-0.38, -0.62):
        flange(p, (x, 0.55, 1.87), 0.16, "X", "steel_dark", 0.05)
    # Middle: a grey pump between the tanks, a yellow pipe from the west tank into it.
    p.slab(-0.25, 0.25, 0.9, 0.35, 0.85, 1.5, "steel_dark", bevel=0.05)
    p.cyl((0.05, 0.55, 1.6), 0.18, 0.2, "steel", segs=12)
    # Its status light on the south face, moved with it.
    lamp = Part("anim_glow_chem_lamp")
    lamp.cyl((0.12, 0.235, 1.25), 0.06, 0.03, "lamp_green", segs=10, axis="Y")
    lamp.transform(T(0.0, -CP_PULL[1], CP_PULL[1] / COS_P))
    pulled(body, p, CP_PULL[1], [(0.05, 0.55, 0.3)], z0=0.9)
    p = body
    # North-east: a second grey pump feeding the east input, a pipe arching over to the lid.
    p.slab(0.3, 0.5, 0.6, 0.85, 1.1, 1.25, "steel_dark", bevel=0.05)
    p.cyl((0.58, 0.8, 1.32), 0.16, 0.14, "steel", segs=12)
    p.pipe([(1.0, 1.0, 1.0), (1.25, 0.6, 1.25), (1.2, 0.15, 1.15)], 0.11, "steel_light", segs=10)
    p.pipe([(-0.42, -0.3, 1.2), (-0.42, 0.35, 1.45), (0.0, 0.5, 1.55)], 0.1, "steel_light", segs=10)
    # West riser from the front up over the tank.
    p.pipe([(-1.33, -0.75, 0.5), (-1.33, -0.75, 1.35), (-1.3, -0.5, 1.55), (-1.1, -0.45, 1.65)], 0.12, "steel", segs=10)
    for z in (0.65, 1.1):
        flange(p, (-1.33, -0.75, z), 0.16, "Z", "rust_brown", 0.05)
    # Front: pipework from the west tank to the south-west port, a valve, the grey pipe down
    # from the lid, and a sight-glass pot over the south-east port.
    p.pipe([(-1.15, -0.75, 0.3), (-0.3, -0.75, 0.3), (-0.3, -0.75, 0.75)], 0.12, "steel", segs=10)
    p.pipe([(-1.0, -1.2, 0.2), (-1.0, -0.85, 0.2)], 0.12, "steel", segs=10)
    p.pipe([(0.45, -0.25, 1.0), (0.3, -0.85, 0.75), (0.0, -1.05, 0.3), (-0.5, -1.15, 0.22)], 0.13, "steel_dark", segs=10)
    p.cyl((-0.25, -1.3, 0.5), 0.1, 0.02, "lamp_red", segs=8, axis="Y")
    p.cyl((0.93, -1.0, 0.24), 0.32, 0.48, "steel_light", segs=18, bevel=0.03)
    p.cyl((0.93, -1.0, 0.49), 0.24, 0.03, "glass_dark", segs=16)
    # Pipe connections: inputs north (flanges on the tanks' backs), outputs south.
    for x in (-1.0, 1.0):
        bell(p, x, -1.45, -1, r=CP_BELL)
        bell(p, x, 1.45, 1, r=CP_BELL)
    p.cyl((1.0, 1.0, 1.35), 0.07, 0.04, "lamp_red", segs=8, axis="Y")
    return [p, lamp]


CP_FACINGS = ("", "-east", "-south", "-west")
CP_BELL_EW = 0.33


def _cp_tub(p, x, y, r, top=0.88):
    """The grey tub: a riveted drum on a dark plinth, its window to the south, the orange rim and
    a low yellow dome (the turned pictures show it over the window) with a pump housing."""
    p.cyl((x, y, (0.24 + top - 0.02) / 2), r, top - 0.26, "steel_dark", segs=24, bevel=0.03)
    p.cyl((x, y, 0.13), r - 0.15, 0.26, "steel_black", segs=20)
    p.cyl((x, y, top), r + 0.03, 0.1, "hazard", segs=24, bevel=0.02)
    p.sphere((x, y, top + 0.04), r - 0.02, "hazard", segs=22, rings=6, hemisphere=True, scale=(1, 1, 0.55))
    p.bolts_ring((x, y, top + 0.06), r - 0.06, 18)
    p.ring_band((x, y), r - 0.01, r + 0.01, 0.34, top - 0.2, 235, 305, "glass_dark", segs=6)
    for z in (0.3, top - 0.12):  # seams with rivets round the drum
        p.cyl((x, y, z), r + 0.012, 0.03, "rust_brown", segs=24)
        for k in range(14):
            a = 2 * math.pi * (k + 0.5) / 14
            p.bolt((x + (r + 0.02) * math.cos(a), y + (r + 0.02) * math.sin(a), z + 0.04), radius=0.018,
                   axis="X" if abs(math.cos(a)) > 0.7 else "Y")
    h = 0.55 * (r - 0.02)
    p.cyl((x, y, top + h + 0.05), 0.16, 0.12, "steel_dark", segs=12, bevel=0.02)
    p.cyl((x, y, top + h + 0.14), 0.09, 0.08, "steel", segs=10)


def _cp_tank(p, x, y, r, z1):
    """The yellow tank: a riveted drum on a dark foot, banded, with a dome and a nozzle on top."""
    p.cyl((x, y, (0.42 + z1) / 2), r, z1 - 0.42, "hazard", segs=22, bevel=0.03)
    p.cyl((x, y, 0.22), r - 0.25, 0.44, "steel_black", segs=18)
    p.sphere((x, y, z1), r, "hazard", segs=22, rings=8, hemisphere=True)
    for z in (0.62, z1 - 0.05):
        p.cyl((x, y, z), r + 0.02, 0.06, "rust_brown", segs=22)
    p.cyl((x - 0.1 * r, y + 0.2 * r, z1 + r - 0.04), 0.13, 0.12, "steel", segs=10)
    p.bolts_ring((x - 0.1 * r, y + 0.2 * r, z1 + r + 0.02), 0.1, 6)


def _cp_chimney(p, x, y, z0, z1, r=0.17):
    """The chimney: a steel stack banded twice, a dark rim and soot at its mouth."""
    p.cyl((x, y, (z0 + z1) / 2), r, z1 - z0, "steel", segs=14)
    for z in (z0 + 0.45 * (z1 - z0), z0 + 0.75 * (z1 - z0)):
        p.cyl((x, y, z), r + 0.03, 0.06, "rust_brown", segs=14)
    p.cyl((x, y, z1 - 0.03), r + 0.02, 0.08, "steel_dark", segs=14)
    p.cyl((x, y, z1), r - 0.04, 0.02, "soot", segs=12)
    p.cyl((x, y, z0 + 0.1), r + 0.06, 0.2, "hazard", segs=14)  # its yellow collar


def _cp_pipe(p, pts, r, mat="steel_light", flanges=()):
    p.pipe(pts, r, mat, segs=10)
    for c, axis in flanges:
        flange(p, c, r + 0.04, axis, "steel_dark", 0.05)


def _cp_ports(p, east_west):
    """The four pipe connections, flared bells on the ground at the footprint's edges: on the
    north and south edges at x = +-1 (or east and west at y = +-1 when turned)."""
    for a in (-1.0, 1.0):
        for side in (-1, 1):
            if not east_west:
                bell(p, a, side * 1.45, side, r=CP_BELL)
            else:
                # Seen side on, the east-west pictures draw them a little smaller and further out,
                # the back pair a little in from the north edge.
                q = Part()
                bell(q, 0.0, 1.5, 1, r=CP_BELL_EW, z=0.2)
                p.add_part(q, T(0.0, -0.88 if a < 0 else 1.08, 0.0) @ R("Z", -90 * side))


def _cp_lamp(x, y, z, axis="Y"):
    """The status light that flickers green while the plant works (`anim_glow_chem_lamp`), where
    the direction's chemical-plant-*-anim layer draws it."""
    lamp = Part("anim_glow_chem_lamp")
    lamp.cyl((x, y, z), 0.06, 0.03, "lamp_green", segs=10, axis=axis)
    return lamp


def _chemical_plant_turned(facing):
    """The chemical plant's east, south and west pictures: separate renders with the tub, the
    yellow tank, the chimney and the vent elsewhere, each laid out from its own picture
    (chemical-plant-<direction>-base.png, Factorio's camera: x right, y + 0.669 z up the screen
    at true proportions)."""
    p = Part()
    p.slab(-1.2, -1.0 if facing == 2 else -0.9, 0.0, 1.2, 1.1, 0.12, "steel_dark", bevel=0.03)
    # The machinery behind fills the picture out to its east and west edges.
    p.slab(-1.42, -0.45, 0.1, 1.42, 1.15, 0.95, "steel_dark", bevel=0.04)
    if facing == 1:
        # East: the tub in front, the yellow tank at the back on the west, the chimney and vent
        # at the back on the east; the connections on the east and west edges.
        p.slab(-1.2, -0.5, 0.1, 1.2, 1.15, 1.0, "steel_dark", bevel=0.04)
        _cp_tub(p, 0.1, -0.25, 0.7)
        _cp_tank(p, -0.85, 0.75, 0.42, 1.35)
        _cp_chimney(p, 0.42, 0.57, 0.9, 2.82)
        _cp_pipe(p, [(0.72, 0.42, 0.9), (0.72, 0.42, 2.45), (0.8, 0.38, 2.57), (0.88, 0.35, 2.45)], 0.12,
                 flanges=[((0.72, 0.42, 1.5), "Z"), ((0.72, 0.42, 2.2), "Z")])
        _cp_pipe(p, [(-0.75, 0.9, 1.45), (-0.62, 0.85, 1.7), (-0.35, 0.75, 1.7), (-0.15, 0.6, 1.45)], 0.13,
                 flanges=[((-0.5, 0.8, 1.72), "X")])
        _cp_pipe(p, [(1.15, -0.1, 0.25), (1.15, 0.1, 1.5), (1.05, 0.45, 1.75), (0.85, 0.6, 1.7)], 0.12,
                 flanges=[((1.15, 0.0, 0.9), "Z")])
        _cp_pipe(p, [(-1.3, -0.35, 0.2), (-1.32, -0.3, 1.3), (-1.2, 0.2, 1.55), (-1.0, 0.45, 1.5)], 0.11, "steel",
                 flanges=[((-1.32, -0.32, 0.6), "Z"), ((-1.32, -0.3, 1.05), "Z")])
        p.cyl((-1.45, -0.3, 1.2), 0.09, 0.02, "lamp_red", segs=8, axis="X")
        # Grey risers on the west between the valve pipe and the yellow pipes.
        for x, y in ((-1.05, 0.15), (-0.75, -0.05)):
            _cp_pipe(p, [(x, y, 0.9), (x, y, 1.45), (x + 0.1, y + 0.25, 1.6)], 0.1,
                     flanges=[((x, y, 1.2), "Z")])
        # Yellow pipes from the tank down past the pump to the tub's lid.
        _cp_pipe(p, [(-0.75, 0.45, 1.25), (-0.5, 0.1, 1.15), (-0.35, -0.2, 0.95)], 0.15, "hazard")
        _cp_pipe(p, [(-1.0, 0.3, 0.9), (-0.7, -0.2, 0.75), (-0.2, -0.45, 1.0)], 0.12, "hazard")
        # The grey pump between, its light on the south face.
        p.slab(-0.55, 0.25, 0.9, -0.1, 0.65, 1.7, "steel_dark", bevel=0.05)
        p.cyl((-0.33, 0.45, 1.78), 0.17, 0.16, "steel", segs=12)
        lamp = _cp_lamp(-0.33, 0.235, 1.7)
        _cp_pipe(p, [(-0.3, -0.62, 1.0), (0.95, -0.62, 1.0), (1.1, -0.5, 0.9)], 0.1,
                 flanges=[((0.0, -0.62, 1.0), "X"), ((0.55, -0.62, 1.0), "X")])
        p.cyl((0.3, -0.72, 1.0), 0.1, 0.02, "lamp_red", segs=10, axis="Y")
        p.cyl((1.0, -0.62, 0.3), 0.3, 0.6, "steel", segs=16, bevel=0.03)
        p.cyl((1.0, -0.62, 0.62), 0.32, 0.05, "steel_dark", segs=16)
        p.bolts_ring((1.0, -0.62, 0.65), 0.27, 10)
        _cp_pipe(p, [(-1.3, -0.75, 0.15), (-1.3, -0.75, 0.6), (-1.15, -0.75, 0.75), (-0.75, -0.6, 0.75)], 0.13,
                 flanges=[((-1.3, -0.75, 0.4), "Z"), ((-1.0, -0.72, 0.75), "X")])
        # A dark pipe run along the south edge under the tub.
        _cp_pipe(p, [(-1.25, -1.2, 0.18), (1.25, -1.2, 0.18)], 0.17, "steel_dark",
                 flanges=[((-0.6, -1.2, 0.18), "X"), ((0.65, -1.2, 0.18), "X")])
        p.cyl((0.25, -0.1, 0.95), 0.08, 0.02, "lamp_red", segs=8, axis="Y")
        _cp_ports(p, True)
    elif facing == 2:
        # South: the tub in front, the yellow tank on the east, the chimney in the middle with an
        # elbow over to the east; the connections on the north and south edges.
        p.slab(-1.2, -0.4, 0.1, 1.2, 1.15, 1.0, "steel_dark", bevel=0.04)
        _cp_tub(p, 0.05, -0.35, 0.62)
        _cp_tank(p, 0.88, 0.45, 0.5, 1.37)
        _cp_chimney(p, 0.17, 0.3, 0.9, 2.85)
        _cp_pipe(p, [(0.3, 0.4, 2.25), (0.85, 0.4, 2.25), (0.98, 0.45, 2.05), (1.0, 0.6, 1.7)], 0.13,
                 flanges=[((0.55, 0.4, 2.25), "X")])
        # The west: a grey drum lying east-west over the north-west connection, its ends bolted
        # rims; a big elbow with a red valve, yellow pipes.
        p.cyl((-1.05, 1.0, 1.0), 0.34, 0.62, "steel", segs=18, axis="X", bevel=0.03)
        for x in (-1.36, -0.74):
            p.cyl((x, 1.0, 1.0), 0.37, 0.05, "steel_dark", segs=18, axis="X")
            p.bolts_ring((x, 1.0, 1.0), 0.33, 12, axis="X")
        p.slab(-1.3, 0.8, 0.1, -0.8, 1.2, 0.7, "steel_dark", bevel=0.03)
        # A yellow pump housing west of the chimney with grey motor drums on top.
        p.slab(-0.95, 0.3, 0.6, -0.35, 0.75, 1.3, "hazard", bevel=0.05)
        panel(p, (-0.95, 0.3, 0.6), (-0.35, 0.75, 1.3), "-y", "hazard", rivet="steel_light")
        p.cyl((-0.65, 0.55, 1.45), 0.2, 0.36, "steel", segs=12, axis="Y", bevel=0.02)
        p.cyl((-0.65, 0.35, 1.45), 0.08, 0.04, "steel_dark", segs=10, axis="Y")
        _cp_pipe(p, [(-0.45, 0.55, 1.75), (-0.15, 0.45, 2.0), (-0.12, 0.38, 2.0), (-0.12, 0.35, 0.95)], 0.11,
                 flanges=[((-0.12, 0.35, 1.3), "Z"), ((-0.12, 0.35, 1.65), "Z")])
        for x in (0.62, 1.2):
            _cp_pipe(p, [(x, -0.12, 0.2), (x, -0.12, 1.25), (x, 0.05, 1.45)], 0.1,
                     flanges=[((x, -0.12, 0.55), "Z"), ((x, -0.12, 0.95), "Z")])
        _cp_pipe(p, [(-1.05, -0.78, 0.0), (-1.05, -0.78, 0.75), (-0.95, -0.6, 0.9)], 0.14,
                 flanges=[((-1.05, -0.78, 0.35), "Z"), ((-1.05, -0.78, 0.65), "Z")])
        _cp_pipe(p, [(-1.25, -0.6, 0.3), (-1.3, -0.3, 1.0), (-1.2, 0.3, 1.3), (-0.9, 0.5, 1.4)], 0.13,
                 flanges=[((-1.3, -0.3, 1.0), "Z")])
        p.cyl((-1.45, 0.3, 1.1), 0.09, 0.02, "lamp_red", segs=8, axis="X")
        _cp_pipe(p, [(-1.0, -0.2, 1.0), (-0.75, -0.4, 0.85), (-0.5, -0.5, 0.9)], 0.14, "hazard")
        _cp_pipe(p, [(-0.6, 0.6, 1.4), (-0.4, 0.4, 1.7), (-0.2, 0.5, 1.9)], 0.13, "steel_light")
        # A ribbed pipe across the front over the tub.
        _cp_pipe(p, [(-0.7, -0.5, 0.97), (0.65, -0.5, 0.97)], 0.1, "steel",
                 flanges=[((-0.45, -0.5, 0.97), "X"), ((-0.1, -0.5, 0.97), "X"), ((0.35, -0.5, 0.97), "X")])
        # The east front: grey and yellow pipes down to the south-east connection, a small pot.
        _cp_pipe(p, [(1.15, 0.2, 1.3), (1.2, -0.2, 0.9), (1.15, -0.8, 0.5)], 0.12, "steel_light")
        p.cyl((0.95, -0.55, 0.45), 0.2, 0.5, "hazard", segs=14, bevel=0.03)
        p.cyl((0.75, -0.55, 0.65), 0.07, 0.02, "lamp_red", segs=8, axis="Y")
        p.slab(-0.45, 0.4, 0.9, 0.05, 0.85, 1.55, "steel_dark", bevel=0.05)
        lamp = _cp_lamp(0.0, -0.95, 0.75)
        _cp_ports(p, False)
    else:
        # West: the tub in front on the west, the yellow tank on the east, the chimney and the
        # vent at the back on the west; the connections on the east and west edges.
        p.slab(-1.2, -0.5, 0.1, 1.2, 1.15, 1.0, "steel_dark", bevel=0.04)
        _cp_tub(p, -0.3, -0.25, 0.62)
        _cp_tank(p, 0.85, 0.4, 0.5, 1.2)
        _cp_chimney(p, -0.52, 0.3, 0.9, 2.94)
        _cp_pipe(p, [(-1.05, 0.5, 0.6), (-1.05, 0.5, 2.3), (-1.15, 0.5, 2.45), (-1.3, 0.45, 2.35)], 0.13,
                 flanges=[((-1.05, 0.5, 1.3), "Z"), ((-1.05, 0.5, 1.9), "Z")])
        p.cyl((-0.85, 0.45, 2.05), 0.08, 0.02, "lamp_red", segs=8, axis="Y")
        _cp_pipe(p, [(0.45, 0.6, 1.5), (0.6, 0.65, 1.7), (0.9, 0.6, 1.7), (1.05, 0.5, 1.45)], 0.15,
                 flanges=[((0.75, 0.62, 1.71), "X")])
        _cp_pipe(p, [(-0.35, 0.7, 1.2), (-0.25, 0.7, 1.35), (0.4, 0.7, 1.35)], 0.14, "steel_light",
                 flanges=[((0.05, 0.7, 1.35), "X")])
        # Yellow pipes round the west and over the tub.
        _cp_pipe(p, [(-1.28, -0.1, 0.4), (-1.28, 0.0, 0.85), (-1.0, 0.0, 0.9), (-0.3, -0.2, 1.05), (0.2, -0.3, 0.95)],
                 0.15, "hazard")
        _cp_pipe(p, [(-1.3, -0.5, 0.2), (-1.25, -0.4, 0.75), (-1.1, -0.1, 1.0)], 0.1, "steel_light")
        # The east front: two grey pipes down to the south-east, a red valve.
        for x in (0.65, 1.0):
            _cp_pipe(p, [(x, -0.95, 0.15), (x, -0.95, 1.4), (x, -0.6, 1.6)], 0.14, "steel_light",
                     flanges=[((x, -0.95, 0.5), "Z"), ((x, -0.95, 1.0), "Z")])
        p.cyl((0.45, -1.0, 0.5), 0.09, 0.02, "lamp_red", segs=8, axis="Y")
        # A grey pot at the south-west corner.
        p.cyl((-1.1, -0.75, 0.35), 0.3, 0.7, "steel", segs=16, bevel=0.03)
        p.cyl((-1.1, -0.75, 0.72), 0.2, 0.06, "steel_dark", segs=14)
        p.slab(0.15, 0.3, 0.9, 0.55, 0.65, 1.6, "steel_dark", bevel=0.05)
        lamp = _cp_lamp(0.33, 0.285, 1.3)
        _cp_ports(p, True)
    return [p, lamp]


def chemical_plant(facing=0):
    """Factorio's chemical plant facing north, east, south or west: a round grey tub with a window
    and an orange rim, a yellow domed tank, a tall chimney and a vent elbow, pumps and pipework
    over everything. Inputs connect on the edge it faces, outputs on the opposite edge, at +-1.

    Factorio's four pictures are separate renders with the parts in different places (the east
    one is laid out differently altogether), so each direction is a model of its own
    (chemical-plant, -east, -south, -west; model_library.gd FACING_MODELS picks it, PICTURES
    keeps it unturned).

    While it works the light on the grey pump flickers green (chemical-plant-*-anim, 24 frames:
    0.4 s a loop): `anim_glow_chem_lamp`, blinking once a loop."""
    return _chemical_plant_north() if facing == 0 else _chemical_plant_turned(facing)


for _i, _suffix in enumerate(CP_FACINGS):
    model("chemical-plant" + _suffix)(lambda f=_i: chemical_plant(f))


# ---------------------------------------------------------------------------------------------
# Oil refinery.

def column(p, x, y, z0, z1, r, mat, bands=(), band_mat="rust_brown", segs=18):
    """A vertical vessel with banded seams."""
    p.cyl((x, y, (z0 + z1) / 2), r, z1 - z0, mat, segs=segs, bevel=0.03)
    for z in bands:
        p.cyl((x, y, z), r + 0.025, 0.06, band_mat, segs=segs)


def domed_tank(p, x, y, z0, z1, r, mat, dome=0.5, segs=16):
    """A vertical tank with a squashed dome and a small nozzle on top."""
    p.cyl((x, y, (z0 + z1) / 2), r, z1 - z0, mat, segs=segs, bevel=0.03)
    p.sphere((x, y, z1), r, mat, segs=segs, rings=6, hemisphere=True, scale=(1, 1, dome))
    p.cyl((x, y, z1 + r * dome + 0.04), r * 0.25, 0.1, "steel_dark", segs=8)


REF_SCALE = 0.92
REF_PULL = {"mid": 1.1, "crown": 0.8, "east": 0.6}


def pulled(body, part, d, feet, z0=0.9, mat="rust_brown"):
    """Adds `part` to `body` moved `d` tiles south and as much higher as keeps it on the same
    spot in the north picture, with a stem down to the ground under each of `feet` ((x, y, r))
    from the height `z0` the part stood on."""
    lift = d / COS_P
    body.add_part(part, T(0.0, -d, lift))
    for x, y, r in feet:
        body.cyl((x, y - d, (z0 + lift) / 2), r, z0 + lift, mat, segs=16)


def toothed(part, x, y, z, r, mat, depth=0.06):
    """A gear facing north-south (its axle along Y) at (x, y, z): a disc with a tooth every
    0.09 tiles round its rim, so its turn shows."""
    part.cyl((x, y, z), r, depth, mat, segs=16, axis="Y")
    part.cyl((x, y, z), r * 0.3, depth + 0.03, "steel_dark", segs=8, axis="Y")
    teeth = max(8, round(2 * math.pi * r / 0.09))
    for k in range(teeth):
        a = 360.0 * k / teeth
        part.box((0, 0, 0), (0.045, depth, 0.05), mat, matrix=T(x, y, z) @ R("Y", a) @ T(0, 0, r + 0.02))


def bell(p, x, y, facing, r=0.4, z=0.22):
    """A pipe connection as the refinery's sprites draw it: a short flared bell lying on the
    ground, its mouth (centre `y`, facing north for `facing` 1) on the footprint's edge and its
    lower part below the ground; a pipe rises from its back into the plant."""
    d = facing
    p.cyl((x, y - d * 0.03, z), r, 0.06, "steel_dark", segs=16, axis="Y")
    p.cyl((x, y - d * 0.01, z), r * 0.8, 0.03, "soot", segs=14, axis="Y")
    p.cyl((x, y - d * 0.14, z), r * 0.93, 0.18, "brass", segs=16, axis="Y")
    p.cyl((x, y - d * 0.33, z), r * 0.8, 0.22, "steel", segs=14, axis="Y")
    p.cyl((x, y - d * 0.44, z + 0.3), r * 0.72, 0.6, "steel", segs=14)


@model("oil-refinery")
def oil_refinery():
    """Factorio's oil refinery: a rusty crowded plant on a 5x5 base. A tall distillation column
    in the middle with a pipe ring round its foot, a taller column with a railed platform at the
    north-west and a third with a big elbow pipe between them; tanks, a gear train, a sight glass
    and machinery boxes crowd the south. Crude oil and water come in on the south edge (x = +-1),
    the three products leave on the north edge (x = -2, 0, 2).

    Every pipe connection is a flared bell on the ground (`bell`), as all four pictures draw them.
    Factorio draws the refinery a little under its five tiles and with its ground stretched like
    Wube's true-proportion models (sprite_projection.py), so it's built that way.

    While it works (Factorio's anim and fire layers at 0.75 speed: 20 frames, 0.44 s a loop) the
    flare on the north-west column burns (the emissive `fire`, flickering), the gear train in
    front turns (`anim_gear_refinery_a`, `_b`, `_c`, meshing, each about its axle north-south)
    and the yoke arm below it rocks about its hub (`anim_yoke_refinery`)."""
    p = Part()
    p.slab(-2.5, -2.35, 0.0, 2.5, 2.35, 0.25, "steel_dark", bevel=0.03)
    # The bulk behind: a long rusty block the columns stand on, a lower deck in front of it.
    p.slab(-2.3, 0.7, 0.1, 2.3, 2.3, 1.0, "rust_brown", bevel=0.05)
    p.slab(-1.4, -1.0, 0.1, 1.9, 0.8, 0.75, "iron_rust", bevel=0.05)

    # The tall columns stand further forward and higher than they look: from the north the
    # picture is the same (each is moved along Factorio's line of sight, `pulled`), and the other
    # directions' pictures, drawn with the columns near the middle, fit far better.
    body = p
    p = Part()
    # Central distillation column on a ring deck, its crown of fins, a pipe ring round its foot.
    cx, cy, cr = 0.37, 0.55, 0.47
    p.cyl((cx, cy, 0.85), 0.95, 0.12, "steel_dark", segs=24, bevel=0.02)
    p.cyl((cx, cy, 0.45), 0.85, 0.7, "rust_brown", segs=24)
    column(p, cx, cy, 0.9, 3.15, cr, "rust", bands=(1.3, 1.75, 2.2, 2.65, 3.1))
    for k in range(10):
        a = 2 * math.pi * k / 10
        p.box((cx + 0.38 * math.cos(a), cy + 0.38 * math.sin(a), 3.25), (0.12, 0.08, 0.2), "rust_brown",
              rz=math.degrees(a))
    p.cyl((cx, cy, 3.2), 0.25, 0.12, "steel_dark", segs=12)
    ring = Part()
    ring.ring_band((0, 0), 0.72, 0.86, -0.07, 0.07, 0, 360, "steel", segs=24, bevel=0.02)
    p.add_part(ring, T(cx, cy, 1.05))

    # Middle column with the big elbow over to the central one.
    mx, my = -0.55, 1.3
    column(p, mx, my, 0.9, 2.55, 0.38, "copper_dull", bands=(1.4, 2.0), segs=16)
    p.pipe([(mx, my, 2.5), (mx, my, 3.15), (0.05, my - 0.05, 3.35), (0.3, my - 0.1, 3.2)], 0.2, "steel", segs=12)
    p.slab(0.0, my - 0.3, 3.25, 0.4, my + 0.1, 3.35, "steel_light", bevel=0.02)
    pulled(body, p, REF_PULL["mid"], [(cx, cy, 0.5), (mx, my, 0.38)])

    # North-west column with its railed platform.
    p = Part()
    lx, ly = -1.45, 1.25
    column(p, lx, ly, 0.9, 2.35, 0.3, "copper_dull", bands=(1.3, 1.9), segs=14)
    p.cyl((lx, ly, 2.4), 0.48, 0.07, "steel", segs=20, bevel=0.01)
    p.cyl((lx, ly, 2.9), 0.15, 1.0, "rust_brown", segs=12)
    for k in range(12):
        a = 2 * math.pi * k / 12
        p.cyl((lx + 0.22 * math.cos(a), ly + 0.22 * math.sin(a), 3.6), 0.025, 0.36, "steel", segs=4)
    p.cyl((lx, ly, 3.77), 0.24, 0.03, "steel", segs=16)
    p.cyl((lx, ly, 3.42), 0.13, 0.3, "rust", segs=10)
    # The flare's flame in the crown.
    p.cyl((lx, ly, 3.8), 0.11, 0.46, "fire", segs=8, radius_top=0.015)
    pulled(body, p, REF_PULL["crown"], [(lx, ly, 0.3)])

    # East: a column with a hooked pipe, a short drum beside it.
    p = Part()
    ex, ey = 1.75, 1.3
    column(p, ex, ey, 0.9, 2.1, 0.3, "rust", bands=(1.4,), segs=14)
    p.pipe([(ex - 0.15, ey, 2.0), (ex - 0.15, ey, 2.45), (ex - 0.5, ey - 0.3, 2.55), (1.0, 0.5, 2.2)], 0.12,
           "steel", segs=10)
    pulled(body, p, REF_PULL["east"], [(ex, ey, 0.3)])
    p = body
    domed_tank(p, 1.85, 0.25, 0.7, 1.25, 0.4, "rust_brown")
    p.pipe([(1.15, -0.1, 1.5), (1.6, -0.1, 1.55), (2.05, 0.4, 1.45)], 0.14, "steel", segs=10)

    # Middle: the sight glass, gear train and the yoke arms.
    # A rusty drum lying east-west in front of the central column.
    p.cyl((1.3, -0.5, 1.15), 0.32, 1.5, "rust_brown", segs=16, axis="X", bevel=0.03)
    for x in (0.65, 1.95):
        p.cyl((x, -0.5, 1.15), 0.35, 0.06, "rust", segs=16, axis="X")
    # The sight glass lies tilted, high at its west end.
    p.tube((-0.85, -0.1, 1.8), (0.5, -0.3, 0.98), 0.21, "brass", segs=12)
    p.tube((-0.65, -0.13, 1.68), (0.3, -0.27, 1.1), 0.22, "glass_dark", segs=12)
    p.tube((-0.85, 0.1, 1.5), (-0.85, -0.1, 1.8), 0.15, "rust_brown", segs=10)
    p.slab(-1.3, -0.7, 0.1, -0.3, 0.0, 0.95, "rust_brown", bevel=0.04)
    moving = []
    for kind, (x, z, r) in zip("abc", ((-1.0, 1.15, 0.2), (-0.7, 1.05, 0.15), (-1.15, 0.8, 0.13))):
        g = Part("anim_gear_refinery_" + kind, pivot=(x * REF_SCALE, -0.55 * REF_SCALE, z * REF_SCALE))
        toothed(g, x, -0.55, z, r, "bronze")
        moving.append(g)
    yoke = Part("anim_yoke_refinery", pivot=(-0.45 * REF_SCALE, -0.75 * REF_SCALE, 0.95 * REF_SCALE))
    yoke.beam((-1.1, -0.7, 0.85), (0.2, -0.75, 0.9), 0.14, 0.1, "steel", up=(0, 0, 1))
    moving.append(yoke)
    p.cyl((-0.45, -0.75, 0.95), 0.12, 0.08, "steel_dark", segs=10)

    # West: a big drum, a spiral blower and a grille box at the front corner.
    domed_tank(p, -1.85, -0.3, 0.1, 1.1, 0.55, "rust_brown", dome=0.25)
    p.cyl((-1.45, -0.75, 0.5), 0.08, 0.9, "steel", segs=8)
    p.slab(-2.35, -1.9, 0.1, -1.5, -1.0, 0.7, "rust_brown", bevel=0.04)
    p.cyl((-1.9, -1.9, 0.45), 0.32, 0.12, "steel_dark", segs=14, axis="Y")
    p.slab(-2.3, -2.17, 0.1, -1.55, -1.85, 0.32, "steel_dark", bevel=0.02)
    for k in range(5):
        p.slab(-2.25, -2.19, 0.13 + k * 0.035, -1.6, -2.17, 0.15 + k * 0.035, "steel_light")

    # South: tanks over the inputs and a machinery box at the south-east corner.
    p.slab(-1.55, -2.17, 0.1, -0.5, -1.4, 0.4, "rust_brown", bevel=0.04)
    domed_tank(p, -1.0, -1.85, 0.4, 1.0, 0.46, "rust", dome=0.6)
    domed_tank(p, -0.06, -2.0, 0.1, 0.85, 0.2, "copper_dull", dome=0.7, segs=12)
    domed_tank(p, 0.93, -1.85, 0.1, 0.72, 0.43, "olive_dark", dome=0.5)
    p.slab(1.65, -2.15, 0.1, 2.3, -1.25, 0.95, "rust_brown", bevel=0.04)
    p.slab(1.6, -1.8, 0.3, 1.66, -1.4, 0.75, "steel_dark")

    # Factorio draws the refinery a little smaller than its five tiles: the plant is built at
    # full size and shrunk, the pipe connections stay on their tiles.
    body, p = p, Part()
    p.add_part(body, Matrix.Diagonal((REF_SCALE, REF_SCALE, REF_SCALE, 1.0)))
    for part in moving:
        part.transform(Matrix.Diagonal((REF_SCALE, REF_SCALE, REF_SCALE, 1.0)))
    # Pipe connections: inputs south, outputs north, each a flared bell lying on the ground with
    # its mouth on the edge, half sunk.
    for x in (-1.0, 1.0):
        bell(p, x, -2.45, -1)
    for x in (-2.0, 0.0, 2.0):
        bell(p, x, 2.45, 1)
    return [p] + moving
