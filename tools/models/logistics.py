"""Logistics and mid-game machines: roboport, logistic and construction robots, electric furnace,
beacon, assembling machines 2 and 3, and the crude oil patch.

Each model is matched to Factorio's HR sprite with compare.py (see client/assets/models/README.md,
"Matching a sprite"). Moving parts follow client/assets/models/README.md ("Moving parts"):
`anim_spin_*` turn while the machine works, `anim_glow_*` light up while it works, and the
roboport's `anim_door_n` / `anim_door_s` slide open and `anim_charge` lights up when robots come
close (anim.gd).
"""

import math

from kit import MATERIALS, Part, R, S, T, model, rng
from circuits import cable, coil, vents
import detail  # noqa: F401  (its materials)
import space_kit

MATERIALS.update({
    "paint_robo": ("b6a057", 0.55, 0.45, None, 0),      # roboport's yellow-ochre body bands
    "steel_robo": ("9a9c98", 0.45, 0.8, None, 0),       # roboport's grey sheet steel
    "copper_hose": ("8c5230", 0.6, 0.6, None, 0),       # the beacon's ribbed copper hoses
    "cable_tan": ("a08866", 0.7, 0.1, None, 0),         # the beacon's bundles of thin cables
    "paint_robo_blue": ("3f5f9a", 0.55, 0.45, None, 0),  # roboport's antenna arms
    "brass_rim": ("b08a45", 0.4, 0.9, None, 0),         # roboport hatch rim
    "robot_white": ("d9d3c3", 0.45, 0.4, None, 0),      # robots' shells
    "robot_red": ("a3241b", 0.5, 0.3, None, 0),
    "robot_thruster": ("a3241b", 0.5, 0.3, "ff3a1a", 1.2),  # logistic robot's leg tips, lit in flight
    "lamp_white": ("e8e8e0", 0.4, 0.0, "ffffff", 0.8),
    "robot_cream": ("cfc3a2", 0.5, 0.4, None, 0),
    "paint_efurnace": ("7f8a8e", 0.5, 0.6, None, 0),    # electric furnace's grey-blue steel
    "paint_efurnace_teal": ("3f5654", 0.55, 0.5, None, 0),
    "paint_capacitor": ("c8d3d8", 0.45, 0.5, None, 0),  # the furnace's white-blue cylinders
    "heater": ("ff7a1a", 0.8, 0.0, "ff6010", 2.5),      # glowing heater coils
    "copper_coil": ("9a5a32", 0.45, 0.85, None, 0),     # beacon's coiled cables
    "beacon_light": ("9fd8ff", 0.4, 0.0, "6fc0ff", 2.0),
    "paint_am2": ("3c5f8f", 0.55, 0.45, None, 0),       # assembler 2: blue
    "paint_am3": ("7d9a35", 0.55, 0.45, None, 0),       # assembler 3: green
    "rust_machine": ("7d5a3a", 0.75, 0.5, None, 0),     # the assemblers' brown machinery
    "soot_oil": ("1c1915", 0.3, 0.0, None, 0),          # crude oil: glossy black
    "stone_oil": ("3a3129", 0.95, 0.0, None, 0),
    "charge_spark": ("bfd6ff", 0.3, 0.0, "8fb4ff", 3.0),  # roboport charging glow
})


# ---------------------------------------------------------------------------------------------
# Roboport.

def octagon(rx, ry, cut):
    """Corners (counter-clockwise) of a rectangle rx x ry (half sizes) with corners cut by `cut`."""
    return [(rx, -ry + cut), (rx, ry - cut), (rx - cut, ry), (-rx + cut, ry), (-rx, ry - cut),
            (-rx, -ry + cut), (-rx + cut, -ry), (rx - cut, -ry)]


def frustum(p, base, top, z0, z1, mat, cy=0.0, top_cy=None):
    """A solid from polygon `base` at z0 to polygon `top` (same corner count) at z1."""
    k = Part()
    k.prism(base, z0, z1, mat)
    for v in k.bm.verts:
        if v.co.z > (z0 + z1) / 2:
            i = min(range(len(base)), key=lambda i: (v.co.x - base[i][0]) ** 2 + (v.co.y - base[i][1]) ** 2)
            v.co.x, v.co.y = top[i]
    p.add_part(k)


