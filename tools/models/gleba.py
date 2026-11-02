"""Gleba: biochamber, agricultural tower, heating tower, biolab, captive biter spawner, rocket
turret, capture robot, the Gleba plants, pentapods and spawners.

Each model is matched to Factorio's HR sprite with compare.py (client/assets/models/README.md,
"Matching a sprite"). Parts are placed from where they show in the sprite: `zs` / `ys` (space_kit)
turn a screen height into a height or a depth.
"""

import math
import os

from kit import Part, R, S, T, model
from space_kit import (COS_P, SIN_P, bent, blob, dome, flange, hose, lathe, profile_loft, ring, rock, stalk,
                       sweep, ys, zs)
import detail
import kit

# Parts under an `anim_glow_*` node glow in their material's colour while the machine works (their
# colour at rest is sampled from the sprite), so these carry the colour of Factorio's glow layers.
kit.MATERIALS.update({
    "glass_culture": ("b0c858", 0.2, 0.1, None, 0),  # biochamber tank and window, lit pale green
    "glass_bulb": ("9ab0f0", 0.2, 0.2, None, 0),     # biolab's bulbs in the brain, lit blue-violet
    "ember": ("e05a28", 0.6, 0.3, None, 0),          # heating tower's neck, red-hot behind its bars
    "copper_hot": ("f0a060", 0.5, 0.75, None, 0),    # heating tower's pipes, glowing with heat
})


# ---------------------------------------------------------------------------------------------
# Biochamber (3x3).

@model("biochamber")
def biochamber():
    """Factorio's biochamber: a tall glass tank of green culture on a ring base in the west half,
    a squat green cylinder behind it, a round planter tub in the north-east, a pump housing with
    a fan porthole and a little window in the east, a horizontal tank along the south-east edge,
    and brown copper pipes looping over and round all of it.

    Moving parts, from Factorio's animation (64 frames at 0.75, a loop in 1.42 s): the fan's four
    blades in the porthole (`anim_fan_biochamber`, turning about the north-south axis, four turns a
    loop); the culture tank's glass and the east window (`anim_glow_biochamber`) glow pale green
    while it works, as biochamber-glow and -glow-2 light them."""
    p = Part()
    glow = Part("anim_glow_biochamber")
    # Base plate under everything.
    p.slab(-1.42, -1.5, 0.0, 1.46, 1.38, 0.1, "steel_dark", bevel=0.03)

    # Glass tank on its ring base, west half.
    tx, ty = -0.5, 0.05
    bx, by = -0.5, -0.2
    lathe(p, (bx, by, 0.0), [(0.98, 0.0), (0.98, 0.42), (0.84, 0.5), (0.84, 0.54), (0.0, 0.54)],
          "copper_pipe_dark", segs=20)
    for a in (190, 235, 280, 325):  # green armour plates round the base
        c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
        p.box((bx + 0.99 * c, by + 0.99 * s, 0.25), (0.42, 0.07, 0.42), "paint_gleba", bevel=0.02,
              rz=a + 90)
    glass = [(0.7, 0.5), (0.7, 1.7), (0.67, 1.95), (0.58, 2.12), (0.42, 2.24), (0.22, 2.3), (0.0, 2.32)]
    lathe(glow, (tx, ty, 0.0), glass, "glass_culture", segs=20)
    lathe(p, (tx, ty, 0.0), [(0.6, 0.5), (0.6, 1.6), (0.45, 1.95), (0.0, 2.05)], "flesh_culture", segs=14)
    for z in (0.75, 1.35):  # brass bands round the glass
        lathe(p, (tx, ty, 0.0), [(0.72, z), (0.72, z + 0.06)], "copper_pipe", segs=20)
    p.cyl((tx, ty, 2.35), 0.16, 0.12, "copper_pipe", segs=12, bevel=0.02)
    # The pipe arching over the tank's top towards the back.
    bent(p, [(tx, ty, 2.35), (tx + 0.04, ty + 0.12, 2.68), (tx + 0.28, ty + 0.3, 2.74), (tx + 0.44, ty + 0.38, 2.4),
             (tx + 0.46, ty + 0.42, 1.6)], 0.08, "copper_pipe", segs=8)
    flange(p, (tx + 0.46, ty + 0.42, 1.6), 0.11, "Z", "copper_pipe_dark")

    # Squat green cylinder behind the tank (north-west).
    p.cyl((-1.0, 0.95, 0.5), 0.45, 1.0, "paint_gleba", segs=16, bevel=0.03)
    p.cyl((-1.0, 0.95, 1.02), 0.4, 0.05, "paint_gleba_dark", segs=16)

    # Planter tub in the north-east: a thick rim round a bed of green culture.
    ring(p, (0.78, 0.68), 0.58, 0.68, 0.0, 0.86, "paint_gleba_dark", segs=22)
    p.cyl((0.78, 0.68, 0.4), 0.6, 0.76, "glass_green", segs=22, caps=True)
    lathe(p, (0.78, 0.68, 0.0), [(0.6, 0.78), (0.5, 0.82), (0.25, 0.84), (0.0, 0.85)], "paint_gleba", segs=16)
    ring(p, (0.78, 0.68), 0.6, 0.74, 0.86, 0.92, "copper_pipe", segs=22)

    # Pump housing with the fan porthole facing south-west.
    p.slab(0.12, -0.1, 0.0, 0.95, 0.45, 1.05, "paint_gleba", bevel=0.05)
    p.slab(0.15, -0.45, 0.0, 0.92, -0.1, 0.55, "paint_gleba_dark", bevel=0.04)
    pz = 0.8
    p.cyl((0.58, -0.12, pz), 0.24, 0.06, "copper_pipe", segs=16, axis="Y", bevel=0.01)
    p.cyl((0.58, -0.15, pz), 0.19, 0.02, "soot", segs=16, axis="Y")
    fan = Part("anim_fan_biochamber", pivot=(0.58, -0.16, pz))
    for a in (45, 135):
        fan.box((0.58, -0.16, pz), (0.34, 0.02, 0.05), "copper_pipe", matrix=T(0.58, -0.16, pz) @ R("Y", a) @ T(-0.58, 0.16, -pz))
    # Small window cabinet east of it.
    p.slab(0.98, -0.25, 0.0, 1.42, 0.2, 0.95, "paint_gleba_dark", bevel=0.03)
    glow.slab(1.04, -0.27, 0.35, 1.36, -0.25, 0.8, "glass_culture")

    # Horizontal tank along the south-east edge, on two saddles.
    p.cyl((0.92, -1.26, 0.34), 0.32, 1.06, "paint_gleba", segs=16, axis="X", bevel=0.04)
    for x in (0.42, 1.42):
        p.cyl((x, -1.26, 0.34), 0.3, 0.04, "copper_pipe", segs=16, axis="X")
    for x in (0.62, 1.22):
        p.slab(x - 0.08, -1.48, 0.0, x + 0.08, -1.0, 0.14, "steel_dark")
    p.cyl((1.15, -1.58, 0.4), 0.09, 0.03, "copper_pipe", segs=10, axis="Y")

    # Front-left: a valve block with a red handwheel at the south edge.
    p.slab(-0.55, -1.52, 0.0, -0.15, -1.05, 0.32, "paint_gleba_dark", bevel=0.03)
    p.cyl((-0.35, -1.55, 0.18), 0.1, 0.03, "paint_red", segs=10, axis="Y")

    # Pipework: a loop round the tank's base, runs over to the pump and down to the tank.
    loop = []
    for i in range(13):
        a = math.radians(150 + i * 17)
        loop.append((tx + 0.98 * math.cos(a), ty + 0.98 * math.sin(a), 0.55 + 0.05 * math.sin(i)))
    bent(p, loop, 0.085, "copper_pipe", segs=8)
    bent(p, [(tx + 0.7, ty - 0.2, 0.9), (0.0, -0.25, 1.0), (0.2, -0.45, 0.9), (0.2, -0.75, 0.55),
             (0.35, -0.9, 0.55)], 0.095, "copper_pipe", segs=8)
    bent(p, [(-0.2, -0.85, 0.1), (-0.15, -0.85, 0.75), (0.1, -0.7, 0.95), (0.3, -0.4, 1.1), (0.5, 0.0, 1.15),
             (0.6, 0.4, 1.0)], 0.085, "copper_pipe", segs=8)
    bent(p, [(1.1, 0.25, 0.9), (1.2, 0.3, 1.2), (1.05, 0.5, 1.4), (0.7, 0.55, 1.3)], 0.085, "copper_pipe", segs=8)
    bent(p, [(-1.35, 0.4, 0.2), (-1.42, 0.0, 0.5), (-1.4, -0.5, 0.7), (-1.15, -0.85, 0.6)], 0.09,
         "copper_pipe", segs=8)
    bent(p, [(0.5, -0.85, 0.2), (0.3, -0.75, 0.45), (0.0, -0.95, 0.4), (-0.15, -1.15, 0.2)], 0.06,
         "copper_pipe", segs=8)
    for c, ax in (((tx + 0.98, ty - 0.1, 0.55), "X"), ((-1.42, -0.2, 0.6), "Y"), ((0.2, -0.6, 0.72), "Z")):
        flange(p, c, 0.13, ax, "copper_pipe_dark")
    _biochamber_detail(p, tx, ty, bx, by)
    return [p, fan, glow]


def _collar(p, c, r, axis, mat="copper_pipe_dark", bolts=6):
    """A bolted pipe collar: a flange ring with bolt heads round it (the sprite's pipe joints)."""
    flange(p, c, r, axis, mat, depth=0.07, segs=10)
    p.bolts_ring(c, r * 0.8, bolts, "steel_light", radius=0.016, axis=axis, depth=0.08)


def _biochamber_detail(p, tx, ty, bx, by):
    """The biochamber sprite's surface detail inside the fitted masses: bolted collars on the
    pipes, rivets on the armour plates and bands, moss in the planter, the porthole's bolts, the
    tank's bolted end cap, the window's frame."""
    for a in (190, 235, 280, 325):  # rivets in the corners of the armour plates round the base
        c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
        for du, dz in ((-0.15, 0.1), (0.15, 0.1), (-0.15, 0.4), (0.15, 0.4)):
            p.box((bx + 1.03 * c - du * s, by + 1.03 * s + du * c, dz), (0.035, 0.035, 0.035), "steel_light", rz=a + 90)
    for z in (0.75, 1.35):
        p.bolts_ring((tx, ty, z + 0.03), 0.73, 14, "copper_pipe_dark", radius=0.018, axis="Z", depth=0.07)
    for c, ax in (((tx + 0.46, ty + 0.42, 2.0), "Z"), ((-0.15, -0.85, 0.45), "Z"), ((0.2, -0.75, 0.55), "Z"),
                  ((tx - 0.84, ty - 0.48, 0.55), "Y"), ((1.2, 0.3, 1.2), "Z"), ((-1.41, -0.2, 0.62), "Z"),
                  ((0.25, -0.9, 0.5), "Y")):
        _collar(p, c, 0.12, ax)
    # The pipe hooped round the glass's front at half height, dropping to the valve block.
    hoop = [(tx + 0.78 * math.cos(math.radians(a)), ty + 0.78 * math.sin(math.radians(a)), 0.95) for a in range(185, 336, 15)]
    bent(p, hoop, 0.075, "copper_pipe", segs=8)
    bent(p, [hoop[6], (hoop[6][0], hoop[6][1] - 0.05, 0.6), (-0.3, -1.05, 0.35)], 0.07, "copper_pipe", segs=8)
    _collar(p, hoop[6], 0.11, "Y")
    _collar(p, hoop[2], 0.11, "Y")
    # The planter's moss: lumps of green growth on its bed, rivets round its rim.
    for i, (x, y) in enumerate(((0.62, 0.55), (0.9, 0.8), (0.75, 0.95), (1.0, 0.55), (0.55, 0.85), (0.85, 0.42))):
        blob(p, (x, y, 0.84), 0.13 + 0.03 * (i % 2), "glass_green" if i % 2 else "flesh_culture", segs=6, rings=3,
             scale=(1.2, 1.0, 0.45), seed=10 + i)
    p.bolts_ring((0.78, 0.68, 0.93), 0.67, 16, "steel_light", radius=0.018)
    # The pump housing: a riveted plate round the porthole, bolts round its rim.
    detail.panel(p, (0.12, -0.1, 0.0), (0.95, 0.45, 1.05), "-y", "paint_gleba", rivet="steel_light", margin=0.05)
    p.bolts_ring((0.58, -0.17, 0.8), 0.22, 8, "steel_light", radius=0.018, axis="Y", depth=0.04)
    # The window cabinet's frame.
    for x0, x1, z0, z1 in ((1.02, 1.38, 0.31, 0.35), (1.02, 1.38, 0.8, 0.84), (1.02, 1.06, 0.31, 0.84), (1.34, 1.38, 0.31, 0.84)):
        p.slab(x0, -0.29, z0, x1, -0.25, z1, "copper_pipe_dark")
    # The horizontal tank's bolted end cap and the rivets of its bands.
    p.cyl((1.47, -1.26, 0.34), 0.24, 0.04, "copper_pipe_dark", segs=14, axis="X")
    p.bolts_ring((1.49, -1.26, 0.34), 0.2, 10, "steel_light", radius=0.018, axis="X", depth=0.03)
    for x in (0.42, 1.42):
        p.bolts_ring((x, -1.26, 0.34), 0.31, 10, "steel_light", radius=0.016, axis="X", depth=0.05, start=200)
    # The valve block's plate and rivets, the base plate's edge bolts.
    detail.panel(p, (-0.55, -1.52, 0.0), (-0.15, -1.05, 0.32), "-y", "paint_gleba", margin=0.04)
    detail.rivet_line(p, (-1.3, -1.505, 0.06), (1.3, -1.505, 0.06), 12, "Y", "steel_light", r=0.016)


# ---------------------------------------------------------------------------------------------
# Agricultural tower (3x3) and its crane.

AT_MAST = (0.5, 0.55)   # the crane's origin, {0.5, -0.55, 4.6} in the prototype (y south)
AT_TOP = 4.0            # top of the open mast; the crane's hub sits on it


