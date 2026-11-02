"""Vehicles: car, locomotive, cargo wagon, fluid wagon. Modelled facing north (orientation 0).

Each model is matched to Factorio's HR sprite with compare.py (see client/assets/models/README.md,
"Matching a sprite").
"""

import math

from mathutils import Vector

import detail
import kit
from kit import Part, R, S, T, model


def own_materials(part, suffix):
    """Renames the part's materials to `<name>_<suffix>` (same look as the originals), so the
    part colours (tools/models/part_colors.py) sample turrets, cannons and legs on their own
    instead of snapping them to the hull's paint. Glass and lamps keep theirs. The client picks
    the weathering by substring, so `steel_dark_turret` still weathers as steel."""
    names = []
    for name in part.mats:
        hex_colour, rough, metal, emit, strength = kit.MATERIALS[name]
        if emit or name in kit.ALPHA:
            names.append(name)
            continue
        new = "%s_%s" % (name, suffix)
        kit.MATERIALS.setdefault(new, (hex_colour, rough, metal, emit, strength))
        names.append(new)
    part.mats = names
    return part



def along_y(p, profile, y0, y1, mat, bevel=0.0):
    """A cross-section in the x-z plane (list of (x, z), counter-clockwise seen from +y)
    extruded along y from y0 to y1: the long hoods and tanks of the rolling stock."""
    return p.prism(profile, -y1, -y0, mat, bevel, matrix=R("X", 90))


def mirrored(half):
    """A symmetric cross-section from its right half [(x, z), ...] listed bottom to top, x > 0."""
    return half + [(-x, z) for x, z in reversed(half)]


def bogie(p, y):
    """A two-axle bogie under rolling stock, centred on y. Factorio draws its own (the
    `train-wheel` sprite, turned with the rails), so this is only seen with the fallback
    material; sized like that sprite: wheels on the rails (x = +-0.75), a tall side frame with
    its springs, a bolster up to the body. Each axle with its wheels is a part of its own
    (`anim_wheel_rail`, turning about its axle), returned for the model's list: the client rolls
    them with the train's speed."""
    axles = []
    for dy in (-0.5, 0.5):
        axle = Part("anim_wheel_rail", pivot=(0.0, y + dy, 0.36))
        for sx in (-1, 1):
            axle.cyl((sx * 0.72, y + dy, 0.36), 0.36, 0.12, "steel_black", segs=16, axis="X", bevel=0.02)
            axle.cyl((sx * 0.8, y + dy, 0.36), 0.14, 0.06, "steel", segs=8, axis="X")
            # A spoke, so the turning shows.
            axle.slab(sx * 0.79 - 0.02, y + dy - 0.03, 0.08, sx * 0.79 + 0.02, y + dy + 0.03, 0.64, "steel")
        axle.cyl((0, y + dy, 0.36), 0.06, 1.5, "steel", segs=8, axis="X")
        axles.append(axle)
    for sx in (-1, 1):
        p.side_prism([(y - 0.85, 0.3), (y + 0.85, 0.3), (y + 0.75, 0.62), (y + 0.3, 0.8), (y - 0.3, 0.8),
                      (y - 0.75, 0.62)], sx * 0.84 - 0.06, sx * 0.84 + 0.06, "rust_brown", bevel=0.03)
        p.cyl((sx * 0.84, y, 0.88), 0.12, 0.2, "steel_light", segs=8)
    p.slab(-0.95, y - 0.28, 0.8, 0.95, y + 0.28, 1.05, "rust_brown", bevel=0.04)
    return axles


def tyre(p, x, y, r, w, segs=16):
    """A fat tyre on its rim, axle along x, with the hub cap on the outside (sign of x)."""
    sx = 1 if x > 0 else -1
    p.cyl((x, y, r), r, w, "rubber", segs=segs, axis="X", bevel=0.06)
    p.cyl((x + sx * w / 2, y, r), r * 0.62, 0.03, "steel_dark", segs=segs, axis="X")
    p.cyl((x + sx * (w / 2 + 0.02), y, r), r * 0.28, 0.04, "steel", segs=8, axis="X")
    # Three lugs on the hub cap, so the turning shows.
    for k in range(3):
        a = k * 2 * math.pi / 3
        p.cyl((x + sx * (w / 2 + 0.04), y + math.cos(a) * r * 0.45, r + math.sin(a) * r * 0.45), 0.035, 0.03,
              "steel_dark", segs=6, axis="X")


