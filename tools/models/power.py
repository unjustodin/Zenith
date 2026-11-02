"""Electric poles and steam power.

Boiler (3x2) facing north: steam leaves by the north side, water pipes connect east and west on
the south row, and the fire door faces south. Steam engine (3x5) facing north: long axis
north-south, with pipe connections at both ends.
"""

import math

import facings
from kit import MATERIALS, Part, R, T, model

MATERIALS.update({
    "tank_grey": ("9c9a90", 0.65, 0.3, None, 0),   # the steam engine's weathered tanks
})


@model("small-electric-pole")
def small_electric_pole():
    """Factorio's small pole: a tall wooden post (east of the tile's centre, as in the sprite) in a
    steel sleeve with a brace down to a foot, a steel cap, and a steel crossarm reaching west with
    three white insulators."""
    p = Part()
    px, py = 0.29, 0.05
    p.slab(-0.08, py - 0.12, 0.0, 0.36, py + 0.12, 0.05, "steel_dark", bevel=0.015)
    p.cyl((px, py, 0.5), 0.12, 1.0, "blue_steel", segs=8, bevel=0.02)
    for z in (0.12, 0.92):
        p.cyl((px, py, z), 0.135, 0.06, "steel_dark", segs=8)
    p.beam((px - 0.08, py, 0.62), (-0.06, py, 0.06), 0.06, 0.05, "steel_dark", up=(1, 0, 1))
    p.cyl((px, py, 2.22), 0.095, 2.5, "wood_orange", segs=8, radius_top=0.08)
    p.cyl((px, py, 3.5), 0.1, 0.14, "steel", segs=8)
    # Crossarm, with a brace from the post.
    p.beam((-0.46, py, 3.66), (0.0, py, 3.6), 0.07, 0.06, "steel_dark")
    p.beam((0.0, py, 3.6), (0.44, py, 3.66), 0.07, 0.06, "steel_dark")
    p.beam((px, py, 3.25), (0.0, py, 3.58), 0.04, 0.04, "steel_dark", up=(1, 0, 1))
    for x, z in ((-0.42, 3.68), (0.0, 3.62), (0.4, 3.68)):
        p.cyl((x, py, z + 0.06), 0.03, 0.08, "steel", segs=6)
        p.cyl((x, py, z + 0.14), 0.06, 0.06, "ceramic", segs=8)
        p.cyl((x, py, z + 0.2), 0.05, 0.06, "ceramic", segs=8)
        p.cyl((x, py, z + 0.25), 0.03, 0.05, "copper", segs=6)
    p.cyl((-0.21, py - 0.04, 3.6), 0.012, 0.42, "copper", segs=4, axis="X")
    return p


def flange(p, center, radius, axis, mat="steel_dark"):
    p.cyl(center, radius, 0.06, mat, segs=12, axis=axis, bevel=0.01)


PIPE_Z = 0.34  # height of pipe connections, so neighbouring flanges line up
NB_Y, NB_Z, NB_R = 0.5, 0.3, 0.3  # the boiler's lower body behind the drum
EL_DZ = 0.05  # how far the boiler's steam elbow rises above its base


def _rivets(p, points, mat="steel_light", radius=0.018, axis="Z"):
    for q in points:
        p.bolt(q, mat, radius, 0.02, axis)


def _rivet_arc(p, centre, r, a0, a1, count, axis="X", mat="steel_light", radius=0.018):
    """Rivets along an arc of a drum lying along `axis` ("X": in the y-z plane)."""
    cx, cy, cz = centre
    for i in range(count):
        a = math.radians(a0 + (a1 - a0) * i / max(1, count - 1))
        if axis == "X":
            q = (cx, cy + r * math.cos(a), cz + r * math.sin(a))
        else:
            q = (cx + r * math.cos(a), cy + r * math.sin(a), cz)
        p.sphere(q, radius, mat, segs=6, rings=3)


