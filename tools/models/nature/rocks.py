"""Nauvis rocks and ore tiles, modelled on Factorio's decorative rock and resource sprites.

Factorio's big and huge rocks are warm brown heaps of angular, column-like blocks with flat
broken tops, standing in a skirt of smaller fragments; the sand rock is a rounded, eroded ochre
lump on a dark reddish base. Sizes come from the HR sprites seen from Factorio's camera (north,
48 degrees down: a point `z` up shows `z * 0.67` up the sprite).

An ore tile is a scatter of glossy, half-buried chunks with a sprinkle of dust between them,
spread a little past the tile (the sprites cover 2x2 tiles) so a patch reads as one field. The
client turns and sizes every tile at random and raises richer tiles.
"""

import math

from mathutils import Vector

from geo import material

ROCK = material("rock", "#a87445", 0.92)
SAND_ROCK = material("sand-rock", "#b89152", 0.95)

ORES = {
    # name: (chunk, chunk roughness, chunk metallic, chunk tints, dust)
    "iron-ore": ("#a9c2cc", 0.3, 0.25, ((1.0, 1.0, 1.0), (0.8, 0.86, 0.9), (0.66, 0.7, 0.75)), "#5a4535"),
    "copper-ore": ("#ff9a52", 0.32, 0.2, ((1.0, 1.0, 1.0), (0.92, 0.76, 0.62), (0.8, 0.6, 0.45)), "#7c4a32"),
    "coal": ("#35342f", 0.3, 0.0, ((1.0, 1.0, 1.0), (0.85, 0.84, 0.82), (0.72, 0.7, 0.68)), "#3a2a18"),
    "stone": ("#d6b97c", 0.8, 0.0, ((1.0, 1.0, 1.0), (0.9, 0.88, 0.8), (0.8, 0.76, 0.68)), "#5a5034"),
    # Uranium: glossy bright green lumps on a reddish-brown dust (uranium-ore.png; its glow layer is
    # left out). Space Age: tungsten's blue-violet slate shards, calcite's pale cream lumps.
    "uranium-ore": ("#5fd23a", 0.3, 0.0, ((1.0, 1.0, 1.0), (0.85, 0.95, 0.8), (0.7, 0.8, 0.62)), "#6a3c26"),
    "tungsten-ore": ("#6c6680", 0.4, 0.35, ((1.0, 1.0, 1.0), (0.85, 0.84, 0.92), (0.7, 0.7, 0.78)), "#3c3440"),
    "calcite": ("#e6dcc6", 0.6, 0.0, ((1.0, 1.0, 1.0), (0.92, 0.9, 0.84), (0.82, 0.8, 0.74)), "#7a6e5c"),
}


def column(m, base, radius, height, mat, sides=None, lean=(0.0, 0.0), taper=0.85, tint=None, sink=0.08):
    """An angular rock column: an irregular prism with a tilted, bevelled flat top, like the
    blocks Factorio's big and huge rocks are piled from."""
    rng = m.rng
    bm = m.bm
    sides = sides or rng.randint(4, 6)
    a0 = rng.uniform(0.0, math.tau)
    b = Vector(base)
    top_c = b + Vector((lean[0], lean[1], height))
    tilt = Vector((rng.uniform(-0.45, 0.45), rng.uniform(-0.45, 0.45), 0.0))
    ring = []
    for k in range(sides):
        a = a0 + k / sides * math.tau + rng.uniform(-0.25, 0.25)
        r = radius * rng.uniform(0.6, 1.25)
        ring.append((math.cos(a) * r, math.sin(a) * r))
    low = [bm.verts.new(b + Vector((x, y, -sink))) for x, y in ring]
    mid = [bm.verts.new(b + Vector((x * (1 + taper) / 2, y * (1 + taper) / 2, height * 0.55))
                        + Vector((lean[0], lean[1], 0.0)) * 0.55) for x, y in ring]
    shoulder = []
    cap = []
    for x, y in ring:
        off = Vector((x, y, 0.0)) * taper
        h = tilt.dot(off) * 0.8
        shoulder.append(bm.verts.new(top_c + off + Vector((0, 0, h - height * 0.12))))
        cap.append(bm.verts.new(top_c + off * 0.72 + Vector((0, 0, h))))
    n = sides
    for rows in ((low, mid), (mid, shoulder), (shoulder, cap)):
        a, c = rows
        for k in range(n):
            bm.faces.new((a[k], a[(k + 1) % n], c[(k + 1) % n], c[k]))
    bm.faces.new(cap)
    m._tag(low + mid + shoulder + cap, mat, False, tint, 0.25)