@model("roboport")
def roboport():
    """Factorio's roboport: a heavy octagonal body, grey sheet steel with ochre bands, narrowing
    to a big round hatch on top (its two doors slide apart, `anim_door_n`/`anim_door_s`); a
    front of machinery (boxes, pipes); four blue channel brackets at the corners carrying white
    tube frames, ball joints and antennas, and the charging points (`anim_charge` glows while
    robots are near); a black lattice antenna mast at the back."""
    p = Part()
    # Lower body: octagonal, from the front to near the back edge.
    p.prism(octagon(1.32, 1.5, 0.45), 0.0, 0.12, "steel_dark")
    lower = [(x, y - 0.12) for x, y in octagon(1.22, 1.42, 0.42)]
    p.prism(lower, 0.12, 1.15, "steel_robo")
    # Ochre bands round it at the bottom and just under the shoulder.
    band = [(x * 1.01, y * 1.01 - 0.12) for x, y in octagon(1.22, 1.42, 0.42)]
    p.prism(band, 0.12, 0.3, "paint_robo")
    p.prism(band, 0.95, 1.15, "paint_robo")
    # Shoulder: a frustum up to the hatch collar.
    hatch_y, hatch_z = -0.05, 1.85
    top = [(x * 0.7, y * 0.64 + hatch_y) for x, y in octagon(1.22, 1.32, 0.42)]
    frustum(p, lower, top, 1.15, hatch_z - 0.15, "steel_robo")
    collar = [(x, y) for x, y in top]
    p.prism(collar, hatch_z - 0.15, hatch_z, "paint_robo")
    # The hatch: a brass rim round a dark well, two doors in it.
    rim = Part()
    rim.ring_band((0, 0), 0.62, 0.8, 0.0, 0.12, 0, 360, "brass_rim", segs=28)
    rim.bolts_ring((0, 0, 0.1), 0.67, 20, radius=0.015)
    p.add_part(rim, T(0, hatch_y, hatch_z) @ S(1.0, 0.92, 1.0))
    p.cyl((0, 0, 0), 0.6, 0.5, "steel_black", segs=28, matrix=T(0, hatch_y, hatch_z - 0.25) @ S(1.0, 0.92, 1.0))
    doors = []
    for name, sign in (("anim_door_n", 1), ("anim_door_s", -1)):
        d = Part(name, pivot=(0, hatch_y, hatch_z + 0.03))
        pts = []
        for i in range(13):
            a = math.radians(i * 15) if sign > 0 else math.radians(180 + i * 15)
            pts.append((0.6 * math.cos(a), hatch_y + 0.55 * math.sin(a)))
        d.prism(pts, hatch_z + 0.02, hatch_z + 0.06, "steel_light", bevel=0.01)
        for k in range(3):
            a = math.radians(30 + k * 60) if sign > 0 else math.radians(210 + k * 60)
            d.beam((0, hatch_y, hatch_z + 0.065), (0.55 * math.cos(a), hatch_y + 0.5 * math.sin(a), hatch_z + 0.065),
                   0.03, 0.015, "steel")
        doors.append(d)
    # Grey panels on the shoulder's front, riveted.
    for x in (-0.55, 0.45):
        p.box((x, -1.05, 1.42), (0.5, 0.06, 0.4), "steel", bevel=0.02, matrix=None)
    # Front machinery: a dark box on the west, pipes, a cylinder tank.
    p.slab(-1.2, -1.95, 0.0, -0.55, -1.3, 0.85, "steel_dark", bevel=0.04)
    p.slab(-1.12, -1.97, 0.25, -0.75, -1.94, 0.6, "steel_black")
    for k in range(4):
        p.slab(-1.1, -1.99, 0.3 + k * 0.08, -0.77, -1.97, 0.33 + k * 0.08, "steel")
    p.cyl((-0.15, -1.62, 0.42), 0.38, 0.84, "steel_robo", segs=20, axis="X", bevel=0.04)
    p.cyl((-0.15, -1.62, 0.42), 0.4, 0.1, "paint_robo", segs=20, axis="X")
    for x in (-0.5, -0.35):
        p.pipe([(x, -1.4, 1.2), (x, -1.75, 1.0), (x, -1.9, 0.2)], 0.04, "copper_dull")
    p.pipe([(0.12, -1.3, 1.1), (0.12, -1.55, 1.05), (0.25, -1.55, 0.9)], 0.04, "copper_dull")
    p.pipe([(0.32, -1.3, 1.1), (0.32, -1.55, 1.05), (0.4, -1.55, 0.9)], 0.04, "copper_dull")
    p.pipe([(0.55, -1.9, 0.15), (0.55, -1.75, 0.35), (0.3, -1.7, 0.4)], 0.035, "steel_light")
    # Arms: broad blue channel brackets leaning out from the body's corners, each carrying the
    # sprite's white tube frames: an A-frame over the bracket with a small white ball joint and a
    # thin antenna at its top, a white knob on the bracket's end and a square frame hanging out
    # and down from it (they were thin lattices with a white block).
    from mathutils import Vector
    charge = Part("anim_charge")
    for sx in (-1, 1):
        for y, zt in ((-0.95, 1.2), (0.95, 1.7)):
            root = Vector((sx * 1.12, y, 0.45))
            tip = Vector((sx * 1.58, y + 0.18 * (1 if y > 0 else -1), zt))
            out = Vector((sx, 0, 0))
            along = (tip - root).normalized()
            for dy in (-0.11, 0.11):
                p.beam(root + Vector((0, dy, 0)), tip + Vector((0, dy, 0)), 0.2, 0.04, "paint_robo_blue", up=(0, 1, 0))
            p.beam(root - out * 0.06, tip - out * 0.06, 0.24, 0.04, "paint_robo_blue", up=tuple(out))
            p.beam((sx * 1.15, y, 0.3), (sx * 1.15, y, 1.0), 0.14, 0.1, "steel_dark")
            a_top = tip + out * 0.05 + Vector((0, 0, 0.3))
            p.pipe([tip + Vector((0, -0.13, 0.04)), a_top, tip + Vector((0, 0.13, 0.04))], 0.022, "steel_light", segs=6)
            p.sphere(a_top, 0.05, "steel_light", segs=10, rings=5)
            p.tube(a_top, a_top + Vector((sx * 0.05, 0, 0.18)), 0.012, "steel_light", segs=5)
            p.sphere(tip + out * 0.06 + Vector((0, 0, 0.06)), 0.065, "steel_light", segs=10, rings=5)
            loop = []
            for dy in (-0.14, 0.14):
                hang = [tip + Vector((0, dy, -0.04)), tip + out * 0.3 + Vector((0, dy, -0.16)),
                        tip + out * 0.3 + Vector((0, dy, -0.72))]
                loop += hang if dy < 0 else list(reversed(hang))
            p.pipe(loop, 0.022, "steel_light", segs=6)
            p.beam(tip - along * 0.25 + Vector((0, -0.11, 0)), tip + out * 0.3 + Vector((0, -0.14, -0.4)),
                   0.03, 0.03, "steel_light")
            cable(p, [(sx * 1.2, y + 0.1, 0.7), (sx * 1.45, y + 0.12, 1.3), tuple(tip + Vector((0, 0.06, 0)))],
                  "rubber_red", 0.015)
            charge.sphere(tip + out * 0.12 - Vector((0, 0, 0.12)), 0.07, "charge_spark", segs=8, rings=4)
    # The back and sides, which the sprite hardly shows: riveted grey panels and a ladder.
    for x in (-0.5, 0.5):
        p.slab(x - 0.3, 1.3, 0.35, x + 0.3, 1.34, 0.9, "steel", bevel=0.015)
        for bz in (0.4, 0.85):
            for bx in (-0.25, 0.25):
                p.bolt((x + bx, 1.345, bz), "steel_light", radius=0.015, axis="Y")
    for z in [0.2 + 0.15 * k for k in range(7)]:
        p.beam((0.95, 1.36, z), (1.12, 1.36, z), 0.025, 0.025, "steel_dark")
    for x in (0.95, 1.12):
        p.beam((x, 1.36, 0.1), (x, 1.36, 1.2), 0.03, 0.03, "steel_dark")
    # The antenna mast at the back west: a black lattice tower, four legs drawn in towards a
    # round cap; a grey ribbed box beside it.
    cx, cy = -0.65, 1.12
    legs = [(sx * 0.2, sy * 0.17) for sx in (-1, 1) for sy in (-1, 1)]
    for lx, ly in legs:
        p.beam((cx + lx, cy + ly, 1.6), (cx + lx * 0.45, cy + ly * 0.45, 2.45), 0.04, 0.04, "steel_black")
    for z0, z1 in ((1.6, 1.9), (1.9, 2.2), (2.2, 2.45)):
        f0 = 1.0 - 0.55 * (z0 - 1.6) / 0.85
        f1 = 1.0 - 0.55 * (z1 - 1.6) / 0.85
        for i in range(4):
            ax, ay = legs[i]
            bx, by = legs[(i + 1) % 4] if i % 2 == 0 else legs[(i + 3) % 4]
            p.beam((cx + ax * f0, cy + ay * f0, z0), (cx + bx * f1, cy + by * f1, z1), 0.025, 0.025, "steel_black")
    p.slab(-0.88, 0.92, 1.6, -0.42, 1.32, 1.68, "steel_black", bevel=0.02)
    p.cyl((cx, cy, 2.55), 0.11, 0.22, "steel_black", segs=12, bevel=0.02)
    p.cyl((cx, cy, 2.67), 0.07, 0.04, "steel_dark", segs=10)
    p.slab(-0.35, 1.0, 1.75, 0.05, 1.3, 2.05, "steel_dark", bevel=0.03)
    for k in range(5):
        p.slab(-0.33 + k * 0.08, 1.02, 2.05, -0.29 + k * 0.08, 1.28, 2.09, "steel_light")
    p.cyl((0.35, 1.15, 1.9), 0.12, 0.3, "steel_light", segs=10)
    p.cyl((0.6, 1.15, 1.85), 0.1, 0.25, "steel_light", segs=10)
    return [p, charge] + doors