def _boiler_groups():
    """The boiler facing north, as groups of parts (facings.py fits each to every picture)."""
    g = {name: Part() for name in ("drum", "west", "chimney", "steam", "lowbody", "water_w",
                                   "water_e", "east")}
    # Feet, base box and the drum.
    p = g["drum"]
    for x in (-0.8, -0.05, 0.72):
        p.slab(x - 0.09, -0.8, 0.0, x + 0.09, 0.3, 0.08, "steel_black", bevel=0.02)
        p.slab(x - 0.11, -0.84, 0.0, x + 0.11, -0.7, 0.04, "steel_black")
    p.slab(-0.95, -0.88, 0.06, 0.72, 0.42, 0.56, "olive_dark", bevel=0.04)
    # Riveted seams along the base box's top edge.
    _rivets(p, [(x, -0.89, 0.5) for x in (-0.85, -0.6, -0.35, -0.1, 0.15, 0.4, 0.62)], axis="Y")
    dy, dz, dr = -0.3, 0.64, 0.62
    p.cyl((0, dy, dz), dr, 1.12, "olive_steel", segs=20, axis="X", bevel=0.03)
    for sx in (-1, 1):
        p.cyl((sx * 0.56, dy, dz), dr + 0.03, 0.06, "olive_dark", segs=20, axis="X")
        p.bolts_ring((sx * 0.6, dy, dz), dr - 0.04, 12, mat="steel_light", axis="X", radius=0.02)
        # A row of rivets down each seam, as the sprite's riveted plates.
        _rivet_arc(p, (sx * 0.5, dy, dz), dr + 0.005, 10, 170, 9)
    # A band round the middle of the drum, riveted, behind the grate.
    p.cyl((0, dy, dz), dr + 0.012, 0.05, "olive_dark", segs=20, axis="X")
    # The grate door on the drum's sloping front, square to the surface.
    phi = math.radians(58)
    gy, gz = dy - dr * math.cos(phi), dz + dr * math.sin(phi)
    tilt = T(0, gy, gz) @ R("X", -(90 - math.degrees(phi)))
    p.box((0, -0.02, 0), (0.6, 0.06, 0.5), "olive_dark", bevel=0.05, matrix=tilt)
    p.box((0, -0.04, 0), (0.5, 0.04, 0.4), "olive_steel", bevel=0.03, matrix=tilt)
    p.box((0, -0.05, 0), (0.38, 0.04, 0.3), "fire", matrix=tilt)
    for x in (-0.1, 0.0, 0.1):
        p.box((x, -0.07, 0), (0.045, 0.04, 0.3), "olive_dark", matrix=tilt)
    for x in (-0.27, -0.09, 0.09, 0.27):
        for z in (-0.22, 0.22):
            p.cyl((0, 0, 0), 0.02, 0.02, "steel_light", segs=6, matrix=tilt @ T(x, -0.06, z) @ R("X", 90))
    for z in (-0.08, 0.08):
        for x in (-0.27, 0.27):
            p.cyl((0, 0, 0), 0.02, 0.02, "steel_light", segs=6, matrix=tilt @ T(x, -0.06, z) @ R("X", 90))
    # Front details: a round hatch, a vent box, a bolted plate and the copper pipe runs.
    # (on the drum and base box: they move with it)
    p.cyl((-0.66, -0.98, 0.2), 0.11, 0.05, "olive_steel", segs=10, axis="Y")
    p.cyl((-0.66, -1.0, 0.2), 0.06, 0.03, "olive_dark", segs=8, axis="Y")
    p.bolts_ring((-0.66, -1.0, 0.2), 0.085, 6, axis="Y", radius=0.015)
    p.slab(0.12, -1.0, 0.08, 0.34, -0.94, 0.3, "olive_steel", bevel=0.02)
    p.slab(0.16, -1.0, 0.14, 0.3, -0.99, 0.24, "soot")
    for x in (0.18, 0.28):
        p.slab(x - 0.03, -1.01, 0.14, x + 0.03, -1.0, 0.24, "steel_dark")
    p.slab(-0.38, -0.96, 0.12, 0.06, -0.92, 0.32, "olive_steel", bevel=0.015)
    _rivets(p, [(x, -0.965, z) for x in (-0.34, 0.02) for z in (0.16, 0.28)], axis="Y", radius=0.014)
    p.pipe([(-0.5, -0.99, 0.42), (0.56, -0.99, 0.42), (0.56, -0.99, 0.12)], 0.035, "copper_dull", segs=6)
    for x in (-0.3, 0.0, 0.3):
        p.cyl((x, -0.99, 0.42), 0.045, 0.04, "steel_dark", segs=6, axis="X")
    p.pipe([(-0.5, -0.95, 0.1), (-0.5, -0.95, 1.0), (-0.5, -0.3, 1.3)], 0.035, "copper_dull", segs=6)
    p.pipe([(-0.42, -0.94, 0.42), (-0.42, -0.94, 0.85)], 0.03, "copper_dull", segs=6)
    p.pipe([(0.62, -0.95, 0.85), (0.66, -0.95, 1.08), (0.66, -0.4, 1.22)], 0.035, "copper_dull", segs=6)
    # A thin steel pipe looped over the drum, front to back, beside each seam (the sprite's).
    for x in (-0.44, 0.44):
        p.pipe([(x, -0.92, 0.6), (x, -0.86, 1.05), (x, -0.5, 1.3), (x, 0.05, 1.32)], 0.025, "steel_light", segs=6)
    # West: a column of pipes beside the drum.
    p = g["west"]
    p.slab(-0.95, -0.95, 0.06, -0.56, 0.1, 0.95, "olive_dark", bevel=0.05)
    p.cyl((-0.78, -0.8, 0.55), 0.15, 0.9, "olive_steel", segs=10)
    p.sphere((-0.78, -0.8, 1.0), 0.15, "olive_steel", segs=10, rings=4, hemisphere=True)
    for z in (0.3, 0.7):
        p.cyl((-0.78, -0.8, z), 0.17, 0.04, "olive_dark", segs=10)
    p.pipe([(-0.66, -0.93, 0.15), (-0.66, -0.93, 1.05), (-0.66, -0.4, 1.12)], 0.04, "copper_dull", segs=6)
    _rivets(p, [(-0.94, y, 0.9) for y in (-0.8, -0.55, -0.3, -0.05)], radius=0.015)
    # The chimney: its housing at the north-west corner and the stack on it.
    p = g["chimney"]
    p.cyl((-1.12, 0.4, 0.62), 0.3, 0.9, "olive_steel", segs=14, bevel=0.03)
    p.sphere((-1.12, 0.4, 1.07), 0.3, "olive_steel", segs=14, rings=6, hemisphere=True, scale=(1, 1, 0.5))
    p.cyl((-1.12, 0.4, 0.4), 0.32, 0.05, "olive_dark", segs=14)
    p.bolts_ring((-1.12, 0.4, 0.43), 0.29, 10, radius=0.015)
    p.cyl((-1.18, 0.45, 1.38), 0.12, 1.1, "olive_steel", segs=12, radius_top=0.13)
    p.cyl((-1.18, 0.45, 1.25), 0.15, 0.08, "olive_dark", segs=12)
    p.cyl((-1.18, 0.45, 1.92), 0.15, 0.06, "olive_dark", segs=12)
    p.cyl((-1.18, 0.45, 1.95), 0.1, 0.01, "soot", segs=10)
    p.pipe([(-1.3, 0.1, 1.3), (-1.45, -0.1, 1.1), (-1.25, -0.25, 0.9)], 0.05, "olive_dark", segs=6)
    p.pipe([(-0.9, 0.35, 1.0), (-0.9, 0.35, 1.25), (-0.6, 0.3, 1.25)], 0.035, "copper_dull", segs=6)
    # Steam out: a tall elbow behind the drum, down to a flange on the north edge.
    p = g["steam"]
    oy, orad = 0.58, 0.36
    p.cyl((0, oy, 0.6 + EL_DZ / 2), orad, 0.6 + EL_DZ, "olive_steel", segs=16, bevel=0.02)
    p.sphere((0, oy, 0.9 + EL_DZ), orad, "olive_steel", segs=16, rings=8, hemisphere=True, scale=(1, 1, 0.75))
    p.cyl((0, oy, 0.85 + EL_DZ), orad + 0.06, 0.08, "olive_dark", segs=16)
    p.bolts_ring((0, oy, 0.9 + EL_DZ), orad + 0.02, 12, radius=0.018)
    p.cyl((0, (oy + 0.93) / 2, PIPE_Z), 0.26, 0.93 - oy, "olive_steel", segs=14, axis="Y")
    flange(p, (0, 0.95, PIPE_Z), 0.32, "Y")
    p.bolts_ring((0, 0.985, PIPE_Z), 0.27, 10, axis="Y", radius=0.02)
    # The sprites' rounded lower body behind the drum, under the steam elbow (it fills the
    # north side seen from the east, south and west).
    g["lowbody"].cyl((-0.05, NB_Y, NB_Z), NB_R, 1.8, "olive_dark", segs=16, axis="X", bevel=0.04)
    _rivet_arc(g["lowbody"], (-0.7, NB_Y, NB_Z), NB_R + 0.005, 0, 180, 6)
    _rivet_arc(g["lowbody"], (0.6, NB_Y, NB_Z), NB_R + 0.005, 0, 180, 6)
    # Water in and out: flared stubs on the south row, east and west.
    for sx in (-1, 1):
        p = g["water_e" if sx > 0 else "water_w"]
        p.cyl((sx * 1.2, -0.5, PIPE_Z), 0.22, 0.5, "olive_steel", segs=14, axis="X",
              radius_top=0.31 if sx > 0 else 0.22)
        if sx < 0:
            p.cyl((sx * 1.2, -0.5, PIPE_Z), 0.31, 0.5, "olive_steel", segs=14, axis="X", radius_top=0.22)
        flange(p, (sx * 1.45, -0.5, PIPE_Z), 0.34, "X")
        p.bolts_ring((sx * 1.485, -0.5, PIPE_Z), 0.29, 10, axis="X", radius=0.02)
        flange(p, (sx * 1.02, -0.5, PIPE_Z), 0.25, "X", mat="olive_dark")
    # East: a pump housing on the water line and a big pipe up past the drum.
    p = g["east"]
    p.cyl((1.0, -0.1, 0.62), 0.3, 0.75, "olive_dark", segs=14, bevel=0.03)
    p.sphere((1.0, -0.1, 1.0), 0.3, "olive_dark", segs=14, rings=6, hemisphere=True, scale=(1, 1, 0.6))
    p.pipe([(0.8, -0.78, 0.1), (0.8, -0.78, 1.0), (0.85, -0.3, 1.18), (1.05, 0.1, 1.15)], 0.15, "olive_steel", segs=10)
    for z in (0.35, 0.75):
        p.cyl((0.8, -0.78, z), 0.19, 0.06, "olive_dark", segs=10)
        p.bolts_ring((0.8, -0.78, z + 0.03), 0.17, 8, radius=0.015)
    p.slab(0.66, -0.98, 0.0, 0.94, -0.7, 0.16, "olive_dark", bevel=0.02)
    _rivets(p, [(x, -0.99, 0.08) for x in (0.72, 0.88)], axis="Y", radius=0.015)
    return g


