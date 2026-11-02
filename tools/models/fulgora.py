"""Fulgora: electromagnetic plant, recycler, lightning rod, lightning collector, tesla turret,
fulgoran ruins, fulgurite, scrap.

Matched to their HR sprites with compare.py like space_platform.py (zs, ys); sprite numbers in
space_sprites.py. Fulgoran machines are slate-blue and cream with copper coils; the ruins are
pale concrete and rusted iron, the ground dark purple-grey rock.
"""

import math

import bmesh
from mathutils import Matrix, Vector, noise

import detail
import kit
import oil
import space_kit
from kit import Part, R, S, T, model
from space_platform import COS_P, SIN_P, ring, ys, zs  # noqa: F401

kit.MATERIALS.update({
    "paint_fulgora_blue": ("4d6680", 0.55, 0.45, None, 0),
    "paint_fulgora_cream": ("c9c0ad", 0.6, 0.3, None, 0),
    "copper_coil": ("b0683a", 0.4, 0.9, None, 0),
    "copper_tip": ("c0703a", 0.45, 0.85, None, 0),   # the collector's tip, sampled apart from its coils

    "paint_recycler_green": ("6c7a3e", 0.65, 0.4, None, 0),
    "rust_recycler": ("7a4a2c", 0.8, 0.45, None, 0),
    "lamp_recycler": ("5cff4a", 0.3, 0.0, "40ff30", 2.0),   # its green working lamp
    "insulator_ceramic": ("ddd4c0", 0.35, 0.0, None, 0),
    "insulator_green": ("8e9c7c", 0.35, 0.1, None, 0),
    "glow_cyan": ("7fe8ff", 0.4, 0.0, "40d8ff", 2.0),
    "concrete_ruin": ("8f8a86", 0.95, 0.0, None, 0),
    "concrete_ruin_dark": ("5d5856", 0.95, 0.0, None, 0),
    "rust_ruin": ("6e4430", 0.85, 0.45, None, 0),
    "stone_fulgurite": ("6b5a68", 0.6, 0.1, None, 0),   # glassy fused rock (stone class)
    "glass_fulgurite_core": ("c8486a", 0.5, 0.0, None, 0),  # the pink inside of a broken end
    "stone_fulgora": ("4a4048", 0.95, 0.0, None, 0),
})


# ---------------------------------------------------------------------------------------------
# Electromagnetic plant.