def grounded(p):
    """Moves a part so its lowest point is on the ground."""
    low = min(v.co.z for v in p.bm.verts)
    return p.transform(T(0, 0, -low))


# ---------------------------------------------------------------------------------------------
# Robots: modelled round their middle, lowest point on the ground; movers.gd flies them.

def grounded_parts(parts, matrix):
    """Transforms the parts of one model (pivots too), then grounds them together."""
    for part in parts:
        part.transform(matrix)
        part.pivot = matrix @ part.pivot
    low = min(v.co.z for part in parts for v in part.bm.verts)
    for part in parts:
        part.transform(T(0, 0, -low))
        part.pivot.z -= low
    return parts


@model("logistic-robot")
def logistic_robot():
    """Factorio's logistic robot facing north: a cream-white dome with a black cross on top,
    a red-tipped tail leg reaching back and two side legs splayed back, an antenna with a ball
    on its west side.

    Moving parts, from its sprite sheet's four rows (idle, in motion, each with and without
    cargo): the legs are its thrusters (`anim_thrusters`, pivot where they meet the body), swung
    back and their red tips lit while it flies; the antenna's ball is red while it carries
    cargo (`anim_lamp_cargo`) and white without (`anim_lamp_empty`). vehicle_anim.gd shows one
    or the other."""
    p = Part()
    zc = 0.32
    p.sphere((0, 0.02, zc), 0.25, "robot_white", segs=16, rings=8, scale=(1.0, 1.05, 0.82))
    p.cyl((0, 0.02, zc - 0.08), 0.25, 0.06, "steel_dark", segs=16)
    # The black cross: bands over the dome, north-south and east-west.
    for rz in (0, 90):
        band = Part()
        band.ring_band((0, 0), 0.245, 0.262, -0.03, 0.03, 0, 180, "steel_black", segs=10)
        p.add_part(band, T(0, 0.02, zc) @ R("Z", rz) @ R("X", 90) @ S(1.0, 0.82, 1.0))
    # Legs: rails down from the body, red caps at their ends (glowing: the thrusters).
    legs = (((0, -0.15, zc - 0.05), (0, -0.3, 0.06)),
            ((-0.18, -0.06, zc - 0.05), (-0.28, -0.2, 0.08)),
            ((0.18, -0.06, zc - 0.05), (0.28, -0.2, 0.08)))
    thrusters = Part("anim_thrusters", pivot=(0.0, -0.08, zc - 0.05))
    for a, b in legs:
        thrusters.tube(a, b, 0.045, "robot_white", segs=8)
        end = tuple(b[i] + (b[i] - a[i]) * 0.2 for i in range(3))
        thrusters.tube(b, end, 0.052, "robot_thruster", segs=8)
    p.slab(-0.03, -0.3, zc + 0.05, 0.03, 0.2, zc + 0.24, "robot_white", bevel=0.02)
    p.tube((-0.12, 0.05, zc + 0.15), (-0.22, 0.1, zc + 0.45), 0.01, "steel_black", segs=4)
    cargo = Part("anim_lamp_cargo", pivot=(-0.22, 0.1, zc + 0.46))
    cargo.sphere((-0.22, 0.1, zc + 0.46), 0.025, "lamp_red", segs=6, rings=3)
    empty = Part("anim_lamp_empty", pivot=(-0.22, 0.1, zc + 0.46))
    empty.sphere((-0.22, 0.1, zc + 0.46), 0.025, "lamp_white", segs=6, rings=3)
    return grounded_parts([p, thrusters, cargo, empty], S(1.25, 1.25, 1.25))