@model("agricultural-tower")
def agricultural_tower():
    """Factorio's agricultural tower: a smoked-glass dome on a squat round body in the west, a
    tall octagonal green mast in the north-east carrying the crane, and orange ribbed hoses
    hanging from mast and dome down to the ground, a hose reel lying in front.

    The crane (`anim_spin_crane`) is the hub on the mast with its counterweight and a boom
    reaching out over the field; the client turns it slowly while the tower works."""
    p = Part()
    dx, dy, dz = -0.43, 0.0, 1.25
    # Round body under the dome: dark steel with green panels and a fan box in front.
    lathe(p, (dx, dy, 0.0), [(1.1, 0.0), (1.1, 0.9), (1.0, 1.05), (0.97, dz), (0.0, dz)], "copper_pipe_dark", segs=24)
    for a in range(170, 345, 35):
        c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
        p.box((dx + 1.11 * c, dy + 1.11 * s, 0.5), (0.38, 0.06, 0.5), "paint_gleba", bevel=0.02, rz=a + 90)
    lathe(p, (dx, dy, 0.0), [(1.03, 1.0), (1.03, 1.1)], "copper_pipe", segs=24)
    p.slab(-1.05, -1.02, 0.25, -0.6, -0.82, 0.7, "steel_dark", bevel=0.03)
    p.cyl((-0.82, -1.03, 0.47), 0.17, 0.03, "steel_light", segs=14, axis="Y")
    p.cyl((-0.82, -1.05, 0.47), 0.13, 0.02, "soot", segs=14, axis="Y")
    # Smoked glass dome with copper ribs.
    dome(p, (dx, dy, dz), 1.0, 0.84, "glass_smoke", segs=24, rings=6)
    for a in (0, 60, 120, 180, 240, 300):
        rib = []
        for i in range(9):
            t = math.radians(90 * i / 8)
            r = 1.01 * math.cos(t)
            rib.append((dx + r * math.cos(math.radians(a)), dy + r * math.sin(math.radians(a)), dz + 0.86 * math.sin(t)))
        bent(p, rib, 0.025, "copper_pipe", segs=6, smooth=2)
    lathe(p, (dx, dy, 0.0), [(1.04, dz + 0.0), (1.07, dz + 0.04), (1.04, dz + 0.08)], "copper_pipe", segs=24)
    p.cyl((dx, dy, dz + 0.85), 0.12, 0.06, "copper_pipe", segs=12)
    # Pipe running round the dome's front at its foot, to an outlet in the south-east.
    bent(p, [(-1.45, -0.3, 1.05), (-1.05, -0.85, 1.05), (-0.4, -1.08, 1.05), (0.25, -0.85, 1.02), (0.35, -0.6, 0.75)],
         0.04, "steel_light", segs=6)
    p.cyl((0.35, -0.75, 0.62), 0.24, 0.25, "steel_dark", segs=12, axis="Y", bevel=0.02)

    # The mast: octagonal, green, steel bands, open at the top.
    mx, my = AT_MAST
    lathe(p, (mx, my, 0.0), [(0.4, 0.0), (0.4, 0.5), (0.33, 0.6), (0.33, AT_TOP), (0.27, AT_TOP), (0.27, AT_TOP - 0.3)],
          "paint_gleba", segs=8, a0=22.5, a1=382.5)
    for z in (1.5, 2.6, 3.55):
        lathe(p, (mx, my, 0.0), [(0.355, z), (0.355, z + 0.16)], "steel_light", segs=8, a0=22.5, a1=382.5)
    p.slab(mx - 0.2, my - 0.42, 0.2, mx + 0.2, my - 0.3, 3.4, "paint_gleba_dark", bevel=0.02)
    p.slab(mx + 0.18, my - 0.6, 0.0, mx + 0.75, my - 0.15, 1.9, "copper_pipe_dark", bevel=0.04)
    p.slab(mx + 0.25, my - 0.62, 0.4, mx + 0.7, my - 0.6, 1.6, "paint_gleba", bevel=0.01)
    # Green straps bracing the mast, splayed down to the ground on both sides.
    p.beam((mx - 0.28, my - 0.1, 3.0), (mx - 0.55, my - 0.25, 0.0), 0.2, 0.08, "paint_gleba")
    p.beam((mx + 0.3, my - 0.15, 2.9), (mx + 0.55, my - 0.4, 0.0), 0.2, 0.08, "paint_gleba")
    # A gearbox on the mast's south face.
    p.cyl((mx - 0.05, my - 0.42, 2.35), 0.16, 0.12, "steel", segs=12, axis="Y", bevel=0.02)
    p.cyl((mx + 0.12, my - 0.45, 2.15), 0.1, 0.1, "steel", segs=10, axis="Y", bevel=0.02)
    # Cabinet on the east edge.
    p.slab(0.95, -0.7, 0.0, 1.5, 0.05, 1.05, "copper_pipe_dark", bevel=0.04)
    p.slab(1.0, -0.72, 0.25, 1.45, -0.7, 0.95, "paint_gleba", bevel=0.01)
    # Dark machinery under the hoses in the south-east, a green post rising out of it.
    p.slab(0.5, -1.05, 0.0, 1.5, -0.3, 0.8, "copper_pipe_dark", bevel=0.04)
    p.slab(0.95, -1.0, 0.0, 1.18, -0.8, 1.55, "paint_gleba", bevel=0.02)

    # Orange ribbed hoses.
    H = "hose_orange"
    hose(p, [(0.36, -0.85, 0.62), (0.3, -1.15, 0.32), (-0.1, -1.42, 0.22), (-0.68, -1.6, 0.22)], 0.22, H, segs=10, rib=0.17)
    hose(p, [(-1.2, -0.45, 0.6), (-1.34, -0.85, 0.3), (-1.3, -1.3, 0.12)], 0.12, H, rib=0.13)
    hose(p, [(-1.1, -0.8, 0.5), (-1.25, -1.2, 0.25), (-1.2, -1.85, 0.12)], 0.11, H, rib=0.13)
    hose(p, [(-0.8, -0.95, 0.45), (-0.88, -1.3, 0.2), (-0.82, -1.85, 0.12)], 0.12, H, rib=0.13)
    hose(p, [(mx - 0.3, my, 2.85), (0.2, 0.45, 2.65), (-0.1, 0.3, 2.45), (-0.45, 0.15, 2.18)], 0.1, H, rib=0.11)
    hose(p, [(mx + 0.3, my - 0.15, 2.8), (mx + 0.35, my - 0.3, 2.2), (mx + 0.38, my - 0.5, 1.6), (1.2, -0.4, 0.85),
             (1.3, -0.85, 0.5), (1.28, -1.75, 0.19)], 0.19, H, rib=0.17)
    hose(p, [(mx + 0.1, my - 0.4, 2.4), (0.7, -0.2, 1.4), (0.68, -0.8, 0.9), (0.68, -1.75, 0.22)], 0.22, H, rib=0.17)
    bent(p, [(mx + 0.37, my + 0.05, 3.5), (mx + 0.41, my - 0.05, 2.6), (mx + 0.38, my - 0.2, 1.8)], 0.06, "copper_pipe", segs=6)
    hose(p, [(mx - 0.3, my + 0.0, 1.4), (mx - 0.5, my - 0.2, 1.8), (mx - 0.25, my - 0.45, 2.1)], 0.07, H, rib=0.1)
    # The hose reel standing in front, its wheel to the south.
    p.cyl((0.0, -2.1, 0.5), 0.5, 0.2, "steel_dark", segs=18, axis="Y", bevel=0.03)
    p.cyl((0.0, -2.21, 0.5), 0.38, 0.05, "steel", segs=18, axis="Y")
    p.cyl((0.0, -2.25, 0.5), 0.12, 0.06, "steel_light", segs=10, axis="Y")
    _agricultural_tower_detail(p, dx, dy, dz, mx, my)
    return [p, _crane()]


def _agricultural_tower_detail(p, dx, dy, dz, mx, my):
    """The tower sprite's surface detail inside its fitted masses: the pale pipes round the dome,
    rivets round its belt and the mast's bands, the fan in the porthole, the reel's stepped wheel,
    plates on the body and the cabinet."""
    # A pale pipe hooped round the dome's front and running down its west side, on clamps.
    hoop = []
    for i in range(9):
        a = math.radians(185 + i * 20)
        hoop.append((dx + 0.93 * math.cos(a), dy + 0.93 * math.sin(a), dz + 0.32))
    bent(p, hoop, 0.035, "steel_light", segs=6, smooth=2)
    bent(p, [hoop[0], (dx - 1.02, dy - 0.05, dz + 0.05), (dx - 1.1, dy - 0.15, 0.8), (dx - 1.1, dy - 0.4, 0.55)], 0.035,
         "steel_light", segs=6)
    for q in hoop[1::2]:
        p.box(q, (0.07, 0.07, 0.07), "steel_dark")
    # Rivets round the dome's belt and the body's band; plates' corner rivets.
    p.bolts_ring((dx, dy, dz + 0.04), 1.07, 30, "steel_light", radius=0.018, depth=0.1)
    p.bolts_ring((dx, dy, 1.05), 1.04, 30, "steel_light", radius=0.016, depth=0.1)
    for a in range(170, 345, 35):
        c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
        for du in (-0.14, 0.14):
            for z in (0.33, 0.67):
                p.box((dx + 1.14 * c - du * s, dy + 1.14 * s + du * c, z), (0.03, 0.03, 0.03), "steel_light", rz=a + 90)
    # The porthole's fan: three blades on a hub.
    for a in (0, 120, 240):
        p.box((0, 0, 0.06), (0.04, 0.012, 0.11), "steel_light", matrix=T(-0.82, -1.07, 0.47) @ R("Y", a))
    p.cyl((-0.82, -1.075, 0.47), 0.035, 0.02, "steel_light", segs=8, axis="Y")
    # The mast: rivets on its bands, a seam up its south face, a dark ring at its open top.
    for z in (1.58, 2.68, 3.63):
        p.bolts_ring((mx, my, z), 0.37, 16, "steel_light", radius=0.016, depth=0.04, start=11)
    p.slab(mx - 0.012, my - 0.345, 0.6, mx + 0.012, my - 0.33, AT_TOP - 0.05, "paint_gleba_dark")
    # The east cabinet's riveted plate and a vent, the south-east machinery's slots.
    detail.panel(p, (0.95, -0.7, 0.0), (1.5, 0.05, 1.05), "+x", "paint_gleba", rivet="steel_light", margin=0.08)
    detail.slots(p, (0.5, -1.05, 0.0), (1.5, -0.3, 0.8), "-y", 4)
    # The reel's stepped wheel and spokes.
    for r, y in ((0.3, -2.25), (0.22, -2.28)):
        p.cyl((0.0, y, 0.5), r, 0.03, "steel_dark", segs=16, axis="Y")
    for a in (0, 60, 120):
        p.box((0, 0, 0), (0.7, 0.03, 0.04), "steel", matrix=T(0.0, -2.24, 0.5) @ R("Y", a))


def _crane():
    """The crane at rest: a round hub on a turntable ringed by an orange hose, and the boom with
    its telescoping arm and grappler reaching south, as Factorio's first crane frame draws it
    (it turns about the mast's axis; the client spins it from this pose)."""
    mx, my = AT_MAST
    z0 = AT_TOP
    c = Part("anim_spin_crane", pivot=(mx, my, z0))
    # The turntable sits down inside the mast's open top, only its cap showing over the rim.
    z0 -= 0.3
    c.cyl((mx, my, z0 + 0.08), 0.3, 0.16, "steel_dark", segs=16, bevel=0.02)
    lathe(c, (mx, my, z0 + 0.16), [(0.3, 0.0), (0.3, 0.14), (0.24, 0.24), (0.0, 0.27)], "paint_gleba", segs=16)
    hose(c, [(mx - 0.3, my, z0 + 0.36), (mx, my + 0.34, z0 + 0.38), (mx + 0.3, my, z0 + 0.36)], 0.05, "hose_orange", rib=0.05)
    # Boom, south, rising slightly, and the arm hanging down from its tip (built north, turned).
    tip = (mx, my + 2.2, z0 + 0.7)
    c.beam((mx, my + 0.2, z0 + 0.35), tip, 0.18, 0.16, "paint_gleba", bevel=0.02)
    c.beam((mx, my + 0.2, z0 + 0.48), (tip[0], tip[1] - 0.2, tip[2] + 0.12), 0.06, 0.05, "steel_light")
    c.beam((mx, my + 0.6, z0 + 0.5), (mx, my + 0.6, z0 + 0.95), 0.05, 0.05, "steel_light")
    c.beam((mx, my + 0.6, z0 + 0.95), (tip[0], tip[1] - 0.1, tip[2] + 0.1), 0.04, 0.04, "steel_light")
    c.cyl((tip[0], tip[1], tip[2] - 0.6), 0.07, 1.2, "steel_light", segs=8)
    c.cyl((tip[0], tip[1], tip[2] - 1.25), 0.11, 0.12, "copper_pipe", segs=10)
    for a in (0, 120, 240):
        ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
        c.beam((tip[0], tip[1], tip[2] - 1.3), (tip[0] + 0.15 * ca, tip[1] + 0.15 * sa, tip[2] - 1.55), 0.03, 0.03, "steel")
    c.transform(T(mx, my, 0) @ R("Z", 180) @ T(-mx, -my, 0))
    return c


# ---------------------------------------------------------------------------------------------
# Heating tower (3x3).

