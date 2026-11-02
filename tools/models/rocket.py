"""Rockets and odds and ends: rocket silo, its rocket, cargo pod, cargo landing pad, market,
loader.

Each model is matched to Factorio's HR sprite with compare.py (client/assets/models/README.md,
"Matching a sprite").
"""

import math

import bmesh

from mathutils import Vector

import kit
from kit import Part, R, S, T, model
from nuclear import bend, corrugated, fan_ring
import space_kit as sk
import detail

kit.MATERIALS.update({
    "concrete_dark": ("5d5b55", 0.9, 0.05, None, 0),      # the silo's deck
    "paint_olive": ("8d9157", 0.6, 0.35, None, 0),        # yellow-green boxes, the pad's olive block
    "olive_pale": ("a3a27a", 0.6, 0.3, None, 0),          # the pad's pale olive turbine ring
    "paint_rose": ("9a5148", 0.6, 0.3, None, 0),          # the landing pad's red tower
    "paint_market": ("6a8a3a", 0.6, 0.25, None, 0),       # the market's green walls
    "stone_brick": ("8f5a3c", 0.9, 0.0, None, 0),         # the market's roof
    "rocket_white": ("bdb9ab", 0.55, 0.35, None, 0),      # rocket and pod cladding
})


def plate_door(p, pts, z, mat="steel_dark", stripes=6):
    """A flat door: a plate through `pts` with a band of hazard stripes along its first edge."""
    p.prism(pts, z - 0.06, z, mat, bevel=0.02)
    a, b = Vector((*pts[0], 0)), Vector((*pts[1], 0))
    inward = (Vector((*pts[-1], 0)) - a).normalized() * 0.3
    for k in range(stripes):
        q0 = a + (b - a) * (k / stripes)
        q1 = a + (b - a) * ((k + 1) / stripes)
        p.prism([(q0.x, q0.y), (q1.x, q1.y), (q1.x + inward.x, q1.y + inward.y), (q0.x + inward.x, q0.y + inward.y)],
                 z, z + 0.012, "hazard" if k % 2 == 0 else "hazard_black")


# ---------------------------------------------------------------------------------------------
# Rocket silo.

def deck_plate(p, outline, hole, radius, z0, z1, mat, segs=48):
    """A slab with the outline `outline` (counter-clockwise) and a round hole through it."""
    bm = bmesh.new()
    cx, cy = hole
    outer = [bm.verts.new((x, y, z1)) for x, y in outline]
    inner = [bm.verts.new((cx + radius * math.cos(2 * math.pi * k / segs),
                           cy + radius * math.sin(2 * math.pi * k / segs), z1)) for k in range(segs)]
    edges = [bm.edges.new((loop[i], loop[(i + 1) % len(loop)])) for loop in (outer, inner) for i in range(len(loop))]
    bmesh.ops.triangle_fill(bm, use_beauty=True, use_dissolve=False, edges=edges)
    # triangle_fill fills the hole too.
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if (f.calc_center_median().x - cx) ** 2 +
                               (f.calc_center_median().y - cy) ** 2 < radius ** 2], context="FACES_ONLY")
    for f in bm.faces:
        if f.normal.z < 0:
            f.normal_flip()
    bottom = [bm.verts.new((x, y, z0)) for x, y in outline]
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([bottom[i], bottom[j], outer[j], outer[i]])
    p.merge(bm, mat)
    bm.free()
    return p


