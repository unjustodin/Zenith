"""Railways: ground and elevated rail pieces, rail supports and ramps, signals, train stops, gates.

Factorio 2.x lays track from four pieces, each in eight directions (north, northeast, ... in the
16-way encoding: 0, 2, 4, ... 14). A piece turned by 90 degrees is the same piece, so each has
two models: `<name>` for direction 0 and `<name>-ne` for direction 2 (a mirror image for the
curves, the 45 degree piece for the straight). The client turns them by the rest of the
direction in quarter turns (model_library.gd, turn_dir).

Track geometry, measured from the rail sprites (rail-metals.png, 64 px a tile) and fitted to
within about a pixel: every piece runs between two rail ends, given here in Factorio's axes
(x east, y south) relative to the entity's position:

    straight         (0, 1) -> (0, -1)                north
    straight-ne      (-1, 1) -> (1, -1)               45 degrees
    half-diagonal    (1, 2) -> (-1, -2)               1 across, 2 along
    curved-a         (0, 2) north -> (-1, -3) along the half-diagonal
    curved-b         (1, 2) along the half-diagonal -> (-2, -2) along the diagonal

Curves are cubic Beziers with the end tangents of the pieces they join, so track runs on
without a kink. Layers follow the sprites: a ballast bed of stones, wooden ties every 0.4 tiles
(as the straight piece's five), steel tie plates under the rails, and the rails, 0.59 tiles
either side of the centre line. The sprites are drawn straight down (rails are flat), so their
projection is "top" (sprite_projection.py).

Elevated pieces carry the same track on a steel deck 4.5 tiles up (the sprites' 3 tile shift): two side
girders with X bracing between them and red railings, as the elevated-rail sheets show.
"""

import math
import zlib

from mathutils import Vector

import kit
from kit import Part, model, rng

# Colours picked from the rail sprites (their lit parts, lighting taken out).
kit.MATERIALS.update({
    "stone_ballast": ("6e604d", 0.95, 0.0, None, 0),   # rail-stone-path: grey-brown stones
    "stone_ballast_light": ("9a8f80", 0.95, 0.0, None, 0),
    "wood_tie": ("9a7f4a", 0.85, 0.0, None, 0),        # rail-ties: weathered ochre wood
    "steel_rail": ("a9a9a6", 0.35, 0.9, None, 0),      # rail-metals: bright worn steel
    "paint_rail_red": ("a2432f", 0.6, 0.35, None, 0),  # elevated rails' railings and supports
})

GAUGE = 0.586        # centre line to rail, tiles
TIE_HALF = 0.78      # ties reach this far either side
TIE_WIDTH = 0.125
TIE_STEP = 0.4
BED_HALF = 1.02      # ballast at the ground (the sprite's stones reach 1.2, ragged)
BED_TOP_HALF = 0.8  # ballast top
BED_Z = 0.07
TIE_Z0, TIE_Z1 = 0.05, 0.105
PLATE_Z = 0.12
RAIL_PROFILE = [  # (across, up) round the rail's section, counter-clockwise seen along the rail
    (-0.045, 0.0), (0.045, 0.0), (0.045, 0.014), (0.013, 0.024), (0.013, 0.062), (0.026, 0.07),
    (0.026, 0.095), (-0.026, 0.095), (-0.026, 0.07), (-0.013, 0.062), (-0.013, 0.024), (-0.045, 0.014)]
# Deck top above the ground. The sprites draw elevated rails 3 tiles up the screen; heights here
# are matched to sprites through compare.py's 48 degree camera (a height shows 0.669 as tall), as
# every other model is, so the deck is 3 / 0.669 tiles up and trains (2.5 tall) fit under it.
ELEVATION = 4.5
DECK_HALF = 1.0      # side girders' centre lines