@model("electromagnetic-plant")
def electromagnetic_plant():
    """Factorio's electromagnetic plant (4x4): a round plinth ringed by ribbed rusty hoses, two
    slate-blue riveted housings arching over it from the west and the east, cream towers with an
    antenna and a ribbed dome at the back, a corrugated hump at the back left, a brass column under
    the east arch, a blue pillar at the front right and a banded brass drum lying at the front; in
    the middle a toothed turntable with a ring of small cogs at its front edge, a dark arch ring
    behind it, and the copper coil assembly (a wire ball on its post) that spins while it works
    (anim_spin_arms). Outline fitted to the sprite; the detail pass (detail.py) keeps it."""
    p = Part()
    blue, cream = "paint_fulgora_blue", "paint_fulgora_cream"
    p.cyl((0.1, -0.8, 0.03), 1.745, 0.06, "steel_dark", segs=36)
    p.cyl((0.1, -0.8, 0.09), 1.5, 0.06, "rust_brown", segs=36)
    # The hoses: a thick ribbed ring at the plinth's rim, a second loop over it at the back
    # where the sprite shows them stacked, clamped to posts.
    detail.hose_arc(p, (0.1, -0.8), 1.57, 0.2, 0, 360, 0.18, "rust_brown", rib=0.34, steps=36)
    detail.hose_arc(p, (0.1, -0.8), 1.57, 0.53, 0, 180, 0.17, "rust_brown", rib=0.34, steps=24)
    for a in range(0, 360, 45):
        t = math.radians(a)
        p.box((0.1 + 1.57 * math.cos(t), -0.8 + 1.57 * math.sin(t), 0.2), (0.1, 0.4, 0.36), "steel_dark",
              rz=a + 90)
    # The turntable in the middle: a cone under a toothed gear with cut-outs and a spindle, and
    # at its front edge a toothed rail with four small cogs.
    p.cyl((0.04, -0.4, 0.62), 1.047, 0.6, "steel_dark", segs=24, radius_top=0.73, bevel=0.03)
    detail.gear(p, (0.04, -0.4), 0.68, 0.9, 0.98, "steel", holes=6, teeth=22)
    p.cyl((0.04, -0.4, 1.0), 0.06, 0.4, "steel_light", segs=8)
    rail = Part()
    rail.ring_band((0, 0), 0.92, 1.02, 0.42, 0.5, 200, 340, "steel_dark", segs=14)
    for k in range(11):
        a = math.radians(200 + 140 * k / 10)
        rail.box((0.97 * math.cos(a), 0.97 * math.sin(a), 0.53), (0.05, 0.08, 0.06), "steel", rz=math.degrees(a))
    p.add_part(rail, T(0.04, -0.4, 0))
    for a in (225, 250, 290, 315):
        t = math.radians(a)
        x, y = 0.04 + 0.8 * math.cos(t), -0.4 + 0.8 * math.sin(t)
        detail.gear(p, (x, y), 0.13, 0.5, 0.6, "steel_light", teeth=6, hub="steel_dark", segs=8)
    arch = Part()   # the dark ring standing behind the coil, open to the east
    arch.ring_band((0, 0), 0.5, 0.6, -0.06, 0.06, 90, 280, "steel_dark", segs=14)
    for k in range(5):
        a = math.radians(95 + 180 * k / 4)
        arch.box((0.6 * math.cos(a), 0.6 * math.sin(a), 0), (0.06, 0.06, 0.13), "steel", rz=math.degrees(a))
    p.add_part(arch, T(-0.05, 0.05, 1.45) @ R("X", 90))
    # West: the blue housing and its arm arching over towards the middle, panelled and riveted.
    detail.panelled(p, (-1.41, -1.05, 0.0), (-0.62, 1.08, 1.5), blue)
    detail.panelled(p, (-1.24, -0.64, 1.45), (-0.61, 0.89, 1.85), blue, bevel=0.06)
    detail.panelled(p, (-0.78, -0.6, 1.49), (-0.41, 0.96, 2.1), blue, bevel=0.06)
    detail.panelled(p, (-1.25, -1.71, 0.33), (-0.82, -0.5, 1.43), blue, bevel=0.06)
    detail.slots(p, (-1.25, -1.71, 0.45), (-0.82, -0.5, 0.8), "-y", 3)
    p.slab(-1.32, -1.78, 0.2, -0.75, -1.6, 0.42, "steel_dark", bevel=0.03)
    # The coil column on the west housing: a steel post, copper windings, a cap.
    p.cyl((-1.03, -1.1, 1.62), 0.1, 0.44, "steel_dark", segs=10)
    detail.coil(p, (-1.03, -1.1), 0.13, 1.42, 1.78, "copper_coil")
    p.cyl((-1.03, -1.1, 1.86), 0.15, 0.08, "steel_light", segs=10, bevel=0.02)
    detail.cable(p, [(-1.3, -0.4, 1.5), (-1.45, -0.2, 1.2), (-1.42, 0.2, 0.9)], 0.025, "wire_yellow")
    detail.cable(p, [(-1.2, 0.6, 1.85), (-1.0, 0.75, 2.0), (-0.75, 0.9, 1.9)], 0.02, "wire_green")
    # East: the arch over the turntable with dark windows on its top and a red cable along it,
    # the cream control box under its front end, the brass column, the front pillar.
    detail.panelled(p, (0.22, -0.38, 1.17), (1.27, 0.81, 1.82), blue, faces=("-y", "-x", "+x", "+y"),
                    bevel=0.12)
    detail.panelled(p, (-0.34, 0.3, 1.42), (0.3, 0.81, 1.82), blue, faces=("-y",), bevel=0.06)
    for x0, x1 in ((0.35, 0.72), (0.8, 1.12)):
        p.slab(x0, -0.2, 1.82, x1, 0.25, 1.835, "grime")
    p.slab(0.35, 0.38, 1.82, 1.12, 0.66, 1.84, blue)
    detail.rivet_line(p, (0.3, -0.33, 1.83), (1.2, -0.33, 1.83), 7, "Z")
    detail.cable(p, [(-0.3, 0.72, 1.86), (0.4, 0.75, 1.9), (1.0, 0.7, 1.88), (1.3, 0.4, 1.6)], 0.022,
                 "wire_red")
    p.slab(0.25, -0.4, 1.3, 1.1, -0.36, 1.7, "steel_dark")
    p.slab(0.36, -0.58, 0.98, 0.94, -0.22, 1.42, cream, bevel=0.04)
    p.slab(0.42, -0.6, 1.05, 0.62, -0.58, 1.3, "grime")
    detail.cable(p, [(0.66, -0.6, 1.3), (0.72, -0.66, 1.15), (0.8, -0.6, 1.02)], 0.018, "wire_green")
    detail.cable(p, [(0.56, -0.6, 1.36), (0.6, -0.68, 1.2), (0.7, -0.62, 1.06)], 0.018, "wire_red")
    p.cyl((0.66, -0.23, 0.45), 0.093, 0.68, "brass", segs=16, radius_top=0.47)
    p.sphere((0.49, -0.35, 0.94), 0.355, "brass", segs=14, rings=7)
    p.cyl((0.49, -0.35, 0.94), 0.37, 0.05, "steel_dark", segs=14)
    space_kit.bent(p, [(0.75, -0.5, 0.95), (1.05, -0.65, 0.8), (1.15, -0.75, 0.3)], 0.1, "brass", segs=10)
    p.cyl((1.15, -0.75, 0.15), 0.14, 0.12, "steel_dark", segs=10)
    detail.panelled(p, (0.92, -2.16, 0.0), (1.6, -1.11, 1.41), blue)
    p.slab(1.02, -2.18, 0.35, 1.5, -2.16, 0.7, "grime")
    p.slab(0.45, -2.1, 0.0, 0.95, -1.15, 0.4, "steel_dark", bevel=0.04)
    p.cyl((0.68, -1.55, 0.75), 0.17, 0.8, "brass", segs=12)
    for z in (0.5, 1.0):
        p.cyl((0.68, -1.55, z), 0.19, 0.05, "steel_dark", segs=12)
    space_kit.bent(p, [(0.68, -1.55, 1.15), (0.66, -1.2, 1.3), (0.6, -0.75, 1.15)], 0.13, "brass", segs=10)
    p.cyl((1.0, -1.6, 1.55), 0.15, 0.3, "steel_light", segs=10)
    p.cyl((1.0, -1.6, 1.74), 0.1, 0.08, "ceramic", segs=10)
    p.sphere((1.0, -1.6, 1.8), 0.07, "steel_light", segs=8, rings=4)
    # Back: the cream towers (stepped, slotted, the antenna on the left one, the ribbed dome
    # and a vent on the right), the corrugated hump and the hoses' riser.
    detail.panelled(p, (-0.67, 0.95, 0.4), (-0.04, 1.36, 1.85), cream, faces=("-y", "-x", "+x"), bevel=0.05)
    for z in (0.9, 1.3, 1.7):
        p.slab(-0.69, 0.93, z, -0.02, 0.96, z + 0.06, "steel_dark")
    p.slab(-0.6, 1.0, 1.85, -0.12, 1.3, 2.05, cream, bevel=0.03)
    detail.slots(p, (-0.6, 1.0, 1.86), (-0.12, 1.3, 2.05), "-y", 2)
    for a, b in (((-0.39, 1.2, 2.05), (-0.37, 1.2, 2.6)), ((-0.37, 1.2, 2.6), (-0.3, 1.2, 2.72)),
                 ((-0.3, 1.2, 2.72), (-0.36, 1.2, 3.02)), ((-0.46, 1.2, 2.2), (-0.46, 1.2, 2.55))):
        p.beam(a, b, 0.035, 0.035, "rust_brown")
    detail.panelled(p, (0.06, 0.86, 0.0), (0.7, 1.13, 1.63), cream, faces=("-y", "-x", "+x"), bevel=0.05)
    detail.slots(p, (0.3, 0.84, 1.15), (0.66, 0.86, 1.5), "-y", 4)
    p.sphere((0.31, 0.98, 1.95), 0.22, "steel_light", segs=14, rings=7)
    for r_, z in ((0.225, 1.95), (0.19, 2.06)):
        p.cyl((0.31, 0.98, z), r_, 0.025, "steel_dark", segs=14)
    p.cyl((0.31, 0.98, 1.72), 0.16, 0.12, "steel_dark", segs=12)
    hump = Part()
    hump.cyl((0, 0, 0), 0.47, 0.99, "rust_brown", segs=12, axis="Y")
    for k in range(7):
        hump.cyl((0, -0.42 + k * 0.14, 0), 0.5, 0.05, "steel_dark", segs=12, axis="Y")
    p.add_part(hump, T(-1.35, 0.785, 0.53) @ S(0.62, 1, 1.06))
    p.slab(-1.66, 0.29, 0.0, -1.04, 1.28, 0.2, "steel_dark")
    p.cyl((1.46, 0.83, 0.72), 0.415, 1.43, "rust_brown", segs=14, radius_top=0.234)
    for z, r_ in ((0.3, 0.4), (0.6, 0.36), (0.9, 0.32), (1.2, 0.28)):
        p.cyl((1.46, 0.83, z), r_ + 0.03, 0.06, "steel_dark", segs=14)
    p.cyl((1.46, 0.83, 1.46), 0.26, 0.06, "steel_dark", segs=14)
    # Front: the brass drum lying in the hose ring, banded and capped.
    detail.ribbed_drum(p, (-0.09, -2.175, 0.5), 0.325, 0.79, "brass", "steel_dark", ribs=3)
    for x in (-0.49, 0.31):
        p.cyl((x, -2.175, 0.5), 0.2, 0.04, "steel_dark", segs=12, axis="X")
    # The coil assembly: a copper core with a wire ball, on arms with cream pods.
    cx, cy = 0.1, -0.25
    coil = Part("anim_spin_arms", pivot=(cx, cy, 0.0))
    coil.cyl((cx, cy, 1.05), 0.2, 0.9, "copper_coil", segs=14)
    detail.coil(coil, (cx, cy), 0.22, 0.65, 1.15, "copper_coil", turns=4)
    for z in (0.8, 1.05, 1.3):
        coil.cyl((cx, cy, z), 0.31, 0.04, "steel_dark", segs=14)
    detail.cage(coil, (cx, cy, 1.42), 0.27, "copper_coil", rings=3, segs=10)
    coil.cyl((cx, cy, 1.6), 0.08, 0.3, "steel_light", segs=8)
    for k in range(3):
        a = 2 * math.pi * k / 3
        ex, ey = cx + 0.6 * math.cos(a), cy + 0.6 * math.sin(a)
        coil.beam((cx, cy, 1.3), (ex, ey, 1.1), 0.08, 0.08, "steel_dark")
        coil.cyl((ex, ey, 0.92), 0.13, 0.4, "paint_fulgora_cream", segs=10, bevel=0.03)
        coil.cyl((ex, ey, 1.14), 0.09, 0.05, "copper_coil", segs=10)
    return [p, coil]


