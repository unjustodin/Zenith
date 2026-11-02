"""Circuit network and fluid control: arithmetic, decider, selector and constant combinators,
power switch, programmable speaker, display panel, the three valves and the pump.

Each model is matched to Factorio's HR sprites at true proportions (client/assets/models/README.md,
"Matching a sprite"; tools/models/score_proto.py): a point (x, y, z) shows x tiles right and
y + 0.669 z tiles up the screen. Factorio drew these small entities shallower than their footprint
in every direction (a combinator is as wide as its tile but its front edge sits a quarter tile in
from the footprint's), so one shape can't match all four frames with plain boxes. The bodies are
`block`s, boxes chamfered under and over (wide at the middle, narrower at the foot and the top),
whose sizes were fitted to all four frames' silhouettes together; their undercut hides from
Factorio's angle as it does in the sprites. Combinators face north like their sprites' first
frame: outputs (two posts on a bar) at the north end, inputs (two terminal pads) at the south.
"""

import math

import bmesh

from kit import MATERIALS, Part, R, T, _bevel, model
from fluids import KIT_FLANGE_R, KIT_R, KIT_Z, PIPE_R, PIPE_Z, flange_ring, hose, south_cut

# Colours picked from the sprites (their lit tops, a little brighter than the shaded sides).
MATERIALS.update({
    "paint_arith": ("5b7f92", 0.6, 0.4, None, 0),      # arithmetic combinator: blue-grey
    "paint_decider": ("b08a42", 0.6, 0.35, None, 0),   # decider: ochre
    "paint_selector": ("4f8f6c", 0.6, 0.35, None, 0),  # selector: green
    "paint_constant": ("a23d33", 0.6, 0.3, None, 0),   # constant: red
    "paint_switch": ("4d6f94", 0.55, 0.4, None, 0),    # power switch: blue
    "paint_panel": ("6f7158", 0.6, 0.4, None, 0),      # display panel: olive grey
    "paint_valve": ("a3a6a4", 0.55, 0.4, None, 0),     # valves: Factorio's grey icon plate
    "rubber_red": ("b0281e", 0.7, 0.0, None, 0),       # circuit wires on the combinators
    "rubber_green": ("3d9a2c", 0.7, 0.0, None, 0),
    "brass_coil": ("b38a3a", 0.45, 0.85, None, 0),     # the coiled yellow cables
    "screen_glass": ("1d1f1f", 0.25, 0.3, None, 0),    # dark screens (steel_black-like, glossier)
    "copper_prong": ("a65a36", 0.45, 0.9, None, 0),
    "led_red": ("d8331f", 0.4, 0.0, "ff3010", 1.2),
    "led_green": ("4ccf3a", 0.4, 0.0, "40ff30", 1.2),
})


def hull(p, points, mat, bevel=0.0):
    """The convex hull of `points` as one solid."""
    bm = bmesh.new()
    for v in points:
        bm.verts.new(v)
    res = bmesh.ops.convex_hull(bm, input=list(bm.verts))
    loose = [v for v in res["geom_interior"] + res["geom_unused"] if isinstance(v, bmesh.types.BMVert)]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bmesh.ops.dissolve_limit(bm, angle_limit=0.002, verts=list(bm.verts), edges=list(bm.edges))
    if bevel > 0:
        _bevel(bm, bevel)
    p.merge(bm, mat)
    bm.free()


def block(x0, x1, y0, y1, zm, zm2, h, inset_low, inset_top, top_dy=0.0):
    """Corners of a box chamfered under and over: its foot inset by `inset_low` (x, y), full size
    from zm to zm2, its top at h inset by `inset_top` (x, y) and moved `top_dy` north."""
    (bx, by), (tx, ty) = inset_low, inset_top
    return ([(x, y, 0.0) for x in (x0 + bx, x1 - bx) for y in (y0 + by, y1 - by)]
            + [(x, y, z) for z in (zm, zm2) for x in (x0, x1) for y in (y0, y1)]
            + [(x, y + top_dy, h) for x in (x0 + tx, x1 - tx) for y in (y0 + ty, y1 - ty)])


def post(p, x, y, z0, z1, cap, radius=0.035):
    """A terminal post: a steel stem with a ceramic insulator and a coloured cap."""
    p.cyl((x, y, (z0 + z1) / 2), radius, z1 - z0, "steel_dark", segs=8)
    p.cyl((x, y, z1 - 0.06), radius * 1.9, 0.07, "ceramic", segs=10, bevel=0.01)
    p.cyl((x, y, z1 + 0.0), radius * 1.6, 0.05, cap, segs=10, bevel=0.01)
    p.cyl((x, y, z1 + 0.04), radius * 0.8, 0.04, "steel_light", segs=6)


def grille(p, cx, cy, z, w, d, rows=5, cols=6):
    """A dark display grille: a bright frame, the dark glass, and a grid of small cells."""
    p.slab(cx - w / 2, cy - d / 2, z - 0.1, cx + w / 2, cy + d / 2, z, "steel_light", bevel=0.025)
    p.slab(cx - w / 2 + 0.05, cy - d / 2 + 0.05, z, cx + w / 2 - 0.05, cy + d / 2 - 0.05, z + 0.012, "screen_glass")
    iw, id_ = w - 0.14, d - 0.14
    for i in range(cols):
        for j in range(rows):
            x = cx - iw / 2 + (i + 0.5) * iw / cols
            y = cy - id_ / 2 + (j + 0.5) * id_ / rows
            p.slab(x - 0.012, y - 0.012, z + 0.012, x + 0.012, y + 0.012, z + 0.02, "steel_black")


