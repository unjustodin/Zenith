"""Electric network: medium and big poles, substation, small lamp, solar panel, accumulator, radar.

Each model is matched to Factorio's HR sprite with compare.py (see client/assets/models/README.md,
"Matching a sprite").
"""

import math

from mathutils import Vector

import detail
import kit
from kit import Part, R, T, model

def R_Z(deg):
    """Turn about the vertical axis (radar(), whose own R is the dish radius)."""
    return R("Z", deg)


def lerp(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def lattice(p, base, top, z0, z1, levels, mat, leg=0.05, brace=0.025, rings=True, cross=False):
    """A four-legged lattice tower: legs from the `base` corners (4 (x, y), counter-clockwise)
    at z0 to the `top` corners at z1, with a zigzag of braces on each face (an X per level with
    `cross`) and a ring of horizontals at each level."""
    zs = [z0 + (z1 - z0) * i / levels for i in range(levels + 1)]
    pts = [[(*lerp(b, t, (z - z0) / (z1 - z0)), z) for b, t in zip(base, top)] for z in zs]
    for i in range(4):
        p.beam(pts[0][i], pts[-1][i], leg, leg, mat, up=(1, 1, 0))
    for k in range(levels):
        lo, hi = pts[k], pts[k + 1]
        for i in range(4):
            j = (i + 1) % 4
            # One diagonal per face per level, alternating, as the sprite's zigzag.
            if cross or (k + i) % 2:
                p.beam(lo[i], hi[j], brace, brace, mat)
            if cross or not (k + i) % 2:
                p.beam(lo[j], hi[i], brace, brace, mat)
            if rings:
                p.beam(hi[i], hi[j], brace, brace, mat)
    return pts


def core(p, base, top, z0, z1, mat="steel_black"):
    """A solid frustum from the `base` corners (counter-clockwise) at z0 to the `top` corners at
    z1: a prism whose top ring is moved onto `top`."""
    k = Part()
    k.prism(base, z0, z1, mat)
    n = len(base)
    for v in k.bm.verts:
        if v.co.z > (z0 + z1) / 2:
            i = min(range(n), key=lambda i: (v.co.x - base[i][0]) ** 2 + (v.co.y - base[i][1]) ** 2)
            v.co.x, v.co.y = top[i]
    p.add_part(k)


def diamond(cx, cy, r, turn=45.0):
    """Four corners (counter-clockwise) of a square with half-diagonal r, turned `turn` degrees."""
    out = []
    for i in range(4):
        a = math.radians(turn - 45.0 + 90.0 * i)
        out.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return out


def insulator(p, x, y, z, mat="ceramic"):
    """A post insulator standing at (x, y, z): a steel pin, two ceramic sheds, a copper cap."""
    p.cyl((x, y, z + 0.04), 0.022, 0.08, "steel_dark", segs=6)
    p.cyl((x, y, z + 0.11), 0.055, 0.06, mat, segs=8)
    p.cyl((x, y, z + 0.17), 0.045, 0.06, mat, segs=8)
    p.cyl((x, y, z + 0.22), 0.025, 0.04, "copper", segs=6)


@model("medium-electric-pole")
def medium_electric_pole():
    """Factorio's medium pole: a tall orange steel lattice tower on a small diamond footing,
    leaning a little east as the sprite draws it, under a diamond frame head with a small cage
    in the middle, insulators on its east and west corners and one raised on the cage, where
    Factorio hangs the wires (client/scripts/world/wires.gd POLE_POINTS)."""
    p = Part()
    P = MEDIUM_POLE
    mat = "rust_orange"
    # The sprite's tower stands west of the tile centre at its foot and east of it at the head.
    bc, tc = (P["bx"], P["by"]), (P["tx"], P["ty"])
    base = diamond(*bc, P["br"], turn=P["turn"])
    top = diamond(*tc, P["tr"], turn=P["turn"])
    z1 = P["z1"]
    for x, y in base:
        p.slab(x - 0.05, y - 0.05, 0.0, x + 0.05, y + 0.05, 0.05, "steel_dark")
    lattice(p, base, top, 0.0, z1, int(P["levels"]), mat, leg=P["leg"], brace=P["brace"])
    # The sprite shows the tower's inside as near black: a slim dark core catches that, where
    # open lattice would let the ground show through.
    if P["core"] > 0:
        core(p, [lerp(c, bc, 1 - P["core"]) for c in base], [lerp(c, tc, 1 - P["core"]) for c in top], 0.0, z1)
    # Behind the foot on the east, a dark triangular gusset plate braces the tower.
    gx, gy, gw, gh = P["gx"], P["gy"], P["gw"], P["gh"]
    p.poly([(gx, gy, 0.0), (gx + gw, gy, 0.18), (gx + gw, gy, gh * 0.5), (gx + gw * 0.35, gy, gh)], "steel_black", thick=0.05)
    # The head: a flat diamond frame round a small cage.
    hx, hz = P["hx"], P["hz"]
    ring = [(hx - P["hw"], 0.0), (hx, -P["hd"]), (hx + P["he"], 0.0), (hx, P["hd"])]
    for i in range(4):
        a, b = ring[i], ring[(i + 1) % 4]
        p.beam((*a, hz), (*b, hz), 0.05, 0.06, mat)
    p.beam((*ring[0], hz), (*ring[2], hz), 0.05, 0.05, mat)
    p.slab(hx - P["hs"], -P["hs"] * 0.9, z1, hx + P["hs"], P["hs"] * 0.9, hz + 0.05, mat, bevel=0.015)
    zc = P["zc"]
    for x, y in diamond(hx, 0.0, 0.2, turn=45):
        p.beam((x, y, hz), (hx + (x - hx) * 0.8, y * 0.8, zc), 0.035, 0.035, mat)
    p.beam((hx - 0.15, 0.0, zc), (hx + 0.15, 0.0, zc), 0.04, 0.04, mat)
    # Insulators: copper on a post up from the cage, green on a post at the west corner, red on
    # the east corner.
    wx, wy, wz = P["wire_w"]
    p.beam((wx, wy, hz), (wx, wy, wz - 0.15), 0.04, 0.04, mat)
    insulator_at(p, P["wire_w"])
    gx, gy, gz = P["wire_g"]
    p.cyl((gx, gy, (hz + gz - 0.15) / 2), 0.025, gz - 0.15 - hz, "steel_dark", segs=6)
    insulator_at(p, P["wire_g"])
    rx, ry, rz = P["wire_r"]
    if rz - 0.15 > hz + 0.02:
        p.cyl((rx, ry, (hz + rz - 0.15) / 2), 0.025, rz - 0.15 - hz, "steel_dark", segs=6)
    insulator_at(p, P["wire_r"])
    # The leaning legs' boxes dip a little under the ground at their feet: cut them off there.
    return p.warp(lambda co: (co.x, co.y, max(co.z, 0.0)))


# The medium pole's numbers, fitted to its sprite (score.py): the foot's and head's diamonds
# (centre, half-diagonal, turn), the tower's height and levels, member sizes, the core's share of
# the tower, the gusset and the head. Wire points as for the big pole below.
MEDIUM_POLE = {"bx": -0.11, "by": 0.019, "br": 0.245, "tx": 0.175, "ty": -0.128, "tr": 0.103, "turn": 38.0,
               "z1": 4.25, "levels": 12, "leg": 0.06, "brace": 0.068, "core": 0.784,
               "gx": 0.15, "gy": 0.045, "gw": 0.208, "gh": 0.95,
               "hx": 0.215, "hz": 4.3, "hw": 0.42, "he": 0.508, "hd": 0.204, "hs": 0.208, "zc": 4.74,
               "wire_w": (0.234, 0.0, 4.947), "wire_r": (0.672, 0.0, 4.48), "wire_g": (-0.234, 0.0, 4.62)}


@model("big-electric-pole")
def big_electric_pole():
    """Factorio's big pole: a dark steel pylon. Four legs splay out to feet at the corners, a
    lattice body (deeper than it is wide, its back legs a little narrower than the front ones)
    rises to a small cage on top, and two ladder-like crossarms (the upper one braced and tied
    down to the lower) carry insulators at their ends and on the cage, where Factorio hangs the
    wires (client/scripts/world/wires.gd POLE_POINTS)."""
    p = Part()
    P = BIG_POLE
    mat, rail = "steel_dark", "steel"
    zk, za, zb, zt = P["zk"], P["za"], P["zb"], P["zt"]
    # Knots up the legs: (z, front half-width, back half-width, half-depth).
    knots = [(0.0, P["f_wf"], P["f_wb"], P["f_d"]), (zk, P["k_wf"], P["k_wb"], P["k_d"]),
             (za, P["a_wf"], P["a_wb"], P["a_d"]), (zb, P["b_wf"], P["b_wb"], P["b_d"])]

    def half(z):
        for (z0, *w0), (z1, *w1) in zip(knots, knots[1:]):
            if z <= z1:
                t = (z - z0) / (z1 - z0)
                return tuple(a + (b - a) * t for a, b in zip(w0, w1))
        return tuple(knots[-1][1:])

    def corners(z):
        wf, wb, d = half(z)
        return [(wf, -d), (-wf, -d), (-wb, d), (wb, d)]

    def at(i, z):
        return (*corners(z)[i], z)

    # Feet: a plate under each leg and a gusset bracket sticking out sideways, as drawn.
    for x, y in corners(0.0):
        p.slab(x - 0.1, y - 0.1, 0.0, x + 0.1, y + 0.1, 0.07, "steel_black", bevel=0.015)
        sx = 1 if x > 0 else -1
        p.poly([(x, y, 0.07), (x + sx * P["foot_out"], y, 0.07), (x, y, 0.07 + P["foot_out"] * 1.6)], "steel_black", thick=0.04)
    # Legs: thick angle iron from the feet to the knee, lighter above it.
    for i in range(4):
        p.beam(at(i, 0.04), at(i, zk), P["leg0"], P["leg0"], mat, up=(1, 1, 0))
        p.beam(at(i, zk), at(i, za), P["leg1"], P["leg1"], mat, up=(1, 1, 0))
        p.beam(at(i, za), at(i, zb), P["leg2"], P["leg2"], mat, up=(1, 1, 0))
    # Below the knee each face has one big X: from the knee's corners down to a crossing in the
    # middle of the face, on through it to the legs low down, with a horizontal at the crossing.
    zx, zl, br = P["zx"], P["zl"], P["brace0"]
    for i in range(4):
        j = (i + 1) % 4
        p.beam(at(i, zk), at(j, zk), P["ring"], P["ring"], mat)
        if not int(P["low_faces"]) & (1 << i):
            continue
        a, b = at(i, zx), at(j, zx)
        mid = lerp(a, b, 0.5)
        for u, v in ((i, j), (j, i)):
            p.beam(at(u, zk), mid, br, br, mat)
            p.beam(mid, at(v, zl), br, br, mat)
        p.beam(a, b, br, br, mat)
    # Above it, X-braced bays up to each crossarm, a ring of horizontals between them.
    n_lo, n_hi = int(P["bays_lo"]), int(P["bays_hi"])
    levels = [zk + (za - zk) * t / n_lo for t in range(n_lo + 1)] + [za + (zb - za) * t / n_hi for t in range(1, n_hi + 1)]
    # The rings between the arms sit where the sprite draws them, not evenly.
    for k in range(1, len(levels) - 1):
        levels[k] += P.get("lv%d" % k, 0.0)
    # Each face's bracing: 1 an X per bay, 2 or 3 a zigzag (one diagonal per bay, alternating),
    # 0 none (faces: south, west, north, east).
    pattern = [int(P["pat_f"]), int(P["pat_s"]), int(P["pat_b"]), int(P["pat_s"])]
    for k, (z0, z1) in enumerate(zip(levels, levels[1:])):
        for i in range(4):
            j = (i + 1) % 4
            pat = pattern[i]
            # The north face is a lighter zigzag: the sprite shows little of it through the south face.
            bw = P["brace_far"] if i == 2 else P["brace1"]
            if pat == 1 or (pat >= 2 and (k + pat + (i == 3)) % 2):
                p.beam(at(i, z0), at(j, z1), bw, bw, mat)
            if pat == 1 or (pat >= 2 and not (k + pat + (i == 3)) % 2):
                p.beam(at(j, z0), at(i, z1), bw, bw, mat)
            p.beam(at(i, z1), at(j, z1), P["ring"], P["ring"], mat)
    # The cage on top: four posts, a ring part way up and a heavier frame on top, the copper
    # wire's insulator on its middle.
    cw, cd = P["cage_w"], P["cage_d"]
    cage = [(cw, -cd), (-cw, -cd), (-cw, cd), (cw, cd)]
    for i, (x, y) in enumerate(cage):
        x0, y0 = corners(zb)[i]
        p.beam((x0, y0, zb), (x, y, zt), 0.07, 0.07, mat, up=(1, 1, 0))
    for z, t in ((zb + (zt - zb) * 0.5, 0.05), (zt, 0.08)):
        for i in range(4):
            a, b = cage[i], cage[(i + 1) % 4]
            p.beam((*a, z), (*b, z), t, t, mat)
    p.beam((-cw, 0.0, zt), (cw, 0.0, zt), 0.06, 0.06, mat)
    wx, wy, wz = P["wire_w"]
    p.beam((wx, wy, zt), (wx, wy, wz - 0.15), 0.04, 0.04, mat)
    insulator_at(p, P["wire_w"])
    # Crossarms: flat ladders (front and back rails, rungs across) at both heights, the circuit
    # wires' insulators at the upper one's ends.
    reach, d = P["reach"], P["arm_d"]
    for z, drop, rungs in ((za, P["low_drop"], (0.6,)), (zb, P["high_drop"], (0.56,))):
        for y in (-d, d):
            p.beam((-reach, y, z), (reach, y, z), P["rail"], P["rail"], rail)
        for x in (-reach + 0.04,) + tuple(-r for r in rungs) + rungs + (reach - 0.04,):
            p.beam((x, -d, z), (x, d, z), 0.05, 0.06, rail)
        for sx in (-1, 1):
            p.slab(sx * reach - 0.07, -d - 0.03, z - 0.06, sx * reach + 0.07, d + 0.03, z + 0.05, mat, bevel=0.015)
            # Braces from under the arm's end back to the body, front and back.
            for sy in (-1, 1):
                wf, wb, wd = half(z - drop)
                w = wf if sy < 0 else wb
                p.beam((sx * (reach - 0.1), sy * d, z - 0.03), (sx * w, sy * wd, z - drop), P["brace2"], P["brace2"], mat)
    for sx, kind in ((1, "wire_r"), (-1, "wire_g")):
        x, y, z = P[kind]
        insulator_at(p, (sx * abs(x), y, z))
    # Insulators on the lower arm's ends too, as drawn.
    for sx in (-1, 1):
        insulator(p, sx * (reach - 0.05), 0.0, za + 0.05)
    # Hangers tie the lower arm's ends up to the upper arm's.
    for sx in (-1, 1):
        p.beam((sx * (reach - 0.03), -d, za), (sx * (reach - 0.03), -d, zb), 0.02, 0.02, rail)
    return p


def insulator_at(p, point):
    """An insulator centred on `point`, where Factorio hangs the wire (its connection points sit
    in the middle of the sprite's insulators)."""
    x, y, z = point
    insulator(p, x, y, z - 0.15)


# The big pole's numbers, fitted to its sprite (polefit / score.py): heights of the knee, the
# lower and upper crossarms and the cage's top; the legs' half-widths (front, back) and
# half-depth at the feet, knee and arms; where the lower X crosses and meets the legs; member
# sizes. The wire points are Factorio's connection_points turned into 3D with the sprite's camera
# (wires.gd POLE_POINTS has the same numbers, x east, y north, z up).
BIG_POLE = {"zk": 1.57, "za": 2.99, "zb": 4.735, "zt": 5.47,
            "f_wf": 0.6, "f_wb": 0.585, "f_d": 0.6775, "k_wf": 0.4538, "k_wb": 0.3462, "k_d": 0.22,
            "a_wf": 0.315, "a_wb": 0.245, "a_d": 0.18, "b_wf": 0.1938, "b_wb": 0.19, "b_d": 0.285,
            "zx": 0.9925, "zl": 0.06, "foot_out": 0.135, "leg0": 0.1487, "leg1": 0.13, "leg2": 0.105,
            "brace0": 0.05, "brace1": 0.075, "brace_far": 0.05, "brace2": 0.06, "ring": 0.065, "rail": 0.055,
            "bays_lo": 2, "bays_hi": 3, "pat_f": 1, "pat_s": 1, "pat_b": 3, "low_faces": 11,
            "lv1": -0.165, "lv2": 0.0, "lv3": -0.0075, "lv4": 0.075, "cage_w": 0.16, "cage_d": 0.125,
            "reach": 0.92, "arm_d": 0.14, "low_drop": 0.305, "high_drop": 0.55,
            "wire_w": (0.0, 0.0, 5.784), "wire_r": (0.906, 0.0, 4.967), "wire_g": (-0.906, 0.0, 4.967)}


@model("substation")
def substation():
    """Factorio's substation: a blue transformer block (stacked coils on top, drums on the west
    side, a finned cooler box at the north-east) inside a steel frame whose four corner legs lean
    in to a lattice tower carrying a crossarm with three insulators, where Factorio hangs the
    wires (client/scripts/world/wires.gd POLE_POINTS)."""
    p = Part()
    P = SUBSTATION
    blue, frame = "paint_blue", "steel"
    t = Part()
    # The transformer: a base block, a grille box on the front, coils stacked up and back.
    # The front stays behind the frame's front legs, which climb almost straight up.
    t.slab(-0.8, -0.72, 0.0, 0.8, 0.65, 0.7, blue, bevel=0.05)
    t.slab(-0.8, -0.5, 0.6, 0.8, 0.65, 1.05, blue, bevel=0.05)
    t.slab(-0.72, -0.88, 0.04, 0.72, -0.7, 0.55, "steel_dark", bevel=0.03)
    t.slab(0.1, -0.92, 0.12, 0.5, -0.86, 0.42, "steel_dark", bevel=0.02)
    for i, (y, z) in enumerate(((-0.45, 0.98), (-0.18, 1.2), (0.12, 1.4))):
        t.cyl((0, y, z), 0.2, 1.35 - 0.1 * i, blue, segs=12, axis="X", bevel=0.03)
        t.cyl((0, y - 0.02, z), 0.205, 0.5, "steel_dark", segs=12, axis="X")
    t.slab(-0.65, -0.1, 0.9, 0.65, 0.55, 1.5, blue, bevel=0.05)
    # West: two drums lying north-south, and a round end-cap on the top corner.
    for x, z, y0 in ((-0.64, 0.3, -0.6), (-0.78, 0.68, -0.75)):
        t.cyl((x, (y0 + 0.25) / 2, z), 0.17, 0.25 - y0, blue, segs=12, axis="Y", bevel=0.03)
        t.cyl((x, (y0 + 0.25) / 2, z), 0.11, 0.31 - y0, "steel_dark", segs=10, axis="Y")
    t.cyl((-0.6, -0.1, 1.15), 0.2, 0.12, "steel_dark", segs=14, axis="X")
    # North-east: the cooler box with fins.
    t.slab(0.4, -0.05, 0.75, 0.86, 0.7, 1.31, "steel_dark", bevel=0.04)
    t.slab(0.86, 0.0, 1.02, 0.9, 0.68, 1.28, "steel_dark")
    for k in range(5):
        y = 0.0 + k * 0.14
        t.slab(0.86, y, 1.04, 0.95, y + 0.06, 1.28, "steel")
    # South-east: a coil drum low on the front corner.
    t.cyl((0.84, -0.3, 0.58), 0.16, 0.45, blue, segs=12, axis="Y", bevel=0.03)
    t.cyl((0.84, -0.3, 0.58), 0.1, 0.51, "steel_dark", segs=10, axis="Y")
    p.add_part(t, T(P["tdx"], P["tdy"], 0.0) @ kit.S(P["tsx"], P["tsy"], P["tsz"]))
    # Frame: four legs leaning in from the corners to the tower's foot.
    feet = [(P["fx"], P["fyb"]), (-P["fx"], P["fyb"]), (-P["fx"], -P["fyf"]), (P["fx"], -P["fyf"])]
    zf, zt = P["zf"], P["zt"]
    foot = [(sx * P["tfw"], sy * P["tfd"]) for sx, sy in ((1, 1), (-1, 1), (-1, -1), (1, -1))]
    head = [(sx * P["thw"], sy * P["thd"]) for sx, sy in ((1, 1), (-1, 1), (-1, -1), (1, -1))]
    for (x, y), (fx, fy) in zip(feet, foot):
        p.slab(x - 0.09, y - 0.09, 0.0, x + 0.09, y + 0.09, 0.08, "steel_dark")
        if y < 0:
            p.beam((x, y, 0.0), (fx, fy, zf), P["leg"], P["leg"], frame, up=(1, 1, 0))
        else:
            # The back legs climb straight up behind the transformer before leaning in.
            knee = (x * P["kx"], y * P["ky"], P["kz"])
            p.beam((x, y, 0.0), knee, P["leg"], P["leg"], frame, up=(1, 1, 0))
            p.beam(knee, (fx, fy, zf), P["leg"], P["leg"], frame, up=(1, 1, 0))
    a, b = feet[3], feet[0]
    p.beam((*a, 0.08), (*b, 0.08), 0.07, 0.07, frame)
    zm = zf + (zt - zf) * P["tmid"]
    mid = [lerp(f, h, P["tmid"]) for f, h in zip(foot, head)]
    # The tower: four legs, a ring at its foot, middle and head, and an X in each bay of the
    # faces the sprite shows braced (bit i of `tfaces` for the face from corner i to i + 1).
    rings = [(foot, zf), (mid, zm), (head, zt)]
    for i in range(4):
        for (a, z0), (b, z1) in zip(rings, rings[1:]):
            p.beam((*a[i], z0), (*b[i], z1), P["tleg"], P["tleg"], frame, up=(1, 1, 0))
    for (a, z0), (b, z1) in zip(rings, rings[1:]):
        for i in range(4):
            j = (i + 1) % 4
            if int(P["tfaces"]) & (1 << i):
                p.beam((*a[i], z0), (*b[j], z1), P["tbrace"], P["tbrace"], frame)
                p.beam((*a[j], z0), (*b[i], z1), P["tbrace"], P["tbrace"], frame)
    for ring, z in rings:
        for i in range(4):
            p.beam((*ring[i], z), (*ring[(i + 1) % 4], z), P["tbrace"], P["tbrace"], frame)
    # The crossarm: a shallow V up to the outer insulators, one more raised in the middle, and
    # struts from the outer insulators down to the tower's legs.
    za = zt + P["arm_z"]
    for sx, kind in ((1, "wire_r"), (-1, "wire_g")):
        x, y, z = P[kind]
        p.beam((0.0, 0.0, za), (x, y, z - 0.17), 0.06, 0.06, frame)
        # Under each outer insulator a short post, then a strut in to the tower's leg.
        zp = z - 0.15 - P["post"]
        p.beam((x, y, z - 0.15), (x, y, zp), 0.05, 0.05, frame)
        hw = P["thw"] + (P["tfw"] - P["thw"]) * P["strut"] / (zt - zf)
        p.beam((x, y, zp), (sx * hw, 0.0, zt - P["strut"]), 0.05, 0.05, frame)
        insulator_at(p, P[kind])
    wx, wy, wz = P["wire_w"]
    p.beam((0, 0, zt), (wx, wy, wz - 0.15), 0.06, 0.06, frame)
    insulator_at(p, P["wire_w"])
    return p


# The substation's numbers, fitted to its sprite (score.py): the transformer's shift and scale,
# the frame's feet, back knees, the tower's foot, middle and head, member sizes and the arm.
SUBSTATION = {"tdx": 0.015, "tdy": 0.03, "tsx": 1.0, "tsy": 1.0, "tsz": 0.955,
              "fx": 0.808, "fyf": 0.93, "fyb": 0.864, "kx": 0.824, "ky": 1.005, "kz": 1.1,
              "tfw": 0.355, "tfd": 0.39, "thw": 0.2565, "thd": 0.1855, "zf": 2.168, "zt": 3.668, "tmid": 0.4,
              "leg": 0.079, "tleg": 0.093, "tbrace": 0.033, "tfaces": 14, "arm_z": -0.099, "post": 0.1975,
              "strut": 0.6625,
              "wire_w": (0.0, 0.0, 4.316), "wire_r": (0.688, 0.0, 4.083), "wire_g": (-0.656, 0.0, 4.13)}


@model("small-lamp")
def small_lamp():
    """Factorio's small lamp: a low steel box with a dark rim, chamfered under like the
    combinators (circuits.py `block`, fitted to the sprite), two ribs on its front, lugs on its
    east and west sides, a tall light-grey diffuser (a squared-off dome) with a coiled filament
    inside, and a copper pin at the north-east corner."""
    from circuits import block, hull
    p = Part()
    x0, x1, y0, y1, h = -0.35, 0.455, -0.29, 0.26, 0.36
    hull(p, block(x0, x1, y0, y1, 0.1, 0.33, h, (0.07, 0.04), (0.03, 0.03)), "steel", bevel=0.02)
    p.slab(x0 - 0.01, y0 - 0.01, h - 0.06, x1 + 0.01, y1 + 0.01, h, "steel_dark", bevel=0.015)
    for x in (-0.18, 0.22):
        p.slab(x - 0.03, y0 - 0.025, 0.02, x + 0.03, y0 + 0.01, h - 0.06, "steel_light", bevel=0.01)
    p.slab(-0.45, -0.215, 0.04, 0.45, 0.21, 0.14, "steel_dark", bevel=0.02)
    for x in (x0 + 0.05, x1 - 0.05):
        for y in (y0 + 0.04, y1 - 0.04):
            p.bolt((x, y, h + 0.005), "copper", radius=0.02)
    # The diffuser: wide at the foot, narrowing to a small flat top well above the box.
    base = [(0.36, -0.28), (0.36, 0.16), (-0.36, 0.16), (-0.36, -0.28)]
    top = [(0.1, -0.16), (0.1, 0.16), (-0.1, 0.16), (-0.1, -0.16)]
    p.slab(-0.3, -0.27, h - 0.01, 0.3, 0.2, h + 0.03, "steel_dark")
    core(p, base, top, h + 0.03, 0.6, "steel_light")
    p.pipe([(-0.08, -0.05, 0.42), (0.0, -0.1, 0.48), (0.08, -0.05, 0.42), (0.0, 0.0, 0.5)], 0.015, "copper", segs=5)
    p.cyl((0.36, 0.2, 0.43), 0.02, 0.2, "copper", segs=6)
    return p


@model("solar-panel")
def solar_panel():
    """Factorio's solar panel: four long blue panels side by side, each running north-south,
    tilted up towards the north and banked up towards the east, framed in light steel and held
    on a dark rail with a foot at each end."""
    p = Part()
    tilt, bank = 14.7, 36.0
    length, width = 2.9, 0.9
    for x in (-1.1, -0.365, 0.365, 1.1):
        m = T(x, -0.16, 0.62) @ R("X", tilt) @ R("Y", -bank)
        p.box((0, 0, 0), (width, length, 0.04), "paint_blue", matrix=m)
        # The frame: rails down both long sides, across both ends and between the cells.
        for sx in (-1, 1):
            p.box((sx * (width / 2 - 0.015), 0, 0.02), (0.035, length, 0.05), "steel_light", bevel=0.01, matrix=m)
        for k in range(8):
            y = -length / 2 + 0.015 + k * (length - 0.03) / 7
            p.box((0, y, 0.02), (width, 0.035 if k in (0, 7) else 0.025, 0.04), "steel_light", matrix=m)
        # Under it: a dark rail along the middle and a foot at each end, and a deep cross
        # beam under the south end.
        p.box((0, 0, -0.06), (0.06, length - 0.2, 0.08), "steel_dark", matrix=m)
        sw, se = (m @ Vector((sx * (width / 2 - 0.03), -length / 2 + 0.05, -0.02)) for sx in (-1, 1))
        p.poly([(sw.x, sw.y, max(0.0, sw.z - 0.24)), (se.x, se.y, max(0.0, se.z - 0.24)), tuple(se), tuple(sw)],
               "steel_dark", thick=0.08)
        for y in (-length / 2 + 0.12, length / 2 - 0.12):
            top = m @ Vector((0, y, -0.1))
            p.slab(top.x - 0.05, top.y - 0.05, 0.0, top.x + 0.05, top.y + 0.05, top.z, "steel_black")
        # The sprite shows a small bracket foot below each panel's south end.
        foot = m @ Vector((0, -length / 2, -0.1))
        p.slab(foot.x - 0.07, -1.46, 0.0, foot.x + 0.07, foot.y + 0.05, 0.06, "steel_black", bevel=0.01)
        p.beam((foot.x, -1.42, 0.05), (foot.x, foot.y, foot.z), 0.06, 0.05, "steel_dark")
    return p


@model("accumulator")
def accumulator():
    """Factorio's accumulator: four tall steel cells in a square on a low lattice tray, each
    with a terminal cap, a bridge across the middle carrying the terminals, and an insulator
    post at each corner (braced up from the tray in front, tied to the bridge behind)."""
    p = Part()
    # The tray: a low dark box with a lattice front, feet under the corners.
    p.slab(-0.92, -0.93, 0.03, 0.92, 0.93, 0.4, "steel_dark", bevel=0.03)
    p.slab(-0.92, -0.95, 0.33, 0.92, -0.9, 0.4, "steel", bevel=0.01)
    for i in range(7):
        x = -0.78 + i * 0.26
        p.beam((x, -0.945, 0.07), (x + 0.2, -0.945, 0.33), 0.03, 0.02, "steel", up=(0, 1, 0))
    for x in (-0.8, 0.8):
        for y in (-0.82, 0.82):
            p.slab(x - 0.09, y - 0.09, 0.0, x + 0.09, y + 0.09, 0.05, "steel_black")
    # The cells, with a terminal cap on each and a bar joining the caps of each row.
    zt = 1.12
    for x in (-0.47, 0.47):
        for y in (-0.47, 0.47):
            p.cyl((x, y, (0.3 + zt) / 2), 0.45, zt - 0.3, "blue_steel", segs=24, bevel=0.04)
            p.cyl((x * 0.85, y, zt + 0.06), 0.16, 0.12, "steel", segs=12, bevel=0.02)
            p.cyl((x * 0.85, y, zt + 0.15), 0.05, 0.08, "steel_light", segs=8)
    for y in (-0.47, 0.47):
        p.slab(-0.42, y - 0.08, zt, 0.42, y + 0.08, zt + 0.08, "steel", bevel=0.02)
    # The bridge down the middle, raised above the cells, with two terminal blocks.
    p.slab(-0.18, -0.5, zt + 0.05, 0.18, 0.62, zt + 0.16, "steel", bevel=0.03)
    for x in (-0.07, 0.07):
        p.slab(x - 0.045, 0.0, zt + 0.16, x + 0.045, 0.1, zt + 0.25, "ceramic")
    # Corner posts: braced from the middle of the tray at the front, tied to the bridge behind.
    for sx in (-1, 1):
        x = sx * 0.96
        p.beam((sx * 0.1, -0.95, 0.4), (x, -0.95, 1.0), 0.05, 0.04, "steel", up=(0, -1, 0))
        p.cyl((x, -0.95, 1.25), 0.03, 0.55, "steel", segs=6)
        insulator(p, x, -0.95, 1.5)
        p.beam((sx * 0.18, 0.4, zt + 0.12), (x, 0.95, 1.3), 0.05, 0.04, "steel")
        p.cyl((x, 0.95, 1.45), 0.03, 0.4, "steel", segs=6)
        insulator(p, x, 0.95, 1.62)
    return [p, accumulator_charge(zt), accumulator_discharge(zt)]


def accumulator_charge(zt):
    """Charging (accumulator-charge.png): the cells' tops glow blue and sparks jump at the corner
    insulators. Shown only while the mod reports it charging (anim_lit_charge, anim.gd)."""
    q = Part("anim_lit_charge")
    for x in (-0.47, 0.47):
        for y in (-0.47, 0.47):
            q.cyl((x, y, zt + 0.004), 0.41, 0.01, "glow_blue", segs=24)
    for k, (x, y, z) in enumerate(((-0.96, -0.95, 1.62), (0.96, -0.95, 1.62), (-0.96, 0.95, 1.74), (0.96, 0.95, 1.74))):
        kit.arc(q, (x, y, z), (x * 0.8, y * 0.85, z + 0.22), seed=k, kinks=4, jitter=0.05)
    return q


def accumulator_discharge(zt):
    """Discharging (accumulator-discharge.png): arcs run round the frame from insulator to
    insulator and across the cells' middle. Shown only while it discharges (anim_lit_discharge)."""
    q = Part("anim_lit_discharge")
    corners = [(-0.9, -0.9, 1.62), (0.9, -0.9, 1.62), (0.9, 0.9, 1.74), (-0.9, 0.9, 1.74)]
    for k, (a, b) in enumerate(zip(corners, corners[1:] + corners[:1])):
        kit.arc(q, a, b, seed=10 + k, kinks=9, jitter=0.06)
    for k, (a, b) in enumerate(((corners[0], (0.9, -0.92, 0.75)), ((-0.9, -0.93, 0.75), (0.9, -0.93, 0.75)),
                                (corners[1], (0.9, 0.0, 0.8)), (corners[0], (-0.9, 0.0, 0.8)))):
        kit.arc(q, a, b, seed=20 + k, kinks=8, jitter=0.05)
    return q


@model("radar")
def radar():
    """Factorio's radar: a turntable drum on a square truss platform, which stands on four
    bent truss legs reaching out to the corners; a generator box on the west side and a round
    housing on the east. On the turntable (anim_spin_radar, turning about the drum's axis) a
    curved dish band facing north on a bracket, with a feed rod reaching up in front of it."""
    p = Part()
    truss, dark = "bronze", "steel_dark"
    # Legs: from each platform corner out to a knee, then down to a foot at the footprint's
    # corner. The sprite's back knees sit higher and carry a block; the front ones arch low.
    # The sprite draws the east legs a little further out than the west ones.
    for sx in (-1, 1):
        for sy in (-1, 1):
            corner = (sx * 0.62, sy * 0.72, 0.9)
            if sy < 0:
                knee = (1.14 if sx > 0 else -1.11, -1.22, 0.62)
                foot, w = (1.42 if sx > 0 else -1.32, -1.38, 0.0), 0.26
            else:
                knee = (1.32 if sx > 0 else -1.28, 1.18, 0.86)
                foot, w = (knee[0] * 0.75, 0.9, 0.0), 0.2
            detail.girder(p, corner, knee, 0.2, 0.15, truss, bay=0.11, web=0.038, chord=0.06)
            detail.girder(p, knee, (foot[0], foot[1], 0.1), w, 0.16, truss, up=(sx, sy, 0), bay=0.11, web=0.038,
                          chord=0.065)
            if sy > 0:
                p.box(knee, (0.3, 0.3, 0.52), dark, bevel=0.03)
            p.slab(foot[0] - 0.12, foot[1] - 0.11, 0.0, foot[0] + 0.12, foot[1] + 0.11, 0.12, dark, bevel=0.02)
    # The platform: a square of truss beams round the drum, and a lower one between the legs.
    c = [(0.62, 0.72), (-0.62, 0.72), (-0.62, -0.72), (0.62, -0.72)]
    for i in range(4):
        a, b = c[i], c[(i + 1) % 4]
        detail.girder(p, (*a, 0.84), (*b, 0.84), 0.14, 0.18, truss)
    for sy, z, h in ((-1, 0.37, 0.36), (1, 0.4, 0.2)):
        p.beam((-0.85, sy * 0.95, z), (0.85, sy * 0.95, z), 0.1, h, truss)
        for k in range(7):   # the lattice's diagonals drawn on its face
            x0 = -0.8 + k * 0.23
            yf = sy * (0.95 + 0.055)
            p.beam((x0, yf, z - h / 2 + 0.03), (x0 + 0.2, yf, z + h / 2 - 0.03), 0.03, 0.02, "steel_dark",
                   up=(0, sy, 0))
    # Machinery under the drum fills the front between the platform and the lower beam.
    p.slab(-0.6, -0.8, 0.45, 0.6, -0.7, 0.82, dark)
    for x, y in c:
        p.slab(x - 0.1, y - 0.1, 0.3, x + 0.1, y + 0.1, 0.98, dark)
    # Side arches over the platform, rising towards the back.
    # The sprite's lattice horseshoe round the drum: up from the front corners, round the back.
    shoe = [(-0.66, -0.72, 0.95), (-0.66, -0.2, 1.2)]
    shoe += [(0.66 * math.cos(math.radians(a)), -0.05 + 0.7 * math.sin(math.radians(a)), 1.28)
             for a in range(180, -1, -30)]
    shoe += [(0.66, -0.2, 1.2), (0.66, -0.72, 0.95)]
    for q0, q1 in zip(shoe, shoe[1:]):
        detail.girder(p, q0, q1, 0.15, 0.16, truss, up=(0, 0, 1), bay=0.12, web=0.03)
    # The drum the turntable sits on.
    p.cyl((0, 0, 0.6), 0.58, 0.6, dark, segs=24, bevel=0.03)
    p.cyl((0, 0, 0.98), 0.64, 0.16, "blue_steel", segs=24, bevel=0.03)
    p.cyl((0, 0, 1.1), 0.52, 0.1, "steel", segs=24)
    p.cyl((0, 0, 1.152), 0.4, 0.01, "steel_dark", segs=24)
    p.bolts_ring((0, 0, 1.06), 0.6, 16, "steel_light", radius=0.02)
    p.bolts_ring((0, 0, 0.3), 0.58, 12, "steel_light", radius=0.02, axis="Z")
    # West: a generator box with coils; east: a round housing with a domed top.
    # Its back is stepped down on the outside, as the sprite shows.
    p.slab(-1.3, -0.3, 0.2, -0.6, 0.3, 1.12, dark, bevel=0.04)
    p.slab(-1.0, 0.25, 0.15, -0.6, 0.6, 1.12, dark, bevel=0.04)
    p.slab(-1.3, 0.25, 0.15, -0.95, 0.6, 0.8, dark, bevel=0.04)
    for y in (-0.1, 0.15, 0.4):
        p.cyl((-0.95, y, 1.12), 0.08, 0.5 if y < 0.3 else 0.3, "steel_light", segs=8, axis="X")
    p.slab(-1.33, -0.28, 0.25, -1.28, 0.2, 1.0, "steel_light")
    detail.slots(p, (-1.3, -0.3, 0.2), (-0.6, 0.3, 1.12), "-y", 5)
    detail.spring(p, (-1.25, -0.42, 0.35), (-1.25, -0.42, 0.75), 0.1, "steel_light", turns=7)
    detail.panel(p, (-1.3, -0.3, 0.2), (-0.6, 0.3, 1.12), "+z", "steel_dark", rivet=None)
    p.cyl((1.05, 0.25, 0.68), 0.38, 0.96, dark, segs=18, bevel=0.03, radius_top=0.46)
    p.cyl((1.05, 0.25, 1.0), 0.45, 0.08, "blue_steel", segs=18)
    p.sphere((1.05, 0.3, 1.16), 0.22, "steel", segs=12, rings=4, hemisphere=True)
    p.slab(0.85, -0.6, 0.2, 1.25, -0.1, 0.8, dark, bevel=0.03)
    detail.slots(p, (0.85, -0.6, 0.2), (1.25, -0.1, 0.8), "-y", 4)
    for z in (0.5, 0.8):
        p.cyl((1.05, 0.25, z), 0.4 + (z - 0.2) * 0.08, 0.04, "steel_light", segs=18)

    spin = Part("anim_spin_radar", pivot=(0, 0, 1.15))
    spin.cyl((0, 0, 1.2), 0.42, 0.1, "steel_light", segs=20)
    # The bracket: two plates up to the dish's middle, a cross block between them.
    for x in (-0.22, 0.22):
        spin.slab(x - 0.06, -0.15, 1.2, x + 0.06, 0.3, 2.0, "steel", bevel=0.02)
    spin.slab(-0.3, -0.18, 1.6, 0.3, 0.25, 1.85, "rust_light", bevel=0.03)
    # The dish: a band curved round a centre north of it, so its ends reach north. The sprite's
    # first frame has it turned a few degrees anticlockwise, the feed rod leaning a little west.
    dish = Part()
    R, xc, zt = 1.52, 0.05, 2.21
    yc = 0.35 + R
    half = math.degrees(math.asin(1.12 / R))
    dish.ring_band((xc, yc), R - 0.05, R, 1.11, zt, 270 - half, 270 + half, "olive_steel", segs=12)
    for z in (1.15, 1.52, 1.89, zt - 0.05):
        dish.ring_band((xc, yc), R, R + 0.05, z, z + 0.05, 270 - half, 270 + half, "brass", segs=12)
    tip = (-0.08, 0.9, 2.42)
    spin.tube((0, 0.32, 1.7), tip, 0.03, "ceramic", segs=6)
    for sx in (-1, 1):
        a = math.radians(270 + sx * half)
        dish.tube(tip, (xc + R * math.cos(a), yc + R * math.sin(a), zt), 0.008, "steel_dark", segs=4)
    spin.add_part(dish.transform(R_Z(RADAR_TURN)))
    return [p, spin]


RADAR_TURN = 4.5
