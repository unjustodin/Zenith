"""Belts, undergrounds and splitters. Items flow north (+y). The yellow is `tier_paint`, which
the client recolours for the fast/express/turbo tiers.

Belt cross-section (shared by every model here so they line up tile to tile): the belt surface
spans x -0.40..0.40 with its top at z 0.12 (items ride at 0.16 in the client), with a yellow
side rail 0.08 wide on each side, 0.17 tall.
"""

import math

from kit import Part, R, S, T, model

SURFACE_TOP = 0.12
SURFACE_BOTTOM = 0.05
RAIL_TOP = 0.17
HALF = 0.40  # half width of the belt surface
RAIL = 0.08  # rail width


def chevron(part, matrix):
    """A flat arrow on the belt surface pointing +y, built around the origin."""
    for side in (-1, 1):
        x0, y0 = 0.0, 0.07
        x1, y1 = side * 0.33, -0.10
        length = math.hypot(x1 - x0, y1 - y0)
        angle = math.degrees(math.atan2(y1 - y0, x1 - x0))
        part.box(((x0 + x1) / 2, (y0 + y1) / 2, SURFACE_TOP + 0.006), (length + 0.04, 0.05, 0.014),
                 "steel_dark", matrix=matrix, rz=angle)


def straight_section(part, x=0.0, y0=-0.5, y1=0.5, chevrons=(-0.33, 0.0, 0.33), bolts=True):
    """One belt lane centred on `x`, running from y0 to y1."""
    part.slab(x - HALF, y0, SURFACE_BOTTOM, x + HALF, y1, SURFACE_TOP, "belt_surface")
    for side in (-1, 1):
        inner = x + side * HALF
        outer = x + side * (HALF + RAIL)
        part.slab(min(inner, outer), y0, 0.02, max(inner, outer), y1, RAIL_TOP, "tier_paint", bevel=0.012)
        if bolts:
            for by in (y0 + 0.25 * (y1 - y0), y0 + 0.75 * (y1 - y0)):
                part.bolt((outer + side * 0.006, by, 0.10), "steel_light", 0.02, 0.014, axis="X")
    # Cross members under the belt, and little feet so it doesn't look like a floating slab.
    for cy in (y0 + 0.2 * (y1 - y0), y0 + 0.8 * (y1 - y0)):
        part.slab(x - HALF, cy - 0.04, 0.0, x + HALF, cy + 0.04, SURFACE_BOTTOM, "steel_black")
    for cy in chevrons:
        chevron(part, T(x, cy, 0))
    return part


@model("transport-belt")
def transport_belt():
    return straight_section(Part())


def bend_left(co, corner):
    """Maps a point on a straight north-flowing tile onto the left curve: y -0.5..0.5 becomes
    the angle -90..0 degrees round `corner`, and x (right of the flow) becomes the radius."""
    angle = math.radians((co.y + 0.5) * 90.0 - 90.0)
    r = 0.5 + co.x
    return (corner[0] + r * math.cos(angle), corner[1] + r * math.sin(angle), co.z)


def curve_left():
    """Output to the north edge, input from the west edge: items turn left. The belt bends
    around the north-west corner of the tile."""
    p = Part()
    c = (-0.5, 0.5)
    p.ring_band(c, 0.5 - HALF, 0.5 + HALF, SURFACE_BOTTOM, SURFACE_TOP, -90, 0, "belt_surface", segs=8)
    p.ring_band(c, 0.5 + HALF, 0.5 + HALF + RAIL, 0.02, RAIL_TOP, -90, 0, "tier_paint", segs=10, bevel=0.012)
    p.ring_band(c, 0.5 - HALF - RAIL, 0.5 - HALF, 0.02, RAIL_TOP, -90, 0, "tier_paint", segs=3, bevel=0.012)
    # Arrows and cross members are built as on a straight belt, then bent round the corner.
    details = Part()
    for y in (-0.33, 0.0, 0.33):
        chevron(details, T(0, y, 0))
    for y in (-0.3, 0.3):
        details.slab(-HALF, y - 0.04, 0.0, HALF, y + 0.04, SURFACE_BOTTOM, "steel_black")
    p.add_part(details.warp(lambda co: bend_left(co, c)))
    return p