@model("construction-robot")
def construction_robot():
    """Factorio's construction robot facing north: a cream barrel with a fan intake on top
    (dark ring and blades), a dark band round its foot, a nozzle with a red light on its front,
    and two thin jointed arms hanging below.

    Moving parts: the nozzle's light (`anim_lamp_nozzle`) flickers and the arms (`anim_arms`,
    pivot at the shoulders) reach forward while it works (Factorio's two `working` frames at
    0.3 a tick, with its sparks); vehicle_anim.gd decides it works when it hovers in one place."""
    p = Part()
    zc = 0.34
    p.cyl((0, 0, zc), 0.22, 0.3, "robot_cream", segs=18, bevel=0.03)
    p.cyl((0, 0, zc - 0.17), 0.2, 0.06, "steel_dark", segs=18)
    p.cyl((0, 0, zc + 0.16), 0.24, 0.05, "robot_cream", segs=18, bevel=0.015)
    p.cyl((0, 0, zc + 0.17), 0.19, 0.04, "steel_black", segs=18)
    for k in range(12):
        a = 2 * math.pi * k / 12
        p.beam((0.05 * math.cos(a), 0.05 * math.sin(a), zc + 0.185), (0.18 * math.cos(a), 0.18 * math.sin(a), zc + 0.185),
               0.02, 0.01, "steel_dark")
    p.cyl((0, 0, zc + 0.19), 0.06, 0.03, "steel", segs=10)
    # Nozzle on the front (south, towards the camera when flying north) with its red light.
    p.cyl((0, -0.24, zc - 0.02), 0.05, 0.08, "robot_cream", segs=8, axis="Y")
    lamp = Part("anim_lamp_nozzle", pivot=(0, -0.29, zc - 0.1))
    lamp.sphere((0, -0.29, zc - 0.1), 0.03, "lamp_red", segs=6, rings=3)
    # Side lugs and the hanging arms.
    arms = Part("anim_arms", pivot=(0.0, 0.0, zc - 0.2))
    for sx in (-1, 1):
        p.slab(sx * 0.2, -0.05, zc - 0.05, sx * 0.27, 0.05, zc + 0.05, "robot_cream", bevel=0.01)
        arms.pipe([(sx * 0.1, 0.0, zc - 0.2), (sx * 0.16, -0.12, 0.12), (sx * 0.12, -0.2, 0.0)], 0.018, "steel_dark")
    # Flying, it leans forward: the sprite looks down into its fan.
    return grounded_parts([p, lamp, arms], R("X", 22) @ S(1.3, 1.3, 1.3))


# ---------------------------------------------------------------------------------------------
# Electric furnace.

@model("electric-furnace")
def electric_furnace():
    """Factorio's electric furnace: a grey-blue block with a round tank wrapped in cable at its
    back west, two fan housings and an oval vent on top (`anim_spin_fan` turn while it works),
    a grille box at the back east, three white capacitors and pipes down the east side, and a
    teal sloped front with the heater window glowing (`anim_glow_heater`) while it works."""
    p = Part()
    p.slab(-1.4, -1.38, 0.0, 1.38, 1.35, 0.12, "steel_dark", bevel=0.02)
    p.slab(-1.25, -0.55, 0.12, 1.1, 1.28, 1.05, "paint_efurnace", bevel=0.05)
    # The tank at the back west, wrapped round with bands.
    p.cyl((-0.82, 0.6, 0.75), 0.6, 1.5, "paint_efurnace", segs=24, bevel=0.05)
    for z in (0.4, 0.7, 1.0, 1.3):
        p.cyl((-0.82, 0.6, z), 0.62, 0.08, "steel_dark", segs=24)
    # On top of the tank: the oval vent, a fan housing in front of it.
    vent = Part()
    vent.cyl((0, 0, 0), 0.32, 0.18, "steel", segs=20, bevel=0.03)
    vent.cyl((0, 0, 0.09), 0.26, 0.02, "steel_black", segs=20)
    for k in range(5):
        vent.slab(-0.2, -0.16 + k * 0.08, 0.09, 0.2, -0.14 + k * 0.08, 0.12, "steel_dark")
    p.add_part(vent, T(-0.72, 0.85, 1.58) @ S(1.25, 0.8, 1.0))
    fans = []
    for i, (x, y, z, r) in enumerate(((-0.62, 0.15, 1.3, 0.34), (0.05, 0.85, 1.3, 0.3))):
        p.cyl((x, y, z - 0.12), r + 0.04, 0.42, "steel", segs=22, bevel=0.03)
        p.cyl((x, y, z + 0.08), r - 0.03, 0.02, "steel_black", segs=22)
        fan = Part("anim_spin_fan", pivot=(x, y, z + 0.1))
        for k in range(3):
            a = 2 * math.pi * k / 3
            fan.beam((x, y, z + 0.11), (x + (r - 0.06) * math.cos(a), y + (r - 0.06) * math.sin(a), z + 0.11),
                     0.12, 0.02, "steel_light")
        fan.cyl((x, y, z + 0.12), 0.06, 0.04, "steel_dark", segs=10)
        fans.append(fan)
    # Back east: a grille box; then three capacitors stepping down towards the front.
    p.slab(0.4, 0.55, 1.0, 1.28, 1.3, 1.45, "steel", bevel=0.04)
    vents(p, 0.55, 1.15, 0.55, 1.08, 1.38, 5)
    for k, (y, z) in enumerate(((0.3, 1.18), (-0.05, 1.08), (-0.4, 0.98))):
        p.cyl((0.42, y, z), 0.16, 0.62, "paint_capacitor", segs=16, axis="X", bevel=0.03)
        for x in (0.15, 0.68):
            p.cyl((x, y, z), 0.17, 0.05, "steel_dark", segs=16, axis="X")
        p.cyl((0.42, y, z + 0.1), 0.17, 0.04, "rust_orange", segs=16, axis="X")
    # Pipes down the east side and along the front.
    for x in (1.0, 1.18):
        p.pipe([(x, 0.6, 1.2), (x, 0.3, 1.2), (x, -0.3, 0.9), (x, -0.5, 0.2)], 0.06, "steel")
    p.pipe([(-0.9, -0.4, 0.85), (-0.3, -0.45, 0.95), (0.2, -0.45, 0.95), (0.3, -0.1, 0.95)], 0.06, "steel")
    p.pipe([(-1.15, -0.2, 0.9), (-1.2, -0.7, 0.6), (-1.15, -1.1, 0.35)], 0.06, "steel")
    p.slab(-0.18, -0.58, 0.95, 0.12, -0.35, 1.15, "paint_blue", bevel=0.02)
    vents(p, -0.14, 0.08, -0.58, 0.98, 1.12, 3)
    # Front: the teal housing sloping up to the block, the heater window on its slope.
    prof = [(-1.36, 0.0), (-0.5, 0.0), (-0.5, 0.95), (-0.85, 0.95), (-1.36, 0.45)]
    p.side_prism(prof, -0.95, 0.85, "paint_efurnace_teal", bevel=0.03)
    slope = math.degrees(math.atan2(0.95 - 0.45, 1.36 - 0.85))
    frame = Part()
    frame.slab(-0.55, -0.32, -0.03, 0.55, 0.32, 0.03, "steel", bevel=0.03)
    frame.slab(-0.45, -0.24, 0.0, 0.45, 0.24, 0.04, "steel_black")
    for i in range(10):
        x = -0.5 + i * 0.11
        frame.bolt((x, 0.28, 0.035), "steel_light", radius=0.015)
        frame.bolt((x, -0.28, 0.035), "steel_light", radius=0.015)
    m = T(-0.05, -1.08, 0.72) @ R("X", -slope)
    p.add_part(frame, m)
    heater = Part("anim_glow_heater")
    for i in range(4):
        x = -0.3 + i * 0.2
        heater.slab(x - 0.06, -0.2, 0.03, x + 0.06, 0.2, 0.05, "heater")
    heater.transform(m)
    # The back (north), which the sprite never shows: louvres, a cable duct and service pipes,
    # so it reads as the same machine from behind.
    vents(p, 0.1, 0.9, 1.28, 0.25, 0.85, 6, face=1)
    p.slab(-0.2, 1.28, 0.15, 0.02, 1.36, 1.0, "steel_dark", bevel=0.02)
    for x in (0.3, 0.7):
        p.pipe([(x, 1.2, 1.05), (x, 1.38, 0.95), (x, 1.38, 0.15)], 0.05, "steel")
    p.slab(1.1, -0.5, 0.15, 1.16, 1.2, 0.95, "steel_dark")
    for k in range(4):
        p.slab(1.16, -0.4 + k * 0.4, 0.25, 1.19, -0.1 + k * 0.4, 0.85, "paint_efurnace", bevel=0.01)
    # Feet at the front corners and a small box with a dial at the front west.
    p.slab(-1.3, -1.38, 0.0, -1.0, -0.9, 0.3, "steel_dark", bevel=0.03)
    p.cyl((-1.15, -1.15, 0.4), 0.09, 0.2, "steel_light", segs=10)
    p.slab(0.9, -1.36, 0.0, 1.3, -0.6, 0.45, "steel_dark", bevel=0.03)
    for k in range(6):
        p.slab(0.95 + k * 0.06, -1.37, 0.06, 0.97 + k * 0.06, -1.35, 0.4, "steel")
    return [p, heater] + fans