def vents(p, x0, x1, y, z0, z1, n, face=-1, mat="steel_dark"):
    """Louvres on a vertical face at `y` (face -1: facing south)."""
    p.slab(x0, y, z0, x1, y + face * 0.015, z1, "steel_black")
    for k in range(n):
        z = z0 + (k + 0.5) * (z1 - z0) / n
        p.slab(x0 + 0.01, y + face * 0.015, z - 0.008, x1 - 0.01, y + face * 0.03, z + 0.008, mat)


def cable(p, points, mat, radius=0.022):
    p.pipe(points, radius, mat, segs=6)


def coil(p, a, b, radius=0.03, turns=8):
    """A coiled yellow cable from a to b: rings along a thin core."""
    from mathutils import Vector
    a, b = Vector(a), Vector(b)
    p.tube(a, b, radius * 0.6, "brass_coil", segs=6)
    d = (b - a) / turns
    for k in range(turns):
        c = a + d * (k + 0.5)
        p.tube(c - d * 0.25, c + d * 0.25, radius, "brass_coil", segs=8)


# ---------------------------------------------------------------------------------------------
# Combinators: 1x2, north = outputs. Each kind's sprites differ a little in size, so each has its
# own fitted body: (x0, x1, y0, y1, zm, zm2, h, inset_low, inset_top), the input pads (south end,
# top height, gap between them, their own undercut) and its posts (x, y, top) north and south.

COMBINATORS = {
    "arith": {"body": (-0.477, 0.46, -0.58, 0.56, 0.245, 0.275, 0.619, (0.178, 0.213), (0.078, 0.217)),
              "pads": (-0.68, 0.36, 0.115, 0.14), "north": (0.275, 0.608, 0.552), "south": (0.265, -0.667, 0.66)},
    "decider": {"body": (-0.456, 0.459, -0.578, 0.606, 0.268, 0.275, 0.776, (0.177, 0.03), (0.04, 0.337)),
                "pads": (-0.68, 0.22, 0.05, 0.08), "north": (0.26, 0.609, 0.687), "south": (0.264, -0.76, 0.765)},
    "selector": {"body": (-0.471, 0.489, -0.48, 0.636, 0.29, 0.305, 0.551, (0.193, 0.078), (0.085, 0.164)),
                 "pads": (-0.724, 0.378, 0.13, 0.134), "north": (0.215, 0.684, 0.545), "south": (0.197, -0.542, 0.52)},
}


def combinator_body(paint, kind, detail):
    """The shared body: a rounded block with a grille display on top, a bar with the two output
    posts at the north end, two input pads with posts at the south, the red and green wires
    draped from the inputs over the body to the outputs."""
    d = COMBINATORS[kind]
    x0, x1, y0, y1, zm, zm2, h, low, top = d["body"]
    p = Part()
    hull(p, block(x0, x1, y0, y1, zm, zm2, h, low, top), paint, bevel=0.03)
    # The dark foot under the undercut and a seam band round the widest part.
    p.slab(x0 + low[0] + 0.02, y0 + low[1] + 0.02, 0.0, x1 - low[0] - 0.02, y1 - low[1] - 0.02, 0.04, "steel_dark")
    p.slab(x0 - 0.008, y0 - 0.008, zm - 0.02, x1 + 0.008, y1 + 0.008, zm2 + 0.0, "steel_dark")
    # The display on top, towards the north as the sprites draw it, with a brace each side.
    ty0, ty1 = y0 + top[1], y1 - top[1]
    gw = min(0.46, x1 - x0 - 2 * top[0] - 0.04)
    cy = (ty0 + ty1) / 2 + 0.04
    grille(p, (x0 + x1) / 2, cy, h + 0.07, gw, min(0.4, ty1 - ty0 + 0.1))
    for sx in (-1, 1):
        x = (x0 + x1) / 2 + sx * (gw / 2 + 0.03)
        p.slab(x - 0.025, cy - 0.2, h - 0.06, x + 0.025, cy + 0.2, h + 0.03, "steel_light", bevel=0.008)
    # Outputs: posts on a bracket against the north face.
    nx, ny, nz = d["north"]
    for sx in (-1, 1):
        p.slab(sx * nx - 0.04, y1 - 0.08, 0.3, sx * nx + 0.04, ny, 0.36, "steel_dark", bevel=0.01)
    p.beam((-nx, ny, nz - 0.12), (nx, ny, nz - 0.12), 0.035, 0.035, "steel")
    post(p, -nx, ny, 0.28, nz - 0.04, "rubber_red")
    post(p, nx, ny, 0.28, nz - 0.04, "rubber_green")
    # Inputs: two pads at the south end, a post on each.
    py0, ph, gap, under = d["pads"]
    sx_, sy_, sz_ = d["south"]
    for sx, cap in ((-1, "rubber_red"), (1, "rubber_green")):
        xa, xb = sorted((sx * gap, x1 if sx > 0 else x0))
        hull(p, block(xa, xb, py0, y0 + 0.1, ph * 0.4, ph * 0.6, ph, (under, under), (0.03, 0.03)), paint, bevel=0.02)
        x = sx * sx_
        p.slab(x - 0.08, sy_ - 0.08, ph - 0.02, x + 0.08, sy_ + 0.08, ph + 0.015, "steel_dark", bevel=0.01)
        p.cyl((x, sy_, ph + 0.025), 0.06, 0.025, cap, segs=12)
        post(p, x, sy_, 0.05, max(sz_, ph + 0.12), cap, radius=0.032)
    # Wires from the inputs up over the top's edges to the outputs, as the sprites drape them.
    zt = max(sz_, ph + 0.12)
    for sx, mat in ((-1, "rubber_red"), (1, "rubber_green")):
        xe = sx * ((x1 - x0) / 2 - top[0] - 0.06)
        cable(p, [(sx * sx_, sy_, zt - 0.06), (sx * sx_ * 1.1, y0 + top[1] * 0.5, h - 0.04),
                  (xe, y0 + top[1] + 0.05, h + 0.03), (xe * 1.05, (y0 + y1) / 2, h + 0.04),
                  (xe, y1 - top[1] - 0.02, h + 0.03), (sx * nx, y1 - top[1] * 0.4, h - 0.06),
                  (sx * nx, ny, nz - 0.1)], mat, 0.03)
    detail(p, d)
    return p