@model("car")
def car():
    """Factorio's car: a buggy. Four big tyres stand out beside a narrow riveted cream body
    (the whole thing sits about 0.13 tiles forward of the vehicle's position, as in the
    sprite). The radiator grille slopes down to the front (north) between two headlights on the
    bumper; behind the open cockpit the engine block, its fan and the yellow hoses are bare at
    the back; coil-sprung arms reach out to the wheels. The roof machine gun is the separate
    `anim_turret_head`, its pivot on the vehicle's axis, barrel north at rest."""
    p = Part()
    wheels = []
    # The rear tyres are bigger than the front ones, as in the sprite. Each is a part of its own
    # (`anim_wheel_front` steers and rolls, `anim_wheel_rear` rolls), its pivot on its axle.
    # Sizes and places measured against all 64 of the car's rotation frames (turntable.py).
    for y, r, w in ((0.955, 0.358, 0.336), (-0.705, 0.414, 0.38)):
        for sx in (-1, 1):
            wheel = Part("anim_wheel_front" if y > 0 else "anim_wheel_rear", pivot=(sx * 0.77, y, r))
            tyre(wheel, sx * 0.77, y, r, w)
            wheels.append(wheel)
            # Wishbone arms and a coil spring from the body to each hub.
            for dy in (-0.12, 0.12):
                p.beam((sx * 0.45, y + dy * 1.5, 0.5), (sx * 0.66, y + dy * 0.3, r), 0.05, 0.05, "steel_dark")
            p.cyl((sx * 0.55, y, 0.62), 0.06, 0.32, "steel_light", segs=8)
    # Chassis tub: low and narrow between the wheels.
    p.slab(-0.52, -1.18, 0.22, 0.52, 1.2, 0.64, "paint_cream", bevel=0.06)
    # Front: the grille slopes from the cockpit down to a rounded nose over the bumper.
    # (A little bigger and lower than built, its middle 0.08 further back.)
    hood = T(0, 0.67, 0.68) @ S(1.12, 1.12, 1.12) @ T(0, -0.75, -0.76)
    p.side_prism([(0.0, 0.38), (1.36, 0.38), (1.36, 0.58), (1.27, 0.77), (1.12, 0.86), (0.08, 1.15), (0.0, 1.15)],
                 -0.42, 0.42, "paint_cream", bevel=0.04, matrix=hood)
    for k in range(10):
        t = (k + 0.5) / 10
        y, z = 0.12 + 0.98 * t, 1.15 - 0.29 * t + 0.015
        a, b = hood @ Vector((-0.32, y, z)), hood @ Vector((0.32, y, z))
        p.beam(tuple(a), tuple(b), 0.05, 0.034, "rust_brown")
    # Bumper and headlights on the nose.
    p.slab(-0.56, 1.27, 0.39, 0.56, 1.41, 0.51, "steel", bevel=0.03)
    for x in (-0.4, 0.4):
        p.cyl((x, 1.35, 0.62), 0.084, 0.11, "steel_light", segs=10, axis="Y")
        p.cyl((x, 1.41, 0.62), 0.062, 0.01, "glass", segs=10, axis="Y")
    # Side panels with the round-cornered window in the middle.
    for sx in (-1, 1):
        p.slab(sx * 0.5, -0.3, 0.4, sx * 0.56, 0.3, 0.9, "paint_cream", bevel=0.03)
        p.slab(sx * 0.55, -0.15, 0.6, sx * 0.57, 0.15, 0.75, "soot")
    # Cockpit roof frame.
    p.slab(-0.45, -0.25, 0.9, 0.45, 0.25, 0.98, "steel_dark", bevel=0.03)
    # Rear: engine block, fan and exhaust, rear bumper.
    p.slab(-0.47, -1.17, 0.58, 0.47, -0.17, 0.97, "steel_dark", bevel=0.05)
    p.cyl((0, -1.05, 0.72), 0.24, 0.12, "steel", segs=12, axis="Y")
    p.slab(-0.62, -1.2, 0.39, 0.62, -1.08, 0.53, "steel", bevel=0.03)
    p.pipe([(0.1, -0.8, 0.95), (0.1, -0.8, 1.28), (0.1, -1.0, 1.28)], 0.04, "steel_dark", segs=6)
    for sx in (-1, 1):
        p.pipe([(sx * 0.3, -0.4, 0.9), (sx * 0.48, -0.6, 0.85), (sx * 0.4, -1.0, 0.8)], 0.05, "hazard", segs=6)

    # The gun sits mostly behind its post, as in the turret sheet (measured against all 64 of its
    # frames by tools/models/turntable.py): a short barrel north, the receiver over the post, the
    # ammo box on the west side and the belt's round loop standing up behind.
    turret = Part("anim_turret_head", pivot=(0.0, 0.0, 0.98))
    turret.cyl((0, 0.02, 1.2), 0.1, 0.2, "steel_dark", segs=10)
    turret.slab(-0.16, -0.39, 1.33, 0.08, 0.03, 1.65, "steel", bevel=0.03)
    turret.slab(-0.0, -0.41, 1.51, 0.16, -0.17, 1.61, "steel_dark", bevel=0.02)
    turret.cyl((0.02, 0.14, 1.58), 0.04, 0.32, "steel_dark", segs=8, axis="Y")
    turret.cyl((0.04, 0.13, 1.54), 0.057, 0.09, "steel_black", segs=8, axis="Y")
    turret.cyl((0.04, 0.29, 1.58), 0.045, 0.04, "steel_black", segs=8, axis="Y")
    turret.slab(-0.21, -0.2, 1.22, -0.08, 0.08, 1.46, "brass", bevel=0.02)
    loop = Part()
    loop.ring_band((0, 0), 0.088, 0.15, -0.03, 0.03, 0, 360, "brass", segs=14)
    turret.add_part(loop, T(0.02, -0.34, 1.46) @ R("Y", 90))
    return [p, own_materials(turret, "turret")] + wheels