# ---------------------------------------------------------------------------------------------
# Recycler.

@model("recycler")
def recycler():
    """Factorio's recycler (2x4): a long rusty frame painted lichen-green with hazard stripes: a
    tall housing down the west side, an open hopper with rollers in the middle under a green
    plate, a motor panel at the back left, a stout column behind the hopper, the funnel (the
    input) rising from a rusty bulb at the back right, a ribbed drum and a domed pot at the
    front. Sizes fitted to the four direction sprites' outlines at once.

    Moving parts, from Factorio's 64-frame loop at speed 4 (0.27 s): the ribbed drum drops to open
    the bin and comes back up (`anim_slide_recycler_drum`), the motor panel at the back jolts up
    and down (`anim_slide_recycler_panel`), the hopper's three toothed rollers turn
    (`anim_roll_recycler`, one turn every four loops) and the green lamp is lit while it works
    (`anim_glow_recycler_lamp`)."""
    p = Part()
    p.slab(-0.94, -1.98, 0.0, 0.95, 2.02, 0.14, "rust_recycler", bevel=0.03)
    # The west housing with its pipe, the east wall with its spring, the hopper between.
    p.slab(-1.02, -1.23, 0.0, -0.54, 1.71, 0.83, "paint_recycler_green", bevel=0.05)
    for face in ("-x", "+x"):
        detail.stripes(p, (-1.02, -1.23, 0.62), (-0.54, 1.71, 0.8), face, 16)
    detail.panel(p, (-1.02, -1.23, 0.0), (-0.54, 1.71, 0.62), "-x", "paint_recycler_green", split=3,
                 rivet="steel_light")
    detail.slots(p, (-1.02, -1.23, 0.0), (-0.54, -0.5, 0.6), "-y", 3)
    p.cyl((-0.79, 0.32, 0.154), 0.088, 2.3, "copper_dull", segs=8, axis="Y")
    p.slab(0.25, -0.89, 0.0, 1.04, 0.54, 0.56, "paint_recycler_green", bevel=0.04)
    detail.panel(p, (0.25, -0.89, 0.0), (1.04, 0.54, 0.56), "+x", "paint_recycler_green", split=2,
                 rivet="steel_light")
    for y in (-0.75, 0.35):   # the east wall's springs
        detail.spring(p, (0.99, y, 0.12), (0.99, y, 0.5), 0.065, "rust_recycler", turns=6)
    p.cyl((0.999, -0.55, 0.088), 0.088, 2.28, "copper_dull", segs=8, axis="Y")
    for k in range(10):
        p.cyl((1.0, -1.6 + k * 0.22, 0.09), 0.1, 0.05, "rust_recycler", segs=8, axis="Y")
    # The open hopper: a green frame round a dark well with shredder rollers and bars, a plate
    # over the drum's end of it.
    p.slab(-0.65, -1.4, 0.43, 0.87, -0.06, 0.6, "soot")
    for y0, y1 in ((-1.4, -1.3), (-0.16, -0.06)):
        p.slab(-0.65, y0, 0.43, 0.87, y1, 1.18, "paint_recycler_green", bevel=0.03)
    for x0, x1 in ((-0.65, -0.55), (0.77, 0.87)):
        p.slab(x0, -1.4, 0.43, x1, -0.06, 1.18, "paint_recycler_green", bevel=0.03)
    rollers = []
    for y in (-1.0, -0.75, -0.5):
        roll = Part("anim_roll_recycler", pivot=(0.1, y, 0.75))
        roll.cyl((0.1, y, 0.75), 0.11, 1.3, "steel_dark", segs=10, axis="X")
        for k in range(4):  # shredder teeth, so the turning shows
            a = k * 90 + (45 if y == -0.75 else 0)
            for x in (-0.35, 0.1, 0.55):
                roll.box((0, 0, 0.12), (0.08, 0.05, 0.05), "steel_light",
                         matrix=T(x, y, 0.75) @ R("X", a))
        rollers.append(roll)
    for y in (-0.62, -0.38):
        p.cyl((0.1, y, 1.1), 0.025, 1.4, "steel_light", segs=6, axis="X")
    p.slab(-0.15, -1.4, 1.06, 0.87, -0.9, 1.2, "paint_recycler_green", bevel=0.03)
    detail.stripes(p, (-0.15, -1.4, 1.06), (0.87, -0.9, 1.2), "-y", 7)
    detail.rivet_line(p, (-0.1, -1.15, 1.205), (0.82, -1.15, 1.205), 6, "Z")
    p.slab(-0.57, -0.41, 0.42, 0.24, 0.02, 0.83, "soot")
    p.slab(-0.36, -0.56, 0.78, -0.14, -0.27, 1.74, "paint_recycler_green", bevel=0.03)
    # Back: the motor panel and its drum, the column behind the hopper, the funnel on its bulb.
    panel = Part("anim_slide_recycler_panel", pivot=(-0.43, 1.5, 1.2))
    panel.slab(-0.88, 1.57, 0.91, 0.02, 1.68, 1.46, "paint_recycler_green", bevel=0.03)
    detail.stripes(panel, (-0.88, 1.57, 1.33), (0.02, 1.68, 1.46), "+y", 7)
    detail.stripes(panel, (-0.88, 1.57, 1.33), (0.02, 1.68, 1.46), "+z", 7)
    panel.cyl((-0.03, 1.29, 1.12), 0.11, 1.08, "steel_dark", segs=10, axis="X")
    p.slab(-0.24, 0.46, 0.15, 0.01, 0.51, 0.96, "rust_recycler")
    # The motor box behind the hopper: a green housing with a roller on top, its windings and
    # the blue and red cables over it.
    p.slab(-0.84, 0.22, 0.4, -0.06, 1.0, 1.42, "paint_recycler_green", bevel=0.04)
    detail.panel(p, (-0.84, 0.22, 0.4), (-0.06, 1.0, 1.42), "-y", "paint_recycler_green", rivet="steel_light")
    detail.slots(p, (-0.84, 0.22, 0.4), (-0.06, 1.0, 1.42), "-x", 4)
    p.cyl((-0.45, 0.62, 1.55), 0.17, 0.74, "steel_dark", segs=12, axis="X")
    for x in (-0.72, -0.18):
        p.cyl((x, 0.62, 1.55), 0.2, 0.06, "rust_recycler", segs=12, axis="X")
    detail.coil(p, (-0.45, 0.62), 0.12, 1.75, 2.0, "copper_coil", turns=3)
    p.cyl((-0.45, 0.62, 1.86), 0.1, 0.4, "steel_dark", segs=8)
    detail.cable(p, [(-0.8, 0.3, 1.43), (-0.6, 0.15, 1.6), (-0.2, 0.2, 1.62), (0.05, 0.4, 1.3)], 0.022, "wire_blue")
    detail.cable(p, [(-0.7, 0.95, 1.43), (-0.4, 1.0, 1.66), (-0.1, 0.9, 1.6), (0.2, 1.05, 1.2)], 0.02, "wire_red")
    detail.cable(p, [(-0.9, 0.0, 0.9), (-0.95, 0.35, 1.2), (-0.8, 0.7, 1.45)], 0.022, "wire_blue")
    # The chain over the hopper's back end: a sprocket each side and the links sagging between.
    for x in (-0.5, 0.72):
        oil.toothed(p, x, 0.08, 1.12, 0.14, "steel_dark")
    for k in range(13):
        t = k / 12
        x = -0.5 + 1.22 * t
        z = 1.0 - 0.28 * math.sin(math.pi * t)
        p.box((x, 0.08, z), (0.06, 0.08, 0.07), "steel", rz=0)

    p.cyl((0.29, 1.21, 0.28), 0.49, 0.56, "rust_recycler", segs=18, radius_top=0.63, bevel=0.03)
    p.cyl((0.25, 1.32, 0.78), 0.635, 0.79, "rust_recycler", segs=18, radius_top=0.3)
    p.cyl((0.53, 1.335, 1.75), 0.24, 1.31, "paint_recycler_green", segs=16, radius_top=0.195)
    for k in range(4):   # straps down the funnel
        a = math.radians(45 + 90 * k)
        p.beam((0.53 + 0.245 * math.cos(a), 1.335 + 0.245 * math.sin(a), 1.12),
               (0.53 + 0.2 * math.cos(a), 1.335 + 0.2 * math.sin(a), 2.3), 0.05, 0.03, "rust_recycler",
               up=(math.cos(a), math.sin(a), 0))
    detail.cable(p, [(0.25, 1.0, 1.3), (0.45, 1.05, 1.45), (0.75, 1.1, 1.4)], 0.02, "wire_blue")
    p.cyl((0.85, 1.05, 1.0), 0.12, 0.04, "grime", segs=12, axis="Y")   # the bulb's round gauge
    ring(p, (0.53, 1.335), 0.12, 0.22, 2.36, 2.44, "brass", segs=16)
    p.cyl((0.53, 1.335, 2.4), 0.12, 0.02, "soot", segs=12)
    lamp = Part("anim_glow_recycler_lamp")  # the green lamp on the bulb's west side
    lamp.sphere((-0.2, 1.25, 1.0), 0.07, "lamp_recycler", segs=8, rings=4)
    # Front: the ribbed drum on its frame and the domed pot.
    drum = Part("anim_slide_recycler_drum", pivot=(0.23, -1.45, 0.72))
    drum.cyl((0.23, -1.45, 0.72), 0.485, 0.78, "steel_platform", segs=20, axis="X", bevel=0.03)
    for k in range(5):
        drum.cyl((-0.1 + k * 0.165, -1.45, 0.72), 0.505, 0.05, "steel_dark", segs=20, axis="X")
    p.slab(0.08, -1.55, 0.0, 0.3, -1.01, 0.35, "rust_recycler")
    p.slab(0.22, -1.86, 0.0, 0.94, -1.51, 0.54, "rust_recycler", bevel=0.03)
    detail.stripes(p, (0.22, -1.86, 0.36), (0.94, -1.51, 0.52), "-y", 6)
    p.cyl((-0.607, -1.463, 0.55), 0.445, 1.1, "rust_recycler", segs=16, radius_top=0.32, bevel=0.03)
    p.sphere((-0.54, -1.51, 1.11), 0.283, "rust_recycler", segs=14, rings=7)
    p.cyl((-0.54, -1.51, 1.4), 0.07, 0.1, "steel_light", segs=8)
    for z in (0.3, 0.75):
        p.cyl((-0.607, -1.463, z), 0.457 - 0.125 * z / 1.1, 0.05, "steel_dark", segs=16)
    p.slab(-0.82, -1.93, 0.25, -0.42, -1.9, 0.55, "grime")   # the pot's label plate
    detail.cable(p, [(-0.3, -1.6, 1.0), (-0.1, -1.7, 0.75), (0.05, -1.55, 0.5)], 0.02, "wire_red")
    return [p, drum, panel, lamp] + rollers



