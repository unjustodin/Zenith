"""Models for entities the client drew as boxes (the placeholder audit): the lane splitter and the
1x1 loader (Factorio draws them with the splitter's and loader's pictures, smaller), legacy rails
(1.1's rail pieces, kept in old saves), the landing pad's unloading bay, the landed cargo pod,
Gleba's planted tree, Fulgora's sunken ruins and Gleba's stromatolites.

Placed by hand against their sprites seen from Factorio's camera (48 degrees down: a height z
shows z * 0.67 up the screen), the first variation of each, and compared with part_colors.py's
--debug pictures.
"""

import math

from mathutils import Vector

import belts
import kit
import rails
import rocket
from kit import Part, S, model
from space_kit import blob, stalk

kit.MATERIALS.update({
    "paint_extractor_red": ("a5483a", 0.6, 0.35, None, 0),   # the unloading bay's red housings
    "paint_extractor_green": ("5f6a3e", 0.65, 0.3, None, 0),  # its olive side tanks
    "paint_pod_panel": ("7fa6c2", 0.4, 0.3, None, 0),         # the landed pod's opened blue panels
    "bark_planted": ("6b4a32", 0.9, 0.0, None, 0),
    "leaf_planted": ("3f6a2c", 0.8, 0.0, None, 0),
    "leaf_planted_light": ("5f8a3a", 0.8, 0.0, None, 0),
    "rust_ruin_green": ("5c6a55", 0.8, 0.45, None, 0),        # the sunken ruins' green-pink iron bands
    "rock_stromatolite_copper": ("c98a2a", 0.85, 0.0, None, 0),
    "rock_stromatolite_copper_moss": ("6f6a26", 0.9, 0.0, None, 0),
    "rock_stromatolite_iron": ("7f8ea0", 0.85, 0.0, None, 0),
    "rock_stromatolite_iron_moss": ("4e5530", 0.9, 0.0, None, 0),
})


def _scaled(result, sx, sy, sz):
    parts = kit.as_parts(result)
    for p in parts:
        p.transform(S(sx, sy, sz))
        p.pivot = Vector((p.pivot.x * sx, p.pivot.y * sy, p.pivot.z * sz))
    return parts


# ---------------------------------------------------------------------------------------------
# Belt odds: Factorio draws both with their bigger relatives' pictures, smaller.

@model("lane-splitter")
def lane_splitter():
    """The lane splitter (1x1): Factorio draws the splitter's picture at half its size
    (transport-belts.lua) on a belt, so a whole belt with the splitter's housing at half its
    width and depth astride it. Its east and west pictures stand taller than half the splitter's
    (the housing reaches 0.86 tiles up the screen), so it keeps 0.8 of its height."""
    p = belts.straight_section(Part(), chevrons=(-0.37, 0.37), bolts=False)
    gears = []
    housing = belts.splitter_housing(Part(), gears)
    housing.transform(S(0.5, 0.5, LANE_SPLITTER_Z))
    p.add_part(housing)
    for g in gears:
        g.transform(S(0.5, 0.5, LANE_SPLITTER_Z))
        g.pivot = Vector((g.pivot.x * 0.5, g.pivot.y * 0.5, g.pivot.z * LANE_SPLITTER_Z))
    return [p] + gears


LANE_SPLITTER_Z = 0.8


@model("loader-1x1")
def loader_1x1():
    """The 1x1 loader: Factorio draws it with the 1x2 loader's plate (loader-structure.png), which
    overhangs its tile by 0.4 at each end; here the loader's plated hopper kept on its tile."""
    return rocket.loader_hopper(0.98)