S5 = 1 / math.sqrt(5)
S2 = 1 / math.sqrt(2)
# Factorio axes: (start, start direction, end, end direction, tangent length).
PIECES = {
    "straight": ((0, 1), (0, -1), (0, -1), (0, -1), None),
    "straight-ne": ((-1, 1), (S2, -S2), (1, -1), (S2, -S2), None),
    "half-diagonal": ((1, 2), (-S5, -2 * S5), (-1, -2), (-S5, -2 * S5), None),
    "half-diagonal-ne": ((-1, 2), (S5, -2 * S5), (1, -2), (S5, -2 * S5), None),
    "curved-a": ((0, 2), (0, -1), (-1, -3), (-S5, -2 * S5), 1.4),
    "curved-a-ne": ((0, 2), (0, -1), (1, -3), (S5, -2 * S5), 1.4),
    "curved-b": ((1, 2), (-S5, -2 * S5), (-2, -2), (-S2, -S2), 1.8),
    "curved-b-ne": ((-1, 2), (S5, -2 * S5), (2, -2), (S2, -S2), 1.8),
}
# Prototype name for each piece (ground; elevated ones are "elevated-" + this).
PIECE_PROTOS = {"straight": "straight-rail", "half-diagonal": "half-diagonal-rail",
                "curved-a": "curved-rail-a", "curved-b": "curved-rail-b"}


class Track:
    """A piece's centre line in Blender axes (x east, y north): point and unit tangent at a
    distance along it, sampled finely and walked by arc length."""

    def __init__(self, piece):
        p0, d0, p1, d1, a = PIECES[piece]
        b = lambda v: Vector((v[0], -v[1]))  # noqa: E731  (Factorio y south -> Blender y north)
        self.p0, self.d0, self.p1, self.d1 = b(p0), b(d0).normalized(), b(p1), b(d1).normalized()
        self.curved = a is not None
        if a is None:
            a = (self.p1 - self.p0).length / 3
        c1, c2 = self.p0 + self.d0 * a, self.p1 - self.d1 * a
        n = 400
        self.pts = []
        for i in range(n + 1):
            t = i / n
            u = 1 - t
            self.pts.append(self.p0 * u ** 3 + c1 * 3 * u * u * t + c2 * 3 * u * t * t + self.p1 * t ** 3)
        self.cum = [0.0]
        for q0, q1 in zip(self.pts, self.pts[1:]):
            self.cum.append(self.cum[-1] + (q1 - q0).length)
        self.length = self.cum[-1]

    def at(self, s):
        """(point, tangent, left normal) at distance s."""
        s = min(max(s, 0.0), self.length)
        lo, hi = 0, len(self.cum) - 1
        while hi - lo > 1:
            mid = (lo + hi) // 2
            if self.cum[mid] <= s:
                lo = mid
            else:
                hi = mid
        f = (s - self.cum[lo]) / max(self.cum[hi] - self.cum[lo], 1e-9)
        p = self.pts[lo].lerp(self.pts[hi], f)
        if s <= 0:
            t = self.d0
        elif s >= self.length:
            t = self.d1
        else:
            t = (self.pts[hi] - self.pts[lo]).normalized()
        return p, t, Vector((-t.y, t.x))

    def stations(self, step=0.25):
        n = 1 if not self.curved else max(2, int(math.ceil(self.length / step)))
        return [self.length * i / n for i in range(n + 1)]


