"""Vulcanus: foundry, big mining drill, demolishers, volcanic rocks, chimneys, ashland lichen
trees, sulfuric acid geyser.

Machines are matched to their HR sprites with compare.py the same way as space_platform.py (zs,
ys); the sprite numbers are in space_sprites.py. Vulcanus machines are rust-red and verdigris
green steel with cream tanks; the land is black basalt and ash.
"""

import math

import bmesh
from mathutils import Vector, noise

import detail
import space_kit
import kit
from kit import Part, R, S, T, model
from space_kit import lathe, profile_loft
from space_platform import COS_P, SIN_P, ring, ys, zs  # noqa: F401

kit.MATERIALS.update({
    "paint_foundry_red": ("8f4630", 0.6, 0.45, None, 0),
    "paint_foundry_green": ("566650", 0.6, 0.45, None, 0),
    "paint_foundry_cream": ("b5a284", 0.6, 0.3, None, 0),
    "rust_drill": ("6b3f2c", 0.75, 0.5, None, 0),       # the big drill's rusty frame
    "steel_drill_teeth": ("5b5560", 0.45, 0.8, None, 0),
    "crystal_drill": ("4a3a5a", 0.35, 0.3, None, 0),      # the big drill's purple crystal teeth
    "hose_violet": ("6a4a62", 0.7, 0.0, None, 0),        # its cable bundles
    "molten": ("ff9a3a", 0.6, 0.0, "ff6a10", 3.0),      # glowing metal (foundry, hot rocks)
    "rock_basalt": ("3b3532", 0.95, 0.0, None, 0),       # volcanic rock
    "rock_basalt_dark": ("27221f", 0.95, 0.0, None, 0),
    "rock_ash": ("6a625a", 0.95, 0.0, None, 0),
    "stone_sulfur": ("c2b04a", 0.9, 0.0, None, 0),       # sulfur crust round chimneys and the geyser
    "lava_glow": ("ff7a22", 0.7, 0.0, "ff5a0a", 2.5),    # cracks in hot rocks and chimneys
    "bark_lichen": ("5a4a3c", 0.9, 0.0, None, 0),        # ashland lichen tree branches
    "leaf_lichen": ("7a5a3a", 0.9, 0.0, None, 0),        # its lichen tufts (foliage class)
    "flesh_demolisher": ("4a3a34", 0.8, 0.1, None, 0),   # the demolisher's underside
    "rock_demolisher": ("2e2a28", 0.9, 0.05, None, 0),   # its armour plates
})


# ---------------------------------------------------------------------------------------------
# Foundry.