def _arith_detail(p, d):
    """The east side's grille, a slot plate on the south face, the yellow coil on the west."""
    x0, x1, y0, y1, zm, zm2, h, low, top = d["body"]
    p.slab(x1 - 0.005, -0.1, zm2 + 0.03, x1 + 0.01, 0.3, h - 0.12, "steel_black")
    for k in range(4):
        p.slab(x1 + 0.005, -0.08 + k * 0.1, zm2 + 0.05, x1 + 0.02, -0.04 + k * 0.1, h - 0.14, "steel_light")
    p.slab(-0.12, y0 - 0.01, zm - 0.05, 0.12, y0 + 0.02, zm2 + 0.05, "steel_light", bevel=0.01)
    coil(p, (x0 - 0.01, 0.3, zm2 + 0.05), (x0 - 0.01, 0.0, zm2 + 0.05), radius=0.035, turns=6)


def _decider_detail(p, d):
    """Round ports on both sides and a ribbed plate on the south face."""
    x0, x1, y0, y1, zm, zm2, h, low, top = d["body"]
    for x in (x0, x1):
        p.cyl((x, 0.05, (zm + h) / 2), 0.08, 0.05, "steel", segs=12, axis="X", bevel=0.01)
        p.cyl((x, 0.05, (zm + h) / 2), 0.045, 0.07, "steel_black", segs=10, axis="X")
    vents(p, -0.16, 0.16, y0 + 0.01, zm - 0.04, zm2 + 0.08, 4, mat="steel_light")
    coil(p, (x1 - 0.06, y0 + 0.02, zm), (x1 - 0.06, y0 + 0.02, h - 0.12), radius=0.03, turns=5)


def _selector_detail(p, d):
    """A louvred panel on the south face and coiled yellow cables down both sides."""
    x0, x1, y0, y1, zm, zm2, h, low, top = d["body"]
    vents(p, -0.22, 0.22, y0 + 0.01, zm - 0.05, zm2 + 0.12, 5, mat="steel_light")
    coil(p, (x0 + 0.03, -0.3, zm2 + 0.04), (x0 + 0.03, 0.45, zm2 + 0.04), radius=0.035, turns=9)
    coil(p, (x1 - 0.04, -0.1, zm2 + 0.02), (x1 - 0.04, 0.45, zm2 + 0.06), radius=0.035, turns=7)


@model("arithmetic-combinator")
def arithmetic_combinator():
    """Factorio's arithmetic combinator: a blue-grey box, a grille display on top, red and green
    wires from two input pads (south) to two output posts (north)."""
    return combinator_body("paint_arith", "arith", _arith_detail)


@model("decider-combinator")
def decider_combinator():
    """Factorio's decider combinator: the combinator body in ochre, taller, with round side
    ports."""
    return combinator_body("paint_decider", "decider", _decider_detail)


@model("selector-combinator")
def selector_combinator():
    """Factorio's selector combinator (2.0): the combinator body in green, lower, a louvred front
    and coiled yellow cables down both sides."""
    return combinator_body("paint_selector", "selector", _selector_detail)


