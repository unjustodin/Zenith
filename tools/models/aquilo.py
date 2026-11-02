"""Aquilo: cryogenic plant, fusion reactor, fusion generator, railgun turret, lithium icebergs,
lithium brine and fluorine vents.

Matched to Factorio's HR sprites with compare.py, like gleba.py.
"""

import math

import detail
import kit
from kit import Part, R, S, T, model
from space_kit import (COS_P, SIN_P, bent, blob, dome, flange, hose, lathe, ring, rock, sweep, ys,
                       zs)

kit.MATERIALS.update({
    "plasma_pink": ("ff3a86", 0.4, 0.0, "ff1a6a", 2.5),  # the fusion plant's plasma glow
})


# ---------------------------------------------------------------------------------------------
# Cryogenic plant (5x5).

@model("cryogenic-plant")
def cryogenic_plant():
    """Factorio's cryogenic plant at its true proportions (Space Age pictures draw the ground's
    north-south distances at full length): a riveted pale-blue helmet with a dark window, on a
    heap of blue armoured housings that fill the footprint; fat tan ribbed hoses arc over the
    front from the west corner to the east; a steel tank and a white capsule on a stand in the
    east, a radiator box in the north-west, a drawer cabinet and a hand-wheel port at the front,
    steel cans at the front corners. Masses fitted to the picture's outline.

    Moving parts, from Factorio's 192-frame loop at 0.5 (6.4 s): the drawer cabinet's drawers slide
    out south and back once a loop (`anim_slide_cryo_drawers`, anim6), the cover over a grille on
    the west housing slides off and back twice a loop (`anim_slide_cryo_hatch`, anim5), and the
    capsule's level gauge glows, breathing every 3.2 s (`anim_glow_cryo_gauge`, anim3)."""
    p = Part()
    B, BD, S_, H = "paint_aquilo", "paint_aquilo_dark", "steel_cold", "hose_tan"
    # Armoured housings under everything.
    lathe(p, (0.1, 0.0, 0.0), [(2.3, 0.0), (2.3, 0.45), (2.0, 0.8), (1.6, 0.95), (0.0, 0.95)], B, segs=28)
    p.slab(-2.44, -1.84, 0.0, -1.0, 1.42, 1.75, B, bevel=0.22)
    p.slab(-2.46, -1.6, 0.2, -2.42, 1.2, 1.5, BD)
    p.slab(-1.36, -2.19, 0.0, 0.4, -0.6, 1.0, B, bevel=0.15)
    p.slab(0.4, -1.0, 0.0, 2.0, 1.5, 1.65, B, bevel=0.2)
    for x, y, ax in ((-2.45, -0.6, "X"), (-2.45, 0.6, "X"), (-0.8, -2.2, "Y"), (-0.1, -2.2, "Y"), (2.01, 0.0, "X")):
        p.bolts_ring((x, y, 0.85), 0.25, 8, "steel_light", axis=ax)

    # The helmet: riveted drum and dome with a window, a pipe fitting on top.
    hx, hy, hz, hr = -0.15, 0.2, 2.1, 1.1
    lathe(p, (hx, hy, 0.0), [(hr, 0.8), (hr, hz), (0.0, hz)], B, segs=24)
    dome(p, (hx, hy, hz), hr, 0.9, B, segs=24, rings=7)
    lathe(p, (hx, hy, 0.0), [(hr + 0.03, hz - 0.05), (hr + 0.03, hz + 0.05)], S_, segs=24)
    p.bolts_ring((hx, hy, hz + 0.08), hr, 28, "steel_light", radius=0.02)
    for k in range(6):
        a0 = math.radians(235 + k * 12)
        a1 = math.radians(235 + (k + 1) * 12)
        q = [(hx + hr * math.cos(a0), hy + hr * math.sin(a0)), (hx + hr * math.cos(a1), hy + hr * math.sin(a1))]
        p.poly([(q[0][0], q[0][1] - 0.02, 1.75), (q[1][0], q[1][1] - 0.02, 1.75), (q[1][0], q[1][1] - 0.02, 2.3),
                (q[0][0], q[0][1] - 0.02, 2.3)], "glass_dark", thick=0.03)
    lathe(p, (hx, hy, 0.0), [(hr + 0.04, 1.68), (hr + 0.04, 1.76)], S_, segs=24, a0=228, a1=312)
    lathe(p, (hx, hy, 0.0), [(hr, 2.3), (hr + 0.02, 2.36)], S_, segs=24, a0=228, a1=312)
    p.cyl((hx, hy, hz + 0.92), 0.2, 0.15, S_, segs=14, bevel=0.03)
    bent(p, [(hx, hy, hz + 0.95), (hx, hy, 3.2), (hx + 0.15, hy + 0.25, 3.3), (hx + 0.55, hy + 0.7, 3.1), (hx + 0.7, 1.3, 2.4)],
         0.12, S_, segs=10)

    # Fat ribbed hoses over the front.
    hose(p, [(-2.2, -1.9, 0.4), (-1.5, -2.0, 0.7), (-0.8, -1.4, 1.35), (-0.3, -0.85, 1.65), (0.3, -0.85, 1.55), (0.9, -1.1, 1.3),
             (1.3, -1.0, 1.45), (1.7, -1.1, 1.05), (2.15, -1.3, 0.45)], 0.25, H, segs=10, rib=0.14)
    hose(p, [(0.85, 0.1, 1.65), (1.3, -0.2, 1.75), (1.85, -0.4, 1.25), (2.2, -0.6, 0.45)], 0.18, H, segs=10, rib=0.12)
    hose(p, [(-0.9, -0.7, 1.2), (-1.2, -1.3, 0.95), (-1.6, -1.7, 0.6), (-1.9, -2.15, 0.3)], 0.15, H, segs=8, rib=0.12)

    # East: a steel tank with a vented cap, and a white capsule on a stand.
    tx, ty = 1.95, 1.2
    lathe(p, (tx, ty, 0.0), [(0.42, 0.0), (0.42, 1.85), (0.34, 2.0), (0.2, 2.06), (0.0, 2.06)], S_, segs=18)
    for z in (0.6, 1.3):
        lathe(p, (tx, ty, 0.0), [(0.44, z), (0.44, z + 0.08)], "steel_dark", segs=18)
    p.cyl((tx, ty, 2.12), 0.16, 0.14, S_, segs=12, bevel=0.03)
    cx_, cy_ = 2.14, 0.45
    p.slab(cx_ - 0.25, cy_ - 0.25, 0.0, cx_ + 0.25, cy_ + 0.25, 0.65, "steel_dark", bevel=0.04)
    lathe(p, (cx_, cy_, 0.0), [(0.0, 0.6), (0.24, 0.65), (0.28, 0.75), (0.28, 2.5), (0.24, 2.62), (0.0, 2.66)], "paint_bone", segs=14)
    p.bolts_ring((cx_, cy_, 1.6), 0.29, 10, "steel_light")

    # North-west radiator box on a pipe frame, a north box.
    p.slab(-2.3, 1.42, 0.0, -1.2, 2.1, 1.0, "steel_dark", bevel=0.08)
    for k in range(4):
        p.slab(-2.2 + k * 0.25, 1.4, 0.2, -2.05 + k * 0.25, 1.42, 0.85, "steel_black")
    bent(p, [(-2.2, 1.75, 1.0), (-2.2, 1.75, 1.3), (-1.5, 1.75, 1.3), (-1.3, 1.5, 1.5), (-1.0, 1.0, 1.7)], 0.09, S_, segs=8)
    p.slab(0.13, 1.6, 0.0, 1.2, 2.14, 1.3, "steel_dark", bevel=0.06)

    # Front: drawer cabinet, hand-wheel port, steel cans in the corners.
    p.slab(0.7, -2.2, 0.0, 1.15, -1.4, 1.15, S_, bevel=0.05)
    drawers = Part("anim_slide_cryo_drawers", pivot=(0.92, -2.2, 0.6))
    for z in (0.3, 0.7):
        drawers.slab(0.75, -2.23, z, 1.1, -2.17, z + 0.3, "steel_dark", bevel=0.02)
    # West: a grille on the housing's top under a cover that slides south off it and back.
    for k in range(4):
        p.slab(-2.1, -0.85 + k * 0.15, 1.75, -1.6, -0.78 + k * 0.15, 1.77, "steel_black")
    hatch = Part("anim_slide_cryo_hatch", pivot=(-1.85, -0.55, 1.78))
    hatch.slab(-2.2, -0.9, 1.76, -1.5, -0.2, 1.82, B, bevel=0.02)
    # East: the capsule's level gauge, lit while it works.
    gauge = Part("anim_glow_cryo_gauge")
    gauge.slab(2.1, 0.13, 1.0, 2.18, 0.18, 2.3, "glow_blue")
    p.cyl((0.05, -1.95, 0.4), 0.23, 0.6, B, segs=16, axis="Y", bevel=0.04)
    p.cyl((0.05, -2.26, 0.4), 0.11, 0.05, "paint_red", segs=12, axis="Y")
    p.cyl((-1.85, -1.95, 0.45), 0.6, 0.6, S_, segs=16, bevel=0.06)
    p.cyl((-1.85, -1.95, 0.77), 0.4, 0.06, "steel_dark", segs=14)
    p.cyl((2.04, -1.7, 0.62), 0.3, 1.24, S_, segs=14, bevel=0.05)
    p.cyl((2.04, -1.7, 1.26), 0.2, 0.05, "steel_dark", segs=12)
    # Wiring and small pipes.
    bent(p, [(-0.75, 0.3, 2.3), (-0.6, -0.4, 2.1), (-0.85, -0.75, 1.6), (-1.0, -0.95, 1.2)], 0.05, S_, segs=6)
    bent(p, [(0.6, -0.5, 1.95), (0.9, -0.6, 1.7), (1.4, -0.5, 1.8), (1.6, -0.3, 2.05)], 0.06, S_, segs=6)
    _cryo_detail(p, hx, hy, hz, hr, tx, ty, cx_, cy_)
    return [p, drawers, hatch, gauge]