# Each direction's fit (facings.py): Factorio renders the boiler's four directions separately
# (boiler-N/E/S/W-idle.png). Fitted to each picture's silhouette.
BOILER_FITS = {
    0: {
        "chimney": (0.01, -0.12, 0, 1, 1, 1),
        "drum": (-0.13, 0.12, 0, 1, 1, 1),
        "east": (0.04, 0, 0, 0.97, 0.97, 0.97),
        "lowbody": (0, -0.23, 0, 1, 1, 1),
        "steam": (0, -0.1, 0, 1, 1, 1),
        "water_e": (0, 0, 0.07, 1, 1, 1),
        "water_w": (0, 0, 0.06, 1, 1, 1),
        "west": (0, 0.08, 0, 1, 1, 1),
    },
    1: {
        "chimney": (0.12, 0.17, 0, 1, 1, 1),
        "drum": (-0.04, 0.12, 0, 1.06, 1.06, 1.315),
        "east": (0.16, 0, 0, 1.082, 1.082, 1.082),
        "lowbody": (0.22, -0.04, 0, 1, 1, 1),
        "steam": (0, 0.04, 0.01, 1, 1, 1),
        "water_e": (0, 0, 0.2, 1, 1, 1),
        "water_w": (0, 0, 0.12, 1, 1, 1),
        "west": (0, 0.06, 0, 1, 1, 1),
    },
    2: {
        "chimney": (0, -0.17, 0, 1, 1, 1),
        "drum": (0.23, 0.22, 0, 0.955, 0.955, 0.895),
        "east": (0.12, 0.24, -0.01, 1, 1, 1),
        "lowbody": (-0.02, 0, 0, 1, 1, 1),
        "steam": (0, -0.09, 0.02, 1, 1, 1),
        "water_e": (0, 0, -0.01, 1, 1, 1),
        "water_w": (0, 0, -0.01, 1, 1, 1),
        "west": (0, 0.25, 0, 0.91, 0.91, 0.91),
    },
    3: {
        "chimney": (0.03, -0.25, 0, 1, 1, 1),
        "drum": (0.24, 0.13, 0, 1.12, 1.12, 1.24),
        "east": (-0.01, -0.07, 0, 1, 1, 1),
        "steam": (0, -0.01, -0.01, 1, 1, 1),
        "water_w": (0, 0, 0.17, 1, 1, 1),
        "west": (0, 0.08, 0, 1, 1, 1),
    },
}