@model("heating-tower")
def heating_tower():
    """Factorio's heating tower: a tall violet-steel furnace column in the west, its neck caged
    in brass bars up to an open rim; a lower boiler body in the east with a slim chimney; a brass
    burner drum and a grilled firebox in front, a ladder up the west side and copper pipes
    between them.

    While it burns (Factorio's working fire, 24 frames at 0.333, a loop in 1.2 s): the fire in the
    rim, the firebox window and a small flame on the chimney's top flicker (`fire_glow`), the neck's
    inner barrel glows red-hot between its bars (`anim_glow_fire`, the "fire" style), and the copper
    pipes glow with heat (`anim_glow_heat`, steady), as the fire layer and the heat picture draw them."""
    p = Part()
    ember = Part("anim_glow_fire")
    heat = Part("anim_glow_heat")
    # A wide plinth and a low housing fill the front, between the column and the firebox.
    p.slab(-1.15, -1.45, 0.0, 1.1, 1.2, 0.3, "steel_violet_dark", bevel=0.12)
    p.slab(-0.95, -1.2, 0.0, 0.45, -0.2, 0.62, "steel_violet", bevel=0.06)
    cx, cy = -0.55, 0.2
    lathe(p, (cx, cy, 0.0), [(0.72, 0.0), (0.72, 0.2), (0.66, 0.3), (0.6, 1.0), (0.56, 1.3), (0.55, 1.6), (0.48, 1.85), (0.4, 2.0),
                             (0.0, 2.0)], "steel_violet", segs=20)
    for z in (0.55, 1.2):
        lathe(p, (cx, cy, 0.0), [(0.66 - (z - 0.3) * 0.1, z), (0.66 - (z - 0.3) * 0.1, z + 0.06)], "steel_violet_dark", segs=20)
    # Neck: an inner barrel in a cage of brass bars, a thick rolled rim on top.
    lathe(ember, (cx, cy, 0.0), [(0.33, 1.95), (0.33, 3.57), (0.25, 3.57), (0.25, 3.2)], "ember", segs=16)
    for i in range(12):
        a = math.radians(i * 30 + 15)
        p.beam((cx + 0.38 * math.cos(a), cy + 0.38 * math.sin(a), 2.0), (cx + 0.38 * math.cos(a), cy + 0.38 * math.sin(a), 3.47),
               0.05, 0.04, "brass_dull")
    for z in (2.0, 2.65, 3.3):
        lathe(p, (cx, cy, 0.0), [(0.41, z), (0.41, z + 0.08)], "brass_dull", segs=16)
    lathe(p, (cx, cy, 0.0), [(0.3, 3.47), (0.42, 3.47), (0.47, 3.62), (0.42, 3.77), (0.3, 3.77), (0.3, 3.62)],
          "steel", segs=20)  # the rolled rim is bare pale steel
    p.cyl((cx, cy, 3.52), 0.27, 0.05, "fire_glow", segs=16)
    # Ladder up the west side.
    for x in (-1.2, -0.96):
        p.beam((x, -0.3, 0.0), (x, -0.3, 1.7), 0.04, 0.04, "steel_light")
    for k in range(9):
        p.beam((-1.2, -0.3, 0.25 + k * 0.17), (-0.96, -0.3, 0.25 + k * 0.17), 0.025, 0.025, "steel_light")
    # The long pipe running up across the front, and a red hose beside the chimney.
    bent(heat, [(-1.05, -0.95, 0.2), (-1.05, -0.75, 0.9), (-0.7, -0.6, 1.35), (0.0, -0.3, 1.75), (0.15, -0.1, 2.0)], 0.1, "copper_hot")
    hose(p, [(-0.15, -0.55, 1.35), (0.05, -0.6, 1.4), (0.3, -0.55, 1.3)], 0.09, "paint_red", rib=0.07)

    # East boiler body and its chimney.
    p.slab(0.05, -0.95, 0.0, 1.22, 1.1, 1.0, "steel_violet", bevel=0.12)
    p.slab(0.15, -0.85, 1.0, 1.12, 1.0, 1.08, "steel_violet_dark", bevel=0.03)
    lathe(p, (0.6, 0.45, 0.0), [(0.36, 1.0), (0.36, 1.4), (0.24, 1.6), (0.18, 2.0), (0.24, 2.1), (0.24, 2.3), (0.12, 2.35),
                                 (0.09, 2.7), (0.0, 2.7)], "steel_violet", segs=14)
    p.cyl((0.6, 0.45, 2.7), 0.06, 0.04, "soot", segs=8)
    lathe(p, (0.6, 0.45, 0.0), [(0.05, 2.72), (0.04, 2.82), (0.0, 3.02)], "fire_glow", segs=8)
    for x in (0.2, 1.1):
        p.cyl((x, 0.55, 1.12), 0.12, 0.25, "brass_dull", segs=10, bevel=0.02)
    # A brass tank at the east edge.
    p.cyl((1.05, -0.45, 0.95), 0.2, 0.55, "brass_dull", segs=12, bevel=0.04)

    # Burner drum, lying across the front, and the firebox under the east body.
    p.cyl((-0.3, -0.62, 1.2), 0.32, 0.6, "brass_dull", segs=16, axis="X", bevel=0.04,
          matrix=T(-0.3, -0.62, 1.2) @ R("Z", -25) @ T(0.3, 0.62, -1.2))
    p.cyl((-0.62, -0.78, 1.2), 0.2, 0.08, "steel_dark", segs=14, axis="X",
          matrix=T(-0.62, -0.78, 1.2) @ R("Z", -25) @ T(0.62, 0.78, -1.2))
    p.slab(0.42, -1.12, 0.0, 1.1, -0.8, 0.75, "steel_violet_dark", bevel=0.04)
    p.slab(0.55, -1.14, 0.25, 0.97, -1.1, 0.6, "fire_glow")
    for k in range(5):
        p.slab(0.55 + k * 0.1, -1.16, 0.25, 0.57 + k * 0.1, -1.12, 0.6, "steel_dark")
    # Small tanks along the front.
    for x, r, h in ((-0.95, 0.2, 0.65), (-0.2, 0.2, 0.75), (0.15, 0.14, 0.55)):
        p.cyl((x, -1.28, h / 2 + 0.05), r, h, "brass_dull" if x > -0.5 else "steel_violet_dark", segs=12, bevel=0.03)

    # Copper pipes, hot.
    C = "copper_hot"
    bent(heat, [(-1.18, 0.4, 0.3), (-1.22, 0.0, 1.0), (-1.12, -0.05, 1.8), (-0.9, 0.0, 2.1)], 0.095, C)
    bent(heat, [(-1.0, -0.65, 0.9), (-0.85, -0.5, 1.4), (-0.3, -0.45, 1.75), (0.2, -0.3, 1.95), (0.4, 0.0, 2.1)], 0.095, C)
    bent(heat, [(-1.2, -1.25, 0.55), (-0.9, -1.4, 0.65), (-0.2, -1.42, 0.65), (0.3, -1.3, 0.8)], 0.095, C)
    bent(heat, [(-0.1, -0.6, 2.0), (0.25, -0.6, 2.2), (0.3, 0.0, 2.6), (0.2, 0.3, 2.3)], 0.08, C)
    bent(p, [(1.1, 0.4, 0.4), (1.16, 0.1, 0.8), (1.1, -0.4, 1.35)], 0.07, "paint_red")
    # The pipe arching from the column's shoulder over to the boiler, and a louvred box under it.
    bent(heat, [(cx + 0.42, cy + 0.05, 2.15), (0.0, 0.4, 2.4), (0.3, 0.3, 2.15), (0.35, 0.05, 1.5)], 0.11, C)
    p.slab(-0.08, 0.25, 0.9, 0.32, 0.95, 1.6, "steel_violet_dark", bevel=0.03)
    for k in range(5):
        p.slab(-0.04, 0.23, 1.0 + k * 0.12, 0.28, 0.25, 1.05 + k * 0.12, "steel_light")
    flange(p, (-1.22, 0.05, 0.8), 0.1, "Z", "copper_pipe_dark")
    _heating_tower_detail(p, cx, cy)
    return [p, ember, heat]


def _heating_tower_detail(p, cx, cy):
    """The heating tower sprite's surface detail inside its fitted masses: the ring of vent holes
    in the rim, rivets on the column's bands and the boiler's edges, plates on the boiler, the
    burner drum's bolted hatch and bands, clamps on the pipes, the firebox's bolted frame."""
    p.bolts_ring((cx, cy, 3.775), 0.38, 14, "soot", radius=0.03, depth=0.012)
    p.bolts_ring((cx, cy, 3.62), 0.47, 20, "steel_light", radius=0.018, axis="Z", depth=0.02)
    for z in (0.58, 1.23):
        r = 0.66 - (z - 0.3) * 0.1 + 0.005
        for i in range(12):
            a = math.radians(200 + i * 13)
            p.box((cx + r * math.cos(a), cy + r * math.sin(a), z), (0.03, 0.03, 0.03), "steel_light", rz=math.degrees(a))
    p.bolts_ring((cx, cy, 2.04), 0.42, 12, "steel_light", radius=0.018, depth=0.04)
    # The column's lower plates: seams between them.
    for a in (220, 260, 300, 340):
        r = math.radians(a)
        p.box((cx + 0.64 * math.cos(r), cy + 0.64 * math.sin(r), 0.95), (0.02, 0.05, 0.7), "steel_violet_dark", rz=a)
    # The boiler: riveted plates on its south and east faces, rivets along its top edge.
    detail.panel(p, (0.05, -0.95, 0.0), (1.22, 1.1, 1.0), "+x", "steel_violet", rivet="steel_light", margin=0.12, split=2)
    detail.panel(p, (0.05, -0.95, 0.75), (0.42, 1.1, 1.0), "-y", "steel_violet", margin=0.04)
    detail.rivet_line(p, (0.2, -0.86, 1.085), (1.08, -0.86, 1.085), 7, "Z", "steel_light", r=0.016)
    # The burner drum: bands and a bolted round hatch on its end.
    drum = T(-0.3, -0.62, 1.2) @ R("Z", -25)
    for x in (-0.18, 0.18):
        p.cyl((x, 0, 0), 0.335, 0.05, "copper_pipe_dark", segs=16, axis="X", matrix=drum)
    for i in range(8):
        a = 2 * math.pi * i / 8
        p.cyl((-0.045, 0.16 * math.cos(a), 0.16 * math.sin(a)), 0.018, 0.03, "steel_light", segs=6, axis="X",
              matrix=T(-0.62, -0.78, 1.2) @ R("Z", -25))
    # The firebox's bolted frame and the clamps round the hot pipes.
    detail.rivet_line(p, (0.52, -1.165, 0.65), (1.0, -1.165, 0.65), 6, "Y", "steel_light", r=0.016)
    detail.rivet_line(p, (0.52, -1.165, 0.2), (1.0, -1.165, 0.2), 6, "Y", "steel_light", r=0.016)
    for q in ((-1.05, -0.8, 0.75), (-0.62, -0.57, 1.42), (-1.21, 0.1, 1.15), (-0.55, -1.42, 0.65), (0.15, -0.33, 1.83)):
        p.box(q, (0.24, 0.24, 0.06), "steel_dark", bevel=0.01)
    # The small tanks' bands.
    for x, r, h in ((-0.95, 0.2, 0.65), (-0.2, 0.2, 0.75), (0.15, 0.14, 0.55)):
        for z in (0.2, h - 0.1):
            p.cyl((x, -1.28, z), r + 0.012, 0.04, "steel_dark", segs=12)


# ---------------------------------------------------------------------------------------------
# Biolab (5x5).

def _canister(p, x, y, z0, r, h, glass=None, mat="steel_teal"):
    """An upright capsule: steel caps, an optional window band of `glass`."""
    lathe(p, (x, y, 0.0), [(r * 0.8, z0), (r, z0 + 0.06), (r, z0 + h - 0.06), (r * 0.7, z0 + h), (0.0, z0 + h)], mat, segs=12)
    if glass:
        lathe(p, (x, y, 0.0), [(r * 1.02, z0 + h * 0.3), (r * 1.02, z0 + h * 0.75)], glass, segs=12)