# ---------------------------------------------------------------------------------------------
# Beacon.

@model("beacon")
def beacon():
    """Factorio's beacon: a low octagonal steel frame with bolted corner blocks round a pit full
    of coiled copper cables, and a tall ribbed antenna on a skirt of eight curved fins in the
    middle; the light under the skirt glows while it works (`anim_glow_light`)."""
    p = Part()
    # The sprite's frame is cut more at the back corners than at the front ones.
    w, front, back, cf, cb = 1.44, 1.46, 1.38, 0.3, 0.6
    ring = [(w, -front + cf), (w, back - cb), (w - cb, back), (-w + cb, back), (-w, back - cb),
            (-w, -front + cf), (-w + cf, -front), (w - cf, -front)]
    p.prism(ring, 0.0, 0.08, "steel_dark")
    # The frame: beams along the octagon, raised blocks at the corners.
    for i in range(8):
        a, b = ring[i], ring[(i + 1) % 8]
        inner_a = (a[0] * 0.86, a[1] * 0.86)
        inner_b = (b[0] * 0.86, b[1] * 0.86)
        p.prism([a, b, inner_b, inner_a], 0.0, 0.32, "steel", bevel=0.02)
        bx, by = a[0] * 0.94, a[1] * 0.94
        p.slab(bx - 0.13, by - 0.13, 0.0, bx + 0.13, by + 0.13, 0.42, "steel_robo", bevel=0.04)
        p.bolt((bx, by, 0.43), "steel_dark", radius=0.035)
    # The pit: dark floor with a deep hole at the front west, and what fills it as the sprite
    # draws it: thick ribbed copper hoses swirling out from the collar and over the frame, bundles
    # of thin tan cables, and red cables looping over the rim.
    p.prism([(x * 0.86, y * 0.86) for x, y in ring], 0.0, 0.1, "steel_black")
    p.cyl((-0.42, -0.4, 0.105), 0.36, 0.01, "grime", segs=14)
    r = rng(7)
    for k in range(8):
        a0 = 2 * math.pi * k / 8 + r.uniform(-0.15, 0.15)
        swirl, r1 = r.uniform(0.3, 1.2), r.uniform(0.95, 1.2)
        rad = r.uniform(0.14, 0.18)
        pts = []
        for t in (0.0, 0.3, 0.6, 0.85, 1.0):
            rr = 0.28 + (r1 - 0.28) * t
            a = a0 + swirl * t
            z = 0.3 + 0.3 * math.sin(math.pi * min(t, 0.85) / 0.85) - (0.12 if t == 1.0 else 0.0)
            pts.append((rr * math.cos(a), rr * math.sin(a), max(z, rad + 0.1)))
        space_kit.hose(p, pts, rad, "copper_hose", segs=8, rib=0.12, depth=0.14, smooth=3)
    for k in range(4):   # bundles of thin cables
        a0 = 2 * math.pi * (k + 0.3) / 4
        for j in range(4):
            off = (j - 1.5) * 0.04
            pts = [((0.3 + off) * math.cos(a0 + off), (0.3 + off) * math.sin(a0 + off), 0.45),
                   (0.7 * math.cos(a0 + 0.35 + off), 0.7 * math.sin(a0 + 0.35 + off), 0.5),
                   (1.1 * math.cos(a0 + 0.5 + off), 1.1 * math.sin(a0 + 0.5 + off), 0.25)]
            space_kit.bent(p, pts, 0.018, "cable_tan", segs=4, smooth=3)
    for a0, out in ((2.4, 1.48), (3.6, 1.5), (5.6, 1.42), (0.6, 1.3), (1.6, 1.25)):
        pts = [(0.6 * math.cos(a0), 0.6 * math.sin(a0), 0.4), (1.1 * math.cos(a0 + 0.1), 1.1 * math.sin(a0 + 0.1), 0.55),
               (out * math.cos(a0 + 0.2), out * math.sin(a0 + 0.2), 0.3),
               (out * math.cos(a0 + 0.35), out * math.sin(a0 + 0.35), 0.06)]
        space_kit.bent(p, pts, 0.035, "rubber_red", segs=6, smooth=4)
    # Bolted plates on the frame's beams.
    for i in range(8):
        a, b = ring[i], ring[(i + 1) % 8]
        mx, my = (a[0] + b[0]) / 2 * 0.93, (a[1] + b[1]) / 2 * 0.93
        ang = math.degrees(math.atan2(b[1] - a[1], b[0] - a[0]))
        p.box((mx, my, 0.33), (0.36, 0.14, 0.03), "steel_robo", rz=ang)
        for d in (-0.13, 0.13):
            c, s_ = math.cos(math.radians(ang)), math.sin(math.radians(ang))
            p.bolt((mx + d * c, my + d * s_, 0.35), "steel_dark", radius=0.02)
    # Side boxes on four faces, as the sprite's grey clamps.
    for ang in (0, 90, 180, 270):
        box = Part()
        box.slab(-0.22, -0.1, 0.0, 0.22, 0.1, 0.36, "steel_robo", bevel=0.03)
        box.slab(-0.15, -0.12, 0.08, 0.15, -0.1, 0.28, "steel_dark")
        p.add_part(box, R("Z", ang) @ T(0, -1.3, 0))
    # The antenna: a collar, eight fins hanging out and down, a ribbed mast.
    p.cyl((0, 0, 0.55), 0.22, 0.6, "steel_dark", segs=14)
    p.cyl((0, 0, 0.95), 0.16, 0.2, "steel", segs=14, bevel=0.02)
    for k in range(8):
        a = 2 * math.pi * (k + 0.5) / 8
        c, s = math.cos(a), math.sin(a)
        p.pipe([(0.1 * c, 0.1 * s, 0.98), (0.32 * c, 0.32 * s, 0.9), (0.52 * c, 0.52 * s, 0.6), (0.58 * c, 0.58 * s, 0.32)],
               0.022, "steel_light", segs=4)
        p.beam((0.52 * c, 0.52 * s, 0.6), (0.6 * c, 0.6 * s, 0.25), 0.07, 0.015, "steel_light", up=(c, s, 0))
    top = 2.5
    p.cyl((0, 0, (1.0 + top) / 2), 0.05, top - 1.0, "steel_light", segs=8, radius_top=0.025)
    n = 14
    for k in range(n):
        z = 1.1 + k * (top - 0.3 - 1.1) / n
        rr = 0.13 - 0.07 * k / n
        p.cyl((0, 0, z), rr, 0.035, "steel_light", segs=10)
    cable(p, [(0.08, -0.05, 0.6), (0.12, -0.08, 1.0), (0.06, -0.06, 1.25)], "rubber_red", 0.02)
    glow = Part("anim_glow_light")
    glow.cyl((0, 0, 0.75), 0.24, 0.16, "beacon_light", segs=14)
    return [p, glow]