def boiler(facing=0):
    """Factorio's boiler: an olive drum lying east-west with the fire grate on its sloping
    south face, a tall elbow taking steam out to the north, flared water stubs east and west on
    the south row, the chimney at the north-west corner, riveted seams, pipes and copper lines
    over everything. One model per direction (boiler, -east, -south, -west), each fitted to its
    own picture.

    The fire behind the grate's bars is the emissive `fire` (Factorio's boiler-*-fire, 64 frames
    at half speed: 2.1 s a loop): lit and flickering while the boiler burns, dark when idle."""
    return facings.variant(_boiler_groups(), facing, BOILER_FITS[facing])


for _facing, _suffix in enumerate(facings.SUFFIXES):
    model("boiler" + _suffix)(lambda f=_facing: boiler(f))


def gear(part, centre, radius, width, mat, teeth=14, axis="X"):
    """A toothed wheel facing along `axis` ("X" only: the steam engine's gears face west)."""
    cx, cy, cz = centre
    part.cyl(centre, radius, width, mat, segs=16, axis="X", bevel=0.01)
    part.cyl(centre, radius * 0.35, width + 0.04, "steel_dark", segs=8, axis="X")
    for i in range(teeth):
        a = 360.0 * i / teeth
        part.box((0, 0, 0), (width * 0.8, 0.07, 0.08), mat,
                 matrix=T(cx, cy, cz) @ R("X", a) @ T(0, 0, radius + 0.03))


