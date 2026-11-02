"""Cliffs, modelled on Factorio's cliff sprites (data/base/graphics/terrain/cliffs/, and Space
Age's under data/space-age/graphics/terrain/cliffs/<planet>/).

A Factorio cliff is a chain of entities on a 4x4-tile grid. Each one runs from the middle of one
edge of its cell to the middle of another (`cliff_orientation`, "west-to-east" ... "none-to-north")
with the high ground on its left; the cliff face looks out to the right, over the low ground.
Twenty orientations come from five pieces, each turned in quarter turns by the client
(model_library.gd, CLIFF_PIECES):

    sides     straight, west to east (the face looks south)
    outer     turning left, west to north: a corner of the high ground
    inner     turning right, west to south: a bay in the high ground
    exit      west to none: the cliff runs out in the middle of the cell
    entrance  none to east: the cliff starts in the middle of the cell

Every piece has the same cross-section where it meets the edge of its cell, so any chain joins
up. The ground stays flat in the client, so a cliff is a ridge: a steep face of tall, broken,
column-like blocks (the Nauvis sprites' look; Vulcanus, Gleba and Fulgora have flat layered
slabs instead), a crest with loose boulders, and a slope back down on the high side. Sizes
come from the HR sprites: the tallest blocks stand about 2.6 tiles high and the whole cliff is about
3.3 tiles across.
"""

import math

from mathutils import Vector

from geo import material
from rocks import column, fragment

ROCK = material("cliff-rock", "#8a6844", 0.95)
ROCK_DARK = material("cliff-rock-dark", "#4a3620", 1.0)
HEIGHT = 2.5
# The cross-section, from the high side to the low: (offset towards the face, height / HEIGHT).
# The crest stands a little in front of the line and the face's foot near the cell's edge, as
# the sprites have it (seen along the cliff, the north-south sprites span -1.5 to +1.75 tiles).
PROFILE = ((-1.5, 0.0), (-1.0, 0.25), (-0.5, 0.58), (-0.1, 0.74), (0.25, 0.76), (0.7, 0.5), (1.2, 0.22),
           (1.75, 0.0))
STEPS = 16

PLANETS = {
    # suffix: (rock, dark rock, style)
    "": (ROCK, ROCK_DARK, "columns"),
    "vulcanus": (material("cliff-vulcanus-rock", "#4a4440", 0.95), material("cliff-vulcanus-rock-dark", "#1e1b1a", 1.0),
                 "slabs"),
    "gleba": (material("cliff-gleba-rock", "#6a6a58", 0.95), material("cliff-gleba-rock-dark", "#2c2e24", 1.0),
              "slabs"),
    "fulgora": (material("cliff-fulgora-rock", "#9a5a58", 0.95), material("cliff-fulgora-rock-dark", "#4a2626", 1.0),
                "slabs"),
}
# Gleba's cliffs are wrapped in orange roots.
GLEBA_ROOT = material("cliff-gleba-flesh-root", "#a06a2a", 0.8)