@model("rocket-silo")
def rocket_silo():
    """Factorio's rocket silo, 9x9, at true proportions (its sprite fits stretched, as Wube's
    models): a dark riveted deck whose top slopes like a funnel into the great shaft north of
    centre, its two hazard-striped doors closed deep inside (Factorio opens them only to raise
    the rocket). The deck's north-west corner is cut back in a long slant with a sunken hatch
    behind it; machinery crowds the rest: fat corrugated copper hoses, a turbine and the blue
    control box in the north-east, a bundle of pipes down the west side, a jet engine and a
    yellow-green box in the south-west, a second green box and the small exhaust hole in the
    south-east, pipe runs round the east and south edges.

    Moving parts: the doors (anim_door_silo_e, anim_door_silo_w) slide apart while a rocket
    stands in the silo, as Factorio's do (door_back_open_offset: 1.8 across and a little north,
    at door_opening_speed 1/255 a tick, 4.25 s), sinking under the shaft's floor as they go
    since the deck is too narrow to take them whole; while it works the drum in the
    south-east hole (anim_lift_silo) rises and sinks once per loop of the crafting sheet (64
    frames at 0.65, 1.64 s) and the jet engine's intake fan (anim_fan_silo) turns."""
    p = Part()
    top, hy = 0.55, 0.2
    outline = [(-3.6, -4.35), (3.75, -4.35), (4.4, -3.7), (4.4, 3.4), (3.9, 3.9), (-0.9, 3.9),
               (-4.2, 2.9), (-4.2, -3.75)]
    deck_plate(p, outline, (0, hy), 3.95, 0.0, top, "concrete_dark", segs=40)
    p.cyl((0, hy, 0.03), 2.7, 0.06, "soot", segs=40)
    # The great ring round the shaft, highest at its lip, and the shaft's wall down to the doors.
    sk.lathe(p, (0, hy, 0), [(3.97, top - 0.02), (3.7, 1.15), (3.4, 1.42), (3.1, 1.38), (2.8, 0.75), (2.65, 0.08)],
             "concrete_dark", segs=40)
    # The doors, closed, low in the shaft: striped plates under a grid of beams, one moving part
    # each (the seam's beam goes with the east door).
    doors = []
    for sx in (-1, 1):
        door = Part("anim_door_silo_e" if sx > 0 else "anim_door_silo_w", pivot=(sx * 1.35, hy, 0.12))
        doors.append(door)
        start = -90 if sx > 0 else 90
        pts = [(2.7 * math.cos(math.radians(start + 180 * k / 14)), hy + 2.7 * math.sin(math.radians(start + 180 * k / 14)))
               for k in range(15)]
        door.prism(pts, 0.06, 0.12, "hazard", bevel=0.02)
        u = Vector((math.sqrt(0.5), -math.sqrt(0.5)))
        v = Vector((math.sqrt(0.5), math.sqrt(0.5)))
        for k in range(-11, 12):
            off = k * 0.5
            inside = [t / 20.0 for t in range(-120, 121)
                      if sx * (off * v.x + t / 20.0 * u.x) > 0.06
                      and (off * v.x + t / 20.0 * u.x) ** 2 + (off * v.y + t / 20.0 * u.y) ** 2 < 2.6 ** 2]
            if len(inside) < 2:
                continue
            t0, t1 = min(inside), max(inside)
            c = v * off + u * ((t0 + t1) / 2)
            door.box((c.x, hy + c.y, 0.125), (0.2, t1 - t0, 0.01), "hazard_black", rz=45)
        for y in (-1.8, -0.9, 0.0, 0.9, 1.8):
            half = math.sqrt(max(0.0, 2.6 ** 2 - y * y))
            door.slab(min(sx * 0.12, sx * half), hy + y - 0.05, 0.12, max(sx * 0.12, sx * half), hy + y + 0.05, 0.22,
                   "steel_dark")
        for x in (0.9, 1.8):
            half = math.sqrt(2.6 ** 2 - x * x)
            door.slab(sx * x - 0.05, hy - half, 0.12, sx * x + 0.05, hy + half, 0.2, "steel_dark")
    doors[1].slab(-0.12, hy - 2.6, 0.12, 0.12, hy + 2.6, 0.26, "steel")
    # Rivets round the funnel's lip and the red lights on it.
    for k in range(32):
        a = math.radians(k * 360 / 32)
        p.bolt((3.42 * math.cos(a), hy + 3.42 * math.sin(a), 1.42), "steel_light", radius=0.035)
    for a in (25, 65, 115, 155, 205, 335):
        r = math.radians(a)
        p.sphere((3.0 * math.cos(r), hy + 3.0 * math.sin(r), 1.2), 0.06, "lamp_red", segs=6, rings=3)
    # The funnel's plating: radial seams down its slope and a second rivet ring at its foot;
    # rusty pipes hug the ring outside it round the west and south (the sprite's pipe bundles),
    # brackets holding them.
    for k in range(12):
        a = math.radians(k * 30 + 15)
        c, s = math.cos(a), math.sin(a)
        p.beam((3.95 * c, hy + 3.95 * s, top + 0.01), (3.45 * c, hy + 3.45 * s, 1.4), 0.04, 0.03, "steel_dark")
    for r_, z_, mat in ((4.02, top + 0.12, "rust"), (4.14, top + 0.1, "steel"), (4.25, top + 0.1, "rust")):
        sk.bent(p, [(r_ * math.cos(math.radians(a)), hy + r_ * math.sin(math.radians(a)), z_) for a in range(150, 301, 15)],
                0.06, mat, segs=6, smooth=2)
    for a in (160, 190, 220, 250, 280):
        r = math.radians(a)
        p.box((4.13 * math.cos(r), hy + 4.13 * math.sin(r), top + 0.12), (0.12, 0.4, 0.1), "steel_dark", rz=a)
    # The doors' seam and frame: a dark rim round the shaft's floor.
    sp_ring = Part()
    sp_ring.ring_band((0, hy), 2.6, 2.75, 0.05, 0.3, 0, 360, "steel_dark", segs=20)
    p.add_part(sp_ring)
    # North-west: the sunken hatch behind the slanted corner, and a machine with red wires.
    p.slab(-3.7, 1.9, top - 0.25, -2.0, 3.1, top + 0.01, "soot")
    p.slab(-3.85, 1.75, top, -1.85, 1.9, top + 0.12, "steel_dark")
    p.slab(-3.85, 3.1, top, -2.3, 3.25, top + 0.12, "steel_dark")
    p.slab(-4.35, 0.6, top, -3.3, 1.7, top + 0.75, "steel_dark", bevel=0.06)
    p.cyl((-3.5, 1.15, top + 0.95), 0.32, 0.4, "rust_brown", segs=12, bevel=0.04)
    p.cyl((-2.6, 1.3, top + 0.35), 0.4, 0.7, "steel", segs=14, axis="X", bevel=0.04)
    for k in range(3):
        sk.bent(p, [(-4.3, 1.6 - 0.1 * k, top + 0.5), (-4.5, 2.4, top + 0.3), (-4.2, 3.1 + 0.08 * k, top + 0.1)],
                0.025, "paint_red", segs=5)
    # North: copper hoses arching over the deck to the turbine.
    corrugated(p, bend((-0.9, 4.0, top), (-0.6, 5.0, 3.0), (0.6, 2.4, top + 0.2), steps=9), 0.3, segs=8, rib=0.16)
    corrugated(p, bend((0.8, 3.0, top), (1.6, 4.3, 2.6), (1.9, 3.3, top + 0.8), steps=7), 0.24, segs=8, rib=0.16)
    # North-east: turbine housing, the blue control box with its round port, pipes.
    p.cyl((2.0, 3.45, top + 0.6), 0.65, 1.2, "steel", segs=16, axis="X", bevel=0.05)
    p.cyl((2.0, 3.45, top + 1.15), 0.5, 0.4, "steel_dark", segs=14, bevel=0.03)
    p.cyl((2.75, 3.45, top + 0.6), 0.45, 0.25, "rust_brown", segs=14, axis="X", bevel=0.03)
    p.slab(3.1, 2.85, top, 4.35, 4.1, top + 1.3, "paint_blue", bevel=0.06)
    p.cyl((3.72, 3.47, top + 1.31), 0.32, 0.02, "soot", segs=16)
    p.slab(3.3, 2.83, top + 0.3, 4.15, 2.87, top + 1.0, "soot")
    p.cyl((3.1, 2.2, top + 0.45), 0.22, 0.5, "steel_light", segs=10, axis="Y")
    p.pipe([(4.2, 2.8, top + 0.25), (4.2, -2.2, top + 0.25), (3.95, -2.7, top + 0.25)], 0.11, "steel", segs=8)
    p.pipe([(3.95, 2.8, top + 0.45), (3.95, 0.4, top + 0.45), (3.5, 0.0, top + 0.2)], 0.09, "copper_dull", segs=8)
    p.slab(2.9, -0.4, top, 3.9, 0.9, top + 0.7, "steel_dark", bevel=0.05)
    # West: a bundle of pipes down the edge, bending in to the south-west machinery.
    for k in range(4):
        x = -4.25 + 0.17 * k
        p.pipe([(x, 0.4, top + 0.12), (x, -1.9 - 0.1 * k, top + 0.12), (x + 0.6, -2.6 - 0.1 * k, top + 0.12)],
               0.075, "steel_light" if k % 2 else "steel", segs=6)
    # South-west: the jet engine lying east-west, its intake facing west, and the yellow-green box.
    p.cyl((-2.65, -3.25, top + 0.55), 0.78, 1.5, "steel", segs=20, axis="X", bevel=0.06)
    p.cyl((-3.45, -3.25, top + 0.55), 0.7, 0.12, "steel_dark", segs=20, axis="X")
    # Its intake fan turns while the silo works (the sheet Factorio calls satellite_animation,
    # 32 frames at 0.4): a hub and eight blades on the intake's face.
    fan = Part("anim_fan_silo", pivot=(-3.5, -3.25, top + 0.55))
    fan.cyl((-3.5, -3.25, top + 0.55), 0.25, 0.14, "steel_light", segs=10, axis="X")
    for k in range(8):
        a = 2 * math.pi * k / 8
        fan.beam((-3.53, -3.25 + 0.2 * math.cos(a), top + 0.55 + 0.2 * math.sin(a)),
                 (-3.53, -3.25 + 0.62 * math.cos(a), top + 0.55 + 0.62 * math.sin(a)), 0.16, 0.02, "steel",
                 up=(1.0, -0.5 * math.sin(a), 0.5 * math.cos(a)))
    p.cyl((-1.75, -3.25, top + 0.55), 0.55, 0.4, "rust_brown", segs=16, axis="X", bevel=0.04)
    p.slab(-1.5, -3.95, top, -0.3, -2.65, top + 1.05, "paint_olive", bevel=0.06)
    p.slab(-0.25, -4.05, top, 0.6, -3.5, top + 0.45, "steel_dark", bevel=0.04)
    # South: hoses from the shaft's rim to the boxes, the exhaust hole, a pipe along the edge.
    corrugated(p, bend((-0.6, -2.6, top + 0.9), (0.2, -1.4, 2.6), (0.7, -2.5, top), steps=8), 0.25, segs=8, rib=0.16)
    corrugated(p, bend((1.2, -2.0, top), (1.9, -0.9, 2.4), (2.6, -2.4, top + 1.0), steps=8), 0.25, segs=8, rib=0.16)
    sk.lathe(p, (1.3, -3.2, 0), [(0.85, top + 0.02), (0.75, top - 0.3), (0.7, 0.35)], "steel_dark", segs=20)
    p.cyl((1.3, -3.2, 0.36), 0.7, 0.02, "soot", segs=20)
    # In the hole, the drum that rises and sinks while rocket parts are made (Factorio's crafting
    # sheet): dark, riveted, a pale rim round its top; most of it hidden below the deck at rest.
    lift = Part("anim_lift_silo", pivot=(1.3, -3.2, 0.45))
    lift.cyl((1.3, -3.2, -0.03), 0.62, 0.96, "steel_dark", segs=20)
    lift.ring_band((1.3, -3.2), 0.5, 0.64, 0.38, 0.47, 0, 360, "steel_light", segs=20, bevel=0.02)
    lift.cyl((1.3, -3.2, 0.4), 0.5, 0.03, "soot", segs=20)
    for z in (0.05, 0.25):
        lift.cyl((1.3, -3.2, z), 0.64, 0.05, "steel", segs=20)
    p.pipe([(-0.4, -4.1, top + 0.1), (3.3, -4.1, top + 0.1), (4.2, -3.2, top + 0.1)], 0.08, "steel", segs=6)
    # South-east: the second green box with its vents.
    p.slab(2.75, -3.75, top, 4.25, -2.3, top + 1.15, "paint_olive", bevel=0.06)
    for k in range(4):
        p.slab(2.9, -3.77, top + 0.25 + 0.2 * k, 4.1, -3.74, top + 0.33 + 0.2 * k, "soot")
    return [p, lift, fan] + doors