def _steam_engine_groups(flywheel_kind):
    """The steam engine facing north, as groups (facings.py), and its flywheel."""
    g = {name: Part() for name in ("frame", "legs_e", "legs_w", "tank_s", "tank_m", "tank_n", "tank_pipes", "end_s",
                                   "end_n", "generator", "gears", "pipes_n", "pipes_s", "east")}
    cx, rt = 0.18, 0.68          # tank centre line and radius
    z0, z1 = 0.95, 1.95          # tank body
    tanks = (-1.5, 0.0, 1.5)
    # The frame under the tanks: a dark rusty bed the whole length, solid to the ground.
    p = g["frame"]
    p.slab(-0.55, -2.05, 0.18, 0.95, 2.05, 0.82, "rust_brown", bevel=0.04)
    p.slab(-0.62, -2.15, 0.62, 1.02, 2.15, 0.78, "steel_dark", bevel=0.03)
    _rivets(p, [(x, y, 0.785) for x in (-0.58, 0.98) for y in (-1.9, -1.2, -0.4, 0.4, 1.2, 1.9)], radius=0.02)
    for y in (-2.05, -0.75, 0.75, 2.05):
        p.slab(-0.6, y - 0.08, 0.0, 1.0, y + 0.08, 0.2, "steel_black")
    # Splayed legs on both sides, crossing in X's along the length (the sprite's "VVV").
    for sx, x0, x1, ys in ((1, 0.85, 1.4, (-1.45, -0.75, 0.0, 0.75, 1.5, 2.1)), (-1, -0.5, -1.12, (-1.55, -0.52, 0.52, 1.55))):
        p = g["legs_e" if sx > 0 else "legs_w"]
        for y in ys:
            for dy in ((-0.25,) if sx > 0 else (-0.5, 0.5)):
                p.beam((x0, y, 0.85), (x1, y + dy, 0.04), 0.13, 0.11, "rust_brown")
                p.slab(x1 - 0.1, y + dy - 0.12, 0.0, x1 + 0.1, y + dy + 0.12, 0.06, "steel_black")
        p.beam((x0 + sx * 0.3, -1.95, 0.45), (x0 + sx * 0.3, 1.95, 0.45), 0.09, 0.1, "rust_brown")
        if sx > 0:
            # (the west side's legs stand apart, open between: the H picture shows the ground there)
            p.beam((x1 - sx * 0.05, -1.95, 0.2), (x1 - sx * 0.05, 1.95, 0.2), 0.14, 0.32, "rust_brown")
    # The tanks: dark bowl, a fat rusty collar, the weathered body, rounded lid.
    for y, tank in zip(tanks, ("tank_s", "tank_m", "tank_n")):
        p = g[tank]
        z1 = 2.04 if y else 1.95  # the end tanks stand taller in the sprite
        p.cyl((cx, y, 0.86), rt - 0.08, 0.22, "steel_dark", segs=16, radius_top=rt)
        p.cyl((cx, y, 1.0), rt + 0.06, 0.16, "rust_brown", segs=20, bevel=0.05)
        p.bolts_ring((cx, y, 1.08), rt + 0.03, 16, radius=0.018)
        p.cyl((cx, y, (z0 + z1) / 2 + 0.05), rt, z1 - z0 - 0.1, "tank_grey", segs=20, bevel=0.02)
        p.cyl((cx, y, z1 + 0.02), rt, 0.12, "tank_grey", segs=20, radius_top=rt - 0.08, bevel=0.03)
        p.cyl((cx, y, z1 + 0.1), rt - 0.08, 0.06, "tank_grey", segs=16, radius_top=rt - 0.2)
        p.ring_band((cx, y), rt - 0.01, rt + 0.015, z1 - 0.08, z1 - 0.02, 0, 360, "rust_orange", segs=16)
        p.ring_band((cx, y), rt - 0.01, rt + 0.015, 1.12, 1.17, 0, 360, "rust_orange", segs=16)
        # Valve gear on the lid: a bolted plate, a blue-grey stack and a rocker frame.
        top = z1 + 0.13
        p.cyl((cx, y, top + 0.03), 0.24, 0.06, "steel_dark", segs=14)
        p.bolts_ring((cx, y, top + 0.07), 0.2, 6, radius=0.02)
        p.cyl((cx, y, top + 0.16), 0.08, 0.22, "blue_steel", segs=8)
        p.cyl((cx, y, top + 0.3), 0.1, 0.06, "steel_dark", segs=8)
        for dy in (-0.09, 0.09):
            p.slab(cx + 0.08, y + dy - 0.02, top, cx + 0.14, y + dy + 0.02, top + 0.78, "steel_dark")
        p.slab(cx - 0.08, y - 0.11, top + 0.72, cx + 0.16, y + 0.11, top + 0.78, "steel")
        p.cyl((cx + 0.11, y, top + 0.81), 0.035, 0.12, "steel_dark", segs=6, axis="Y")
        p.beam((cx - 0.06, y, top + 0.75), (cx - 0.12, y - 0.05, top + 0.2), 0.03, 0.03, "steel_light")
        p.cyl((cx - 0.12, y - 0.05, top + 0.45), 0.04, 0.12, "steel_dark", segs=6)
        p.pipe([(cx + 0.12, y - 0.12, top + 0.05), (cx + 0.32, y - 0.2, top + 0.05),
                (cx + 0.36, y - 0.2, top + 0.32), (cx + 0.12, y, top + 0.36)], 0.03, "steel_light", segs=6)
        # Steam line from each lid down the west side, into the mechanism.
        p.pipe([(cx - 0.18, y + 0.1, top), (cx - 0.45, y + 0.2, top - 0.25),
                (-0.6, y + 0.25, 1.55), (-0.62, y + 0.25, 1.15)], 0.055, "steel_light", segs=8)
        p.cyl((-0.6, y + 0.25, 1.5), 0.075, 0.05, "steel_dark", segs=8)
    # A pipe joining the tanks between their collars, west and east.
    p = g["tank_pipes"]
    for x in (-0.55, 0.92):
        p.pipe([(x, -2.0, 1.15), (x, 2.0, 1.15)], 0.07, "steel_light", segs=8, joints=False)
    # Pipe housings and flanged connections at both ends (they reach into the next tile, as the
    # sprite's do).
    for sy in (-1, 1):
        p = g["end_n" if sy > 0 else "end_s"]
        p.slab(-0.48, sy * 2.0, 0.0, 0.48, sy * 2.45, 0.85, "blue_steel", bevel=0.05)
        _rivets(p, [(x, sy * 2.46, z) for x in (-0.4, 0.4) for z in (0.12, 0.75)], axis="Y", radius=0.02)
        p.bolts_ring((0, sy * 2.46, 0.45), 0.36, 8, axis="Y", radius=0.02)
        p.cyl((0, sy * 2.55, 0.45), 0.38, 0.2, "steel", segs=16, axis="Y")
        flange(p, (0, sy * 2.66, 0.45), 0.44, "Y")
        p.bolts_ring((0, sy * 2.69, 0.45), 0.4, 12, axis="Y", radius=0.02)
        p.pipe([(-0.22, sy * 2.2, 0.78), (-0.22, sy * 2.2, 1.02), (0.22, sy * 2.2, 1.02), (0.22, sy * 2.2, 0.78)],
               0.08, "steel_light", segs=8)
        # A valve on the pipe beside the housing, its handwheel facing east.
        p.pipe([(0.48, sy * 2.15, 0.6), (0.6, sy * 2.15, 0.6), (0.6, sy * 2.3, 0.4)], 0.06, "steel_light", segs=8)
        p.cyl((0.68, sy * 2.3, 0.4), 0.17, 0.04, "steel", segs=14, axis="X")
        p.cyl((0.7, sy * 2.3, 0.4), 0.05, 0.06, "steel_dark", segs=8, axis="X")
    # West, north: the ribbed generator lying north-south, with a grille of pipes beyond it.
    p = g["generator"]
    gx, gy, gz, gr = -1.0, 0.85, 0.95, 0.46
    p.cyl((gx, gy, gz), gr, 1.3, "rust_brown", segs=16, axis="Y", bevel=0.03)
    for k in range(7):
        p.cyl((gx, gy - 0.54 + k * 0.18, gz), gr + 0.05, 0.05, "steel_dark", segs=14, axis="Y")
    for y in (gy - 0.68, gy + 0.68):
        p.cyl((gx, y, gz), gr * 0.55, 0.1, "blue_steel", segs=12, axis="Y", bevel=0.015)
        p.bolts_ring((gx, y, gz), gr * 0.4, 6, axis="Y", radius=0.02)
    p.slab(gx - 0.45, gy - 0.7, 0.0, gx + 0.45, gy + 0.7, 0.5, "rust_brown", bevel=0.03)
    for y in (gy - 0.5, gy - 0.25, gy, gy + 0.25, gy + 0.5):
        p.pipe([(-1.45, y, 0.2), (-1.45, y, 1.0), (-1.3, y, 1.12)], 0.035, "steel_light", segs=6)
    p.pipe([(-1.45, gy - 0.65, 1.02), (-1.45, gy + 0.7, 1.02)], 0.05, "steel_light", segs=6, joints=False)
    # North-west: a tall pipe column with a round tank on it; north-east, a pipe up into the tank.
    p = g["pipes_n"]
    p.pipe([(-0.55, 2.05, 0.3), (-0.55, 2.05, 1.9), (-0.3, 1.9, 2.1)], 0.08, "steel_light", segs=8)
    p.sphere((-0.8, 1.8, 1.65), 0.2, "steel_light", segs=10, rings=6)
    p.cyl((-0.8, 1.8, 1.25), 0.14, 0.7, "steel", segs=10)
    p.pipe([(0.98, 1.75, 0.6), (0.98, 1.75, 1.95), (0.75, 1.65, 2.05)], 0.07, "steel_light", segs=8)
    p.pipe([(0.92, 1.9, 0.9), (1.25, 1.9, 0.9), (1.25, 1.9, 0.2)], 0.06, "steel_light", segs=8)
    # West, south: the gear train on a dark block, gears facing west, a crank and its rod.
    p = g["gears"]
    p.slab(-1.2, -1.25, 0.15, -0.55, 0.15, 1.1, "steel_dark", bevel=0.04)
    _rivets(p, [(-1.21, y, z) for y in (-1.15, 0.05) for z in (0.25, 1.0)], axis="X", radius=0.02)
    for (y, z, r, mat) in ((-0.05, 0.62, 0.26, "bronze"), (-0.95, 1.0, 0.2, "steel"),
                           (-0.35, 1.0, 0.16, "steel"), (-1.05, 0.38, 0.16, "bronze")):
        gear(p, (-1.26, y, z), r, 0.08, mat, teeth=int(10 + r * 20))
    p.beam((-1.36, -1.15, 0.35), (-1.36, 0.1, 0.35), 0.07, 0.07, "steel_dark", up=(1, 0, 0))
    p.beam((-1.36, -0.55, 0.62), (-1.36, 0.3, 1.1), 0.06, 0.12, "steel", up=(1, 0, 0))
    p.pipe([(-1.38, -1.2, 1.25), (-1.38, 0.2, 1.25), (-1.1, 0.3, 1.35)], 0.05, "steel_light", segs=6)
    # The piston's crosshead guide and rod, from the middle tank's foot to the crank.
    p.slab(-1.32, -0.2, 1.18, -1.22, 0.55, 1.26, "steel_dark")
    p.cyl((-1.3, 0.2, 1.22), 0.03, 0.7, "steel_light", segs=6, axis="Y")
    # South-west: a tall thin pipe, as at the north-east.
    p = g["pipes_s"]
    p.pipe([(-1.25, -2.0, 0.2), (-1.25, -2.0, 1.85)], 0.07, "steel_light", segs=8)
    p.sphere((-0.95, -1.75, 1.6), 0.2, "steel_light", segs=10, rings=6)
    p.cyl((-0.95, -1.75, 1.2), 0.14, 0.7, "steel", segs=10)
    p.pipe([(-0.75, -1.75, 1.65), (-0.5, -1.65, 1.95)], 0.06, "steel_light", segs=8)
    # South-east: a pipe column like the north-west one.
    p.pipe([(0.6, -2.05, 0.8), (0.6, -2.05, 1.85), (0.45, -1.9, 2.0)], 0.07, "steel_light", segs=8)
    # East: a dark box beside the middle tank, an exhaust pipe by the south one.
    p = g["east"]
    p.slab(0.88, 0.25, 0.7, 1.3, 0.95, 1.45, "steel_dark", bevel=0.04)
    _rivets(p, [(1.31, y, z) for y in (0.32, 0.88) for z in (0.78, 1.37)], axis="X", radius=0.018)
    p.cyl((1.02, -1.15, 1.0), 0.24, 0.9, "steel_dark", segs=14, bevel=0.03)
    p.sphere((1.02, -1.15, 1.45), 0.24, "steel_dark", segs=14, rings=5, hemisphere=True, scale=(1, 1, 0.5))
    p.cyl((1.02, -1.15, 0.75), 0.26, 0.05, "rust_brown", segs=14)
    p.cyl((0.95, -0.82, 1.5), 0.065, 1.0, "steel", segs=10)
    p.cyl((0.95, -0.82, 2.0), 0.08, 0.05, "steel_dark", segs=10)
    # The flywheel: the big gear at the head of the train (turns about the east-west axis).
    fy, fz = -0.6, 0.62
    wheel = Part(flywheel_kind, pivot=(-1.38, fy, fz))
    gear(wheel, (-1.38, fy, fz), 0.4, 0.08, "bronze", teeth=18)
    for a in range(0, 180, 60):
        wheel.box((-1.38, fy, fz), (0.1, 0.06, 0.7), "steel_dark", matrix=_about_x(fy, fz, a))
    wheel.cyl((-1.44, fy, fz), 0.09, 0.06, "steel_dark", segs=10, axis="X")
    # The crank pin and the start of its connecting rod, turning with the wheel.
    wheel.cyl((-1.46, fy + 0.25, fz), 0.04, 0.06, "steel_light", segs=6, axis="X")
    return g, {"gears": [wheel]}