@model("locomotive")
def locomotive():
    """Factorio's locomotive, front north, from its 256 rotation frames (front and side views):
    a long riveted underframe on two bogies (+-2 tiles, joint_distance 4) carrying, from the back,
    a rear platform with the coupler, handrail and coiled brass hoses; a dark rear box with a
    grilled window each side; a rusty ribbed dome; the long light hood with its round hatch,
    seams and rivet rows, a ribbed tank down its west side and a louvred box down its east;
    the taller front machinery (a stack of small boxes and a long pipe west, a slatted grille,
    a radiator and two upright tanks with looping pipes east); the riveted nose with its
    whistle and headlights; and the V plough down to the rails."""
    p = Part()
    axles = []
    for y in (-2.0, 2.0):
        axles += bogie(p, y)
    # Underframe: riveted sills the full length, equipment hung between the bogies.
    p.slab(-0.96, -3.3, 0.95, 0.96, 3.3, 1.22, "steel_dark", bevel=0.04)
    for sx in (-1, 1):
        detail.rivet_line(p, (sx * 0.965, -3.3, 1.15), (sx * 0.965, 3.15, 1.15), 27, "X")
        p.cyl((sx * 0.62, -0.05, 0.74), 0.22, 1.9, "steel", segs=12, axis="Y", bevel=0.02)
        for y in (-0.7, 0.0, 0.7):
            p.cyl((sx * 0.62, y - 0.05, 0.74), 0.235, 0.06, "steel_dark", segs=12, axis="Y")
    p.pipe([(0.25, -1.1, 0.95), (0.25, -0.9, 0.55), (0.25, 0.9, 0.55), (0.25, 1.1, 0.95)], 0.07, "steel_black", segs=8)
    p.slab(-0.35, -0.6, 0.5, 0.05, 0.6, 0.95, "steel_black", bevel=0.04)

    # Rear platform: deck, coupler, handrail loop and the coiled hoses at the corners.
    # (Cars couple 7 tiles apart, so nothing reaches past 3.5 tiles from the middle.)
    p.slab(-0.9, -3.45, 1.12, 0.9, -3.1, 1.24, "steel_dark", bevel=0.03)
    p.slab(-0.2, -3.5, 0.5, 0.2, -3.25, 0.8, "steel_black", bevel=0.03)
    p.pipe([(-0.72, -3.2, 1.24), (-0.72, -3.45, 0.95), (0.72, -3.45, 0.95), (0.72, -3.2, 1.24)], 0.035, "steel_light",
           segs=6)
    for sx in (-1, 1):
        detail.spring(p, (sx * 0.62, -3.08, 1.85), (sx * 0.7, -3.42, 1.3), 0.06, "brass", turns=10, wire=0.018)
        p.cyl((sx * 0.62, -3.35, 1.0), 0.07, 0.2, "steel_black", segs=8, axis="Y")

    # Rear box: rounded top edges, a grilled window each side, a door panel on the back.
    rear = mirrored([(0.97, 1.22), (0.97, 1.75), (0.8, 2.05), (0.45, 2.18)])
    along_y(p, rear, -3.1, -1.55, "steel_dark", bevel=0.04)
    for sx in (-1, 1):
        lo, hi = (min(sx * 0.95, sx * 0.99), -2.95, 1.38), (max(sx * 0.95, sx * 0.99), -1.85, 1.82)
        p.slab(*lo, *hi, "steel_black")
        detail.slots(p, lo, hi, "+x" if sx > 0 else "-x", 5, mat="grime", depth=0.015)
        detail.rivet_line(p, (sx * 0.975, -3.0, 1.7), (sx * 0.975, -1.65, 1.7), 9, "X")
    detail.panel(p, (-0.8, -3.12, 1.3), (0.8, -3.1, 1.95), "-y", "steel", margin=0.08, rivet="steel_light")
    p.slab(-0.3, -2.95, 2.12, 0.3, -2.45, 2.33, "rust", bevel=0.05)
    detail.rivet_line(p, (-0.25, -2.7, 2.335), (0.25, -2.7, 2.335), 4, "Z")
    p.pipe([(-0.98, -3.0, 1.3), (-0.98, -2.8, 1.85), (-0.98, -2.0, 1.85), (-0.9, -1.75, 1.6)], 0.06, "steel_light", segs=8)

    # The rusty ribbed dome between the rear box and the hood, a brass hose down its west side.
    dome = mirrored([(0.45, 1.9), (0.45, 2.25), (0.33, 2.43), (0.12, 2.48)])
    along_y(p, dome, -1.85, -1.0, "rust", bevel=0.03)
    end_taper(p, dome, -1.85, -2.0, "rust", 1.9, 0.55)
    ribs = mirrored([(0.47, 1.95), (0.47, 2.27), (0.35, 2.45), (0.13, 2.5)])
    for y in (-1.7, -1.48, -1.26, -1.06):
        along_y(p, ribs, y - 0.025, y + 0.025, "steel_dark")
    detail.spring(p, (-0.48, -1.2, 2.25), (-0.62, -1.75, 1.55), 0.055, "brass", turns=10, wire=0.017)
    p.cyl((0.3, -1.95, 2.2), 0.09, 0.3, "steel_light", segs=8)

    # The long hood: light steel, rounded, with seams, rivet rows, a raised plate and the hatch.
    hood = mirrored([(0.66, 1.22), (0.66, 1.95), (0.55, 2.22), (0.3, 2.36)])
    along_y(p, hood, -1.55, 1.3, "steel", bevel=0.03)
    seam = mirrored([(0.675, 1.5), (0.675, 1.96), (0.56, 2.235), (0.305, 2.375)])
    for y in (-0.75, 0.62):
        along_y(p, seam, y - 0.02, y + 0.02, "steel_dark")
    for sx in (-1, 1):
        detail.rivet_line(p, (sx * 0.6, -1.45, 2.1), (sx * 0.6, 1.2, 2.1), 14, "Z")
        detail.rivet_line(p, (sx * 0.665, -1.45, 1.75), (sx * 0.665, 1.2, 1.75), 14, "X")
    p.cyl((0, 0.0, 2.37), 0.26, 0.06, "steel_dark", segs=20)
    p.cyl((0, 0.0, 2.41), 0.2, 0.06, "steel_light", segs=20, bevel=0.02)
    p.cyl((0, 0.0, 2.45), 0.05, 0.04, "steel_dark", segs=8)
    p.slab(-0.2, 0.42, 2.3, 0.2, 0.82, 2.4, "steel_dark", bevel=0.03)
    detail.rivet_line(p, (-0.15, 0.62, 2.405), (0.15, 0.62, 2.405), 3, "Z")
    # West side: a ribbed tank along the hood; east side: a louvred box.
    detail.ribbed_drum(p, (-0.8, -0.15, 1.5), 0.2, 2.3, "steel_dark", "steel", axis="Y", ribs=6, segs=12)
    p.slab(-0.97, -1.45, 1.22, -0.66, 1.25, 1.32, "steel_dark")
    lo, hi = (0.66, -1.35, 1.22), (0.95, 1.05, 1.88)
    p.slab(*lo, *hi, "steel_dark", bevel=0.03)
    detail.slots(p, lo, hi, "+x", 12, mat="grime", along=1, depth=0.015)
    detail.slots(p, lo, hi, "+z", 12, mat="grime", along=1, depth=0.012)

    # Front machinery, taller than the hood.
    p.slab(-0.97, 1.3, 1.22, 0.97, 2.95, 1.75, "steel_dark", bevel=0.04)
    p.slab(-0.5, 1.3, 1.75, 0.5, 2.95, 2.34, "steel", bevel=0.08)
    detail.panel(p, (-0.5, 1.3, 1.75), (0.5, 2.95, 2.34), "+z", "steel", margin=0.1, split=2)
    detail.rivet_line(p, (-0.42, 1.38, 2.36), (-0.42, 2.87, 2.36), 9, "Z")
    detail.rivet_line(p, (0.42, 1.38, 2.36), (0.42, 2.87, 2.36), 9, "Z")
    for k, y in enumerate((1.45, 1.8, 2.15, 2.5)):
        p.slab(-0.95, y, 1.75, -0.6, y + 0.28, 2.1 + 0.05 * (k % 2), "steel_black", bevel=0.03)
    p.pipe([(-0.97, 0.95, 1.4), (-0.97, 1.15, 1.95), (-0.97, 2.75, 1.95), (-0.9, 2.9, 1.6)], 0.06, "steel_light", segs=8)
    lo, hi = (-0.6, 2.05, 1.75), (-0.32, 2.6, 2.3)
    p.slab(*lo, *hi, "steel_dark", bevel=0.02)
    detail.slots(p, lo, hi, "+z", 5, mat="grime", along=0, depth=0.012)
    for y in (1.5, 2.65):
        p.cyl((0.72, y, 2.02), 0.21, 0.54, "steel", segs=14, bevel=0.03)
        p.sphere((0.72, y, 2.29), 0.21, "steel", segs=14, rings=4, hemisphere=True, scale=(1, 1, 0.45))
        p.cyl((0.72, y, 1.95), 0.225, 0.05, "steel_dark", segs=14)
    lo, hi = (0.48, 1.8, 1.75), (0.96, 2.35, 2.3)
    p.slab(*lo, *hi, "steel_dark", bevel=0.03)
    detail.slots(p, lo, hi, "+z", 5, mat="grime", along=0, depth=0.012)
    detail.slots(p, lo, hi, "+x", 5, mat="grime", along=0, depth=0.012)
    p.pipe([(0.55, 2.7, 2.35), (0.35, 2.55, 2.42), (0.35, 1.75, 2.42), (0.55, 1.55, 2.3)], 0.055, "steel_light", segs=8)
    p.pipe([(0.95, 1.3, 1.7), (0.98, 1.0, 1.4)], 0.05, "steel_light", segs=6)

    # Nose: a riveted cap narrowing forward, its top sloping down, the whistle on top.
    nose = Part()
    outline = [(-0.97, 2.95), (0.97, 2.95), (0.97, 3.15), (0.6, 3.45), (-0.6, 3.45), (-0.97, 3.15)]
    nose.prism(outline, 1.22, 2.34, "steel_dark", bevel=0.04)
    nose.warp(lambda co: (co.x * (1.0 - 0.55 * max(0.0, co.z - 1.9) / 0.44), co.y,
                           co.z if co.z < 1.5 or co.y < 3.0 else co.z - (co.y - 3.0) * 1.5))
    p.add_part(nose)
    detail.rivet_line(p, (-0.85, 3.0, 2.35), (0.85, 3.0, 2.35), 9, "Z")
    detail.rivet_line(p, (-0.5, 3.4, 1.7), (0.5, 3.4, 1.7), 6, "Z")
    p.cyl((0, 3.1, 2.3), 0.06, 0.12, "steel", segs=10)
    p.sphere((0, 3.1, 2.36), 0.06, "steel_light", segs=10, rings=4)
    for sx in (-1, 1):
        p.cyl((sx * 0.6, 3.36, 1.68), 0.1, 0.1, "steel_light", segs=10, axis="Y")
        p.cyl((sx * 0.6, 3.41, 1.68), 0.075, 0.02, "glass", segs=10, axis="Y")
    # The dark slatted grille across the nose's foot, between and under the headlights.
    lo, hi = (-0.45, 3.42, 1.24), (0.45, 3.47, 1.6)
    p.slab(*lo, *hi, "steel_black")
    detail.slots(p, lo, hi, "+y", 7, mat="grime", along=1, depth=0.012)
    # V plough down to the rails, ribbed.
    plough = Part()
    plough.side_prism([(3.25, 0.12), (3.66, 0.12), (3.48, 1.22), (3.25, 1.22)], -0.95, 0.95, "steel_black", bevel=0.03)
    plough.warp(lambda co: (co.x, co.y - abs(co.x) * 0.36 if co.y > 3.3 else co.y, co.z))
    p.add_part(plough)
    for sx in (-1, 1):
        for k in range(3):
            x = sx * (0.2 + 0.3 * k)
            p.beam((x, 3.63 - abs(x) * 0.36, 0.2), (x, 3.46 - abs(x) * 0.36, 1.15), 0.05, 0.03, "steel",
                   up=(0, 1, 0.2))
    return [p] + axles