@model("transport-belt-curve-left")
def transport_belt_curve_left():
    return curve_left()


@model("transport-belt-curve-right")
def transport_belt_curve_right():
    # Mirroring keeps the arrows pointing along the flow: east edge -> north edge.
    return curve_left().mirror_x()


def underground_hood(part):
    """The housing over the north half of an entrance, open to the south."""
    profile = [(-0.16, 0.0), (0.47, 0.0), (0.47, 0.44), (0.38, 0.54), (-0.04, 0.54), (-0.16, 0.42)]
    for x0, x1 in ((-0.48, -0.39), (0.39, 0.48)):
        part.side_prism(profile, x0, x1, "tier_paint", bevel=0.015)
    # Roof and back wall between the side walls.
    part.slab(-0.39, -0.10, 0.44, 0.39, 0.42, 0.52, "tier_paint", bevel=0.01)
    part.slab(-0.39, 0.38, 0.0, 0.39, 0.46, 0.44, "tier_paint", bevel=0.01)
    # A dark interior, so the opening reads as a tunnel mouth.
    part.slab(-0.39, 0.0, 0.0, 0.39, 0.38, 0.44, "soot")
    # A steel lip over the opening, and a ribbed cap on the roof.
    part.slab(-0.44, -0.18, 0.40, 0.44, -0.12, 0.47, "steel_dark", bevel=0.01)
    for rx in (-0.22, 0.0, 0.22):
        part.slab(rx - 0.05, 0.0, 0.52, rx + 0.05, 0.36, 0.55, "steel_dark", bevel=0.008)
    for bx in (-0.43, 0.43):
        for by in (0.05, 0.3):
            part.bolt((bx * 1.1, by, 0.3), "steel_light", 0.022, 0.014, axis="X")
    return part


@model("underground-belt-input")
def underground_belt_input():
    """Entrance: the belt comes in from the south edge and dives under the hood."""
    p = Part()
    straight_section(p, y0=-0.5, y1=0.05, chevrons=(-0.3,), bolts=False)
    underground_hood(p)
    return p


@model("underground-belt-output")
def underground_belt_output():
    """Exit: the belt comes out of the hood (south half) and leaves by the north edge."""
    p = Part()
    straight_section(p, y0=-0.05, y1=0.5, chevrons=(0.3,), bolts=False)
    hood = underground_hood(Part())
    p.add_part(hood.mirror_y())
    return p


@model("splitter")
def splitter():
    """Factorio's splitter (its 2.x sprites, all four directions): two belt lanes run through a
    dark gearbox as deep as the belts, almost to their north end. On its lid lie spoked gear
    wheels under four pale oval cranks (each pair over a lane lifts its inner ends together and lays
    them down once a loop, the pairs half a loop apart); a rod runs along its front top edge between two tall end posts, over a toothed
    rack and a rack housing at the east end, and a chain loops down off the east end. Behind it,
    over the belts' north ends, a yellow guard per lane bent to a point in the flow direction
    (`tier_paint`: red, blue and green for the faster tiers). Built at true depth for the
    projection's north-south stretch. 2 tiles wide, 1 deep."""
    p = Part()
    for x in (-0.5, 0.5):
        straight_section(p, x=x, chevrons=(), bolts=False)  # the arrows would be inside the case
    gears = []
    splitter_housing(p, gears)
    return [p] + gears


