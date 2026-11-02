"""Military, Nauvis mid and late game: laser, flamethrower and artillery turrets, land mine, tank,
spidertron, artillery wagon and the three combat robots.

Each model is matched to Factorio's HR sprite with compare.py (client/assets/models/README.md,
"Matching a sprite"). Turret heads and the tank's turret are `anim_turret_head` parts, pivot on
their axis, barrels north at rest, as on the gun turret.
"""

import math

from mathutils import Vector

import detail
import kit
from kit import Part, R, S, T, model
from vehicles import along_y, bogie, buffers, mirrored, own_materials

# Colours picked against the sprites of the models below.
kit.MATERIALS.update({
    "paint_white": ("d6d3c9", 0.55, 0.3, None, 0),       # laser turret head, defender dome
    "rust_dark": ("4c3426", 0.85, 0.4, None, 0),         # tank hull, flamethrower plates
    "steel_spider": ("9a9d9c", 0.45, 0.75, None, 0),     # spidertron shell, destroyer dome
    "paint_green_pale": ("9db88e", 0.5, 0.3, None, 0),  # laser turret capacitor
    "paint_ochre": ("c39a4a", 0.6, 0.35, None, 0),       # laser turret middle
    "lamp_cyan": ("6ff0e8", 0.4, 0.0, "40e0ff", 1.2),    # robot leg lights
    "lamp_orange": ("ffb040", 0.4, 0.0, "ff9a20", 1.5),  # flamethrower pilot light
    # The artillery's hazard yellow is stronger than the kit's, which weathers to cream.
    "hazard_strong": ("ecb20c", 0.55, 0.3, None, 0),
})


def octagon(r, turn=22.5):
    return [(r * math.cos(math.radians(turn + 45 * i)), r * math.sin(math.radians(turn + 45 * i))) for i in range(8)]


def ring_of(n, r, start=0.0):
    return [(r * math.cos(math.radians(start + 360.0 * i / n)), r * math.sin(math.radians(start + 360.0 * i / n)))
            for i in range(n)]


# ---------------------------------------------------------------------------------------------
# Turrets.

@model("laser-turret")
def laser_turret():
    """Factorio's laser turret. The base is an open stand: four ladder legs, two rails and their
    rungs, slope down from a dark hub to feet out at the corners (from the south the far two look
    level and the near two steep, as in the sprite), an orange and a green capacitor sticking out
    west and east, black cables looping round on the ground. The head (`anim_turret_head`) is a
    swivel block on the hub, a dark arm up and back, and the long gun high above: a white rear
    block with three slots a side, the rusty orange middle, the white front block and a
    three-pronged emitter at the muzzle, a cable from its back down to the swivel."""
    p = Part()
    zt = 0.45
    zh = 0.75
    # Hub: a dark drum with a rim, the swivel's socket in its top.
    p.cyl((0, 0, zh - 0.2), 0.22, 0.4, "rust_dark", segs=12, bevel=0.02)
    p.ring_band((0, 0), 0.18, 0.27, zh - 0.06, zh + 0.02, 0, 360, "steel", segs=12)
    p.cyl((0, 0, zh), 0.18, 0.01, "soot", segs=12)
    # Legs: ladders from the hub's rim down to feet out at the corners. The far two splay wide to
    # the east and west and stand on raised pads, the near two reach in steeply to the south.
    for fx, fy, fz in ((0.78, 0.62, 0.1), (-0.78, 0.62, 0.1), (0.5, -0.55, 0.05), (-0.5, -0.55, 0.05)):
        r = math.atan2(fy, fx)
        c, s_ = math.cos(r), math.sin(r)
        tc, ts = -s_, c
        top = Vector((0.24 * c, 0.24 * s_, zh - 0.02))
        foot = Vector((fx, fy, fz))
        rails = []
        for k in (-1, 1):
            a0 = top + Vector((tc, ts, 0)) * (k * 0.1)
            a1 = foot + Vector((tc, ts, 0)) * (k * 0.2)
            p.beam(a0, a1, 0.08, 0.045, "steel_light", up=(c, s_, 1.0), bevel=0.01)
            p.bolt((a0.x, a0.y, a0.z + 0.03), "rust_brown", radius=0.03)
            rails.append((a0, a1))
        for t in (0.35, 0.68):
            q0 = rails[0][0].lerp(rails[0][1], t)
            q1 = rails[1][0].lerp(rails[1][1], t)
            p.beam(q0, q1, 0.05, 0.035, "steel_dark")
        for k in (-1, 1):
            q = foot + Vector((tc, ts, 0)) * (k * 0.2)
            p.box((q.x, q.y, fz / 2 + 0.02), (0.09, 0.09, fz + 0.04), "steel_black", bevel=0.015)
            p.bolt((q.x, q.y, fz + 0.05), "rust_brown", radius=0.03)
    # Capacitors sticking out of the hub: orange west, green east.
    for sx, mat in ((-1, "copper_dull"), (1, "paint_green_pale")):
        p.cyl((sx * 0.42, 0.08, 0.42), 0.11, 0.3, mat, segs=12, axis="X", bevel=0.02)
        for x in (0.28, 0.56):
            p.cyl((sx * x, 0.08, 0.42), 0.13, 0.04, "steel_light", segs=12, axis="X", bevel=0.01)
        p.cyl((sx * 0.6, 0.08, 0.42), 0.08, 0.05, "rust_brown", segs=10, axis="X")
    # Cables looping round on the ground, in front between the near legs as in the sprite.
    for sx in (-1, 1):
        p.pipe([(sx * 0.5, 0.08, 0.32), (sx * 0.62, -0.1, 0.08), (sx * 0.4, -0.5, 0.05), (0.0, -0.58, 0.05),
                (-sx * 0.3, -0.4, 0.06), (-sx * 0.12, -0.15, 0.25)], 0.035, "rubber", segs=6)
    # Low frame: beams on the ground from foot to foot round the stand (the sprite's outline).
    feet = [(0.78, 0.62), (0.5, -0.55), (-0.5, -0.55), (-0.78, 0.62)]
    for (ax, ay), (bx, by) in zip(feet, feet[1:] + feet[:1]):
        p.beam((ax, ay, 0.1), (bx, by, 0.1), 0.07, 0.06, "steel_dark")
    # The stand sized to the sprite (tools/models/fit_cells.py --fit scale,shift): a little
    # longer north-south and taller; the head stays on its axis.
    p.transform(T(0, 0.043, 0) @ S(0.972, 1.087, 1.032))

    head = Part("anim_turret_head", pivot=(0.0, 0.0, zt))
    # Swivel: two rusty white blocks on the socket.
    head.slab(-0.22, -0.24, zt + 0.02, 0.22, 0.2, zt + 0.3, "paint_white", bevel=0.03)
    head.cyl((0, -0.02, zt + 0.5), 0.12, 0.4, "steel_dark", segs=10)
    head.slab(-0.17, -0.3, zt + 0.66, 0.17, 0.12, zt + 0.92, "paint_white", bevel=0.03)
    for x in (-0.23, 0.23):
        head.bolt((x, -0.05, zt + 0.14), "rust_brown", radius=0.035, axis="X")
    gz = 2.25
    # Arm up and back to the gun's belly.
    head.beam((0, -0.05, zt + 0.85), (0, -0.25, gz - 0.24), 0.2, 0.14, "steel_dark", up=(0, 1, 0), bevel=0.02)
    head.slab(-0.15, -0.5, gz - 0.33, 0.15, -0.16, gz - 0.2, "paint_white", bevel=0.02)
    # Rear block with three slots a side.
    head.slab(-0.27, -0.6, gz - 0.24, 0.27, -0.1, gz + 0.24, "paint_white", bevel=0.05)
    for sx in (-1, 1):
        for k in range(3):
            y = -0.5 + k * 0.14
            head.slab(sx * 0.265, y - 0.04, gz - 0.15, sx * 0.285, y + 0.04, gz + 0.17, "soot")
        for z in (gz - 0.15, gz + 0.13):
            head.bolt((sx * 0.28, -0.57, z), "rust_brown", radius=0.035, axis="X")
    for k in range(3):
        head.slab(-0.14 + k * 0.11, -0.5, gz + 0.235, -0.09 + k * 0.11, -0.2, gz + 0.255, "soot")
    # Rusty orange middle, a little slimmer.
    head.slab(-0.21, -0.12, gz - 0.19, 0.21, 0.28, gz + 0.19, "paint_ochre", bevel=0.03)
    head.slab(-0.22, 0.04, gz - 0.2, 0.22, 0.1, gz + 0.2, "rust_brown")
    # Front block, with a small box on its east side.
    head.slab(-0.25, 0.26, gz - 0.24, 0.25, 0.58, gz + 0.24, "paint_white", bevel=0.05)
    head.slab(0.24, 0.0, gz - 0.05, 0.36, 0.22, gz + 0.18, "paint_ochre", bevel=0.02)
    # Emitter: three prongs closing in on the muzzle.
    for a in (90, 210, 330):
        r = math.radians(a)
        c, s = math.cos(r), math.sin(r)
        head.beam((0.16 * c, 0.56, gz + 0.16 * s), (0.08 * c, 0.8, gz + 0.08 * s), 0.05, 0.05, "steel_black")
        head.box((0.075 * c, 0.8, gz + 0.075 * s), (0.07, 0.07, 0.07), "rust_brown")
    head.cyl((0, 0.62, gz), 0.07, 0.1, "steel_dark", segs=8, axis="Y")
    # Cable from the back of the gun down to the swivel.
    head.pipe([(-0.12, -0.61, gz - 0.08), (-0.3, -0.85, gz - 0.45), (-0.34, -0.6, zt + 0.9), (-0.17, -0.3, zt + 0.75)],
              0.04, "rubber", segs=6)
    return [p, head]