def smooth(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def path(kind):
    """The piece's line as a function of t in 0..1 -> (point, tangent, scale): x east, y north,
    in tiles from the cell's centre. `scale` shrinks the ridge where a cliff starts or ends."""
    if kind == "sides":
        return lambda t: (Vector((-2.0 + 4.0 * t, 0.0)), Vector((1.0, 0.0)), 1.0)
    if kind == "outer":  # quarter circle round the north-west corner, turning left
        def outer(t):
            a = math.radians(-90.0 + 90.0 * t)
            return (Vector((-2.0, 2.0)) + 2.0 * Vector((math.cos(a), math.sin(a))),
                    Vector((-math.sin(a), math.cos(a))), 1.0)
        return outer
    if kind == "inner":  # quarter circle round the south-west corner, turning right
        def inner(t):
            a = math.radians(90.0 - 90.0 * t)
            return (Vector((-2.0, -2.0)) + 2.0 * Vector((math.cos(a), math.sin(a))),
                    Vector((math.sin(a), -math.cos(a))), 1.0)
        return inner
    if kind == "exit":
        return lambda t: (Vector((-2.0 + 3.0 * t, 0.0)), Vector((1.0, 0.0)), 1.0 - smooth(0.35, 1.0, t))
    if kind == "entrance":
        return lambda t: (Vector((-1.0 + 3.0 * t, 0.0)), Vector((1.0, 0.0)), smooth(0.0, 0.65, t))
    raise ValueError(kind)


def length(kind):
    return {"sides": 4.0, "outer": math.pi, "inner": math.pi, "exit": 3.0, "entrance": 3.0}[kind]


def frame(f, t, r, z):
    """A point `r` tiles to the right of the line (towards the face) at height z."""
    p, tangent, _ = f(t)
    right = Vector((tangent.y, -tangent.x))
    q = p + right * r
    return Vector((q.x, q.y, z))


def body(m, kind, rock, rng):
    """The ridge itself: the profile swept along the line, wobbling a little except at the ends
    (where it must meet the next piece exactly)."""
    f = path(kind)
    bm = m.bm
    rings = []
    for i in range(STEPS + 1):
        t = i / STEPS
        s = f(t)[2]
        edge = min(t, 1.0 - t)
        wobble = smooth(0.0, 0.12, edge) if kind not in ("exit", "entrance") else smooth(0.0, 0.12, t if kind == "exit" else 1.0 - t)
        ring = []
        for k, (r, h) in enumerate(PROFILE):
            w = wobble * (0.0 if h == 0.0 else rng.uniform(-0.12, 0.12))
            reach = 0.35 + 0.65 * s  # a dying cliff is narrower as well as lower
            ring.append(bm.verts.new(frame(f, t, r * reach + w, max(0.0, h * HEIGHT * s * (1.0 + w)) - (0.06 if h == 0.0 else 0.0))))
        rings.append(ring)
    verts = []
    for a, b in zip(rings, rings[1:]):
        for k in range(len(PROFILE) - 1):
            bm.faces.new((a[k], a[k + 1], b[k + 1], b[k]))
        verts += a
    verts += rings[-1]
    for ring in (rings[0], rings[-1]):
        if f(0.0 if ring is rings[0] else 1.0)[2] > 0.05:
            bm.faces.new(ring)
    m._tag(verts, rock, False, (0.85, 0.85, 0.85), 0.15)


def columns(m, kind, rock, dark, rng):
    """Tall, broken, column-like blocks standing along the face (Nauvis), shorter ones in front
    of them and a skirt of fallen stones at the foot."""
    f = path(kind)
    n = int(length(kind) / 0.5)
    for i in range(n):
        t = (i + rng.uniform(0.25, 0.75)) / n
        s = f(t)[2]
        if s < 0.12:
            continue
        h = HEIGHT * s * rng.uniform(0.62, 1.04)
        reach = 0.35 + 0.65 * s
        base = frame(f, t, rng.uniform(0.15, 0.55) * reach, 0.0)
        p, tangent, _ = f(t)
        out = Vector((tangent.y, -tangent.x, 0.0))
        # Leaning back a little into the cliff, so the tops sit on the crest.
        column(m, base, rng.uniform(0.3, 0.42) * (0.6 + 0.4 * s), h, rock, sides=rng.choice((5, 6)),
               lean=(-out.x * 0.25, -out.y * 0.25), taper=0.8, tint=(rng.uniform(0.75, 1.0),) * 3)
    for i in range(int(n * 0.8)):
        t = (i + rng.uniform(0.0, 1.0)) / int(n * 0.8)
        s = f(t)[2]
        if s < 0.25:
            continue
        base = frame(f, t, rng.uniform(0.8, 1.15) * (0.35 + 0.65 * s), 0.0)
        column(m, base, rng.uniform(0.2, 0.3), HEIGHT * s * rng.uniform(0.2, 0.45), rock, sides=5,
               taper=0.8, tint=(rng.uniform(0.65, 0.85),) * 3)
    lip_and_rubble(m, kind, rock, dark, rng, n)


def slabs(m, kind, rock, dark, rng):
    """Flat layered slabs stacked up the face (Vulcanus, Gleba, Fulgora): each layer a little
    further back than the one under it, with ragged ends."""
    f = path(kind)
    n = int(length(kind) / 0.5)
    layers = 4
    for i in range(n):
        t = (i + 0.5) / n
        s = f(t)[2]
        if s < 0.12:
            continue
        p, tangent, _ = f(t)
        for k in range(layers):
            z0 = HEIGHT * s * k / layers
            z1 = HEIGHT * s * (k + 1) / layers * rng.uniform(0.95, 1.05)
            r = 1.3 - 1.0 * k / layers + rng.uniform(-0.06, 0.06)
            c = frame(f, t, (r - 0.35) * (0.4 + 0.6 * s), z0)
            half = Vector((tangent.x, tangent.y, 0.0)) * rng.uniform(0.3, 0.42)
            depth = Vector((tangent.y, -tangent.x, 0.0)) * 0.35
            slab(m, c, half, depth, z1 - z0, rock if k % 2 == 0 else dark, rng)
    lip_and_rubble(m, kind, rock, dark, rng, n)


def slab(m, centre, half, depth, height, mat, rng):
    """A block with a slightly tilted, uneven top: one layer of a stratified cliff."""
    bm = m.bm
    corners = [centre - half - depth, centre + half - depth, centre + half + depth, centre - half + depth]
    corners = [c + Vector((rng.uniform(-0.05, 0.05), rng.uniform(-0.05, 0.05), 0.0)) for c in corners]
    low = [bm.verts.new(c - Vector((0, 0, 0.03))) for c in corners]
    high = [bm.verts.new(c + Vector((0, 0, height * rng.uniform(0.9, 1.08)))) for c in corners]
    for k in range(4):
        bm.faces.new((low[k], low[(k + 1) % 4], high[(k + 1) % 4], high[k]))
    bm.faces.new(high)
    m._tag(low + high, mat, False, (rng.uniform(0.8, 1.0),) * 3)


def lip_and_rubble(m, kind, rock, dark, rng, n):
    """Pale boulders along the crest (what Factorio shows of a cliff seen from the high side) and
    fallen stones in front of the face."""
    f = path(kind)
    for i in range(max(3, n // 3)):
        t = (i + rng.uniform(0.2, 0.8)) / max(3, n // 3)
        s = f(t)[2]
        if s < 0.3:
            continue
        r = rng.uniform(-0.35, 0.05)
        z = HEIGHT * s * 0.7
        fragment(m, frame(f, t, r, z), rng.uniform(0.16, 0.26) * s, rock, scale=(1.2, 1.0, 0.75),
                 tint=(rng.uniform(0.95, 1.1),) * 3)
    for i in range(max(4, int(n * 0.7))):
        t = rng.uniform(0.04, 0.96)
        s = f(t)[2]
        if s < 0.2:
            continue
        fragment(m, frame(f, t, rng.uniform(1.3, 2.0) * (0.5 + 0.5 * s), 0.0), rng.uniform(0.07, 0.17), dark,
                 scale=(1.2, 1.0, 0.7), tint=(rng.uniform(0.7, 0.95),) * 3)


def roots(m, kind, rng):
    """Gleba: thick orange roots drape from the crest and fork across the low ground."""
    f = path(kind)
    n = max(5, int(length(kind) / 0.52))
    for i in range(n):
        t = (i + rng.uniform(0.2, 0.8)) / n
        s = f(t)[2]
        if s < 0.3:
            continue
        # Each tendril sweeps sideways along the cliff as it drapes over the face, then spreads
        # across the ground. This follows Gleba's wide branching root fans instead of making
        # parallel vertical ropes.
        drift = rng.choice((-1, 1)) * rng.uniform(0.14, 0.28)
        t1 = min(0.98, max(0.02, t + drift * 0.35))
        t2 = min(0.98, max(0.02, t + drift))
        t3 = min(0.98, max(0.02, t + drift * 1.45))
        top = frame(f, t, -0.16, HEIGHT * s * 0.98)
        mid = frame(f, t1, 0.22, HEIGHT * s * 0.84)
        shoulder = frame(f, t2, 0.82, HEIGHT * s * 0.58)
        lower = frame(f, t2, 1.52, HEIGHT * s * 0.32)
        outer = frame(f, t3, 2.18, HEIGHT * s * 0.12)
        foot = frame(f, t3, rng.uniform(2.65, 3.25), 0.0)
        m.tube((top, mid, shoulder, lower, outer, foot), (0.19, 0.17, 0.14, 0.10, 0.06, 0.022),
               GLEBA_ROOT, segments=5, smooth=False)
        fork_t = min(0.98, max(0.02, t2 - math.copysign(rng.uniform(0.25, 0.38), drift)))
        fork = frame(f, fork_t, rng.uniform(2.4, 3.1), 0.0)
        m.tube((shoulder, frame(f, fork_t, 1.5, HEIGHT * s * 0.38), fork),
               (0.105, 0.065, 0.02), GLEBA_ROOT, segments=5, smooth=False)


def shade(m):
    def fn(face, p, n):
        h = min(1.0, max(0.0, p.z / HEIGHT))
        up = max(0.0, n.z)
        return 0.35 + 0.65 * min(1.0, 0.2 + 0.45 * h + 0.45 * up)
    m.shade(fn)


def cliff(kind, planet=""):
    rock, dark, style = PLANETS[planet]

    def build(m):
        rng = m.rng
        body(m, kind, rock, rng)
        if style == "columns":
            columns(m, kind, rock, dark, rng)
        else:
            slabs(m, kind, rock, dark, rng)
        if planet == "gleba":
            roots(m, kind, rng)
        shade(m)
    return build


KINDS = ("sides", "outer", "inner", "exit", "entrance")
MODELS = {}
for _planet in PLANETS:
    for _kind in KINDS:
        MODELS["cliff-%s%s" % (_planet + "-" if _planet else "", _kind)] = cliff(_kind, _planet)