def _cryo_detail(p, hx, hy, hz, hr, tx, ty, cx_, cy_):
    """The cryogenic plant sprite's surface detail inside its fitted masses: rows of rivets on the
    helmet's plates and the housings' edges, the window's riveted frame, red and green wires down
    the helmet, bolted collars on the steel pipes, the tank's vented cap, the capsule's rivet
    column, plates and grilles on the housings, the hand-wheel's spokes."""
    B, BD, S_ = "paint_aquilo", "paint_aquilo_dark", "steel_cold"
    # The helmet: rivet rows up its plates' seams and round the dome.
    for a in (200, 222, 318, 340):
        r = math.radians(a)
        for k in range(4):
            z = 1.0 + k * 0.3
            p.bolt((hx + (hr + 0.005) * math.cos(r), hy + (hr + 0.005) * math.sin(r), z), "steel_light", radius=0.02,
                   depth=0.03, axis="Z")
    for el in (25, 52):
        e = math.radians(el)
        p.bolts_ring((hx, hy, hz + 0.9 * math.sin(e) + 0.01), hr * math.cos(e) + 0.005, 12, "steel_light", radius=0.02)
    # The window's frame: a steel rim round it with rivets.
    for z in (1.72, 2.33):
        lathe(p, (hx, hy, 0.0), [(hr + 0.035, z - 0.03), (hr + 0.035, z + 0.03)], S_, segs=24, a0=231, a1=309)
    for a in (231, 309):
        r = math.radians(a)
        p.box((hx + (hr + 0.035) * math.cos(r), hy + (hr + 0.035) * math.sin(r), 2.02), (0.06, 0.06, 0.66), S_, rz=a)
    # Red and green wires down the helmet's west side into the housing.
    for i, (mat, d) in enumerate((("wire_red", 0.0), ("wire_green", 0.05))):
        detail.cable(p, [(hx - 0.35 + d, hy - 0.9, 2.55), (hx - 0.55 + d, hy - 0.95, 2.1), (hx - 0.7 + d, hy - 0.85, 1.6),
                         (-0.95 + d, -0.95, 1.1)], 0.022, mat, segs=4)
    # The housings: rivets along their top edges, plates and a grille on their fronts.
    detail.rivet_line(p, (-2.3, -1.85, 1.6), (-1.15, -1.85, 1.6), 8, "Y", "steel_light", r=0.02)
    detail.rivet_line(p, (-1.25, -2.2, 0.88), (0.3, -2.2, 0.88), 10, "Y", "steel_light", r=0.02)
    detail.rivet_line(p, (0.55, -1.01, 1.5), (1.85, -1.01, 1.5), 9, "Y", "steel_light", r=0.02)
    detail.panel(p, (-2.44, -1.84, 0.0), (-1.0, 1.42, 1.75), "-y", B, rivet="steel_light", margin=0.22)
    detail.panel(p, (0.4, -1.0, 0.0), (2.0, 1.5, 1.65), "-y", B, margin=0.22, split=2)
    detail.slots(p, (-1.0, -2.19, 0.15), (-0.3, -0.6, 0.75), "-y", 4, mat="steel_black")
    p.slab(-2.47, -1.5, 0.3, -2.44, -0.9, 0.7, "steel_black")
    # Grey pipework and a motor drum over the west housing, a box of switchgear on the front one
    # (the sprite's housings are half hidden under steel pipes).
    for pts in ([(-2.3, 1.2, 1.75), (-2.3, 0.4, 1.88), (-1.6, 0.2, 1.92), (-1.25, 0.5, 1.98), (-1.0, 0.45, 1.7)],
                [(-2.35, -1.5, 1.55), (-2.05, -1.6, 1.85), (-1.45, -1.55, 1.88), (-1.1, -1.25, 1.65)],
                [(-2.1, 0.9, 1.75), (-1.9, 0.75, 1.95), (-1.4, 0.85, 2.0), (-1.05, 1.1, 1.8)]):
        bent(p, pts, 0.07, S_, segs=6, smooth=3)
    p.cyl((-1.75, -0.95, 1.9), 0.2, 0.8, S_, segs=12, axis="X", bevel=0.03)
    for x in (-2.05, -1.45):
        p.cyl((x, -0.95, 1.9), 0.215, 0.05, "steel_dark", segs=12, axis="X")
    p.slab(-0.55, -1.65, 0.95, 0.15, -1.05, 1.3, "steel_dark", bevel=0.03)
    p.slab(-0.45, -1.67, 1.02, 0.05, -1.65, 1.22, "steel_light")
    p.cyl((-0.75, -1.4, 1.15), 0.12, 0.3, S_, segs=10, bevel=0.02)
    detail.cable(p, [(-0.45, -1.4, 1.3), (-0.6, -1.45, 1.35), (-0.75, -1.4, 1.3)], 0.02, "wire_red", segs=4)
    detail.cable(p, [(-0.45, -1.3, 1.3), (-0.6, -1.3, 1.38), (-0.75, -1.3, 1.3)], 0.02, "wire_green", segs=4)
    # Bolted collars on the steel pipes, rings round the hoses' ends.
    for c, ax in (((hx, hy, 3.2), "Z"), ((hx + 0.55, hy + 0.7, 3.1), "Y"), ((-2.2, 1.75, 1.15), "Z"), ((-1.5, 1.75, 1.3), "X")):
        flange(p, c, 0.15, ax, S_, depth=0.07, segs=10)
        p.bolts_ring(c, 0.12, 4, "steel_light", radius=0.016, axis=ax, depth=0.08, start=45)
    for c in ((-2.2, -1.9, 0.4), (2.15, -1.3, 0.45), (2.2, -0.6, 0.45), (-1.9, -2.15, 0.3)):
        p.cyl(c, 0.27, 0.08, S_, segs=10)
    # The tank's vented cap and its riveted seams; the capsule's rivet column.
    p.bolts_ring((tx, ty, 2.19), 0.11, 8, "soot", radius=0.025, depth=0.01)
    p.bolts_ring((tx, ty, 0.64), 0.445, 10, "steel_light", radius=0.018, depth=0.05)
    p.bolts_ring((tx, ty, 1.34), 0.445, 10, "steel_light", radius=0.018, depth=0.05)
    for k in range(9):
        p.bolt((cx_ - 0.29, cy_ - 0.05, 0.85 + k * 0.18), "steel_light", radius=0.018, depth=0.03, axis="X")
    # The front: the hand-wheel's spokes, the cans' riveted bands, the drawer cabinet's rivets.
    for a in (0, 60, 120):
        p.box((0, 0, 0), (0.2, 0.02, 0.025), "paint_red", matrix=T(0.05, -2.28, 0.4) @ R("Y", a))
    p.bolts_ring((-1.85, -1.95, 0.45), 0.605, 12, "steel_light", radius=0.018, depth=0.05)
    p.bolts_ring((2.04, -1.7, 0.9), 0.305, 10, "steel_light", radius=0.016, depth=0.05)
    detail.rivet_line(p, (0.72, -2.205, 1.1), (1.13, -2.205, 1.1), 4, "Y", "steel_light", r=0.016)