def fragment(m, center, radius, mat, scale=(1.0, 1.0, 0.6), tint=None):
    """A broken stone lying in the skirt round a rock: a chopped, flat-bottomed lump."""
    verts = m.blob(center, radius, mat, scale=scale, jitter=0.3, subdiv=1, flat_bottom=-0.05, tint=tint, vary=0.25)
    c = Vector(center)
    m.chop(verts, c, [((m.rng.uniform(-0.3, 0.3), m.rng.uniform(-0.3, 0.3), 1.0), 0.6)])
    return verts


# Each rock's size and place, fitted to its sprite (the first of the prototype's pictures) seen
# from Factorio's camera: ((across, north-south, height) scale, (east, north) shift in tiles).
FIT = {
    "big-rock": ((0.98, 1.2, 1.41), (-0.06, -0.36)),
    "huge-rock": ((0.7, 1.16, 1.24), (-0.06, -0.5)),
    "big-sand-rock": ((0.92, 0.92, 1.19), (0.03, -0.09)),
}


def place(m, name):
    """Scales and moves the finished rock to its FIT, before shading (which reads heights)."""
    (sx, sy, sz), (dx, dy) = FIT[name]
    for v in m.bm.verts:
        v.co.x = v.co.x * sx + dx
        v.co.y = v.co.y * sy + dy
        v.co.z = v.co.z * sz if v.co.z > 0.0 else v.co.z


def shade_rock(m, top, dark=0.3):
    """Dark at the foot and in the cracks, light on top faces, like the sprites."""
    def fn(f, p, n):
        h = min(1.0, max(0.0, p.z / top))
        up = max(0.0, n.z)
        return dark + (1.0 - dark) * min(1.0, 0.15 + 0.45 * h + 0.5 * up)
    m.shade(fn)


def heap(m, count, spread, heights, radii, skirt, skirt_r, frag, top, name):
    """A heap of columns, tallest in the middle, in a skirt of fragments."""
    rng = m.rng
    golden = math.pi * (3.0 - math.sqrt(5.0))
    a0 = rng.uniform(0.0, math.tau)
    for i in range(count):
        f = math.sqrt((i + 0.5) / count)
        a = a0 + golden * i
        p = Vector((math.cos(a) * spread[0] * f, math.sin(a) * spread[1] * f, 0.0))
        h = heights[0] + (heights[1] - heights[0]) * (1.0 - f) * rng.uniform(0.75, 1.1)
        r = rng.uniform(*radii)
        out = p.normalized() if p.length > 1e-3 else Vector((1, 0, 0))
        column(m, p, r, h, ROCK, lean=(out.x * h * 0.12, out.y * h * 0.12), tint=(rng.uniform(0.85, 1.0),) * 3)
    # A low, broken foot under it all: the sprites' heaps stand on a solid apron of rubble.
    foot = m.blob((0.0, 0.0, 0.0), 1.0, ROCK, scale=(skirt_r[0] * 0.95, skirt_r[1] * 0.95, top * 0.3), jitter=0.2,
                  subdiv=2, flat_bottom=-0.05, tint=(0.8, 0.8, 0.8), vary=0.25)
    m.chop(foot, Vector((0.0, 0.0, 0.0)), [((0.0, 0.0, 1.0), 0.7)])
    for i in range(skirt):
        a = a0 + i / skirt * math.tau + rng.uniform(-0.2, 0.2)
        p = Vector((math.cos(a) * skirt_r[0], math.sin(a) * skirt_r[1], 0.0)) * rng.uniform(0.85, 1.05)
        fragment(m, p, rng.uniform(*frag), ROCK, scale=(1.2, 1.0, 0.7), tint=(rng.uniform(0.75, 0.95),) * 3)
    place(m, name)
    shade_rock(m, top * FIT[name][0][2])