@model("foundry")
def foundry():
    """Factorio's foundry (5x5) at its true proportions (Space Age pictures draw the ground's
    north-south distances at full length, space_sprites.py): a round red plinth with a raised rim
    round its front, crowded with rust-red and verdigris machinery round a tall tapering red
    furnace stack with a red hopper and a cream tank on top; a caged green cylinder in the
    north-east, a cream drum and green boxes on the east; red machine boxes on a green bed along
    the west; two cream crucibles and a tipping ladle at the front, a round vent drum at the
    south-west. Factorio draws it the same every way round, and so does the client (it doesn't
    turn the model, model_library.gd PICTURES): its masses are fitted to the one picture.

    Moving parts, from Factorio's 128-frame loop at 0.16 (13.3 s): the ladle tips west to pour
    and back (`anim_tilt_foundry_ladle`), a cast plate is pushed out of the west red box along two
    rails and back twice a loop (`anim_slide_foundry_plate`). The melt in the ladle and the red
    box's vents are `molten` (lit and flickering while it works)."""
    p = Part()
    RED, GRN, CRM, R_, SD = "paint_foundry_red", "paint_foundry_green", "paint_foundry_cream", "rust_drill", "steel_dark"
    # Plinth: a round base, a rim round its front half, a dark floor.
    lathe(p, (0, 0.12, 0), [(0.0, 0.0), (2.5, 0.0), (2.56, 0.12), (2.56, 0.64), (2.45, 0.74), (0.0, 0.74)], RED, segs=40)
    lathe(p, (0, 0.12, 0), [(2.2, 0.74), (2.5, 0.74), (2.5, 0.9), (2.2, 0.9)], RED, segs=40, a0=190, a1=350)
    p.cyl((0, 0.12, 0.75), 2.25, 0.02, SD, segs=40)
    # The plinth's front-east corner is squared off under the ladle.
    p.slab(1.3, -2.45, 0.0, 2.5, -1.4, 0.8, RED, bevel=0.1)
    for a in range(200, 350, 25):
        r = math.radians(a)
        p.slab(2.45 * math.cos(r) - 0.12, 2.45 * math.sin(r) - 0.12, 0.15, 2.45 * math.cos(r) + 0.12,
               2.45 * math.sin(r) + 0.12, 0.5, SD)
    # The furnace stack: a tapering red tower, banded, its hopper and a cream tank on top.
    tx, ty = 0.1, 0.0
    p.cyl((tx, ty, 1.55), 0.8, 2.5, RED, segs=24, radius_top=0.6, bevel=0.03)
    for z in (0.9, 1.6, 2.3):
        p.cyl((tx, ty, z), 0.8 - (z - 0.3) * 0.08 + 0.03, 0.06, R_, segs=24)
    p.slab(0.2, 0.3, 2.4, 1.06, 1.52, 2.9, RED, bevel=0.06)
    p.slab(-0.3, 0.4, 2.3, 0.25, 1.2, 2.7, RED, bevel=0.05)
    p.cyl((0.45, 0.9, 2.95), 0.28, 1.1, CRM, segs=14, axis="X", bevel=0.05)
    for x in (-0.05, 0.95):
        p.cyl((x, 0.9, 2.95), 0.3, 0.06, R_, segs=14, axis="X")
    for x in (-0.2, 0.9):
        p.beam((x, 0.5, 2.8), (x, 0.8, 3.25), 0.05, 0.05, SD)
    p.pipe([(-0.45, 0.2, 2.6), (-0.45, 0.4, 3.2), (0.2, 0.6, 3.3), (0.2, 0.7, 3.2)], 0.05, "copper_dull", segs=6)
    # North-east: the caged green cylinder; east: the cream drum, green machine boxes.
    p.cyl((1.62, 1.46, 0.88), 0.5, 1.72, GRN, segs=18, bevel=0.03)
    for z in (0.8, 1.2, 1.6):
        p.cyl((1.62, 1.46, z), 0.54, 0.05, SD, segs=18)
    p.cyl((1.62, 1.46, 1.78), 0.22, 0.12, SD, segs=12)
    p.cyl((1.64, 0.1, 1.0), 0.22, 1.4, CRM, segs=14, bevel=0.04)
    p.sphere((1.64, 0.1, 1.7), 0.22, CRM, segs=14, rings=5, hemisphere=True, scale=(1, 1, 0.6))
    p.slab(1.0, -1.0, 0.6, 2.54, -0.14, 1.32, GRN, bevel=0.05)
    p.slab(0.14, 1.4, 0.5, 1.16, 2.42, 1.38, GRN, bevel=0.05)
    p.slab(-2.4, -1.1, 0.3, -1.4, 0.0, 1.2, GRN, bevel=0.05)
    # West: the red machine boxes on a green bed, pipe columns.
    p.slab(-2.34, 0.1, 0.18, -1.14, 1.2, 1.9, GRN, bevel=0.05)
    p.slab(-2.45, 1.2, 0.18, -1.14, 2.34, 0.45, GRN, bevel=0.05)
    p.slab(-2.34, 0.1, 1.8, -1.3, 0.9, 2.5, RED, bevel=0.07)
    for k in range(4):  # its vents glow with the melt inside (foundry-lights)
        p.cyl((-1.55 - k * 0.15, 0.09, 2.2), 0.03, 0.02, "molten", segs=6, axis="Y")
    # Rails east of the red box that the cast plates ride out on, and a plate (anim_slide_foundry_
    # plate) that rests inside the box and is pushed out along them and back.
    for y in (0.3, 0.7):
        p.slab(-1.32, y - 0.03, 1.82, -0.74, y + 0.03, 1.86, SD)
    plate = Part("anim_slide_foundry_plate", pivot=(-1.6, 0.5, 1.9))
    plate.slab(-1.85, 0.2, 1.86, -1.35, 0.8, 1.94, RED, bevel=0.02)
    for i in range(2):
        for j in range(3):
            plate.cyl((-1.72 + i * 0.24, 0.32 + j * 0.18, 1.94), 0.04, 0.01, "soot", segs=6)
    p.cyl((-1.0, 1.5, 1.35), 0.15, 1.1, GRN, segs=10, bevel=0.03)
    p.pipe([(-1.9, 0.6, 2.45), (-1.9, 0.6, 2.6), (-1.4, 0.8, 2.4), (-1.0, 1.5, 1.9)], 0.06, SD, segs=8)
    p.cyl((-1.0, 0.3, 1.6), 0.25, 0.9, SD, segs=12, axis="X")
    p.slab(-2.36, -0.6, 0.6, -2.3, 0.0, 1.4, CRM)
    # South-west: the round vent drum, pipes curling round the plinth.
    p.cyl((-1.7, -1.76, 0.46), 0.68, 0.56, R_, segs=22, bevel=0.04)
    p.cyl((-1.7, -1.76, 0.75), 0.6, 0.04, CRM, segs=22)
    for k in range(5):
        a = math.radians(k * 72)
        p.cyl((-1.7 + 0.3 * math.cos(a), -1.76 + 0.3 * math.sin(a), 0.76), 0.07, 0.03, SD, segs=8)
    # Front: two cream crucibles and the tipping ladle.
    for x0, x1 in ((-1.4, -0.74), (-0.64, 0.0)):
        p.slab(x0, -2.46, 0.6, x1, -1.2, 1.3, CRM, bevel=0.06)
        p.cyl(((x0 + x1) / 2, -1.83, 1.3), 0.17, 0.04, "soot", segs=12)
    ladle = Part()
    ladle.cyl((0, 0, 0), 0.55, 0.8, "steel_light", segs=16, bevel=0.03)
    ladle.cyl((0, 0, 0.38), 0.47, 0.05, "molten", segs=16)
    ladle.cyl((0, 0, 0), 0.07, 1.25, SD, segs=8, axis="X")
    # The ladle tips on its trunnions to pour west into the moulds and back (anim_tilt_foundry_ladle).
    tip = Part("anim_tilt_foundry_ladle", pivot=(1.6, -1.5, 1.0))
    # The ladle's ribbed back and its yellow bail (they tip with it).
    for z in (-0.12, 0.12):
        ladle.cyl((0, 0, z), 0.57, 0.05, "steel", segs=16)
    ladle.cyl((0, 0, 0.4), 0.56, 0.05, "steel_dark", segs=16)
    for sx in (-1, 1):
        ladle.beam((sx * 0.6, 0, 0), (sx * 0.62, 0, -0.42), 0.06, 0.08, "wire_yellow")
    tip.add_part(ladle, T(1.6, -1.5, 1.0) @ R("X", -30) @ R("Y", 15))
    p.slab(0.75, -1.6, 0.6, 2.15, -1.1, 0.9, GRN, bevel=0.04)
    _foundry_detail(p)
    return [p, tip, plate]