@model("biolab")
def biolab():
    """Factorio's biolab: a big pink brain under a steel cage of struts and hubs, glass bulbs
    set in it, on a ring base; a column carrying purple bulbs in the north-west, a pale glass
    bellows with a claw in the north-east, a machinery stack on the east edge, a fan box and a
    blue glass tube in the south-east, canisters and flesh spilling out round the bottom.

    Moving parts, from Factorio's animation (32 frames at 0.2, a loop in 2.67 s; Factorio plays it
    idle too): the four purple vials on the north-west column (`anim_vial_biolab_fw`, `_fe`, `_bw`,
    `_be`, each turning about its own level axis through the column) dip down and rise back once a
    loop; the bellows' outer half with its claw (`anim_bellows_biolab`) pushes in along the drum and
    out again; the glass bulbs in the brain (`anim_glow_biolab`) glow blue-violet, breathing and
    flickering as biolab-lights does."""
    p = Part()
    glow = Part("anim_glow_biolab")
    moving = [glow]
    cx, cy, zb = 0.0, -0.12, 0.47
    rx, h = 1.8, 1.2
    lathe(p, (cx, cy, 0.0), [(2.0, 0.0), (2.0, 0.3), (1.9, zb), (0.0, zb)], "steel_teal", segs=28)
    lathe(p, (cx, cy, 0.0), [(2.03, 0.15), (2.03, 0.25)], "copper_pipe_dark", segs=28)
    # The brain: lumps over an ellipsoid.
    dome(p, (cx, cy, zb), rx - 0.05, h - 0.05, "flesh_pink", segs=24, rings=7)
    for i in range(18):
        a = i * 2.39996
        t = (i + 0.5) / 18
        el = math.asin(t) * 0.9
        r = (rx - 0.15) * math.cos(el)
        blob(p, (cx + r * math.cos(a), cy + r * math.sin(a), zb + (h - 0.15) * math.sin(el)), 0.32, "flesh_pink" if i % 3 else "flesh_purple",
             segs=7, rings=5, scale=(1.0, 1.0, 0.6), seed=i)
    # Glass bulbs in the brain.
    for a, el in ((30, 0.55), (110, 0.5), (200, 0.6), (300, 0.45), (250, 0.25), (160, 0.85), (0, 0.15)):
        ar = math.radians(a)
        r = rx * math.cos(el)
        glow.sphere((cx + r * math.cos(ar), cy + r * math.sin(ar), zb + h * math.sin(el) + 0.05), 0.24, "glass_bulb", segs=10, rings=6,
                    scale=(1, 1, 0.8))
    # Cage: meridian struts, two rings, hubs where they meet.
    def on(a, el, out=0.06):
        return (cx + (rx + out) * math.cos(el) * math.cos(a), cy + (rx + out) * math.cos(el) * math.sin(a),
                zb + (h + out) * math.sin(el))
    for k in range(8):
        a = math.radians(k * 45 + 22.5)
        bent(p, [on(a, math.radians(e)) for e in range(0, 91, 10)], 0.055, "steel_teal", segs=6, smooth=2)
    for el in (25, 55):
        e = math.radians(el)
        bent(p, [on(math.radians(k * 15), e) for k in range(25)], 0.05, "steel_teal", segs=6, smooth=1)
        for k in range(8):
            a = math.radians(k * 45 + 22.5)
            q = on(a, e, 0.1)
            p.sphere(q, 0.1, "steel_teal", segs=8, rings=4, scale=(1, 1, 0.7))
    for k in range(8):  # pointed plates round the foot of the cage
        a = math.radians(k * 45 + 22.5)
        q = on(a, math.radians(6), 0.05)
        p.box(q, (0.22, 0.06, 0.3), "steel_teal", bevel=0.02, rz=math.degrees(a) + 90)
    p.cyl((cx, cy, zb + h + 0.08), 0.15, 0.12, "steel_teal", segs=12, bevel=0.03)

    # North-west column with purple bulbs on four arms: the front pair reaching out east and
    # west, the back pair higher. A machinery block west of it.
    qx, qy = -0.95, 1.65
    p.slab(qx - 0.6, qy - 0.5, 0.0, qx + 0.7, qy + 0.68, 1.1, "steel_dark", bevel=0.08)
    p.slab(-2.15, 1.2, 0.0, qx - 0.5, 2.3, 0.6, "steel_dark", bevel=0.08)
    lathe(p, (qx, qy, 0.0), [(0.3, 1.1), (0.3, 1.45), (0.2, 1.6), (0.2, 2.1), (0.27, 2.15), (0.27, 2.3), (0.0, 2.35)],
          "steel_teal", segs=14)
    for kind, (ex, ey, ez) in zip(("fw", "fe", "bw", "be"),
                                  ((-0.65, -0.35, 1.85), (0.65, -0.35, 1.85), (-0.33, 0.3, 2.0), (0.33, 0.3, 2.0))):
        arm = Part("anim_vial_biolab_" + kind, pivot=(qx, qy, ez - 0.05))
        e = (qx + ex, qy + ey, ez)
        arm.beam((qx, qy, ez - 0.05), e, 0.06, 0.06, "steel_teal")
        arm.sphere((e[0], e[1], e[2] + 0.1), 0.19, "glow_purple", segs=10, rings=6)
        moving.append(arm)
    p.cyl((qx - 0.6, qy - 0.55, 1.25), 0.25, 0.3, "steel_teal", segs=12, bevel=0.03)

    # North-east bellows: a pale glass corrugated drum rising to the east, a claw beyond it.
    # The bellows telescopes: its outer (east) half, a little wider, slides over the inner half.
    bx, by, bz = 1.3, 1.85, 1.72
    a, b = (bx - 0.55, by - 0.1, bz - 0.25), (bx + 0.55, by + 0.1, bz + 0.3)
    m = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2)
    d = [(b[i] - a[i]) / 1.246 for i in range(3)]
    bellows = Part("anim_bellows_biolab", pivot=b)
    hose(p, [a, m], 0.4, "glass_pale", segs=14, rib=0.2, depth=0.12)
    hose(bellows, [tuple(m[i] - 0.05 * d[i] for i in range(3)), b], 0.42, "glass_pale", segs=14, rib=0.2, depth=0.12)
    moving.append(bellows)
    p.slab(bx - 0.75, by - 0.4, 0.0, bx + 1.1, by + 0.48, bz - 0.25, "steel_dark", bevel=0.08)
    for k in (-1, 1):
        q = (bx + 0.62 * k, by + 0.11 * k, bz + 0.03 + 0.3 * k)
        (bellows if k > 0 else p).cyl(q, 0.43, 0.1, "steel_teal", segs=14, axis="X", bevel=0.02,
                                      matrix=T(*q) @ R("Y", -26) @ T(-q[0], -q[1], -q[2]))
    bellows.beam((bx + 0.7, by, bz + 0.3), (bx + 0.95, by - 0.05, bz + 0.7), 0.08, 0.08, "steel_teal")
    bellows.beam((bx + 0.95, by - 0.05, bz + 0.7), (bx + 1.1, by - 0.2, bz + 0.45), 0.06, 0.06, "steel_teal")
    bellows.beam((bx + 0.95, by - 0.05, bz + 0.7), (bx + 1.1, by + 0.15, bz + 0.45), 0.06, 0.06, "steel_teal")
    p.cyl((0.3, 1.95, 1.5), 0.22, 0.08, "steel_dark", segs=14, axis="Y")  # gear behind the dome
    p.sphere((0.8, 1.6, 1.75), 0.3, "steel_teal", segs=12, rings=6, scale=(1, 1, 0.8))

    # East machinery stack.
    p.slab(1.75, -0.2, 0.0, 2.42, 1.9, 1.65, "steel_dark", bevel=0.08)
    p.slab(1.8, -0.22, 0.4, 2.37, -0.2, 1.45, "steel_teal", bevel=0.01)
    for z in (0.65, 0.95, 1.25):
        p.cyl((2.1, -0.24, z), 0.12, 0.03, "copper_pipe", segs=10, axis="Y")
    # The sprite's south row stands a little past the footprint: a low dark plinth of pipes and
    # boxes under the parts standing on it.
    p.slab(-2.3, -2.85, 0.0, 2.3, -1.5, 0.3, "steel_dark", bevel=0.05)
    # South-east fan box with the motor on top, and the blue glass tube above it.
    p.slab(1.2, -2.88, 0.0, 2.35, -2.15, 1.35, "steel_teal", bevel=0.07)
    p.cyl((1.85, -2.9, 0.7), 0.4, 0.04, "steel_dark", segs=14, axis="Y")
    p.cyl((1.85, -2.92, 0.7), 0.33, 0.02, "soot", segs=14, axis="Y")
    for k in range(4):
        p.slab(1.25 + k * 0.28, -2.91, 0.05, 1.37 + k * 0.28, -2.88, 0.13, "hazard_black")
    p.cyl((1.75, -2.45, 1.55), 0.3, 0.4, "steel_teal", segs=14, axis="Y", bevel=0.03)
    p.cyl((1.75, -2.66, 1.55), 0.24, 0.02, "soot", segs=14, axis="Y")
    p.cyl((1.4, -0.85, 0.95), 0.2, 0.75, "glow_cyan", segs=12, axis="X",
          matrix=T(1.4, -0.85, 0.95) @ R("Z", -20) @ T(-1.4, 0.85, -0.95))
    for dx_ in (-0.4, 0.4):
        p.cyl((1.4 + dx_, -0.85 - dx_ * 0.36, 0.95), 0.23, 0.08, "steel_teal", segs=12, axis="X",
              matrix=T(1.4 + dx_, -0.85 - dx_ * 0.36, 0.95) @ R("Z", -20) @ T(-1.4 - dx_, 0.85 + dx_ * 0.36, -0.95))

    # Canisters round the south and west: a tall one at the front, one lying in the south-west
    # corner with its round end out, a green glass panel, small boxes and a blue bottle.
    _canister(p, -2.15, -1.55, 0.0, 0.3, 1.0, "glass_green")
    _canister(p, -0.8, -2.7, 0.0, 0.3, 1.85)
    p.cyl((0, 0, 0), 0.3, 0.75, "steel_teal", segs=12, axis="Y", bevel=0.05,
          matrix=T(-1.85, -2.35, 0.32) @ R("Z", -35))
    p.sphere((-2.07, -2.66, 0.32), 0.28, "steel_teal", segs=10, rings=5)
    p.slab(-1.8, -2.55, 0.0, -1.05, -1.85, 0.8, "glass_green", bevel=0.04)
    p.slab(-0.45, -2.88, 0.0, 0.05, -2.45, 0.6, "steel_teal", bevel=0.04)
    p.slab(0.45, -2.88, 0.0, 1.05, -2.4, 0.7, "steel_teal", bevel=0.04)
    p.cyl((1.27, -2.75, 0.4), 0.15, 0.8, "glow_cyan", segs=10, bevel=0.03)
    p.slab(-2.3, -1.3, 0.0, -1.6, 1.0, 0.7, "steel_dark", bevel=0.06)
    # Black hoses from the canisters up into the cage.
    for a, b in (((-2.15, -1.55, 1.0), (-1.4, -0.9, 1.0)), ((-0.8, -2.7, 1.85), (-0.6, -1.6, 1.3)),
                 ((-2.1, -0.3, 0.6), (-1.75, 0.0, 0.9))):
        bent(p, [a, ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, max(a[2], b[2]) + 0.35), b], 0.085, "rubber", segs=6)
    # Flesh spilling out at the bottom, west and east.
    for i, (x, y, s) in enumerate(((-1.95, 0.4, 0.35), (-1.7, -1.0, 0.4), (-1.95, 1.3, 0.35), (2.0, -0.8, 0.35),
                                   (-1.2, -1.6, 0.35), (0.6, -1.85, 0.3), (-0.2, -2.1, 0.35), (1.0, -2.05, 0.3), (2.1, -1.55, 0.35))):
        blob(p, (x, y, s * 0.82), s, "flesh_dark" if x < -1.5 else "flesh_pink", segs=8, rings=5, scale=(1.2, 1.0, 0.7), seed=40 + i)
    _biolab_detail(p, cx, cy, zb, rx, h, on)
    return [p] + moving


def _biolab_detail(p, cx, cy, zb, rx, h, on):
    """The biolab sprite's surface detail inside its fitted masses: bolted caps on the cage's hubs
    and lozenge plates where its struts cross, the bolted crown, conduits up the front into the
    brain, the fan's blades and grille, banded and riveted canisters, gears on the east stack."""
    for el in (25, 55):
        for k in range(8):
            a = math.radians(k * 45 + 22.5)
            q = on(a, math.radians(el), 0.17)
            p.sphere(q, 0.035, "steel_light", segs=6, rings=3)
    for k in range(8):  # lozenge plates on the struts between the rings
        a = math.radians(k * 45 + 22.5)
        q = on(a, math.radians(40), 0.08)
        p.box(q, (0.16, 0.05, 0.16), "steel_teal", bevel=0.01,
              matrix=T(*q) @ R("Z", math.degrees(a) + 90) @ R("X", -40) @ R("Y", 45) @ T(-q[0], -q[1], -q[2]))
    p.bolts_ring((cx, cy, zb + h + 0.15), 0.11, 6, "steel_light", radius=0.016)
    # Conduits up the front from the plinth into the brain's foot, slots in the plinth.
    for i, x in enumerate((-0.45, -0.3, -0.12, 0.25, 0.42)):
        p.cyl((x, -1.62, 0.55), 0.03 if i % 2 else 0.04, 0.5, "steel_dark" if i % 2 else "steel_teal", segs=6)
    detail.slots(p, (-2.3, -2.85, 0.0), (2.3, -1.5, 0.3), "-y", 2)
    # The fan: blades behind a grille ring, rivets on its box.
    for k in range(6):
        p.box((0, 0, 0.16), (0.08, 0.012, 0.26), "steel_dark", matrix=T(1.85, -2.9, 0.7) @ R("Y", k * 60 + 15))
    for r in (0.31, 0.2):
        lathe(p, (1.85, -2.935, 0.7), [(r - 0.02, 0.0), (r, 0.0), (r, 0.02), (r - 0.02, 0.02)], "steel_teal", segs=16, axis="Y")
    p.slab(1.83, -2.93, 0.4, 1.87, -2.91, 1.0, "steel_teal")
    p.slab(1.55, -2.93, 0.68, 2.15, -2.91, 0.72, "steel_teal")
    detail.rivet_line(p, (1.27, -2.89, 1.28), (2.28, -2.89, 1.28), 7, "Y", "steel_light", r=0.016)
    detail.panel(p, (1.2, -2.88, 0.0), (2.35, -2.15, 1.35), "+z", "steel_teal", rivet="steel_light", margin=0.08)
    # The canisters' bands.
    for x, y, r, hh in ((-2.15, -1.55, 0.3, 1.0), (-0.8, -2.7, 0.3, 1.85)):
        for z in (0.15, hh - 0.18):
            # (they stand at the sprite's outline: bands only, no proud rivets)
            p.cyl((x, y, z), r + 0.008, 0.06, "steel_dark", segs=12)
    # Gears on the east stack's top, a riveted plate on it.
    detail.gear(p, (2.08, 1.3), 0.24, 1.65, 1.71, "steel_teal", hub="steel_dark", holes=4)
    detail.gear(p, (2.12, 0.72), 0.16, 1.65, 1.7, "copper_pipe", hub="steel_dark")
    detail.rivet_line(p, (1.82, -0.235, 1.38), (2.33, -0.235, 1.38), 5, "Y", "steel_light", r=0.016)


# ---------------------------------------------------------------------------------------------
# Captive biter spawner (5x5).

import kit  # noqa: E402

kit.MATERIALS.update({
    "flesh_pad": ("c8a890", 0.6, 0.0, None, 0),  # the pale pads on the captive spawner's mound
})

def _tentacle(p, root, tip, r0, mat, seed, segs=7):
    """A tapering claw of flesh from `root` out to `tip`, sagging to the ground."""
    a, b = root, tip
    mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, max(a[2], b[2]) * 0.6 + r0 * 0.6)
    pts = [a, mid, b]
    from space_kit import catmull
    path = catmull(pts, 4)
    n = len(path)
    sweep(p, path, r0, mat, segs, True, [r0 * (1.0 - 0.8 * i / (n - 1)) for i in range(n)])