@model("constant-combinator")
def constant_combinator():
    """Factorio's constant combinator: a red block with rounded edges, two terminal posts on a bar
    at the back, a vent and a coiled yellow cable on the front, a grille on the east side."""
    p = Part()
    x0, x1, y0, y1 = -0.46, 0.468, -0.46, 0.447
    zm, zm2, h = 0.29, 0.3, 0.525
    hull(p, block(x0, x1, y0, y1, zm, zm2, h, (0.225, 0.195), (0.04, 0.278), top_dy=-0.135),
         "paint_constant", bevel=0.03)
    p.slab(x0 + 0.24, y0 + 0.21, 0.0, x1 - 0.24, y1 - 0.21, 0.04, "steel_dark")
    p.slab(x0 - 0.008, y0 - 0.008, zm - 0.03, x1 + 0.008, y1 + 0.008, zm2 + 0.01, "steel_dark")
    # Front: a vent panel under the top edge and a coil across.
    p.slab(-0.3, y0 + 0.1, h - 0.01, 0.05, y0 + 0.26, h + 0.015, "steel_dark", bevel=0.01)
    for k in range(5):
        p.slab(-0.27 + k * 0.065, y0 + 0.13, h + 0.01, -0.24 + k * 0.065, y0 + 0.23, h + 0.025, "steel_light")
    # The coil runs across the sloped front, held by two straps, and up the east side.
    coil(p, (x0 + 0.04, y0 + 0.05, 0.42), (x1 - 0.08, y0 + 0.05, 0.43), radius=0.04, turns=12)
    coil(p, (x1 - 0.08, y0 + 0.05, 0.43), (x1 - 0.06, 0.0, h - 0.02), radius=0.04, turns=6)
    for x in (-0.15, 0.12):
        p.slab(x - 0.025, y0 - 0.005, zm - 0.06, x + 0.025, y0 + 0.1, 0.48, "steel_light", bevel=0.008)
    # East: a grille.
    p.slab(x1 - 0.005, -0.25, zm2 - 0.02, x1 + 0.01, 0.2, zm2 + 0.12, "steel_black")
    for k in range(4):
        p.slab(x1 + 0.005, -0.23 + k * 0.11, zm2, x1 + 0.02, -0.18 + k * 0.11, zm2 + 0.1, "steel_dark")
    # The posts at the back, standing on the sloped top.
    py, top = 0.16, 0.79
    p.slab(-0.33, py - 0.08, 0.38, 0.27, py + 0.08, 0.47, "steel_dark", bevel=0.015)
    p.beam((-0.27, py, top - 0.14), (0.215, py, top - 0.14), 0.03, 0.03, "steel")
    post(p, -0.27, py, 0.42, top - 0.04, "rubber_red")
    post(p, 0.215, py, 0.42, top - 0.04, "rubber_green")
    cable(p, [(-0.27, py, top - 0.2), (-0.36, 0.0, h), (-0.42, -0.25, zm2 + 0.08)], "rubber_red", 0.026)
    return p


# ---------------------------------------------------------------------------------------------

@model("power-switch")
def power_switch():
    """Factorio's power switch: two blue cabinets standing apart on the tile, each a wedge rising
    to the back with a ribbed lever on top. The west one carries the rusty contact frame on its
    top with copper blades reaching east and two insulated terminals at its foot; the east one's
    top is cut away to the west, with a slotted hatch on that slope, a status lamp and a socket on
    its front."""
    p = Part()
    blue = "paint_switch"
    yf, yw, yb = -0.78, -0.71, 0.15

    def top_z(z_front, z_back, y):
        return z_front + (z_back - z_front) * (y - yw) / (yb - yw)

    # West cabinet: front 0.8 high, back 1.18, narrowing towards its top.
    hull(p, [(-1.02, yw, 0), (-0.25, yw, 0), (-1.02, yb, 0), (-0.25, yb, 0),
             (-1.01, yw, 0.8), (-0.26, yw, 0.8), (-0.92, yb, 1.18), (-0.38, yb, 1.18)], blue, bevel=0.03)
    # East cabinet: its west edge chamfered steeply where the hatch sits.
    hull(p, [(0.12, yf, 0), (1.01, yf, 0), (0.12, yb, 0), (1.01, yb, 0),
             (0.12, yf, 0.3), (0.42, yf, 0.74), (1.01, yf, 0.74),
             (0.12, yb, 0.52), (0.45, yb, 1.0), (0.97, yb, 1.0)], blue, bevel=0.03)
    # Feet: a dark plate under each, running back to the tile's north half.
    for xa, xb, y in ((-0.98, -0.29, yw), (0.16, 0.97, yf)):
        p.slab(xa, y + 0.01, 0.0, xb, 0.48, 0.05, "steel_dark", bevel=0.01)
    # The contact frame on the west cabinet's top, east half, and its copper blades.
    def tz(y):
        return top_z(0.8, 1.18, y)

    # It moves (anim_switch, model_library.gd SLIDE_KINDS): when the switch turns on it slides
    # east and down into the gap between the cabinets, its blades into the east one's hatch, as
    # the power_on_animation's 6 frames close it.
    contact = Part("anim_switch")
    frame = [(y, tz(y) + dz) for y, dz in ((-0.62, 0.0), (0.05, 0.0), (0.05, 0.06), (-0.62, 0.06))]
    contact.side_prism([(y, z - 0.02) for y, z in frame], -0.64, -0.36, "steel_dark", bevel=0.015)
    contact.side_prism([(-0.55, tz(-0.55) + 0.03), (-0.02, tz(-0.02) + 0.03), (-0.02, tz(-0.02) + 0.07),
                        (-0.55, tz(-0.55) + 0.07)], -0.61, -0.39, "rust_brown")
    # The blades reach east off the frame and hook down.
    for y in (-0.4, -0.2):
        z = tz(y) - 0.02
        contact.slab(-0.4, y - 0.045, z - 0.03, -0.06, y + 0.045, z + 0.02, "copper_prong", bevel=0.01)
        contact.slab(-0.1, y - 0.045, z - 0.1, -0.06, y + 0.045, z + 0.02, "copper_prong", bevel=0.01)
    # A lever on each cabinet's back, with a ribbed grip.
    for x, z0, z1 in ((-0.76, 1.15, 1.66), (0.93, 0.98, 1.42)):
        p.slab(x - 0.07, 0.01, z0 - 0.04, x + 0.07, 0.13, z0 + 0.04, "steel_dark", bevel=0.02)
        p.tube((x, 0.07, z0), (x - 0.02, 0.1, z1 - 0.1), 0.025, "steel_light", segs=6)
        for k in range(5):
            p.cyl((x - 0.02, 0.1, z1 - 0.18 + k * 0.04), 0.07 - k * 0.007, 0.025, "steel_light", segs=10)
    # Terminals on the west cabinet's foot, and their wires up to the frame.
    for x in (-0.9, -0.72):
        p.slab(x - 0.08, yw - 0.05, 0.04, x + 0.08, yw, 0.34, "steel_black")
        for k in range(3):
            p.cyl((x, yw - 0.03, 0.12 + k * 0.06), 0.06, 0.035, "ceramic", segs=10)
        p.cyl((x, yw - 0.03, 0.31), 0.03, 0.05, "steel_light", segs=6)
    cable(p, [(-0.9, yw - 0.03, 0.33), (-0.75, yw - 0.03, 0.42), (-0.5, yw, 0.62), (-0.42, -0.6, tz(-0.6))], "rubber_green", 0.025)
    cable(p, [(-0.72, yw - 0.03, 0.33), (-0.6, yw - 0.03, 0.44), (-0.45, yw, 0.66), (-0.38, -0.58, tz(-0.58))], "rubber_red", 0.025)
    # The hatch on the east cabinet's chamfer: a frame and two slots, square to the slope.
    slope = math.degrees(math.atan2(0.72 - 0.3, 0.45 - 0.12))
    hatch = Part()
    hatch.slab(-0.19, -0.36, 0.0, 0.19, 0.36, 0.04, "steel_dark", bevel=0.015)
    for y in (-0.12, 0.12):
        hatch.slab(-0.14, y - 0.025, 0.035, 0.14, y + 0.025, 0.05, "steel_black")
    p.add_part(hatch, T(0.275, -0.25, 0.665) @ R("Y", -slope))
    # Status lamp and socket on the east cabinet's front.
    p.cyl((0.72, yf - 0.02, 0.5), 0.06, 0.05, "steel_dark", segs=10, axis="Y")
    p.sphere((0.72, yf - 0.04, 0.5), 0.04, "led_green", segs=8, rings=4)
    p.cyl((0.72, yf - 0.02, 0.36), 0.05, 0.04, "steel_dark", segs=10, axis="Y")
    p.slab(0.36, yf - 0.03, 0.06, 0.7, yf, 0.26, "steel_dark", bevel=0.01)
    p.slab(0.42, yf - 0.045, 0.1, 0.64, yf - 0.02, 0.22, "steel_black")
    return [p, contact]