# ---------------------------------------------------------------------------------------------
# Fusion reactor (6x6) and fusion generator (3x5).

def _fusion_port(p, x, y, out_x, out_y, z=0.45):
    """A connection port on the reactor's edge: a housing with a ribbed round cap facing out
    (Factorio draws these as connection sprites; frame 0, unconnected, is what we model)."""
    yaw = math.degrees(math.atan2(out_y, out_x))
    m = T(x, y, 0) @ R("Z", yaw)
    p.box((-0.25, 0, 0.35), (0.6, 0.9, 0.7), "paint_fusion", bevel=0.1, matrix=m)
    for k, (r, d) in enumerate(((0.42, 0.14), (0.34, 0.1), (0.26, 0.08), (0.14, 0.06))):
        p.cyl((0.07 + k * 0.08, 0, z), r, d, "paint_bone" if k % 2 else "steel_cold", segs=16, axis="X", matrix=m)


@model("fusion-reactor")
def fusion_reactor():
    """Factorio's fusion reactor at its true proportions (Space Age pictures draw the ground's
    north-south distances at full length): a ring of blue armoured plasma chambers round a tall
    banded column, olive domed tanks at the back corners, white tanks at the front corners, and
    ribbed connection ports on all four edges (two per edge). Masses fitted to the picture's
    outline, connection sprites included.

    Factorio draws it still, with a pink plasma glow in the slots on top of each chamber and a
    lamp on the column (fusion-reactor-glow) while it works; here they are `anim_glow_plasma`,
    breathing as the plasma flows."""
    p = Part()
    B, BD, W = "paint_fusion", "paint_aquilo_dark", "paint_bone"
    cx, cy = 0.0, 0.24
    # The ring of chambers.
    prof = [(0.0, 0.0), (2.95, 0.0), (3.0, 0.45), (2.85, 0.95), (2.4, 1.3), (1.8, 1.62), (1.3, 1.5), (1.05, 1.2), (0.0, 1.1)]
    lathe(p, (cx, cy, 0), prof, B, segs=32)
    for k in range(8):  # seams and dark vents between the chambers
        a = math.radians(k * 45 + 22.5)
        p.box((cx + 1.9 * math.cos(a), cy + 1.9 * math.sin(a), 0.82), (0.12, 1.7, 1.64), BD, bevel=0.03, rz=math.degrees(a))
        b = math.radians(k * 45)
        p.box((cx + 2.72 * math.cos(b), cy + 2.72 * math.sin(b), 0.85), (0.08, 0.35, 0.8), "steel_black", rz=math.degrees(b))
    lathe(p, (cx, cy, 0), [(1.7, 1.62), (1.8, 1.66), (1.9, 1.62)], "steel_cold", segs=32)
    # The plasma slots along the top of each chamber, lit while it works.
    plasma = Part("anim_glow_plasma")
    for k in range(8):
        lathe(plasma, (cx, cy, 0), [(2.3, 1.38), (2.12, 1.48)], "plasma_pink", segs=6, a0=k * 45 - 11, a1=k * 45 + 11)
    # The column.
    kx, ky = 0.0, 0.12
    lathe(p, (kx, ky, 0), [(0.95, 1.2), (0.95, 2.3), (0.85, 2.6), (0.75, 2.75), (0.75, 3.4), (0.72, 3.45), (0.72, 4.0),
                            (0.66, 4.05), (0.66, 4.4), (0.5, 4.5), (0.12, 4.55), (0.0, 4.55)], B, segs=20)
    for z in (2.7, 3.42, 4.02):
        lathe(p, (kx, ky, 0), [(0.79 - (z - 2.7) * 0.1, z), (0.79 - (z - 2.7) * 0.1, z + 0.07)], "steel_cold", segs=20)
    p.cyl((kx - 0.1, ky + 0.1, 4.75), 0.12, 0.4, W, segs=10)
    p.sphere((kx - 0.1, ky + 0.1, 5.0), 0.09, W, segs=8, rings=4)
    p.slab(kx - 0.7, ky - 0.75, 2.3, kx - 0.35, ky - 0.5, 4.2, W, bevel=0.03)  # white riser on the column's front
    plasma.sphere((kx + 0.05, ky - 0.78, 3.1), 0.07, "plasma_pink", segs=8, rings=4)
    bent(p, [(kx + 0.35, ky - 0.4, 4.3), (kx + 0.5, ky - 0.45, 4.6), (kx + 0.2, ky - 0.1, 4.6)], 0.05, "brass_dull", segs=6)
    # Machinery in the ring's middle, in front of the column.
    p.cyl((0.4, -0.6, 0.95), 0.3, 1.9, B, segs=14, bevel=0.04)
    p.cyl((0.75, -0.25, 0.8), 0.25, 1.6, "steel_cold", segs=12, bevel=0.04)
    p.slab(-0.6, -1.2, 0.0, 0.1, -0.5, 1.9, BD, bevel=0.06)
    # Olive domed tanks, back corners.
    for x, y, r, h in ((-2.11, 1.48, 0.81, 1.34), (2.08, 1.46, 0.69, 1.5)):
        lathe(p, (x, y, 0), [(r, 0.0), (r, h * 0.7), (r * 0.85, h * 0.88), (r * 0.5, h), (0.0, h * 1.03)], "olive_steel", segs=18)
        p.bolts_ring((x, y, h * 0.72), r + 0.01, 16, "steel_light")
        hose(p, [(x * 0.75, y - 0.2, h * 0.9), (x * 0.6, y - 0.6, h + 0.2), (x * 0.45, y - 0.9, 1.9)], 0.08, "hazard", rib=0.08)
    # White tanks at the front corners.
    lathe(p, (-2.35, -2.09, 0), [(0.48, 0.0), (0.48, 1.75), (0.38, 1.88), (0.0, 1.9)], W, segs=16)
    p.bolts_ring((-2.35, -2.09, 1.78), 0.42, 10, "steel_light")
    lathe(p, (1.75, -1.25, 0), [(0.4, 0.0), (0.4, 2.3), (0.3, 2.42), (0.0, 2.45)], W, segs=16)
    bent(p, [(1.75, -1.25, 2.42), (1.75, -1.25, 2.6), (1.45, -1.3, 2.6), (1.4, -1.4, 1.6)], 0.06, "steel_cold", segs=6)
    # Pipes round the front of the ring.
    bent(p, [(-2.2, -1.4, 0.5), (-1.2, -2.7, 0.45), (0.0, -2.95, 0.4), (1.2, -2.7, 0.45)], 0.08, "brass_dull", segs=8)
    # A pump housing on the front-east corner.
    p.slab(1.9, -2.9, 0.0, 2.8, -2.2, 0.9, BD, bevel=0.1)
    p.cyl((2.35, -2.55, 0.95), 0.25, 0.15, "steel_cold", segs=12)
    # Connection ports: two per edge, ribbed round caps facing out (Factorio's connection
    # sprites, frame 0, unconnected); the front ones stand out furthest.
    for x in (-1.5, 1.5):
        _fusion_port(p, x, -2.95, 0, -1, z=0.59)
        _fusion_port(p, x, 2.75, 0, 1, z=0.4)
    for y in (-1.6, 1.45):
        _fusion_port(p, 2.75, y, 1, 0)
        _fusion_port(p, -2.75, y, -1, 0)
    _fusion_reactor_detail(p, cx, cy, prof, kx, ky)
    return [p, plasma]


def _profile_z(prof, r):
    """The height of a lathe profile's outer slope at radius r."""
    pts = [q for q in prof if q[0] >= 1.8]
    pts.sort()
    for (r0, z0), (r1, z1) in zip(pts, pts[1:]):
        if r0 <= r <= r1:
            return z0 + (z1 - z0) * (r - r0) / max(1e-6, r1 - r0)
    return pts[-1][1]