def big_rock(m):
    """A 2x2 heap of blocky brown stone, about a tile high."""
    heap(m, 7, (0.55, 0.45), (0.45, 1.05), (0.32, 0.48), 9, (0.82, 0.72), (0.16, 0.26), 1.0, "big-rock")


def huge_rock(m):
    """A 3x2 outcrop of tall, column-like blocks, over one and a half tiles high."""
    heap(m, 12, (1.0, 0.7), (1.0, 1.55), (0.38, 0.55), 12, (1.35, 1.0), (0.18, 0.3), 1.8, "huge-rock")


def big_sand_rock(m):
    """A rounded, wind-worn sandstone lump, as in the sprite: its high, bulging mass at the back
    right, sloping down to a long low lobe at the front left; ochre on top, dark red-brown at the
    foot, with a few broken stones lying at the front."""
    rng = m.rng
    # (centre, radius, scale): the back-right mass, the front-left lobe, the front, the right side.
    parts = (((0.4, 0.3, 0.6), 0.75, (0.9, 0.95, 1.05)), ((-0.55, -0.05, 0.25), 0.55, (1.25, 0.9, 0.75)),
             ((0.1, -0.3, 0.2), 0.5, (1.3, 0.8, 0.65)), ((0.8, 0.0, 0.3), 0.42, (1.0, 1.0, 0.9)),
             ((-0.1, 0.25, 0.45), 0.5, (1.1, 1.0, 0.8)))
    for c, r, sc in parts:
        verts = m.blob(c, r, SAND_ROCK, scale=sc, jitter=0.3, subdiv=2, flat_bottom=-0.06, vary=0.2)
        m.chop(verts, Vector(c), [((rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2), 1.0), 0.8)])
    for x, y in ((-1.0, -0.15), (-0.35, -0.6), (0.45, -0.5)):
        fragment(m, (x, y, 0.0), rng.uniform(0.12, 0.18), SAND_ROCK, tint=(0.75, 0.6, 0.5))
    place(m, "big-sand-rock")
    sz = FIT["big-sand-rock"][0][2]

    def fn(f, p, n):
        # Dark reddish foot, ochre top, darker in the crevices.
        h = min(1.0, max(0.0, (p.z + 0.05) / (0.9 * sz)))
        foot = (0.48, 0.34, 0.28)
        k = 0.7 + 0.3 * max(0.0, n.z)
        return tuple((foot[i] + (1.0 - foot[i]) * h ** 0.8) * k for i in range(3))
    m.shade(fn)


# Nauvis ores, matched to their sprites. Factorio draws an ore tile from one of eight richness
# stages (rows of the sheet, chosen by the tile's amount), each a 2x2-tile picture centred on the
# tile: the richest a dense cluster of about sixteen small, angular, glossy nuggets about a tile
# and a half across, the poorest four or five scattered crumbs, over a sprinkle of reddish dust.
# Three of those stages are modelled (STAGES; the client picks one by the tile's amount,
# model_library.gd ORE_STAGES): "-rich", the plain name (middle) and "-sparse". Nuggets are kept
# small and low-poly: an ore field draws one per tile. The Space Age ores keep their first look.
PATCH = {"iron-ore", "copper-ore", "coal", "stone", "uranium-ore"}
# suffix: (nuggets, radius range, reach, dust flecks)
STAGES = {"-rich": (17, (0.085, 0.15), 0.7, 70), "": (11, (0.08, 0.14), 0.66, 55), "-sparse": (5, (0.065, 0.11), 0.6, 35)}