@model("programmable-speaker")
def programmable_speaker():
    """Factorio's programmable speaker: a tall cream pole on a heavy round foot, three horns on
    top (one west, one up to the north-east, one facing south) and a red and a green wire running
    up it. The sprite stands it a little north of the tile's middle."""
    p = Part()
    # The sprite's foot sits a quarter tile north of the tile's middle; the model goes as far as
    # the footprint check allows (0.18) and stands that much taller instead.
    cx, cy = -0.02, 0.18
    p.cyl((cx, cy, 0.05), 0.19, 0.1, "steel_dark", segs=16, bevel=0.02)
    p.cyl((cx, cy, 0.2), 0.16, 0.2, "paint_cream", segs=16, bevel=0.03)
    p.cyl((cx, cy, 0.52), 0.13, 0.5, "paint_cream", segs=16, bevel=0.02)
    p.cyl((cx, cy, 0.8), 0.1, 0.06, "steel_dark", segs=14, bevel=0.01)
    hub = 3.11
    p.cyl((cx, cy, (0.55 + hub) / 2), 0.08, hub - 0.55, "paint_cream", segs=12, radius_top=0.065)
    p.cyl((cx, cy, hub), 0.09, 0.16, "steel_dark", segs=12)

    def horn(mouth, radius, length=0.3):
        """A horn from the hub out to its mouth's centre, flaring to `radius`."""
        from mathutils import Vector
        root = Vector((cx, cy, hub))
        tip = Vector(mouth)
        d = (tip - root).normalized()
        neck = tip - d * length
        p.tube(root, neck, 0.035, "steel_dark", segs=6)
        p.tube(neck, tip, 0.045, "paint_cream", segs=12, radius_top=radius)
        p.tube(neck + d * 0.05, tip + d * 0.005, 0.03, "steel_black", segs=12, radius_top=radius - 0.025)

    horn((-0.4, cy, 3.3), 0.14, length=0.26)
    horn((0.24, 0.32, 3.51), 0.13, length=0.26)
    horn((0.2, -0.06, 3.39), 0.13, length=0.22)
    cable(p, [(cx + 0.06, cy - 0.06, 0.6), (cx + 0.08, cy - 0.08, 2.0), (cx + 0.12, cy - 0.1, hub - 0.2)], "rubber_red", 0.018)
    cable(p, [(cx + 0.02, cy - 0.08, 0.6), (cx + 0.04, cy - 0.09, 2.2), (cx, cy - 0.1, hub - 0.1)], "rubber_green", 0.018)
    return p