# ---------------------------------------------------------------------------------------------
# Legacy rails (Factorio 1.1's pieces, rail-pictures.lua): the straight piece is the 2.x one;
# the diagonal piece crosses one corner of its 2x2 cell (its middle at (0.5, -0.5) for direction
# 2, deconstruction_marker_positions); the curve runs 3 tiles across and 7 along, from straight
# north at (1, 4) to the diagonal at (-2, -3), fitted to legacy-curved-rail's metals sprite.
_S2 = 1 / math.sqrt(2)
rails.PIECES.update({
    "legacy-straight": rails.PIECES["straight"],
    "legacy-straight-ne": ((0, -1), (_S2, _S2), (1, 0), (_S2, _S2), None),
    "legacy-curved": ((1, 4), (0, -1), (-2, -3), (-_S2, -_S2), 2.8),
    "legacy-curved-ne": ((-1, 4), (0, -1), (2, -3), (_S2, -_S2), 2.8),
})
for _piece in ("legacy-straight", "legacy-curved"):
    for _suffix in ("", "-ne"):
        model(_piece + "-rail" + _suffix)(lambda piece=_piece + _suffix: rails.rail_piece(piece))


# ---------------------------------------------------------------------------------------------
# Landing pad unloading bay (2.1, cargo-hubs/extractor): a cargo bay whose north part carries a
# red machine block crowded with pipes, boxes and an elbow chute, olive tanks on its flanks; the
# south of its 4x4 is a low dark floor between the bay's side frames. Facing north, the block's
# front shows at the sprite's bottom edge (about y = 1 south) and its back 1.5 high.

@model("landing-pad-unloading-bay")
def landing_pad_unloading_bay():
    p = Part()
    # Floor of the 4x4 bay (Blender y north: the machine stands from y -1 to 3).
    p.slab(-1.95, -1.95, 0.0, 1.95, 1.95, 0.22, "steel_dark", bevel=0.04)
    p.slab(-1.7, -1.8, 0.22, 1.7, -0.9, 0.26, "steel_black")
    for sx in (-1, 1):  # the side frames of the bay's open south part
        p.slab(min(sx * 1.6, sx * 1.95), -1.95, 0.0, max(sx * 1.6, sx * 1.95), -0.6, 0.62, "paint_extractor_red",
               bevel=0.04)
    # The machine block.
    p.slab(-1.85, -0.95, 0.2, 1.75, 2.9, 1.05, "paint_extractor_red", bevel=0.06)
    p.slab(-1.6, 0.2, 1.05, 1.5, 2.8, 1.45, "paint_extractor_red", bevel=0.05)
    p.slab(-1.9, -0.9, 0.95, 1.8, -0.75, 1.0, "steel_dark")
    for x in (-1.2, -0.4, 0.4, 1.2):  # riveted panel seams on the front
        p.slab(x - 0.03, -0.98, 0.3, x + 0.03, -0.94, 0.95, "steel_dark")
    # Olive tanks on the flanks, as the sprite's edges.
    for sx in (-1, 1):
        p.cyl((sx * 1.78, 1.6, 0.65), 0.32, 1.6, "paint_extractor_green", segs=12, axis="Y", bevel=0.03)
        for y in (1.0, 2.2):
            p.cyl((sx * 1.78, y, 0.65), 0.34, 0.06, "steel_dark", segs=12, axis="Y")
    # On top: the brown elbow chute in the east, a grey drum and gear in the west, boxes and pipes.
    p.pipe([(0.9, 2.3, 1.45), (0.9, 1.4, 1.9), (0.9, 0.3, 1.5), (0.9, -0.6, 1.05)], 0.28, "rust_brown", segs=12)
    p.cyl((0.9, -0.6, 1.0), 0.34, 0.12, "steel_dark", segs=12)
    p.cyl((-0.9, 1.9, 1.75), 0.38, 0.6, "steel", segs=14, axis="X", bevel=0.03)
    p.cyl((-1.25, 0.3, 1.1), 0.36, 0.12, "steel_dark", segs=16, axis="Y")
    p.cyl((-1.25, 0.24, 1.1), 0.2, 0.06, "steel_light", segs=10, axis="Y")
    p.slab(-0.6, 2.1, 1.45, 0.25, 2.75, 1.95, "paint_extractor_red", bevel=0.04)
    p.slab(-0.45, 2.2, 1.95, 0.1, 2.6, 2.05, "steel_light")
    p.slab(-0.3, 0.5, 1.45, 0.4, 1.3, 1.75, "steel", bevel=0.03)
    p.slab(1.25, 1.9, 1.45, 1.7, 2.7, 1.8, "paint_extractor_red", bevel=0.03)
    for x in (-0.15, 0.3, -1.55):
        p.pipe([(x, 2.8, 1.5), (x, 0.95, 1.5), (x, -0.9, 0.9)], 0.07, "steel_dark", segs=6)
    for x in (-1.5, -0.6, 0.3, 1.2):
        p.bolt((x, -0.97, 0.9), "steel_light", axis="Y")
    return p