def _foundry_detail(p):
    """The foundry sprite's surface detail, kept inside the fitted masses: the stack's riveted
    plates and seams, the toothed ring at its foot, the cage round the cream tank and the ore in
    the hopper, ribbed hoses, cables, grilles on the crucibles and boxes, the rim's panels."""
    RED, GRN, CRM, R_, SD = "paint_foundry_red", "paint_foundry_green", "paint_foundry_cream", "rust_drill", "steel_dark"
    tx, ty = 0.1, 0.0

    def stack_r(z):
        return 0.8 - (z - 0.3) * 0.08

    # The stack: vertical seams with clips between its plates (the sprite's rows of light clips),
    # a dark broken joint between the lower and middle plates, a brown pipe curling round its foot.
    for a in (205, 240, 275, 310, 345):
        r = math.radians(a)
        for z0, z1 in ((0.35, 1.55), (1.65, 2.7)):
            rr = stack_r((z0 + z1) / 2) + 0.01
            m = T(tx + rr * math.cos(r), ty + rr * math.sin(r), (z0 + z1) / 2) @ R("Z", a)
            p.box((0, 0, 0), (0.03, 0.07, z1 - z0), R_, matrix=m)
            for k in range(3):
                z = z0 + 0.12 + (z1 - z0 - 0.24) * k / 2
                p.box((0.02, 0, z - (z0 + z1) / 2), (0.03, 0.09, 0.06), "steel_light", matrix=m)
    p.cyl((tx, ty, 1.6), stack_r(1.6) + 0.015, 0.05, "soot", segs=24)
    p.ring_band((tx, ty), stack_r(1.25), stack_r(1.25) + 0.03, 1.15, 1.35, 215, 260, "soot", segs=4)
    detail.cable(p, [(tx - 0.75, ty - 0.35, 0.95), (tx - 0.3, ty - 0.92, 0.88), (tx + 0.4, ty - 0.9, 0.86),
                     (tx + 0.85, ty - 0.55, 0.9), (1.2, -0.5, 0.75)], 0.06, "copper_dull", segs=6)
    # The toothed ring the stack stands on.
    detail.gear(p, (tx, ty), 0.98, 0.76, 0.84, SD, teeth=40, hub=SD, segs=32)
    # Top: rivets round the hopper's rim, ore heaped in it, the cage round the cream tank, a valve.
    for x0, y0, x1, y1 in ((0.2, 0.3, 1.06, 0.3), (0.2, 1.52, 1.06, 1.52), (0.2, 0.3, 0.2, 1.52), (1.06, 0.3, 1.06, 1.52)):
        detail.rivet_line(p, (x0, y0, 2.905), (x1, y1, 2.905), 6, "Z", "steel_light", r=0.022)
    p.slab(0.3, 0.42, 2.9, 0.96, 0.62, 2.93, "soot")
    for i, (x, y) in enumerate(((0.38, 0.5), (0.52, 0.48), (0.66, 0.53), (0.8, 0.5), (0.9, 0.56), (0.45, 0.58), (0.72, 0.6))):
        p.sphere((x, y, 2.93), 0.06 + 0.015 * (i % 3), "rust_brown" if i % 2 else "stone_dark", segs=5, rings=3,
                 scale=(1, 1, 0.6))
    for x in (-0.2, 1.05):
        for y in (0.6, 1.2):
            p.beam((x, y, 2.6), (x, y, 3.12), 0.035, 0.035, "steel_light")
        p.beam((x, 0.6, 3.12), (x, 1.2, 3.12), 0.035, 0.035, "steel_light")
    for y in (0.6, 1.2):
        p.beam((-0.2, y, 3.12), (1.05, y, 3.12), 0.035, 0.035, "steel_light")
    for x in (0.15, 0.45, 0.75):
        p.cyl((x, 0.9, 2.95), 0.29, 0.03, R_, segs=14, axis="X")
    p.cyl((0.45, 0.9, 3.27), 0.05, 0.12, "steel_light", segs=8)
    p.sphere((0.45, 0.9, 3.35), 0.06, "steel_light", segs=8, rings=4)
    # The red chute leaning off the hopper to the east, a blue cable and a little box on it.
    p.beam((0.95, 0.55, 2.45), (1.3, -0.15, 1.6), 0.36, 0.08, RED, bevel=0.02)
    p.box((1.15, 0.12, 2.06), (0.14, 0.1, 0.1), "steel_light", rz=-30)
    detail.cable(p, [(0.75, 0.6, 2.5), (1.0, 0.45, 2.42), (1.2, 0.1, 2.05), (1.3, -0.1, 1.7)], 0.03, "wire_blue", segs=4)
    # North-east: the cage round the green cylinder, a yellow ribbed hose looping to the stack.
    for k in range(10):
        a = math.radians(k * 36 + 18)
        x, y = 1.62 + 0.53 * math.cos(a), 1.46 + 0.53 * math.sin(a)
        p.beam((x, y, 0.1), (x, y, 1.72), 0.035, 0.035, "steel_light")
    detail.cable(p, [(1.62, 1.95, 1.75), (1.6, 2.0, 2.05), (1.5, 1.9, 2.2)], 0.025, "wire_blue", segs=4)
    p.cyl((2.15, 1.05, 1.0), 0.05, 1.3, "steel_light", segs=6)
    p.sphere((2.15, 1.05, 1.68), 0.07, "steel_light", segs=8, rings=4)
    space_kit.hose(p, [(1.15, 1.1, 1.45), (1.3, 0.9, 1.8), (1.2, 0.65, 1.95), (0.95, 0.55, 1.75)], 0.08, "wire_yellow", segs=6, rib=0.09)
    # East: the cream tank's banded body and its green window; louvres down the green boxes.
    for z in (0.5, 1.1):
        p.cyl((1.64, 0.1, z), 0.235, 0.05, R_, segs=14)
    p.slab(1.56, -0.135, 0.75, 1.72, -0.12, 1.25, "glass_green")
    detail.slots(p, (1.0, -1.0, 0.6), (2.54, -0.14, 1.32), "+x", 5)
    detail.slots(p, (1.0, -1.0, 0.6), (2.54, -0.14, 1.32), "+z", 6, along=1)
    detail.panel(p, (0.14, 1.4, 0.5), (1.16, 2.42, 1.38), "+z", GRN, rivet="steel_light", split=2)
    # North-west: the red box's riveted lid and perforated face, a canister and coloured wires on
    # it, the big ribbed hose from the green housing down to the stack.
    detail.panel(p, (-2.34, 0.1, 1.8), (-1.3, 0.9, 2.5), "+z", RED, rivet="steel_light", split=2)
    for i in range(3):
        for j in range(4):
            p.cyl((-2.15 + j * 0.13, 0.095, 2.3 - i * 0.07), 0.025, 0.01, "soot", segs=6, axis="Y")
    p.cyl((-1.65, 0.55, 2.68), 0.16, 0.36, "steel", segs=12, bevel=0.03)
    p.cyl((-1.65, 0.55, 2.87), 0.11, 0.04, "steel_light", segs=10)
    detail.cable(p, [(-2.0, 0.35, 2.52), (-2.2, 0.2, 2.4), (-2.36, 0.1, 1.9), (-2.36, -0.1, 1.2)], 0.025, "wire_green", segs=4)
    detail.cable(p, [(-1.95, 0.4, 2.52), (-2.15, 0.25, 2.42), (-2.32, 0.12, 1.95), (-2.3, -0.2, 1.3)], 0.025, "wire_red", segs=4)
    detail.cable(p, [(-1.4, 0.15, 2.4), (-1.3, 0.05, 2.0), (-1.2, -0.05, 1.5)], 0.03, "wire_yellow", segs=4)
    space_kit.hose(p, [(-1.0, 1.6, 2.0), (-0.75, 1.25, 2.35), (-0.5, 0.8, 2.45), (-0.4, 0.45, 2.35)], 0.15, "rubber", segs=6, rib=0.14)
    # West: the yellow banded drum and the rods along the rails, a grille on the green bed.
    detail.ribbed_drum(p, (-1.85, -0.45, 1.36), 0.17, 0.5, "brass", "wire_red", axis="X", ribs=3, segs=12)
    for z in (1.25, 1.45):
        p.cyl((-1.8, 0.3, z), 0.035, 0.9, "steel_light", segs=6, axis="Y")
    detail.slots(p, (-2.4, -1.1, 0.3), (-1.4, 0.0, 1.2), "+z", 4, along=1)
    p.slab(-2.2, -1.12, 0.75, -1.65, -1.1, 0.95, "paint_red")
    detail.cable(p, [(-2.4, -0.9, 1.1), (-2.2, -0.95, 1.2), (-1.9, -1.0, 1.15), (-1.6, -1.05, 1.0)], 0.025, "wire_red", segs=4)
    detail.cable(p, [(-2.4, -0.75, 1.1), (-2.15, -0.8, 1.22), (-1.85, -0.85, 1.18)], 0.025, "wire_green", segs=4)
    # South-west: the vent drum's bands, the dark ribbed hoses round the front and into a crucible.
    for z in (0.3, 0.6):
        p.cyl((-1.7, -1.76, z), 0.7, 0.04, SD, segs=22)
    space_kit.hose(p, [(-2.3, -0.8, 0.5), (-2.45, -1.5, 0.45), (-2.2, -2.2, 0.4), (-1.3, -2.5, 0.35)], 0.15, "rubber", segs=6, rib=0.15)
    space_kit.hose(p, [(-1.25, -1.95, 0.6), (-1.15, -1.75, 0.85), (-1.3, -1.55, 1.05)], 0.1, "rubber", segs=6, rib=0.1)
    # The crucibles: rust trim round their feet, grilles on their south faces, raised rims.
    for x0, x1 in ((-1.4, -0.74), (-0.64, 0.0)):
        p.slab(x0 - 0.01, -2.47, 0.6, x1 + 0.01, -1.19, 0.68, R_)
        detail.slots(p, (x0 + 0.08, -2.46, 0.68), (x1 - 0.2, -1.2, 1.2), "-y", 5, along=1)
        p.cyl(((x0 + x1) / 2, -1.83, 1.32), 0.24, 0.04, "steel_light", segs=12)
    # The rim round the front: panels with dark slots, a copper radiator and a fan sign east.
    for a0 in range(195, 345, 30):
        p.ring_band((0, 0.12), 2.56, 2.58, 0.25, 0.55, a0 + 3, a0 + 27, SD, segs=3)
    for k in range(7):
        x = 0.55 + k * 0.08
        p.slab(x, -2.42, 0.15, x + 0.04, -2.3, 0.48, "copper_dull")
    p.cyl((2.52, -1.9, 0.5), 0.2, 0.03, "steel_light", segs=14, axis="X")
    for a in (90, 210, 330):
        p.box((0, 0.09, 0), (0.01, 0.1, 0.12), "soot", matrix=T(2.535, -1.9, 0.5) @ R("X", a))
    detail.panel(p, (1.3, -2.45, 0.0), (2.5, -1.4, 0.8), "-y", RED, rivet="steel_light")