# Each picture's fit (facings.py): Factorio draws the steam engine with two renders,
# steam-engine-V.png for north and south and steam-engine-H.png for east and west. The H picture
# shows the engine turned to face west (its gears to the south), so the east model is the north
# one turned three quarters; its flywheel turns about the north-south axis.
STEAM_ENGINE_FITS = {
    0: {
        "east": (0.1, 0, 0, 1, 1, 1.03),
        "end_s": (0, -0.295, 0, 1.015, 1.375, 1.015),
        "frame": (-0.16, 0, 0, 0.985, 0.985, 0.989),
        "gears": (0.03, 0.05, 0, 1.03, 0.76, 0.97),
        "generator": (-0.07, 0.22, 0.06, 0.993, 1, 1),
        "legs_e": (0.01, -0.05, 0, 1, 1, 1.004),
        "legs_w": (0, 0, 0, 0.835, 1.004, 1),
        "pipes_n": (0, -0.025, -0.02, 1.022, 1, 1.015),
        "pipes_s": (0.3, 0, 0, 0.992, 1, 1),
        "tank_n": (0.06, 0.155, 0, 1.03, 1, 1),
    },
    3: {
        "east": (-0.28, -0.17, -0.08, 1, 1, 1),
        "end_n": (0, -0.16, -0.015, 1, 0.884, 1),
        "end_s": (0, 0.16, 0, 1, 0.884, 1),
        "flue": (0, -0.04, 0, 1, 1, 0.827),
        "frame": (-0.26, 0.005, 0, 1.06, 1.06, 1),
        "gears": (-0.3, -0.08, -0.08, 1, 1, 1),
        "generator": (-0.005, 0.12, 0, 1.12, 1.12, 1.12),
        "legs_e": (0, 0, 0, 1, 1.06, 1),
        "legs_w": (-0.3, -0.04, 0, 1.221, 1, 0.944),
        "pipes_n": (0.005, -0.055, 0, 1, 1, 1),
        "pipes_s": (-0.01, 0, 0, 1, 1, 1),
        "tank_m": (-0.09, -0.045, 0, 0.993, 0.993, 0.963),
        "tank_n": (-0.22, 0, -0.02, 1, 1, 1),
        "tank_pipes": (-0.18, 0, 0, 1, 1, 1),
        "tank_s": (-0.135, -0.095, -0.08, 1, 1, 0.985),
    },
}


