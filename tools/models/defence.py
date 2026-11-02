"""Gun turret and stone wall."""

import math

from mathutils import Vector

from kit import Part, R, S, T, model, rng


@model("gun-turret")
def gun_turret():
    """Factorio's gun turret. The base is static: a cast drum with four splayed corner brackets.
    The head (`anim_turret_head`, pivot on the turret's axis) turns, barrels north at rest: a
    toothed slewing ring, a dark cradle, the blue-grey receiver with a six-barrel gatling, a
    rusty breech box behind, the ammo box and its brass belt on the left."""
    p = Part()
    p.prism([(0.66 * math.cos(math.radians(a)), 0.66 * math.sin(math.radians(a))) for a in range(0, 360, 45)],
            0.0, 0.14, "steel_dark", bevel=0.03, matrix=R("Z", 22.5))
    p.cyl((0, 0, 0.42), 0.58, 0.7, "steel_dark", segs=16, bevel=0.03)
    p.ring_band((0, 0), 0.48, 0.66, 0.7, 0.78, 0, 360, "steel", segs=16, bevel=0.01)
    p.cyl((0, 0, 0.76), 0.48, 0.03, "soot", segs=16)
    for k in range(10):
        a = 200 + k * 14
        r = math.radians(a)
        p.box((0.59 * math.cos(r), 0.59 * math.sin(r), 0.42), (0.05, 0.04, 0.5), "steel", rz=a)
    # Corner buttresses: pairs of plates from the drum's rim down to a foot on the ground.
    # They splay more east-west than north-south, as in the sprite.
    profile = [(0.45, 0.0), (0.98, 0.0), (0.98, 0.14), (0.7, 0.84), (0.45, 0.84)]
    for a in (32, 148, 212, 328):
        r = math.radians(a)
        c, s_ = math.cos(r), math.sin(r)
        turn = R("Z", a - 90)
        for off in (-0.1, 0.1):
            p.side_prism(profile, off - 0.035, off + 0.035, "steel_dark", bevel=0.015, matrix=turn)
        p.box((0.86 * c, 0.86 * s_, 0.05), (0.26, 0.32, 0.1), "steel_black", rz=a, bevel=0.02)
        # Bolts through both plates.
        for d, z in ((0.6, 0.68), (0.76, 0.42), (0.9, 0.14)):
            p.tube((d * c - 0.15 * s_, d * s_ + 0.15 * c, z), (d * c + 0.15 * s_, d * s_ - 0.15 * c, z), 0.03,
                   "steel_light", segs=6)

    # The base's corner brackets splay a little wider east-west in the sprite (fit_cells.py --fit
    # scale); the head is a little wider too (below).
    p.transform(S(1.085, 1.017, 1.0))

    head = Part("anim_turret_head", pivot=(0.0, 0.0, 0.65))
    # The ring on four arms, its teeth round the inside (the sprite's ring is smooth outside).
    head.ring_band((0, 0), 0.657, 0.763, 1.06, 1.16, 0, 360, "bronze", segs=24)
    for k in range(32):
        a = 360.0 * k / 32
        r = math.radians(a)
        head.box((0.66 * math.cos(r), 0.66 * math.sin(r), 1.11), (0.07, 0.05, 0.08), "steel_light", rz=a)
    for a in (45, 135, 225, 315):
        r = math.radians(a)
        head.beam((0.15 * math.cos(r), 0.15 * math.sin(r), 1.3), (0.64 * math.cos(r), 0.64 * math.sin(r), 1.12),
                  0.09, 0.07, "rust_brown", bevel=0.01)
        head.bolt((0.6 * math.cos(r), 0.6 * math.sin(r), 1.18), radius=0.03)
    head.cyl((0, 0, 1.06), 0.22, 0.16, "steel_dark", segs=12)
    # Cradle and receiver.
    head.slab(-0.29, -0.34, 1.02, 0.29, 0.34, 1.8, "rust_brown", bevel=0.08)
    for x in (-0.09, 0.09):
        for z in (1.35, 1.52):
            head.bolt((x, -0.31, z), axis="Y", radius=0.035)
    head.slab(-0.27, -0.3, 1.68, 0.27, 0.36, 2.17, "blue_steel", bevel=0.04)
    # Breech box behind, with its slot.
    head.slab(-0.2, -0.91, 1.76, 0.2, -0.12, 2.14, "rust_brown", bevel=0.03)
    head.slab(-0.11, -0.93, 1.86, 0.11, -0.89, 2.02, "soot")
    for z in (1.84, 1.95, 2.06):
        head.bolt((0.21, -0.77, z), axis="X", radius=0.022)
    # The gatling: six barrels round an axle, two bands.
    bz = 1.96
    head.cyl((0, 0.36, bz), 0.15, 0.1, "steel_dark", segs=10, axis="Y")
    head.cyl((0, 0.67, bz), 0.05, 0.62, "steel_dark", segs=6, axis="Y")
    for k in range(6):
        r = math.radians(k * 60)
        head.cyl((0.13 * math.cos(r), 0.67, bz + 0.13 * math.sin(r)), 0.045, 0.62, "steel_light", segs=6, axis="Y")
    for y, rb in ((0.6, 0.17), (0.92, 0.19)):
        head.cyl((0, y, bz), rb, 0.07, "rust_brown", segs=12, axis="Y", bevel=0.01)
    # Ammo box on the left with brass rounds on top and the belt down to the ring; a small
    # box on the right.
    head.slab(-0.43, -0.74, 1.81, -0.16, -0.41, 2.08, "rust_brown", bevel=0.03)
    for k in range(4):
        for x in (-0.36, -0.23):
            head.cyl((x, -0.7 + k * 0.08, 2.15), 0.035, 0.16, "brass", segs=6)
    belt = [Vector(v) for v in ((-0.44, -0.5, 1.95), (-0.66, -0.3, 1.8), (-0.72, -0.05, 1.55), (-0.52, 0.15, 1.3),
                                 (-0.3, 0.2, 1.2))]
    for a, b in zip(belt, belt[1:]):
        steps = max(2, int((b - a).length / 0.075))
        for i in range(steps):
            q = a + (b - a) * (i / steps)
            head.beam(q - Vector((0.06, 0, 0)), q + Vector((0.06, 0, 0)), 0.045, 0.045, "brass")
    head.slab(0.19, -0.12, 2.03, 0.45, 0.34, 2.38, "rust_brown", bevel=0.03)
    for y in (0.02, 0.2):
        head.bolt((0.46, y, 2.2), axis="X", radius=0.03)
    # Placed and sized against all 64 of the head's rotation frames (tools/models/turntable.py):
    # it sits a little higher and is a little smaller than built. Factorio's raising animation
    # lifts it only about 0.02 tiles, so the client keeps it where it is.
    head.transform(S(1.03, 1.017, 1.0) @ T(0.014, -0.006, 0.105) @ S(0.972, 0.964, 1.032) @ T(0, 0, -0.25))
    return [p, head]