@model("display-panel")
def display_panel():
    """Factorio's display panel (2.0): a squat olive block on a dark foot carrying a big dark
    rounded screen, tipped only a little towards the south: Factorio draws the screen facing the
    viewer whichever way the panel turns, so lying nearly flat it reads the same in all four.
    Terminal posts at the screen's back corners, a coiled cable and a vent on the front."""
    p = Part()
    x0, x1, y0, y1 = -0.427, 0.442, -0.37, 0.44
    zm, h = 0.318, 0.413
    hull(p, block(x0, x1, y0, y1, zm, zm + 0.01, h, (0.205, 0.145), (0.05, 0.09)), "paint_panel", bevel=0.03)
    p.slab(x0 + 0.22, y0 + 0.16, 0.0, x1 - 0.22, y1 - 0.16, 0.04, "steel_dark")
    # The screen: a slab from (y, z) = (-0.36, 0.51) to (0.315, 0.62), its corners rounded, on a
    # dark pedestal.
    (ya, za), (yb, zb) = (-0.36, 0.51), (0.315, 0.62)
    length = math.hypot(yb - ya, zb - za)
    tilt = math.degrees(math.atan2(zb - za, yb - ya))
    w, cut, thick = 0.383, 0.195, 0.1
    arc = [(math.cos(math.radians(a)), math.sin(math.radians(a))) for a in (0, 30, 60, 90)]
    outline = [(w - cut + cut * c, cut - cut * s) for c, s in reversed(arc)]
    outline += [(w - cut + cut * c, length - cut + cut * s) for c, s in arc]
    outline = outline + [(-x, y) for x, y in reversed(outline)]
    screen = Part()
    screen.prism(outline, -thick, 0.0, "steel_dark", bevel=0.02)
    inner = [(x * 0.9, 0.035 + y * (1 - 0.07 / length)) for x, y in outline]
    screen.prism(inner, -0.01, 0.012, "screen_glass")
    # Screen frame: x across, y up the slab, z out of its face.
    p.add_part(screen, T(0, ya, za) @ R("X", tilt) @ T(0, 0, thick))
    p.slab(-0.25, -0.22, h - 0.04, 0.25, 0.25, za + 0.06, "steel_dark", bevel=0.02)
    # Front: a vent box in the undercut and a coiled cable up to the screen.
    p.slab(-0.33, y0 + 0.02, 0.16, 0.01, y0 + 0.14, zm, "steel_dark", bevel=0.01)
    vents(p, -0.31, -0.01, y0 + 0.02, 0.18, zm - 0.02, 3)
    coil(p, (0.1, y0 - 0.01, zm - 0.04), (0.33, -0.2, za + 0.02), radius=0.035, turns=7)
    # Back: the terminal posts at the screen's corners and a coil between them.
    coil(p, (0.05, 0.36, h), (0.0, 0.36, 0.72), radius=0.035, turns=5)
    post(p, -0.37, 0.46, 0.3, 0.64, "rubber_red", radius=0.028)
    post(p, 0.38, 0.46, 0.3, 0.6, "rubber_green", radius=0.028)
    cable(p, [(-0.37, 0.46, 0.45), (-0.44, 0.2, zm + 0.04), (-0.44, -0.12, zm - 0.02)], "rubber_red", 0.022)
    cable(p, [(0.38, 0.46, 0.42), (0.45, 0.15, zm + 0.04), (0.44, -0.2, zm - 0.02)], "rubber_green", 0.022)
    return p


# ---------------------------------------------------------------------------------------------
# Valves (2.0): Factorio draws each as a flat grey plate 0.94 tiles square on screen (black rim,
# a cross bolt in each corner, the flow arrow and the valve's two bars), one picture per direction
# with the symbol laid out afresh, not turned. Here a grey housing sitting on the pipe, sized so
# that from Factorio's camera (the pipe kit's, PIPE_FIT: a point shows y + 0.669 z up the screen)
# its top and front together fill that square, and the picture's markings are laid over both
# faces where they show in it. One model per direction (model_library.gd FACING_MODELS, drawn
# unturned): the housing stays put, the pipe runs north-south or east-west under it.

V_HALF = 0.462             # half the plate's side (its 60 of 64 pixels, less the markings' depth)
V_Z0, V_Z1 = KIT_Z, 0.76   # the housing's foot (on the pipe's middle) and top
# Its front sits on the tile's south edge, so its foot shows at the picture's bottom edge; its
# depth makes its top edge the picture's top edge.
V_Y0 = -0.5
V_Y1 = (V_HALF + 0.375 * 0.669) - 0.669 * V_Z1
V_EDGE = V_Y0 + 0.669 * V_Z1 - 0.375 * 0.669  # the front's top edge, as height in the picture


def _decal(p, u0, v0, u1, v1, mat="steel_black", h=0.012, bevel=0.0):
    """A rectangle of the picture (u right, v up from its middle, in tiles) laid over the
    housing: the part above V_EDGE on its top, the rest down its front."""
    if v1 > V_EDGE:
        a = max(v0, V_EDGE)
        p.slab(u0, V_Y0 + a - V_EDGE, V_Z1, u1, V_Y0 + v1 - V_EDGE, V_Z1 + h, mat, bevel=bevel)
    if v0 < V_EDGE:
        b = min(v1, V_EDGE)
        p.slab(u0, V_Y0 - h, V_Z1 - (V_EDGE - v0) / 0.669, u1, V_Y0, V_Z1 - (V_EDGE - b) / 0.669, mat, bevel=bevel)