# ---------------------------------------------------------------------------------------------
# Lightning rod and lightning collector.

def insulator_mast(p, x, y, z0, z1, discs, r_disc=0.15, tip=0.9):
    """A thin mast with a stack of ceramic insulator discs and a copper tip on top."""
    p.cyl((x, y, (z0 + z1) / 2), 0.05, z1 - z0, "steel_dark", segs=8)
    for z in discs:
        p.cyl((x, y, z), r_disc, 0.06, "insulator_ceramic", segs=14, bevel=0.02)
        p.cyl((x, y, z - 0.06), r_disc * 0.6, 0.06, "insulator_ceramic", segs=12)
    p.cyl((x, y, z1 + tip / 2), 0.045, tip, "copper_tip", segs=8, radius_top=0.02)


@model("lightning-rod")
def lightning_rod():
    """Factorio's lightning rod (1x1): low boxes of cabling round the foot, a dark drum with a
    green dome on top and a cyan charge gauge in front, a cage of four posts with blue
    insulators and white balls, arms curving up to a collar, then a thin mast wound with a blue
    cable, four ceramic insulator discs and a long copper tip."""
    p = Part()
    p.slab(-0.45, -0.15, 0.0, 0.4, 0.4, 0.12, "steel_dark", bevel=0.02)
    p.slab(-0.5, -0.27, 0.0, -0.08, 0.25, 0.26, "steel_dark", bevel=0.03)
    p.slab(0.12, -0.26, 0.0, 0.3, 0.25, 0.22, "steel_dark", bevel=0.03)
    for x, c in ((-0.38, "copper_coil"), (-0.22, "insulator_ceramic"), (-0.3, "paint_fulgora_blue")):
        p.pipe([(x, -0.2, 0.26), (x + 0.05, -0.28, 0.45), (x + 0.12, -0.22, 0.7)], 0.03, c, segs=6)
    p.pipe([(-0.35, -0.1, 0.3), (-0.62, -0.15, 0.55), (-0.55, -0.2, 0.85), (-0.35, -0.25, 0.95)], 0.04, "insulator_green",
           segs=6)
    p.cyl((-0.03, 0.05, 0.62), 0.42, 0.84, "steel_dark", segs=20, bevel=0.03)
    ring(p, (-0.03, 0.05), 0.34, 0.45, 0.92, 1.08, "steel_light", segs=20)
    p.sphere((0, 0.1, 1.12), 0.2, "insulator_green", segs=12, rings=6)
    p.slab(0.08, -0.47, 0.2, 0.32, -0.3, 1.5, "steel_dark", bevel=0.03)
    p.slab(0.13, -0.49, 0.85, 0.27, -0.47, 1.45, "glow_cyan")
    p.cyl((0.42, -0.1, 1.15), 0.07, 0.4, "paint_fulgora_blue", segs=8)
    # The cage: four posts tied by a ring, arms curving up to the mast's collar.
    posts = [(-0.52, 0.3), (0.42, 0.3), (0.25, -0.3), (-0.35, -0.3)]
    for k, (x, y) in enumerate(posts):
        p.tube((x, y, 1.55), (x, y, 2.18), 0.04, "steel_dark", segs=6)
        p.cyl((x, y, 2.05), 0.065, 0.22, "paint_fulgora_blue", segs=8)
        p.sphere((x, y, 2.25 - 0.12 * (x < -0.5)), 0.075, "insulator_ceramic", segs=8, rings=4)
        nx, ny = posts[(k + 1) % 4]
        p.beam((x, y, 1.82), (nx, ny, 1.82), 0.07, 0.14, "steel_dark")
        p.pipe([(x, y, 1.75), (x * (0.4 if x > 0 else 0.1), y * 0.3, 2.45), (0.0, 0.0, 3.2)], 0.035, "steel_dark", segs=6)
    p.cyl((0, 0, 3.1), 0.07, 3.6, "steel_dark", segs=8)
    p.cyl((0, 0, 3.3), 0.13, 0.18, "insulator_ceramic", segs=12, bevel=0.02)
    p.pipe([(0.08 * math.cos(math.radians(120 * k)) - 0.03, 0.08 * math.sin(math.radians(120 * k)), 3.35 + 0.18 * k)
            for k in range(9)], 0.03, "paint_fulgora_blue", segs=6)
    for z in (4.98, 5.22, 5.46, 5.7):
        p.cyl((0, 0, z), 0.11, 0.07, "insulator_ceramic", segs=14, bevel=0.02)
        p.cyl((0, 0, z - 0.07), 0.07, 0.07, "insulator_ceramic", segs=10)
    p.cyl((0, 0, 6.55), 0.045, 1.5, "copper_coil", segs=8, radius_top=0.03)
    return [p, strike_sparks(0.0, 7.3, (0.82, 0.42), seed=1, tip_arcs=3, base_arcs=3)]