# ---------------------------------------------------------------------------------------------
# Big mining drill.

# Its box-shaped pieces: (x0, y0, z0, x1, y1, z1, material, mirrored to the west, bevel, label),
# mirrored ones given on the east side. Measured from the four pictures and then fitted face by
# face to all four outlines at once (each face moved while that raised the overlaps).
_BMD_BOXES = [
    # Rails: a girder along each inner edge on a low web and posts, a deck between it and the
    # outer chord, open where the pictures see the ground; a bar in front of the foot.
    (1.40, -2.05, 0.42, 1.72, 2.15, 0.85, "rust_drill", True, 0.03, "girder"),
    (1.45, -2.00, 0.05, 1.52, 2.10, 0.44, "steel_dark", True, 0.0, "girder web"),
    (1.52, -1.35, 0.15, 1.58, -1.28, 0.42, "steel_dark", True, 0.0, "rail post 1"),
    (1.52, -0.85, 0.00, 1.68, -0.73, 0.42, "steel_dark", True, 0.0, "rail post 2"),
    (1.52, 0.30, 0.00, 1.68, 0.42, 0.42, "steel_dark", True, 0.0, "rail post 3"),
    (1.52, 1.10, 0.00, 1.88, 1.27, 0.27, "steel_dark", True, 0.0, "rail post 4"),
    (1.57, 2.05, 0.05, 1.73, 2.12, 0.42, "steel_dark", True, 0.0, "rail post 5"),
    (1.82, -2.40, 0.35, 2.20, -1.80, 0.70, "rust_drill", True, 0.02, "deck 1"),
    (1.72, -1.10, 0.35, 2.20, -0.46, 0.50, "rust_drill", True, 0.02, "deck 2"),
    (1.72, -0.41, 0.15, 2.20, -0.22, 0.45, "rust_drill", True, 0.02, "deck 3"),
    (1.72, -0.07, 0.10, 2.20, 0.50, 0.40, "rust_drill", True, 0.02, "deck 4"),
    (1.72, 0.70, -0.00, 2.20, 1.10, 0.40, "rust_drill", True, 0.02, "deck 5"),
    (1.72, 1.55, 0.45, 2.30, 2.35, 0.70, "rust_drill", True, 0.02, "deck 6"),
    (1.20, -2.43, 0.15, 1.45, -2.08, 0.55, "rust_drill", True, 0.0, "foot bar"),
    (2.15, -2.15, 0.35, 2.44, 2.00, 0.55, "rust_drill", True, 0.03, "chord"),
    # The portal arch over the north ends: posts on the rails, a deep red beam, open under its
    # middle (the east and west pictures see through there, under the drum's back).
    (1.90, 1.20, 0.60, 2.30, 2.05, 1.35, "rust_drill", True, 0.05, "arch post"),
    (0.95, 1.39, 0.76, 1.52, 1.79, 1.65, "paint_foundry_red", True, 0.05, "arch beam"),
    (0.50, 1.45, 1.43, 1.17, 1.79, 1.75, "paint_foundry_red", True, 0.05, "arch beam inner"),
    (-0.50, 1.60, 1.00, 0.35, 1.80, 1.75, "paint_foundry_red", False, 0.05, "arch beam middle"),
    # The output housing under the arch, its chute poking out north, a cream box on top.
    (-0.65, 1.79, 0.16, 0.65, 2.13, 0.85, "steel_dark", False, 0.06, "output housing"),
    (0.40, 2.10, 0.56, 0.99, 2.38, 0.75, "steel_dark", True, 0.06, "output housing side"),
    (0.85, 1.74, 0.50, 2.18, 2.43, 0.55, "steel_dark", True, 0.04, "output housing wing"),
    (-0.45, 2.10, 0.10, 0.40, 2.42, 0.80, "steel_dark", False, 0.05, "chute"),
    (-0.25, 2.40, 0.30, 0.25, 2.65, 0.45, "steel_dark", False, 0.03, "chute end"),
    (-0.83, 2.33, 0.80, -0.33, 2.43, 1.30, "steel_light", False, 0.03, "output box"),
    # The carriage at its first stop: legs on the rails, the drill's supports beside the drum,
    # struts and posts under its back.
    (1.80, -0.20, 0.60, 2.05, -0.13, 1.95, "rust_drill", True, 0.05, "carriage leg"),
    (1.40, -0.30, 1.40, 1.85, 0.12, 1.95, "rust_drill", True, 0.04, "carriage arm"),
    (1.40, -1.20, 0.45, 2.10, -0.65, 1.55, "rust_drill", True, 0.04, "support"),
    (1.18, 0.58, 0.45, 1.73, 1.05, 0.90, "rust_drill", True, 0.03, "strut"),
    (0.63, 0.33, 0.50, 1.23, 0.83, 1.75, "steel_dark", True, 0.03, "back post"),
    # The drum's casings: its sides, its front and two lower front boxes; the green mast behind.
    (0.80, -0.60, 1.70, 1.45, -0.05, 2.55, "paint_foundry_red", True, 0.06, "side casing"),
    (-0.70, -1.35, 1.80, 0.75, -1.00, 2.10, "paint_foundry_red", False, 0.06, "front casing"),
    (-1.18, -1.55, 1.25, -0.33, -0.83, 1.45, "paint_foundry_red", False, 0.05, "front casing west"),
    (0.63, -1.55, 1.35, 1.23, -0.95, 1.80, "paint_foundry_red", False, 0.05, "front casing east"),
    (-0.76, 0.60, 1.45, -0.34, 0.74, 3.15, "paint_foundry_green", False, 0.03, "mast"),
    # Smaller pieces the pictures show: a skid under the drum's back, a bar of hose clamps, cable
    # runs over the front, the grille box on the west side, a beam under the drum.
    (-0.525, 0.575, 0.00, 0.525, 0.775, 0.55, "paint_foundry_red", False, 0.02, "back skid"),
    (-0.975, -1.175, 0.80, -0.875, -0.275, 1.25, "steel_light", False, 0.02, "hose bar west"),
    (1.425, 0.675, 1.95, 1.475, 0.925, 2.20, "rust_drill", False, 0.02, "bracket"),
    (-0.025, -1.675, 2.10, 0.375, -1.325, 2.20, "rust_drill", False, 0.02, "cable run east"),
    (-2.175, 0.725, 0.75, -2.075, 1.275, 1.15, "steel_light", False, 0.02, "grille box"),
    (0.675, -1.225, 0.80, 0.975, 0.425, 1.10, "rust_drill", False, 0.02, "beam under the drum"),
    (-0.325, -1.675, 2.05, -0.175, -0.075, 2.35, "rust_drill", False, 0.02, "cable run west"),
]