def _fusion_reactor_detail(p, cx, cy, prof, kx, ky):
    """The fusion reactor sprite's surface detail inside its fitted masses: rivet rows down every
    chamber seam, the dark oval vents in the chambers' sides, yellow ribbed hoses from the
    chambers up to the column, brass pipes on clamps round the front, panels and cables on the
    column, control panels on the white tanks."""
    for k in range(8):
        a = k * 45 + 22.5
        for side in (-5, 5):
            r_ = math.radians(a + side)
            for i in range(4):
                rr = 2.0 + i * 0.25
                p.bolt((cx + rr * math.cos(r_), cy + rr * math.sin(r_), _profile_z(prof, rr) + 0.01), "steel_light",
                       radius=0.022, depth=0.04)
        # The vent in the chamber's side and a riveted plate above it.
        b = k * 45
        lathe(p, (cx, cy, 0), [(2.87, 0.9), (2.7, 1.07)], "steel_black", segs=4, a0=b - 13, a1=b + 13)
        lathe(p, (cx, cy, 0), [(2.53, 1.21), (2.25, 1.39)], "paint_aquilo_dark", segs=4, a0=b - 15, a1=b + 15)
    # Yellow ribbed hoses from four chambers up to the column.
    for a in (60, 150, 240, 300):
        r_ = math.radians(a)
        c, s = math.cos(r_), math.sin(r_)
        hose(p, [(cx + 2.15 * c, cy + 2.15 * s, _profile_z(prof, 2.15) + 0.05), (cx + 1.6 * c, cy + 1.6 * s, 1.95),
                 (kx + 0.98 * c, ky + 0.98 * s, 2.25)], 0.06, "hazard", rib=0.09)
    # Brass pipes round the front on clamps.
    run = [(cx + 3.0 * math.cos(math.radians(a)), cy + 3.0 * math.sin(math.radians(a)), 0.25) for a in range(205, 336, 13)]
    bent(p, run, 0.05, "brass_dull", segs=6, smooth=2)
    for q in run[1::2]:
        p.box(q, (0.12, 0.12, 0.12), "steel_cold")
    # The column: plates with rivets, cables down its front, a band of bolts.
    for z in (2.35, 3.1, 3.75):
        p.bolts_ring((kx, ky, z), 0.96 - (z - 2.35) * 0.18, 20, "steel_light", radius=0.018, depth=0.05)
    for a in (230, 255, 285, 310):
        r_ = math.radians(a)
        p.box((kx + 0.77 * math.cos(r_), ky + 0.77 * math.sin(r_), 3.07), (0.03, 0.18, 0.55), "paint_aquilo_dark", rz=a)
    for i, (mat, d) in enumerate((("wire_red", 0.0), ("wire_green", 0.06), ("wire_yellow", 0.12))):
        detail.cable(p, [(kx + 0.2 + d, ky - 0.62, 4.3), (kx + 0.25 + d, ky - 0.8, 3.5), (kx + 0.3 + d, ky - 0.98, 2.4),
                         (kx + 0.4 + d, ky - 1.35, 1.6)], 0.022, mat, segs=4)
    # Control panels on the white tanks: a dark plate with lamps and switches.
    for x, y, r, z in ((-2.35, -2.09, 0.48, 1.0), (1.75, -1.25, 0.4, 1.3)):
        p.slab(x - 0.17, y - r - 0.02, z - 0.25, x + 0.17, y - r + 0.06, z + 0.25, "steel_black")
        for j, lamp in enumerate(("lamp_red", "lamp_green", "steel_light")):
            p.slab(x - 0.12 + j * 0.09, y - r - 0.035, z + 0.08, x - 0.06 + j * 0.09, y - r - 0.015, z + 0.15, lamp)
        p.bolts_ring((x, y, z + 0.55), r + 0.005, 12, "steel_light", radius=0.018, depth=0.05)


@model("fusion-generator")
def fusion_generator():
    """Factorio's fusion generator, facing north, at its true proportions (its four pictures draw
    the ground's north-south distances at full length): a blue turbine drum lying north-south
    in the south half on a low cradle, a domed nozzle with a port at its south end, a toothed
    brass gear ring where it meets the stator, a big blue half-drum stator over the north half
    wrapped in a band of copper coils with a louvred vent on its front, olive domed tanks in the
    north corners, pumps at the waist and steel cans at the south corners. Proportions fitted to
    all four directions' outlines at once.

    Moving parts, from Factorio's 6-frame loop at speed 1 (0.1 s, the turbine's teeth and coils
    advancing one pitch a loop, as Factorio's frames repeat): the gear ring turns one tooth about
    the turbine's axis and starts over (`anim_roll_fusion_gear`), the coil band rolls one coil a loop
    (`anim_roll_fusion_coils`), and pink plasma glows at both ends of the coil band and between
    gear and stator (`anim_glow_plasma`) while it works."""
    p = Part()
    B, W = "paint_fusion", "paint_bone"
    # Cradle under everything.
    p.slab(-0.86, -2.3, 0.0, 0.9, 2.45, 0.4, "steel_dark", bevel=0.05)
    # Turbine drum, south half, and its nozzle.
    zc, r = 0.64, 0.6
    p.cyl((0, -0.9, zc), r, 1.8, B, segs=24, axis="Y", bevel=0.05)
    for y in (-1.65, -1.2, -0.75, -0.3):
        p.cyl((0, y, zc), r + 0.03, 0.06, "steel_cold", segs=24, axis="Y")
    for k in range(10):
        a = math.radians(20 + k * 14)
        p.cyl((0.62 * math.cos(a), -1.0, zc + 0.62 * math.sin(a)), 0.035, 0.05, "steel_dark", segs=6, axis="Y")
    lathe(p, (0, -2.5, zc), [(0.0, 0.0), (0.14, 0.0), (0.32, 0.15), (0.5, 0.4), (0.58, 0.72)], B, segs=20, axis="Y")
    p.cyl((0, -2.42, zc + 0.05), 0.16, 0.16, "steel_cold", segs=12, axis="Y")
    p.cyl((0, -2.5, zc + 0.05), 0.09, 0.02, "rust_brown", segs=12, axis="Y")
    for x in (-0.25, 0.25):
        p.cyl((x, -2.2, zc + 0.3), 0.1, 0.12, "steel_cold", segs=10, axis="Y")
    # Gear ring between drum and stator.
    gz = 0.8
    gear = Part("anim_roll_fusion_gear", pivot=(0, 0.15, gz))
    gear.cyl((0, 0.15, gz), 0.8, 0.3, "brass_dull", segs=28, axis="Y")
    for k in range(28):  # it only ever turns one tooth and starts over, so the gap stays below
        a = math.radians(k * 360 / 28)
        q = (0.83 * math.cos(a), 0.15, gz + 0.83 * math.sin(a))
        if q[2] > 0.05:
                gear.box(q, (0.05, 0.28, 0.06), "brass_dull",
                     matrix=T(*q) @ R("Y", -math.degrees(a)) @ T(-q[0], -q[1], -q[2]))
    # Stator: a half drum along y over the north half, a band of coils round its crown.
    sy0, sy1, sr, sz = 0.4, 1.72, 1.5, 0.28
    lathe(p, (0, sy0, sz), [(0.0, 0.0), (sr, 0.0), (sr, sy1 - sy0), (0.0, sy1 - sy0)], B, segs=20, axis="Y", a0=180, a1=360)
    p.slab(-sr, sy0, 0.0, sr, sy1, sz, B)
    for y in (sy0 + 0.04, sy1 - 0.04):
        lathe(p, (0, y, sz), [(sr + 0.02, -0.05), (sr + 0.02, 0.05)], "steel_cold", segs=20, axis="Y", a0=180, a1=360)
    coils = Part("anim_roll_fusion_coils", pivot=(0, sy0 + 0.45, sz))
    for k in range(9):
        a = math.radians(26 + k * 16)
        q = ((sr + 0.02) * math.cos(a), sy0 + 0.45, sz + (sr + 0.02) * math.sin(a))
        coils.cyl(q, 0.12, 0.55, "copper", segs=8, axis="Y")
    # Plasma glow at both ends of the coil band and in the gap between the gear and the stator.
    plasma = Part("anim_glow_plasma")
    for y in (sy0 + 0.13, sy0 + 0.77):
        lathe(plasma, (0, y, sz), [(sr + 0.03, 0.0), (sr + 0.03, 0.04)], "plasma_pink", segs=12, axis="Y", a0=200, a1=340)
    lathe(plasma, (0, 0.3, gz), [(0.72, 0.0), (0.72, 0.1)], "plasma_pink", segs=20, axis="Y")
    p.slab(-0.38, sy0 - 0.05, 0.5, 0.38, sy0 + 0.05, 1.4, "steel_dark", bevel=0.02)
    for k in range(6):
        p.slab(-0.32, sy0 - 0.08, 0.6 + k * 0.13, 0.32, sy0 - 0.03, 0.65 + k * 0.13, "steel_black")
    # Olive domed tanks in the north corners.
    for x in (-1.05, 1.05):
        lathe(p, (x, 2.1, 0), [(0.38, 0.0), (0.38, 0.5), (0.3, 0.64), (0.0, 0.7)], "olive_steel", segs=14)
        p.bolts_ring((x, 2.1, 0.52), 0.38, 10, "steel_light")
    # The waist: pumps on both sides; steel cans at the south corners; pipes between.
    for sx in (-1, 1):
        p.slab(sx * 0.85, -0.5, 0.0, sx * 1.54, 0.42, 0.72, "steel_dark", bevel=0.05)
        p.slab(sx * 1.2, -0.35, 0.1, sx * 1.56, 0.3, 0.6, B, bevel=0.04)
        p.slab(sx * 0.8, -1.8, 0.0, sx * 1.44, -0.4, 0.36, "steel_dark", bevel=0.04)
        lathe(p, (sx * 1.01, -1.68, 0), [(0.37, 0.0), (0.37, 0.5), (0.3, 0.62), (0.0, 0.64)], "steel_cold", segs=14)
        p.cyl((sx * 1.01, -1.68, 0.66), 0.2, 0.06, "steel_dark", segs=12)
        bent(p, [(sx * 0.6, -1.5, 0.75), (sx * 0.9, -1.1, 0.5), (sx * 1.1, -0.7, 0.45), (sx * 1.2, -0.4, 0.6)], 0.06,
             "brass_dull", segs=6)
    hose(p, [(1.3, -0.5, 0.55), (1.4, -0.95, 0.4), (1.35, -1.35, 0.3)], 0.08, "hazard", rib=0.08)
    _fusion_generator_detail(p, zc, r, sy0, sy1, sr, sz)
    return [p, gear, coils, plasma]