# ---------------------------------------------------------------------------------------------
# Assembling machines 2 and 3: an open-topped box with battered walls in the tier's colour
# (riveted panels on every face, chamfered front corners) packed with brown machinery: a spoked
# wheel at the west, big gears at the front, a chain beam across the back, a motor block in the
# tier's colour and a gear (`anim_spin_arms`) that turns while it works. Measured on the HR
# sprites (the base layer with the animation layer drawn over it): the walls lean in from about
# 2.75 x 2.5 tiles at the ground to 2.3 x 2.15 at the rim, 1 tile up.

def _loft(p, bottom, top, mat):
    """A closed solid between two 3D outlines with the same corner count (counter-clockwise
    seen from above)."""
    n = len(bottom)
    p.poly(list(reversed(bottom)), mat)
    p.poly(top, mat)
    for i in range(n):
        j = (i + 1) % n
        p.poly([bottom[i], bottom[j], top[j], top[i]], mat)


def _lerp(a, b, t):
    return tuple(a[k] + (b[k] - a[k]) * t for k in range(3))


def _quad_at(q, u, v):
    """A point on quad q = (b_i, b_j, t_j, t_i) at u along the bottom edge, v up the face."""
    return _lerp(_lerp(q[0], q[1], u), _lerp(q[3], q[2], u), v)


def _face_normal(q):
    from mathutils import Vector
    a, b, d = Vector(q[0]), Vector(q[1]), Vector(q[3])
    return (b - a).cross(d - a).normalized()


def _panels(p, q, count, paint, u_pad=0.04, v0=0.12, v1=0.9):
    """Riveted plates standing proud of a wall face."""
    n = _face_normal(q)
    off = n * 0.035
    axis = "X" if abs(n.x) > max(abs(n.y), abs(n.z)) else "Y" if abs(n.y) > abs(n.z) else "Z"
    for k in range(count):
        u0 = u_pad / 2 + k / count
        u1 = (k + 1) / count - u_pad / 2
        pts = [_quad_at(q, u, v) for u, v in ((u0, v0), (u1, v0), (u1, v1), (u0, v1))]
        p.poly([tuple(c + o for c, o in zip(pt, off)) for pt in pts], paint, thick=0.035)
        for u in (u0 + 0.12 * (u1 - u0), u1 - 0.12 * (u1 - u0)):
            for v in (v0 + 0.1, (v0 + v1) / 2, v1 - 0.1):
                c = _quad_at(q, u, v)
                p.cyl(tuple(x + o * 0.06 for x, o in zip(c, n)), 0.02, 0.025, "steel_light", segs=6, axis=axis)