# ---------------------------------------------------------------------------------------------
# The landed cargo pod (cargo-pod-container, pod-landing.png): the pod standing on the ground
# with its three blue panels opened out flat round its foot.

@model("cargo-pod-container")
def cargo_pod_container():
    """A battered, open cargo capsule with a dark plated shell, raised hatch hardware and three
    blue deployment panels. Its landing sprite is much more industrial than the clean white pod
    used in flight, so this is built separately rather than scaled from rocket.cargo_pod()."""
    p = Part()
    hull = Part()
    # Heavy thruster skirt and lower shell. The stepped bands make the base read as machinery
    # from the default isometric view instead of a smooth white cylinder.
    hull.cyl((0, 0, 0.22), 0.54, 0.42, "rust_brown", segs=16, radius_top=0.68)
    hull.ring_band((0, 0), 0.57, 0.72, 0.38, 0.52, 0, 360, "steel_dark", segs=20)
    hull.cyl((0, 0, 1.35), 0.68, 1.78, "olive_dark", segs=12, bevel=0.04)
    hull.ring_band((0, 0), 0.62, 0.74, 0.62, 0.72, 0, 360, "rust_brown", segs=16)
    hull.ring_band((0, 0), 0.62, 0.74, 2.06, 2.18, 0, 360, "steel_dark", segs=16)

    # Faceted armor panels, dark rails and exposed seams around the shell.
    for k in range(8):
        a = math.radians(45 * k + 22.5)
        c, s = math.cos(a), math.sin(a)
        hull.box((0.65 * c, 0.65 * s, 1.32), (0.11, 0.47, 1.43),
              "steel_dark" if k % 2 else "rust_brown", bevel=0.025, rz=45 * k + 22.5)
        hull.box((0.712 * c, 0.712 * s, 1.35), (0.035, 0.31, 1.2),
              "olive_dark" if k % 2 else "steel", bevel=0.015, rz=45 * k + 22.5)
        hull.beam((0.56 * c, 0.56 * s, 0.57), (0.56 * c, 0.56 * s, 2.02),
               0.055, 0.045, "steel_light")
    for z in (0.82, 1.18, 1.57, 1.91):
        hull.ring_band((0, 0), 0.69, 0.735, z, z + 0.045, 0, 360,
                    "steel_dark" if z in (0.82, 1.57) else "rust_brown", segs=16)

    # The exposed top is a thick hatch rim with an inset dark opening, bolt circle and crooked
    # aerial. This replaces the round white dome that was too unlike the sprite's open cap.
    hull.ring_band((0, 0), 0.18, 0.66, 2.15, 2.32, 0, 360, "steel", segs=20)
    hull.cyl((0, 0, 2.18), 0.18, 0.10, "steel_black", segs=12)
    for k in range(12):
        a = math.radians(k * 30)
        hull.bolt((0.57 * math.cos(a), 0.57 * math.sin(a), 2.33), "steel_light", radius=0.025)
    hull.tube((-0.24, -0.05, 2.3), (-0.31, -0.07, 2.85), 0.045, "steel_dark", segs=6)
    hull.sphere((-0.32, -0.07, 2.96), 0.13, "steel_light", segs=10, rings=5)
    # Small irregular service boxes and hoses break up the side profile at gameplay distance.
    hull.slab(-0.61, -0.34, 0.72, -0.48, 0.02, 1.13, "steel_dark", bevel=0.035)
    hull.slab(0.47, -0.56, 0.94, 0.68, -0.31, 1.52, "rust_brown", bevel=0.035)
    hull.pipe([(0.44, -0.48, 1.75), (0.28, -0.69, 1.46), (0.45, -0.57, 1.04)],
           0.045, "steel_light", segs=6)
    hull.transform(S(0.78, 0.78, 0.88))
    p.add_part(hull)

    # Three opened solar/landing panels lie flat around the foot; reinforce their hinges and
    # give each panel a darker perimeter so the long spokes survive at small screen sizes.
    for a in (192, 290, 80):
        r = math.radians(a)
        c, s = math.cos(r), math.sin(r)
        mid = 1.15
        p.box((c * mid, s * mid, 0.045), (1.4, 0.38, 0.045), "paint_pod_panel", bevel=0.01, rz=a)
        p.box((c * mid, s * mid, 0.015), (1.46, 0.44, 0.035), "steel_dark", rz=a)
        p.beam((c * 0.45, s * 0.45, 0.18), (c * 1.75, s * 1.75, 0.12),
               0.065, 0.05, "steel_dark")
        p.box((c * 0.45, s * 0.45, 0.14), (0.2, 0.22, 0.17), "steel_dark", rz=a, bevel=0.02)
    return p