def _fusion_generator_detail(p, zc, r, sy0, sy1, sr, sz):
    """The fusion generator sprite's surface detail inside its fitted masses: bolts round the
    stator's rims and the turbine's bands, brass U-pipes on the stator's face, the nozzle's bolts,
    the olive tanks' bolted lids and a yellow hose, round pump heads at the waist, plates on the
    cradle."""
    for y in (sy0 + 0.04, sy1 - 0.04):
        for k in range(15):
            a = math.radians(12 + k * 11.2)
            p.cyl(((sr + 0.025) * math.cos(a), y, sz + (sr + 0.025) * math.sin(a)), 0.022, 0.03, "steel_light", segs=6, axis="Y")
    for y in (-1.65, -1.2, -0.75, -0.3):  # the upper half only: the cradle hides the rest
        for k in range(8):
            a = math.radians(15 + k * 21.4)
            p.cyl(((r + 0.04) * math.cos(a), y, zc + (r + 0.04) * math.sin(a)), 0.018, 0.05, "steel_light", segs=6, axis="Y")
    # Brass U-pipes on the stator's south face either side of the vent.
    for sx in (-1, 1):
        bent(p, [(sx * 0.5, sy0 - 0.06, 0.5), (sx * 0.5, sy0 - 0.08, 1.1), (sx * 0.75, sy0 - 0.08, 1.25),
                 (sx * 1.0, sy0 - 0.08, 1.05), (sx * 1.0, sy0 - 0.06, 0.45)], 0.045, "brass_dull", segs=6)
        bent(p, [(sx * 0.62, sy0 - 0.14, 0.55), (sx * 0.62, sy0 - 0.16, 0.95), (sx * 0.85, sy0 - 0.16, 1.0),
                 (sx * 0.88, sy0 - 0.14, 0.5)], 0.035, "brass_dull", segs=6)
    detail.rivet_line(p, (-0.34, sy0 - 0.06, 1.38), (0.34, sy0 - 0.06, 1.38), 5, "Y", "steel_light", r=0.016)
    # The louvred vent box straddling the stator's crown at its front, as the sprite draws it.
    vlo, vhi = (-0.3, sy0 - 0.08, 1.15), (0.3, sy0 + 0.4, 1.79)
    p.slab(*vlo, *vhi, "steel_dark", bevel=0.04)
    detail.slots(p, vlo, vhi, "-y", 5, mat="steel_black", depth=0.015)
    detail.slots(p, (-0.3, sy0 - 0.08, 1.15), (0.3, sy0 + 0.4, 1.79), "+z", 3, mat="steel_black", along=1)
    p.slab(-0.12, sy0 - 0.1, 1.17, 0.12, sy0 - 0.08, 1.27, "steel_cold")
    # The nozzle's bolts and the dark slot over its port.
    p.bolts_ring((0, -2.36, zc + 0.05), 0.24, 8, "steel_light", radius=0.018, axis="Y", depth=0.04)
    p.slab(-0.15, -2.2, zc + 0.48, 0.15, -1.9, zc + 0.52, "steel_black")
    # Olive tanks: bolted lids, a yellow ribbed hose from the west one.
    for x in (-1.05, 1.05):
        p.cyl((x, 2.1, 0.66), 0.18, 0.05, "olive_dark", segs=12)
        p.bolts_ring((x, 2.1, 0.69), 0.15, 8, "steel_light", radius=0.016, depth=0.03)
    hose(p, [(-1.2, 1.8, 0.45), (-1.35, 1.35, 0.55), (-1.3, 0.9, 0.7)], 0.08, "hazard", rib=0.08)
    # Round pump heads at the waist, bolted.
    for sx in (-1, 1):
        p.cyl((sx * 1.45, -0.02, 0.4), 0.22, 0.2, "steel_cold", segs=14, axis="X", bevel=0.03)
        p.bolts_ring((sx * 1.555, -0.02, 0.4), 0.16, 6, "steel_light", radius=0.016, axis="X", depth=0.02)
    # Plates and rivets on the cradle's sides.
    detail.rivet_line(p, (-0.8, -2.31, 0.33), (0.8, -2.31, 0.33), 8, "Y", "steel_light", r=0.016)
    detail.slots(p, (-0.86, -2.3, 0.0), (0.9, 2.45, 0.4), "-x", 6, along=1)
    detail.slots(p, (-0.86, -2.3, 0.0), (0.9, 2.45, 0.4), "+x", 6, along=1)


# ---------------------------------------------------------------------------------------------
# Railgun turret (3x5, eight directions; the head aims within 72 degrees of the way it faces).