def strike_sparks(x, tip_z, base, seed, tip_arcs=5, base_arcs=6):
    """What a strike lights on a lightning attractor (its charge and discharge sheets: sparks at
    the tip and round the foot, the copper glowing): arcs down from the tip, a ring of short arcs
    about `base` = (height, radius). Shown only after a strike there (anim_lit_strike, anim.gd)."""
    q = Part("anim_lit_strike")
    for k in range(tip_arcs):
        a = math.radians(360 / tip_arcs * k + 20)
        kit.arc(q, (x, 0, tip_z), (x + 0.32 * math.cos(a), 0.32 * math.sin(a), tip_z - 0.9), seed=seed * 100 + k,
                kinks=4, jitter=0.07, width=0.02)
    z, r = base
    for k in range(base_arcs):
        a0, a1 = math.radians(360 / base_arcs * k), math.radians(360 / base_arcs * k + 40)
        kit.arc(q, (x + r * math.cos(a0), r * math.sin(a0), z), (x + r * math.cos(a1), r * math.sin(a1), z + 0.25),
                seed=seed * 100 + 10 + k, kinks=3, jitter=0.06, width=0.02)
    q.cyl((x, 0, tip_z - 0.4), 0.06, 0.8, "arc_blue", segs=8, radius_top=0.035)
    return q