def end_taper(p, section, y0, y1, mat, z_pivot, keep):
    """An end piece of a long body: `section` extruded from y0 to y1, its far end squashed
    towards z_pivot by `keep` (0..1), so the roof slopes down to the buffer beam."""
    piece = Part()
    along_y(piece, section, min(y0, y1), max(y0, y1), mat)
    piece.warp(lambda co: (co.x, co.y, co.z if abs(co.y - y0) < 1e-4 else z_pivot + (co.z - z_pivot) * keep))
    p.add_part(piece)


def buffers(p, y_end):
    """Coupler box and buffer beam at one end (y_end is the outer face, sign gives the end)."""
    sy = 1 if y_end > 0 else -1
    p.slab(-0.85, y_end - sy * 0.25, 0.75, 0.85, y_end - sy * 0.02, 1.0, "steel_dark", bevel=0.03)
    p.slab(-0.22, y_end - sy * 0.3, 0.55, 0.22, y_end + sy * 0.05, 0.85, "steel_black", bevel=0.03)


def planks(p, a, b, y0, y1, count, mat, out=0.025, gap=0.025):
    """`count` planks running along y from y0 to y1, laid side by side across the face from
    a to b (two (x, z) points of a cross-section), standing `out` proud of it."""
    ax, az = a
    dx, dz = b[0] - ax, b[1] - az
    length = math.hypot(dx, dz)
    nx, nz = dz / length, -dx / length
    if nx * (ax + dx / 2) + nz * (az + dz / 2) < 0:   # the normal points away from the axis
        nx, nz = -nx, -nz
    w = length / count
    for k in range(count):
        t = (k + 0.5) / count
        cx, cz = ax + dx * t + nx * out / 2, az + dz * t + nz * out / 2
        p.beam((cx, y0, cz), (cx, y1, cz), w - gap, out, mat, up=(nx, 0, nz))