@model("railgun-turret")
def railgun_turret():
    """Factorio's railgun turret, facing north: a long dark armoured hull with spiked shoulders
    at the north corners and a deep skirt at the south end, a steel tank along each side, a
    recessed chamber and a bundle of yellow cables at the back; the gun (`anim_turret_head`,
    pivot on its turntable; turrets.gd turns it within Factorio's turn_range and raises it from
    upright) is a grey breech with a long square rail barrel reaching north past the hull, its
    coils glowing orange."""
    p = Part()
    G, GD, D = "steel_grey", "steel_grey_dark", "rust_brown"
    # Hull.
    p.prism([(-1.45, -2.3), (-1.3, -2.48), (1.3, -2.48), (1.45, -2.3), (1.45, 1.75), (1.25, 1.95), (-1.25, 1.95), (-1.45, 1.75)],
            0.0, 0.75, GD, bevel=0.06)
    p.slab(-1.45, -2.48, 0.0, 1.45, -1.6, 1.15, D, bevel=0.12)            # south skirt
    p.slab(-1.15, -2.0, 1.15, 1.15, -1.55, 1.3, GD, bevel=0.04)
    p.slab(-1.42, -1.6, 0.0, -0.85, 0.2, 1.05, G, bevel=0.06)             # west wall
    p.slab(0.75, -1.6, 0.0, 1.42, 0.2, 1.0, GD, bevel=0.06)               # east bay
    for x in (-1.25, 1.25):                                              # spiked shoulders
        p.slab(x - 0.22, 1.25, 0.0, x + 0.22, 1.95, 1.3, GD, bevel=0.06)
        p.prism([(x - 0.2, 1.3), (x + 0.2, 1.3), (x + 0.25 * (1 if x > 0 else -1), 1.95)], 1.3, 1.75, G)
    # Side tanks.
    for x in (-1.22, 1.22):
        p.cyl((x, 0.55, 1.15), 0.25, 1.5, G, segs=14, axis="Y", bevel=0.05)
        p.cyl((x, 1.32, 1.15), 0.15, 0.04, "steel_light", segs=10, axis="Y")
    # Recessed chamber (west), cables (east), a lamp panel at the back.
    p.slab(-0.85, -1.4, 0.75, -0.3, -0.5, 0.78, "soot")
    for k in range(9):
        x = 0.9 + k * 0.055
        bent(p, [(x, -1.5, 0.9), (x + 0.03 * math.sin(k), -0.9, 1.05), (x - 0.02, -0.3, 1.0), (x, 0.0, 0.85)], 0.025,
             "hazard", segs=5, smooth=3)
    p.slab(0.62, -1.2, 0.75, 0.82, -0.6, 1.55, G, bevel=0.05)
    p.slab(0.65, -1.22, 1.0, 0.79, -1.2, 1.4, "glow_cyan")
    p.slab(-0.35, -1.58, 0.9, 0.35, -1.45, 1.25, "glow_cyan")
    p.cyl((0.0, -1.0, 1.4), 0.12, 0.06, "brass", segs=10, axis="Y")

    # The gun: turntable, breech, rail barrel with glowing coils, pipes.
    p.cyl((0, -0.1, 0.85), 0.8, 0.2, GD, segs=20, bevel=0.03)
    head = Part("anim_turret_head", pivot=(0.0, -0.1, 0.85))
    head.slab(-0.55, -1.35, 0.9, 0.55, 0.15, 1.85, G, bevel=0.1)
    head.slab(-0.42, -1.5, 1.0, 0.42, -1.3, 1.65, GD, bevel=0.04)
    head.prism([(-0.5, 0.15), (0.5, 0.15), (0.38, 0.85), (-0.38, 0.85)], 1.25, 2.05, G, bevel=0.04)
    head.slab(-0.24, 0.6, 1.55, 0.24, 3.05, 2.05, G, bevel=0.04)             # rail barrel
    head.slab(-0.05, 1.3, 2.04, 0.05, 2.7, 2.07, "soot")
    for k in range(6):
        y = 1.35 + k * 0.22
        for sx in (-1, 1):
            head.slab(sx * 0.24, y, 1.65, sx * 0.3, y + 0.1, 1.95, "glow_orange")
    head.slab(-0.27, 2.75, 1.5, 0.27, 3.1, 2.1, G, bevel=0.04)
    # Its ammo lights (resource_indicator_animation): a short row of cyan LEDs on the breech's
    # east shoulder, lit as far as the magazine is full (drawn full).
    for k in range(5):
        y = -0.95 + k * 0.14
        head.slab(0.5, y, 1.62, 0.57, y + 0.09, 1.7, "glow_cyan")
    for sx in (-1, 1):
        bent(head, [(sx * 0.5, 0.0, 1.5), (sx * 0.62, 0.6, 1.75), (sx * 0.4, 1.1, 1.85), (sx * 0.28, 1.3, 1.8)], 0.06, "steel_dark", segs=6)
        bent(head, [(sx * 0.6, -0.8, 1.1), (sx * 0.75, -0.2, 1.25), (sx * 0.62, 0.4, 1.4)], 0.05, "steel_dark", segs=6)
    hose(p, [(-0.75, -1.55, 0.6), (-0.65, -1.1, 1.0), (-0.45, -0.6, 1.2)], 0.09, "steel_violet", rib=0.07)
    return [p, head]


# ---------------------------------------------------------------------------------------------
# Aquilo resources: lithium brine and fluorine vents (variation 0 of their sheets). Their
# selection box is one tile, the picture about three across.

def _rock_ring(p, radius, count, size, height, mat, seed, jitter=0.12, tilt=0.35):
    """Rocks round a ring, leaning outward a little, like the rim of a crater."""
    from kit import rng
    rnd = rng(seed)
    for i in range(count):
        a = 2 * math.pi * (i + rnd.uniform(-0.3, 0.3)) / count
        r = radius * (1 + rnd.uniform(-jitter, jitter))
        s = size * rnd.uniform(0.75, 1.25)
        h = height * rnd.uniform(0.7, 1.3)
        x, y = r * math.cos(a), r * math.sin(a)
        m = T(x, y, 0) @ R("Z", math.degrees(a)) @ R("Y", -math.degrees(tilt) * rnd.uniform(0.3, 1.0))
        rock(p, (0, 0, 0.0), (s, s * rnd.uniform(0.7, 1.0), h), mat, seed=seed * 100 + i, matrix=m)


import kit  # noqa: E402
import bmesh  # noqa: E402


def _screen_plate(p, outline, z, mat):
    """A flat-topped slab `z` high whose outline, seen from Factorio's camera, is `outline`
    ((x, screen-up) in tiles, measured from the sprite). Its front walls lean back along the
    camera's line of sight, so they hide behind the top instead of hanging below it."""
    area = sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(outline, outline[1:] + outline[:1]))
    pts = list(outline) if area > 0 else list(reversed(outline))
    n = len(pts)
    shear = z * COS_P / SIN_P
    bm = bmesh.new()
    top, bottom = [], []
    for i, (x, u) in enumerate(pts):
        a, b = pts[i - 1], pts[(i + 1) % n]
        ny = -(b[0] - a[0])  # outward normal's y for a counter-clockwise outline
        y = (u - COS_P * z) / SIN_P
        top.append(bm.verts.new((x, y, z)))
        bottom.append(bm.verts.new((x, y + (shear if ny < 0 else 0.0), 0.0)))
    faces = [bm.faces.new(top)]
    for i in range(n):
        j = (i + 1) % n
        faces.append(bm.faces.new((bottom[i], bottom[j], top[j], top[i])))
    bm.normal_update()  # ear clipping projects on the face normal: without it, notches fill in
    bmesh.ops.triangulate(bm, faces=[faces[0]], ngon_method="EAR_CLIP")
    bm.normal_update()
    p.merge(bm, mat)
    bm.free()
    return p


