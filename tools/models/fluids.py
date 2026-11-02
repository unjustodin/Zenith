"""Fluid handling: offshore pump, pipes, pipe-to-ground, storage tank.

Each model is matched to Factorio's HR sprite with compare.py (see client/assets/models/README.md,
"Matching a sprite"). Pipes run at PIPE_Z, the height of the boiler's and steam engine's
connections, so flanges line up between neighbours.

Pipes come as a kit of 16 shapes named after Factorio's pipe pictures (`pipe-straight-vertical`,
`pipe-corner-up-right`, `pipe-t-left`, `pipe-ending-down`, ...): the client picks one from which
neighbours a pipe connects to (world.gd). "up" is north, as in the sprites' names.
"""

import math

import facings
from kit import Part, R, S, T, model
from power import PIPE_Z as BOILER_PIPE_Z

PIPE_R = 0.3       # the pipe's body
FLANGE_R = 0.39    # the bolted ring at each tile edge
# A little above the boiler's connections (BOILER_PIPE_Z): the sprites' flanges are bigger.
PIPE_Z = BOILER_PIPE_Z + 0.14
# The pipe kit's own pipe, a little lower than the connections above. Factorio's pipe pictures
# draw the pipe round on screen, about 0.6 tiles across either way, and the projection's
# north-south stretch makes a round east-west pipe look taller than that: east-west pipes and
# flanges are a little thinner than north-south ones (fitted with score.py over the kit).
KIT_Z = 0.42
KIT_R = {"Y": 0.3, "X": 0.27}         # by the axis the pipe runs along
KIT_FLANGE_R = {"Y": 0.4, "X": 0.34}
ARMS = {"N": (0, 1), "E": (1, 0), "S": (0, -1), "W": (-1, 0)}


def flange_ring(p, centre, axis, radius=FLANGE_R, bolts=8):
    """A bolted pipe flange facing along `axis` ("X" or "Y")."""
    p.cyl(centre, radius, 0.07, "rust_brown", segs=16, axis=axis, bevel=0.012)
    x, y, z = centre
    for i in range(bolts):
        a = 2 * math.pi * (i + 0.5) / bolts
        off = (radius - 0.035) * math.cos(a), (radius - 0.035) * math.sin(a)
        at = (x, y + off[0], z + off[1]) if axis == "X" else (x + off[0], y, z + off[1])
        p.cyl(at, 0.018, 0.09, "steel_light", segs=5, axis=axis)


def end_cap(p, centre, axis, sign, radius=FLANGE_R):
    """A blind flange with stepped rings, closing a pipe end (the sprites' "ending" pictures)."""
    x, y, z = centre
    k_ = radius / FLANGE_R
    for k, (r, d) in enumerate(((radius, 0.07), (0.27 * k_, 0.05), (0.19 * k_, 0.05), (0.11 * k_, 0.04))):
        off = sign * (0.035 + 0.05 * k)
        at = (x + off, y, z) if axis == "X" else (x, y + off, z)
        p.cyl(at, r, d, "rust_brown" if k == 0 else "steel", segs=16, axis=axis, bevel=0.01)


def half_flange(p, centre, radius=KIT_FLANGE_R["Y"] + 0.006, depth=0.08):
    """The upper half of a north-south joint's flange. Factorio draws each joint's flange whole on
    the southern pipe (its north flange straddles the tile edge) and its top again on the northern
    one, cut where that picture ends; the northern pipe carries this half so that one alone looks
    the same. A shade bigger than the whole flange, so their faces never coincide."""
    x, y, z = centre
    k = Part()
    k.ring_band((0, 0), 0.0, radius, -depth / 2, depth / 2, 0, 180, "rust_brown", segs=8, bevel=0.01)
    k.transform(T(x, y, z) @ R("X", 90))
    p.add_part(k)
    for i in range(4):
        a = math.pi * (i + 0.5) / 4
        p.cyl((x + (radius - 0.04) * math.cos(a), y, z + (radius - 0.04) * math.sin(a)),
              0.018, depth + 0.02, "steel_light", segs=5, axis="Y")