def steam_engine(facing=0):
    """Factorio's steam engine (steam-engine-V/H.png): three weathered grey tanks in a row along
    the length, each with a rusty collar at its foot and valve gear on its lid, standing on a
    dark rusty frame with splayed legs; on the west side a ribbed generator (north) and a dense
    gear train with the flywheel (south), on the east a dark box and an exhaust pipe; blue-grey
    pipe housings with flanged connections at both ends."""
    kind = "anim_spin_flywheel" if facing % 2 == 0 else "anim_spin_flywheel_ns"
    groups, anims = _steam_engine_groups(kind)
    if facing % 2:
        # The H picture draws a tall thin flue at the engine's north end (west, as it is drawn)
        # that the V picture hides behind the north tank.
        p = groups["flue"] = Part()
        p.cyl((0.95, 2.1, 1.3), 0.06, 2.6, "steel", segs=10)
        p.cyl((0.95, 2.1, 2.6), 0.075, 0.06, "steel_dark", segs=10)
        p.cyl((0.95, 2.1, 2.62), 0.045, 0.01, "soot", segs=8)
        p.cyl((0.95, 2.1, 1.0), 0.13, 0.5, "steel_dark", segs=10, bevel=0.02)
    return facings.variant(groups, facing, STEAM_ENGINE_FITS[facing], anims=anims)


model("steam-engine")(lambda: steam_engine(0))
model("steam-engine-east")(lambda: steam_engine(3))


def _about_x(y, z, degrees):
    """Rotation about the east-west axis through (*, y, z)."""
    return T(0, y, z) @ R("X", degrees) @ T(0, -y, -z)