@model("lightning-collector")
def lightning_collector():
    """Factorio's lightning collector (2x2): a round domed cage of dark ribs over blue tanks,
    coils and cables, with a grille and foot pads at the front; a column of struts and cables
    rising from it to a cream capsule with a cyan charge gauge, then a collar, a mast of five
    ceramic insulator discs and a long copper tip."""
    p = Part()
    cx = 0.05
    p.cyl((cx, 0, 0.12), 1.0, 0.24, "steel_dark", segs=24, bevel=0.03)
    # The dome: stacked frustums following the sprite's outline.
    prof = [(0.2, 1.0), (0.7, 0.95), (1.2, 0.84), (1.6, 0.69), (1.9, 0.48), (2.05, 0.3)]
    for (z0, r0), (z1, r1) in zip(prof, prof[1:]):
        # The dome's top is a cream deck, its sides the blue tanks.
        p.cyl((cx, 0, (z0 + z1) / 2), r0, z1 - z0, "paint_fulgora_cream" if z0 >= 1.6 else "paint_fulgora_blue",
              segs=24, radius_top=r1)
    for z, r in ((0.7, 0.98), (1.2, 0.87), (1.6, 0.71)):
        p.cyl((cx, 0, z), r + 0.02, 0.07, "steel_dark", segs=24)
    for a in range(0, 360, 45):
        t = math.radians(a + 22)
        p.pipe([(cx + 1.0 * math.cos(t), 1.0 * math.sin(t), 0.25), (cx + 0.97 * math.cos(t), 0.97 * math.sin(t), 1.0),
                (cx + 0.7 * math.cos(t), 0.7 * math.sin(t), 1.75), (cx + 0.22 * math.cos(t), 0.22 * math.sin(t), 2.1)],
               0.045, "steel_dark", segs=6)
    for a in (210, 250, 300):
        t = math.radians(a)
        p.cyl((cx + 0.82 * math.cos(t), 0.82 * math.sin(t), 0.55), 0.17, 0.5, "copper_coil", segs=10)
    # Front: the grille, a strut and the foot pads.
    p.box((-0.5, -0.85, 0.2), (0.45, 0.12, 0.4), "steel_dark", rz=-25)
    p.slab(-0.15, -1.15, 0.0, 0.15, -0.9, 0.6, "steel_dark", bevel=0.03)
    p.cyl((0.89, -0.96, 0.08), 0.24, 0.16, "steel_dark", segs=14, bevel=0.03)
    p.cyl((-0.86, -0.5, 0.15), 0.2, 0.3, "steel_dark", segs=14, bevel=0.03)
    p.pipe([(0.55, -0.75, 0.1), (0.7, -0.85, 0.45), (0.6, -0.7, 0.9)], 0.07, "rust_brown", segs=8)
    for x, y, z in ((-0.72, 0.1, 2.1), (0.53, 0.2, 2.27)):
        p.tube((x, y, 1.3), (x, y, z - 0.05), 0.03, "steel_dark", segs=6)
        p.sphere((x, y, z), 0.07, "insulator_ceramic", segs=8, rings=4)
    # The column of struts and cables, the capsule, collar, insulators and the copper tip.
    p.cyl((0.06, 0, 2.9), 0.17, 1.8, "steel_dark", segs=12)
    for sx in (-1, 1):
        p.tube((cx + sx * 0.2, 0, 2.05), (cx + sx * 0.15, 0, 3.8), 0.04, "steel_light", segs=6)

    p.cyl((0.03, 0, 4.1), 0.34, 0.8, "paint_fulgora_cream", segs=18, bevel=0.04)
    p.cyl((0.03, 0, 4.68), 0.34, 0.36, "paint_fulgora_cream", segs=18, radius_top=0.14)
    p.slab(-0.08, -0.35, 3.95, 0.16, -0.3, 4.4, "glow_cyan")
    p.slab(0.32, -0.1, 3.45, 0.42, 0.1, 3.65, "steel_dark")
    p.cyl((0.0, 0, 5.1), 0.13, 0.5, "insulator_ceramic", segs=12, bevel=0.02)
    insulator_mast(p, 0.01, 0, 5.3, 6.85, (5.5, 5.78, 6.07, 6.36, 6.65), r_disc=0.11, tip=1.55)
    return [p, strike_sparks(0.01, 8.4, (0.3, 1.05), seed=2)]


# ---------------------------------------------------------------------------------------------
# Tesla turret.