@model("big-mining-drill")
def big_mining_drill():
    """Factorio's big mining drill (5x5), facing north, at its true proportions (its sprites draw
    the ground's north-south distances at full length, space_sprites.py): two rusty rails along
    the east and west edges, each a girder carrying a toothed rack beside a deck that is open in
    places, an outer chord over a zigzag lattice, a foot at the front; a red portal arch over
    their north ends, braced from the rails and open under its middle, the output housing under
    it; a carriage on legs over the rails just south of the middle, with supports beside the drum,
    carrying the drill's motor: a round red housing with red casings round its sides and front,
    domed by a lid round a steel hub, and a green toothed mast behind it; the drill head, a
    cluster of purple crystal teeth, hangs under it and spins while it works (anim_spin_drill).
    In Factorio the carriage slides along the rails between stops; the model holds it at the
    first stop. The box-shaped pieces are in _BMD_BOXES, fitted to all four pictures at once."""
    p = Part()
    R_, RD, G, RED = "rust_drill", "steel_dark", "paint_foundry_green", "paint_foundry_red"
    # The box-shaped pieces, fitted face by face to the four pictures (_BMD_BOXES).
    boxes = {}
    for x0, y0, z0, x1, y1, z1, mat, mirrored, bevel, label in _BMD_BOXES:
        for sx in ((1, -1) if mirrored else (1,)):
            p.slab(sx * x0, y0, z0, sx * x1, y1, z1, mat, bevel=bevel)
        boxes[label] = (x0, y0, z0, x1, y1, z1)
    # Rails: the rack's teeth along each girder's top, the outer chord with a zigzag lattice under
    # it, and the foot sloping down at the south end.
    gx0, gy0, _, gx1, gy1, gz1 = boxes["girder"]
    for sx in (-1, 1):
        for k in range(int((gy1 - gy0 - 0.15) / 0.2)):
            y = gy0 + 0.1 + k * 0.2
            p.slab(sx * (gx0 + 0.11), y, gz1, sx * (gx1 - 0.02), y + 0.09, gz1 + 0.06, "steel_drill_teeth")
        for k in range(14):
            y = -1.75 + k * 0.26
            x = sx * 2.32
            p.beam((x, y, 0.2), (x, y + 0.13, 0.4), 0.1, 0.06, RD, up=(1, 0, 0))
            p.beam((x, y + 0.13, 0.4), (x, y + 0.26, 0.2), 0.1, 0.06, RD, up=(1, 0, 0))
        fx0, fx1 = sorted((sx * 1.45, sx * 2.0))
        p.side_prism([(-2.15, 0.0), (-1.8, 0.0), (-1.8, 0.9), (-2.0, 0.7), (-2.15, 0.35)], fx0, fx1, R_, bevel=0.04)
    # The portal arch: braces from the posts up to the beam, bolts along its face.
    for sx in (-1, 1):
        p.beam((sx * 2.0, 1.0, 1.4), (sx * 1.55, 1.44, 1.6), 0.2, 0.25, R_, bevel=0.03)
        for x in (0.7, 1.2):
            p.cyl((sx * x, 1.39 if x < 1 else 1.43, 1.64), 0.04, 0.03, "steel_light", segs=6, axis="Y")
    # The output chute's mouth, and rollers on the housing's sides.
    cx0, _, cz0, cx1, cy1, cz1 = boxes["chute end"]
    p.slab(cx0 + 0.08, cy1 - 0.01, cz0 + 0.05, cx1 - 0.08, cy1 + 0.01, cz1 - 0.05, "soot")
    for sx in (-1, 1):
        p.cyl((sx * 0.94, 2.2, 0.45), 0.2, 0.12, "steel_drill_teeth", segs=10, axis="X")
    # The carriage's wheels on the rails, braced from its legs.
    lx0, ly0, _, lx1, ly1, _ = boxes["carriage leg"]
    for sx in (-1, 1):
        x = sx * (lx0 + lx1) / 2
        p.beam((x, ly0 - 0.3, 0.6), (x, ly0 + 0.05, 1.3), 0.14, 0.14, R_)
        p.beam((x, ly1 + 0.3, 0.6), (x, ly1 - 0.05, 1.3), 0.14, 0.14, R_)
        for y in (ly0 - 0.2, ly1 + 0.2):
            p.cyl((x, y, 0.72), 0.17, 0.5, RD, segs=12, axis="X")
    # Motor housing: a round red drum (casings round its sides and front are boxes above); its
    # upper half and domed lid sit a little north of the lower.
    hx, hy = 0.0, -0.24
    lathe(p, (hx, hy, 0), [(0.0, 1.76), (1.05, 1.76), (1.1, 1.85), (1.1, 2.6), (0.0, 2.6)], RED, segs=24)
    lathe(p, (hx, hy + 0.15, 0), [(0.0, 2.58), (1.1, 2.58), (1.1, 2.96), (0.9, 3.24), (0.0, 3.24)], RED, segs=24)
    # The lid is a low ring round an open top, the gear train showing inside it as the sprite has.
    lathe(p, (hx, hy + 0.15, 0), [(0.55, 3.22), (0.9, 3.22), (0.86, 3.38), (0.6, 3.38)], RED, segs=20)
    p.cyl((hx, hy + 0.15, 3.25), 0.62, 0.06, "steel_dark", segs=18)
    p.cyl((hx, hy + 0.15, 3.42), 0.24, 0.3, "steel_light", segs=14)
    for k in range(5):
        a = math.radians(-150 + k * 60)
        p.pipe([(hx + 0.8 * math.cos(a), hy + 0.8 * math.sin(a), 3.35), (hx + 1.2 * math.cos(a), hy + 1.2 * math.sin(a), 2.8),
                (hx + 1.2 * math.cos(a), hy + 1.2 * math.sin(a), 1.9)], 0.05, "hose_violet", segs=6)
    # The sprite's detail on the motor: seams down the drum's plates, a band of cables wrapped
    # round its shoulder, blue, green and violet cables looping down to the frame, and the gear
    # train on the lid round its hub.
    for k in range(12):
        a = math.radians(15 + 30 * k)
        c, s_ = math.cos(a), math.sin(a)
        p.beam((hx + 1.105 * c, hy + 1.105 * s_, 1.9), (hx + 1.105 * c, hy + 1.105 * s_, 2.55), 0.035, 0.02,
               "rust_drill", up=(c, s_, 0))
    detail.hose_arc(p, (hx, hy + 0.15), 1.12, 2.66, 0, 360, 0.07, "hose_violet", rib=0.2, steps=24)
    for k, (a0, mat) in enumerate(((-120, "wire_blue"), (-60, "wire_green"), (20, "wire_blue"),
                                   (160, "wire_green"), (-100, "wire_red"))):
        a = math.radians(a0)
        c, s_ = math.cos(a), math.sin(a)
        detail.cable(p, [(hx + 0.85 * c, hy + 0.15 + 0.85 * s_, 3.3), (hx + 1.3 * c, hy + 0.15 + 1.3 * s_, 3.0),
                         (hx + 1.45 * c, hy + 1.45 * s_, 2.2), (hx + 1.3 * c, hy + 1.3 * s_, 1.75)], 0.035, mat)
    detail.gear(p, (hx + 0.3, hy + 0.4), 0.26, 3.3, 3.38, "steel_light", teeth=12, hub="steel_dark", segs=14)
    detail.gear(p, (hx - 0.3, hy + 0.1), 0.2, 3.3, 3.38, "steel_light", teeth=9, hub="steel_dark", segs=12)
    p.beam((hx - 0.45, hy - 0.2, 3.45), (hx + 0.45, hy + 0.5, 3.6), 0.08, 0.06, "steel_dark")
    p.cyl((hx + 0.55, hy - 0.4, 3.45), 0.1, 0.3, "steel_light", segs=10)
    detail.cable(p, [(hx - 0.5, hy + 0.5, 3.3), (hx - 0.1, hy + 0.7, 3.55), (hx + 0.4, hy + 0.2, 3.5),
                     (hx + 0.7, hy - 0.2, 3.3)], 0.035, "wire_blue")
    # Rivets along the portal's beam and the rails' girders.
    detail.rivet_line(p, (-1.8, 1.38, 1.85), (1.8, 1.38, 1.85), 14, "Y", "steel_light", r=0.025)
    for sx in (-1, 1):
        detail.rivet_line(p, (sx * 2.38, -1.9, 0.62), (sx * 2.38, 1.4, 0.62), 12, "X", "steel_light", r=0.025)
    # The green mast's teeth.
    mx0, my0, mz0, mx1, _, mz1 = boxes["mast"]
    for k in range(int((mz1 - mz0 - 0.5) / 0.12)):
        p.slab(mx0 + 0.1, my0 - 0.03, mz0 + 0.4 + k * 0.12, mx1 - 0.1, my0, mz0 + 0.46 + k * 0.12, RD)
    # Drill head: purple crystal teeth round a hub under the housing.
    head = Part("anim_spin_drill", pivot=(hx, hy, 0.0))
    head.cyl((hx, hy, 1.3), 0.4, 0.8, RD, segs=12)
   # Four clusters of teeth on the diagonals: every direction's picture shows two lobes low at
    # the sides with nothing in the middle (the same frame of the head is drawn for all four).
    for k in range(4):
        a = math.radians(45 + 90 * k)
        for j, (r, z, da, tilt, s) in enumerate(((0.8, 1.2, -0.35, 135, 0.3), (0.8, 1.2, 0.35, 135, 0.3), (1.0, 0.85, 0.0, 145, 0.34),
                                                 (0.95, 0.6, -0.22, 160, 0.26), (0.95, 0.6, 0.22, 160, 0.26))):
            b = a + da
            tooth = Part()
            tooth.cyl((0, 0, 0), s, 0.7, "crystal_drill", segs=5, radius_top=0.05)
            head.add_part(tooth, T(hx + r * math.cos(b), hy + r * math.sin(b), z) @ R("Z", math.degrees(b)) @ R("Y", tilt))
    return [p, head]