@model("rocket-silo-rocket")
def rocket_silo_rocket():
    """Factorio's rocket, standing (about 18.6 tiles tall, its sprite's height over the camera's
    foreshortening): a cluster of engine bells round a round base, a band of plumbing, the
    widest part, a girder cage with green panels and boxes strapped to its sides, four riveted
    fuel tanks above it whose domed tops close in round the core, and the slim capsule on top
    with its yellow panels and the round ball at its tip. Red cables run down the side."""
    p = Part()
    # Engines and base.
    for k in range(6):
        a = math.radians(k * 60 + 30)
        p.cyl((0.8 * math.cos(a), 0.8 * math.sin(a), 1.1), 0.34, 0.6, "steel_dark", segs=12, radius_top=0.22)
    p.cyl((0, 0, 0.6), 0.62, 1.2, "rust_brown", segs=18, radius_top=0.9)
    # Plumbing band: a drum under a tangle of pipes.
    p.cyl((0, 0, 1.45), 1.05, 0.9, "steel_dark", segs=20, radius_top=1.3)
    p.cyl((0, 0, 2.1), 1.5, 0.5, "steel_dark", segs=24, bevel=0.08)
    p.cyl((0, 0, 3.05), 1.62, 1.6, "rust_brown", segs=24, bevel=0.06)
    for k in range(10):
        a = math.radians(k * 36 + 10)
        c, s = math.cos(a), math.sin(a)
        sk.bent(p, [(1.45 * c, 1.45 * s, 0.9), (1.7 * c, 1.7 * s, 1.8 + 0.2 * (k % 3)), (1.6 * c, 1.6 * s, 3.4)],
                0.07, "steel" if k % 2 else "steel_light", segs=6)
    for z in (2.3, 3.85):
        p.ring_band((0, 0), 1.6, 1.72, z - 0.06, z + 0.06, 0, 360, "rust_brown", segs=24)
    # The cage: an octagon of girders with green panels, boxes strapped on.
    p.cyl((0, 0, 5.6), 1.75, 3.3, "steel", segs=24)
    for k in range(8):
        a = math.radians(k * 45 + 22.5)
        c, s = math.cos(a), math.sin(a)
        p.box((1.8 * c, 1.8 * s, 5.6), (0.06, 1.25, 2.9), "paint_green", rz=k * 45 + 22.5)
        # Louvres across the green panels, as the sprite's cage shows them.
        for j in range(7):
            p.box((1.83 * c, 1.83 * s, 4.45 + 0.38 * j), (0.03, 1.1, 0.07), "steel_dark", rz=k * 45 + 22.5)
        p.beam((1.98 * c, 1.98 * s, 3.95), (1.98 * c, 1.98 * s, 7.3), 0.12, 0.12, "rust_brown")
        b = math.radians(k * 45 + 45)
        p.beam((1.98 * c, 1.98 * s, 4.0), (1.98 * math.cos(b), 1.98 * math.sin(b), 7.25), 0.06, 0.06, "rust_brown")
    for z in (4.0, 5.6, 7.25):
        p.ring_band((0, 0), 1.85, 2.05, z - 0.09, z + 0.09, 0, 360, "rust_brown", segs=24)
    p.slab(-2.35, -0.35, 5.0, -1.95, 0.45, 6.3, "steel_dark", bevel=0.04)
    p.slab(1.95, -0.6, 4.5, 2.35, 0.2, 5.6, "rust_brown", bevel=0.04)
    p.slab(1.0, -2.25, 2.6, 1.9, -1.75, 3.4, "steel_dark", bevel=0.04)
    # Four fuel tanks with domed tops round the core.
    p.cyl((0, 0, 9.5), 0.8, 4.4, "steel", segs=16)
    for x, y in ((0.78, 0.78), (-0.78, 0.78), (0.78, -0.78), (-0.78, -0.78)):
        p.cyl((x, y, 9.15), 0.97, 3.7, "rocket_white", segs=16, bevel=0.06)
        p.sphere((x, y, 11.0), 0.97, "rocket_white", segs=16, rings=6, hemisphere=True, scale=(1, 1, 1.5))
        # Rivet rows up the tank's outer side and round its seams.
        out_ = math.atan2(y, x)
        for da in (-0.5, 0.5):
            a = out_ + da
            detail.rivet_line(p, (x + 0.98 * math.cos(a), y + 0.98 * math.sin(a), 7.5),
                              (x + 0.98 * math.cos(a), y + 0.98 * math.sin(a), 10.8), 9, "X", r=0.03)
        for z in (7.9, 9.15, 10.4):
            p.cyl((x, y, z), 0.94, 0.07, "steel_dark", segs=16)
        out = math.atan2(y, x)
        for k in range(5):
            h = 0.15 + 0.25 * k
            r = 0.93 * math.sqrt(max(0.0, 1 - (h / (0.92 * 1.55)) ** 2))
            p.sphere((x + r * math.cos(out), y + r * math.sin(out), 11.0 + h), 0.045, "steel_light", segs=6, rings=3)
    for k in range(4):
        a = math.radians(k * 90)
        p.beam((1.75 * math.cos(a), 1.75 * math.sin(a), 7.3), (1.1 * math.cos(a), 1.1 * math.sin(a), 11.5), 0.08, 0.08,
               "rust_brown")
    # Capsule and its ball.
    p.cyl((0, 0, 12.6), 0.95, 2.2, "steel", segs=18, radius_top=0.8, bevel=0.04)
    p.cyl((0, 0, 14.6), 0.8, 1.8, "rocket_white", segs=18, radius_top=0.55, bevel=0.04)
    p.slab(0.25, -0.95, 12.6, 0.85, -0.6, 14.0, "paint_olive", bevel=0.03)
    p.slab(-0.75, -0.9, 13.0, -0.2, -0.6, 14.4, "hazard", bevel=0.03)
    p.slab(-0.25, -0.7, 14.4, 0.25, -0.5, 15.3, "steel_dark", bevel=0.03)
    p.sphere((0, 0, 16.0), 0.5, "steel", segs=14, rings=7)
    p.cyl((0, 0, 15.55), 0.3, 0.3, "steel_dark", segs=12)
    # Red cables down the side.
    for a in (200, 250, 300):
        r = math.radians(a)
        sk.bent(p, [(0.9 * math.cos(r), 0.9 * math.sin(r), 12.8), (1.75 * math.cos(r), 1.75 * math.sin(r), 9.0),
                    (2.05 * math.cos(r), 2.05 * math.sin(r), 5.0), (1.75 * math.cos(r), 1.75 * math.sin(r), 2.2)],
                0.06, "paint_red", segs=5)
    # The east side carries more: a pipe bundle up the tanks and a box beside the capsule.
    for k in range(3):
        sk.bent(p, [(1.75 + 0.05 * k, -0.45 + 0.2 * k, 7.3), (1.85, -0.35 + 0.2 * k, 9.5), (1.5, -0.3 + 0.2 * k, 11.8),
                    (0.95, -0.2 + 0.2 * k, 12.6)], 0.09, "steel", segs=6)
    p.slab(0.3, -0.95, 11.9, 0.85, -0.55, 12.9, "steel_dark", bevel=0.04)
    # The sprite leans a little east above the cage.
    p.warp(lambda v: (v[0] + 0.12 * min(1.0, max(0.0, (v[2] - 6.5) / 2.0)), v[1], v[2]))
    # The sprite's tanks and capsule are shorter than built: squeezed above the cage.
    p.warp(lambda v: (v[0], v[1], v[2] if v[2] < 7.3 else 7.3 + (v[2] - 7.3) * 0.88))
    p.transform(S(0.96, 0.96, 1.1))
    return p