@model("captive-biter-spawner")
def captive_biter_spawner():
    """Factorio's captive biter spawner: a biter spawner's broad fleshy mound with five pale pads
    on its slopes, ringed by folds of flesh and claws splayed out on the ground (two big ones to
    the south-west and south-east), held captive by machinery: steel canisters with windows lying
    in the flesh at the front with black hoses into it, a sealed drum standing on top at the back,
    and in the north-east the biolab's pale bellows with a claw arm on a dark machinery block.

    The sprite spills well past the 5x5 footprint (the claws reach a tile further south), so the
    mound's foot and the claws do too; pads and parts are placed from where the sprite shows them.

    Moving parts, from Factorio's animation (32 frames at 0.4, a loop in 1.33 s): the five pale pads
    (`anim_pads_captive`) swell up out of their red rims and settle once a loop, as the captive
    spawner breathes; the bellows' outer half with its claw (`anim_bellows_captive`) pushes in along
    the drum and out again."""
    p = Part()
    pads = Part("anim_pads_captive")
    cx, cy, rx, ry, H = 0.1, 0.0, 2.3, 2.2, 1.45

    def mound_z(x, y):
        d = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2
        return H * math.sqrt(max(0.0, 1.0 - d))

    def on_mound(x, u):
        """The mound's surface point at x that shows u tiles up the screen (its visible side)."""
        lo, hi = cy - ry, cy + ry
        for _ in range(40):
            y = (lo + hi) / 2
            if SIN_P * y + COS_P * mound_z(x, y) < u:
                lo = y
            else:
                hi = y
        return x, y, mound_z(x, y)

    dome(p, (cx, cy, 0.0), 1.0, 1.0, "flesh_tan", segs=28, rings=8, matrix=T(cx, cy, 0) @ S(rx, ry, H) @ T(-cx, -cy, 0))
    # Five pale pads, lying along the slope, in a reddish rim.
    for x, u, r in ((0.3, 1.2, 0.48), (-0.85, 0.72, 0.5), (1.45, 0.78, 0.45), (0.05, 0.12, 0.5), (0.95, -0.12, 0.45)):
        q = on_mound(x, u)
        nx, ny, nz = (q[0] - cx) / rx ** 2, (q[1] - cy) / ry ** 2, q[2] / H ** 2  # the surface's normal
        m = T(*q) @ R("Y", math.degrees(math.atan2(nx, math.hypot(ny, nz)))) @ R("X", -math.degrees(math.atan2(ny, nz)))
        p.sphere((0, 0, -0.01), r * 1.2, "flesh_red", segs=16, rings=4, scale=(1, 1, 0.1), matrix=m)  # a swollen rim
        pads.sphere((0, 0, 0.0), r, "flesh_pad", segs=16, rings=5, scale=(1, 1, 0.2), matrix=m)  # a soft swelling, not a disc

    # Folds of flesh round the mound's foot, further out to the south where the sprite spills.
    for i in range(18):
        a = math.radians(i * 20 + 5)
        ca, sa = math.cos(a), math.sin(a)
        stretch = 1.0 + 0.22 * max(0.0, -sa)
        x, y = cx + (2.0 if ca > 0 else 2.15) * ca, cy + 2.1 * sa * stretch
        blob(p, (x, y, 0.42), 0.5, "flesh_dark" if i % 2 else "flesh_tan", segs=8, rings=5,
             scale=(1.15, 1.0, 0.75), seed=60 + i)
    for i, (x, y) in enumerate(((1.0, -2.55), (1.6, -2.35), (-1.4, -2.75), (0.35, -2.85))):
        blob(p, (x, y, 0.34), 0.42, "flesh_dark" if i % 2 else "flesh_tan", segs=8, rings=5,
             scale=(1.2, 1.0, 0.7), seed=80 + i)
    # Claws splayed out on the ground: (root, tip, thickness).
    for i, (root, tip, r) in enumerate((((-1.3, -1.8, 0.5), (-2.15, -3.0, 0.12), 0.52),
                                        ((0.8, -2.0, 0.5), (2.3, -2.85, 0.12), 0.48),
                                        ((-0.9, 2.05, 0.4), (-2.35, 2.4, 0.25), 0.42),
                                        ((-1.9, 0.0, 0.4), (-2.3, -0.8, 0.15), 0.32),
                                        ((1.8, -0.5, 0.4), (2.25, -1.3, 0.15), 0.3),
                                        ((1.8, 0.8, 0.4), (2.25, 0.3, 0.15), 0.28),
                                        ((0.4, -2.0, 0.4), (0.7, -3.0, 0.12), 0.32),
                                        ((-1.9, -1.2, 0.4), (-2.3, -1.9, 0.2), 0.4))):
        _tentacle(p, root, tip, r, "flesh_tan" if i % 2 else "flesh_dark", i)

    # Canisters lying in the flesh at the front, their ends to the south, hoses into the mound.
    for x, y0, y1, z0, z1, r, glass in ((-0.78, -3.25, -2.1, 0.3, 0.95, 0.34, "glass_smoke"),
                                        (-0.12, -3.25, -2.1, 0.3, 0.85, 0.3, None)):
        c = Part()
        L = math.hypot(y1 - y0, z1 - z0)
        _canister(c, 0.0, 0.0, 0.0, r, L, glass)
        c.cyl((0.0, 0.0, L + 0.05), r * 0.4, 0.14, "steel_teal", segs=10)
        for z in (0.14, L * 0.5, L - 0.14):  # riveted bands, as the sprite's canisters have
            c.cyl((0.0, 0.0, z), r + 0.015, 0.06, "steel_dark", segs=12)
            c.bolts_ring((0.0, 0.0, z), r + 0.03, 10, "steel_light", radius=0.015, depth=0.05)
        c.cyl((0.0, 0.0, -0.02), r * 0.55, 0.04, "copper_pipe_dark", segs=10)
        tilt = math.degrees(math.atan2(z1 - z0, y1 - y0))
        p.add_part(c, T(x, y0, z0) @ R("X", -(90 - tilt)))
    p.cyl((0, 0, 0), 0.27, 1.0, "steel_teal", segs=12, axis="Y", bevel=0.04,
          matrix=T(-1.85, -1.45, 0.5) @ R("Z", -40) @ R("X", 10))
    for a, b in (((-0.78, -2.0, 1.25), (-0.5, -1.2, 1.15)), ((-0.12, -2.0, 1.1), (0.25, -1.3, 1.1)),
                 ((-1.6, -1.1, 0.75), (-1.2, -0.6, 1.0)), ((1.9, -0.9, 0.55), (1.55, -0.3, 0.95)),
                 ((-2.0, 0.2, 0.6), (-1.7, 0.6, 0.9))):
        bent(p, [a, ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, max(a[2], b[2]) + 0.25), b], 0.07, "rubber", segs=6)

    # Sealed drum standing on top at the back, a lying cylinder in the north-west.
    _canister(p, -0.75, 1.2, 0.85, 0.3, 1.0)
    p.cyl((-0.75, 0.9, 1.45), 0.08, 0.05, "soot", segs=10, axis="Y")
    p.cyl((-1.75, 1.55, 0.55), 0.2, 0.7, "steel_dark", segs=10, axis="X", bevel=0.03,
          matrix=T(-1.75, 1.55, 0.55) @ R("Z", 30) @ T(1.75, -1.55, -0.55))
    # North-east: dark machinery block, a toothed collar, the bellows and its claw.
    p.slab(1.45, 1.1, 0.0, 2.42, 2.2, 0.95, "steel_dark", bevel=0.08)
    p.cyl((0.95, 1.55, 1.0), 0.42, 0.14, "steel_dark", segs=16, bevel=0.02)
    for k in range(10):
        a = math.radians(k * 36)
        p.box((0.95 + 0.45 * math.cos(a), 1.55 + 0.45 * math.sin(a), 1.0), (0.1, 0.08, 0.12), "steel_dark", rz=math.degrees(a))
    # The bellows telescopes: its outer (east) half, a little wider, slides over the inner half.
    a, b = (0.85, 1.5, 1.3), (1.85, 1.8, 1.6)
    m = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2)
    d = [(b[i] - a[i]) / 1.086 for i in range(3)]
    bellows = Part("anim_bellows_captive", pivot=b)
    hose(p, [a, m], 0.42, "glass_pale", segs=14, rib=0.16, depth=0.12)
    hose(bellows, [tuple(m[i] - 0.05 * d[i] for i in range(3)), b], 0.44, "glass_pale", segs=14, rib=0.16, depth=0.12)
    p.sphere((0.83, 1.5, 1.3), 0.36, "steel_teal", segs=12, rings=6, scale=(0.6, 1, 1))
    bellows.sphere((1.88, 1.8, 1.6), 0.36, "steel_teal", segs=12, rings=6, scale=(0.6, 1, 1))
    bellows.beam((1.95, 1.8, 1.6), (2.25, 1.9, 2.0), 0.08, 0.08, "steel_teal")
    bellows.beam((2.25, 1.9, 2.0), (2.45, 1.75, 1.85), 0.06, 0.06, "steel_teal")
    bellows.beam((2.25, 1.9, 2.0), (2.45, 2.05, 2.0), 0.06, 0.06, "steel_teal")
    _captive_detail(p, cx, cy, rx, ry, mound_z)
    return [p, pads, bellows]


def _captive_detail(p, cx, cy, rx, ry, mound_z):
    """The captive spawner sprite's flesh: red veins running down the mound between the pads and
    wrinkled ridges round its lower slopes, a toothed collar of purple flesh round the bellows."""
    for i, a in enumerate((205, 235, 262, 290, 318, 345, 15, 160, 182)):
        pts = []
        for k in range(8):
            t = 0.35 + 0.6 * k / 7
            w = math.radians(a + 6 * math.sin(k * 1.7 + i))
            x, y = cx + rx * t * math.cos(w), cy + ry * t * math.sin(w)
            pts.append((x, y, mound_z(x, y) + 0.015))
        bent(p, pts, 0.03 if i % 2 else 0.04, "flesh_red" if i % 3 else "flesh_purple", segs=5, smooth=2)
    for i in range(14):
        a = math.radians(190 + i * 12 + (i % 3) * 3)
        t = 0.8 + 0.06 * (i % 2)
        x, y = cx + rx * t * math.cos(a), cy + ry * t * math.sin(a)
        blob(p, (x, y, mound_z(x, y) - 0.02), 0.2, "flesh_red" if i % 2 else "flesh_tan", segs=6, rings=3,
             scale=(1.3, 0.6, 0.45), seed=120 + i)
    for k in range(12):
        a = math.radians(k * 30 + 15)
        p.box((0.95 + 0.47 * math.cos(a), 1.55 + 0.47 * math.sin(a), 1.12), (0.08, 0.06, 0.1), "flesh_purple",
              rz=math.degrees(a))


# ---------------------------------------------------------------------------------------------
# Rocket turret (3x3).

@model("rocket-turret")
def rocket_turret():
    """Factorio's rocket turret: a dark round base with a toothed slewing ring on four clamped
    feet, a louvred motor box and a green tank at the front corners; the head (`anim_turret_head`,
    launchers north at rest) is a rounded grey body between two rocket pods, hoses looping over
    its back and a red lamp on top."""
    p = Part()
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * (1.12 if sy > 0 else 1.05), sy * (1.12 if sy > 0 else 1.2)
            p.box((x, y, 0.1), (0.58, 0.34, 0.2), "steel_grey_dark", bevel=0.04, rz=45 * sx * sy)
            p.cyl((x, y, 0.18), 0.07, 0.06, "steel_light", segs=8)
            p.beam((x * 0.55, y * 0.55, 0.3), (x * 0.9, y * 0.9, 0.12), 0.16, 0.1, "steel_grey")
    lathe(p, (0, 0, 0), [(1.32, 0.0), (1.32, 0.3), (1.12, 0.5), (0.9, 0.62), (0.0, 0.62)], "steel_grey_dark", segs=24)
    # A row of pipes and brackets along the front, between the feet.
    p.slab(-1.0, -1.32, 0.0, 1.0, -0.9, 0.28, "steel_grey_dark", bevel=0.05)
    for x in (-0.75, -0.25, 0.25, 0.75):
        p.cyl((x, -1.15, 0.36), 0.08, 0.4, "rust_brown", segs=8, axis="Y")
    # Machinery round the front of the base.
    for x in (-0.35, 0.3):
        p.slab(x - 0.22, -1.2, 0.0, x + 0.22, -0.8, 0.5, "steel_grey", bevel=0.05)
    hose(p, [(-0.95, 0.35, 0.62), (-1.22, 0.1, 0.5), (-1.25, -0.4, 0.3), (-1.1, -0.85, 0.12)], 0.09, "rust_brown", rib=0.1)
    ring(p, (0, 0), 0.82, 0.98, 0.62, 0.74, "rust_brown", segs=32)
    for k in range(32):
        a = math.radians(k * 360 / 32)
        p.box((0.99 * math.cos(a), 0.99 * math.sin(a), 0.68), (0.05, 0.06, 0.1), "rust_brown", rz=math.degrees(a))
    # Front corners: the louvred motor box (west) and the green tank (east).
    p.slab(-1.15, -1.05, 0.0, -0.55, -0.55, 0.62, "steel_grey", bevel=0.05)
    for k in range(5):
        p.slab(-1.08 + k * 0.1, -1.07, 0.15, -1.04 + k * 0.1, -1.05, 0.5, "steel_black")
    p.cyl((0.85, -0.85, 0.4), 0.34, 0.42, "paint_green", segs=14, axis="X", bevel=0.05)
    p.cyl((0.85, -0.85, 0.4), 0.22, 0.5, "steel_grey", segs=12, axis="X")
    bent(p, [(1.05, -0.8, 0.38), (1.2, -0.6, 0.5), (1.15, -0.2, 0.6), (0.95, 0.1, 0.6)], 0.06, "rust_brown", segs=6)
    bent(p, [(-1.1, -0.4, 0.4), (-1.2, -0.1, 0.65), (-1.05, 0.3, 0.7)], 0.06, "rust_brown", segs=6)
    p.slab(0.85, 0.3, 0.0, 1.22, 0.9, 0.55, "steel_grey_dark", bevel=0.04)
    p.cyl((1.32, 0.62, 0.35), 0.2, 0.16, "steel_grey", segs=12, axis="X", bevel=0.03)
    hose(p, [(1.15, -0.1, 0.5), (1.38, -0.6, 0.35), (1.3, -1.0, 0.15)], 0.1, "rust_brown", rib=0.1)
    p.slab(0.95, -0.55, 0.0, 1.32, 0.3, 0.5, "steel_grey", bevel=0.05)  # machinery on the east side
    p.slab(-1.32, -0.55, 0.0, -1.0, 0.25, 0.45, "steel_grey", bevel=0.05)

    head = Part("anim_turret_head", pivot=(0.0, 0.0, 0.74))
    head.cyl((0, 0, 0.84), 0.72, 0.2, "steel_grey_dark", segs=20, bevel=0.03)
    # Body: rounded, taller at the back, a dome on top.
    head.slab(-0.45, -0.5, 0.92, 0.45, 0.62, 2.18, "steel_grey", bevel=0.14)
    dome(head, (0, 0.1, 2.18), 0.46, 0.32, "steel_grey", segs=16, rings=4)
    head.sphere((0, 0.1, 2.51), 0.07, "lamp_red", segs=8, rings=4)
    head.slab(-0.3, -0.52, 1.0, 0.3, -0.5, 1.75, "steel_black")
    # Rocket pods either side, their tubes opening north.
    for sx in (-1, 1):
        x0, x1 = sorted((sx * 0.42, sx * 1.17))
        head.slab(x0, -0.42, 0.95, x1, 0.62, 2.18, "steel_grey", bevel=0.24)
        head.slab(x0 + 0.04, -0.44, 1.2, x1 - 0.04, -0.42, 1.85, "steel_grey_dark")
        for k in range(2):
            for j in range(2):
                head.cyl((x0 + 0.2 + k * 0.28, 0.63, 1.25 + j * 0.4), 0.09, 0.03, "soot", segs=10, axis="Y")
    # Hoses looping over the back (south face), down to the turntable.
    for sx in (-1, 1):
        hose(head, [(sx * 0.25, -0.5, 1.7), (sx * 0.4, -0.75, 1.35), (sx * 0.35, -0.66, 0.98)], 0.06, "rust_brown", rib=0.07)
        hose(head, [(sx * 0.08, -0.5, 1.5), (sx * 0.15, -0.68, 1.2), (sx * 0.1, -0.58, 0.96)], 0.05, "rust_brown", rib=0.07)
    head.cyl((0, -0.56, 1.15), 0.12, 0.14, "paint_green", segs=10, axis="Y")
    return [p, head]


# ---------------------------------------------------------------------------------------------
# Gleba plants: variation 1 of each, height and spread read off the sprite (drawn 4-7 tiles
# tall, like the Nauvis trees, and standing a little south of the entity's position). All their
# materials are "flesh_*" (the organic weathering class).

import random  # noqa: E402

from space_kit import stalk  # noqa: E402

import kit  # noqa: E402

kit.MATERIALS.update({
    "flesh_stingstalk": ("3e4c46", 0.6, 0.0, None, 0),  # stingfrond stalk, darker than its tendrils
    "flesh_slipcap": ("4e6470", 0.25, 0.0, None, 0),    # slipstack's glossy slate-blue tube caps
})

import bmesh  # noqa: E402
from mathutils import Vector, noise  # noqa: E402

from plant_skeletons import PLANTS as SKELETONS  # noqa: E402
from space_kit import catmull, sweep  # noqa: E402


FLESH_STIFFNESS = 10.0
FLESH_GROW = 1 / 0.78  # a lone metaball of radius R and stiffness 10 has its surface at 0.78 R