# ---------------------------------------------------------------------------------------------
# Ashland lichen trees.

def _limb(p, pts, r0, r1, mat="bark_lichen"):
    """A tapering limb through `pts`, radius r0 at the start to r1 at the tip."""
    n = len(pts) - 1
    for k in range(n):
        ra = r0 + (r1 - r0) * k / n
        rb = r0 + (r1 - r0) * (k + 1) / n
        p.tube(pts[k], pts[k + 1], ra, mat, segs=7, radius_top=rb)
        if 0 < k:
            p.sphere(pts[k], ra, mat, segs=7, rings=4)


# The tree_00 sprite's limbs, measured from its outline (the skeleton of its opaque pixels):
# each point is (x, screen-up, radius) in tiles, as Factorio's camera sees it. _ASH_DEPTH gives
# each limb a lean north or south; the height is worked back from the screen position, so the
# limb still lands where the sprite draws it.
_ASH_LIMBS = [
    [(0.076, 0.052, 0.144), (0.028, 0.163, 0.237), (0.091, 0.351, 0.250), (-0.017, 0.946, 0.262)],
    [(0.008, 0.913, 0.272), (0.055, 1.040, 0.273), (0.070, 1.086, 0.279), (0.088, 1.336, 0.215), (0.211, 1.398, 0.206)],
    [(0.008, 0.929, 0.290), (-0.070, 1.008, 0.205), (-0.242, 1.007, 0.190), (-0.492, 1.132, 0.124), (-0.727, 1.508, 0.112)],
    [(0.226, 1.367, 0.139), (0.492, 1.440, 0.117), (0.773, 1.680, 0.153), (1.007, 1.836, 0.139), (1.226, 2.055, 0.136), (1.289, 2.102, 0.121), (1.320, 2.164, 0.019), (1.460, 2.304, 0.022)],
    [(-0.743, 1.571, 0.112), (-0.720, 1.648, 0.108), (-0.505, 1.898, 0.092), (-0.464, 2.008, 0.111), (-0.652, 2.383, 0.070), (-0.774, 2.523, 0.063), (-0.775, 2.633, 0.037)],
    [(0.227, 1.414, 0.150), (0.336, 1.570, 0.030), (0.382, 1.664, 0.030), (0.446, 1.914, 0.034)],
    [(-0.758, 1.539, 0.072), (-0.946, 1.352, 0.017), (-1.007, 1.211, 0.020), (-1.055, 1.007, 0.012), (-1.164, 0.977, 0.020)],
    [(0.414, 1.914, 0.034), (0.477, 1.961, 0.019), (0.461, 2.023, 0.020), (0.727, 2.289, 0.012)],
    [(0.398, 1.851, 0.026), (0.414, 2.273, 0.020), (0.523, 2.555, 0.012), (0.632, 2.679, 0.012), (0.664, 2.836, 0.012)],
    [(1.273, 2.149, 0.011), (1.320, 2.383, 0.020), (1.320, 2.414, 0.012), (1.320, 2.476, 0.012), (1.273, 2.616, 0.012)],
    [(1.492, 2.336, 0.030), (1.540, 2.336, 0.017), (1.586, 2.368, 0.012), (1.742, 2.477, 0.012), (1.977, 2.695, 0.012)],
    [(1.492, 2.336, 0.020), (1.523, 2.508, 0.012), (1.632, 2.602, 0.012)],
    [(1.336, 2.351, 0.012), (1.461, 2.539, 0.012), (1.461, 2.805, 0.012)],
]
# North (+) or south (-) lean per limb, in tiles at its tip.
_ASH_DEPTH = [0.0, 0.1, -0.15, 0.35, -0.3, 0.1, -0.35, 0.25, 0.15, 0.45, 0.5, 0.35, 0.4]