@model("flamethrower-turret")
def flamethrower_turret():
    """Factorio's flamethrower turret, 2x3, facing north: a fat pipe across its south end with
    flanged ends (the fluid inputs) and the pump box on it, its grille and hand wheel to the
    south; pipes and hoses from the pump up to a rusty three-armed mount (two legs sloping down
    to feet near the north corners, a stem back to the pump), where the gun turns
    (`anim_turret_head`): a riveted grey drum with a perforated muzzle, the orange pilot light
    on top and a coiled hose under its back."""
    p = Part()
    # The pipe across the south end.
    py, pz = -1.12, 0.37
    p.cyl((0, py, pz), 0.34, 1.9, "olive_steel", segs=18, axis="X", bevel=0.03)
    for sx in (-1, 1):
        p.cyl((sx * 0.92, py, pz), 0.38, 0.08, "steel_dark", segs=18, axis="X", bevel=0.02)
        p.bolts_ring((sx * 0.97, py, pz), 0.31, 8, "rust_brown", radius=0.025, axis="X", start=22.5)
    for x in (-0.55, 0.55):
        p.cyl((x, py, pz), 0.35, 0.04, "rust_brown", segs=18, axis="X")
    # Pump box on the pipe, grille and hand wheel facing south.
    p.prism([(-0.5, -1.78), (0.5, -1.78), (0.42, -0.85), (-0.42, -0.85)], 0.0, 0.64, "steel_dark", bevel=0.05)
    p.slab(-0.42, -1.78, 0.08, 0.42, -1.72, 0.5, "steel", bevel=0.01)
    p.slab(-0.24, -1.81, 0.18, 0.0, -1.76, 0.34, "soot")
    p.cyl((0.22, -1.8, 0.26), 0.11, 0.03, "steel_light", segs=10, axis="Y")
    p.beam((0.12, -1.82, 0.26), (0.32, -1.82, 0.26), 0.02, 0.02, "steel_light")
    p.beam((0.22, -1.82, 0.16), (0.22, -1.82, 0.36), 0.02, 0.02, "steel_light")
    p.slab(-0.4, -1.4, 0.62, 0.4, -0.85, 0.72, "rust_dark", bevel=0.03)
    p.slab(-0.25, -1.3, 0.72, 0.25, -0.95, 0.78, "steel_dark", bevel=0.02)
    for x in (-0.42, 0.42):
        for z in (0.14, 0.56):
            p.bolt((x, -1.75, z), "steel_light", radius=0.03, axis="Y")
    # Feeds from the pump to the mount: two pipes with elbows and a bundle of hoses.
    for sx in (-1, 1):
        p.pipe([(sx * 0.2, -0.8, 0.8), (sx * 0.22, -0.4, 0.75), (sx * 0.16, 0.0, 0.7)], 0.09, "steel", segs=8)
        p.cyl((sx * 0.21, -0.55, 0.77), 0.11, 0.06, "steel_dark", segs=8, axis="Y")
    for k, x in enumerate((-0.07, 0.0, 0.07)):
        p.pipe([(x, -0.9, 0.8), (x * 2.5, -0.4, 0.62 + 0.03 * k), (x, 0.05, 0.7)], 0.035, "rubber", segs=6)
    # The three-armed mount: two legs sloping down to bolted feet near the north corners, a
    # stem back to the pump.
    my, mz = 0.3, 0.86
    p.cyl((0, my, mz / 2), 0.22, mz, "rust_dark", segs=12, bevel=0.03)
    for sx in (-1, 1):
        top = Vector((sx * 0.15, my + 0.05, mz - 0.06))
        foot = Vector((sx * 0.74, 1.05, 0.14))
        p.beam(top, foot, 0.3, 0.13, "rust_dark", up=(0, 0, 1), bevel=0.02)
        p.slab(foot.x - 0.17, foot.y - 0.16, 0.0, foot.x + 0.17, foot.y + 0.16, 0.16, "steel_dark", bevel=0.03)
        for k in (-1, 1):
            p.bolt((foot.x + k * 0.09, foot.y, 0.17), "steel_light", radius=0.03)
    root = Vector((0, my, 0))
    end = Vector((0.0, -0.4, 0))
    d = (end - root).normalized()
    side = Vector((-d.y, d.x, 0)) * 0.26
    pts = [root - side, end - side * 0.55, end + side * 0.55, root + side]
    p.prism([(v.x, v.y) for v in pts], mz - 0.12, mz, "rust_dark", bevel=0.02)
    p.beam((end.x, end.y, mz - 0.06), (end.x, end.y - 0.2, 0.3), 0.3, 0.12, "rust_dark", bevel=0.02)
    p.prism(octagon(0.3), mz - 0.1, mz + 0.03, "rust_dark", bevel=0.02, matrix=T(0, my, 0))

    head = Part("anim_turret_head", pivot=(0.0, 0.19, mz))
    hz = 1.3
    head.cyl((0, 0.19, mz + 0.12), 0.18, 0.22, "steel_dark", segs=10)
    head.slab(-0.14, -0.05, mz + 0.18, 0.14, 0.4, hz - 0.12, "steel_dark", bevel=0.03)
    # Drum body along the barrel.
    head.cyl((0, 0.45, hz), 0.25, 1.0, "steel_light", segs=14, axis="Y", bevel=0.03)
    for y in (0.0, 0.3, 0.62, 0.93):
        head.cyl((0, y, hz), 0.265, 0.05, "steel_dark", segs=14, axis="Y")
    for y in (0.15, 0.78):
        for k in range(10):
            a = math.radians(k * 36)
            head.bolt((0.26 * math.cos(a), y, hz + 0.26 * math.sin(a)), "rust_brown", radius=0.022, axis="Y")
    head.slab(-0.12, 0.35, hz + 0.24, 0.12, 0.6, hz + 0.3, "steel_dark", bevel=0.01)
    # Perforated muzzle.
    head.cyl((0, 1.12, hz), 0.2, 0.36, "steel_dark", segs=12, axis="Y")
    head.cyl((0, 1.3, hz), 0.14, 0.02, "soot", segs=10, axis="Y")
    for k in range(6):
        a = math.radians(k * 60 + 30)
        head.cyl((0.2 * math.cos(a), 1.12, hz + 0.2 * math.sin(a)), 0.05, 0.24, "soot", segs=6, axis="Y")
    # Pilot light and its bracket.
    head.cyl((0, 1.18, hz + 0.27), 0.065, 0.12, "lamp_orange", segs=8)
    head.cyl((0, 1.18, hz + 0.22), 0.075, 0.04, "brass", segs=8)
    # Back end and the hose coil down to the mount.
    head.cyl((0, -0.1, hz), 0.2, 0.14, "steel_dark", segs=12, axis="Y")
    coil = []
    for k in range(13):
        t = k / 12
        a = t * 4 * math.pi
        coil.append((0.2 * math.cos(a), -0.15 - 0.12 * t + 0.05 * math.sin(a), hz - 0.15 - (hz - mz - 0.2) * t))
    head.pipe(coil, 0.04, "rubber", segs=6, joints=False)
    return [p, head]