@model("tesla-turret")
def tesla_turret():
    """Factorio's tesla turret (4x4): a round grey plinth crowded with machinery round a tall
    column with a copper coil: a racetrack-shaped coil frame and a big drum on its side on the
    west, two boxes on the east, legs braced down to the front, a box at the front-left corner
    and a vented dome at the front-right. The head on top, a riveted helmet on a neck of black
    tubes with a spike either side, turns towards its target (anim_turret_head). Sizes fitted
    to the sprite's outline."""
    p = Part()
    p.cyl((0, -0.18, 0.1), 2.02, 0.2, "steel_dark", segs=32, radius_top=1.95, bevel=0.03)
    rim = Part()
    rim.ring_band((0, 0), 1.75, 2.0, 0.0, 0.3, 0, 360, "steel_platform", segs=32)
    p.add_part(rim, T(0, -0.18, 0.0))
    # The column, its coil, and the copper-wound skirt round it.
    p.cyl((0, 0, 1.12), 0.651, 1.84, "steel_platform", segs=20, radius_top=0.758, bevel=0.04)
    for z in (1.5, 1.65, 1.8):
        p.cyl((0, 0, z), 0.74, 0.1, "copper_coil", segs=20)
    p.cyl((-0.46, -0.13, 1.3), 1.064, 0.37, "steel_dark", segs=24, radius_top=0.164)
    # West: the coil frame at the back, the drum on its side, a box between.
    p.slab(-2.0, 0.82, 1.04, -0.53, 1.36, 1.41, "steel_dark", bevel=0.12)
    for x in (-1.6, -1.25, -0.9):
        p.cyl((x, 1.09, 1.42), 0.13, 0.3, "copper_coil", segs=10, axis="Y")
    p.cyl((-1.13, -0.06, 0.73), 0.619, 1.6, "steel_platform", segs=18, axis="X", bevel=0.04)
    for x in (-1.75, -1.5, -1.25):
        p.cyl((x, -0.06, 0.73), 0.64, 0.08, "steel_dark", segs=18, axis="X")
    p.cyl((-0.4, -0.06, 0.73), 0.3, 0.2, "copper_coil", segs=14, axis="X")
    p.slab(-1.26, -0.52, 0.21, -0.71, 0.26, 1.42, "steel_dark", bevel=0.05)
    # East: the big louvred box at the back, the motor box in front of it.
    p.slab(0.85, 0.35, 0.71, 1.97, 1.28, 1.77, "steel_platform", bevel=0.1)
    for k in range(5):
        p.slab(1.0 + k * 0.18, 0.5, 1.765, 1.1 + k * 0.18, 1.15, 1.79, "steel_dark")
    p.slab(0.22, -0.75, 0.88, 1.54, 0.59, 1.16, "steel_platform", bevel=0.05)
    p.cyl((1.0, -0.75, 1.0), 0.25, 0.12, "steel_light", segs=14, axis="Y")
    p.slab(0.2, -0.7, 0.0, 1.28, -0.59, 1.22, "steel_dark", bevel=0.03)
    # Front: legs braced down from the column, the corner box and the vented dome.
    for sx in (-1, 1):
        p.beam((sx * 0.45, -0.45, 1.6), (sx * 0.8, -1.95, 0.2), 0.4, 0.3, "steel_platform")
        p.beam((sx * 0.45, -0.45, 1.6), (sx * 0.8, -1.95, 0.2), 0.2, 0.34, "steel_dark")

    p.slab(-0.96, -2.1, 0.0, 1.3, -1.7, 0.7, "steel_dark", bevel=0.04)
    p.slab(-0.3, -2.0, 0.0, 0.3, -1.45, 1.3, "steel_platform", bevel=0.06)
    p.cyl((0.0, -2.02, 0.75), 0.18, 0.1, "steel_dark", segs=12, axis="Y")

    p.slab(-1.9, -2.19, 0.0, -0.56, -1.65, 0.48, "steel_platform", bevel=0.06)
    p.sphere((1.58, -2.0, 0.44), 0.435, "steel_platform", segs=16, rings=8)
    p.cyl((1.58, -2.41, 0.48), 0.15, 0.06, "steel_dark", segs=12, axis="Y")
    p.pipe([(-0.7, -0.6, 1.5), (-0.6, -1.4, 0.9), (0.0, -1.9, 0.6)], 0.08, "steel_black", segs=8)
    p.pipe([(-0.5, 0.6, 2.0), (-0.9, 0.9, 1.4), (-1.1, 1.0, 0.6)], 0.05, "paint_blue_dark", segs=8)
    # The head: a riveted helmet on a neck of black tubes, turning about the column.
    head = Part("anim_turret_head", pivot=(0.0, 0.0, 2.3))
    head.cyl((0, -0.11, 2.87), 0.232, 1.35, "steel_dark", segs=16, radius_top=0.266)
    for sx in (-0.15, -0.05, 0.05, 0.15):
        head.cyl((sx, -0.3, 3.0), 0.05, 1.1, "steel_black", segs=8)
    head.sphere((0, 0.25, 3.91), 0.54, "steel_platform", segs=18, rings=9)
    head.bolts_ring((0, 0.25, 3.91), 0.54, 10, axis="Z")
    head.slab(-0.66, 0.01, 3.59, 0.56, 0.08, 3.9, "steel_dark")
    for sx in (-1, 1):
        head.tube((sx * 0.55, 0.05, 3.75), (sx * 0.75, 0.05, 3.95), 0.03, "steel_light", segs=6)
    return [p, head]


# ---------------------------------------------------------------------------------------------
# Fulgurite: lightning-fused glass in the ground, mauve and knobbly, broken ends pink inside.
# Each limb is a chain of knobs fitted to the sprite's outline in screen tiles (x right, u up from
# the ground origin, r the knob's radius): seen from Factorio's camera a chain of balls and tapered
# tubes shows as the same chain of discs, whatever the depth. Standing limbs get a depth `y`;
# a knob that would end up under the ground (and lying limbs, y None) rests on it instead.

def _knob(x, u, r, y):
    z = r if y is None else zs(u, y)
    if z < r:
        z = r
    return Vector((x, ys(u, z), z))