def _screen_mound(p, cols, depth, mat, seed=0, ridge=0.45, jag=0.06, rows=(6, 4), lumps=0):
    """A craggy lump standing on the ground whose outline from Factorio's camera is `cols`
    ((x, screen-up of its foot, screen-up of its top) per column, measured from the sprite).
    Each column is a ridge: its front slope rises from the foot on the ground to the ridge, `ridge`
    of the way back, whose height puts it at the top; the back slope falls `depth` tiles behind the
    foot (less where that would show over the top). Facets are jittered inside the outline."""
    rnd = kit.rng(seed)
    nf, nb = rows
    bm = bmesh.new()
    grid = []
    for i, (x, ub, ut) in enumerate(cols):
        yf = ub / SIN_P
        yb = min(yf + depth, ut / SIN_P - 0.02)
        yb = max(yb, yf + 0.05)
        yr = yf + ridge * (yb - yf)
        zr = max(0.0, (ut - SIN_P * yr) / COS_P)
        col = []
        for j in range(nf + nb + 1):
            if j <= nf:
                t = j / nf
                y, z = yf + (yr - yf) * t, zr * t
            else:
                t = (j - nf) / nb
                y, z = yr + (yb - yr) * t, zr * (1 - t)
            inner = 0 < j < nf + nb and j != nf and 0 < i < len(cols) - 1
            if inner:
                k = jag * min(1.0, zr) * 4 * (t * (1 - t))
                z = max(0.0, z + rnd.uniform(-k, k))
                if j > nf:  # the back slope must stay under the ridge's line of sight
                    z = min(z, (ut - SIN_P * y) / COS_P - 0.01)
                x_ = x + rnd.uniform(-0.3, 0.3) * (cols[1][0] - cols[0][0])
            else:
                x_ = x
            col.append(bm.verts.new((x_, y, z)))
        grid.append(col)
    m = nf + nb
    for i in range(len(grid) - 1):
        for j in range(m):
            bm.faces.new((grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]))
    bm.faces.new(list(reversed(grid[0])))
    bm.faces.new(grid[-1])
    bm.faces.new([c[m] for c in grid] + [c[0] for c in reversed(grid)])
    bm.normal_update()
    bmesh.ops.triangulate(bm, faces=list(bm.faces), ngon_method="EAR_CLIP")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    p.merge(bm, mat)
    bm.free()
    # Crags: lumps of ice bulging out of the front slope, each small enough to stay inside the
    # outline (a lump only covers its own patch of screen).
    xs = [c[0] for c in cols]
    for k in range(lumps):
        i = rnd.randint(2, len(cols) - 3)
        x, ub, ut = cols[i]
        t = rnd.uniform(0.25, 0.75)
        uc = ub + (ut - ub) * t * 0.8
        margin = min(x - xs[0], xs[-1] - x)
        for x2, ub2, ut2 in cols:
            if abs(x2 - x) < 0.6:
                margin = min(margin, math.hypot(x2 - x, max(0.0, min(uc - ub2, ut2 - uc))) if ub2 < uc < ut2
                             else abs(x2 - x))
        s = min(0.5, margin / 1.35)
        if s < 0.08:
            continue
        # The front slope's point under (x, uc): on the line from the foot to the ridge.
        yf = ub / SIN_P
        yb = max(min(yf + depth, ut / SIN_P - 0.02), yf + 0.05)
        yr = yf + ridge * (yb - yf)
        zr = max(0.0, (ut - SIN_P * yr) / COS_P)
        f = (uc - ub) / max(1e-3, ut - ub)
        y, z = yf + (yr - yf) * f, zr * f
        rock(p, (x, y, z), (s, s * 0.6, s * 0.8), mat, seed=seed * 50 + k, flat_bottom=False, jag=0.25)
    return p


def _screen_blade(p, cols, y, thick, mat, segs=6):
    """A blade of ice whose outline from Factorio's camera is `cols` ((x, screen-up of its
    lower edge, of its upper edge) per column): each column's cross-section is an ellipse whose
    long axis is the screen's up, `thick` deep along the line of sight, centred `y` north."""
    bm = bmesh.new()
    rings = []
    eu, ev = (SIN_P, COS_P), (COS_P, -SIN_P)
    for x, lo, hi in cols:
        uc, h = (lo + hi) / 2, (hi - lo) / 2
        zc = (uc - SIN_P * y) / COS_P
        ring = []
        for k in range(segs):
            a = 2 * math.pi * k / segs
            du, dv = h * math.cos(a), thick * math.sin(a)
            ring.append(bm.verts.new((x, y + du * eu[0] + dv * ev[0], zc + du * eu[1] + dv * ev[1])))
        rings.append(ring)
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(segs):
            bm.faces.new((r0[k], r0[(k + 1) % segs], r1[(k + 1) % segs], r1[k]))
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[-1])))
    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    p.merge(bm, mat)
    bm.free()
    return p


def _area(poly):
    return sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(poly, poly[1:] + poly[:1])) / 2


def _with_hole(outer, hole):
    """One outline that runs round `outer` and, through a slit from its nearest point, round
    `hole` the other way: a plate with a hole in it for _screen_plate."""
    if (_area(outer) > 0) == (_area(hole) > 0):
        hole = list(reversed(hole))
    i, j = min(((i, j) for i in range(len(outer)) for j in range(len(hole))),
               key=lambda ij: math.dist(outer[ij[0]], hole[ij[1]]))
    # Nudge the way back so no two corners share a point.
    ring = hole[j:] + hole[:j] + [(hole[j][0] + 0.003, hole[j][1])]
    back = (outer[i][0] + 0.003, outer[i][1])
    return outer[:i + 1] + ring + [back] + outer[i + 1:]


kit.MATERIALS.update({
    # The brine pool: a still green liquid, not a light (glow_green lit it neon).
    "glass_brine": ("6f8f50", 0.25, 0.0, None, 0),
})


# The brine's outline from Factorio's camera, (x, screen-up) in tiles, traced from variation 0.
_BRINE_OUTLINE = [(-0.49, -0.59), (-0.44, -0.46), (-0.55, -0.36), (-0.73, -0.48), (-0.64, -0.29), (-0.78, 0.01), (-0.73, 0.10),
                  (-0.77, 0.23), (-0.51, 0.44), (-0.21, 0.50), (0.21, 0.48), (0.72, 0.29), (0.73, 0.13), (0.81, 0.05),
                  (0.77, 0.01), (0.80, -0.13), (0.94, -0.29), (0.85, -0.36), (0.77, -0.28), (0.68, -0.30), (0.64, -0.43),
                  (0.49, -0.55), (0.34, -0.45), (0.05, -0.52), (-0.15, -0.42)]


@model("lithium-brine")
def lithium_brine():
    """Factorio's lithium brine: a low rim of pale, snow-dusted ice boulders round a green pool
    that sits towards the back, the rim thickest at the front, blue ice shards splintering off
    its south-east."""
    p = Part()
    _screen_plate(p, _BRINE_OUTLINE, 0.08, "ice")
    # The pool, sunk a little into the rim.
    px, py = 0.08, 0.2
    p.cyl((px, py, 0.085), 0.3, 0.02, "glass_brine", segs=18)
    lathe(p, (px, py, 0.0), [(0.3, 0.08), (0.36, 0.12), (0.42, 0.09)], "ice", segs=18)
    # Boulders on the rim: big ones at the front (they show against the rim's face), low ones at
    # the back so they don't rise past its outline.
    for i, (x, y, s, h) in enumerate(((-0.45, -0.25, 0.22, 0.2), (-0.15, -0.35, 0.24, 0.24), (0.2, -0.3, 0.2, 0.2),
                                      (0.5, -0.15, 0.18, 0.16), (-0.55, 0.1, 0.16, 0.14), (0.5, 0.25, 0.12, 0.07),
                                      (-0.35, 0.4, 0.14, 0.07), (0.25, 0.48, 0.12, 0.05), (-0.1, 0.52, 0.12, 0.05),
                                      (-0.2, 0.0, 0.12, 0.1), (0.38, 0.05, 0.1, 0.08))):
        rock(p, (x, y, 0.06), (s, s * 0.8, h), "ice" if i % 3 else "ice_blue", seed=70 + i)
    for i, (x, y) in enumerate(((0.75, -0.35), (0.62, -0.5), (0.85, -0.25))):
        rock(p, (x, y, 0.0), (0.09, 0.05, 0.05), "ice_shadow", seed=90 + i, jag=0.3)
    return p


# The vent's outline from Factorio's camera, (x, screen-up) in tiles, traced from variation 0.
_VENT_OUTLINE = [(0.23, -0.61), (0.12, -0.59), (-0.13, -0.44), (-0.27, -0.42), (-0.38, -0.47), (-0.60, -0.25), (-0.66, -0.31),
                 (-0.76, -0.25), (-0.85, -0.36), (-0.92, -0.24), (-0.78, -0.09), (-0.77, 0.02), (-0.91, 0.14), (-1.09, 0.12),
                 (-0.95, 0.21), (-0.93, 0.33), (-0.82, 0.25), (-0.73, 0.41), (-0.41, 0.56), (-0.34, 0.63), (-0.35, 0.78),
                 (-0.23, 0.72), (0.15, 0.73), (0.21, 0.64), (0.45, 0.64), (0.62, 0.74), (0.63, 0.84), (0.70, 0.79),
                 (0.72, 0.65), (0.59, 0.66), (0.31, 0.51), (0.53, 0.37), (0.70, 0.12), (0.79, 0.14), (0.88, 0.30),
                 (0.98, 0.25), (1.10, 0.33), (1.11, 0.27), (0.70, 0.05), (0.66, 0.01), (0.66, -0.21)]
# The gap between the pit's lip and the tipped-up plates behind it.
_VENT_GAP = [(-0.09, 0.51), (0.12, 0.52), (0.17, 0.57), (0.14, 0.65), (0.09, 0.70), (-0.13, 0.67), (-0.19, 0.55)]