def ashland_tree(flaming=False):
    """Vulcanus' ashland lichen tree: a bare black lumpy trunk forking at about a tile and a half
    into two crooked limbs, the east one reaching out and up to a spray of thin twigs, the west one
    kinking back up, and a thin twig hanging off to the west (tree_00 of its sprites)."""
    p = Part()
    for limb, lean in zip(_ASH_LIMBS, _ASH_DEPTH):
        u0 = limb[0][1]
        u1 = max(limb[-1][1], u0 + 1e-3)
        pts = []
        for x, u, r in limb:
            t = min(1.0, max(0.0, (u - u0) / (u1 - u0))) if lean else 0.0
            y = lean * t
            pts.append(((x, y, max(-0.12, (u - SIN_P * y) / COS_P)), r))
        for (a, ra), (b, rb) in zip(pts, pts[1:]):
            segs = 8 if ra > 0.05 else 5
            p.tube(a, b, ra, "bark_lichen", segs=segs, radius_top=rb)
            p.sphere(b, rb, "bark_lichen", segs=segs, rings=4)
    # The trunk's bark is lumpy: knots where it swells.
    p.sphere((-0.04, 0.0, 0.13), 0.19, "bark_lichen", segs=8, rings=5, scale=(1.0, 1.0, 0.6))
    for x, u, r in ((0.05, 0.55, 0.25), (-0.01, 0.85, 0.25), (0.08, 1.15, 0.22), (-0.15, 1.05, 0.17)):
        p.sphere((x, 0.0, u / COS_P), r, "bark_lichen", segs=8, rings=5, scale=(1.0, 1.0, 1.3))
    if flaming:
        # Embers glowing in the bark's front face, inside the limbs' outline (Factorio draws the
        # flames themselves as a separate fire effect).
        for k, i in ((0, 1), (0, 2), (1, 2), (2, 3), (3, 2), (3, 4), (4, 2)):
            x, u, r = _ASH_LIMBS[k][i]
            d = r * 0.75
            p.sphere((x, -d, (u + SIN_P * d) / COS_P), r * 0.35, "molten", segs=8, rings=4, scale=(1.0, 0.5, 1.6))
    return p