# ---------------------------------------------------------------------------------------------
# Gleba's planted tree (the agricultural tower's Nauvis tree, plants.lua "planted-tree"): a
# short, twisting brown trunk splitting into crooked boughs under a dense round dark green crown.

@model("tree-plant")
def tree_plant():
    # Grown along its sprite's skeleton like the Gleba plants (gleba.skeleton_plant).
    import gleba
    return gleba.plant("tree-plant", [("leaf_planted_light", "6b8058"), ("leaf_planted", "4f5a3a"),
                                       ("bark_planted", "30301d")], budget=3400)


# ---------------------------------------------------------------------------------------------
# Fulgora's sunken ruins: half-drowned rust-pink brickwork. The big one is an arc of carved
# brick under a green iron band (a height field fitted to its sprite); the medium tall one a
# small cylindrical tank standing in a cage of four rusty posts.

@model("fulgora-sunk-ruin-big")
def fulgora_sunk_ruin_big():
    """The south-west of a wide round brick tower, sunk to its knees: carved brick blocks on the
    outside under a riveted band of green-pink iron, highest in the north-west and low in the
    south-east, the tower's middle to the north-east; across it, the far wall is only broken
    plates (sunken-ruin-big-1)."""
    # A height field fitted to the sprite's silhouette (space_nature.heightfield, 1/16-tile
    # columns): a thick wall following the arc. The top 0.3 tiles on screen of every column are
    # the iron band and the broken plates behind it, the rest the brick; the client's part colours
    # carry the sprite's carved blocks and patches onto it (part_colors_overrides/placeholders.py).
    import space_nature
    from space_profiles import PROFILES
    name = "fulgora-sunk-ruin-big"
    tops = {math.floor(x / 0.0625): max(r[0] for r in runs) for x, runs in PROFILES[name]}
    sin_p, cos_p = math.sin(math.radians(48)), math.cos(math.radians(48))

    def band(x, y, z):
        top = tops.get(math.floor(x / 0.0625))
        return "rust_ruin_green" if top is not None and sin_p * y + cos_p * z > top - 0.3 else None
    return space_nature.heightfield(name, 1.0, space_nature.walls(4.0), "concrete_ruin", jitter=0.04, seed=31,
                                    step=0.0625, mat_fn=band)