@model("land-mine")
def land_mine():
    """Factorio's land mine, lying flat: a rusty ring with square tabs all round its rim, bent
    up and out like a crown, a low grey drum in the middle with a cross-hatched pressure plate
    on top."""
    p = Part()
    p.cyl((0, 0, 0.035), 0.3, 0.07, "rust_brown", segs=24, bevel=0.015)
    for k in range(14):
        a = math.radians(k * 360 / 14 + 8)
        c, s_ = math.cos(a), math.sin(a)
        p.beam((0.24 * c, 0.24 * s_, 0.06), (0.43 * c, 0.43 * s_, 0.22), 0.13, 0.035, "rust_light",
               up=(-c, -s_, 0.8))
    # The grey drum slopes up over the tabs' roots to a groove round the plate.
    p.cyl((0, 0, 0.13), 0.37, 0.1, "stone_dark", segs=24, radius_top=0.25, bevel=0.01)
    p.cyl((0, 0, 0.19), 0.23, 0.02, "soot", segs=20)
    p.cyl((0, 0, 0.22), 0.2, 0.05, "rust", segs=20, bevel=0.01)
    for k in range(-4, 5):
        for turn in (45, -45):
            p.box((0.034 * k, 0, 0.248), (0.014, 0.3 - abs(k) * 0.05, 0.012), "rust_brown", matrix=R("Z", turn))
    # Fitted to the sprite (tools/models/fit_cells.py --fit scale): a little wider and taller,
    # shorter north-south (overlap 0.875 -> 0.91).
    p.transform(T(0.01, 0.005, 0) @ S(1.032, 0.907, 1.067))
    return p


def artillery_cannon(pivot, z_ring, head_name="anim_turret_head", barrel=3.5, elevation=25.0, scale=1.0):
    """The artillery cannon shared by the turret and the wagon: a slewing ring with red lights,
    a tall dark machinery block with the trunnions and gear boxes either side, the breech, and
    a long barrel in three steps with a slotted sleeve near its root, raised `elevation`
    degrees, pointing north."""
    px, py = pivot
    k = scale
    h = Part(head_name, pivot=(px, py, z_ring))
    h.ring_band((px, py), 0.62 * k, 0.8 * k, z_ring, z_ring + 0.12, 0, 360, "steel", segs=24, bevel=0.01)
    for a in (160, 200, 340, 20):
        r = math.radians(a)
        h.sphere((px + 0.78 * k * math.cos(r), py + 0.78 * k * math.sin(r), z_ring + 0.14), 0.04, "lamp_red", segs=6,
                 rings=3)
    h.cyl((px, py, z_ring + 0.2), 0.62 * k, 0.16, "steel_dark", segs=20)
    # Machinery: the cradle block, side gear boxes, pipes, the breech housing behind.
    zc = z_ring + 0.85 * k
    h.slab(px - 0.36 * k, py - 0.5 * k, z_ring + 0.25, px + 0.36 * k, py + 0.3 * k, zc + 0.2 * k, "steel_dark", bevel=0.06)
    h.slab(px - 0.3 * k, py - 0.62 * k, z_ring + 0.3, px + 0.3 * k, py - 0.2 * k, zc - 0.1 * k, "steel", bevel=0.05)
    for sx in (-1, 1):
        h.cyl((px + sx * 0.42 * k, py - 0.05 * k, zc), 0.22 * k, 0.14 * k, "steel", segs=12, axis="X", bevel=0.02)
        h.cyl((px + sx * 0.5 * k, py - 0.05 * k, zc), 0.1 * k, 0.06 * k, "steel_light", segs=8, axis="X")
        h.slab(px + sx * 0.3 * k, py - 0.55 * k, z_ring + 0.3, px + sx * 0.6 * k, py - 0.15 * k, zc - 0.25 * k,
               "steel_black", bevel=0.03)
        h.pipe([(px + sx * 0.3 * k, py - 0.5 * k, zc + 0.15 * k), (px + sx * 0.52 * k, py - 0.68 * k, zc - 0.15 * k),
                (px + sx * 0.58 * k, py - 0.45 * k, z_ring + 0.35)], 0.04 * k, "steel_light", segs=6)
    h.slab(px - 0.2 * k, py - 0.78 * k, zc - 0.25 * k, px + 0.2 * k, py - 0.35 * k, zc + 0.25 * k, "steel", bevel=0.04)
    h.sphere((px + 0.3 * k, py - 0.45 * k, zc + 0.32 * k), 0.12 * k, "steel_light", segs=8, rings=4)
    h.cyl((px - 0.18 * k, py - 0.3 * k, zc + 0.3 * k), 0.08 * k, 0.2 * k, "steel_dark", segs=8)
    # Barrel, raised.
    e = math.radians(elevation)
    d = Vector((0, math.cos(e), math.sin(e)))
    root = Vector((px, py - 0.05 * k, zc + 0.05 * k))
    h.tube(root - d * 0.45 * k, root + d * 0.6 * k, 0.22 * k, "steel_dark", segs=14)
    h.tube(root + d * 0.6 * k, root + d * 1.4 * k, 0.16 * k, "steel", segs=14)
    h.tube(root + d * 0.85 * k, root + d * 1.2 * k, 0.165 * k, "soot", segs=14)
    h.tube(root + d * 1.4 * k, root + d * barrel, 0.13 * k, "steel_light", segs=14)
    h.tube(root + d * (barrel - 0.06), root + d * (barrel + 0.04), 0.145 * k, "steel_dark", segs=14)
    h.tube(root + d * (barrel + 0.03), root + d * (barrel + 0.05), 0.09 * k, "soot", segs=12)
    return own_materials(h, "cannon")


