"""Nuclear power: nuclear reactor, heat pipes, heat exchanger, steam turbine, centrifuge.

Each model is matched to Factorio's HR sprite with compare.py (client/assets/models/README.md,
"Matching a sprite"). Heat pipes come as a kit of 16 shapes named after Factorio's heat pipe
pictures, like the pipes (`heat-pipe-straight-vertical`, `heat-pipe-corner-up-right`, ...); the
client picks one from the neighbouring heat pipes. "up" is north.
"""

import math

from mathutils import Vector

import kit
from kit import Part, R, S, T, model
from fluids import PIPE_SHAPES

kit.MATERIALS.update({
    "paint_reactor": ("cfc8ae", 0.6, 0.25, None, 0),      # the reactor's cream shell
    "paint_heatex": ("8c9483", 0.55, 0.45, None, 0),      # heat exchanger, turbine: pale green-grey
    "copper_hose": ("8a4a2c", 0.6, 0.7, None, 0),         # corrugated hoses
    "copper_red": ("6e2e22", 0.6, 0.5, None, 0),          # heat exchanger radiator plates
    "glass_green": ("6fd27a", 0.2, 0.1, None, 0),         # reactor portholes (glow when working)
    "paint_yellow": ("c9a227", 0.55, 0.35, None, 0),      # centrifuge gantries
    "paint_centrifuge": ("c7c4b2", 0.6, 0.3, None, 0),    # centrifuge drums
    # Polished rotor rings: bright, and only half metallic so they don't mirror a dark sky.
    "steel_polished": ("cfd0cc", 0.3, 0.45, None, 0),
})