def sweep(part, track, profile, mat, offset=0.0, z=0.0, step=0.25, jitter=None, caps=True):
    """Sweeps a closed `profile` [(across, up), ...] along the track, `offset` to the left of the
    centre line. `jitter(i, j, s)` may lift profile point j at station i (rough ballast); it must
    be 0 at both ends so pieces meet."""
    rows = []
    stations = track.stations(step)
    for i, s in enumerate(stations):
        p, _t, n = track.at(s)
        row = []
        for j, (a, h) in enumerate(profile):
            dz = jitter(i, j, s) if jitter else 0.0
            q = p + n * (offset + a)
            row.append((q.x, q.y, z + h + dz))
        rows.append(row)
    import bmesh  # noqa: PLC0415  (Blender only)
    bm = bmesh.new()
    vrows = [[bm.verts.new(v) for v in row] for row in rows]
    k = len(profile)
    for r0, r1 in zip(vrows, vrows[1:]):
        for j in range(k):
            j2 = (j + 1) % k
            bm.faces.new([r0[j], r0[j2], r1[j2], r1[j]])
    if caps:
        bm.faces.new(list(reversed(vrows[0])))
        bm.faces.new(vrows[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    part.merge(bm, mat)
    bm.free()


def ties(track):
    n = max(1, round(track.length / TIE_STEP))
    return [track.length * (i + 0.5) / n for i in range(n)]


def bed_height(across):
    """Height of the ballast bed's surface at a distance across the track."""
    a = abs(across)
    if a <= BED_TOP_HALF:
        return BED_Z
    return max(0.0, BED_Z * (BED_HALF - a) / (BED_HALF - BED_TOP_HALF))


def stones(part, track, r, z=0.0, per_tile=60):
    """Loose stones over the ballast (low octahedra in two shades), so the bed reads as stones
    from any side, where Factorio's top-down sprite doesn't reach."""
    import bmesh  # noqa: PLC0415  (Blender only)
    count = int(track.length * per_tile)
    for _ in range(count):
        s = r.uniform(0.02, track.length - 0.02)
        across = r.uniform(-BED_HALF + 0.05, BED_HALF - 0.05)
        if abs(abs(across) - GAUGE) < 0.06:
            continue  # not through the rails
        p, t, n = track.at(s)
        q = p + n * across
        size = r.uniform(0.03, 0.06)
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=4, v_segments=2, radius=size)  # an octahedron
        bmesh.ops.scale(bm, vec=(r.uniform(0.8, 1.3), r.uniform(0.8, 1.3), r.uniform(0.45, 0.7)), verts=bm.verts)
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0),
                         matrix=kit.R("Z", r.uniform(0, 360)).to_3x3() @ kit.R("X", r.uniform(-25, 25)).to_3x3())
        part.merge(bm, "stone_ballast" if r.random() < 0.6 else "stone_ballast_light",
                   kit.T(q.x, q.y, z + bed_height(across) + size * 0.15))
        bm.free()


def track_on(part, track, z=0.0, ballast=True, seed=1):
    """Ballast (optional), ties, tie plates and rails along the track, `z` above the ground."""
    r = rng(seed)
    if ballast:
        bed = [(-BED_HALF, 0.0), (BED_HALF, 0.0), (BED_TOP_HALF, BED_Z), (0.35, BED_Z + 0.012),
               (-0.35, BED_Z + 0.012), (-BED_TOP_HALF, BED_Z)]
        last = len(track.stations(0.25)) - 1
        bumps = {}

        def rough(i, j, s):
            if i in (0, last) or j < 2:
                return 0.0
            return bumps.setdefault((i, j), r.uniform(-0.012, 0.018))
        sweep(part, track, bed, "stone_ballast", z=z, jitter=rough)
        stones(part, track, r, z)
    for s in ties(track):
        p, t, n = track.at(s)
        yaw = math.degrees(math.atan2(t.y, t.x)) + 90
        wob = r.uniform(-2.0, 2.0)
        part.box((p.x, p.y, z + (TIE_Z0 + TIE_Z1) / 2), (TIE_WIDTH, TIE_HALF * 2, TIE_Z1 - TIE_Z0),
                 "wood_tie", bevel=0.012, rz=yaw - 90 + wob)
        for side in (-1, 1):
            q = p + n * (side * GAUGE)
            part.box((q.x, q.y, z + (TIE_Z1 + PLATE_Z) / 2), (0.16, 0.24, PLATE_Z - TIE_Z1 + 0.004),
                     "steel_dark", rz=yaw - 90 + wob)
            for k in (-1, 1):
                b = q + n * (k * 0.085)
                part.cyl((b.x, b.y, z + PLATE_Z + 0.008), 0.018, 0.02, "steel_light", segs=6)
    for side in (-1, 1):
        sweep(part, track, RAIL_PROFILE, "steel_rail", offset=side * GAUGE, z=z + PLATE_Z - 0.003)