def _decal_tri(p, pts, mat="steel_black", h=0.012):
    """A triangle of the picture, on whichever face its middle falls (kept on that face)."""
    v = sum(q[1] for q in pts) / 3
    if v >= V_EDGE:
        p.prism([(u, V_Y0 + max(w, V_EDGE) - V_EDGE) for u, w in pts], V_Z1, V_Z1 + h, mat)
    else:
        # Prism frame: (u, w, e) -> (u, -e, w) after R("X", 90); w is the height on the front.
        p.prism([(u, V_Z1 - (V_EDGE - min(w, V_EDGE)) / 0.669) for u, w in pts], 0.0, h, mat,
                matrix=T(0, V_Y0, 0) @ R("X", 90))


def valve(facing, bars):
    """A valve facing `facing` (0 north .. 3 west: the way it lets fluid through) with its two bars
    long or short (`bars`: first is the upper bar in the north and south pictures, the left one in
    the east and west ones)."""
    p = Part()
    ns = facing % 2 == 0
    # The pipe under the housing, as the kit's: north-south with the whole flange straddling the
    # north edge (the southern neighbour carries the south joint's, and the pipe's south end is cut
    # back where the picture stops); east-west with flanges just inside both edges.
    if ns:
        arm = Part()
        # (Its end just behind the housing's front, which stands on the tile's edge.)
        arm.cyl((0, 0.005, KIT_Z), KIT_R["Y"], 0.99, "steel", segs=16, axis="Y")
        p.add_part(arm.warp(south_cut))
        # Only the flange's lower half: the northern neighbour draws its top half (fluids.py
        # half_flange), and a whole one would rise far above the picture's plate.
        k, rf = Part(), KIT_FLANGE_R["Y"] + 0.006
        k.ring_band((0, 0), 0.0, rf, -0.04, 0.04, 180, 360, "rust_brown", segs=8, bevel=0.01)
        p.add_part(k, T(0, 0.5, KIT_Z) @ R("X", 90))
        for i in range(4):
            a = math.pi * (i + 0.5) / 4
            p.cyl(((rf - 0.04) * math.cos(a), 0.5, KIT_Z - (rf - 0.04) * math.sin(a)), 0.018, 0.1,
                  "steel_light", segs=5, axis="Y")
    else:
        # (The flanges a little further in than the kit's, under the housing's ends.)
        p.cyl((0, 0, KIT_Z), KIT_R["X"], 1.0, "steel", segs=16, axis="X")
        for sx in (-1, 1):
            flange_ring(p, (sx * 0.42, 0, KIT_Z), "X", radius=KIT_FLANGE_R["X"])
    # A post holding the pipe off the ground, as the kit's (hidden under the housing).
    p.cyl((0, 0, (KIT_Z - 0.25) / 2), 0.07, KIT_Z - 0.25, "steel_dark", segs=8)
    # The housing: grey, its edges a little rounded; a black rim round what the picture shows.
    p.slab(-V_HALF, V_Y0, V_Z0, V_HALF, V_Y1, V_Z1, "paint_valve", bevel=0.012)
    rim = 0.031
    _decal(p, -V_HALF, V_HALF - rim, V_HALF, V_HALF)
    _decal(p, -V_HALF, -V_HALF, V_HALF, -V_HALF + rim)
    for sx in (-1, 1):
        _decal(p, sx * V_HALF - (rim if sx > 0 else 0), -V_HALF, sx * V_HALF + (rim if sx < 0 else 0), V_HALF)
    # The housing's ends and back: the same rim round their edges, the plate's grey inside.
    for sx in (-1, 1):
        x = sx * (V_HALF + 0.002)
        p.slab(x - 0.002, V_Y0, V_Z0, x + 0.002, V_Y1, V_Z0 + rim, "steel_black")
        p.slab(x - 0.002, V_Y1 - rim, V_Z0, x + 0.002, V_Y1, V_Z1, "steel_black")
    p.slab(-V_HALF, V_Y1, V_Z0, V_HALF, V_Y1 + 0.012, V_Z0 + rim, "steel_black")
    # A cross bolt in each corner: two on the top, two down the front.
    for su in (-1, 1):
        for sv in (-1, 1):
            cu, cv = su * 0.359, sv * 0.359
            _decal(p, cu - 0.047, cv - 0.016, cu + 0.047, cv + 0.016)
            _decal(p, cu - 0.016, cv - 0.047, cu + 0.016, cv + 0.047)
    # The arrow: a thin shaft with a head, along the left side (north, south) or the top (east, west).
    head, half_w = 0.11, 0.032
    if ns:
        sgn = 1 if facing == 0 else -1
        u = -0.266
        _decal(p, u - 0.008, -0.258, u + 0.008, 0.258)
        tip = sgn * 0.266
        base = tip - sgn * head
        _decal_tri(p, [(u - half_w, base), (u + half_w, base), (u, tip)] if sgn > 0 else
                   [(u + half_w, base), (u - half_w, base), (u, tip)])
    else:
        sgn = 1 if facing == 1 else -1
        v = 0.266
        _decal(p, -0.258, v - 0.008, 0.258, v + 0.008)
        tip = sgn * 0.266
        base = tip - sgn * head
        _decal_tri(p, [(base, v - half_w), (tip, v), (base, v + half_w)] if sgn > 0 else
                   [(base, v + half_w), (tip, v), (base, v - half_w)])
    # The two bars: rounded, long or short.
    for k, long_ in enumerate(bars):
        if ns:
            v0, v1 = (0.094, 0.203) if k == 0 else (-0.203, -0.094)
            _decal(p, -0.125 if long_ else 0.031, v0, 0.297, v1, h=0.016, bevel=0.006)
        else:
            u0, u1 = (-0.203, -0.094) if k == 0 else (0.094, 0.203)
            _decal(p, u0, -0.297, u1, 0.125 if long_ else -0.031, h=0.016, bevel=0.006)
    return p