def _fused(p, limbs, grow=1.03, segs=12):
    """limbs: (y, cut, [(x, u, r), ...]); `cut` ends the limb in the pink broken face."""
    for y, cut, knobs in limbs:
        pts = [_knob(x, u, r, y) for x, u, r in knobs]
        # 12-sided knobs show a little smaller than the round discs they were fitted as.
        rs = [r * grow for _, _, r in knobs]
        for k in range(len(pts)):
            p.sphere(pts[k], rs[k], "stone_fulgurite", segs=segs, rings=segs // 2)
            if k:
                p.tube(pts[k - 1], pts[k], rs[k - 1], "stone_fulgurite", segs=segs, radius_top=rs[k], caps=False)
        if cut:
            # A disc set into the end knob, just proud of its surface; the sprites' breaks are
            # slanted, their pink faces turned up towards the camera.
            d = ((pts[-1] - pts[-2]).normalized() + Vector((0, -0.6, 0.6))).normalized()
            p.tube(pts[-1] + d * (rs[-1] * 0.3), pts[-1] + d * (rs[-1] * 0.36), rs[-1] * 0.94,
                   "glass_fulgurite_core", segs=12)


@model("fulgurite")
def fulgurite():
    """A fulgurite: a crooked tube of fused glass standing up out of the ground, broken off at
    the top and at a stub on its west side, with a twig to the east and glassy roots running out
    across the ground."""
    p = Part()
    _fused(p, FULGURITE)
    return p


@model("fulgurite-small")
def fulgurite_small():
    """A small fulgurite: two broken glass stubs standing up, a third leaning west, and three
    pieces lying in the ground round them, one showing its pink broken end."""
    p = Part()
    _fused(p, FULGURITE_SMALL, grow=1.0, segs=16)





    return p


FULGURITE = [
    (0.1, True, [(-0.29, 0.15, 0.145), (-0.37, 0.31, 0.17), (-0.4, 0.57, 0.144), (-0.51, 0.74, 0.123),
                 (-0.51, 0.72, 0.147), (-0.48, 0.97, 0.167), (-0.47, 1.16, 0.199), (-0.39, 1.43, 0.141),
                 (-0.53, 1.73, 0.173), (-0.51, 1.91, 0.195), (-0.46, 2.07, 0.2), (-0.43, 2.31, 0.218),
                 (-0.42, 2.49, 0.193)]),
    (0.0, True, [(-0.34, 1.7, 0.212), (-0.47, 1.61, 0.158), (-0.69, 1.66, 0.192)]),
    (0.1, False, [(-0.35, 1.47, 0.148), (-0.07, 1.22, 0.126), (0.14, 1.05, 0.16), (0.23, 1.09, 0.109),
                  (0.29, 1, 0.07), (0.34, 0.95, 0.065), (0.39, 0.85, 0.06)]),
    (0.1, False, [(-0.08, 0.65, 0.07), (0.07, 0.84, 0.128), (0.03, 0.74, 0.16), (0.09, 0.48, 0.113),
                  (0.42, 0.08, 0.118), (0.55, 0.07, 0.109), (0.66, 0.11, 0.129), (0.82, -0.07, 0.161),
                  (0.94, -0.15, 0.127)]),
    (None, False, [(0.52, -0.01, 0.207), (0.6, -0.37, 0.134), (0.61, -0.63, 0.122), (0.72, -0.82, 0.15),
                   (0.7, -0.84, 0.146)]),
    (0.1, False, [(-0.18, 0.55, 0.114), (-0.43, 0.44, 0.112), (-0.61, 0.41, 0.072), (-0.76, 0.32, 0.09),
                  (-0.97, 0.14, 0.097)]),
    (None, False, [(-0.27, 0.06, 0.147), (-0.42, -0.13, 0.112), (-0.52, -0.27, 0.093), (-0.82, -0.53, 0.106),
                   (-0.99, -0.68, 0.133), (-1.06, -0.7, 0.07), (-1.04, -1.03, 0.07)]),
    (None, False, [(-0.28, -0.13, 0.084), (-0.2, -0.36, 0.082), (-0.21, -0.5, 0.097), (-0.33, -0.77, 0.103),
                   (-0.25, -1.17, 0.147)]),
]

FULGURITE_SMALL = [
    (0.0, True, [(0.29, 0.14, 0.163), (0.21, 0.245, 0.134), (0.15, 0.425, 0.127), (0.12, 0.685, 0.076),
                 (0.19, 1.045, 0.123)]),
    (0.0, False, [(-0.15, 0.61, 0.129), (0.1, 0.85, 0.143), (0.12, 0.93, 0.142)]),
    (0.1, True, [(0.12, -0.09, 0.071), (-0.2, 0.19, 0.128), (-0.36, 0.37, 0.162), (-0.48, 0.52, 0.133),
                 (-0.51, 0.585, 0.108)]),
    (None, False, [(-0.74, -0.23, 0.105), (-0.57, -0.28, 0.102), (-0.27, -0.25, 0.097), (-0.36, -0.24, 0.152),
                   (-0.25, -0.15, 0.127)]),
    (None, False, [(0.02, -0.36, 0.148), (0.14, -0.22, 0.161), (0.11, -0.12, 0.096), (0.34, -0.07, 0.08),
                   (0.09, -0.28, 0.107), (0.33, -0.13, 0.098), (0.27, -0.07, 0.072)]),
    (None, True, [(0.28, -0.56, 0.082), (0.24, -0.54, 0.102), (0.17, -0.47, 0.114)]),
]


# ---------------------------------------------------------------------------------------------
# Fulgoran ruin attractor: an old lightning tower.

@model("fulgoran-ruin-attractor")
def fulgoran_ruin_attractor():
    """The fulgoran attractor: a weathered round tower on a heap of broken blocks, two bent
    pipes running into it on the west, a banded cap with a hatch, a perforated cone and a ball
    on top, a little dish on a stalk and an aerial on the east. It still draws lightning.
    Pipe and aerial points are read off the sprite in screen tiles (x, u) at a chosen depth."""

    def at(x, u, y):
        return (x, y, zs(u, y))

    p = Part()
    # The heap of broken blocks round the foot.
    p.box((0.57, -0.97, 0.3), (0.82, 0.7, 0.6), "concrete_ruin", bevel=0.06, rz=4)
    p.box((-0.07, -0.66, 0.2), (0.78, 0.7, 0.4), "concrete_ruin", bevel=0.06, rz=-8)
    p.box((-0.75, -0.25, 0.16), (0.62, 0.6, 0.32), "concrete_ruin_dark", bevel=0.05, rz=12)
    p.box((0.3, -0.35, 0.25), (0.7, 0.5, 0.5), "concrete_ruin_dark", bevel=0.05)
    # The tower narrowing under its cap; the cap, cone and ball sit a little east of it.
    p.cyl((0.28, 0.0, 1.85), 0.63, 3.7, "concrete_ruin", segs=20, radius_top=0.55, bevel=0.03)
    for z in (1.2, 2.4):
        p.cyl((0.28, 0.0, z), 0.63 - z * 0.022 + 0.02, 0.1, "rust_ruin", segs=20)
    p.sphere((0.5, 0.0, 4.15), 0.63, "rust_ruin", segs=20, rings=10, scale=(1, 1, 0.6))
    p.slab(0.25, -0.6, 3.85, 0.8, -0.5, 4.3, "concrete_ruin_dark", bevel=0.02)
    p.cyl((0.49, 0.0, 4.9), 0.4, 1.2, "concrete_ruin_dark", segs=16, radius_top=0.26)
    p.sphere((0.55, 0.0, 5.72), 0.375, "concrete_ruin", segs=16, rings=8)    # Two pipes bent into the tower on the west, the outer one with a flange.
    p.pipe([at(-0.9, -0.1, -0.35), at(-0.78, 0.6, -0.35), at(-0.62, 1.2, -0.35), at(-0.45, 1.28, -0.35),
            at(-0.2, 1.12, -0.35)], 0.12, "steel_platform", segs=10)
    p.tube(at(-0.3, 1.14, -0.4), at(-0.05, 1.08, -0.4), 0.16, "steel_platform", segs=10)
    p.pipe([at(-0.52, -0.2, -0.55), at(-0.48, 0.6, -0.55), at(-0.4, 0.92, -0.55), at(-0.2, 0.95, -0.55)], 0.17,
           "steel_platform", segs=10)
    # The dish on its stalk, and the aerial.
    p.tube(at(-0.2, 2.1, -0.45), at(-0.3, 2.92, -0.45), 0.03, "steel_dark", segs=6)
    p.cyl(at(-0.33, 2.93, -0.45), 0.2, 0.06, "steel_platform", segs=14, bevel=0.02)
    p.slab(0.5, -0.62, 0.3, 0.75, -0.5, 2.2, "rust_ruin", bevel=0.03)
    p.tube(at(0.8, 1.3, -0.6), at(1.12, 1.74, -0.6), 0.05, "steel_dark", segs=6)
    p.sphere(at(1.12, 1.74, -0.6), 0.05, "steel_dark", segs=8, rings=4)
    return p