def ore(name, stage=""):
    chunk_hex, rough, metal, tints, dust_hex = ORES[name]
    chunk = material(name + "-chunk", chunk_hex, rough, metal)
    dust = material(name + "-dust", dust_hex, 1.0)
    patch = name in PATCH

    def build(m):
        rng = m.rng
        if patch:
            count, radii, reach, flecks = STAGES[stage]
        else:
            count, radii, reach, flecks = 12, None, 0.72, 40
        # Dust first: small flat flecks on the ground, denser in the middle.
        for _ in range(flecks):
            r = (reach + 0.05) * math.sqrt(rng.random())
            a = rng.uniform(0.0, math.tau)
            m.disc((math.cos(a) * r, math.sin(a) * r, 0.006), rng.uniform(0.025, 0.06), dust, sides=3, jitter=0.3,
                   tint=(rng.uniform(0.7, 1.0),) * 3)
        # Nuggets: in the sprites they lie in loose bunches of two to four, touching; the bunches
        # spread over the picture.
        placed = []
        tries = 0
        while len(placed) < count and tries < 1500:
            tries += 1
            n = len(placed)
            if patch:
                r = rng.uniform(*radii)
                if placed and rng.random() < 0.55:
                    q, s = rng.choice(placed)  # next to one already there
                    a = rng.uniform(0.0, math.tau)
                    p = q + Vector((math.cos(a), math.sin(a), 0.0)) * (s + r) * rng.uniform(0.9, 1.15)
                    if p.length > reach:
                        continue
                else:
                    d = reach * math.sqrt(rng.random())
                    a = rng.uniform(0.0, math.tau)
                    p = Vector((math.cos(a) * d, math.sin(a) * d, 0.0))
                gap = 0.85
            else:
                r = (0.24, 0.22, 0.2)[n] if n < 3 else rng.uniform(0.1, 0.16)
                lim = 0.4 if n < 3 else reach
                d = lim * math.sqrt(rng.random())
                a = rng.uniform(0.0, math.tau)
                p = Vector((math.cos(a) * d, math.sin(a) * d, 0.0))
                gap = 0.75
            if all((p - q).length > (r + s) * gap for q, s in placed):
                placed.append((p, r))
        for p, r in placed:
            if patch:  # the darker, dusty ground each nugget lies in
                m.disc((p.x + r * 0.2, p.y - r * 0.3, 0.008), r * 1.5, dust, sides=6, jitter=0.25,
                       tint=(rng.uniform(0.75, 0.9),) * 3)
            c = p + Vector((0, 0, r * (0.4 if patch else 0.25)))
            # Uranium grows as jagged, pointed crystals rather than rounded nuggets.
            shape = (1.0, 0.9, 1.3) if name == "uranium-ore" else (1.2, 0.95, 0.9 if patch else 0.7)
            verts = m.blob(c, r, chunk, scale=shape, jitter=0.45 if name == "uranium-ore" else 0.3,
                           subdiv=1 if patch else 2, flat_bottom=-0.03, tint=rng.choice(tints), vary=0.3)
            # Broken faces make the lumps angular, like the sprites' nuggets.
            m.chop(verts, c, [((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(0.2, 1.0)), rng.uniform(0.55, 0.8))
                              for _ in range(3)])

        def fn(f, p, n):
            if f.material_index == m.materials.index(dust):
                return 1.0
            return 0.4 + 0.6 * min(1.0, max(0.0, p.z / 0.16)) * (0.55 + 0.45 * max(0.0, n.z))
        m.shade(fn)

    return build


MODELS = {
    "big-rock": big_rock, "huge-rock": huge_rock, "big-sand-rock": big_sand_rock,
    **{name: ore(name) for name in ORES},
    **{name + stage: ore(name, stage) for name in sorted(PATCH) for stage in STAGES if stage},
}