@model("artillery-turret")
def artillery_turret():
    """Factorio's artillery turret, 3x3: a squat pedestal with chamfered corners in yellow and
    black hazard stripes with a hatch on its south face, a thick rounded ring of armour on it and
    the slewing ring on top, where the cannon (`anim_turret_head`) turns: tall dark machinery
    and a long barrel raised high to the north."""
    p = Part()
    h, c = 1.47, 0.45
    sq = [(h, -h + c), (h, h - c), (h - c, h), (-h + c, h), (-h, h - c), (-h, -h + c), (-h + c, -h), (h - c, -h)]
    p.prism(sq, 0.0, 0.1, "steel_black", bevel=0.03)
    # Hazard pedestal: vertical yellow and black bands round the sides.
    inner = [(x * 0.97, y * 0.97) for x, y in sq]
    n = 0
    for i in range(8):
        a, b = inner[i], inner[(i + 1) % 8]
        steps = 3 if i % 2 == 0 else 1
        for s in range(steps):
            t0, t1 = s / steps, (s + 1) / steps
            q0 = (a[0] + (b[0] - a[0]) * t0, a[1] + (b[1] - a[1]) * t0)
            q1 = (a[0] + (b[0] - a[0]) * t1, a[1] + (b[1] - a[1]) * t1)
            p.prism([(0, 0), q0, q1], 0.1, 0.95, "hazard_strong" if n % 2 == 0 else "hazard_black")
            n += 1
    p.prism(sq, 0.95, 1.05, "steel_dark", bevel=0.03)
    # South hatch.
    p.slab(-0.48, -1.5, 0.12, 0.48, -1.36, 0.66, "steel_dark", bevel=0.03)
    p.slab(-0.38, -1.53, 0.18, 0.38, -1.48, 0.6, "soot")
    for x in (-0.22, 0.0, 0.22):
        p.slab(x - 0.05, -1.55, 0.2, x + 0.05, -1.52, 0.58, "steel")
    # Rounded armour ring, the drum inside it and the ring the cannon turns on.
    p.cyl((0, 0, 1.2), 1.0, 0.4, "steel_dark", segs=28)
    p.ring_band((0, 0), 0.85, 1.4, 1.02, 1.28, 0, 360, "steel", segs=32, bevel=0.1)
    p.ring_band((0, 0), 0.9, 1.26, 1.28, 1.4, 0, 360, "steel", segs=32, bevel=0.05)
    p.ring_band((0, 0), 0.82, 1.0, 1.4, 1.52, 0, 360, "steel_light", segs=28, bevel=0.02)
    p.cyl((0, 0, 1.44), 0.82, 0.02, "soot", segs=24)
    for k in range(16):
        a = math.radians(k * 22.5)
        p.bolt((0.91 * math.cos(a), 0.91 * math.sin(a), 1.52), "steel_dark", radius=0.03)
    for sx in (-1, 1):
        p.slab(sx * 1.2, -0.3, 1.0, sx * 1.42, 0.3, 1.3, "steel_dark", bevel=0.04)
    head = artillery_cannon((0.0, 0.0), 1.44, barrel=3.9)
    return [p, head]


# ---------------------------------------------------------------------------------------------
# Vehicles.

def track(p, x, y0, y1, r=0.27, w=0.36, wheels=5):
    """A track run along y at x: a dark belt round two end sprockets with road wheels between
    and treads across its top and sides. Returns its moving parts: the treads on top
    (`anim_tread`, which the client slides forward by the distance driven, one tread's spacing
    round and round: Factorio's two-frame track animation) and the road wheels' hubs
    (`anim_wheel_track`, rolling)."""
    p.cyl((x, y0 + r, r), r, w, "steel_black", segs=14, axis="X", bevel=0.03)
    p.cyl((x, y1 - r, r), r, w, "steel_black", segs=14, axis="X", bevel=0.03)
    p.slab(x - w / 2, y0 + r, 0.02, x + w / 2, y1 - r, 2 * r, "steel_black", bevel=0.03)
    n = int((y1 - y0) / 0.11)
    tread = Part("anim_tread", pivot=(x, 0.0, 2 * r))
    for k in range(n + 1):
        y = y0 + 0.04 + (y1 - y0 - 0.08) * k / n
        tread.box((x, y, 2 * r + 0.01), (w + 0.02, 0.05, 0.03), "rubber")
    parts = [tread]
    sx = 1 if x > 0 else -1
    for k in range(wheels):
        y = y0 + r + (y1 - y0 - 2 * r) * k / (wheels - 1)
        hub = Part("anim_wheel_track", pivot=(x, y, r * 0.95))
        hub.cyl((x + sx * (w / 2 + 0.01), y, r * 0.95), r * 0.62, 0.03, "rust_brown", segs=12, axis="X")
        hub.cyl((x + sx * (w / 2 + 0.02), y, r * 0.95), r * 0.22, 0.03, "steel", segs=8, axis="X")
        # A spoke, so the turning shows.
        hub.slab(x + sx * (w / 2 + 0.02) - 0.012, y - 0.02, r * 0.95 - r * 0.55, x + sx * (w / 2 + 0.02) + 0.012, y + 0.02,
                 r * 0.95 + r * 0.55, "steel_dark")
        parts.append(hub)
    return parts