def flesh(p, balls, tris, resolution=0.02):
    """One smooth skin over `balls` [(centre, radius, material)]: Blender metaballs (each ball's
    surface where it stands alone at its radius; neighbours melt together like flesh), meshed and
    decimated to about `tris` triangles. Each face takes the material of the ball it's nearest."""
    import bpy
    from mathutils.kdtree import KDTree
    if not balls:
        return p
    mb = bpy.data.metaballs.new("flesh")
    mb.resolution = mb.render_resolution = resolution
    mb.threshold = 0.6
    obj = bpy.data.objects.new("flesh", mb)
    bpy.context.scene.collection.objects.link(obj)
    for co, r, _ in balls:
        e = mb.elements.new()
        e.co = co
        e.radius = r * FLESH_GROW
        e.stiffness = FLESH_STIFFNESS
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(obj)
    bpy.data.metaballs.remove(mb)
    count = sum(len(f.vertices) - 2 for f in me.polygons)
    if count > tris:
        mo = bpy.data.objects.new("flesh", me)
        bpy.context.scene.collection.objects.link(mo)
        mod = mo.modifiers.new("decimate", "DECIMATE")
        mod.ratio = tris / count
        me2 = bpy.data.meshes.new_from_object(mo.evaluated_get(bpy.context.evaluated_depsgraph_get()))
        bpy.data.objects.remove(mo)
        bpy.data.meshes.remove(me)
        me = me2
    bm = bmesh.new()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    tree = KDTree(len(balls))
    for i, (co, _, _) in enumerate(balls):
        tree.insert(co, i)
    tree.balance()
    reach = max(r for _, r, _ in balls) * 2
    for f in bm.faces:
        c = f.calc_center_median()
        near = tree.find_range(c, reach) or [tree.find(c)]
        i = min(near, key=lambda h: h[2] - balls[h[1]][1])[1]
        f.material_index = p._mat_index(balls[i][2])
    bm.normal_update()
    p.merge(bm, None, mats=list(p.mats))
    bm.free()
    return p