def _gear(p, centre, radius, width, teeth, mat, axis="Z", hub="steel_dark", yaw=0.0):
    """A toothed wheel lying flat (axis "Z") or standing up with its axle east-west ("X"), then
    turned `yaw` degrees about the vertical."""
    g = Part()
    g.cyl((0, 0, 0), radius, width, mat, segs=max(12, teeth), axis=axis, bevel=0.01)
    g.cyl((0, 0, 0), radius * 0.3, width * 1.6, hub, segs=8, axis=axis)
    for k in range(teeth):
        a = 2 * math.pi * k / teeth
        c, s = math.cos(a) * (radius + 0.03), math.sin(a) * (radius + 0.03)
        if axis == "Z":
            g.box((c, s, 0), (0.07, 0.06, width), mat, rz=math.degrees(a))
        else:
            g.box((0, 0, 0), (width, 0.07, 0.06), mat, matrix=T(0, c, s) @ R("X", math.degrees(a)))
    p.add_part(g, T(*centre) @ R("Z", yaw))


ASSEMBLER_TIERS = {
    # Where the big pieces sit differs a little between the two sprites.
    2: {"wheel": (-0.78, 0.2, 1.0, 0.19), "motor": (0.25, -0.3, 0.45, 0.4, 1.12),
        "chain": ((-0.25, 0.25, 1.12), (0.95, 0.5, 1.12)),
        "gears": ((-0.62, -0.55, 0.26), (-0.18, -0.45, 0.2)), "top": 1.0,
        # Standing gears along the front-west, their teeth showing over the rim.
        "row": ((-0.85, -0.72, 0.24), (-0.45, -0.75, 0.2))},
    3: {"wheel": (-0.72, 0.05, 1.12, 0.28), "motor": (0.28, -0.1, 0.6, 0.5, 1.25),
        "chain": ((-0.6, 0.55, 1.15), (1.0, 0.75, 1.15)),
        "gears": ((-0.55, -0.45, 0.24), (0.05, -0.55, 0.2)), "top": 1.05,
        "row": ((-0.95, -0.75, 0.26), (-0.62, -0.5, 0.26), (-0.3, -0.25, 0.24), (-0.25, -0.75, 0.2))},
}