@model("stone-wall")
def stone_wall():
    """A wall pillar of rough blocks under a concrete cap, nearly a full tile so a line of
    walls reads as one wall."""
    p = Part()
    r = rng(5)
    mats = ("stone", "stone", "stone_light", "stone_dark")
    p.slab(-0.49, -0.49, 0.0, 0.49, 0.49, 0.12, "stone_dark", bevel=0.03)
    p.slab(-0.42, -0.42, 0.12, 0.42, 0.42, 0.96, "stone_dark")
    z = 0.12
    for course in range(3):
        h = 0.28
        split_x = course % 2 == 0
        for i in range(2):
            lo, hi = -0.47 + i * 0.47, -0.47 + (i + 1) * 0.47
            inset = r.uniform(0.0, 0.025)
            mat = mats[r.randrange(len(mats))]
            if split_x:
                p.slab(lo + 0.008, -0.47 + inset, z, hi - 0.008, 0.47 - inset, z + h - 0.012, mat, bevel=0.035)
            else:
                p.slab(-0.47 + inset, lo + 0.008, z, 0.47 - inset, hi - 0.008, z + h - 0.012, mat, bevel=0.035)
        z += h
    p.slab(-0.49, -0.49, z, 0.49, 0.49, z + 0.1, "concrete", bevel=0.03)
    p.slab(-0.36, -0.36, z + 0.1, 0.36, 0.36, z + 0.14, "concrete", bevel=0.02)
    return p