kit.MATERIALS.setdefault("panel_blue", ("5d9ec9", 0.35, 0.3, None, 0))
kit.MATERIALS.setdefault("pod_flame", ("ffb15a", 0.5, 0.0, "ff8a2a", 3.0))


@model("cargo-pod")
def cargo_pod():
    """Factorio's cargo pod: a squat riveted capsule with a big domed top and a hatch, its sides
    clad in dark frames with green panels, standing on its copper thruster skirt."""
    p = Part()
    p.cyl((0, 0, 0.18), 0.3, 0.36, "copper_dull", segs=14, radius_top=0.38)
    for k in range(12):
        a = math.radians(k * 30)
        p.beam((0.3 * math.cos(a), 0.3 * math.sin(a), 0.02), (0.38 * math.cos(a), 0.38 * math.sin(a), 0.36), 0.04,
               0.03, "rust_brown")
    p.cyl((0, 0, 1.05), 0.55, 1.4, "rocket_white", segs=20, bevel=0.05)
    p.sphere((0, 0, 1.75), 0.55, "rocket_white", segs=20, rings=8, hemisphere=True, scale=(1, 1, 1.0))
    p.cyl((0, 0, 2.28), 0.2, 0.08, "steel_dark", segs=12)
    for k in range(4):
        a = math.radians(k * 90 + 45)
        p.box((0.56 * math.cos(a), 0.56 * math.sin(a), 1.05), (0.07, 0.55, 1.2), "steel_dark", rz=k * 90 + 45, bevel=0.02)
        p.box((0.585 * math.cos(a), 0.585 * math.sin(a), 1.05), (0.03, 0.4, 1.0), "paint_green", rz=k * 90 + 45)
    for z in (0.4, 1.72):
        p.cyl((0, 0, z), 0.58, 0.08, "steel_dark", segs=20)
    for k in range(12):
        a = math.radians(k * 30)
        p.bolt((0.57 * math.cos(a), 0.57 * math.sin(a), 1.76), "steel_light", radius=0.025, axis="Z")
    # Moving parts, from pod-opening.png (34 frames): the antenna (`anim_antenna`) rises out of
    # the dome, then three panels hinged under the dome's rim (`anim_panel`, pivot on the hinge)
    # swing out flat, blue cells up; the thruster's flame (`anim_flame`) burns under the skirt
    # while it brakes or climbs (pod-thruster-loop). vehicle_anim.gd opens it high in the sky.
    antenna = Part("anim_antenna", pivot=(0.0, 0.0, 2.2))
    antenna.tube((0.0, 0.0, 1.9), (0.0, 0.0, 2.25), 0.025, "steel_light", segs=6)
    antenna.cyl((0.0, 0.0, 2.27), 0.12, 0.03, "steel", segs=10)
    antenna.sphere((0.0, 0.0, 2.3), 0.03, "lamp_red", segs=6, rings=3)
    parts = [p, antenna]
    for a in (100, 220, 340):
        r = math.radians(a)
        c, s = math.cos(r), math.sin(r)
        hinge = (0.66 * c, 0.66 * s, 1.62)
        panel = Part("anim_panel", pivot=hinge)
        m = T(*hinge) @ R("Z", a - 90)
        panel.add_part(_pod_panel(), m)
        parts.append(panel)
    flame = Part("anim_flame", pivot=(0.0, 0.0, 0.0))
    flame.cyl((0.0, 0.0, -0.45), 0.05, 0.9, "pod_flame", segs=12, radius_top=0.3)
    flame.cyl((0.0, 0.0, -0.06), 0.28, 0.06, "pod_flame", segs=12)
    parts.append(flame)
    return parts