def bend(p, corner, a0, radius, r0, r1, mat="steel", steps=6, segs=14, bulge=0.04,
         u=(1, 0, 0), v=(0, 1, 0)):
    """A quarter torus: the pipe's centre line runs round `corner` (x, y, or x, y, z) at `radius`
    from angle a0 (degrees) to a0 + 90 in the plane of `u` and `v` (level at KIT_Z by default),
    its own radius going from r0 to r1."""
    import bmesh
    from mathutils import Vector
    u, v = Vector(u), Vector(v)
    normal = u.cross(v)
    centre = Vector((corner[0], corner[1], corner[2] if len(corner) > 2 else KIT_Z))
    bm = bmesh.new()
    rows = []
    for i in range(steps + 1):
        a = math.radians(a0 + 90 * i / steps)
        out = math.cos(a) * u + math.sin(a) * v
        c = centre + radius * out
        # Cast elbows swell a little at the middle, as the sprites' do.
        r = r0 + (r1 - r0) * i / steps + bulge * math.sin(math.pi * i / steps)
        rows.append([bm.verts.new(c + r * (math.cos(t) * out + math.sin(t) * normal))
                     for t in (2 * math.pi * j / segs for j in range(segs))])
    for a, b in zip(rows, rows[1:]):
        for j in range(segs):
            j2 = (j + 1) % segs
            bm.faces.new([a[j], a[j2], b[j2], b[j]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    p.merge(bm, mat)
    bm.free()


def post(p, at, top):
    """A short post holding the pipe off the ground, hidden under it from Factorio's camera."""
    p.cyl((at[0], at[1], top / 2), 0.07, top, "steel_dark", segs=8)


def south_cut(v):
    """Factorio's pictures stop at their frame, which cuts a south arm's end along a slant (the
    line on screen through the joint's flange); the southern neighbour's flange covers the rest.
    Pulls an arm's south end back to that line (the projection's anchor 0.375 and stretch 1.346)."""
    return v.x, max(v.y, -0.25 - 0.669 * v.z), v.z


def pipe_piece(conns):
    """A pipe joining the tile edges in `conns` (a string of N, E, S, W) at the tile's centre,
    as Factorio's pictures draw it: east and west flanges just inside the tile, the north one
    straddling the tile edge, and on the south only the top of the southern neighbour's flange.
    No connections: a short north-south stub with an end cap, the "single" picture. One: a pipe
    from that edge most of the way across, closed by a stepped end cap."""
    p = Part()
    z = KIT_Z
    if not conns:
        z = 0.48
        p.cyl((0, 0.05, z), 0.3, 0.6, "steel", segs=16, axis="Y")
        flange_ring(p, (0, 0.33, z), "Y", radius=0.42, bolts=10)
        end_cap(p, (0, -0.25, z), "Y", -1)
        p.cyl((0, -0.29, z), 0.42, 0.07, "rust_brown", segs=16, axis="Y", bevel=0.012)
        post(p, (0, 0.05), z - 0.27)
        return p
    corner = len(conns) == 2 and sorted(conns) not in (["N", "S"], ["E", "W"])
    # Where each arm stops at the middle of the tile (an ending runs on to its cap).
    reach = {c: 0.0 for c in conns}
    if len(conns) == 1:
        reach[conns] = {"N": -0.16, "S": 0.14, "E": -0.29, "W": 0.29}[conns]
    for c in conns:
        dx, dy = ARMS[c]
        axis = "X" if dx else "Y"
        edge = 0.5 if c != "S" else 0.505
        start = reach[c] * (dx + dy)   # signed distance along the arm
        if not corner:
            arm = Part()
            arm.cyl((dx * (edge + start) / 2, dy * (edge + start) / 2, z), KIT_R[axis], edge - start, "steel",
                    segs=14, axis=axis)
            p.add_part(arm.warp(south_cut) if c == "S" else arm)
        if c == "N":
            flange_ring(p, (0, 0.5, z), "Y", radius=KIT_FLANGE_R["Y"])
        elif c == "S":
            half_flange(p, (0, -0.5, z))
        else:
            flange_ring(p, (dx * 0.465, 0, z), "X", radius=KIT_FLANGE_R["X"])
    if corner:
        (dx1, dy1), (dx2, dy2) = (ARMS[c] for c in conns)
        cx, cy = 0.5 * (dx1 + dx2), 0.5 * (dy1 + dy2)
        # Start angle: from the corner towards the first arm's edge midpoint, sweeping 90 degrees.
        angles = sorted(math.degrees(math.atan2(dy * 0.5 - cy, dx * 0.5 - cx)) % 360
                        for dx, dy in ((dx1, dy1), (dx2, dy2)))
        a0 = angles[0] if round(angles[1] - angles[0]) == 90 else angles[1]
        # The bend runs from the arm at a0 (east-west if the corner lies east or west of it).
        first_ew = abs(math.cos(math.radians(a0))) < 0.5
        rs = (KIT_R["X"], KIT_R["Y"]) if first_ew else (KIT_R["Y"], KIT_R["X"])
        b = Part()
        bend(b, (cx, cy), a0, 0.5, *rs)
        p.add_part(b.warp(south_cut) if "S" in conns else b)
        mid = math.radians(a0 + 45)
        post(p, (cx + 0.5 * math.cos(mid), cy + 0.5 * math.sin(mid)), z - 0.25)
    else:
        post(p, (0, 0), z - 0.25)
    if len(conns) == 1:
        dx, dy = ARMS[conns]
        axis = "X" if dx else "Y"
        s = -1 if (dx + dy) > 0 else 1
        cap = reach[conns]
        end_cap(p, ((cap if dx else 0), (cap if dy else 0), z), axis, s, radius=KIT_FLANGE_R[axis])
    return p


# Factorio's pipe pictures, by the connections each shows.
PIPE_SHAPES = {
    "straight-vertical-single": "", "straight-vertical": "NS", "straight-horizontal": "EW",
    "corner-up-right": "NE", "corner-up-left": "NW", "corner-down-right": "SE", "corner-down-left": "SW",
    "t-up": "NEW", "t-down": "SEW", "t-left": "NSW", "t-right": "NES", "cross": "NESW",
    "ending-up": "N", "ending-down": "S", "ending-left": "W", "ending-right": "E",
}


def _register_pipes():
    for shape, conns in PIPE_SHAPES.items():
        model("pipe-" + shape)(lambda conns=conns: pipe_piece(conns))


_register_pipes()


@model("pipe")
def pipe():
    """A pipe on its own: drawn when the client can't tell its neighbours (the straight
    north-south piece, Factorio's default picture)."""
    return pipe_piece("NS")


def pipe_to_ground_piece(f):
    """A pipe-to-ground built facing north, then turned to its facing: a pipe from the connection
    edge (its bolted flange `jy` north of the tile's middle) runs level at `z`, bends down (radius
    `rb`, its radius going from `r` to `r * swell`) and goes into the ground `yg` north of the
    middle through a broad bolted flange lying on it. `f` holds the numbers fitted to that
    direction's picture (PTG_FACINGS)."""
    p = Part()
    z, r, r2 = f["z"], f["r"], f["r"] * f["swell"]
    yg, rb, gz = f["yg"], f["rb"], f["gz"]
    yb = yg + rb                           # where the level run ends and the bend starts
    end = f.get("end", f["jy"])            # the pipe may run on past its flange to the tile edge
    arm = Part()
    if end > yb:
        arm.cyl((0, (end + yb) / 2, z), r, end - yb, "steel", segs=16, axis="Y")
    # A south end is cut back along the slant where Factorio's picture stops, as the kit's are.
    arm.transform(R("Z", f["turn"]))
    p.add_part(arm.warp(south_cut) if f.get("cut") else arm, R("Z", -f["turn"]))
    flange_ring(p, (0, f["jy"], z), "Y", radius=f["fr"], bolts=10)
    bend(p, (0, yb, z - rb), 0, rb, r, r2, steps=8, segs=16, bulge=f["bulge"], u=(0, -1, 0), v=(0, 0, 1))
    if z - rb > gz:
        p.cyl((0, yg, (z - rb + gz) / 2), r2, z - rb - gz, "steel", segs=16)
    # The ground flange: a thick bolted ring with a collar round the pipe, a thin lip under it;
    # oval (`ga` along the pipe, `gx` across) where the pipe goes in at a slant.
    g = Part()
    g.cyl((0, 0, gz / 2), 1.0, gz, "rust_brown", segs=24)
    g.cyl((0, 0, 0.015), 1.0 + 0.03 / f["ga"], 0.03, "steel_dark", segs=24)
    g.transform(T(0, yg, 0) @ S(f["gx"], f["ga"], 1))
    p.add_part(g)
    # Bolts round its rim, where the pipe's collar leaves room.
    for i in range(16):
        a = 2 * math.pi * (i + 0.5) / 16
        bx, by = (f["gx"] - 0.035) * math.cos(a), (f["ga"] - 0.035) * math.sin(a)
        if math.hypot(bx, by) > r2 + 0.05:
            p.cyl((bx, yg + by, gz + 0.008), 0.02, 0.025, "steel_light", segs=6)
    p.cyl((0, yg, gz + 0.025), r2 + 0.025, 0.05, "rust_brown", segs=18, bevel=0.01)
    p.transform(R("Z", f["turn"]))
    return p


# Factorio rendered each direction of the pipe-to-ground on its own, and the pictures don't turn
# into each other: the north one drops into the ground just behind its flange, the east and west
# ones sweep a wide elbow down into a flange long along the pipe, and the south one's flange sits
# a quarter tile in from the edge with the bend close behind it. So each direction is a model of
# its own (pipe-to-ground, -east, -south, -west; model_library.gd FACING_MODELS draws it unturned),
# its numbers fitted to its picture's silhouette at the pipe kit's camera (PIPE_FIT), the pipe at
# the kit's height and within 0.05 of its radius, the joint flange where the kit has it (straddling
# the north edge, just inside the east and west ones) so pipes meet it as they meet each other.
# The south pipe runs on to the edge under the southern neighbour's flange, cut back where the
# picture stops (south_cut). The ground flange's ovals are the pictures' (hidden in the south one).
_PTG = {"z": KIT_Z, "r": 0.305, "fr": 0.39, "jy": 0.5, "yg": 0.17, "rb": 0.36, "gz": 0.08, "ga": 0.29,
        "gx": 0.37, "swell": 0.94, "bulge": 0.03, "turn": 0}
_PTG_EW = dict(_PTG, r=0.25, fr=0.335, jy=0.465, yg=-0.01, rb=0.44, ga=0.37, gx=0.24, swell=1.115, bulge=0.01)
PTG_FACINGS = {
    "": dict(_PTG),
    "-east": dict(_PTG_EW, turn=-90),
    "-south": dict(_PTG, r=0.26, fr=0.4, jy=0.22, end=0.5, cut=True, yg=0.05, rb=0.3, ga=0.2, gx=0.35,
                   swell=0.85, bulge=0.045, turn=180),
    "-west": dict(_PTG_EW, turn=90),
}


def _register_ptg():
    for sfx, f in PTG_FACINGS.items():
        model("pipe-to-ground" + sfx)(lambda f=f: pipe_to_ground_piece(f))


_register_ptg()


def hose(p, points, radius, segs=10, ribs=4):
    """A ribbed hose along `points`: rings of slightly varying radius, as the sprites' orange
    corrugated hoses."""
    from mathutils import Vector
    pts = [Vector(q) for q in points]
    for a, b in zip(pts, pts[1:]):
        p.tube(a, b, radius, "rust_orange", segs=segs)
        for k in range(ribs):
            c = a.lerp(b, (k + 0.5) / ribs)
            d = (b - a).normalized() * 0.03
            p.tube(c - d, c + d, radius * 1.12, "rust_orange", segs=segs)
    for q in pts[1:-1]:
        p.sphere(q, radius, "rust_orange", segs=segs, rings=5)


def _offshore_pump_groups():
    """The offshore pump facing north as groups (facings.py), and its pistons."""
    g = {name: Part() for name in ("base", "outlet", "barrels", "hoses_s", "hoses_n", "guard", "plates")}
    # Outlet on the land tile, on a foot (left where it is: it stands on the land).
    g["base"].slab(-0.24, -0.4, 0.0, 0.24, 0.05, 0.16, "steel_dark", bevel=0.03)
    p = g["outlet"]
    p.cyl((0, -0.25, 0.44), 0.37, 0.44, "steel", segs=16, axis="Y", bevel=0.02)
    flange_ring(p, (0, -0.45, 0.44), "Y", radius=0.44, bolts=12)
    p.cyl((0, -0.05, 0.44), 0.4, 0.08, "rust_brown", segs=16, axis="Y")
    p.bolts_ring((0, 0.0, 0.44), 0.35, 10, axis="Y", radius=0.016)
    p = g["barrels"]
    # A web between the barrels.
    p.slab(-0.1, 0.2, 0.28, 0.1, 1.3, 0.6, "steel_dark", bevel=0.02)
    pistons = []
    for sx in (-1, 1):
        x = sx * 0.28
        # Hoses from the outlet up into the barrels.
        hose(g["hoses_s"], [(x * 0.7, -0.05, 0.42), (x, 0.05, 0.45), (x, 0.15, 0.45)], 0.17)
        # The barrels, banded and bolted, with a dark window on top.
        p.cyl((x, 0.75, 0.45), 0.24, 1.2, "steel", segs=14, axis="Y", bevel=0.02)
        for y in (0.18, 0.47, 1.0, 1.32):
            p.cyl((x, y, 0.45), 0.265, 0.07, "steel_dark", segs=14, axis="Y")
            p.bolts_ring((x, y, 0.45), 0.25, 8, axis="Y", radius=0.014, start=22.5)
        p.slab(x - 0.12, 0.55, 0.62, x + 0.12, 0.92, 0.68, "steel_dark", bevel=0.01)
        p.slab(x - 0.1, 0.57, 0.63, x + 0.1, 0.9, 0.71, "soot")
        for wx in (x - 0.105, x + 0.105):
            p.cyl((wx, 0.735, 0.69), 0.015, 0.36, "steel_light", segs=6, axis="Y")
        # A cream piston in each window, running along it while it pumps, in turn (anim_bob_*;
        # placed where the squeeze below puts the window).
        piston = Part("anim_bob_a" if sx < 0 else "anim_bob_b")
        piston.slab(x - 0.07, 0.6, 0.66, x + 0.07, 0.69, 0.73, "paint_cream", bevel=0.01)
        pistons.append(piston)
        # Side plates bracing the barrels, with the drive's gears on their outsides.
        q = g["plates"]
        q.slab(sx * 0.5 - 0.04, 0.1, 0.18, sx * 0.5 + 0.04, 1.0, 0.62, "steel_dark", bevel=0.02)
        for gy, gr in ((0.3, 0.17), (0.66, 0.14)):
            gear_x = sx * 0.56
            q.cyl((gear_x, gy, 0.3), gr, 0.06, "steel", segs=12, axis="X", bevel=0.01)
            q.cyl((sx * 0.6, gy, 0.3), 0.05, 0.05, "steel_dark", segs=8, axis="X")
            for k in range(8):
                a = math.radians(45 * k)
                q.box((gear_x, gy + (gr + 0.02) * math.cos(a), 0.3 + (gr + 0.02) * math.sin(a)), (0.05, 0.05, 0.05),
                      "steel")
        # A brace from the side plate down to the bank: the sprites' legs on either side.
        q.beam((sx * 0.5, 0.95, 0.5), (sx * 0.56, 1.25, 0.0), 0.08, 0.06, "rust_brown")
        # Hoses arching up from the barrels' north ends through the collar, down into the water.
        hose(g["hoses_n"], [(x, 1.35, 0.5), (x, 1.6, 0.8), (x, 1.85, 0.55), (x, 1.85, 0.25)], 0.17)
        g["guard"].ring_band((x, 1.8), 0.18, 0.3, 0.5, 0.66, 0, 360, "hazard", segs=16, bevel=0.01)
    g["guard"].slab(-0.3, 1.67, 0.52, 0.3, 1.93, 0.64, "hazard")
    # The yellow horseshoe guard round the intake.
    g["guard"].ring_band((0, 1.6), 0.44, 0.54, 0.35, 0.72, 0, 180, "hazard", segs=12, bevel=0.015)
    # Squeezed a little north of the land tile: the pictures draw it shorter than its tiles.
    squeeze = lambda v: (v.x, v.y if v.y < 0.3 else 0.3 + (v.y - 0.3) * 0.85, v.z)  # noqa: E731
    for part in list(g.values()) + pistons:
        part.warp(squeeze)
    return g, {"barrels": pistons}


# Each picture's fit (facings.py): Factorio renders the offshore pump's four directions
# separately (offshore-pump_North/East/South/West.png), the east and west ones from a lower angle.
OFFSHORE_PUMP_FITS = {
    0: {
        "barrels": (-0.06, 0.165, 0.02, 1.022, 1.022, 1.022),
        "guard": (0.055, -0.3, -0.22, 1.06, 1.06, 1.06),
        "hoses_n": (-0.03, -0.2, -0.015, 0.996, 0.996, 0.996),
        "hoses_s": (-0.03, 0.03, 0.01, 1, 1, 1),
        "outlet": (0, 0, -0, 1.015, 1.015, 1.015),
        "plates": (-0.02, 0.21, 0.2, 0.94, 0.94, 0.94),
    },
    1: {
        "barrels": (-0.09, 0.01, 0.08, 1.015, 1.022, 1),
        "base": (0, 0, 0, 0.61, 0.61, 0.61),
        "guard": (0.08, -0.295, 0.03, 0.97, 0.955, 0.94),
        "hoses_n": (0.15, 0, 0, 1, 1, 1),
        "hoses_s": (-0.155, 0.04, -0.005, 0.992, 1, 1),
        "outlet": (0, 0, 0.095, 0.978, 0.978, 0.978),
        "plates": (-0.155, 0.01, 0.06, 0.857, 0.939, 0.94),
    },
    2: {
        "barrels": (-0.02, -0.01, -0.05, 0.985, 0.985, 0.985),
        "guard": (0.03, -0.275, 0.285, 1.21, 1.21, 1.21),
        "hoses_n": (0.03, -0.26, 0.185, 0.993, 0.993, 0.993),
        "hoses_s": (-0.005, -0.18, 0, 1, 1, 1),
        "outlet": (0, 0, 0.025, 0.985, 0.985, 0.985),
        "plates": (0.11, 0.08, 0.01, 0.85, 0.85, 0.85),
    },
    3: {
        "barrels": (0.16, 0.015, -0.04, 1.015, 1.015, 1.015),
        "guard": (-0.1, -0.3, -0.02, 0.985, 0.985, 0.985),
        "hoses_n": (-0.14, 0.005, -0.06, 1, 1, 1),
        "hoses_s": (0.15, 0, -0.03, 1, 1, 1),
        "outlet": (0, 0, 0.015, 1, 1, 1),
        "plates": (0.21, 0.01, 0.01, 0.865, 0.865, 0.865),
    },
}


def offshore_pump(facing=0):
    """Factorio's offshore pump facing north: on its land tile, the outlet pipe ending in a
    flange at the south edge; two orange corrugated hoses up into a pair of banded pump barrels
    lying side by side out over the water, braced by side plates; at their north end two more
    hoses arch up through a yellow intake collar and down into the water. The sprite draws it
    longer north-south than its tiles (Factorio's sprites stretch the ground that way), so the
    collar reaches past the selection box. One model per direction (offshore-pump, -east,
    -south, -west), each fitted to its own picture."""
    groups, anims = _offshore_pump_groups()
    return facings.variant(groups, facing, OFFSHORE_PUMP_FITS[facing], anims=anims)


for _facing, _suffix in enumerate(facings.SUFFIXES):
    model("offshore-pump" + _suffix)(lambda f=_facing: offshore_pump(f))


@model("storage-tank")
def storage_tank():
    """Factorio's storage tank: a round drum (both of the sprite's frames draw the same drum and
    turn only the connections, so a round one fits both) under a shallow lid with a hatch, bolted rims, a window on the south side, and pipe
    connections at its north-west and south-east corners (north and west, south and east)."""
    p = Part()
    rx, ry, h = 1.32, 1.32, 1.35

    def oval(z, r_scale, depth, mat, top_scale=None, segs=28, bevel=0.0):
        k = Part()
        k.cyl((0, 0, 0), 1.0, depth, mat, segs=segs, radius_top=top_scale, bevel=bevel)
        k.transform(T(0, 0, z) @ _scale(rx * r_scale, ry * r_scale, 1.0))
        p.add_part(k)

    oval(0.05, 1.02, 0.1, "steel_dark")
    oval(h / 2 + 0.05, 1.0, h - 0.1, "steel", bevel=0.02)
    for z in (0.18, h - 0.02):
        oval(z, 1.025, 0.06, "rust_brown")
    # The lid: a low cone up to a hatch in the middle.
    oval(h + 0.08, 1.0, 0.14, "steel", top_scale=0.25)
    p.cyl((0, 0, h + 0.2), 0.24, 0.1, "steel_dark", segs=14, bevel=0.02)
    p.cyl((0, 0, h + 0.27), 0.13, 0.06, "steel", segs=12)
    p.bolts_ring((0, 0, h + 0.25), 0.2, 8, radius=0.02)
    p.pipe([(-0.95, 0.55, h + 0.15), (-0.6, 0.35, h + 0.18), (-0.2, 0.1, h + 0.24)], 0.035, "steel_light", segs=6)
    p.pipe([(0.25, 0.1, h + 0.24), (0.7, -0.35, h + 0.12), (1.0, -0.6, h - 0.2)], 0.025, "steel_light", segs=6)
    # The window on the south face.
    p.slab(-0.2, -ry - 0.03, 0.3, 0.2, -ry + 0.1, 0.7, "steel_dark", bevel=0.02)
    p.slab(-0.14, -ry - 0.05, 0.36, 0.14, -ry + 0.05, 0.64, "glass_dark")
    # Connections: corner housings with a pipe out of two sides each.
    for (cx, cy), arms in (((-1.0, 1.0), ((0, 1), (-1, 0))), ((1.0, -1.0), ((0, -1), (1, 0)))):
        p.cyl((cx, cy, 0.42), 0.26, 0.84, "steel", segs=14, bevel=0.02)
        p.cyl((cx, cy, 0.87), 0.29, 0.06, "rust_brown", segs=14)
        for dx, dy in arms:
            axis = "X" if dx else "Y"
            # As the pipe kit: north and south flanges straddle the tile edge, east and west
            # ones sit just inside it.
            out = 0.5 if dy else 0.465
            p.cyl((cx + dx * 0.25, cy + dy * 0.25, KIT_Z), KIT_R[axis], 0.5, "steel", segs=14, axis=axis)
            flange_ring(p, (cx + dx * out, cy + dy * out, KIT_Z), axis, radius=KIT_FLANGE_R[axis])
    return p


def _scale(x, y, z):
    from kit import S
    return S(x, y, z)