@model("ashland-lichen-tree")
def ashland_lichen_tree():
    return ashland_tree()


@model("ashland-lichen-tree-flaming")
def ashland_lichen_tree_flaming():
    """The ashland lichen tree on fire: embers in its bark and flames licking up the limbs."""
    return ashland_tree(flaming=True)


# ---------------------------------------------------------------------------------------------
# Demolishers: Vulcanus' giant lava worms. Each is a head, a train of segments that follow it
# and a tail, which the bridge sends as one segmented unit (`seg`, demolishers.gd draws it). The
# models are at the big demolisher's scale (1); the client sizes each one by the scale in its
# prototype name (`small-demolisher-segment-x0_545` is a segment at 0.545, model_library.gd).
#
# Factorio draws each part from 128 directions: creature_hull.py carves their visual hull and
# measures it as rings across the part (creature_profiles.py), which these loft through. Each
# ring point carries the colour class the sprite shows there (dark rock, lit rock, the lava in
# the seams and under the plates, the bone of the head's mandibles), so the materials sit where
# Factorio paints them.

kit.MATERIALS.update({
    "rock_demolisher": ("2c2826", 0.85, 0.05, None, 0),
    "rock_demolisher_light": ("4a433e", 0.85, 0.05, None, 0),
    "bone_demolisher": ("c8b49a", 0.55, 0.0, None, 0),
    "lava_demolisher": ("ff6a1a", 0.7, 0.0, "ff4a08", 2.5),
    "lava_demolisher_dim": ("6a2414", 0.8, 0.0, "a02808", 0.6),  # crust over the lava, faintly lit
})

# Colour class (creature_profiles' letters, darkest first) -> material, per part.
DEMOLISHER_CLASSES = {
    "demolisher-head": {"a": "rock_demolisher", "b": "rock_demolisher_light", "c": "rock_demolisher_light",
                        "d": "bone_demolisher"},
    "demolisher-segment": {"a": "rock_demolisher", "b": "rock_demolisher", "c": "rock_demolisher_light",
                           "d": "lava_demolisher"},
    "demolisher-tail": {"a": "lava_demolisher_dim", "b": "rock_demolisher", "c": "lava_demolisher_dim",
                        "d": "lava_demolisher"},
}


def _demolisher_part(name):
    from creature_profiles import PROFILES
    p = Part()
    p.sharp_angle = 70.0  # rock and flesh: smooth across the rings
    profile_loft(p, PROFILES[name], DEMOLISHER_CLASSES[name])
    return p


@model("demolisher-head")
def demolisher_head():
    """The demolisher's head: armour plates of black volcanic rock rising over a maw ringed with
    bone-white mandibles at the front (north, the way it crawls), lava in the seams. Factorio
    draws it well ahead of the unit's position, and so does the hull."""
    return _demolisher_part("demolisher-head")


@model("demolisher-segment")
def demolisher_segment():
    """A body segment: one wide arched rock plate, its front open on the glowing lava inside
    (the segment ahead overlaps it as they crawl)."""
    return _demolisher_part("demolisher-segment")


@model("demolisher-tail")
def demolisher_tail():
    """The tail: a rounded lump of rock, lava glowing through its front and its cracks."""
    return _demolisher_part("demolisher-tail")