def _pod_panel():
    """A folded solar panel hanging from its hinge at the origin, its outside facing +y (away
    from the pod): a dark frame, blue cells on its inside, which faces up once unfolded."""
    q = Part()
    q.slab(-0.26, 0.0, -0.95, 0.26, 0.05, 0.0, "steel_dark", bevel=0.01)
    q.slab(-0.22, -0.006, -0.9, 0.22, 0.0, -0.05, "panel_blue")
    for z in (-0.65, -0.35):
        q.slab(-0.22, -0.01, z - 0.01, 0.22, 0.0, z + 0.01, "steel_light")
    return q


# ---------------------------------------------------------------------------------------------
# Cargo landing pad.

@model("cargo-landing-pad")
def cargo_landing_pad():
    """Factorio's cargo landing pad, 8x8 (planet-hub-2/3.png): the platform hub's planet-side
    twin, drawn round the same frame. Shared with the hub (space_platform.py): the upper cargo
    shaft in the north-east on its rusty drum with the clamp band and the yellow tabs on the corner
    posts, the machinery block with the radar dish in the south-east (olive here, cream on the
    hub), the east side under the shaft. Its own: in the north-west a grey machinery block under
    a red riveted box with a round grille port, red pipes and an antenna mast with a blue canister;
    in the south-west an olive ring round the turbine's pit with a capped post and an arm over it,
    a jet engine's nose pointing south-west under it, a rusty drum on the west edge; pipes, cables,
    blue boxes and vents between.

    Moving parts: the turbine's blades in the pit (anim_spin_turbine_pad) turn slowly, as
    Factorio's turbine sheet (32 frames at 0.5) creeps about four blades a loop; the shaft's round
    lid (anim_lid_pad), shut at rest as Factorio draws the upper giga hatch (the same as the hub's),
    hinges up about its north-east edge while a cargo pod comes down."""
    import space_platform as sp_
    import detail
    p = Part()
    # The pad stands on the ground: a base plate only under its machinery (the hub's deck
    # reaches further, its sprite draws the deck's edge).
    p.slab(-3.7, -3.2, 0.0, 3.55, 3.75, 0.1, "steel_dark", bevel=0.03)
    # North-east: the upper shaft, the corner posts' tabs and the east side, as the hub's (the
    # pad's shaft stands a little taller).
    ux, uy, uz = 1.18, 1.72, 2.9
    sp_.upper_shaft(p, ux, uy, uz)
    for x, y, z in ((2.85, 3.5, 2.85), (3.4, 2.75, 2.55)):
        p.slab(x - 0.22, y - 0.2, 0.1, x + 0.22, y + 0.2, z - 0.35, "steel_dark", bevel=0.04)
        p.slab(x - 0.25, y - 0.22, z - 0.4, x + 0.25, y + 0.22, z, "brass_yellow", bevel=0.05)
        p.cyl((x, y - 0.23, z - 0.2), 0.08, 0.04, "steel_black", segs=8, axis="Y")
    p.slab(3.0, -0.2, 0.1, 3.55, 3.2, 2.2, "steel_platform", bevel=0.05)
    detail.slots(p, (3.0, -0.2, 0.2), (3.55, 3.2, 2.0), "+x", 7, along=1)
    p.pipe([(3.55, 3.0, 1.6), (3.62, 2.0, 1.3), (3.58, 0.6, 1.5)], 0.08, "rust_brown", segs=8)
    # South-east: the dish block, olive, a little smaller than the hub's.
    blk = Part()
    sp_.dish_block(blk, "paint_olive")
    for k, (x, c) in enumerate(((1.75, "lamp_green"), (2.05, "lamp_red"), (2.35, "lamp_green"))):
        blk.cyl((x, -3.34, 0.65 + 0.12 * (k % 2)), 0.06, 0.04, c, segs=8, axis="Y")
    blk.slab(2.5, -3.34, 0.45, 3.2, -3.31, 0.85, "steel_light")
    detail.slots(blk, (2.55, -3.34, 0.45), (3.15, -3.31, 0.85), "-y", 4)
    p.add_part(blk, T(2.3, -1.85, 0) @ S(0.9, 0.88, 1.0) @ T(-2.3, 1.85, 0))

    # North-west: a grey machinery block under the red riveted box (both raised to the
    # sprite's height: the box's top shows 0.25 tiles higher than the hub's cockpit pedestal).
    detail.panelled(p, (-3.55, 1.2, 0.1), (-0.85, 3.6, 1.83), "steel_platform", rivet="steel_light", split=2)
    top_ = p
    p = Part()
    box = (-3.2, 2.1, 1.45), (-1.18, 3.4, 1.98)
    detail.panelled(p, *box, "paint_rose", faces=("-y", "-x", "+x"), rivet="steel_light", split=2)
    rivet_top = [(-3.12, 2.18), (-1.26, 2.18), (-1.26, 3.32), (-3.12, 3.32)]
    for a, b in zip(rivet_top, rivet_top[1:] + rivet_top[:1]):
        detail.rivet_line(p, (*a, 1.985), (*b, 1.985), 7, "Z")
    # Its round grille port, raised on a collar, ribs across the dark hole.
    px_, py_ = -2.2, 2.75
    p.cyl((px_, py_, 2.04), 0.45, 0.12, "paint_rose", segs=20, bevel=0.03)
    p.cyl((px_, py_, 2.1), 0.36, 0.02, "soot", segs=20)
    for k in range(7):
        y = py_ - 0.3 + 0.1 * k
        w = math.sqrt(max(0.0, 0.36 ** 2 - (y - py_) ** 2))
        p.slab(px_ - w, y - 0.015, 2.07, px_ + w, y + 0.015, 2.11, "steel_dark")
    p.bolts_ring((px_, py_, 2.105), 0.41, 12, radius=0.025)
    # Red pipes out of the box: east to the shaft and down its south side.
    p.pipe([(-1.2, 3.0, 1.75), (-0.6, 3.0, 1.8), (-0.3, 2.6, 1.6)], 0.11, "paint_red", segs=8)
    p.pipe([(-1.5, 2.08, 1.7), (-1.3, 1.6, 1.2), (-0.7, 1.3, 1.0)], 0.1, "paint_red", segs=8)
    p.pipe([(-2.9, 2.08, 1.6), (-3.0, 1.5, 1.2), (-3.2, 1.1, 0.8)], 0.08, "steel_dark", segs=8)
    detail.cable(p, [(-1.25, 2.4, 1.95), (-0.9, 2.2, 1.7), (-0.7, 1.8, 1.4)], 0.03, "wire_green")
    detail.cable(p, [(-1.25, 2.6, 1.95), (-0.85, 2.4, 1.75), (-0.5, 2.1, 1.3)], 0.03, "wire_red")
    # The antenna mast on the box's north half, a blue canister beside it, a yellow cable.
    ax, ay = -2.64, 3.05
    p.cyl((ax, ay, 2.6), 0.1, 1.3, "steel_light", segs=10, bevel=0.02)
    p.cyl((ax, ay, 2.1), 0.15, 0.2, "steel_dark", segs=10)
    p.cyl((ax, ay, 3.25), 0.06, 0.1, "steel_dark", segs=8)
    p.tube((ax, ay, 3.25), (ax, ay, 4.35), 0.022, "steel_light", segs=5)
    p.cyl((-2.29, 2.85, 2.4), 0.15, 0.7, "paint_blue", segs=12, bevel=0.03)
    p.cyl((-2.29, 2.85, 2.78), 0.1, 0.06, "steel_light", segs=10)
    detail.cable(p, [(ax + 0.08, ay, 3.2), (ax + 0.2, ay - 0.1, 2.95), (-2.3, 2.75, 2.8)], 0.02, "wire_yellow")
    top_.add_part(p, T(0, 0, 0.35))
    p = top_
    # West edge: an olive vent box, grey machinery and pipes down to the drum.
    detail.panelled(p, (-3.78, 1.6, 0.1), (-3.45, 3.0, 1.8), "paint_olive", faces=("-x", "-y"), rivet=None)
    detail.slots(p, (-3.78, 1.6, 0.2), (-3.45, 3.0, 1.7), "-x", 5, along=1)
    p.slab(-3.68, -1.0, 0.1, -2.95, 1.25, 1.2, "steel_platform", bevel=0.05)
    detail.slots(p, (-3.68, -1.0, 0.2), (-2.95, 1.25, 1.1), "-x", 6, along=1)
    for k in range(3):
        x = -3.6 + 0.14 * k
        p.pipe([(x, 1.2, 1.3), (x, 0.0, 1.32), (x - 0.05, -0.9, 1.2)], 0.06, "steel_dark", segs=6)

    # South-west: the olive ring round the turbine pit, on a grey drum.
    tx, ty, tz = -1.48, -1.1, 1.62
    kr = 1.12  # the sprite's ring is 1.38 tiles round (fitted)
    p.cyl((tx, ty, tz / 2 + 0.05), 1.22 * kr, tz - 0.1, "steel_platform", segs=28, caps=False)
    sk.lathe(p, (tx, ty, 0), [(r * kr, z) for r, z in ((1.0, tz - 0.05), (1.02, tz + 0.08), (1.12, tz + 0.18),
                              (1.27, tz + 0.18), (1.36, tz + 0.08), (1.37, tz - 0.05), (1.3, tz - 0.12))],
             "olive_pale", segs=32)
    sp_.ring(p, (tx, ty), 0.95 * kr, 1.02 * kr, 0.5, tz, "steel_black", segs=28)
    p.cyl((tx, ty, 0.55), 0.98 * kr, 0.03, "soot", segs=24)
    p.bolts_ring((tx, ty, tz - 0.06), 1.31 * kr, 18, radius=0.03, mat="steel_dark")
    # Ribbed louvres round the pit's inner wall (the sheet's ring of blades shows behind them).
    for k in range(18):
        a = 2 * math.pi * k / 18
        p.box((tx + 0.9 * kr * math.cos(a), ty + 0.9 * kr * math.sin(a), tz - 0.35), (0.04, 0.16, 0.5), "steel_dark",
              rz=math.degrees(a) + 30)
    # The capped post in the middle and the arm from it over the ring's south-west side.
    p.cyl((tx, ty, 1.35), 0.22, 1.6, "steel", segs=14, bevel=0.03)
    p.sphere((tx, ty, 2.15), 0.3, "steel", segs=14, rings=6, hemisphere=True, scale=(1, 1, 0.7))
    p.cyl((tx, ty, 2.36), 0.09, 0.12, "rust_brown", segs=8)
    p.beam((tx, ty, 2.05), (tx - 0.95, ty - 0.75, 1.9), 0.26, 0.2, "steel", bevel=0.04)
    p.beam((tx - 0.95, ty - 0.75, 1.9), (tx - 1.15, ty - 0.9, 1.3), 0.26, 0.2, "steel", bevel=0.04)
    p.pipe([(tx + 0.2, ty + 0.15, 1.95), (tx + 0.7, ty + 0.6, 1.95), (tx + 1.05, ty + 0.75, 1.75)], 0.05,
           "steel_dark", segs=6)
    # The turbine: blades on a hub low in the pit, turning.
    turbine = Part("anim_spin_turbine_pad", pivot=(tx, ty, 0.9))
    turbine.cyl((tx, ty, 0.85), 0.3, 0.12, "steel_dark", segs=12)
    for k in range(20):
        a = math.radians(360.0 * k / 20)
        c, s = math.cos(a), math.sin(a)
        turbine.beam((tx + 0.3 * c, ty + 0.3 * s, 0.85), (tx + 0.88 * kr * c, ty + 0.88 * kr * s, 0.95), 0.14, 0.015,
                     "steel_light", up=(-s * 0.6, c * 0.6, 0.8))
    # The jet engine's nose, lying south-west out from under the ring, a grille under its mouth.
    a_, b_ = Vector((-1.7, -1.71, 1.1)), Vector((-3.25, -2.37, 0.72))
    p.tube(a_, b_, 0.52, "steel", segs=16, radius_top=0.4, bevel=0.03)
    p.sphere(tuple(b_), 0.4, "steel", segs=14, rings=6)
    p.tube(b_ + (b_ - a_).normalized() * 0.25, b_ + (b_ - a_).normalized() * 0.45, 0.12, "soot", segs=10)
    for t in (0.25, 0.6):
        q = a_.lerp(b_, t)
        p.tube(q - (b_ - a_).normalized() * 0.03, q + (b_ - a_).normalized() * 0.03, 0.54 - 0.1 * t, "steel_dark",
               segs=16)
    p.slab(-3.2, -3.0, 0.1, -2.0, -2.45, 0.6, "steel_dark", bevel=0.04)
    detail.slots(p, (-3.2, -3.0, 0.1), (-2.0, -2.45, 0.6), "-y", 4)
    # The rusty drum on the west edge, the round knobs at the south-west corner.
    detail.ribbed_drum(p, (-3.55, -1.6, 0.68), 0.48, 1.2, "rust_brown", "steel_dark", axis="Y", ribs=3)
    for x in (-3.5, -2.95):
        p.cyl((x, -3.05, 0.32), 0.22, 0.2, "steel_dark", segs=14, axis="Y", bevel=0.04)
        p.cyl((x, -3.16, 0.32), 0.1, 0.03, "steel_light", segs=10, axis="Y")

    # Middle: grey machinery between the pit and the shaft, red pipes over it, an olive vent box.
    detail.panelled(p, (-0.2, -0.3, 0.1), (1.0, 0.9, 1.35), "steel_platform", rivet="steel_light")
    p.slab(0.1, 0.0, 1.35, 0.9, 0.6, 1.7, "steel_light", bevel=0.05)
    p.pipe([(0.0, 0.8, 1.5), (0.3, 0.2, 1.8), (0.9, -0.1, 1.7), (1.4, -0.3, 1.4)], 0.07, "paint_red", segs=8)
    p.pipe([(0.2, 0.9, 1.1), (0.6, 0.4, 1.5), (1.1, 0.1, 1.45)], 0.06, "paint_red", segs=8)
    detail.panelled(p, (0.15, -1.6, 0.1), (1.15, -0.4, 1.05), "paint_olive", faces=("-y",), rivet=None)
    detail.slots(p, (0.15, -1.6, 0.2), (1.15, -0.4, 1.0), "-y", 5)
    detail.cable(p, [(-0.1, -0.35, 1.2), (0.5, -0.9, 1.3), (1.0, -1.6, 1.2)], 0.03, "wire_red")
    detail.cable(p, [(0.0, -0.3, 1.25), (0.6, -0.8, 1.35), (1.05, -1.5, 1.25)], 0.03, "wire_green")
    # South: low machinery, blue boxes and pipes along the edge.
    p.slab(-1.9, -3.2, 0.1, 0.9, -2.3, 0.7, "steel_platform", bevel=0.05)
    p.slab(-0.7, -3.25, 0.35, -0.3, -2.95, 0.75, "paint_blue", bevel=0.03)
    p.slab(-1.6, -3.0, 0.7, -1.05, -2.45, 1.0, "paint_blue", bevel=0.03)
    for k in range(3):
        p.pipe([(-1.8 + 0.25 * k, -3.25, 0.4), (-1.6 + 0.25 * k, -2.9, 0.75), (-1.2 + 0.3 * k, -2.1, 0.9)], 0.05,
               "rust_brown" if k == 1 else "steel_dark", segs=6)
    sk.hose(p, [(-0.2, -3.2, 0.3), (0.3, -3.35, 0.35), (0.8, -3.25, 0.5)], 0.1, "steel_dark", rib=0.08)
    detail.cable(p, [(-1.0, -3.22, 0.75), (-0.4, -3.32, 0.5), (0.4, -3.28, 0.3)], 0.03, "wire_green")
    for x in (0.95, 1.3):
        p.pipe([(x, -3.2, 0.6), (x, -3.45, 0.3), (x, -3.5, 0.05)], 0.05, "rust_brown", segs=6)
    sp_.back_detail(p, -2.9, -1.1, 3.62, 0.15, 1.3)
    sp_.back_detail(p, 0.0, 3.2, 3.55, 0.15, 2.1, axis="x")

    lid, hinge = sp_.upper_lid("anim_lid_pad", ux, uy, uz)
    # The same frame as the hub's (its picture is drawn round the same 7 of 8 tiles).
    fit = T(0.1, 0.0, 0.0) @ S(0.91, 0.91, 1.12)
    p.transform(fit)
    lid.transform(fit)
    lid.pivot = fit @ hinge
    turbine.transform(fit)
    turbine.pivot = fit @ Vector((tx, ty, 0.9))
    return [p, turbine, lid]