def centre_uvs(part, track):
    """Every vertex's UV is the nearest point of the track's centre line (x, y in tiles). The
    client's top-down sprite projection squashes distances across the track north-south from it,
    as Factorio's rail sprites are drawn (sprite_projection.py, "across")."""
    from mathutils import kdtree  # noqa: PLC0415  (Blender only)
    tree = kdtree.KDTree(len(track.pts))
    for i, q in enumerate(track.pts):
        tree.insert((q.x, q.y, 0.0), i)
    tree.balance()

    def fn(co):
        q, _i, _d = tree.find((co.x, co.y, 0.0))
        return (q.x, q.y)
    part.uv_fn = fn
    return part


def rail_piece(piece):
    p = Part()
    track = Track(piece)
    track_on(p, track, seed=zlib.crc32(piece.encode()))
    return centre_uvs(p, track)


# ---------------------------------------------------------------------------------------------
# Elevated track

def deck(part, track, seed=1):
    """The elevated deck under the track: side girders (I-beams), X bracing below the ties, and a
    red railing on posts along both edges."""
    h = ELEVATION
    girder = [(-0.07, -0.34), (0.07, -0.34), (0.07, -0.3), (0.025, -0.29), (0.025, -0.05), (0.07, -0.04),
              (0.07, 0.0), (-0.07, 0.0), (-0.07, -0.04), (-0.025, -0.05), (-0.025, -0.29), (-0.07, -0.3)]
    for side in (-1, 1):
        sweep(part, track, girder, "steel_dark", offset=side * DECK_HALF, z=h)
        # Railing: a red tube along the edge on short posts, and a kick plate.
        sweep(part, track, [(-0.035, 0.0), (0.035, 0.0), (0.035, 0.05), (-0.035, 0.05)], "paint_rail_red",
              offset=side * (DECK_HALF + 0.12), z=h + 0.42)
        sweep(part, track, [(-0.02, -0.12), (0.02, -0.12), (0.02, 0.12), (-0.02, 0.12)], "paint_rail_red",
              offset=side * (DECK_HALF + 0.1), z=h - 0.05)
    # Posts and cross frames every half tile or so; X bracing between them.
    n = max(2, round(track.length / 0.67))
    marks = [track.length * i / n for i in range(n + 1)]
    for i, s in enumerate(marks):
        p, t, nrm = track.at(s)
        inset = 0.04 if i == 0 else (-0.04 if i == n else 0.0)
        p = p + t * inset
        a = p + nrm * DECK_HALF
        b = p - nrm * DECK_HALF
        part.beam((a.x, a.y, h - 0.32), (b.x, b.y, h - 0.32), 0.07, 0.07, "steel_dark")
        for side in (-1, 1):
            q = p + nrm * (side * (DECK_HALF + 0.12))
            part.box((q.x, q.y, h + 0.22), (0.06, 0.06, 0.42), "paint_rail_red")
    for s0, s1 in zip(marks, marks[1:]):
        p0, _t0, n0 = track.at(s0)
        p1, _t1, n1 = track.at(s1)
        for k in (-1, 1):
            a = p0 + n0 * (k * DECK_HALF * 0.95)
            b = p1 - n1 * (k * DECK_HALF * 0.95)
            part.beam((a.x, a.y, h - 0.2), (b.x, b.y, h - 0.2), 0.05, 0.04, "steel_dark")


def elevated_piece(piece):
    p = Part()
    track = Track(piece)
    deck(p, track)
    track_on(p, track, z=ELEVATION - 0.05, ballast=False, seed=zlib.crc32(piece.encode()))
    return centre_uvs(p, track)


def _register_rails():
    for piece, proto in PIECE_PROTOS.items():
        for suffix in ("", "-ne"):
            model(proto + suffix)(lambda piece=piece + suffix: rail_piece(piece))
            model("elevated-" + proto + suffix)(lambda piece=piece + suffix: elevated_piece(piece))


_register_rails()