@model("fluorine-vent")
def fluorine_vent():
    """Factorio's fluorine vent: a pit in the ice lined with slabs of blue-grey rock and dark
    cracks, ringed by a lip of white frost, broken grey plates of ice tipped up round its back
    and splinters reaching out east and west."""
    p = Part()
    _screen_plate(p, _with_hole(_VENT_OUTLINE, _VENT_GAP), 0.04, "ice")
    # The pit: blue-grey slabs round a dark crack, inside the frost lip.
    cx, cy = -0.02, -0.02
    p.cyl((cx, cy, 0.045), 0.48, 0.01, "ice_blue", segs=20)
    lathe(p, (cx, cy, 0.0), [(0.46, 0.04), (0.5, 0.08), (0.58, 0.07), (0.62, 0.04)], "ice", segs=20)
    # Broken slabs filling the pit, separated by dark cracks (the sprite's pit is a jumble of
    # flat blue plates, the darkest crack running across its middle).
    for poly, z in (([(-0.45, -0.05), (-0.1, 0.02), (-0.05, 0.38), (-0.32, 0.3)], 0.07),
                    ([(-0.02, 0.06), (0.4, 0.1), (0.3, 0.38), (0.02, 0.36)], 0.06),
                    ([(-0.3, -0.38), (-0.05, -0.42), (-0.08, -0.06), (-0.42, -0.12)], 0.065),
                    ([(0.1, -0.42), (0.38, -0.3), (0.42, 0.02), (0.0, -0.08)], 0.075)):
        p.prism(poly, 0.04, z, "ice_shadow", bevel=0.01)
    p.prism([(-0.1, -0.11), (-0.09, -0.36), (-0.06, -0.38), (-0.02, -0.1), (0.32, -0.06), (0.3, -0.03), (-0.4, -0.1)],
            0.04, 0.052, "soot")
    # Splintered plates round the outside of the lip.
    for i, (x, y, s, h) in enumerate(((-0.62, 0.05, 0.12, 0.05), (0.6, -0.1, 0.12, 0.05), (-0.45, -0.45, 0.1, 0.04),
                                      (0.35, 0.55, 0.12, 0.03), (-0.5, 0.45, 0.12, 0.03))):
        rock(p, (x, y, 0.03), (s, s * 0.8, h), "ice_blue", seed=120 + i, jag=0.25)
    return p


# ---------------------------------------------------------------------------------------------
# Lithium icebergs (simple entities; picture 1 of big, 2 of huge).

def _peak(p, base, size, peak, mat, seed, segs=10, rings=7, jag=0.12):
    """A craggy ice lump `size` across whose top is drawn over towards `peak` (x, y, z): the
    higher a vertex, the further it leans to the peak."""
    q = Part()
    rock(q, (0, 0, 0), size, mat, seed=seed, segs=segs, rings=rings, jag=jag)
    px_, py_, pz = peak
    sz = size[2]

    def lean(co):
        t = max(0.0, co.z) / sz
        k = t ** 1.6
        return (co.x + (px_ - base[0] - co.x * 0.7) * k, co.y + (py_ - base[1] - co.y * 0.7) * k,
                co.z + (pz - sz) * t ** 2)
    q.warp(lean)
    p.add_part(q, T(*base))


# The icebergs' outlines from Factorio's camera, per column: (x, screen-up of the foot, of the
# top) in tiles, from picture 1 of the big one's sprite and picture 2 of the huge one's.
_BERG_BIG = [(-0.869, 0.031, 0.141), (-0.815, -0.062, 0.406), (-0.761, -0.188, 0.484), (-0.707, -0.328, 0.656),
             (-0.653, -0.359, 1.047), (-0.599, -0.422, 1.25), (-0.545, -0.5, 1.281), (-0.491, -0.562, 1.297),
             (-0.437, -0.609, 1.297), (-0.383, -0.688, 1.281), (-0.329, -0.688, 1.25), (-0.275, -0.688, 1.156),
             (-0.221, -0.672, 1.094), (-0.167, -0.656, 1.031), (-0.112, -0.672, 0.953), (-0.058, -0.688, 0.906),
             (-0.004, -0.688, 0.859), (0.05, -0.688, 0.891), (0.104, -0.688, 0.891), (0.158, -0.672, 0.891),
             (0.212, -0.656, 0.875), (0.266, -0.625, 0.875), (0.32, -0.578, 0.859), (0.374, -0.562, 0.812),
             (0.428, -0.562, 0.734), (0.482, -0.562, 0.703), (0.536, -0.547, 0.672), (0.59, -0.531, 0.641),
             (0.644, -0.516, 0.625), (0.698, -0.5, 0.594), (0.752, -0.484, 0.547), (0.806, -0.422, 0.5),
             (0.86, -0.375, 0.453), (0.914, -0.344, 0.422), (0.968, -0.312, 0.375), (1.022, -0.234, -0.078)]
# The huge one's body; west of x = 0 its fin curls over a gap, so the fin is listed on its own.
_BERG_HUGE = [(-1.803, -0.219, 0.016), (-1.695, -0.281, 0.156), (-1.587, -0.328, 0.266), (-1.479, -0.562, 0.406),
              (-1.371, -0.641, 0.453), (-1.264, -0.75, 0.422), (-1.156, -0.828, 0.344), (-1.048, -0.938, 0.359),
              (-0.94, -1.047, 0.484), (-0.832, -1.172, 0.641), (-0.724, -1.219, 1.016), (-0.616, -1.219, 0.938),
              (-0.508, -1.234, 0.859), (-0.4, -1.266, 0.719), (-0.292, -1.312, 0.734), (-0.184, -1.297, 0.844),
              (-0.076, -1.312, 1.125), (0.032, -1.328, 2.719), (0.139, -1.344, 2.641), (0.247, -1.359, 2.594),
              (0.355, -1.312, 2.531), (0.463, -1.297, 2.453), (0.571, -1.266, 2.359), (0.679, -1.219, 2.281),
              (0.787, -1.156, 2.172), (0.895, -1.141, 2.078), (1.003, -1.078, 1.953), (1.111, -1.031, 1.859),
              (1.219, -1.016, 1.797), (1.327, -1.016, 1.75), (1.435, -1.047, 1.516), (1.542, -1.062, 1.266),
              (1.65, -1.109, 1.141), (1.758, -1.125, 0.969), (1.866, -1.109, 0.75), (1.974, -1.109, 0.656),
              (2.082, -1.125, 0.578), (2.19, -1.125, 0.469), (2.298, -1.094, 0.359), (2.406, -1.078, 0.188),
              (2.514, -1.031, 0.078), (2.622, -0.938, 0), (2.73, -0.891, -0.109), (2.838, -0.672, -0.406)]
_BERG_HUGE_FIN = [(-0.98, 2.9, 3.04), (-0.94, 2.8, 3.05), (-0.85, 2.72, 3.02), (-0.75, 2.67, 2.98), (-0.65, 2.55, 2.97),
                  (-0.56, 2.38, 2.95), (-0.46, 2.2, 2.97), (-0.36, 2.02, 3.0), (-0.27, 1.77, 2.89), (-0.17, 1.5, 2.8),
                  (-0.07, 1.17, 2.77), (0.05, 1.0, 2.7)]


@model("lithium-iceberg-big")
def lithium_iceberg_big():
    """A big lithium iceberg: a craggy blue-white ice lump rising to a blunt peak on its west
    side and sloping away east, its facets catching pale light."""
    p = Part()
    _screen_mound(p, _BERG_BIG, 1.35, "ice_blue", seed=31, jag=0.15, rows=(8, 5), lumps=12)
    return p


@model("lithium-iceberg-huge")
def lithium_iceberg_huge():
    """A huge lithium iceberg: a broad craggy mound of ice with a great fin rising from its
    middle and curling over to a point above its west end, and a small spike in front of the
    curl."""
    p = Part()
    _screen_mound(p, _BERG_HUGE, 3.0, "ice_blue", seed=41, jag=0.25, ridge=0.4, rows=(8, 5), lumps=24)
    # The fin's ridge, where it leaves the mound, lies 0.4 of the way back from the foot.
    y = (-1.33 / SIN_P) + 0.4 * 2.9
    _screen_blade(p, _BERG_HUGE_FIN, y, 0.3, "ice_blue", segs=8)
    return p