@model("tank")
def tank():
    """Factorio's tank, front north: two broad tracks, a rusty hull riding high on them with
    fenders over the tracks, the engine at the front (ribbed cylinders behind a sloped glacis,
    mudguard flaps hanging over the track ends), two cream fuel tanks in a cage at the back with
    a perforated side plate. The turret (`anim_turret_head`) turns on its ring mid-hull: a
    round ribbed drum under a rusty octagonal cap with a hatch, twin barrels north."""
    p = Part()
    running = []
    for sx in (-1, 1):
        running += track(p, sx * 0.72, -1.42, 1.38)
    # Hull and fenders.
    p.slab(-0.55, -1.38, 0.22, 0.55, 1.3, 0.78, "rust_dark", bevel=0.05)
    p.slab(-0.94, -1.3, 0.62, 0.94, 1.2, 0.8, "rust_brown", bevel=0.04)
    p.prism(octagon(0.72), 0.78, 0.98, "rust_dark", bevel=0.04, matrix=T(0, -0.05, 0))
    # Front: engine with its ribbed cylinders, a sloped glacis.
    p.slab(-0.55, 0.45, 0.78, 0.55, 1.05, 1.0, "steel_dark", bevel=0.04)
    for k in range(4):
        x = -0.36 + k * 0.24
        p.cyl((x, 0.78, 1.1), 0.1, 0.28, "steel", segs=10, bevel=0.01)
        for z in (1.02, 1.08, 1.14, 1.2):
            p.cyl((x, 0.78, z), 0.125, 0.025, "steel_light", segs=10)
    p.side_prism([(1.0, 0.3), (1.42, 0.38), (1.42, 0.62), (1.05, 0.98), (1.0, 0.98)], -0.6, 0.6, "rust_brown",
                 bevel=0.03)
    p.slab(-0.25, 1.2, 0.8, 0.25, 1.32, 0.95, "steel", bevel=0.02)
    for sx in (-1, 1):
        # Mudguards hanging over the front of the tracks.
        p.beam((sx * 0.72, 1.3, 0.85), (sx * 0.78, 1.62, 0.42), 0.42, 0.04, "rust_brown", up=(0, 1, 1), bevel=0.01)
        p.cyl((sx * 0.4, 1.36, 0.62), 0.07, 0.08, "steel_light", segs=8, axis="Y")
        p.cyl((sx * 0.4, 1.4, 0.62), 0.05, 0.01, "glass", segs=8, axis="Y")
    # Rear: two cream tanks in a cage.
    for x in (-0.33, 0.33):
        p.cyl((x, -0.95, 0.98), 0.27, 0.62, "tank_white", segs=14, axis="Y", bevel=0.06)
        p.sphere((x, -1.26, 0.98), 0.27, "tank_white", segs=14, rings=6, scale=(1, 0.5, 1))
        for y in (-1.15, -0.8):
            p.cyl((x, y, 0.98), 0.285, 0.04, "steel_dark", segs=14, axis="Y")
    for sx in (-1, 1):
        p.beam((sx * 0.68, -1.4, 0.8), (sx * 0.68, -1.4, 1.3), 0.05, 0.05, "steel_dark")
        p.beam((sx * 0.68, -0.6, 0.8), (sx * 0.68, -0.6, 1.3), 0.05, 0.05, "steel_dark")
        p.beam((sx * 0.68, -1.4, 1.3), (sx * 0.68, -0.6, 1.3), 0.05, 0.05, "steel_dark")
    p.beam((-0.68, -1.4, 1.3), (0.68, -1.4, 1.3), 0.05, 0.05, "steel_dark")
    # Perforated plate on the west side.
    p.slab(-1.0, -1.25, 0.42, -0.95, -0.3, 0.86, "steel_light", bevel=0.01)
    for k in range(7):
        for z in (0.5, 0.62, 0.74):
            p.cyl((-1.005, -1.15 + k * 0.13, z), 0.025, 0.01, "soot", segs=6, axis="X")
    p.slab(-0.3, -1.45, 0.4, 0.3, -1.38, 0.7, "steel_dark", bevel=0.02)
    # Hull seams and rivet rows, so the sides and back read as riveted plate from any side.
    for sx in (-1, 1):
        for y in (-0.9, -0.3, 0.3, 0.9):
            p.slab(sx * 0.551, y - 0.015, 0.3, sx * 0.56, y + 0.015, 0.75, "steel_dark")
        for k in range(12):
            y = -1.25 + k * 0.22
            p.bolt((sx * 0.94, y, 0.805), "steel_light", radius=0.022)
            p.bolt((sx * 0.56, y, 0.7), "steel_light", radius=0.02, axis="X")
    for x in (-0.4, -0.2, 0.0, 0.2, 0.4):
        p.bolt((x, -1.385, 0.74), "steel_light", radius=0.02, axis="Y")
        p.bolt((x, 1.305, 0.72), "steel_light", radius=0.02, axis="Y")

    head = Part("anim_turret_head", pivot=(0.0, -0.05, 0.98))
    tz = 0.98
    head.cyl((0, -0.05, tz + 0.2), 0.52, 0.4, "steel_light", segs=20, bevel=0.06)
    for k in range(20):
        a = math.radians(k * 18)
        head.box((0.53 * math.cos(a), -0.05 + 0.53 * math.sin(a), tz + 0.2), (0.06, 0.06, 0.34), "steel", rz=k * 18,
                 bevel=0.015)
    head.prism(octagon(0.42), tz + 0.36, tz + 0.46, "rust_brown", bevel=0.03, matrix=T(0, -0.13, 0))
    head.cyl((0, -0.2, tz + 0.49), 0.17, 0.08, "rust_dark", segs=12, bevel=0.02)
    for k in range(6):
        a = math.radians(k * 60 + 30)
        head.bolt((0.12 * math.cos(a), -0.2 + 0.12 * math.sin(a), tz + 0.54), "steel_light", radius=0.025)
    head.slab(-0.22, 0.41, tz + 0.12, 0.22, 0.71, tz + 0.38, "rust_dark", bevel=0.04)
    for sx in (-1, 1):
        head.cyl((sx * 0.143, 0.87, tz + 0.184), 0.052, 0.66, "steel_light", segs=8, axis="Y")
        head.cyl((sx * 0.143, 1.18, tz + 0.184), 0.066, 0.1, "steel_dark", segs=8, axis="Y")
    # Built compact, then stretched to the sprite's size, measured against all 64 rotation frames
    # of the body and of the turret (tools/models/turntable.py): the tank draws longer and much
    # taller than its selection box, the hull's middle 0.2 tiles north of the vehicle's position.
    # The turret turns about the vehicle's position (Factorio draws its frames there), riding high
    # on the hull: a narrower, taller drum.
    body = T(0, 0.2, 0) @ S(0.902, 1.071, 1.353)
    p.transform(body)
    for part in running:
        part.transform(body)
        part.pivot = body @ part.pivot
    head.transform(T(0, 0.05, 0.299) @ S(0.923, 1.009, 1.39))
    head.pivot = Vector((0.0, 0.0, tz * 1.39 + 0.299))
    return [p, own_materials(head, "turret")] + running


# Spidertron: legs from the hips (Factorio's mount_position) to the feet (ground_position),
# Factorio coordinates (x east, y south), tiles.
SPIDER_LEGS = [((15, -22), (2.25, -2.5)), ((23, -10), (3.0, -1.0)), ((25, 4), (3.0, 1.0)), ((15, 17), (2.25, 2.5))]
SPIDER_HIP_Z = 2.55
SPIDER_KNEE_Z = 3.8
SPIDER_KNEE_AT = 0.4  # of the way from hip to foot (Factorio's knee_distance_factor)