def splitter_housing(p, gears=None):
    """Everything of the splitter but its belts (the lane splitter wears it at half size). Its
    gear wheels, oval cranks and rack housing go into `gears` as parts of their own (anim_spin_gear,
    anim_crank_split_*, anim_slide_split_rack: they move while the belt runs, as the structure's 32
    frames do), or into `p` without a list."""
    # The gearbox: a dark lower case round the belts, a rusty band and the lid above.
    # Its lid slopes down to the front: Factorio's north and south pictures are barely taller than
    # the tile, so the gearbox can't be tall at its front and back edges.
    p.side_prism([(-0.46, 0.0), (0.24, 0.0), (0.24, 0.42), (-0.46, 0.24)], -0.95, 0.95, "steel_black", bevel=0.02)
    p.side_prism([(-0.44, 0.24), (0.22, 0.42), (0.22, 0.6), (-0.44, 0.36)], -0.93, 0.93, "steel_dark", bevel=0.02)
    p.slab(-0.96, -0.47, 0.0, 0.96, -0.36, 0.08, "steel_dark", bevel=0.01)
    # Spoked gear wheels lying on the lid.
    for gx, gy, r in ((-0.58, 0.02, 0.22), (0.02, -0.02, 0.24), (0.58, 0.02, 0.22)):
        g = Part("anim_spin_gear", pivot=(gx, gy, 0.63)) if gears is not None else p
        g.ring_band((gx, gy), r - 0.05, r, 0.6, 0.66, 0, 360, "steel", segs=14)
        for k in range(6):
            g.box((gx, gy, 0.63), (2 * r - 0.06, 0.03, 0.04), "rust", rz=k * 30)
        g.cyl((gx, gy, 0.67), 0.05, 0.04, "steel", segs=8)
        if gears is not None:
            gears.append(g)
    # Oval cranks: a pair over each lane, each pivoted at its outer end on the north-south axis.
    # Factorio's 32-frame structure lifts a pair's inner ends towards each other and lays them
    # down again once a loop, the east pair half a loop after the west one (anim_crank_split_*,
    # ModelLibrary.CYCLES); at rest they lie flat end to end, as in its frames 8 and 24.
    for kind, px, sign, cy in (("crank_split_wa", -0.9, 1, -0.02), ("crank_split_wb", -0.2, -1, -0.02),
                               ("crank_split_ea", 0.03, 1, -0.16), ("crank_split_eb", 0.73, -1, -0.16)):
        c = Part("anim_" + kind, pivot=(px, cy, 0.7)) if gears is not None else p
        cx = px + sign * 0.17
        c.cyl((0, 0, 0), 0.075, 0.07, "steel_light", segs=12, bevel=0.015,
              matrix=T(cx, cy, 0.7) @ S(2.3, 1.0, 1.0))
        c.cyl((px + sign * 0.07, cy, 0.75), 0.035, 0.03, "steel", segs=6)
        if gears is not None:
            gears.append(c)
    # The front: a rod between two tall posts, the rack under it and its housing at the east end.
    for x in (-0.87, 0.87):
        p.cyl((x, -0.38, 0.28), 0.075, 0.56, "steel", segs=10, bevel=0.01)
        p.cyl((x, -0.38, 0.57), 0.05, 0.03, "steel_dark", segs=8)
    p.cyl((0.0, -0.43, 0.44), 0.055, 1.72, "steel_light", segs=10, axis="X")
    # The rack housing slides along the rod to the west end and back once a loop (frames 0-16).
    rack = Part("anim_slide_split_rack", pivot=(0.6, -0.43, 0.38)) if gears is not None else p
    rack.slab(0.42, -0.49, 0.26, 0.78, -0.36, 0.5, "steel", bevel=0.015)
    if gears is not None:
        gears.append(rack)
    for k in range(14):
        x = -0.3 + k * 0.055
        p.slab(x, -0.49, 0.36, x + 0.03, -0.45, 0.44, "rust")
    p.slab(-0.32, -0.48, 0.32, 0.48, -0.44, 0.37, "steel_dark")
    # The chain looping down the east end (Factorio lets it hang past the tile; ours stays on it).
    for k in range(14):
        a = math.radians(k * 360 / 14)
        p.box((0.985, -0.22 + 0.17 * math.cos(a), 0.3 + 0.2 * math.sin(a)), (0.04, 0.05, 0.05), "steel_black")
    # The guards: per lane a plate bent to a point northwards, raised over the belt.
    for x in (-0.5, 0.5):
        prof = [(x - 0.47, 0.24), (x, 0.38), (x + 0.47, 0.24), (x + 0.47, 0.33), (x, 0.47), (x - 0.47, 0.33)]
        p.prism(prof, 0.18, 0.44, "tier_paint", bevel=0.012)
        for bx in (x - 0.36, x + 0.36):
            p.bolt((bx, 0.27 + 0.0, 0.38), "steel_light", 0.022, 0.014, axis="Y")
    return p