# ---------------------------------------------------------------------------------------------
# Market and loaders.

kit.MATERIALS.setdefault("steel_teal", ("3f574f", 0.6, 0.6, None, 0))  # the market's lattice scaffold


def _octagon(ax, ay, c):
    """An octagon round the origin, `ax` / `ay` to its sides, corners cut by `c` (counter-clockwise)."""
    return [(-ax + c, -ay), (ax - c, -ay), (ax, -ay + c), (ax, ay - c), (ax - c, ay), (-ax + c, ay), (-ax, ay - c),
            (-ax, -ay + c)]


def _roof_band(p, lo, z0, hi, z1, mat):
    """A sloped band from octagon `lo` at z0 up to octagon `hi` at z1, capped on top."""
    for k in range(8):
        a0, a1, b0, b1 = lo[k], lo[(k + 1) % 8], hi[k], hi[(k + 1) % 8]
        p.poly([(*a0, z0), (*a1, z0), (*b1, z1), (*b0, z1)], mat, thick=0.03)
    p.poly([(*q, z1) for q in hi], mat)


def _lattice(p, a, b, z0, z1, mat="steel_teal", bays=None):
    """A lattice girder from a to b (x, y) between heights z0 and z1: two chords and a zigzag."""
    a, b = Vector((*a, 0)), Vector((*b, 0))
    n = bays or max(2, round((b - a).length / (z1 - z0)))
    for z in (z0, z1):
        p.beam((a.x, a.y, z), (b.x, b.y, z), 0.05, 0.05, mat)
    for k in range(n):
        q0, q1 = a + (b - a) * (k / n), a + (b - a) * ((k + 1) / n)
        za, zb = (z0, z1) if k % 2 == 0 else (z1, z0)
        p.beam((q0.x, q0.y, za), (q1.x, q1.y, zb), 0.035, 0.035, mat)