def spider_hip(mx, my, sx, zb):
    """A hip ball on the bowl's rim, towards the leg's mount_position (about 0.9 tiles out)."""
    return Vector((sx * mx / 32.0 * 1.15, -my / 32.0 * 1.15, zb - 0.08))


@model("spidertron")
def spidertron():
    """Factorio's spidertron. The torso floats about two tiles up: a rusty ring underneath
    with ball joints for the hips, and the riveted grey shell on it, bulging into two humps,
    the eyes (red lamps) round the front, the slotted rocket pod at the back, an antenna. The
    eight legs are posed standing (Factorio draws them as separate entities that step on their
    own): upper legs rise from the hips to knees above the shell, lower legs reach down to the
    feet two to three tiles out.

    Moving parts, as Factorio draws it: the shell (`anim_torso`, pivot on its axis) turns with
    the torso's aim over the bowl, which doesn't turn (base_animation has one direction); each
    leg is an upper (`anim_leg_upper`, pivot at the hip) and a lower part (`anim_leg_lower`,
    pivot at the knee), which the client stretches and bends between hip, knee and foot as
    Factorio stretches its leg sprites (vehicle_anim.gd)."""
    p = Part()
    zb = SPIDER_HIP_Z
    # The bottom: a wide shallow rusty bowl, the eight hip balls round its rim and the leg
    # brackets under them (spidertron-body-bottom).
    p.cyl((0, 0, zb - 0.1), 0.62, 0.3, "rust_brown", segs=28, radius_top=0.97, bevel=0.02)
    p.ring_band((0, 0), 0.84, 0.99, zb + 0.03, zb + 0.11, 0, 360, "rust_brown", segs=28, bevel=0.02)
    p.cyl((0, 0, zb - 0.27), 0.56, 0.06, "rust_dark", segs=20)
    p.sphere((0, 0, zb - 0.3), 0.38, "steel_dark", segs=12, rings=6, scale=(1, 1, 0.5))
    for (mx, my), _ in SPIDER_LEGS:
        for sx in (-1, 1):
            hip = spider_hip(mx, my, sx, zb)
            p.sphere(tuple(hip), 0.16, "rust_brown", segs=10, rings=5)
            p.beam((hip.x * 0.7, hip.y * 0.7, zb - 0.22), (hip.x * 1.05, hip.y * 1.05, zb - 0.02), 0.12, 0.08,
                   "steel_dark")
    # Shell: a dome with two humps (front and back), narrower than the bowl, a band round the
    # waist.
    t = Part("anim_torso", pivot=(0.0, 0.0, zb))
    t.sphere((0, 0, zb + 0.08), 0.74, "steel_spider", segs=24, rings=10, hemisphere=True, scale=(1.0, 0.95, 1.45))
    t.sphere((0, -0.1, zb + 0.65), 0.46, "steel_spider", segs=18, rings=8, hemisphere=True, scale=(1.3, 1.1, 1.0))
    t.sphere((0, 0.33, zb + 0.45), 0.37, "steel_spider", segs=18, rings=8, hemisphere=True, scale=(1.3, 0.9, 0.85))
    t.cyl((0, 0, zb + 0.12), 0.77, 0.1, "steel_dark", segs=24)
    for k in range(16):
        a = math.radians(k * 22.5)
        t.bolt((0.78 * math.cos(a), 0.73 * math.sin(a), zb + 0.12), "steel_light", radius=0.03, axis="Z")
    # Eyes: a row of red lamps round the front.
    for k, a in enumerate((60, 75, 90, 105, 120)):
        r = math.radians(a)
        t.sphere((0.7 * math.cos(r), 0.66 * math.sin(r), zb + 0.42 + 0.05 * (k % 2)), 0.06, "lamp_red", segs=8, rings=4)
    for sx in (-1, 1):
        t.sphere((sx * 0.62, 0.35, zb + 0.6), 0.06, "lamp_red", segs=8, rings=4)
        t.sphere((sx * 0.45, -0.55, zb + 0.75), 0.05, "lamp_red", segs=8, rings=4)
    # Rocket pod at the back with its slots, and the hatch above.
    t.slab(-0.42, -0.9, zb + 0.32, 0.42, -0.5, zb + 0.86, "steel_dark", bevel=0.05)
    for k in range(4):
        x = -0.27 + k * 0.18
        t.slab(x - 0.05, -0.92, zb + 0.4, x + 0.05, -0.88, zb + 0.78, "soot")
    # The rusty band round the shell's waist.
    t.ring_band((0, 0), 0.7, 0.82, zb + 0.12, zb + 0.26, 0, 360, "rust_brown", segs=28, bevel=0.03)
    t.tube((0.2, -0.45, zb + 0.95), (0.42, -0.9, zb + 1.7), 0.015, "steel_light", segs=5)
    t.cyl((0.2, -0.45, zb + 0.97), 0.05, 0.06, "steel_dark", segs=8)
    # Legs: their own parts (and materials), coloured from Factorio's leg sprites, not the torso's.
    parts = [p, t]
    for (mx, my), (gx, gy) in SPIDER_LEGS:
        for sx in (-1, 1):
            hip = spider_hip(mx, my, sx, zb)
            foot = Vector((sx * gx, -gy, 0.0))
            knee = hip + (foot - hip) * SPIDER_KNEE_AT
            knee.z = SPIDER_KNEE_Z
            upper = Part("anim_leg_upper", pivot=tuple(hip))
            upper.tube(hip, knee, 0.07, "steel_dark", segs=8)
            upper.tube(hip + (knee - hip) * 0.15, hip + (knee - hip) * 0.85, 0.085, "rust_brown", segs=8)
            # Hydraulic rams along the legs.
            upper.tube(hip + (knee - hip) * 0.3 + Vector((0, 0, 0.1)), knee + (hip - knee) * 0.1 + Vector((0, 0, 0.1)),
                       0.03, "steel_light", segs=5)
            lower = Part("anim_leg_lower", pivot=tuple(knee))
            lower.sphere(knee, 0.11, "steel_dark", segs=10, rings=5)
            lower.tube(knee, foot + Vector((0, 0, 0.18)), 0.06, "steel_dark", segs=8)
            lower.tube(knee + (foot - knee) * 0.1, knee + (foot - knee) * 0.55, 0.075, "rust_brown", segs=8)
            lower.cyl((foot.x, foot.y, 0.08), 0.13, 0.16, "steel_black", segs=10, radius_top=0.07)
            parts += [own_materials(upper, "leg"), own_materials(lower, "leg")]
    return parts