# Which bar is short in each picture (north, east, south, west): (first long, second long).
VALVE_BARS = {
    "one-way-valve": [(True, True)] * 4,
    "overflow-valve": [(False, True), (True, False), (True, False), (False, True)],
    "top-up-valve": [(True, False), (False, True), (False, True), (True, False)],
}


def _register_valves():
    for name, bars in VALVE_BARS.items():
        for facing, sfx in enumerate(("", "-east", "-south", "-west")):
            model(name + sfx)(lambda f=facing, b=bars[facing]: valve(f, b))


_register_valves()


# ---------------------------------------------------------------------------------------------

@model("pump")
def pump():
    """Factorio's pump facing north (output north): a pipe running the length of its two tiles
    with flanges at both ends, a dark frame round two cylinders with windows in the middle, and
    two pairs of orange ribbed hoses arching from the cylinders down into the pipe at either
    end; gear wheels on the east side. The east and west pictures draw the cylinder unit leaning,
    its south (input) end higher, so it leans here too."""
    from mathutils import Vector
    p = Part()
    z = PIPE_Z
    p.cyl((0, 0, z), PIPE_R * 0.95, 1.86, "steel", segs=16, axis="Y")
    for sy in (-1, 1):
        flange_ring(p, (0, sy * 0.955, z), "Y")
        p.cyl((0, sy * 0.72, z), PIPE_R * 1.08, 0.2, "steel_dark", segs=16, axis="Y", bevel=0.02)
    # Low rails either side of the pipe, the frame's feet.
    for sx in (-1, 1):
        p.slab(sx * 0.3, -0.85, RAIL_Z0, sx * RAIL_X, 0.85, RAIL_Z0 + 0.22, "steel_dark", bevel=0.03)
    # The motor frame's foot: a dark box straddling the pipe.
    p.slab(LOW_X0, -0.42, 0.0, LOW_X1, 0.42, 0.72, "steel_dark", bevel=0.04)
    lean = T(0, PIVOT_Y, PIVOT_Z) @ R("X", -LEAN) @ T(0, -PIVOT_Y, -PIVOT_Z)
    p.slab(-0.44, -0.44, CYL_Z - 0.3, 0.44, 0.44, CYL_Z - 0.2, "steel_dark", bevel=0.03, matrix=lean)
    pistons = []
    for sx in (-1, 1):
        x = sx * 0.21
        p.cyl((x, 0.0, CYL_Z), 0.19, 0.62, "steel", segs=14, axis="Y", bevel=0.03, matrix=lean)
        p.slab(x - 0.13, -0.26, CYL_Z + 0.15, x + 0.13, 0.26, CYL_Z + 0.2, "steel_black", matrix=lean)
        # The pistons run up and down their windows while it pumps, in turn (anim_bob_*).
        piston = Part("anim_bob_a" if sx < 0 else "anim_bob_b")
        piston.slab(x - 0.07, -0.17, CYL_Z + 0.18, x + 0.05, -0.03, CYL_Z + 0.22, "paint_cream", bevel=0.01, matrix=lean)
        pistons.append(piston)
        for y in (-0.33, 0.33):
            p.cyl((x, y, CYL_Z), 0.22, 0.06, "steel_dark", segs=14, axis="Y", matrix=lean)
        # Hoses: from each end of the cylinder, arching out and down into the pipe.
        for sy in (-1, 1):
            a = lean @ Vector((x, sy * 0.33, CYL_Z + 0.05))
            b = lean @ Vector((x, sy * 0.58, CYL_Z - 0.02))
            hose(p, [tuple(a), tuple(b), (x * HOSE_SPREAD, sy * 0.78, z + 0.12)], 0.125, ribs=3)
    # East side gears below the frame, and a motor block on the west.
    for y, r in ((-0.15, 0.17), (0.2, 0.15)):
        p.cyl((LOW_X1 + 0.01, y, 0.3), r, 0.05, "steel_dark", segs=14, axis="X")
        for k in range(10):
            a = 2 * math.pi * k / 10
            p.slab(LOW_X1, y + (r + 0.02) * math.cos(a) - 0.02, 0.3 + (r + 0.02) * math.sin(a) - 0.02,
                   LOW_X1 + 0.03, y + (r + 0.02) * math.cos(a) + 0.02, 0.3 + (r + 0.02) * math.sin(a) + 0.02, "steel_dark")
    p.slab(LOW_X0 - 0.06, -0.25, 0.1, LOW_X0, 0.25, 0.45, "steel", bevel=0.02)
    return [p] + pistons


LOW_X0, LOW_X1 = -0.3, 0.3   # the foot box, narrower than the unit on it (the side views' gears sit under it)
PIVOT_Y, PIVOT_Z, LEAN, CYL_Z, HOSE_SPREAD = -0.3, 0.66, 16.0, 0.82, 1.5
RAIL_X, RAIL_Z0 = 0.48, 0.32