def assembler(paint, accent, tier=2):
    cfg = ASSEMBLER_TIERS[tier]
    p = Part()
    h = cfg["top"]
    # Outline at the ground and at the rim (counter-clockwise from the front-right corner).
    bottom = [(1.12, -1.22), (1.3, -1.02), (1.36, -0.7), (1.36, 1.0), (1.12, 1.28), (-1.12, 1.28), (-1.36, 1.0),
              (-1.36, -0.7), (-1.3, -1.02), (-1.12, -1.22)]
    top = [(0.98, -1.08), (1.1, -0.95), (1.13, -0.7), (1.13, 0.8), (0.92, 1.06), (-0.92, 1.06), (-1.13, 0.8),
           (-1.13, -0.7), (-1.1, -0.95), (-0.98, -1.08)]
    B = [(x, y, 0.1) for x, y in bottom]
    Tp = [(x, y, h) for x, y in top]
    # A dark plinth under the walls (the dark strip below the front panels).
    p.prism(bottom, 0.0, 0.12, "steel_black")
    # The walls: a shell leaning in, with an inner face so the rim has thickness.
    inner = [(x * 0.88, y * 0.9 + 0.02) for x, y in top]
    n = len(B)
    for i in range(n):
        j = (i + 1) % n
        _loft(p, [B[i], B[j], (inner[j][0], inner[j][1], 0.1), (inner[i][0], inner[i][1], 0.1)],
              [Tp[i], Tp[j], (inner[j][0], inner[j][1], h), (inner[i][0], inner[i][1], h)], paint)
        # A brown lip along the rim.
        a, b = Tp[i], Tp[j]
        p.beam((a[0], a[1], h + 0.02), (b[0], b[1], h + 0.02), 0.08, 0.05, "rust_machine")
    # Riveted panels: four on the front, one on each chamfer, more down each side.
    for i in range(n):
        j = (i + 1) % n
        count = 4 if i in (n - 1, 4) else max(1, round(math.dist(B[i][:2], B[j][:2]) / 0.45))
        q = (B[i], B[j], Tp[j], Tp[i])
        if i == n - 1:
            # The front's panels sit over a row of dark feet.
            _panels(p, q, count, paint, v0=0.3, v1=0.9)
            n_out = _face_normal(q)
            for k in range(6):
                pts = [_quad_at(q, u, v) for u, v in ((k / 6 + 0.01, 0.0), ((k + 1) / 6 - 0.01, 0.0),
                                                     ((k + 1) / 6 - 0.01, 0.27), (k / 6 + 0.01, 0.27))]
                p.poly([tuple(c + o * 0.04 for c, o in zip(pt, n_out)) for pt in pts], "steel_dark", thick=0.04)
        else:
            _panels(p, q, count, paint, v0=0.06, v1=0.88)
    # Inside: a floor of machinery just under the rim.
    p.prism([(x * 0.86, y * 0.88) for x, y in top], 0.1, h - 0.12, "rust_machine")
    # A big tan elbow housing from under the wheel down to the front gears.
    p.pipe([(-0.8, 0.1, h - 0.05), (-0.6, -0.25, h), (-0.25, -0.45, h - 0.08)], 0.2, "rust_machine", segs=10)
    for x, y in ((-0.72, -0.1), (-0.5, -0.32)):
        p.bolts_ring((x, y, h + 0.19), 0.08, 4, radius=0.02)
    # The spoked wheel over a big brown housing at the west.
    wx, wy, wz, wr = cfg["wheel"]
    p.slab(-1.0, wy - 0.7, h - 0.25, -0.35, wy + 0.25, wz - 0.1, "rust_machine", bevel=0.05)
    p.cyl((wx, wy, wz - 0.05), wr * 0.55, 0.12, "steel_dark", segs=10)
    p.cyl((wx, wy, wz + 0.04), wr, 0.08, "steel_light", segs=20, bevel=0.015)
    p.cyl((wx, wy, wz + 0.09), wr * 0.78, 0.03, "steel_dark", segs=16)
    spokes = 5 if tier == 3 else 4
    for k in range(spokes):
        a = 2 * math.pi * k / spokes
        p.beam((wx, wy, wz + 0.11), (wx + wr * 0.78 * math.cos(a), wy + wr * 0.78 * math.sin(a), wz + 0.11), 0.05,
               0.03, "steel_light")
    p.cyl((wx, wy, wz + 0.12), wr * 0.22, 0.05, "steel_light", segs=8)
    # A copper pipe down the west wall, and a tank lying across the back-west corner.
    p.pipe([(-1.02, -0.75, h - 0.1), (-1.02, 0.45, h - 0.1), (-0.9, 0.55, h)], 0.045, "copper_dull", segs=6)
    p.cyl((-0.85, 0.58, h + 0.05), 0.12, 0.42, "rust_machine", segs=10, axis="X", bevel=0.02)
    # A lever arm across the back-west on a post, and pulleys at the back corners.
    p.cyl((-0.85, 0.8, h + 0.05), 0.07, 0.3, "steel_dark", segs=8)
    p.beam((-0.95, 0.8, h + 0.18), (-0.1, 0.92, h + 0.18), 0.12, 0.06, "steel_dark")
    for sx in (-1, 1):
        p.cyl((sx * 1.02, 1.0, h + 0.06), 0.1, 0.07, "steel_light", segs=10, axis="X")
    # Machinery across the back: a big tan housing with bolted bumps on top.
    p.cyl((0.08, 0.85, h + 0.02), 0.22, 0.8, "rust_machine", segs=12, axis="X", bevel=0.03)
    for x in (-0.18, 0.05, 0.28, 0.45):
        p.cyl((x, 0.9, h + 0.24), 0.045, 0.1, "steel_light", segs=6)
    p.slab(0.45, 0.55, h - 0.2, 1.05, 1.05, h + 0.08, "steel_dark", bevel=0.03)
    # The chain beam with gears at its east end.
    (cx0, cy0, cz0), (cx1, cy1, cz1) = cfg["chain"]
    p.beam((cx0, cy0, cz0), (cx1, cy1, cz1), 0.14, 0.06, "steel")
    for k in range(12):
        t = k / 11
        x, y = cx0 + (cx1 - cx0) * t, cy0 + (cy1 - cy0) * t
        p.slab(x - 0.025, y - 0.08, cz0 + 0.03, x + 0.025, y + 0.08, cz0 + 0.05, "steel_dark")
    _gear(p, (cx1 - 0.15, cy1 - 0.25, cz1 - 0.12), 0.2, 0.07, 12, "steel", axis="X")
    _gear(p, (cx1 - 0.3, cy1 - 0.3, cz1 - 0.2), 0.15, 0.06, 10, "steel_dark", axis="X")
    # The motor block in the tier's colour, with a coiled drum on top.
    mx, my, mw, md, mz = cfg["motor"]
    p.slab(mx, my, h - 0.25, mx + mw * 0.75, my + md, mz, accent, bevel=0.04)
    p.slab(mx + mw * 0.75, my + 0.05, h - 0.25, mx + mw, my + md - 0.05, mz - 0.2, accent, bevel=0.03)
    p.cyl((mx + 0.17, my + md / 2, mz + 0.06), 0.14, 0.12, "steel", segs=14, bevel=0.02)
    p.cyl((mx + 0.17, my + md / 2, mz + 0.13), 0.08, 0.03, "rust_machine", segs=10)
    p.pipe([(mx + mw * 0.75, my + 0.1, mz - 0.05), (mx + mw + 0.12, my, mz - 0.15),
            (mx + mw + 0.15, my - 0.3, h - 0.1)], 0.025, "hazard", segs=6)
    # A piston rod reaching down to a housing in the south-east corner.
    p.slab(0.5, -0.82, h - 0.3, 0.98, -0.4, h - 0.05, "rust_machine", bevel=0.03)
    p.tube((0.62, -0.6, h - 0.02), (0.85, -0.15, h + 0.12), 0.035, "steel_light", segs=6)
    p.cyl((0.9, 0.1, h - 0.1), 0.09, 0.45, "steel_light", segs=10, bevel=0.01)
    # The big gears at the front: one turns (`anim_spin_arms`), the other is an idler.
    (g1x, g1y, g1r), (g2x, g2y, g2r) = cfg["gears"]
    gz = h - 0.12
    _gear(p, (g2x, g2y, gz), g2r, 0.08, 12, "steel")
    for x, y, r in cfg["row"]:
        _gear(p, (x, y, h - 0.02), r, 0.09, 12, "steel", axis="X", yaw=-35)
    gears = Part("anim_spin_arms", pivot=(g1x, g1y, gz + 0.02))
    _gear(gears, (g1x, g1y, gz + 0.02), g1r, 0.08, 14, "steel")
    return [p, gears]


@model("assembling-machine-2")
def assembling_machine_2():
    """Factorio's assembling machine 2: blue walls round a box of brown machinery (a spoked
    wheel, a chain beam, gears, a blue motor block)."""
    return assembler("paint_am2", "paint_am2", 2)


@model("assembling-machine-3")
def assembling_machine_3():
    """Factorio's assembling machine 3: the same box with green walls, a bigger green motor
    block, a bigger wheel and gears."""
    return assembler("paint_am3", "paint_am3", 3)


# ---------------------------------------------------------------------------------------------

@model("crude-oil")
def crude_oil():
    """Factorio's crude oil patch: a glossy black stain soaked into the ground, broken ground
    and a few dark stones round its edge."""
    p = Part()
    r = rng(11)
    n = 28
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        rad = 0.8 + 0.15 * math.sin(3 * a + 0.5) + r.uniform(-0.08, 0.08)
        pts.append((rad * math.cos(a) * 1.05, rad * math.sin(a) * 0.95))
    p.prism(pts, 0.0, 0.004, "stone_oil")
    p.prism([(x * 0.82, y * 0.8) for x, y in pts], 0.0, 0.02, "soot_oil")
    p.prism([(x * 0.45 + 0.1, y * 0.4) for x, y in pts], 0.0, 0.026, "soot_oil")
    for k in range(9):
        a = r.uniform(0, 2 * math.pi)
        d = r.uniform(0.6, 0.92)
        s = r.uniform(0.05, 0.11)
        p.sphere((d * math.cos(a), d * math.sin(a) * 0.9, s * 0.3), s, "stone_oil", segs=7, rings=4,
                 scale=(1.0, r.uniform(0.7, 1.0), 0.6))
    return p