@model("artillery-wagon")
def artillery_wagon():
    """Factorio's artillery wagon, front north, from its base sheets: a heavy riveted flat car on
    two bogies. At the back a square base with rounded corners carries the round armoured ring
    the cannon (`anim_turret_head`) turns on, pointing forward as Factorio parks it, a gauge
    beside it; in the middle an open frame racks brass shells across the car between struts
    rising to the front; at the front a box in yellow and black hazard stripes with a big grille
    on top, red lamps at its corners, an amber lamp and a handle."""
    p = Part()
    axles = []
    for y in (-2.0, 2.0):
        axles += bogie(p, y)
    # Deck and frame, riveted along the sills; hazard plates on the buffer ends.
    along_y(p, mirrored([(0.95, 0.85), (1.0, 1.22)]), -3.25, 3.25, "steel_dark", bevel=0.04)
    for sx in (-1, 1):
        detail.rivet_line(p, (sx * 1.005, -3.1, 1.12), (sx * 1.005, 3.1, 1.12), 26, "X")
    for sy in (-1, 1):
        buffers(p, sy * 3.32)
        for k in range(5):
            x0 = -0.95 + k * 0.38
            p.slab(x0, sy * 3.05, 1.22, x0 + 0.19, sy * 3.25, 1.24, "hazard_black")
            p.slab(x0 + 0.19, sy * 3.05, 1.22, x0 + 0.38, sy * 3.25, 1.24, "hazard_strong")

    # Front: the hazard-striped box, a grille on top inside a striped border, lamps, a handle.
    lo, hi = (-0.86, 1.5, 1.22), (0.86, 3.08, 2.2)
    p.slab(*lo, *hi, "steel", bevel=0.06)
    for face in ("+x", "-x", "+y"):
        detail.stripes(p, lo, hi, face, 7, mats=("hazard_strong", "hazard_black"), slant=0.5, depth=0.012)
    gl, gh = (-0.62, 1.72, 2.2), (0.62, 2.9, 2.24)
    p.slab(*gl, *gh, "steel_dark", bevel=0.01)
    detail.slots(p, gl, gh, "+z", 9, mat="grime", along=1, depth=0.008)
    for sx in (-1, 1):
        p.slab(sx * 0.62, 1.55, 2.2, sx * 0.84, 3.05, 2.215, "hazard_strong")
        for sy, y in ((-1, 1.56), (1, 3.02)):
            p.sphere((sx * 0.8, y, 2.24), 0.04, "lamp_red", segs=6, rings=3)
    p.slab(-0.62, 1.53, 2.2, 0.62, 1.7, 2.215, "hazard_black")
    p.slab(-0.62, 2.92, 2.2, 0.62, 3.05, 2.215, "hazard_black")
    p.pipe([(-0.3, 3.08, 1.95), (-0.3, 3.18, 2.0), (0.3, 3.18, 2.0), (0.3, 3.08, 1.95)], 0.025, "steel_light", segs=6)
    p.slab(-0.42, 1.44, 1.4, 0.42, 1.5, 2.1, "steel_dark")
    p.box((0.0, 1.43, 1.92), (0.12, 0.03, 0.08), "hazard_strong")
    detail.rivet_line(p, (-0.36, 1.435, 1.5), (0.36, 1.435, 1.5), 5, "Y")

    # Middle: an open rack of shells lying across the car, struts rising to the front box.
    p.slab(-0.7, -0.95, 1.22, 0.7, 1.5, 1.32, "steel_black")
    for sx in (-1, 1):
        p.beam((sx * 0.58, -0.95, 1.78), (sx * 0.58, 1.5, 1.78), 0.08, 0.07, "steel", bevel=0.01)
        p.beam((sx * 0.58, -0.95, 1.3), (sx * 0.58, 1.5, 1.3), 0.08, 0.07, "steel")
        for y in (-0.85, -0.15, 0.55, 1.25):
            p.beam((sx * 0.58, y, 1.3), (sx * 0.58, y, 1.8), 0.07, 0.07, "steel", up=(0, 1, 0))
        p.beam((sx * 0.75, -0.6, 1.95), (sx * 0.75, 1.5, 2.15), 0.05, 0.05, "steel_light")
        p.slab(sx * 0.62, -0.9, 1.22, sx * 0.98, 1.45, 1.55, "steel_dark", bevel=0.03)
        detail.rivet_line(p, (sx * 0.985, -0.8, 1.45), (sx * 0.985, 1.35, 1.45), 9, "X")
        p.cyl((sx * 0.8, 0.3, 1.6), 0.12, 1.5, "steel", segs=10, axis="Y", bevel=0.02)
    for y in (-0.62, -0.2, 0.22, 0.64, 1.06):
        p.cyl((0, y, 1.5), 0.15, 0.82, "brass", segs=12, axis="X")
        p.cyl((0.52, y, 1.5), 0.15, 0.22, "steel_dark", segs=12, axis="X", radius_top=0.05)
        p.cyl((-0.43, y, 1.5), 0.155, 0.04, "copper_dull", segs=12, axis="X")
    for y in (-0.85, 0.55):
        p.beam((-0.58, y, 1.78), (0.58, y, 1.78), 0.06, 0.05, "steel")

    # Back: the square base with rounded corners and the armoured ring the cannon turns on.
    ry, zr = -2.07, 1.9
    c = 0.3
    base = [(1.0, -3.2 + c), (1.0, -0.95 - c), (1.0 - c, -0.95), (-1.0 + c, -0.95), (-1.0, -0.95 - c),
            (-1.0, -3.2 + c), (-1.0 + c, -3.2), (1.0 - c, -3.2)]
    p.prism(base, 1.22, 1.5, "steel_dark", bevel=0.05)
    for sx in (-1, 1):
        detail.rivet_line(p, (sx * 1.005, -2.9, 1.4), (sx * 1.005, -1.25, 1.4), 7, "X")
    p.cyl((0, ry, 1.62), 1.06, 0.26, "steel", segs=32, bevel=0.04)
    p.ring_band((0, ry), 0.82, 1.1, 1.74, zr, 0, 360, "steel_dark", segs=32, bevel=0.04)
    p.cyl((0, ry, 1.78), 0.82, 0.04, "soot", segs=28)
    for k in range(16):
        a = math.radians(k * 22.5)
        p.bolt((0.97 * math.cos(a), ry + 0.97 * math.sin(a), zr), "steel_light", radius=0.028)
        p.bolt((1.07 * math.cos(a), ry + 1.07 * math.sin(a), 1.6), "steel_light", radius=0.022, axis="X")
    p.cyl((-0.88, -1.12, 1.68), 0.13, 0.36, "steel_dark", segs=12, bevel=0.02)
    p.cyl((-0.88, -1.12, 1.87), 0.1, 0.02, "ceramic", segs=12)
    p.slab(0.75, -3.15, 1.5, 0.95, -2.85, 1.72, "steel_black", bevel=0.03)
    head = artillery_cannon((0.0, ry), zr, barrel=4.3, elevation=21.0, scale=1.25)
    return [p, head] + axles


# ---------------------------------------------------------------------------------------------
# Combat robots. Drawn flying (the client lifts them, visuals.gd FLYING); modelled from the
# ground up, their features at the back (-y) as the sprites' first frame shows them.