def _lattice_post(p, x, y, z1, mat="steel_teal"):
    """A square lattice column, 0.16 across, from the ground up to z1."""
    h = 0.08
    for dx in (-h, h):
        for dy in (-h, h):
            p.beam((x + dx, y + dy, 0.0), (x + dx, y + dy, z1), 0.035, 0.035, mat)
    n = max(2, round(z1 / 0.18))
    for k in range(n):
        za, zb = z1 * k / n, z1 * (k + 1) / n
        sgn = 1 if k % 2 == 0 else -1
        p.beam((x - h * sgn, y - h, za), (x + h * sgn, y - h, zb), 0.025, 0.025, mat)
        p.beam((x - h, y - h * sgn, za), (x - h, y + h * sgn, zb), 0.025, 0.025, mat)
        p.beam((x + h, y - h * sgn, za), (x + h, y + h * sgn, zb), 0.025, 0.025, mat)


@model("market")
def market():
    """Factorio's market, 3x3 (market.png): an octagonal shed of green corrugated walls under two
    tiers of hipped rose-brown brick roof, inside a two-storey scaffold of dark lattice girders
    (a lower frame on the shed's corners, a taller one round it). The picture's top is cut off at
    the upper girders, so the roof above them is a guess."""
    p = Part()
    base = _octagon(1.2, 1.5, 0.4)
    p.prism(base, 0.0, 1.72, "paint_market")
    # Corrugation: ribs up the front and the cut corners.
    for k in range(12):
        x = -0.77 + k * 0.14
        p.slab(x - 0.025, -1.515, 0.04, x + 0.025, -1.49, 1.7, "olive_dark")
    for sx in (-1, 1):
        for k in range(1, 4):
            t = k / 4
            x, y = sx * (0.8 + 0.4 * t), -1.5 + 0.4 * t
            p.box((x + sx * 0.02, y - 0.02, 0.87), (0.05, 0.04, 1.66), "olive_dark", rz=-sx * 45)
    p.slab(-0.8, -1.515, 0.0, 0.8, -1.48, 0.06, "rust")
    # Lower roof: eaves flaring out over the walls, sloping in to a brick drum.
    _roof_band(p, _octagon(1.27, 1.5, 0.43), 1.72, _octagon(0.89, 1.1, 0.3), 2.1, "stone_brick")
    p.prism(_octagon(0.89, 1.1, 0.3), 2.1, 2.45, "stone_brick")
    # Upper roof, then its cap.
    _roof_band(p, _octagon(1.0, 1.22, 0.33), 2.45, _octagon(0.67, 0.85, 0.22), 3.05, "stone_brick")
    p.prism(_octagon(0.67, 0.85, 0.22), 3.05, 3.6, "stone_brick")
    _roof_band(p, _octagon(0.71, 0.9, 0.24), 3.6, _octagon(0.36, 0.45, 0.12), 4.0, "stone_brick")
    # Lower scaffold: posts on the shed's cut corners, girders round its top.
    lo = [(-1.14, -1.12), (1.14, -1.12), (1.14, 1.12), (-1.14, 1.12)]
    for x, y in lo:
        _lattice_post(p, x, y, 2.75)
    for k in range(4):
        _lattice(p, lo[k], lo[(k + 1) % 4], 2.5, 2.75)
    # Upper scaffold, round the whole market.
    hi = [(-1.27, -0.92), (1.27, -0.92), (1.27, 1.38), (-1.27, 1.38)]
    for x, y in hi:
        _lattice_post(p, x, y, 4.3)
    for k in range(4):
        _lattice(p, hi[k], hi[(k + 1) % 4], 4.05, 4.3)
    # Rusty capping along the girders' fronts, as the picture's orange edges.
    p.beam((-1.14, -1.16, 2.76), (1.14, -1.16, 2.76), 0.03, 0.03, "rust_orange")
    p.beam((-1.27, -0.96, 4.31), (1.27, -0.96, 4.31), 0.03, 0.03, "rust_orange")
    return p