CARGO_SECTION = mirrored([(1.0, 1.1), (1.0, 1.45), (0.42, 2.15)])
CARGO_BAND = mirrored([(1.03, 1.08), (1.03, 1.47), (0.44, 2.19)])


@model("cargo-wagon")
def cargo_wagon():
    """Factorio's cargo wagon: a long box van in three bays, centred on the vehicle's position
    (its sprite is, though the selection box is off centre). Each bay is planked: planks run
    along the wagon on the narrow roof, the steep chamfers and the vertical sides, held by two
    straps round the bay; riveted steel frames stand between the bays and at the ends, a rail
    runs along each side where the chamfer meets it, and a lamp shines at each corner of the
    roof. The roof slopes down at both ends to the buffer beams, a small box on each end; the
    floor hangs lower between the bogies (at +-2)."""
    p = Part()
    axles = []
    for y in (-2.0, 2.0):
        axles += bogie(p, y)
    # The dark carcass the planks lie on, so the gaps between them read dark.
    along_y(p, CARGO_SECTION, -3.0, 3.0, "steel_dark", bevel=0.02)
    for sy in (-1, 1):
        end_taper(p, CARGO_SECTION, sy * 3.0, sy * 3.38, "steel", 1.15, 0.45)
        buffers(p, sy * 3.42)
        # The end door: a riveted box standing out of the sloping end.
        lo, hi = (-0.34, min(sy * 3.0, sy * 3.42), 1.12), (0.34, max(sy * 3.0, sy * 3.42), 1.8)
        p.slab(*lo, *hi, "steel_dark", bevel=0.04)
        detail.panel(p, lo, hi, "+y" if sy > 0 else "-y", "steel", margin=0.07, rivet="steel_light")
        detail.panel(p, lo, hi, "+z", "steel", margin=0.06)
    along_y(p, mirrored([(0.92, 0.82), (0.96, 0.98)]), -1.05, 1.05, "steel_dark", bevel=0.03)
    # Three planked bays.
    for k in range(3):
        y0, y1 = -2.96 + k * 2.0, -1.08 + k * 2.0
        planks(p, (0.4, 2.15), (-0.4, 2.15), y0, y1, 5, "paint_grey")
        for sx in (-1, 1):
            planks(p, (sx * 1.0, 1.47), (sx * 0.43, 2.14), y0, y1, 4, "paint_grey")
            planks(p, (sx * 1.0, 1.12), (sx * 1.0, 1.43), y0, y1, 2, "paint_grey")
        for y in (y0 + 0.42, y1 - 0.42):
            along_y(p, CARGO_BAND, y - 0.035, y + 0.035, "steel_dark")
    # Riveted frames between the bays and at the ends, rails along the sides.
    frame = mirrored([(1.05, 1.02), (1.05, 1.49), (0.45, 2.21)])
    for y in (-3.0, -1.02, 1.02, 3.0):
        along_y(p, frame, y - 0.05, y + 0.05, "steel")
        for sx in (-1, 1):
            detail.rivet_line(p, (sx * 1.055, y, 1.12), (sx * 1.055, y, 1.42), 2, "X")
            detail.rivet_line(p, (sx * 0.98, y, 1.62), (sx * 0.62, y, 2.06), 3, "Z")
    for sx in (-1, 1):
        p.beam((sx * 1.04, -3.0, 1.45), (sx * 1.04, 3.0, 1.45), 0.07, 0.06, "steel", up=(sx, 0, 0))
        p.beam((sx * 1.03, -3.0, 1.08), (sx * 1.03, 3.0, 1.08), 0.07, 0.05, "steel", up=(sx, 0, 0))
        detail.rivet_line(p, (sx * 1.065, -2.9, 1.08), (sx * 1.065, 2.9, 1.08), 24, "X")
        for sy in (-1, 1):
            p.sphere((sx * 0.42, sy * 3.0, 2.2), 0.05, "ceramic", segs=8, rings=4)
    return [p] + axles