def decimate(p, ratio):
    """Collapses the part's mesh to `ratio` of its triangles (Blender's decimate), keeping each
    face's material."""
    import bpy
    me = bpy.data.meshes.new("decimate")
    p.bm.to_mesh(me)
    obj = bpy.data.objects.new("decimate", me)
    bpy.context.scene.collection.objects.link(obj)
    mod = obj.modifiers.new("decimate", "DECIMATE")
    mod.ratio = max(0.05, min(1.0, ratio))
    me2 = bpy.data.meshes.new_from_object(obj.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(obj)
    bpy.data.meshes.remove(me)
    p.bm.free()
    p.bm = bmesh.new()
    p.bm.from_mesh(me2)
    bpy.data.meshes.remove(me2)
    return p


def skeleton_plant(name, mats, y0=None, depth=0.35, lean=0.0, seed=0.0, ground=0.25, thin=0.03, thick=0.05,
                   tris=2000, budget=4900, smooth=True, fork=0.7, p=None):
    """A plant grown along its sprite's skeleton (plant_skeletons.py): every branch as thick as
    the sprite is wide there, so from Factorio's camera it covers what the sprite covers. Branches
    are tubes; single balls (the sprite's lobes) and lumps shorter than they are thick are melted
    into one skin (`flesh`, about `tris` triangles). The
    camera can't see depth, so each point slides along the view line by a smooth field (`depth`
    tiles either way, none at the foot) to give the crown body, and the crown sits `lean` tiles
    further north (keeps the model round its footprint when the sprite stands well south of it);
    the trunk's foot stands `y0` tiles north (default: under the lowest thick branch). Points that
    would sink slide south onto the ground instead (roots). `mats`: [(material, sprite colour
    hex)], each branch takes the one nearest its sprite colour; part_colors.py then paints it from
    the sprite. With `p`, everything goes into that part: "<plant>-fill" skeletons fill in round
    hand-placed parts (the sprite's outline less what those parts already cover; F3D_NO_FILL=1
    leaves them out, to render the hand-placed parts alone and measure the rest). Over `budget`
    triangles (everything in the part), the tubes are decimated to fit."""
    branches = SKELETONS.get(name, [])
    if name.endswith("-fill") and os.environ.get("F3D_NO_FILL"):
        branches = []
    if p is None:
        p = Part()
        p.sharp_angle = 80.0  # few sides, but flesh: shade it round
    if not branches:
        return p
    pal = [(m, [int(h[i:i + 2], 16) for i in (0, 2, 4)]) for m, h in mats]
    if y0 is None:
        rmax = max(q[2] for b in branches for q in b[0])
        y0 = min(q[1] for b in branches for q in b[0] if q[2] > 0.5 * rmax) / SIN_P
    p.plant_y0 = y0
    u_foot = SIN_P * y0

    def place(x, u, r):
        w = min(1.0, max(0.0, (u - u_foot - ground) / 1.2))
        wave = 0.6 * math.sin(2.1 * x + 1.3 * u + seed) + 0.4 * math.sin(-1.7 * x + 2.3 * u + 2 * seed + 1)
        y = y0 + w * (lean + depth * wave)
        z = (u - SIN_P * y) / COS_P
        # Thick roots may sink a little (check.py's sink), thin ones rest on the ground.
        zmin = max(0.6 * r, r - 0.1)
        if z < zmin:
            z = zmin
            y = (u - COS_P * z) / SIN_P
        return Vector((x, y, z))

    ends = {}
    for pts, _, _ in branches:
        for q in (pts[0], pts[-1]):
            k = (round(q[0], 2), round(q[1], 2))
            ends[k] = ends.get(k, 0) + 1
    balls = []
    for pts, _, col in branches:
        c = [int(col[i:i + 2], 16) for i in (0, 2, 4)]
        mat = min(pal, key=lambda m: sum((a - b) ** 2 for a, b in zip(m[1], c)))[0]
        path = [place(*q) for q in pts]
        radii = [q[2] for q in pts]
        if len(radii) > 2:  # the outline's pixel steps make the radius jitter
            radii = [radii[0]] + [0.25 * a + 0.5 * b + 0.25 * c for a, b, c in zip(radii, radii[1:], radii[2:])] + [radii[-1]]
        # Steps shorter than the tube is thick (the medial axis of a lump) would fold the tube
        # inside out: keep only points most of a radius apart.
        if len(path) > 2:
            keep = [0]
            for i in range(1, len(path) - 1):
                if (path[i] - path[keep[-1]]).length >= 0.5 * max(radii[i], radii[keep[-1]]):
                    keep.append(i)
            if (path[-1] - path[keep[-1]]).length < 0.5 * max(radii[-1], radii[keep[-1]]) and len(keep) > 1:
                keep.pop()
            keep.append(len(path) - 1)
            path, radii = [path[i] for i in keep], [radii[i] for i in keep]
        # Single balls (the sprite's lobes) and lumps shorter than they are thick go into the skin.
        if len(path) == 1 or max(radii) >= thick and sum((b - a).length for a, b in zip(path, path[1:])) < 1.5 * max(radii):
            balls += [(q, r, mat) for q, r in zip(path, radii) if r >= thick / 2]
            continue
        rmax = max(radii)
        segs = 3 if rmax < thin / 2 else 4 if rmax < 0.05 else 5 if rmax < 0.12 else 6 if rmax < 0.2 else 8
        # A few-sided tube shows narrower than a round one on average: grow it to match.
        k = 1 / math.cos(math.pi / segs) ** 0.5
        # Free tips end in a dome (the sprite's tips are round).
        for end in (0, -1):
            q = pts[end]
            t = (path[end] - path[1 if end == 0 else -2]).normalized()
            if ends[(round(q[0], 2), round(q[1], 2))] > 1:
                # At a fork, run on into the other branches: a flat end leaves a notch where the
                # sprite's outline turns round the joint.
                path[end] = path[end] + t * radii[end] * fork
                continue
            if radii[end] < 0.06:
                continue
            dome = [(path[end] + t * radii[end] * s, radii[end] * f) for s, f in ((0.5, 0.87), (0.87, 0.5))]
            if end == 0:
                path = [d[0] for d in reversed(dome)] + path
                radii = [d[1] for d in reversed(dome)] + radii
            else:
                path = path + [d[0] for d in dome]
                radii = radii + [d[1] for d in dome]
        if smooth and rmax >= 0.1 and len(path) > 2:
            # Thick tubes bend smoothly (thin ones are too small to show their corners).
            n = len(path)
            path = catmull(path, 2)
            radii = [radii[min(n - 1, i // 2)] if i % 2 == 0 else 0.5 * (radii[i // 2] + radii[min(n - 1, i // 2 + 1)])
                     for i in range(len(path))]
        sweep(p, path, 0.0, mat, segs=segs, radii=[r * k for r in radii])
    skin = min(tris, 40 * len(balls)) if balls else 0
    tubes = sum(len(f.verts) - 2 for f in p.bm.faces)
    if budget and tubes + skin > budget:
        decimate(p, (budget - skin) / tubes)
    return flesh(p, balls, skin)


def plant(name, mats, budget=4900, **kw):
    """`skeleton_plant` for `name`, then its "-fill" skeleton (measured from this model's own render:
    the bits of the sprite the first pass still misses) on the same footing, all in `budget`."""
    p = skeleton_plant(name, mats, budget=None, **kw)
    kw["y0"] = getattr(p, "plant_y0", kw.get("y0"))
    p = skeleton_plant(name + "-fill", mats, budget=budget, p=p, **kw)
    tris = sum(len(f.verts) - 2 for f in p.bm.faces)
    if os.environ.get("F3D_DEBUG"):
        print("plant", name, "triangles before fitting", tris)
    return decimate(p, budget / tris) if tris > budget else p


def column(p, rows, yc, top, mat_of, segs=16, wobble=0.04, lip=None, seed=0.0):
    """A lumpy column lofted through horizontal rings, one per row of the sprite's silhouette:
    `rows` are (u, left, right) in screen tiles, the column's width at that height; each becomes a
    ring centred under the row, `yc` tiles north, at the height that shows it there. Rings whose
    back would rise above the sprite's top `top` are left off, and the column is closed with a flat
    top (or `lip`: [(share of the last radius, height above it)] for a rim and a crater).
    `mat_of(u)` picks the material of the band at screen height u."""
    rings = []
    for u, left, right in rows:
        z = (u - SIN_P * yc) / COS_P
        r = (right - left) / 2
        if z < -0.05 or u + SIN_P * r > top:
            continue
        rings.append(((left + right) / 2, z, r, u))
    rings.sort(key=lambda q: q[1])
    xc0, _, r0, u0 = rings[0]
    rings.insert(0, (xc0, -0.08, r0 * 0.95, u0))
    bm = bmesh.new()
    lay = bm.faces.layers.int.new("mat")
    loops = []
    for xc, z, r, u in rings:
        loop = []
        for k in range(segs):
            a = math.tau * k / segs
            n = noise.noise(Vector((math.cos(a) * 1.7 + seed, math.sin(a) * 1.7, z * 1.3)))
            loop.append(bm.verts.new((xc + r * (1 + wobble * n) * math.cos(a), yc + r * (1 + wobble * n) * math.sin(a), z)))
        loops.append((loop, u))
    xt, zt, rt, ut = rings[-1]
    for share, dz in (lip or []):
        loops.append(([bm.verts.new((xt + rt * share * math.cos(math.tau * k / segs),
                                     yc + rt * share * math.sin(math.tau * k / segs), zt + dz)) for k in range(segs)], ut))
    for (la, ua), (lb, _) in zip(loops, loops[1:]):
        mi = p._mat_index(mat_of(ua))
        for k in range(segs):
            bm.faces.new((la[k], la[(k + 1) % segs], lb[(k + 1) % segs], lb[k]))[lay] = mi
    for loop, u, rev in ((loops[0][0], loops[0][1], True), (loops[-1][0], loops[-1][1], False)):
        bm.faces.new(list(reversed(loop)) if rev else loop)[lay] = p._mat_index(mat_of(u))
    for f in bm.faces:
        f.material_index = f[lay]
    bm.normal_update()
    p.merge(bm, None, mats=list(p.mats))
    bm.free()
    return rings


@model("yumako-tree")
def yumako_tree():
    """Yumako tree: a gnarled, twisting olive-brown trunk on splayed roots, branching at the top
    into crooked twigs that each carry a round red yumako fruit."""
    return plant("yumako-tree", [("flesh_bark", "32291e"), ("flesh_stalk", "6b3f2e"), ("flesh_fruit", "a03028")])


@model("jellystem")
def jellystem():
    """Jellystem: a tall column of pale pink jelly lobes, broadest two thirds of the way up,
    on a short stem with red roots."""
    return plant("jellystem", [("flesh_jelly", "755155"), ("flesh_crimson", "41272a"), ("flesh_pink", "593c40")],
                 tris=3000, lean=0.4)


@model("cuttlepop")
def cuttlepop():
    """Cuttlepop: a clump of thin pale stalks, each topped by a purple cup of feelers."""
    return plant("cuttlepop", [("flesh_cream", "504143"), ("flesh_lilac", "7d6a7f"), ("flesh_purple", "3d2f32")])


@model("slipstack")
def slipstack():
    """Slipstack: a cluster of mauve tubes of many heights, splaying out from the foot; the tall
    ones at the back are shut with glossy slate-blue domes, the short ones in front are open
    pale pink pipes, dark inside."""
    p = Part()
    p.sharp_angle = 80.0
    # (x, u) of each tube's top in the sprite (tiles, screen), its half-width, how far north it
    # stands (back rows taller) and whether it's open.
    tubes = [(-0.265, 4.47, 0.17, 0.35, False), (-0.655, 4.11, 0.18, 0.2, False), (0.51, 4.15, 0.185, 0.3, False),
             (0.57, 3.5, 0.15, 0.1, False), (-1.01, 2.91, 0.22, 0.0, False), (-0.19, 2.95, 0.2, 0.0, False),
             (0.85, 2.72, 0.17, 0.0, False), (0.26, 3.0, 0.15, 0.25, True), (-0.19, 1.98, 0.15, -0.2, False),
             (0.20, 1.8, 0.19, -0.2, False), (-0.77, 1.43, 0.145, -0.25, True), (-0.61, 1.2, 0.17, -0.3, False),
             (-0.13, 1.25, 0.22, -0.3, True), (0.73, 1.1, 0.19, -0.25, True), (0.49, 0.7, 0.16, -0.4, False),
             (0.83, 0.55, 0.15, -0.4, True), (-0.56, 0.68, 0.15, -0.4, True), (-0.34, 0.65, 0.16, -0.45, True),
             (-0.06, 0.62, 0.15, -0.45, True), (0.31, 0.0, 0.19, -0.35, True)]
    for xt, ut, r, y, open_ in tubes:
        zt = (ut - SIN_P * y) / COS_P
        xb = 0.35 * xt
        stalk(p, [(xb, y, -0.1), (xb + (xt - xb) * 0.45, y, zt * 0.5), (xt, y, zt)], r * 0.85, r, "flesh_slip", segs=7, smooth=2)
        if open_:
            lathe(p, (xt, y, zt - 0.06), [(r * 0.98, 0.0), (r * 1.06, 0.07), (r * 0.98, 0.1), (r * 0.72, 0.09),
                                          (r * 0.64, -0.06), (0.0, -0.06)], "flesh_slip", segs=10)
            p.cyl((xt, y, zt - 0.02), r * 0.66, 0.02, "flesh_dark", segs=10)
        else:
            p.sphere((xt, y, zt), r * 0.98, "flesh_slipcap", segs=8, rings=4, scale=(1.0, 1.0, 0.6))
    # Between and behind the tubes: more tube flesh, along what the sprite shows there.
    return skeleton_plant("slipstack-fill", [("flesh_slip", "583e4a"), ("flesh_dark", "160a0e")], y0=0.2, depth=0.1, p=p)


@model("funneltrunk")
def funneltrunk():
    """Funneltrunk: a bundle of olive-yellow trunks, narrow at the foot and fanning out, each
    ending in a funnel mouth with pink feelers."""
    return plant("funneltrunk", [("flesh_coral", "7d5543"), ("flesh_olive", "3e3816"), ("flesh_bark", "131106")])


@model("hairyclubnub")
def hairyclubnub():
    """Hairyclubnub: thick twisting dark trunks coiling up into a bushy mass, studded with
    wine-red nubs, pale blue-grey hair hanging from their ends."""
    return plant("hairyclubnub", [("flesh_lilac", "7d93b0"), ("flesh_crimson", "72605c"), ("flesh_bark", "45332c")], smooth=False)


@model("teflilly")
def teflilly():
    """Teflilly: a slim ringed stalk carrying a fan of long pink fronds, like a palm."""
    return plant("teflilly", [("flesh_coral", "b96673"), ("flesh_bark", "24191a"), ("flesh_crimson", "65393d")],
                          lean=-0.4)


@model("lickmaw")
def lickmaw():
    """Lickmaw: a red, veined fleshy column leaning west from a broad lumpy foot, an open maw
    at its top."""
    return plant("lickmaw", [("flesh_coral", "745256"), ("flesh_crimson", "422025"), ("flesh_red", "58383c")],
                          depth=0.25)


@model("stingfrond")
def stingfrond():
    """Stingfrond: a dark grey-green stalk with spiky collars, crowned by long pale glassy cyan
    tendrils that arch out and droop."""
    return plant("stingfrond", [("flesh_cyan", "9fc2c1"), ("flesh_stingstalk", "5c7b74"), ("flesh_dark", "313b31")],
                          lean=0.5)


@model("boompuff")
def boompuff():
    """Boompuff: a squat stack of swollen puffballs, as the sprite: a brown root stump, a pale
    cream ring, two yellow-ochre puffs on top, the top one with a crater; short spines round
    each puff's waist."""
    p = Part()
    p.sharp_angle = 80.0
    # The sprite's width row by row (screen tiles): the dents are where the puffs meet.
    rows = [(2.38, -0.69, 0.84), (2.26, -0.76, 0.81), (2.14, -0.73, 0.82), (2.02, -0.66, 0.71), (1.90, -0.63, 0.76),
            (1.77, -0.67, 0.86), (1.65, -0.72, 0.87), (1.53, -0.71, 0.88), (1.41, -0.70, 0.86), (1.29, -0.63, 0.80),
            (1.17, -0.70, 0.83), (1.05, -0.72, 0.86), (0.93, -0.73, 0.84), (0.81, -0.70, 0.74), (0.69, -0.63, 0.75),
            (0.57, -0.70, 0.79), (0.45, -0.72, 0.77), (0.33, -0.64, 0.77), (0.21, -0.67, 0.80), (0.09, -0.71, 0.86),
            (-0.04, -0.78, 0.88)]

    # Where two puffs meet the silhouette is the lower one's back rim: the crease itself, hidden,
    # runs far deeper.
    waist = {2.02: 0.7, 1.29: 0.72, 0.81: 0.8, 0.69: 0.85}
    rows = [(u, (l + r) / 2 - (r - l) / 2 * waist.get(u, 1.0), (l + r) / 2 + (r - l) / 2 * waist.get(u, 1.0))
            for u, l, r in rows]

    def mat(u):
        return "flesh_bark" if u < 0.7 else "flesh_cream" if u < 1.2 else "flesh_puff"

    rings = column(p, rows, 0.0, 2.86, mat, segs=18, wobble=0.05,
                   lip=[(0.93, 0.1), (0.78, 0.2), (0.58, 0.24), (0.44, 0.18), (0.3, 0.06), (0.0, 0.02)])
    # Spines on the bulges (widest rows), pointing out and a little up.
    for i, (xc, z, r, u) in enumerate(rings):
        if 0 < i < len(rings) - 1 and r >= max(rings[i - 1][2], rings[i + 1][2]):
            for k in range(9):
                a = math.tau * (k + 0.5 * (i % 2)) / 9
                base = Vector((xc + r * math.cos(a), r * math.sin(a), z))
                tip = base + Vector((math.cos(a) * 0.13, math.sin(a) * 0.13, 0.05))
                p.tube(base, tip, 0.045, mat(u), segs=5, radius_top=0.005)
    return skeleton_plant("boompuff-fill", [("flesh_bark", "4d311c"), ("flesh_puff", "7c5533"), ("flesh_cream", "c19e5f")],
                          y0=-0.2, depth=0.0, p=p)


@model("sunnycomb")
def sunnycomb():
    """Sunnycomb: a pale porous column with a side branch, dotted with bright yellow cups."""
    return plant("sunnycomb", [("flesh_comb", "a58e4d"), ("flesh_dark", "4d3d20"), ("flesh_cream", "776133")],
                          depth=0.2)


@model("water-cane")
def water_cane():
    """Water cane: one curved dark reed with a small ochre flower head of pointed florets."""
    return skeleton_plant("water-cane", [("flesh_reed", "2a1404"), ("flesh_puff", "6d4d0c")], depth=0.0, fork=0.0)


# ---------------------------------------------------------------------------------------------
# Pentapods: wrigglers, strafers, stompers, small to big. A strafer's and a stomper's five legs
# are separate entities in Factorio that step on their own (the bridge sends their feet, `legs`):
# each leg here is an upper part (`anim_leg_upper`, pivot at the hip) and a lower part
# (`anim_leg_lower`, pivot at the knee) standing in its rest pose, which the client bends between
# hip, knee and wherever the foot stands (vehicle_anim.gd), as Factorio stretches its leg
# sprites. The torsos are lofted through rings measured from their 64 rotation frames
# (creature_hull.py, creature_profiles.py), lifted by the prototype's `height`. Tiers are the big
# one scaled as Factorio scales their sprites and legs (small 0.5625, medium 0.75), each its own
# model since the legs' parts carry their own transforms.

kit.MATERIALS.update({
    "flesh_shell_light": ("8a7f80", 0.75, 0.0, None, 0),
    "flesh_shell_dark": ("4e4646", 0.8, 0.0, None, 0),
    # Stomper legs, from its leg sprites under their tint: the thigh dark purple at the hip,
    # ribbed ochre towards the knee; the knee and shin warty red-brown; the foot a dark pad.
    "flesh_stomper_hip": ("2a1a1a", 0.7, 0.0, None, 0),
    "flesh_stomper_thigh": ("4a3a2a", 0.7, 0.0, None, 0),
    "flesh_stomper_knee": ("4a4038", 0.75, 0.0, None, 0),
    "flesh_stomper_shin": ("3a2c28", 0.75, 0.0, None, 0),
    "flesh_stomper_foot": ("2c2c22", 0.8, 0.0, None, 0),
    # Strafer: olive flesh, glossy black eyes; legs olive-brown.
    "flesh_olive_dark": ("4e4534", 0.7, 0.0, None, 0),
    "flesh_olive_light": ("7e7455", 0.7, 0.0, None, 0),
    "flesh_eye": ("1a1816", 0.15, 0.1, None, 0),
    "flesh_strafer_thigh": ("3e3628", 0.7, 0.0, None, 0),
    "flesh_strafer_knee": ("4a4436", 0.7, 0.0, None, 0),
    "flesh_strafer_shin": ("5a5444", 0.7, 0.0, None, 0),
    # Wriggler legs: pale green, tinted per tier by the client (creature_models.gd).
    "chitin_wriggler_leg": ("7c9a48", 0.5, 0.0, None, 0),
    "flesh_slime": ("2c3a22", 0.3, 0.0, None, 0),  # a dead spawner's splash
})

# spider_engine.legs of the big tiers (`factorio --dump-data`): mount and ground positions
# (Factorio's x east, y south) and walking group, in the order the bridge sends their feet.
STOMPER_LEGS = [((-1.0345, -1.4239), (-6.5832, -9.0610), 1), ((-1.6739, 0.5439), (-10.6518, 3.4610), 3),
                ((0.0, 1.76), (0.0, 11.2), 5), ((1.6739, 0.5439), (10.6518, 3.4610), 2),
                ((1.0345, -1.4239), (6.5832, -9.0610), 4)]
STRAFER_LEGS = [((-0.3236, -0.2351), (-6.4721, -4.7023), 1), ((-0.3236, 0.2351), (-6.4721, 4.7023), 3),
                ((0.1236, 0.3804), (2.4721, 7.6085), 5), ((0.4, 0.0), (8.0, 0.0), 2),
                ((0.1236, -0.3804), (2.4721, -7.6085), 4)]
PENTAPOD_TIERS = (("small-", 0.5625), ("medium-", 0.75), ("big-", 1.0))
STOMPER_HEIGHT, STRAFER_HEIGHT = 0.7, 1.5  # the prototypes' torso `height`
STOMPER_TORSO = {"a": "flesh_shell_dark", "b": "flesh_shell", "c": "flesh_shell", "d": "flesh_shell_light"}
STRAFER_TORSO = {"a": "flesh_eye", "b": "flesh_olive_dark", "c": "flesh_olive", "d": "flesh_olive",
                 "e": "flesh_olive_light"}
# Legs come out from under the shell (Factorio draws the torso over the hips): hips a quarter of
# the way up the torso; knees knee_distance_factor of the way out and this far over the hip (big
# tier, tiles), below the shell's top as the leg sprites bend them.
STOMPER_KNEE = (0.55, 2.4)
STRAFER_KNEE = (0.5, 2.0)
HIP_UP = 0.25


def _pentapod(scale, profile, classes, height, legs, knee, leg_fn):
    from creature_profiles import PROFILES
    p = Part()
    p.sharp_angle = 70.0
    profile_loft(p, PROFILES[profile], classes, scale=scale, lift=height)
    rings = PROFILES[profile]["rings"]
    lows, highs = [], []
    for _s, _u, cy, radii, _cls in rings:
        n = len(radii)
        hs = [cy + r * math.sin(2 * math.pi * i / n) for i, r in enumerate(radii)]
        lows.append(min(hs))
        highs.append(max(hs))
    bottom, top = max(0.0, min(lows) + height), max(highs) + height
    hip_z = (bottom + HIP_UP * (top - bottom)) * scale
    parts = [p]
    for (mx, my), (gx, gy), _group in legs:
        hip = Vector((mx * scale, -my * scale, hip_z))
        foot = Vector((gx * scale, -gy * scale, 0.0))
        k = hip + (foot - hip) * knee[0]
        k.z = hip_z + knee[1] * scale
        upper = Part("anim_leg_upper", pivot=tuple(hip))
        lower = Part("anim_leg_lower", pivot=tuple(k))
        leg_fn(upper, lower, hip, k, foot, scale)
        parts += [upper, lower]
    return parts


def _stomper_leg(upper, lower, hip, knee, foot, s):
    """Stomper's leg: a thick tapering thigh (the bulbous joint at the hip, ribbed towards the
    knee), a knee ball, a warty shin narrowing to a dark foot pad (the leg sprites' widths)."""
    d = knee - hip
    stalk(upper, [hip, hip + d * 0.5], 0.9 * s, 1.3 * s, "flesh_stomper_hip", segs=10, smooth=1)
    stalk(upper, [hip + d * 0.5, knee], 1.3 * s, 1.0 * s, "flesh_stomper_thigh", segs=10, smooth=1)
    lower.sphere(tuple(knee), 1.25 * s, "flesh_stomper_knee", segs=12, rings=7)
    e = foot - knee
    ankle = foot + Vector((0, 0, 0.9 * s))
    stalk(lower, [knee, knee + e * 0.5 + Vector((0, 0, -0.2 * s)), ankle], 1.15 * s, 0.35 * s, "flesh_stomper_shin",
          segs=10, smooth=3)
    lower.cyl((foot.x, foot.y, 0.45 * s), 1.45 * s, 0.9 * s, "flesh_stomper_foot", segs=12, radius_top=0.45 * s)


def _strafer_leg(upper, lower, hip, knee, foot, s):
    """Strafer's leg: a thin olive thigh, a knobbly knee, a long shin tapering to a point."""
    stalk(upper, [hip, knee], 0.3 * s, 0.38 * s, "flesh_strafer_thigh", segs=8, smooth=1)
    lower.sphere(tuple(knee), 0.48 * s, "flesh_strafer_knee", segs=10, rings=6)
    e = foot - knee
    stalk(lower, [knee, knee + e * 0.5 + Vector((0, 0, 0.15 * s)), foot], 0.16 * s, 0.03 * s, "flesh_strafer_shin",
          segs=8, smooth=3)


def _stomper(scale):
    """Stomper: a broad shell of mauve-grey armour, studded with pale spikes and holes, held
    low on five massive legs that come out from under it, bend at knees about as high as its
    shell and reach down to wide foot pads eleven tiles out (big)."""
    return _pentapod(scale, "stomper-torso", STOMPER_TORSO, STOMPER_HEIGHT, STOMPER_LEGS, STOMPER_KNEE, _stomper_leg)


def _strafer(scale):
    """Strafer: an olive head studded with black eyes over a cluster of yellow eggs and a spongy
    tip at the back, held high on five thin legs with sharp knees."""
    return _pentapod(scale, "strafer-torso", STRAFER_TORSO, STRAFER_HEIGHT, STRAFER_LEGS, STRAFER_KNEE, _strafer_leg)


for _prefix, _scale in PENTAPOD_TIERS:
    model(_prefix + "stomper-pentapod")(lambda s=_scale: _stomper(s))
    model(_prefix + "strafer-pentapod")(lambda s=_scale: _strafer(s))


# Wriggler: the run sprite's grub, a small olive head (black eyes at the front) on five long
# pale-green legs splayed round it, which wriggle as it scuttles. Rigged like Nauvis's biters
# (wube_rig.py's limb rig): every vertex of a leg carries its limb and how much it follows it in
# TEXCOORD_0, and the client swings the legs in the vertex shader with the distance walked
# (creatures.gd). Big tier; the client scales and tints the others (creature_models.gd).
# Its legs as the run sprite spreads them: (degrees clockwise from north, reach in tiles): two
# short ones curling forward, two long ones out to the sides, one behind.
WRIGGLER_LEGS = ((35.0, 1.3), (95.0, 1.95), (180.0, 1.35), (265.0, 1.95), (325.0, 1.3))
WRIGGLER_HEAD_Z = 0.36


class _Limbs:
    """Collects which limb each vertex added in `with limbs.on(i)` belongs to; Part.uv_fn then
    writes (limb + 1, 1 - weight) per vertex (the glTF exporter flips v), the weight rising from
    0 at the joint to 1 `soft` tiles out, as wube_rig.weights does."""

    def __init__(self, part, soft=(0.08, 0.45)):
        self.part, self.soft = part, soft
        self.of = {}
        self.joints = []
        self._limb = None
        part.uv_fn = self.uv

    def on(self, limb):
        self._limb = limb
        return self

    def __enter__(self):
        self.part.bm.verts.ensure_lookup_table()
        self._start = len(self.part.bm.verts)
        return self.part

    def __exit__(self, *exc):
        bm = self.part.bm
        bm.verts.ensure_lookup_table()
        for v in bm.verts[self._start:]:
            self.of[(round(v.co.x, 4), round(v.co.y, 4), round(v.co.z, 4))] = self._limb
        return False

    def uv(self, co):
        limb = self.of.get((round(co.x, 4), round(co.y, 4), round(co.z, 4)))
        if limb is None:
            return (0.0, 1.0)
        d = (co - self.joints[limb]).length
        t = min(1.0, max(0.0, (d - self.soft[0]) / (self.soft[1] - self.soft[0])))
        return (limb + 1.0, 1.0 - t * t * (3 - 2 * t))


@model("big-wriggler-pentapod")
def big_wriggler():
    """Wriggler: a small olive head with black eyes, on five long pale-green legs splayed round
    it, arching up from the head and down to the ground two tiles out."""
    import wube_rig
    p = Part()
    p.sharp_angle = 70.0
    rig = _Limbs(p)
    hz = WRIGGLER_HEAD_Z
    # Head: about 1.2 tiles across in the run sprite, hunched low, a paler plate over its back.
    blob(p, (0, 0.05, hz), 1.0, "flesh_olive", segs=16, rings=9, scale=(0.66, 0.74, 0.38), seed=111, wobble=0.08)
    blob(p, (0, -0.12, hz + 0.16), 1.0, "flesh_olive_light", segs=12, rings=6, scale=(0.54, 0.56, 0.28), seed=112)
    for x, y, z, r in ((-0.2, 0.6, hz + 0.1, 0.09), (0.2, 0.6, hz + 0.1, 0.09), (0.0, 0.68, hz - 0.02, 0.08),
                       (-0.38, 0.45, hz + 0.02, 0.07), (0.38, 0.45, hz + 0.02, 0.07), (-0.1, 0.5, hz + 0.26, 0.06),
                       (0.1, 0.5, hz + 0.26, 0.06)):
        p.sphere((x, y, z), r, "flesh_eye", segs=8, rings=4)
    limbs = {}
    for i, (deg, reach) in enumerate(WRIGGLER_LEGS):
        a = math.radians(deg)
        dx, dy = math.sin(a), math.cos(a)  # Blender: x east, y north
        # Each leg curls a little sideways towards its tip, as the sprite's tentacles do.
        sx, sy = dy * 0.25, -dx * 0.25
        hip = Vector((0.4 * dx, 0.4 * dy, hz - 0.08))
        knee = Vector((0.6 * reach * dx + sx * 0.4, 0.6 * reach * dy + sy * 0.4, hz + 0.3))
        foot = Vector((reach * dx + sx, reach * dy + sy, 0.06))
        rig.joints.append(hip)
        with rig.on(i):
            stalk(p, [hip, hip.lerp(knee, 0.6), knee, knee.lerp(foot, 0.5) + Vector((0, 0, 0.04)), foot],
                  0.25, 0.1, "chitin_wriggler_leg", segs=7, smooth=3)
        # glTF axes for the rig table (x east, y up, z south).
        limbs["leg_%d" % i] = [(hip.x, hip.z, -hip.y), (knee.x, knee.z, -knee.y), (foot.x, foot.z, -foot.y)]
    # The five legs wriggle in turn round the body, as the run sheet's 21 frames do.
    gait = {"leg_%d" % i: (i * 0.4 % 1.0, 24.0, 16.0, 0.0) for i in range(len(WRIGGLER_LEGS))}
    wube_rig.write_rig_table("big-wriggler-pentapod", {"mode": "walk", "limbs": limbs, "gait": gait})
    return p


# ---------------------------------------------------------------------------------------------
# Gleba spawners: a heap of yellow-orange veined membrane bulging with glossy green egg sacs.
# Factorio has one picture of each (three variations of the big one, two of the small; the
# first is used), so they are measured as heaps (creature_hull.py `relief`, RELIEFS): every
# east-west column is a half-ellipse across a round footprint whose top shows where the picture's
# outline is, and the sacs are set into it where the picture's green bulges are. The sacs swell and settle
# on Factorio's idle loop (16 frames forward then back at 0.1 a tick: 5.3 s), in the vertex
# shader: each is a `sac_*` limb of an idle rig (wube_rig.py's table, creature_models.gd).

SPAWNER_RATE = 0.1 * 60 / 32  # loops a second
SPAWNER_PULSE = 0.09  # how much a sac swells


def relief_loft(p, columns, mat, segs=12, sink=0.0):
    """A heap through east-west columns (x, centre z, half depth, height: glTF's z, south +):
    each a half-ellipse standing on the ground, closed underneath and at both ends."""
    bm = bmesh.new()
    rows = []
    for x, zc, d, h in columns:
        row = []
        for i in range(segs + 1):
            t = math.pi * i / segs
            z, y = zc + d * math.cos(t), h * math.sin(t)
            row.append(bm.verts.new((x, -z, y - sink)))
        rows.append(row)
    for a_, b_ in zip(rows, rows[1:]):
        for i in range(segs):
            bm.faces.new([a_[i], b_[i], b_[i + 1], a_[i + 1]])
        bm.faces.new([a_[segs], b_[segs], b_[0], a_[0]])
    bm.faces.new(rows[0])
    bm.faces.new(list(reversed(rows[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    p.merge(bm, mat)
    bm.free()
    return p


def _gleba_spawner(name):
    import wube_rig
    from creature_profiles import RELIEFS
    relief = RELIEFS[name]
    p = Part()
    p.sharp_angle = 70.0
    sacs = _Limbs(p, soft=(-2.0, -1.0))  # a sac swells whole
    relief_loft(p, relief["columns"], "flesh_puff", sink=0.1)
    limbs, gait = {}, {}
    for i, (x, y, z, r) in enumerate(relief["bulbs"][:12]):
        c = Vector((x, -z, y))
        sacs.joints.append(c)
        with sacs.on(i):
            blob(p, tuple(c), r, "flesh_egg", segs=14, rings=8, scale=(1.0, 1.0, 0.92), seed=300 + i, wobble=0.05)
        limbs["sac_%d" % i] = [(x, y, z), (x, y + r, z)]
        gait["sac_%d" % i] = ((i * 0.37) % 1.0, 0.0, 0.0, SPAWNER_PULSE)
    wube_rig.write_rig_table(name, {"mode": "idle", "rate": round(SPAWNER_RATE, 4), "limbs": limbs, "gait": gait})
    return p


@model("gleba-spawner")
def gleba_spawner():
    """Gleba spawner: a broad heap of veined yellow-orange membrane bulging with glossy green
    egg sacs, which swell and settle as it breathes."""
    return _gleba_spawner("gleba-spawner")


@model("gleba-spawner-small")
def gleba_spawner_small():
    """Small Gleba spawner: a low mound of the same membrane round a couple of egg sacs."""
    return _gleba_spawner("gleba-spawner-small")


@model("gleba-spawner-corpse")
def gleba_spawner_corpse():
    """What a Gleba spawner leaves: a dark green splash of slime on the ground, a sunken crater
    where the heap stood and streaks thrown out round it (Factorio's corpse picture, at the big
    spawner's 0.9 scale; the small one's is the same at 0.3)."""
    from creature_profiles import RELIEFS
    p = Part()
    step = 0.0625
    bm = bmesh.new()
    for x, zc, d, h in RELIEFS["gleba-spawner-corpse"]["columns"]:
        # Each stretch a flat strip on the ground: the splash is all top.
        vs = [bm.verts.new((x + dx, -(zc + dz), h)) for dx, dz in
              ((-step / 2, -d), (step / 2, -d), (step / 2, d), (-step / 2, d))]
        bm.faces.new(vs)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        if f.normal.z < 0:
            f.normal_flip()
    p.merge(bm, "flesh_slime")
    bm.free()
    return p


# ---------------------------------------------------------------------------------------------
# Capture robot (a flying robot: the client lifts movers of its type off the ground, so the
# model sits on its own origin like the others).

@model("capture-robot")
def capture_robot():
    """Factorio's capture robot, facing north: a weathered teal-steel body whose top is an open
    hatch framed in pale steel and copper with the capture claw lying in it, a riveted
    green-and-rust plate across the south face, fat round tanks lying along both sides with two
    smaller ones at the north shoulders, dark hoses arching between them, and a pale corrugated
    bellows standing on the north end with a brass collar in front of its foot.

    Sized from the sprite with Factorio's own camera: the south plate shows 0.6 tiles tall, the
    top 1.15 deep, the tanks reach a tile either side and the bellows 1.75 up the screen."""
    p = Part()
    # Body and the south plate, its lower corners cut off as in the sprite.
    p.slab(-0.55, -0.95, 0.0, 0.55, 0.6, 0.88, "steel_teal", bevel=0.06)
    p.prism([(-0.45, 0.0), (0.45, 0.0), (0.62, 0.32), (0.62, 0.92), (-0.62, 0.92), (-0.62, 0.32)], 0.9, 1.06,
            "rust_brown", bevel=0.03, matrix=R("X", 90))
    p.slab(-0.5, -1.08, 0.24, 0.5, -1.05, 0.72, "paint_green", bevel=0.01)
    for x in (-0.42, -0.14, 0.14, 0.42):
        for z in (0.34, 0.62):
            p.bolt((x, -1.09, z), "steel_light", axis="Y")
    # The hatch on top: a dark well, pale frame rails, copper side rails, the claw lying in it.
    p.slab(-0.46, -0.85, 0.86, 0.46, 0.5, 0.9, "soot")
    for x in (-0.48, -0.28, 0.28, 0.48):
        p.slab(x - 0.05, -0.9, 0.86, x + 0.05, 0.5, 1.0, "paint_bone", bevel=0.015)
    p.slab(-0.5, -0.98, 0.86, 0.5, -0.86, 1.0, "paint_bone", bevel=0.015)
    for x in (-0.38, 0.38):
        p.slab(x - 0.035, -0.86, 0.86, x + 0.035, 0.45, 0.96, "copper_pipe", bevel=0.01)
    p.slab(-0.1, -0.7, 0.88, 0.1, 0.35, 0.98, "paint_bone", bevel=0.01)
    p.slab(-0.2, 0.15, 0.88, 0.2, 0.42, 1.04, "paint_bone", bevel=0.02)
    p.cyl((0.0, -0.4, 0.99), 0.05, 0.03, "steel_dark", segs=8)

    # Side tanks lying north-south, the smaller shoulder tanks at the north corners, and dark
    # hoses from the shoulders over the tanks and down their outsides.
    for sx in (-1, 1):
        p.cyl((sx * 0.72, 0.1, 0.5), 0.28, 1.0, "steel_teal", segs=14, axis="Y", bevel=0.04)
        p.sphere((sx * 0.72, -0.4, 0.5), 0.28, "steel_teal", segs=14, rings=7, scale=(1, 0.6, 1))
        for y in (-0.3, 0.45):
            p.cyl((sx * 0.72, y, 0.5), 0.295, 0.05, "rust_brown", segs=14, axis="Y")
        p.sphere((sx * 0.47, 0.7, 1.0), 0.22, "steel_teal", segs=12, rings=6, scale=(1, 1, 0.9))
        bent(p, [(sx * 0.3, 0.62, 1.02), (sx * 0.6, 0.48, 0.98), (sx * 0.84, 0.2, 0.8), (sx * 0.95, -0.1, 0.55),
                 (sx * 0.94, -0.4, 0.32)], 0.055, "rubber", segs=6)

    # The bellows standing on the north end: ribbed, a domed cap; the brass collar before it.
    bx, by = 0.0, 0.74
    prof, z = [(0.3, 0.5), (0.3, 0.92)], 0.92
    for k in range(5):
        r = 0.36 - 0.012 * k
        prof += [(r, z + 0.03), (r, z + 0.06), (r - 0.05, z + 0.09)]
        z += 0.09
    prof += [(0.28, z + 0.03), (0.2, z + 0.1), (0.0, z + 0.12)]
    lathe(p, (bx, by, 0.0), prof, "glass_pale", segs=16)
    p.cyl((bx, 0.42, 1.04), 0.21, 0.18, "brass", segs=14, axis="Y", bevel=0.02)
    p.cyl((bx, 0.32, 1.04), 0.12, 0.02, "soot", segs=12, axis="Y")

    # Its capture animation (32 frames at 0.25, the only picture Factorio has for it): dark
    # cables hang from under the body to the ground round it, purple tips glowing where they
    # touch, and a thin probe in the middle. Each cable is a part of its own (`anim_cable`, pivot
    # where it leaves the body) that vehicle_anim.gd sways out of step with the others; the
    # client flies the robot CAPTURE_HEIGHT up, so the cables reach that far down.
    parts = [p]
    for k in range(7):
        a = math.radians(-100 + k * 200 / 6 + (12 if k % 2 else 0))
        c, s = math.cos(a), math.sin(a)
        top = (0.45 * c, -0.2 + 0.55 * s, 0.1)
        out = 1.05 + 0.15 * (k % 3)
        cable = Part("anim_cable", pivot=top)
        bent(cable, [top, (0.9 * c, -0.2 + 0.95 * s, -0.25), (out * c, -0.2 + out * s, -0.9),
                     (out * 0.95 * c, -0.2 + out * 0.95 * s, -CAPTURE_HEIGHT + 0.08)], 0.04, "rubber", segs=5)
        cable.sphere((out * 0.95 * c, -0.2 + out * 0.95 * s, -CAPTURE_HEIGHT + 0.06), 0.06, "glow_purple", segs=8, rings=4)
        parts.append(cable)
    probe = Part("anim_cable", pivot=(0.0, -0.3, 0.0))
    probe.tube((0.0, -0.3, 0.0), (0.05, -0.45, -CAPTURE_HEIGHT + 0.1), 0.015, "steel_dark", segs=5)
    probe.sphere((0.05, -0.45, -CAPTURE_HEIGHT + 0.08), 0.05, "glow_purple", segs=8, rings=4)
    parts.append(probe)
    return parts


CAPTURE_HEIGHT = 1.6  # the client's flying height for capture robots (visuals.gd)