@model("loader")
def loader():
    """Factorio's loader, 1x2 facing north. Its picture (loader-structure.png) is only a grey
    plate, 0.9 x 1.78 tiles, with a black rim, a bolt in each corner and a black arrow the way
    items go. Here the plate is the lid of a hopper: its skirts slope in under it in the tier
    colour (the client tints them for fast and express loaders), steep enough that Factorio's
    camera sees only the plate, as the picture does."""
    # Longer than the plate so both the north and the south picture fit: they sit 0.16 apart.
    return loader_hopper(1.88)


def loader_hopper(length):
    """The loader's plated hopper, `length` tiles north-south, 0.9 wide."""
    p = Part()
    w, l, top, inset = 0.45, length / 2, 0.28, 0.2
    # Factorio draws a belt under the plate (belt_animation_set); it shows round the skirts and
    # moves at the tier's speed (the client's belt shader).
    tiles = round(length)
    p.slab(-0.4, -tiles / 2, 0.0, 0.4, tiles / 2, 0.05, "belt_surface")
    p.slab(-w + inset, -l + inset, 0.0, w - inset, l - inset, 0.06, "steel_black")
    # The skirts: a frustum from the base up to the plate's rim.
    bm_pts = [(-w + inset, -l + inset), (w - inset, -l + inset), (w - inset, l - inset), (-w + inset, l - inset)]
    top_pts = [(-w, -l), (w, -l), (w, l), (-w, l)]
    for k in range(4):
        a0, a1 = bm_pts[k], bm_pts[(k + 1) % 4]
        b0, b1 = top_pts[k], top_pts[(k + 1) % 4]
        p.poly([(a0[0], a0[1], 0.04), (a1[0], a1[1], 0.04), (b1[0], b1[1], top), (b0[0], b0[1], top)], "tier_paint",
               thick=0.02)
    # The plate: a black rim round a grey face.
    p.slab(-w, -l, top, w, l, top + 0.03, "steel_black")
    p.slab(-w + 0.04, -l + 0.04, top + 0.03, w - 0.04, l - 0.04, top + 0.045, "steel_light")
    # The arrow, as long as the picture's: a shaft and a head at the north end.
    p.slab(-0.02, -l + 0.2, top + 0.045, 0.02, l - 0.2, top + 0.052, "steel_black")
    for side in (-1, 1):
        p.box((side * 0.07, l - 0.3, top + 0.048), (0.2, 0.035, 0.008), "steel_black", rz=side * -50)
    for x in (-w + 0.12, w - 0.12):
        for y in (-l + 0.12, l - 0.12):
            p.box((x, y, top + 0.05), (0.07, 0.015, 0.01), "steel_black")
            p.box((x, y, top + 0.05), (0.015, 0.07, 0.01), "steel_black")
    return p