@model("fulgora-sunk-ruin-medium-tall")
def fulgora_sunk_ruin_medium_tall():
    """A sunken tank in a hexagonal cage (sunken-ruin-medium-0004), measured on the sprite with
    screen up = 0.743 y + 0.669 z: a ribbed skirt sunk into the water under a round bulb with a
    broken neck, a little west of the cage's middle; six rusty posts round it on a hexagon 0.9
    across its corners, joined by a ring at the water and one higher up; the front-west post a
    tall bent pole leaning out west, the east one hooked at its top."""
    return _sunk_medium()


def _sunk_medium(hx=-0.16, hy=-0.22, hr=0.78, tx=-0.15, ty=-0.07, sink=0.13, ring_z=1.0, dr=0.15, lean=0.25, back=0.62,
                 he=1.95, hne=1.3, hnw=1.15, hw=1.1, hse=1.05):
    # Defaults fitted to the sprite's outline. Its dark water round the deck is drawn opaque enough to
    # count as outline; the deck stops at the posts all the same (dr), as the sprite's iron floor does.
    p = Part()
    # The tank: ribbed skirt, a ring of holes, the bulb, the broken neck.
    z0 = -sink
    p.cyl((tx, ty, z0 + 0.42), 0.42, 0.84, "rust_ruin_green", segs=16, radius_top=0.3)
    for k in range(12):
        a = 2 * math.pi * (k + 0.5) / 12
        p.box((tx + 0.37 * math.cos(a), ty + 0.37 * math.sin(a), z0 + 0.36), (0.05, 0.07, 0.7), "rust_ruin",
              rz=math.degrees(a))
    p.cyl((tx, ty, z0 + 0.86), 0.31, 0.08, "rust_ruin", segs=16)
    p.sphere((tx - 0.06, ty, z0 + 1.08), 0.34, "rust_ruin_green", segs=16, rings=8, scale=(1.0, 1.0, 1.15))
    p.cyl((tx - 0.08, ty, z0 + 1.52), 0.22, 0.2, "rust_ruin_green", segs=14, radius_top=0.26)
    for k in range(7):  # the broken rim
        a = math.radians(k * 51 + 10)
        p.box((tx - 0.08 + 0.24 * math.cos(a), ty + 0.24 * math.sin(a), z0 + 1.68), (0.06, 0.12, 0.12 + 0.08 * (k % 3)),
              "rust_ruin", rz=k * 51 + 100)
    # The cage: posts on a hexagon (corner 0 east, counter-clockwise), with their heights.
    corners = [(hx + hr * math.cos(math.radians(60 * k)), hy + hr * math.sin(math.radians(60 * k))) for k in range(6)]
    heights = (he, hne, hnw, hw, None, hse)  # E, NE, NW, W, SW (the bent pole), SE
    # The cage's floor: a dark iron deck just above the water, a little past the posts.
    p.prism([(hx + (hr + dr) * math.cos(math.radians(60 * k)), hy + (hr + dr) * math.sin(math.radians(60 * k)))
             for k in range(6)], -0.05, 0.03, "concrete_ruin_dark")
    for k, (x, y) in enumerate(corners):
        if heights[k] is not None:
            p.tube((x, y, -0.2), (x, y, heights[k]), 0.065, "rust_ruin", segs=8)
        nx, ny = corners[(k + 1) % 6]
        p.tube((x, y, 0.05), (nx, ny, 0.05), 0.06, "rust_ruin", segs=6)
        p.cyl((x, y, 0.05), 0.08, 0.1, "rust_ruin", segs=8)  # the joints
    # The upper ring, between the posts that reach it, and a brace up to the east post's top.
    for k in (5, 0, 3):
        x, y = corners[k]
        nx, ny = corners[(k + 1) % 6]
        p.tube((x, y, ring_z), (nx, ny, ring_z), 0.06, "rust_ruin", segs=6)
    w, sw, se, e = corners[3], corners[4], corners[5], corners[0]
    p.tube((w[0], w[1], ring_z), (sw[0], sw[1], ring_z), 0.06, "rust_ruin", segs=6)
    p.tube((sw[0], sw[1], ring_z), (se[0], se[1], ring_z), 0.06, "rust_ruin", segs=6)
    mid = ((se[0] + sw[0]) / 2 + 0.25, (se[1] + sw[1]) / 2, ring_z)
    p.cyl(mid, 0.09, 0.08, "rust_ruin", segs=8)
    p.tube(mid, (e[0] - 0.1, e[1] + 0.35, 1.6), 0.06, "rust_ruin", segs=6)
    # The bent pole from the south-west corner, leaning out west and back.
    p.pipe([(sw[0], sw[1], -0.2), (sw[0] - lean * 0.35, sw[1] + back * 0.25, 1.1),
            (sw[0] - lean * 0.8, sw[1] + back * 0.75, 2.1), (sw[0] - lean, sw[1] + back, 2.55)], 0.065, "rust_ruin",
           segs=8)
    # The hook on top of the east post.
    p.pipe([(e[0], e[1], heights[0]), (e[0] - 0.12, e[1], heights[0] + 0.15), (e[0] - 0.22, e[1], heights[0] + 0.05)],
           0.045, "rust_ruin", segs=6)
    return p