def corrugated(p, points, radius, mat="copper_hose", segs=10, rib=0.07):
    """A corrugated hose through `points`: a tube with raised rings every `rib` tiles."""
    pts = [Vector(q) for q in points]
    for a, b in zip(pts, pts[1:]):
        p.tube(a, b, radius, mat, segs=segs)
        d = b - a
        n = max(1, int(d.length / rib))
        for k in range(n):
            c = a + d * ((k + 0.5) / n)
            p.tube(c - d.normalized() * 0.015, c + d.normalized() * 0.015, radius * 1.18, mat, segs=segs)
    for q in pts[1:-1]:
        p.sphere(q, radius * 1.05, mat, segs=segs, rings=max(3, segs // 2))
    return p


def bend(a, b, c, steps=6):
    """Points along a quadratic curve from a to c pulled towards b."""
    a, b, c = Vector(a), Vector(b), Vector(c)
    return [a * (1 - t) ** 2 + b * 2 * t * (1 - t) + c * t * t for t in (i / steps for i in range(steps + 1))]


# ---------------------------------------------------------------------------------------------
# Heat pipes.
#
# Factorio draws each heat pipe almost straight down, tile-sized and square on screen, so they're
# fitted with the pipes' stretch (sprite_projection.py HEAT_PIPE_FIT) and an anchor at the pipes'
# axis. In those pictures a north-south run is a pair of touching copper pipes 0.36 tiles across,
# but an east-west run only 0.3 tiles deep, so east-west pipes are drawn thinner. The pictures
# put north-south runs a pixel east of the middle and east-west runs a pixel south.

HP_Z = 0.075      # height of the pipes' axis
HP_R = {"Y": 0.09, "X": 0.072}    # radius of each of the two pipes of a N-S and an E-W run,
HP_FLAT = 0.64                     # their height over their width, as drawn
HP_X = 0.016
HP_Y = -0.02
ARMS = {"N": (0, 1), "E": (1, 0), "S": (0, -1), "W": (-1, 0)}


def twin(p, a, b, z=HP_Z, gap=None, r=None):
    """The pair of copper pipes from a to b (x, y)."""
    a, b = Vector((a[0], a[1], 0)), Vector((b[0], b[1], 0))
    d = (b - a).normalized()
    if r is None:
        r = HP_R["Y"] * d.y * d.y + HP_R["X"] * d.x * d.x
    side = Vector((-d.y, d.x, 0)) * (r if gap is None else gap)
    off = Vector((0, HP_Y * d.x * d.x, 0))
    q = Part()
    for s in (-1, 1):
        q.tube(a + off + side * s, b + off + side * s, r, "copper", segs=10)
    p.add_part(q, T(0, 0, z) @ S(1, 1, HP_FLAT))


def clamp(p, centre, along):
    """A dark steel clamp band round both pipes, across the run `along` ("X" or "Y")."""
    x, y = centre
    w, d = (0.4, 0.1) if along == "Y" else (0.1, 0.25)
    p.slab(x - w / 2, y - d / 2, 0.0, x + w / 2, y + d / 2, 0.14, "steel_dark", bevel=0.025)
    for k in (-1, 1):
        if along == "Y":
            p.bolt((x + k * 0.15, y, 0.14), "steel_light", radius=0.02)
        else:
            p.bolt((x, y + k * 0.09, 0.14), "steel_light", radius=0.02)


def radiator(p, x0, y0, x1, y1, along):
    """The heat pipe's closed end: a steel sleeve ringed with ribs and rows of holes."""
    p.slab(x0, y0, 0.0, x1, y1, 0.16, "steel", bevel=0.035)
    n = 3
    for k in range(n):
        t = (k + 0.5) / n
        if along == "Y":
            y = y0 + (y1 - y0) * t
            p.slab(x0 - 0.01, y - 0.025, 0.0, x1 + 0.01, y + 0.025, 0.17, "steel_dark")
        else:
            x = x0 + (x1 - x0) * t
            p.slab(x - 0.025, y0 - 0.01, 0.0, x + 0.025, y1 + 0.01, 0.17, "steel_dark")
    # Holes on top, between the ribs.
    for k in range(n + 1):
        t = k / n
        for j in range(4):
            u = -0.3 + 0.2 * j
            if along == "Y":
                y = y0 + 0.04 + (y1 - y0 - 0.08) * t
                if k in (0, n):
                    continue
                at = ((x0 + x1) / 2 + u * (x1 - x0) * 0.9, y - (y1 - y0) / (2 * n))
            else:
                x = x0 + 0.04 + (x1 - x0 - 0.08) * t
                if k in (0, n):
                    continue
                at = (x - (x1 - x0) / (2 * n), (y0 + y1) / 2 + u * (y1 - y0) * 0.9)
            p.box((at[0], at[1], 0.161), (0.035, 0.035, 0.004), "soot")


# Where each closed end's sleeve sits, read from Factorio's ending pictures (x0, y0, x1, y1).
ENDS = {"N": (-0.2, -0.36, 0.21, -0.09), "S": (-0.2, -0.17, 0.21, 0.22),
        "W": (-0.16, -0.15, 0.32, 0.09), "E": (-0.39, -0.16, 0.08, 0.08)}
# How far from the middle each corner's mitred run meets its arms, and its pipes' radius, read
# from Factorio's corner pictures (which differ a little).
CORNERS = {"NE": (0.37, 0.09), "SE": (0.38, 0.09), "SW": (0.39, 0.081), "NW": (0.35, 0.09)}


def heat_pipe_piece(conns):
    p = Part()
    if not conns:
        # Two sleeves end to end, joined by a smooth collar.
        radiator(p, -0.185, 0.09, 0.155, 0.36, "Y")
        radiator(p, -0.185, -0.37, 0.155, -0.05, "Y")
        p.slab(-0.175, -0.07, 0.0, 0.145, 0.11, 0.15, "steel_dark", bevel=0.04)
        for x in (-0.1, 0.07):
            p.cyl((x, 0.02, 0.15), 0.065, 0.02, "steel_light", segs=10)
    elif len(conns) == 1:
        dx, dy = ARMS[conns]
        x0, y0, x1, y1 = ENDS[conns]
        if dy:
            twin(p, (0, dy * 0.5), (0, (y0 + y1) / 2))
        else:
            twin(p, (dx * 0.5, 0), ((x0 + x1) / 2, 0))
        radiator(p, x0, y0, x1, y1, "Y" if dy else "X")
    elif sorted(conns) in (["N", "S"], ["E", "W"]):
        dx, dy = ARMS[conns[0]]
        twin(p, (-dx * 0.5, -dy * 0.5), (dx * 0.5, dy * 0.5))
        clamp(p, (0, -0.07) if dy else (0.0, 0), "Y" if dy else "X")
    elif len(conns) == 2:
        # Corners: a short mitred run cuts across the corner, as Factorio's corner pictures.
        (ax, ay), (bx, by) = ARMS[conns[0]], ARMS[conns[1]]
        k, r = CORNERS[conns]
        pa, pb = (ax * k, ay * k), (bx * k, by * k)
        twin(p, (ax * 0.5, ay * 0.5), pa)
        twin(p, pa, pb, r=r)
        twin(p, pb, (bx * 0.5, by * 0.5))
        for (cx, cy), (dx, dy) in ((pa, (ax, ay)), (pb, (bx, by))):
            # A dark elbow collar where the run bends.
            clamp(p, (cx, cy), "Y" if dy else "X")
    else:
        for c in conns:
            dx, dy = ARMS[c]
            twin(p, (dx * 0.5, dy * 0.5), (dx * 0.1, dy * 0.1))
        # Tees and the cross: a low bolted junction box where the runs meet.
        p.slab(-0.185, -0.14, 0.0, 0.185, 0.1, 0.15, "steel_dark", bevel=0.03)
        p.slab(-0.14, -0.1, 0.15, 0.14, 0.06, 0.16, "steel")
        for x, y in ((-0.15, -0.11), (0.15, -0.11), (0.15, 0.07), (-0.15, 0.07)):
            p.bolt((x, y, 0.15), "steel_light", radius=0.02)
    p.transform(T(HP_X, 0, 0))
    return p


def _register_heat_pipes():
    for shape, conns in PIPE_SHAPES.items():
        model("heat-pipe-" + shape)(lambda conns=conns: heat_pipe_piece(conns))


_register_heat_pipes()


@model("heat-pipe")
def heat_pipe():
    """A heat pipe on its own (the straight north-south picture)."""
    return heat_pipe_piece("NS")


# ---------------------------------------------------------------------------------------------
# Nuclear reactor.

@model("nuclear-reactor")
def nuclear_reactor():
    """Factorio 2.0's nuclear reactor, 5x5: a great riveted cream sphere sitting low on its
    base, two fat corrugated copper hoses arching from its crown and its east side down to the
    east, steel pipes clamped up its west side to the green-eyed hatches there, thin red hoses
    across its front, a squat steel tank by its south-east foot, a bolted hatch on top and
    portholes that glow while it works (`anim_glow_core`)."""
    p = Part()
    c = Vector((-0.05, -0.3, 1.34))
    r = 1.82
    # Base plinth and the sphere.
    p.prism([(2.0 * math.cos(math.radians(22.5 + 45 * i)), 2.0 * math.sin(math.radians(22.5 + 45 * i))) for i in range(8)],
            0.0, 0.22, "steel_dark", bevel=0.05)
    p.cyl((c.x, c.y, 0.35), 1.6, 0.3, "steel_dark", segs=24, bevel=0.04)
    # The sphere's foot is hidden in the plinth; cut it off at the ground.
    q = Part()
    q.sphere(tuple(c), r, "paint_reactor", segs=28, rings=14)
    q.warp(lambda v: (v.x, v.y, max(v.z, 0.02)))
    p.add_part(q)
    # Weld seams and rivets.
    for dz in (-0.7, 0.35, 1.2):
        rr = math.sqrt(max(0.0, r * r - dz * dz))
        p.ring_band((c.x, c.y), rr - 0.01, rr + 0.025, c.z + dz - 0.025, c.z + dz + 0.025, 0, 360, "steel", segs=28)
    for k in range(20):
        a = math.radians(k * 18)
        rr = math.sqrt(r * r - 1.2 ** 2) + 0.02
        p.bolt((c.x + rr * math.cos(a), c.y + rr * math.sin(a), c.z + 1.25), "steel_light", radius=0.03, axis="Z")
    # Top hatch, and two round hatches with green eyes on the west side.
    p.cyl((c.x - 0.2, c.y + 0.1, c.z + r - 0.04), 0.42, 0.14, "paint_reactor", segs=18, bevel=0.04)
    p.bolts_ring((c.x - 0.2, c.y + 0.1, c.z + r + 0.04), 0.34, 10, "steel_light", radius=0.03)
    eyes = []
    for az, el in ((205, 18), (195, -28)):
        d = Vector((math.cos(math.radians(el)) * math.cos(math.radians(az)),
                    math.cos(math.radians(el)) * math.sin(math.radians(az)), math.sin(math.radians(el))))
        at = c + d * r
        q = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
        p.cyl((0, 0, 0.1), 0.42, 0.24, "paint_reactor", segs=16, bevel=0.04, matrix=T(*at) @ q)
        p.cyl((0, 0, 0.25), 0.28, 0.08, "steel_dark", segs=14, matrix=T(*at) @ q)
        eyes.append((at, q))
    # Two big corrugated hoses down the east side.
    corrugated(p, bend((c.x + 0.5, c.y + 0.5, c.z + r - 0.1), (c.x + 1.5, c.y + 1.2, c.z + r + 1.4),
                       (c.x + 1.75, c.y + 0.9, 0.7), steps=9), 0.22, segs=10, rib=0.13)
    corrugated(p, bend((c.x + 1.0, c.y - 0.5, c.z + 1.2), (c.x + 2.0, c.y - 0.4, c.z + 1.4),
                       (c.x + 1.8, c.y - 0.7, 0.6), steps=8), 0.2, segs=10, rib=0.13)
    for at in ((c.x + 0.5, c.y + 0.5, c.z + r - 0.08), (c.x + 1.0, c.y - 0.5, c.z + 1.2)):
        p.sphere(at, 0.3, "steel_dark", segs=12, rings=5, scale=(1, 1, 0.6))
    for y in (0.9, -0.2):
        p.cyl((c.x + 1.75, c.y + y, 0.4), 0.28, 0.6, "steel_dark", segs=12, bevel=0.03)
    # Thin red hoses across the front.
    corrugated(p, bend((c.x - 1.2, c.y - 1.2, c.z + 0.6), (c.x - 0.3, c.y - 2.3, c.z + 0.3),
                       (c.x + 0.5, c.y - 1.6, c.z - 0.3), steps=7), 0.08, mat="copper_red", segs=6, rib=0.09)
    corrugated(p, bend((c.x - 1.6, c.y - 0.6, c.z - 0.5), (c.x - 1.3, c.y - 1.9, c.z - 1.0),
                       (c.x - 0.4, c.y - 1.7, c.z - 1.2), steps=6), 0.07, mat="copper_red", segs=6, rib=0.09)
    corrugated(p, bend((c.x - 0.75, c.y - 1.4, c.z - 0.6), (c.x - 0.6, c.y - 2.0, 0.6),
                       (c.x - 0.55, c.y - 2.05, 0.05), steps=5), 0.12, mat="copper_red", segs=6, rib=0.09)
    # A round tank low on the south-west, under the lower hatch.
    p.sphere((c.x - 1.15, c.y - 1.25, 0.65), 0.65, "paint_reactor", segs=16, rings=8)
    # Machinery under the sphere's front.
    p.slab(c.x - 0.5, c.y - 2.05, 0.0, c.x + 0.6, c.y - 1.2, 0.6, "steel_dark", bevel=0.04)
    # Steel pipes clamped round the west side.
    x = c.x - r - 0.03
    p.pipe([(x, c.y - 0.9, 0.3), (x, c.y - 0.9, c.z + 0.2), (c.x - 1.3, c.y - 1.0, c.z + 1.2)], 0.11, "steel", segs=10)
    p.pipe([(x + 0.05, c.y + 0.6, 0.3), (x + 0.05, c.y + 0.6, c.z + 0.6), (c.x - 1.0, c.y + 0.9, c.z + 1.45)], 0.08,
           "steel_dark", segs=8)
    for z in (0.7, 1.5):
        p.box((x, c.y - 0.9, z), (0.3, 0.3, 0.08), "steel_dark", bevel=0.02)
    # The squat tank at the south-east foot.
    tx, ty = c.x + 1.0, c.y - 1.9
    p.cyl((tx, ty, 0.6), 0.6, 0.95, "steel", segs=16, bevel=0.06)
    p.sphere((tx, ty, 1.07), 0.6, "steel", segs=16, rings=5, hemisphere=True, scale=(1, 1, 0.45))
    for z in (0.3, 0.7, 1.05):
        p.cyl((tx, ty, z), 0.62, 0.05, "steel_dark", segs=16)
    p.cyl((tx, ty, 1.4), 0.12, 0.14, "steel_light", segs=10)
    p.pipe([(tx - 0.5, ty + 0.2, 0.9), (tx - 1.0, ty + 0.35, 0.9), (tx - 1.2, ty + 0.6, 1.3)], 0.07, "rust_brown", segs=8)
    # Portholes, glowing while the reactor works.
    glow = Part("anim_glow_core")
    for at, q in eyes:
        glow.cyl((0, 0, 0.3), 0.2, 0.04, "glass_green", segs=14, matrix=T(*at) @ q)
    return [p, glow]


# ---------------------------------------------------------------------------------------------
# Heat exchanger.

HX_R, HX_Z, HX_Y, HX_HALF = 0.8, 0.45, -0.05, 1.1   # the drum: radius, axis height and y, half length
HX_K = 0.55       # the drum is drawn lower than it is wide: its height over its width


def drum_band(p, x0, x1, a0, a1, r0, r1, mat, segs=12):
    """A band on the heat exchanger's drum from x0 to x1, between angles a0..a1 round its axis
    (0 = straight down, 90 = north, 180 = top, 270 = south)."""
    q = Part()
    q.ring_band((0, 0), r0, r1, x0, x1, a0, a1, mat, segs=segs)
    # ring_band works round Z; turn so its Z is the drum's axis (world X).
    p.add_part(q, T(0, HX_Y, HX_Z) @ S(1, 1, HX_K) @ R("Y", 90))


def on_drum(a, r=HX_R):
    """The point on the drum's circle at angle a (as drum_band), as (y, z)."""
    t = math.radians(a)
    return HX_Y + r * math.sin(t), HX_Z - r * math.cos(t) * HX_K


@model("heat-exchanger")
def heat_exchanger():
    """Factorio's heat exchanger, 3x2 facing north: a great pale green-grey drum lying east-west
    on a dark cradle, ringed with riveted bands, its ends domed, with two copper radiator windows
    on its south shoulder and a copper heat pipe running down between them to the heat input at
    the south edge. Water flanges stand out of both ends, low on the south side; the steam outlet
    rises behind the drum on the north side with a big flange; pipes, valves and small blue and
    yellow cables round it.

    While it works Factorio lights both windows with glowing fluid (heatex-*-fluid, 32 frames at
    half speed: 1.07 s a loop) and the heat pipe glows with the heat (heatex-*-heated, -glow):
    the windows' copper is `anim_glow_heatex` (glowing its colour, rising and falling once a
    loop), the heat pipe and its collar `anim_glow_heat` (steady)."""
    p = Part()
    windows = Part("anim_glow_heatex")
    heat = Part("anim_glow_heat")
    R, Z, Y, H = HX_R, HX_Z, HX_Y, HX_HALF
    # Cradle.
    p.slab(-1.2, -0.75, 0.0, 1.2, 0.5, 0.3, "steel_dark", bevel=0.05)
    for sx in (-1, 1):
        p.slab(sx * 0.9 - 0.16, -0.95, 0.0, sx * 0.9 + 0.16, 0.6, 0.4, "steel_dark", bevel=0.04)
        # Feet under the water flanges.
        p.slab(sx * 1.2 - 0.25, -0.85, 0.0, sx * 1.2 + 0.25, 0.45, 0.3, "steel_dark", bevel=0.04)
    # Machinery along the north side, down to the north edge.
    p.slab(-1.05, 0.35, 0.0, 1.05, 0.95, 0.42, "steel_dark", bevel=0.05)
    p.slab(-1.3, 0.35, 0.0, 1.3, 0.7, 0.3, "steel_dark", bevel=0.05)
    p.cyl((-0.8, 0.6, 0.55), 0.24, 0.8, "paint_heatex", segs=14, axis="X", bevel=0.03)
    p.cyl((0.75, 0.6, 0.42), 0.2, 0.8, "paint_heatex", segs=14, axis="X", bevel=0.03)
    # The steam outlet: an elbow out of the drum's north side, down to the north edge.
    a = on_drum(110, HX_R)
    p.pipe([(0, a[0], a[1]), (0, 0.68, a[1] - 0.1), (0, 0.78, 0.32)], 0.28, "paint_heatex", segs=14)
    p.cyl((0, 0.9, 0.32), 0.32, 0.1, "rust_brown", segs=16, axis="Y", bevel=0.02)
    # Drum and its domed ends.
    d = Part()
    d.cyl((0, 0, 0), R, 2 * H, "paint_heatex", segs=32, axis="X", bevel=0.04)
    for sx in (-1, 1):
        d.sphere((sx * H, 0, 0), R, "paint_heatex", segs=28, rings=14, scale=(0.32, 1, 1))
    p.add_part(d, T(0, Y, Z) @ S(1, 1, HX_K))
    for sx in (-1, 1):
        drum_band(p, sx * H - 0.06, sx * H + 0.06, 0, 360, R - 0.02, R + 0.04, "steel", segs=32)
    for x in (-0.55, 0.0, 0.55):
        drum_band(p, x - 0.04, x + 0.04, 0, 360, R - 0.02, R + 0.03, "steel_dark", segs=32)
    # Radiators on the south shoulder.
    for sx in (-1, 1):
        x0, x1 = sorted((sx * 0.2, sx * 0.85))
        drum_band(p, x0, x1, 188, 272, R - 0.02, R + 0.05, "steel_dark", segs=8)
        drum_band(windows, x0 + 0.05, x1 - 0.05, 195, 265, R + 0.03, R + 0.06, "copper_red", segs=8)
        for k in range(6):
            x = x0 + 0.1 + k * (x1 - x0 - 0.2) / 5
            drum_band(windows, x - 0.015, x + 0.015, 198, 262, R + 0.05, R + 0.08, "copper", segs=6)
    # The heat pipe down the front to the heat input at the south edge.
    top = on_drum(215, R + 0.12)
    heat.pipe([(0, top[0] + 0.1, top[1] + 0.25), (0, top[0], top[1]), (0, -0.88, 0.55), (0, -0.88, 0.12)], 0.13, "copper", segs=10)
    p.slab(-0.28, -1.0, 0.0, 0.28, -0.7, 0.18, "steel_dark", bevel=0.03)
    p.cyl((0, -0.87, 0.55), 0.17, 0.1, "steel", segs=12)
    # Round heat hatch, low on the south side to the east; a valve box to the west.
    p.cyl((0.72, -0.92, 0.3), 0.3, 0.14, "steel_dark", segs=18, axis="Y")
    p.cyl((0.72, -1.0, 0.3), 0.22, 0.04, "rust_brown", segs=16, axis="Y")
    p.slab(-0.95, -1.0, 0.0, -0.45, -0.6, 0.55, "steel_dark", bevel=0.04)
    p.slab(-0.9, -1.03, 0.3, -0.5, -0.95, 0.47, "steel", bevel=0.02)
    # Water flanges at both ends, low on the south side.
    for sx in (-1, 1):
        p.cyl((sx * 1.28, -0.6, 0.4), 0.25, 0.4, "steel", segs=16, axis="X")
        p.cyl((sx * 1.44, -0.6, 0.4), 0.33, 0.12, "rust_brown", segs=16, axis="X", bevel=0.02)
        p.bolts_ring((sx * 1.51, -0.6, 0.4), 0.27, 8, "steel_light", radius=0.022, axis="X")
        # Pipes up the ends.
        p.pipe([(sx * 1.3, -0.3, 0.3), (sx * 1.33, -0.25, 0.8), (sx * 1.1, -0.1, 1.05)], 0.08, "steel", segs=8)
    # Steam outlet behind the drum, on the north side.
    p.cyl((0.0, 0.25, 1.0), 0.3, 0.5, "paint_heatex", segs=18)
    p.sphere((0.0, 0.25, 1.25), 0.34, "paint_heatex", segs=18, rings=9, scale=(1, 1, 0.7))
    p.cyl((0.0, 0.28, 1.47), 0.4, 0.1, "rust_brown", segs=18, bevel=0.02)
    p.cyl((0.0, 0.28, 1.525), 0.25, 0.02, "soot", segs=16)
    p.bolts_ring((0.0, 0.28, 1.52), 0.31, 10, "steel_light", radius=0.022)
    # A pump on the north-west shoulder.
    p.cyl((-1.05, 0.15, 0.7), 0.16, 0.6, "steel_dark", segs=10)
    p.sphere((-1.05, 0.15, 1.15), 0.28, "paint_heatex", segs=12, rings=6)
    # Cables.
    a, b = on_drum(200, R + 0.06), on_drum(240, R + 0.06)
    p.pipe([(-0.9, a[0], a[1]), (-0.5, b[0], b[1]), (-0.1, b[0], b[1] - 0.2)], 0.025, "glow_blue", segs=6)
    p.pipe([(0.9, a[0], a[1]), (0.5, b[0], b[1]), (0.1, b[0], b[1] - 0.2)], 0.025, "hazard", segs=6)
    return [p, windows, heat]


# ---------------------------------------------------------------------------------------------
# Steam turbine.

def fan_ring(p, centre, radius, blades=24):
    """A big intake: a flanged ring lying flat with a dark well and twisted blades round a hub."""
    x, y, z = centre
    p.ring_band((x, y), radius - 0.18, radius, z - 0.18, z + 0.04, 0, 360, "paint_cream", segs=32, bevel=0.03)
    p.ring_band((x, y), radius - 0.24, radius - 0.16, z - 0.3, z - 0.05, 0, 360, "steel_dark", segs=32)
    p.cyl((x, y, z - 0.32), radius - 0.2, 0.04, "soot", segs=28)
    for k in range(blades):
        a = math.radians(360.0 * k / blades)
        c, s = math.cos(a), math.sin(a)
        p.beam((x + 0.2 * c, y + 0.2 * s, z - 0.2), (x + (radius - 0.24) * c, y + (radius - 0.24) * s, z - 0.12),
               0.12, 0.015, "steel", up=(-s * 0.6, c * 0.6, 0.8))
    p.cyl((x, y, z - 0.12), 0.2, 0.16, "steel_light", segs=12, bevel=0.03)


@model("steam-turbine")
def steam_turbine():
    """Factorio's steam turbine, 3x5 facing north: the great intake fan lying in a cream ring on
    top of a drum at its north end, then the body, pale green and worn, with corrugated copper
    hoses and a dark box on its east side, and to the south the turbine housing stepping down
    in rings to the steam pipe; another pipe stands up out of the north end.

    The fan's blades are `anim_spin_turbine_fan` and turn while it makes power (Factorio's sheet
    turns them one blade's spacing every 8 frames). They are round, as long as the narrow way of
    the oval ring allows, so they don't poke through it as they turn."""
    p = Part()
    p.slab(-1.0, -2.0, 0.0, 1.0, 2.0, 0.18, "steel_dark", bevel=0.05)
    # North: the intake drum and fan.
    p.cyl((0.06, 0.78, 1.15), 1.1, 2.0, "paint_heatex", segs=28, bevel=0.06)
    p.cyl((0.06, 0.7, 0.5), 1.14, 0.08, "steel_dark", segs=28)
    # Factorio draws the intake narrower north-south than across.
    f = Part()
    fan_ring(f, (0, 0, 0), 1.17, blades=0)
    p.add_part(f, T(0.06, 0.78, 2.35) @ S(1, 0.82, 1))
    fan = Part("anim_spin_turbine_fan", pivot=(0.06, 0.78, 2.2 * 0.55))
    for k in range(28):
        a = math.radians(360.0 * k / 28)
        c, s = math.cos(a), math.sin(a)
        fan.beam((0.06 + 0.2 * c, 0.78 + 0.2 * s, 2.15), (0.06 + 0.74 * c, 0.78 + 0.74 * s, 2.23), 0.12, 0.015, "steel",
                 up=(-s * 0.6, c * 0.6, 0.8))
    # Pipes up the east side.
    for y, r in ((0.55, 0.13), (-0.25, 0.11)):
        p.pipe([(1.0, y, 1.2), (1.45, y, 1.6), (1.45, y, 2.2), (1.0, y, 2.5)], r, "steel", segs=8)
    # A pump under the north pipe.
    p.slab(-0.45, 1.5, 0.0, 0.45, 2.3, 1.0, "steel_dark", bevel=0.06)
    p.cyl((0, 2.05, 0.9), 0.3, 1.4, "steel", segs=14)
    p.cyl((0, 2.05, 1.6), 0.36, 0.08, "rust_brown", segs=14, bevel=0.015)
    p.bolts_ring((0, 2.05, 1.64), 0.31, 8, "steel_light", radius=0.02)
    # Body.
    p.cyl((0, -0.35, 1.02), 0.95, 1.2, "paint_heatex", segs=26, axis="Y", bevel=0.06)
    p.slab(-1.15, -0.95, 0.15, 0.9, 0.25, 1.0, "paint_heatex", bevel=0.05)
    for y in (-0.85, -0.35, 0.15):
        p.cyl((0, y, 1.02), 0.99, 0.07, "steel_dark", segs=26, axis="Y")
    # South: the housing stepping down in rings to the pipe.
    for k, (y, r, d, mat) in enumerate(((-1.05, 1.26, 0.3, "steel_dark"), (-1.3, 1.17, 0.25, "paint_heatex"),
                                          (-1.55, 1.08, 0.3, "steel"), (-1.8, 0.85, 0.25, "paint_heatex"),
                                          (-2.0, 0.5, 0.2, "steel_dark"))):
        p.cyl((0, y, 1.34 - 0.08 * k), r, d, mat, segs=24, axis="Y", bevel=0.04)
    for k in range(18):
        a = math.radians(k * 20)
        p.beam((0, -1.18, 1.27), (1.18 * math.cos(a), -1.18, 1.27 + 1.18 * math.sin(a)), 0.05, 0.03, "steel_light",
               up=(0, 1, 0))
    p.pipe([(0, -2.05, 0.7), (0, -2.4, 0.55)], 0.26, "steel", segs=14, joints=False)
    p.cyl((0, -2.42, 0.55), 0.34, 0.08, "rust_brown", segs=14, axis="Y", bevel=0.015)
    p.bolts_ring((0, -2.47, 0.55), 0.29, 8, "steel_light", radius=0.02, axis="Y")
    # Machinery along the sides.
    for sx in (-1, 1):
        lift = 0.7 if sx > 0 else 0.0
        corrugated(p, bend((sx * 1.0, 0.55, 1.6 + lift), (sx * 1.45, 0.0, 1.5 + lift), (sx * 1.1, -0.6, 1.75 + lift),
                           steps=5), 0.09, segs=8)
        p.sphere((sx * 1.05, -0.2, 1.4), 0.2, "paint_reactor", segs=10, rings=5)
    p.slab(0.85, -0.9, 1.0, 1.05, 0.3, 1.8, "steel_black", bevel=0.04)
    p.slab(-1.3, -0.6, 0.2, -1.05, 0.1, 0.8, "steel_dark", bevel=0.04)
    p.slab(-0.3, -0.85, 2.1, 0.3, -0.1, 2.25, "steel_dark", bevel=0.03)
    # Modelled tall, then pressed to the sprites' height.
    p.transform(S(1, 1, 0.55))
    fan.transform(S(1, 1, 0.55))
    return [p, fan]


# ---------------------------------------------------------------------------------------------
# Centrifuge.

def rotor_coils(part, x, y, z0):
    """A stack of shiny steel rings: the top of a centrifuge drum, which spins."""
    for k, (r, h) in enumerate(((0.36, 0.1), (0.31, 0.1), (0.27, 0.1), (0.22, 0.1), (0.16, 0.12))):
        part.cyl((x, y, z0 + k * 0.1 + 0.05), r, h * 0.8, "steel_polished" if k % 2 == 0 else "steel", segs=18,
                 bevel=0.02)
    part.cyl((x, y, z0 + 0.6), 0.06, 0.12, "steel", segs=8)
    # A notch so the turn shows.
    part.box((x + 0.2, y, z0 + 0.18), (0.08, 0.04, 0.06), "rust_brown")


@model("centrifuge")
def centrifuge():
    """Factorio's centrifuge, 3x3: three perforated cream drums (one at the back, two at the
    front) on dark machinery, each topped by a stack of shiny rings that spins while it works
    (`anim_spin_rotor`) and reached by a yellow crane arm leaning in from the north-west, a
    small copper-capped drum between them, corrugated copper hoses and pipes round the base."""
    p = Part()
    p.prism([(1.36, -0.9), (1.36, 1.0), (1.0, 1.45), (-1.0, 1.45), (-1.45, 1.0), (-1.5, -0.85), (-1.2, -1.3),
             (1.15, -1.3)], 0.0, 0.14, "steel_dark", bevel=0.05)
    drums = [(0.0, 0.55, 1.45), (-0.8, -0.5, 1.1), (0.74, -0.5, 1.1)]
    parts = [p]
    for i, (x, y, h) in enumerate(drums):
        p.cyl((x, y, 0.25), 0.74, 0.34, "steel_dark", segs=20, bevel=0.08)
        p.cyl((x, y, 0.3 + h / 2), 0.63, h, "paint_centrifuge", segs=24, bevel=0.05)
        p.cyl((x, y, 0.3 + h + 0.03), 0.54, 0.06, "steel", segs=24)
        # Holes in rows round the drum.
        for row in range(3):
            z = 0.45 + row * (h - 0.3) / 2
            for k in range(14):
                a = math.radians(k * 360 / 14 + row * 12)
                p.box((x + 0.63 * math.cos(a), y + 0.63 * math.sin(a), z), (0.02, 0.08, 0.08), "soot", rz=math.degrees(a))
        rotor = Part("anim_spin_rotor", pivot=(x, y, 0.3 + h))
        rotor_coils(rotor, x, y, 0.3 + h)
        parts.append(rotor)
        # The yellow crane: a post at the drum's north-west and a ladder arm from its top over
        # to the coils.
        sx = 1 if i == 2 else -1
        out = (0.8, 0.5, 0.6)[i]
        foot = Vector((x + sx * out, y + 0.42, 0.3))
        lift = 0.15 if i == 0 else 0.0
        top = Vector((x + sx * out, y + 0.42, 0.3 + h + 0.85 + lift))
        end = Vector((x + 0.02, y + 0.02, 0.3 + h + 0.75 + lift * 0.5))
        d = (end - top).normalized()
        side = Vector((-d.y, d.x, 0)) * 0.11
        for s_ in (-1, 1):
            p.beam(foot + side * s_, top + side * s_, 0.07, 0.07, "paint_yellow")
            p.beam(top + side * s_, end + side * s_, 0.06, 0.06, "paint_yellow")
        for t in (0.3, 0.65):
            q = foot + (top - foot) * t
            p.beam(q - side, q + side, 0.04, 0.04, "paint_yellow")
        for t in (0.0, 0.33, 0.66, 1.0):
            q = top + (end - top) * t
            p.beam(q - side, q + side, 0.04, 0.04, "paint_yellow")
        p.beam(end, end - Vector((0, 0, 0.18)), 0.05, 0.05, "steel_dark")
        # A second leg leaning out to the west.
        p.beam(top, Vector((x + sx * (1.25 if i == 0 else 0.72), y - 0.1, 0.3)), 0.07, 0.07, "paint_yellow")
    # A gearbox at the back on the east side.
    p.slab(0.6, 0.45, 0.1, 1.27, 1.15, 1.35, "steel_dark", bevel=0.06)
    p.cyl((0.96, 0.8, 1.4), 0.2, 0.12, "steel", segs=12)
    # The small drum in the middle and pipes round the base.
    p.cyl((0.0, -0.15, 0.7), 0.24, 1.1, "steel", segs=16, bevel=0.03)
    p.cyl((0.0, -0.15, 1.3), 0.17, 0.1, "copper", segs=14, bevel=0.02)
    corrugated(p, [(0.0, -0.75, 0.3), (0.05, -0.55, 0.8), (0.0, -0.35, 1.2)], 0.07, segs=6)
    corrugated(p, [(-0.3, 0.2, 0.4), (-0.6, 0.35, 0.9), (-0.45, 0.6, 1.2)], 0.06, segs=6)
    corrugated(p, [(0.4, 0.0, 0.4), (0.75, 0.15, 0.9), (0.7, 0.4, 1.2)], 0.06, segs=6)
    p.pipe([(-1.3, -1.25, 0.25), (-1.3, 0.3, 0.25), (-0.7, 0.4, 0.25)], 0.06, "copper_dull", segs=8)
    p.pipe([(1.3, 1.25, 0.25), (1.3, -0.1, 0.25), (1.0, -0.15, 0.25)], 0.06, "copper_dull", segs=8)
    for x in (-0.95, 0.0, 0.95):
        p.box((x, -1.22, 0.25), (0.3, 0.16, 0.22), "steel", bevel=0.03)
    return parts