@model("defender")
def defender():
    """Factorio's defender: a white dome with a copper band, its stubby gun leaning out of the
    back of the dome, a stack of dark rings underneath, a nozzle pointing forward and down, two thin
    legs out to the sides with cyan lamps."""
    p = Part()
    z = 0.64
    p.sphere((0, 0, z), 0.235, "paint_white", segs=16, rings=6, hemisphere=True, scale=(1, 1, 0.6))
    p.cyl((0, 0, z - 0.01), 0.24, 0.03, "copper_dull", segs=16)
    for k, r in enumerate((0.225, 0.22, 0.21, 0.2, 0.18)):
        p.cyl((0, 0, z - 0.06 - 0.066 * k), r, 0.056, "rust_brown" if k % 2 else "steel_dark", segs=14)
    p.tube((0, -0.12, z + 0.05), (0, -0.27, z + 0.08), 0.07, "paint_white", segs=6, radius_top=0.045)
    # A block on the front of the rings with the nozzle straight out of it, a post underneath.
    p.slab(-0.09, 0.12, z - 0.38, 0.09, 0.25, z - 0.2, "blue_steel", bevel=0.015)
    p.cyl((0, 0.255, z - 0.29), 0.05, 0.02, "rust_brown", segs=8, axis="Y")
    p.tube((0.0, 0.25, z - 0.29), (0.0, 0.4, z - 0.29), 0.035, "steel", segs=6)
    p.cyl((0, 0, z - 0.43), 0.06, 0.12, "steel_dark", segs=8)
    for sx in (-1, 1):
        p.tube((sx * 0.17, 0, z - 0.1), (sx * 0.37, 0, z - 0.3), 0.014, "steel_dark", segs=4)
        p.sphere((sx * 0.37, 0, z - 0.3), 0.027, "lamp_cyan", segs=6, rings=3)
    # Modelled at the sprite's heights, then set down on the ground like the other robots.
    p.transform(T(0, 0, -0.15))
    return p


@model("distractor")
def distractor():
    """Factorio's distractor: a squat riveted copper-and-steel body, an octagonal collar on top
    round a fan of radial vanes, short cylinders out east and west, four legs with cyan lamps
    and a stacked nozzle leaning down and out at the back."""
    p = Part()
    z = 0.5
    p.cyl((0, 0, z - 0.035), 0.33, 0.21, "copper_dull", segs=16, bevel=0.04)
    p.cyl((0, 0, z + 0.1), 0.33, 0.06, "copper_dull", segs=16, radius_top=0.25)
    oct_out, oct_in = octagon(0.25), octagon(0.19)
    for i in range(8):
        a, b = oct_out[i], oct_out[(i + 1) % 8]
        c, d = oct_in[i], oct_in[(i + 1) % 8]
        p.prism([a, b, d, c], z + 0.1, z + 0.22, "paint_cream")
    p.cyl((0, 0, z + 0.135), 0.19, 0.01, "soot", segs=12)
    for k in range(8):
        a = math.radians(k * 45 + 22.5)
        p.beam((0, 0, z + 0.18), (0.18 * math.cos(a), 0.18 * math.sin(a), z + 0.17), 0.03, 0.015, "brass")
    p.sphere((0, 0, z + 0.185), 0.035, "brass", segs=6, rings=3)
    for k in range(12):
        a = math.radians(k * 30)
        p.bolt((0.32 * math.cos(a), 0.32 * math.sin(a), z + 0.06), "steel_light", radius=0.02, axis="Z")
    for sx in (-1, 1):
        p.cyl((sx * 0.4, 0, z - 0.1), 0.06, 0.14, "steel_dark", segs=8, axis="X")
        p.cyl((sx * 0.48, 0, z - 0.1), 0.045, 0.04, "steel_light", segs=8, axis="X")
    for x, y in ((0.32, 0.3), (-0.32, 0.3), (-0.32, -0.3), (0.32, -0.3)):
        p.tube((0.6 * x, 0.6 * y, z - 0.02), (x, y, z - 0.02), 0.014, "steel_dark", segs=4)
        p.sphere((x, y, z - 0.02), 0.032, "lamp_cyan", segs=6, rings=3)
    d = Vector((0, -0.3, -1)).normalized()
    root = Vector((0, -0.1, z - 0.12))
    for k in range(4):
        q = root + d * (0.07 * k)
        p.tube(q, q + d * 0.06, 0.075 - 0.01 * k, "brass" if k % 2 else "steel_dark", segs=8)
    p.tube(root + d * 0.28, root + d * 0.36, 0.03, "steel_black", segs=6)
    # Modelled at the sprite's heights, then set down on the ground like the other robots; sized
    # to all 16 rotation frames (tools/models/fit_cells.py --fit scale): narrower, taller.
    p.transform(S(0.928, 1.007, 1.064) @ T(0, 0, -0.027))
    return p


@model("destroyer")
def destroyer():
    """Factorio's destroyer: a big riveted steel dome in six segments over a copper skirt, a
    cap on top, a dark bowl underneath, four ringed horn-like guns out round it, leaning down,
    and a red lamp under the middle."""
    p = Part()
    z = 0.6
    r = 0.4
    p.sphere((0, 0, z), r, "steel_spider", segs=20, rings=8, hemisphere=True, scale=(1, 1, 1.0))
    for k in range(6):
        a = math.radians(k * 60)
        p.beam((0.1 * math.cos(a), 0.1 * math.sin(a), z + 0.39), (r * math.cos(a), r * math.sin(a), z + 0.02),
               0.03, 0.03, "steel_dark")
    for ring, zz in ((0.38, z + 0.13), (0.3, z + 0.28)):
        for k in range(10):
            a = math.radians(k * 36 + 18)
            p.bolt((ring * math.cos(a), ring * math.sin(a), zz), "steel_dark", radius=0.02, axis="Z")
    p.sphere((0, 0, z + 0.37), 0.12, "steel", segs=10, rings=4, hemisphere=True)
    p.cyl((0, 0, z - 0.03), r + 0.01, 0.08, "copper_dull", segs=20, bevel=0.01)
    p.sphere((0, 0, z - 0.06), r - 0.04, "steel_dark", segs=16, rings=6, scale=(1, 1, 0.5))
    # Four ringed guns, one each way, leaning down; the red lamp hangs under the middle.
    for k in range(4):
        a = math.radians(k * 90)
        out = Vector((math.cos(a), math.sin(a), 0))
        d = (out - Vector((0, 0, 0.45))).normalized()
        root = out * 0.3 + Vector((0, 0, z - 0.09))
        for j in range(3):
            q = root + d * (0.1 * j)
            p.tube(q, q + d * 0.09, 0.085 - 0.017 * j, "brass" if j % 2 else "steel", segs=8,
                   radius_top=0.075 - 0.017 * j)
        p.tube(root + d * 0.3, root + d * 0.36, 0.03, "soot", segs=6)
    p.cyl((0, 0, z - 0.25), 0.05, 0.05, "steel_dark", segs=8)
    p.sphere((0, 0, z - 0.28), 0.025, "lamp_red", segs=6, rings=3)
    # Modelled at the sprite's heights, then set down on the ground like the other robots; sized
    # to all 32 rotation frames (tools/models/fit_cells.py --fit scale).
    p.transform(S(1.04, 1.031, 1.057) @ T(0, 0, -0.295))
    return p