@model("infinity-cargo-wagon")
def infinity_cargo_wagon():
    """Factorio's infinity cargo wagon (an editor wagon that refills itself): the cargo wagon,
    its picture tinted (0.5, 0.5, 1) as the prototype does, which turns the grey van violet
    blue. Its own materials, so the part colours sample the tinted sprite."""
    parts = cargo_wagon()
    for part in parts:
        tinted(part, "infinity", (0.5, 0.5, 1.0))
    return parts


def tinted(part, suffix, tint):
    """Renames the part's materials to `<name>_<suffix>`, their colours multiplied by `tint`
    (Factorio's layer tint, sRGB), emission left as it is."""
    names = []
    for name in part.mats:
        hex_colour, rough, metal, emit, strength = kit.MATERIALS[name]
        rgb = [int(hex_colour[i:i + 2], 16) * tint[i // 2] for i in (0, 2, 4)]
        new = "%s_%s" % (name, suffix)
        kit.MATERIALS.setdefault(new, ("%02x%02x%02x" % tuple(round(c) for c in rgb), rough, metal, emit, strength))
        names.append(new)
    part.mats = names
    return part


@model("fluid-wagon")
def fluid_wagon():
    """Factorio's fluid wagon: three squat round tanks with domed tops, riveted round the dome's
    foot and seamed down their sides, each with a bolted hatch strapped to the cage; they stand
    on a flat underframe inside a rusty cage whose two top rails run over the tanks, a waist rail
    along each side, posts with V braces between the tanks and splayed end frames; pipes and
    valves run between the tanks under the cage. Centred on the vehicle's position like its
    sprite, bogies at +-2."""
    p = Part()
    axles = []
    for y in (-2.0, 2.0):
        axles += bogie(p, y)
    # Underframe sills, with the pipe run and pumps hanging lower in the middle.
    p.slab(-0.95, -3.05, 0.85, 0.95, 3.05, 1.05, "steel_dark", bevel=0.03)
    for sx in (-1, 1):
        detail.rivet_line(p, (sx * 0.955, -2.95, 0.95), (sx * 0.955, 2.95, 0.95), 24, "X")
    # Valves and pipework filling the gaps between the tanks.
    for y in (-0.98, 0.98):
        p.slab(-0.72, y - 0.2, 1.0, 0.72, y + 0.2, 1.75, "steel_dark", bevel=0.04)
        for sx in (-1, 1):
            p.cyl((sx * 0.55, y, 1.35), 0.14, 0.7, "steel", segs=8, axis="Y")
            p.cyl((sx * 0.55, y, 1.35), 0.17, 0.08, "steel_dark", segs=8, axis="Y")
            p.cyl((sx * 0.72, y, 1.2), 0.07, 0.12, "rust_brown", segs=8, axis="X")
    p.cyl((0, 0, 0.75), 0.12, 4.2, "steel", segs=10, axis="Y")
    for y in (-1.0, 1.0):
        p.cyl((0, y, 0.82), 0.24, 0.5, "steel_dark", segs=10)
    for sy in (-1, 1):
        buffers(p, sy * 3.18)
    # The tanks: squat round drums with domed top and bottom, nearly touching, a flange round
    # the waist, rivets round the dome's foot and across it, seams down the sides, a hatch on top.
    for y in (-1.97, 0.0, 1.97):
        p.cyl((0, y, 1.4), 0.92, 0.7, "tank_white", segs=24)
        p.sphere((0, y, 1.75), 0.92, "tank_white", segs=24, rings=8, hemisphere=True, scale=(1, 1, 0.56))
        p.sphere((0, y, 1.05), 0.92, "tank_white", segs=24, rings=8, hemisphere=True, scale=(1, 1, -0.5))
        p.cyl((0, y, 1.42), 0.95, 0.06, "steel_dark", segs=24)
        p.cyl((0, y, 1.76), 0.935, 0.04, "steel", segs=24)
        for k in range(18):
            a = 2 * math.pi * (k + 0.5) / 18
            p.bolt((0.93 * math.cos(a), y + 0.93 * math.sin(a), 1.8), "steel_light", radius=0.024, axis="Z")
        for k in range(12):
            a = 2 * math.pi * (k + 0.5) / 12
            p.bolt((0.6 * math.cos(a), y + 0.6 * math.sin(a), 2.15), "steel_light", radius=0.022, axis="Z")
        for k in range(6):
            a = 2 * math.pi * k / 6 + 0.3
            p.beam((0.925 * math.cos(a), y + 0.925 * math.sin(a), 1.08), (0.925 * math.cos(a), y + 0.925 * math.sin(a), 1.74),
                   0.025, 0.015, "steel", up=(math.cos(a), math.sin(a), 0))
        # Hatch: a flange, the bolted lid, its boss and a lever strapped out to the cage.
        p.cyl((0, y, 2.27), 0.3, 0.06, "steel_dark", segs=16, bevel=0.02)
        p.cyl((0, y, 2.32), 0.21, 0.08, "steel", segs=16, bevel=0.02)
        p.bolts_ring((0, y, 2.36), 0.16, 8, "steel_light", radius=0.02)
        p.cyl((0, y, 2.38), 0.08, 0.08, "steel_dark", segs=10)
        p.cyl((0, y, 2.42), 0.045, 0.04, "steel_light", segs=8)
        p.beam((0.18, y + 0.1, 2.33), (0.5, y + 0.28, 2.2), 0.08, 0.035, "rust_brown")
        p.beam((-0.25, y - 0.12, 2.3), (-0.72, y - 0.12, 2.32), 0.07, 0.03, "rust_brown")
    # Cage: top rails over the tanks, a waist rail along each side, posts with V braces between
    # the tanks, splayed end frames with a cross beam.
    for sx in (-1, 1):
        p.beam((sx * 0.72, -3.0, 2.34), (sx * 0.72, 3.0, 2.34), 0.08, 0.08, "rust_brown", bevel=0.01)
        p.beam((sx * 0.96, -3.08, 1.55), (sx * 0.96, 3.08, 1.55), 0.07, 0.06, "rust_brown")
        for y in (-0.98, 0.98):
            p.beam((sx * 0.96, y, 1.0), (sx * 0.96, y, 1.6), 0.08, 0.08, "rust_brown", up=(0, 1, 0))
            p.beam((sx * 0.96, y, 1.58), (sx * 0.72, y, 2.36), 0.08, 0.07, "rust_brown", up=(0, 1, 0))
            for sy in (-1, 1):
                p.beam((sx * 0.96, y, 1.55), (sx * 0.72, y + sy * 0.42, 2.34), 0.05, 0.05, "rust_brown", up=(0, 1, 0))
        for sy in (-1, 1):
            y = sy * 3.06
            p.beam((sx * 0.96, y, 1.0), (sx * 0.96, y, 1.6), 0.08, 0.08, "rust_brown", up=(0, 1, 0))
            p.beam((sx * 0.96, y, 1.58), (sx * 0.72, sy * 3.0, 2.36), 0.08, 0.07, "rust_brown", up=(0, 1, 0))
            p.beam((sx * 0.3, y, 1.05), (sx * 0.72, sy * 3.0, 2.3), 0.06, 0.06, "rust_brown", up=(0, 1, 0))
    for sy in (-1, 1):
        p.beam((-0.76, sy * 3.0, 2.34), (0.76, sy * 3.0, 2.34), 0.08, 0.08, "rust_brown", bevel=0.01)
        p.beam((-0.96, sy * 3.06, 1.55), (0.96, sy * 3.06, 1.55), 0.07, 0.06, "rust_brown")
    return [p] + axles