# ---------------------------------------------------------------------------------------------
# Gleba's stromatolites: lumpy domes of layered rock, copper-orange or iron blue-grey, mossy
# olive in their folds.

def _stromatolite(name, mat, moss, lumps, seed):
    """A cluster of rounded lumps (x, y, radius, height) with mossy olive ones in their folds."""
    p = Part()
    rnd = kit.rng(seed)
    for k, (x, y, r, h) in enumerate(lumps):
        blob(p, (x, y, h * 0.5), r, mat, segs=10, rings=7, scale=(1.0, 0.95, h / r * 0.55), seed=seed + k, wobble=0.18)
        for j in range(3):  # knobbly growths on top, like the sprite's bubbly crust
            a = rnd.uniform(0, math.tau)
            q = (x + r * 0.5 * math.cos(a), y + r * 0.5 * math.sin(a), h * 0.82)
            blob(p, q, r * 0.42, mat, segs=7, rings=5, seed=seed * 3 + k * 7 + j, wobble=0.2)
    for k in range(len(lumps)):
        x0, y0 = lumps[k][0], lumps[k][1]
        x1, y1 = lumps[(k + 1) % len(lumps)][0], lumps[(k + 1) % len(lumps)][1]
        blob(p, ((x0 + x1) / 2, (y0 + y1) / 2, 0.08), 0.22, moss, segs=7, rings=4, scale=(1.3, 1.3, 0.6),
             seed=seed + 40 + k, wobble=0.25)
    return p


# Lumps placed over the first variation's silhouette (the profiles above).
model("copper-stromatolite")(lambda: _stromatolite(
    "copper-stromatolite", "rock_stromatolite_copper", "rock_stromatolite_copper_moss",
    [(-0.6, 0.1, 0.36, 0.75), (-0.15, 0.25, 0.32, 0.7), (0.2, 0.05, 0.3, 0.65), (-0.35, -0.35, 0.3, 0.55),
     (0.15, -0.4, 0.26, 0.45), (-0.85, -0.25, 0.22, 0.4)], 3))
model("iron-stromatolite")(lambda: _stromatolite(
    "iron-stromatolite", "rock_stromatolite_iron", "rock_stromatolite_iron_moss",
    [(-0.35, 0.15, 0.38, 0.85), (0.15, 0.35, 0.36, 1.1), (0.4, -0.05, 0.32, 0.9), (-0.55, -0.3, 0.28, 0.6),
     (0.05, -0.35, 0.3, 0.7), (0.55, -0.45, 0.24, 0.45)], 9))
