"""Nauvis trees, living and dead, modelled on Factorio's own tree sprites. Each function fills a
`geo.Model`.

Sizes come from the HR sprites (64 px per tile) seen from Factorio's camera, which looks north
and down at about 48 degrees, so a point `z` tiles up shows `z * 0.67` tiles up the sprite. That
makes Factorio's trees big: tree-01 is a 7-tile spruce, tree-09 a baobab five tiles across. Each
model follows the prototype's first variation ("a"), which is about as common as the others.

Leaf colours are the sprite's leaves multiplied by the mean of the prototype's `colors` list (the
game tints each tree with one of them at random). Materials hold the lit tone; face colours
darken the insides and undersides like the sprites' baked shading (see `shade_tree`). The trunk
sits on the origin; roots and anything hidden go a little below ground so nothing floats.

Trunks and their main limbs follow each trunk sprite (tree_trunks.py, measured by fit_trunks.py):
`sprite_trunk` puts every point where the sprite shows it, flares the foot into buttresses and
streaks the bark with grooves and ridges in the corner colours (`bark_profile`). The wood draws
from its own random stream (`wood`), so the crowns stay as they were fitted.
"""

import contextlib
import math
import random
import zlib

from mathutils import Vector

import tree_crowns
import tree_trunks
from geo import bend, branch_path, material, polar

# Bark, per tree (sRGB, lit tone): the light third of the trunk sprite's bark (tree_trunks.BARK);
# the grooves are darkened from it per vertex (bark_profile). tree-06 keeps its own.
BARK_01 = material("bark-01", tree_trunks.BARK["tree-01"][2], 0.95)
BARK_02 = material("bark-02", tree_trunks.BARK["tree-02"][2], 0.95)
BARK_03 = material("bark-03", tree_trunks.BARK["tree-03"][2], 0.95)
BARK_04 = material("bark-04", tree_trunks.BARK["tree-04"][2], 0.95)
BARK_05 = material("bark-05", tree_trunks.BARK["tree-05"][2], 0.95)
BARK_06 = material("bark-06", "#7a552f", 0.95)
BARK_07 = material("bark-07", tree_trunks.BARK["tree-07"][2], 0.95)
BARK_08 = material("bark-08", tree_trunks.BARK["tree-08"][2], 0.9)
BARK_09 = material("bark-09", tree_trunks.BARK["tree-09"][2], 0.95)

# Leaves, per tree (sRGB, lit tone: the sprite's light leaves times the mean tint).
LEAF_01 = material("leaf-01", "#68a446", 0.85)
LEAF_02 = material("leaf-02", "#8c9a36", 0.85)
LEAF_03 = material("leaf-03", "#9e8b33", 0.85)
LEAF_04 = material("leaf-04", "#5ea05e", 0.85)
LEAF_05 = material("leaf-05", "#89a332", 0.85)
LEAF_06 = material("leaf-06", "#8c9440", 0.85)
LEAF_07 = material("leaf-07", "#aa8e2a", 0.85)
LEAF_08 = material("leaf-08", "#7c9620", 0.85)
LEAF_09 = material("leaf-09", "#c4801a", 0.85)

# Dead and dry wood.
WOOD_HAIRY = material("wood-dead-hairy", "#9c7a5c", 0.95)
WOOD_GREY = material("wood-grey-trunk", "#9a8358", 0.95)
WOOD_DESERT = material("wood-desert", "#c09e70", 0.95)
WOOD_DRY_HAIRY = material("wood-dry-hairy", "#c9a07a", 0.95)
WOOD_DRY = material("wood-dry", "#7d603c", 0.95)

LEAVES = {LEAF_01, LEAF_02, LEAF_03, LEAF_04, LEAF_05, LEAF_06, LEAF_07, LEAF_08, LEAF_09}

# Leaf cards (geo.Model.card): the same lit tones, on squares the client cuts leaves out of.
CARDS = {n: material("leafcard-%s" % n, LEAF_HEX, 0.85) for n, LEAF_HEX in (
    ("01", "#68a446"), ("02", "#8c9a36"), ("03", "#9e8b33"), ("04", "#5ea05e"), ("05", "#89a332"),
    ("07", "#aa8e2a"), ("08", "#7c9620"), ("09", "#c4801a"))}
# The shadow inside a crown, seen through the gaps between the cards: the sprite's mid leaf tone.
SHADOWS = {n: material("leaf-shadow-%s" % n, tree_crowns.SHADES["tree-" + n][1], 1.0) for n in CARDS}

# Face-colour tints that mix a little hue into one leaf material (multiplied, so <= 1).
WARM = (1.0, 0.93, 0.78)
COOL = (0.86, 1.0, 0.9)
PLAIN = (1.0, 1.0, 1.0)


# --- shared parts -----------------------------------------------------------------------------

def trunk(m, points, radii, bark, segments=8, wobble=0.0, profile=None):
    """A tapering trunk along `points` (the first goes a little under ground)."""
    pts = bend(points, m.rng, wobble) if wobble else [Vector(p) for p in points]
    m.tube(pts, radii, bark, segments=segments, profile=profile)
    return pts


def roots(m, r0, bark, count=5, reach=0.3, lift=0.5, thick=0.6, a0=None, centre=(0.0, 0.0), curl=0.0, jitter=0.25):
    """Root flare: buttress roots, thick at the trunk, tapering out into the ground. `curl`
    bends them sideways, for the snaking roots of dead trees."""
    a0 = m.rng.uniform(0.0, math.tau) if a0 is None else a0
    c = Vector((centre[0], centre[1], 0.0))
    for i in range(count):
        a = a0 + i / count * math.tau + m.rng.uniform(-jitter, jitter)
        out = Vector((math.cos(a), math.sin(a), 0.0))
        side = Vector((-out.y, out.x, 0.0)) * curl * m.rng.uniform(-1.0, 1.0)
        far = r0 + reach * m.rng.uniform(0.7, 1.3)
        t = r0 * thick
        # Down the trunk's side, then along the ground, ending under it with a rounded tip.
        pts = [c + out * r0 * 0.25 + Vector((0, 0, lift)), c + out * (r0 * 0.8) + Vector((0, 0, lift * 0.4)),
               c + out * (r0 + (far - r0) * 0.45) + side * 0.4 + Vector((0, 0, t * 0.4)),
               c + out * far + side + Vector((0, 0, t * 0.05)),
               c + out * (far + t * 0.4) + side * 1.1 + Vector((0, 0, -0.12))]
        m.tube(pts, [t, t * 0.85, t * 0.62, t * 0.4, 0.0], bark, segments=6, smooth=True)


@contextlib.contextmanager
def wood(m):
    """Builds the wood with its own random stream, so the crown (from the model's own stream)
    stays the same whatever the trunk and branches draw."""
    if not hasattr(m, "wood_rng"):
        m.wood_rng = random.Random(zlib.crc32((SEED_AS.get(m.name, m.name) + "/wood").encode()))
    main, m.rng = m.rng, m.wood_rng
    try:
        yield
    finally:
        m.rng = main


def skip(m, n):
    """Takes `n` draws from the model's stream: what the trunks before sprite_trunk took there, so
    the crowns built after them stay the ones that were fitted and reviewed."""
    for _ in range(n):
        m.rng.random()


def limb_draws(lumps, smallest, per):
    """The draws the old crown limbs took: `per` for each lump of at least `smallest`."""
    return per * sum(1 for _, r in lumps[1:] if min(r) >= smallest)


def groove_depth(name):
    """How dark the sprite's bark grooves are against its lit ridges: its dark and mid thirds'
    luminance over the light third's (tree_trunks.BARK), linear, as the corner colours are."""
    def lum(h):
        h = h.lstrip("#")
        lin = [((int(h[i:i + 2], 16) / 255.0 + 0.055) / 1.055) ** 2.4 for i in (0, 2, 4)]
        return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]
    dark, mid, light = (lum(h) for h in tree_trunks.BARK[name])
    return min(0.6, max(0.15, (dark + mid) / 2 / light))


def bark_profile(m, segments, groove=0.55, flute=0.0, lobes=0, buttress=(), lobe_depth=0.0, a0=None):
    """A tube profile (geo.Model.tube) for bark: ridges and grooves running along the wood, as
    the sprites' bark is streaked: every other vertex round the tube a groove (darker, and pressed
    in by `flute` of the radius), each groove its own depth and a little uneven along its length.
    `lobes` buttresses round the foot, the first at angle `a0`, stand out by `buttress[i]` of the
    radius at ring i (0 past the list), the roots' flare; `lobe_depth` keeps that many lobes all
    the way up (tree-09's trunks grown together). No more triangles than a plain tube. Its
    randomness comes from the wood's own stream (`wood`)."""
    with wood(m):
        rng = m.rng
    depth = [rng.uniform(0.6, 1.2) for _ in range(segments)]
    if segments % 2:
        kind = [rng.random() < 0.5 for _ in range(segments)]
    else:
        kind = [k % 2 == 1 for k in range(segments)]
    a0 = rng.uniform(0.0, math.tau) if a0 is None else a0
    jitter = {}

    def fn(i, k, a):
        g = kind[k]
        j = jitter.setdefault((i, k), rng.uniform(-0.08, 0.08))
        c = (1.0 - (1.0 - groove) * depth[k]) if g else 1.0
        c = min(1.0, max(0.2, c + j))
        r = 1.0 - (flute * depth[k] if g else 0.0)
        if lobes:
            wave = max(0.0, math.cos(lobes * (a - a0))) ** 1.5
            b = buttress[i] if i < len(buttress) else 0.0
            r += (b + lobe_depth) * wave - lobe_depth * 0.5
            # Between the buttresses the bark is in shadow.
            c *= 0.8 + 0.2 * wave if (b or lobe_depth) else 1.0
        return r, c
    return fn


def _resample(strand, step, fine=0.0):
    """Points along a measured strand (x, up, r) about `step` tiles apart (`fine` apart over the
    first 0.5 tiles, where the foot's flare changes fast), keeping both ends."""
    out = [strand[0]]
    run = 0.0
    for a, b in zip(strand, strand[1:]):
        run += math.hypot(b[0] - a[0], b[1] - a[1])
        along = math.hypot(b[0] - strand[0][0], b[1] - strand[0][1])
        if run >= (fine if (fine and along < 0.5) else step) * 0.999:
            out.append(b)
            run = 0.0
    if out[-1] is not strand[-1]:
        if run < step * 0.4 and len(out) > 1:
            out[-1] = strand[-1]
        else:
            out.append(strand[-1])
    return out


def sprite_trunk(m, *args, **kw):
    with wood(m):
        return _sprite_trunk(m, *args, **kw)


def _sprite_trunk(m, name, bark, segments=12, flare=1.5, lobes=4, flute=0.07, crook=0.05, step=0.55, depth=0.4,
                  lobe_depth=0.0, limb_segments=6, roots_reach=0.0):
    """The trunk and main limbs as the trunk sprite draws them (tree_trunks.STRANDS, measured by
    fit_trunks.py): each point where the sprite shows it from Factorio's camera (on_sprite), so the
    trunk's lean, crook and taper are the sprite's, with a little crook north and south too. The
    foot flares out to `flare` times the lowest measured radius in `lobes` buttresses, the bark is
    ridged and grooved (bark_profile, its grooves as dark as the sprite's), and every strand ends in
    a point. Limbs swing north or south as they reach out (`depth` of their length), so from the
    side they spread as from the front, without moving on the sprite. Returns the 3D points of all
    strands, the trunk's first, for crown limbs and twigs to grow from."""
    S = on_sprite
    groove = groove_depth(name)
    strands = tree_trunks.STRANDS[name]
    main = _resample(strands[0], step, fine=0.25)
    ph = m.rng.uniform(0.0, math.tau)
    ys = [crook * math.sin(ph + 1.7 * up) * min(1.0, up) for _, up, _ in main]
    r0 = main[0][2]
    x0, y0 = main[0][0], ys[0]
    pts = [Vector((x0, y0, -0.12)), S(x0, 0.12, y0)]
    radii = [r0 * flare, r0 * (1.0 + (flare - 1.0) * 0.5)]
    # Buttresses: big at the ground, gone a metre up.
    butt = [(flare - 1.0) * 0.6, (flare - 1.0) * 0.6]
    for (x, up, r), y in zip(main, ys):
        p = S(x, up, y)
        pts.append(p)
        radii.append(min(r, radii[-1] * 1.04) if len(radii) > 2 else r)
        butt.append(max(0.0, 0.25 * (flare - 1.0) * (1.0 - p.z / 0.9)))
    # The tip: a point just past the last measured place (the skeleton stops short of the tip,
    # but further and it pokes out of the crowns).
    d = (pts[-1] - pts[-2]).normalized()
    pts.append(pts[-1] + d * radii[-1] * 0.6)
    radii.append(0.0)
    a0 = m.rng.uniform(0.0, math.tau)
    m.tube(pts, radii, bark, segments=segments,
           profile=bark_profile(m, segments, groove=groove, flute=flute, lobes=lobes, buttress=butt,
                                lobe_depth=lobe_depth, a0=a0))
    if roots_reach:
        # A root out of each buttress, along the ground.
        roots(m, r0 * flare * 0.75, bark, count=lobes, reach=roots_reach, lift=0.3, thick=0.32, a0=a0,
              centre=(x0, y0), jitter=0.08)
    out = [pts]
    for k, strand in enumerate(strands[1:]):
        s = _resample(strand, step * 0.75)
        # Where it leaves its parent: the skeleton's junction reads wide; a limb is thinner.
        parent = min((q for o in out for q in o), key=lambda q: (q.x - s[0][0]) ** 2 + (q.z * 0.669 - s[0][1]) ** 2)
        side = (1.0 if k % 2 == 0 else -1.0) * m.rng.uniform(0.7, 1.0)
        run = 0.0
        lp, lr = [], []
        for j, (x, up, r) in enumerate(s):
            if j:
                run += math.hypot(x - s[j - 1][0], up - s[j - 1][1])
            y = parent.y + side * depth * run
            lp.append(S(x, up, y))
            cap = lr[-1] if lr else 0.75 * max(0.06, _radius_near(out, radii, parent))
            lr.append(min(r, cap))
        # Start inside the parent, so no seam shows where the limb leaves it.
        lp.insert(0, parent.lerp(lp[0], 0.3))
        lr.insert(0, lr[0])
        d = (lp[-1] - lp[-2]).normalized()
        lp.append(lp[-1] + d * lr[-1] * 0.8)
        lr.append(0.0)
        m.tube(lp, lr, bark, segments=limb_segments, profile=bark_profile(m, limb_segments, groove=groove,
                                                                           flute=flute * 0.5))
        out.append(lp)
    return out


def _radius_near(strands, trunk_radii, p):
    """The trunk's radius at point p if it is on the trunk, else a limb's guess."""
    pts = strands[0]
    i = min(range(len(pts)), key=lambda k: (pts[k] - p).length)
    return trunk_radii[i] if (pts[i] - p).length < 1e-6 else 0.12


def twigs_on(m, strands, wood_, count=14, lo=1.2, length=(0.35, 0.7), radius=0.03):
    """Thin twigs off the trunk and limbs above `lo` tiles: what the trunk sprites show sticking out
    in every direction, and what shows through the gaps of a crown. Nine triangles each."""
    cands = [(p, q) for s in strands for p, q in zip(s, s[1:]) if p.z > lo and (q - p).length > 1e-4]
    if not cands:
        return
    with wood(m):
        _twigs(m, cands, wood_, count, length, radius)


def _twigs(m, cands, wood, count, length, radius):
    for _ in range(count):
        p, q = m.rng.choice(cands)
        at = p.lerp(q, m.rng.uniform(0.0, 1.0))
        axis = (q - p).normalized()
        a = m.rng.uniform(0.0, math.tau)
        out = Vector((math.cos(a), math.sin(a), m.rng.uniform(-0.1, 0.5)))
        d = (out - axis * out.dot(axis) * 0.6 + axis * 0.35).normalized()
        n = m.rng.uniform(*length)
        mid = at + d * n * 0.5 + Vector((m.rng.uniform(-0.05, 0.05), m.rng.uniform(-0.05, 0.05), 0.04))
        m.tube([at, mid, at + d * n], [radius, radius * 0.6, 0.0], wood, segments=3)


def leaf_tint(m, tints):
    t = m.rng.choice(tints)
    k = m.rng.uniform(0.82, 1.0)
    return (t[0] * k, t[1] * k, t[2] * k)


def clump(m, center, radius, leaf, tints=(PLAIN,), scale=(1.0, 1.0, 0.85), jitter=0.3, subdiv=2, vary=0.5):
    """One lump of foliage: a jagged ball, each facet a slightly different shade so it reads
    as a mass of leaves."""
    return m.blob(center, radius, leaf, scale=scale, jitter=jitter, subdiv=subdiv, tint=leaf_tint(m, tints),
                  vary=vary, smooth=True)


def crown(m, center, radii, count, size, leaf, tints=(PLAIN,), core=0.8, below=1.0, squash=0.85, jitter=0.3,
          depth=(0.8, 1.0)):
    """A canopy: clumps spread over an ellipsoid (centre, radii), plus a core blob filling the
    middle. `below` < 1 leaves the underside open (umbrella crowns, trunks showing)."""
    c = Vector(center)
    rx, ry, rz = radii
    if core:
        m.blob(c, 1.0, leaf, scale=(rx * core, ry * core, rz * core), jitter=0.15, subdiv=2,
               tint=leaf_tint(m, tints), vary=0.3, smooth=True)
    golden = math.pi * (3.0 - math.sqrt(5.0))
    a0 = m.rng.uniform(0.0, math.tau)
    placed = []
    for i in range(count):
        # Fibonacci sphere: an even spread, nudged at random.
        zf = 1.0 - (i + 0.5) / count * (1.0 + below)
        r = math.sqrt(max(0.0, 1.0 - zf * zf))
        a = a0 + golden * i + m.rng.uniform(-0.3, 0.3)
        d = Vector((math.cos(a) * r, math.sin(a) * r, zf))
        p = c + Vector((d.x * rx, d.y * ry, d.z * rz)) * m.rng.uniform(*depth)
        clump(m, p, size * m.rng.uniform(0.8, 1.2), leaf, tints, scale=(1.0, 1.0, squash), jitter=jitter)
        placed.append(p)
    return placed


def shade_tree(m, center, radii, ground=0.0, leaf_dark=0.5, bark_dark=0.55, bark_top=None):
    """Bakes the sprites' shading into face colours: foliage darkens towards the inside and
    the underside of the crown, bark darkens near the ground and under the leaves."""
    c = Vector(center)
    rx, ry, rz = radii
    leaf_idx = {m.materials.index(x) for x in m.materials if x in LEAVES}
    # Leaf cards and the shadow cores are shaded as they are made (leafy_crown).
    own_idx = {m.materials.index(x) for x in m.materials if x.name.startswith(("leafcard", "leaf-shadow"))}
    top = bark_top if bark_top is not None else c.z

    def fn(f, p, n):
        if f.material_index in own_idx:
            return 1.0
        if f.material_index in leaf_idx:
            d = p - c
            q = math.sqrt((d.x / rx) ** 2 + (d.y / ry) ** 2 + (d.z / rz) ** 2)
            outer = min(1.0, max(0.0, (q - 0.45) / 0.55))
            up = 0.5 + 0.5 * n.z
            height = min(1.0, max(0.0, 0.5 + 0.5 * d.z / rz))
            return leaf_dark + (1.0 - leaf_dark) * (0.55 * outer + 0.25 * up + 0.2 * height)
        h = min(1.0, max(0.0, (p.z - ground) / max(top - ground, 0.1)))
        under = 1.0 - 0.35 * max(0.0, h - 0.6) / 0.4
        side = 0.85 + 0.15 * max(0.0, n.z)
        return (bark_dark + (1.0 - bark_dark) * min(1.0, 0.35 + h * 1.6)) * under * side
    m.shade(fn)


def outline_crown(m, bands, leaf, tints=(PLAIN,), size=0.5, depth=0.75, step=0.5):
    """A canopy filled out to the sprite's outline, so no ground or trunk shows through where
    the sprite has leaves (the client projects the sprite onto the model). `bands`: (up, x0, x1)
    for each `step`-tile band of the sprite, measured up from the entity's position, across from
    x0 to x1 tiles. Each band gets a core blob, a clump at each end and, if wide, one in front;
    each placed at the height that shows on its band from Factorio's camera (z * 0.669 + y * 0.743
    up the sprite). Returns the crown's centre and radii, for shade_tree."""
    def z_at(up, y):
        return (up - y * 0.743) / 0.669
    lo = min(b[0] for b in bands)
    hi = max(b[0] for b in bands) + step
    for k, (up, x0, x1) in enumerate(bands):
        # Kept a little inside the outline: the sprite's leaves are ragged at the edge.
        u = up + step / 2 - (size * 0.35 if k == len(bands) - 1 else 0.0) + (size * 0.2 if k == 0 else 0.0)
        half = (x1 - x0) / 2
        cx = (x0 + x1) / 2
        # Thinner front to back at the top and bottom: from Factorio's camera the crown's far
        # side shows higher and its near side lower than the band.
        n = len(bands)
        d = half * depth * min(1.0, (0.25, 0.55)[n - 1 - k] if n - 1 - k < 2 else 1.0, (0.4, 0.8)[k] if k < 2 else 1.0)
        m.blob((cx, 0.0, z_at(u, 0.0)), 1.0, leaf, scale=(max(half - size * 0.8, 0.2), max(d * 0.8, 0.15), 0.4),
               jitter=0.15, subdiv=2, tint=leaf_tint(m, tints), vary=0.3, smooth=True, tilt=0.05)
        for x in (x0 + size * 1.05, x1 - size * 1.05):
            clump(m, (x, 0.0, z_at(u, 0.0)), size * m.rng.uniform(0.85, 1.0), leaf, tints, scale=(1.0, 1.0, 0.8),
                  jitter=0.25)
        if half > 2.0:
            y = -d * 0.6
            clump(m, (cx + m.rng.uniform(-0.3, 0.3), y, z_at(u, y)), size, leaf, tints, scale=(1.0, 0.8, 0.8))
    xs = [b[1] for b in bands] + [b[2] for b in bands]
    centre = Vector(((min(xs) + max(xs)) / 2, 0.0, z_at((lo + hi) / 2, 0.0)))
    return centre, ((max(xs) - min(xs)) / 2, (max(xs) - min(xs)) / 2 * depth, (hi - lo) / 2 / 0.669)


def crown_lumps(m, name, inset=0.95):
    """The crown's lumps in 3D, from its sprite's disks (tree_crowns.DISKS). Factorio's camera is an
    orthographic view 48 degrees down, so a sphere draws as a disk of its own radius: each disk
    becomes a sphere where the sprite shows it, a little north or south of the trunk. Under them a
    round body fills the crown out in depth (the client turns trees at random, so it has to look
    as full from the side as from the front): as wide north-south as east-west, and as tall as
    leaves the sprite's crown its height once its depth shows. Returns [(centre, radii)], the body
    first."""
    disks = tree_crowns.DISKS[name]
    lo = min(x - r for x, _, r in disks)
    hi = max(x + r for x, _, r in disks)
    ulo = min(u - r for _, u, r in disks)
    uhi = max(u + r for _, u, r in disks)
    big = (hi - lo) / 2 * inset
    seen = (uhi - ulo) / 2 * inset
    tall = math.sqrt(max(0.35 ** 2, seen ** 2 - (big * 0.743) ** 2)) / 0.669
    out = [(Vector(((lo + hi) / 2, 0.0, (ulo + uhi) / 2 / 0.669)), Vector((big, big, tall)))]
    cx, cu = (lo + hi) / 2, (ulo + uhi) / 2
    for x, up, r in disks:
        # Lumps out at the crown's edge stay on the trunk's line, or they'd stand off it when seen
        # from the side.
        q = math.hypot((x - cx) / max(big, 0.1), (up - cu) / max(seen, 0.1))
        y = m.rng.uniform(-0.3, 0.3) * big * max(0.0, 1.0 - q)
        out.append((Vector((x, y, (up - y * 0.743) / 0.669)), Vector((r, r, r))))
    return out


def _inside(p, c, radii, scale):
    q = p - c
    return (q.x / radii.x) ** 2 + (q.y / radii.y) ** 2 + (q.z / radii.z) ** 2 < scale * scale


def leafy_crown(m, lumps, card_mat, core_mat, tints=(PLAIN,), cards=700, size=0.55, dark=0.18, core=0.62,
                spread=0.32):
    """A crown of leaf cards over dark cores, Factorio's look: ragged, see-through edges of small
    leaves, lit on top and outside, deep shadow inside where the branches show.

    Each lump (centre, radii) gets a solid core (`core` of its size: the shadow seen through the
    gaps) and cards spread through its outer shell, as many as its surface needs, `cards` in all.
    Cards inside another lump's core never show and are skipped. Each card faces out of its lump,
    tilted at random, and carries the crown's outward normal (geo.Model.card) for its light; its
    shade darkens towards the crown's middle and underside like the sprites' painted shading
    (`dark`: the deepest)."""
    lo = Vector([min(c[i] - r[i] for c, r in lumps) for i in range(3)])
    hi = Vector([max(c[i] + r[i] for c, r in lumps) for i in range(3)])
    mid = (lo + hi) / 2
    ext = Vector([max(0.3, (hi[i] - lo[i]) / 2) for i in range(3)])
    for c, r in lumps:
        m.blob(c, core, core_mat, scale=(r.x, r.y, r.z), jitter=0.22, subdiv=1, vary=0.25, smooth=True, tilt=0.2)

    def surface(r):
        return r.x * r.y + r.y * r.z + r.x * r.z
    area = sum(surface(r) for _, r in lumps)
    made = 0
    for c, r in lumps:
        n = max(8, int(round(cards * surface(r) / area)))
        # The sprites' leaves grow in bunches with dark gaps between them: the cards gather round
        # a few bunches per lump (more on the top than underneath).
        bunches = [Vector((m.rng.gauss(0, 1), m.rng.gauss(0, 1), m.rng.gauss(0, 1) + 0.45)).normalized()
                   for _ in range(max(3, int(round(5.0 * surface(r) / 1.0))))]
        for _ in range(n * 3):
            if n <= 0:
                break
            b = m.rng.choice(bunches)
            d = (b + Vector((m.rng.gauss(0, 1), m.rng.gauss(0, 1), m.rng.gauss(0, 1))) * spread).normalized()
            f = m.rng.uniform(0.5, 1.06)
            p = c + Vector((d.x * r.x, d.y * r.y, d.z * r.z)) * f
            if any(_inside(p, c2, r2, core * 0.95) for c2, r2 in lumps if c2 is not c):
                continue
            n -= 1
            q = p - mid
            whole = Vector((q.x / ext.x, q.y / ext.y, q.z / ext.z))
            outer = min(1.0, whole.length)
            normal = (d * 0.5 + whole.normalized() * 0.5 + Vector((0, 0, 0.25))).normalized()
            facing = (d + Vector((m.rng.uniform(-0.6, 0.6), m.rng.uniform(-0.6, 0.6), m.rng.uniform(-0.4, 0.6)))).normalized()
            height = min(1.0, max(0.0, 0.5 + 0.5 * whole.z))
            # Deep inside a lump and low in the crown: in shadow; out on top: lit.
            lit = min(1.0, 0.1 + 0.35 * outer + 0.35 * height + 0.2 * max(0.0, d.z))
            lit *= 0.3 + 0.7 * min(1.0, max(0.0, (f - 0.5) / 0.45))
            k = dark + (1.0 - dark) * lit ** 1.3
            t = leaf_tint(m, tints)
            s = size * m.rng.uniform(0.8, 1.15) * min(1.0, 0.55 + 0.6 * min(r))
            m.card(p, s, facing, card_mat, tint=(t[0] * k, t[1] * k, t[2] * k), normal=normal)
            made += 1
    return made


def crown_limbs(m, fork, lumps, bark, r0=0.12, smallest=0.4, lo=1.0):
    """Branches from the trunk's fork into the bigger lumps, ending inside their cores: what shows
    through the gaps between the leaves. `fork` is one point, or the strands sprite_trunk made:
    then each branch leaves the nearest of their points above `lo`."""
    if isinstance(fork, Vector):
        cands = [fork]
    else:
        cands = [p for s in fork for p in s[:-1] if p.z > lo] or [fork[0][-2]]
    with wood(m):
        _crown_limbs(m, cands, lumps, bark, r0, smallest)


def _crown_limbs(m, cands, lumps, bark, r0, smallest):
    for c, r in lumps[1:]:
        if min(r) < smallest:
            continue
        start = min(cands, key=lambda p: (p - c).length)
        end = c + (start - c).normalized() * min(r) * 0.3
        mid = start.lerp(end, 0.5) + Vector((0, 0, 0.25 * (end - start).length))
        tip = end + (c - start).normalized() * min(r) * 0.4
        m.tube(bend([start, mid, end, tip], m.rng, 0.08), [r0, r0 * 0.7, r0 * 0.35, 0.0], bark, segments=5,
               profile=bark_profile(m, 5, groove=0.4))


def tier(m, z, radius, droop, leaf, points=9, tint=PLAIN, inner=0.62, thick=0.35):
    """One whorl of a conifer: a star of drooping branch tips round the stem, as a closed
    jagged umbrella (top and underside)."""
    rng = m.rng
    bm = m.bm
    a0 = rng.uniform(0.0, math.tau)
    top = bm.verts.new((rng.uniform(-0.04, 0.04), rng.uniform(-0.04, 0.04), z + radius * thick))
    bottom = bm.verts.new((0.0, 0.0, z - droop * 0.35))
    rim = []
    for k in range(points * 2):
        a = a0 + k / (points * 2) * math.tau + rng.uniform(-0.08, 0.08)
        if k % 2 == 0:
            r = radius * rng.uniform(0.85, 1.12)
            h = z - droop * rng.uniform(0.85, 1.15)
        else:
            r = radius * inner * rng.uniform(0.85, 1.1)
            h = z - droop * 0.35 + rng.uniform(-0.05, 0.08)
        rim.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, h)))
    n = len(rim)
    for k in range(n):
        bm.faces.new((top, rim[k], rim[(k + 1) % n]))
        bm.faces.new((bottom, rim[(k + 1) % n], rim[k]))
    m._tag([top, bottom] + rim, leaf, False, leaf_tint(m, (tint,)), 0.4)


# --- living trees -----------------------------------------------------------------------------

def tree_01(m):
    """Spruce: a narrow seven-tile column of drooping whorls, tapering only near the top, over
    a short dark trunk with a flared base."""
    strands = sprite_trunk(m, "tree-01", BARK_01, segments=10, flare=1.3, lobes=5, crook=0.03, step=0.7)
    skip(m, 22)  # the draws the old trunk took: the crown stays as it was
    twigs_on(m, strands, BARK_01, count=8, lo=1.4, length=(0.3, 0.6), radius=0.025)
    # Whorls of drooping boughs: each a dark solid umbrella (the shadow under the needles) with
    # sprays of needles (leaf cards) hanging off its rim and lying over its top.
    whorls = 14
    for i in range(whorls):
        f = i / (whorls - 1)
        z = 1.95 + f * 4.4
        r = 0.22 + 1.2 * (1.0 - f) ** 0.6
        droop = 0.4 + 0.3 * (1.0 - f)
        tier(m, z, r * 0.8, droop=droop * 0.8, leaf=SHADOWS["01"], points=8 if r > 0.6 else 6, inner=0.74, thick=0.3)
        a0 = m.rng.uniform(0.0, math.tau)
        n = 4 + int(14 * r)
        for k in range(n):
            a = a0 + k / n * math.tau + m.rng.uniform(-0.2, 0.2)
            out = Vector((math.cos(a), math.sin(a), 0.0))
            reach = r * m.rng.uniform(0.55, 1.05)
            p = out * reach + Vector((0, 0, z - droop * (0.25 + 0.6 * reach / r)))
            facing = (out * 0.6 + Vector((0, 0, 1.0)) + Vector((m.rng.uniform(-0.3, 0.3), m.rng.uniform(-0.3, 0.3), 0))).normalized()
            lit = min(1.0, 0.3 + 0.5 * reach / r + 0.3 * f)
            k_ = 0.3 + 0.7 * lit ** 1.3
            t = leaf_tint(m, (PLAIN, COOL, PLAIN))
            m.card(p, (0.3 + 0.35 * min(1.0, r)) * m.rng.uniform(0.85, 1.15), facing, CARDS["01"],
                   tint=(t[0] * k_, t[1] * k_, t[2] * k_), normal=(out + Vector((0, 0, 0.6))).normalized(),
                   spin=a + math.pi / 2)
    m.cone((0.0, 0.0, 6.2), 0.7, 0.14, LEAF_01, segments=5, tint=PLAIN)
    shade_tree(m, (0, 0, 3.8), (1.4, 1.4, 2.6), leaf_dark=0.42, bark_dark=0.5, bark_top=1.9)


def tree_02(m):
    """Columnar bush-tree: a tall lumpy pillar of yellow-olive foliage from just above the
    ground, on a short flared trunk."""
    strands = sprite_trunk(m, "tree-02", BARK_02, segments=10, flare=1.3, lobes=5, step=0.6)
    skip(m, 22)  # the draws the old trunk took: the crown stays as it was
    lumps = crown_lumps(m, "tree-02")
    crown_limbs(m, strands, lumps, BARK_02, r0=0.09)
    twigs_on(m, strands, BARK_02, count=12, lo=1.8)
    skip(m, limb_draws(lumps, 0.4, 3))
    leafy_crown(m, lumps, CARDS["02"], SHADOWS["02"], (PLAIN, WARM, PLAIN, (0.9, 1.0, 0.85)))
    shade_tree(m, (0, 0, 3.0), (1.4, 1.4, 2.5), leaf_dark=0.4, bark_top=1.2)


def tree_03(m):
    """Old gnarled tree: a thick orange-brown trunk that forks into heavy crooked limbs under
    a broad, open crown of olive-brown leaves."""
    strands = sprite_trunk(m, "tree-03", BARK_03, flare=1.45, lobes=4, flute=0.09, roots_reach=0.18)
    skip(m, 27)  # the draws the old trunk took: the crown stays as it was
    # An open crown: crooked limbs out to every lump, fewer cards, so they show through.
    lumps = crown_lumps(m, "tree-03")
    crown_limbs(m, strands, lumps, BARK_03, r0=0.12, smallest=0.34, lo=1.3)
    twigs_on(m, strands, BARK_03, count=16, lo=1.3)
    skip(m, limb_draws(lumps, 0.34, 5))
    leafy_crown(m, lumps, CARDS["03"], SHADOWS["03"], (PLAIN, WARM, (0.9, 1.0, 0.82)), cards=560, core=0.5)
    shade_tree(m, (0, 0, 4.0), (2.0, 2.0, 1.6), leaf_dark=0.4, bark_top=3.2)


def tree_04(m):
    """Tall tree with a thick, light trunk running right up into a crown of blue-green
    leaves."""
    strands = sprite_trunk(m, "tree-04", BARK_04, flare=1.4, lobes=4, roots_reach=0.15)
    skip(m, 29)  # the draws the old trunk took: the crown stays as it was
    lumps = crown_lumps(m, "tree-04")
    crown_limbs(m, strands, lumps, BARK_04, r0=0.1, smallest=0.34, lo=1.8)
    twigs_on(m, strands, BARK_04, count=12, lo=1.6)
    skip(m, limb_draws(lumps, 0.34, 3))
    leafy_crown(m, lumps, CARDS["04"], SHADOWS["04"], (PLAIN, COOL, PLAIN), cards=600, core=0.55)
    shade_tree(m, (0, 0, 3.6), (1.5, 1.5, 1.8), leaf_dark=0.4, bark_top=4.5)


def tree_05(m):
    """Round, bright yellow-green crown on a short trunk with spreading roots."""
    strands = sprite_trunk(m, "tree-05", BARK_05, segments=10, flare=1.35, lobes=5, step=0.45, roots_reach=0.12)
    skip(m, 26)  # the draws the old trunk took: the crown stays as it was
    lumps = crown_lumps(m, "tree-05")
    crown_limbs(m, strands, lumps, BARK_05, lo=1.3)
    twigs_on(m, strands, BARK_05, count=12, lo=1.4)
    skip(m, limb_draws(lumps, 0.4, 3))
    leafy_crown(m, lumps, CARDS["05"], SHADOWS["05"], (PLAIN, WARM, PLAIN))
    shade_tree(m, (0, 0, 3.0), (1.6, 1.6, 1.6), leaf_dark=0.4, bark_top=2.0)


def tree_06(m):
    """Scraggly swamp tree, traced off the sprite (variation a) like the dead trees: a gnarled
    trunk leaning up and to the right from a tangle of exposed roots, a long limb reaching up to
    the right, shorter crooked ones to the left, and thin strands of olive leaves hanging from
    all of them like a willow's. Points are where each part shows on the sprite (on_sprite)."""
    S = on_sprite
    # The trunk: (across, up the sprite, radius), twisted from three strands as drawn.
    spine = [(-0.04, -0.1, 0.27), (-0.03, 0.4, 0.22), (0.02, 1.0, 0.18), (0.12, 1.5, 0.15), (0.22, 2.0, 0.1),
             (0.32, 2.5, 0.07), (0.4, 2.9, 0.04), (0.45, 3.05, 0.0)]
    for k in range(3):
        ph = k * math.tau / 3
        pts = [S(x + 0.35 * r * math.cos(ph + up * 2.2), up, 0.35 * r * math.sin(ph + up * 2.2)) for x, up, r in spine]
        pts[0].z = -0.1
        m.tube(pts, [r * 0.72 for _, _, r in spine], BARK_06, segments=6, profile=bark_profile(m, 6, 0.55))
    # Limbs: (points on the sprite, radius at the start, how far north of the trunk's plane).
    limbs = [
        ([(0.12, 1.45), (0.4, 1.65), (0.7, 1.85), (1.0, 2.05), (1.2, 2.2)], 0.06, -0.1),   # long, up and right
        ([(0.1, 1.35), (0.4, 1.45), (0.65, 1.5), (0.8, 1.45)], 0.04, 0.25),                 # low right
        ([(0.2, 1.7), (0.45, 1.95), (0.6, 2.1)], 0.035, -0.3),
        ([(0.05, 1.55), (-0.2, 1.65), (-0.45, 1.65), (-0.55, 1.5)], 0.04, 0.2),              # left
        ([(-0.02, 1.0), (-0.3, 0.95), (-0.5, 0.85), (-0.55, 0.65)], 0.035, -0.15),          # low left
        ([(0.15, 1.95), (-0.1, 2.1), (-0.25, 2.05)], 0.03, 0.1),
        ([(0.35, 2.6), (0.45, 2.85), (0.6, 2.95), (0.7, 2.8)], 0.03, 0.0),                  # top
        ([(0.3, 2.4), (0.22, 2.7), (0.18, 3.0)], 0.025, 0.15),
        ([(-0.03, 1.25), (-0.35, 1.38), (-0.62, 1.25)], 0.03, 0.05),
        ([(0.05, 0.8), (0.3, 0.85), (0.5, 0.75)], 0.03, -0.2),
    ]
    for pts, r, y in limbs:
        n = len(pts)
        m.tube([S(x, u, y) for x, u in pts], [r * (1.0 - 0.75 * i / (n - 1)) for i in range(n)], BARK_06, segments=4, profile=bark_profile(m, 4, 0.55))
    # Hanging strands of leaves, as thin as the sprite's: every few hand-widths along the outer
    # part of each limb, one arches out a little and hangs straight down.
    tints = (PLAIN, WARM, COOL)
    for pts, r, y in limbs:
        for (x0, u0), (x1, u1) in zip(pts, pts[1:]):
            seg = math.hypot(x1 - x0, u1 - u0)
            for k in range(max(1, int(seg / 0.09))):
                f = (k + m.rng.uniform(0.2, 0.8)) / max(1, int(seg / 0.09))
                x, u = x0 + (x1 - x0) * f, u0 + (u1 - u0) * f
                if u < 0.7 or abs(x) < 0.15:
                    continue
                side = 1.0 if x1 >= x0 else -1.0
                hang = min(m.rng.uniform(0.4, 0.7), u - 0.35)
                yy = y + m.rng.uniform(-0.12, 0.12)
                path = [S(x, u, yy), S(x + side * 0.04, u + 0.04, yy), S(x + side * 0.07, u - hang * 0.4, yy),
                        S(x + side * 0.08, u - hang, yy)]
                m.tube(path, [0.024, 0.022, 0.02, 0.01], LEAF_06, segments=3, tint=leaf_tint(m, tints))
    # Roots: a tangle of thick, snaking roots out to where the sprite's end.
    base = S(-0.03, 0.05, 0.0)
    for tip, mid in (((-0.6, 0.0), (-0.3, 0.1)), ((-0.5, -0.22), (-0.25, -0.05)), ((-0.3, -0.42), (-0.15, -0.2)),
                     ((0.15, -0.45), (0.05, -0.2)), ((0.5, -0.27), (0.25, -0.1)), ((0.7, -0.3), (0.4, -0.12)),
                     ((0.42, 0.12), (0.2, 0.15)), ((-0.38, 0.12), (-0.2, 0.18))):
        a = Vector((tip[0], tip[1] / 0.743 if tip[1] < 0 else 0.25, -0.05))
        b = Vector((mid[0], (mid[1] / 0.743 if mid[1] < 0 else 0.15) * 0.8, 0.1))
        m.tube([base + Vector((0, 0, 0.35)), b + Vector((0, 0, 0.08)), a.lerp(b, 0.35) + Vector((0, 0, 0.04)), a],
               [0.1, 0.075, 0.05, 0.02], BARK_06, segments=5, profile=bark_profile(m, 5, 0.55))
    shade_tree(m, S(0.3, 1.8), (1.0, 0.6, 1.2), leaf_dark=0.6, bark_top=3.0)


def tree_07(m):
    """Broad oak: a rounded crown of mustard and olive leaves, with a few lower clusters, on a
    short trunk with big roots."""
    strands = sprite_trunk(m, "tree-07", BARK_07, flare=1.45, lobes=4, roots_reach=0.15)
    skip(m, 26)  # the draws the old trunk took: the crown stays as it was
    lumps = crown_lumps(m, "tree-07")
    crown_limbs(m, strands, lumps, BARK_07, r0=0.12, smallest=0.3, lo=1.6)
    twigs_on(m, strands, BARK_07, count=14, lo=1.8)
    skip(m, limb_draws(lumps, 0.3, 3))
    leafy_crown(m, lumps, CARDS["07"], SHADOWS["07"], (PLAIN, (0.85, 1.0, 0.75), WARM))
    shade_tree(m, (0, 0, 3.4), (1.8, 1.8, 2.0), leaf_dark=0.4, bark_top=2.2)


def tree_08(m):
    """Bottle tree: a smooth, pale, bulging trunk that forks into spreading limbs holding a
    wide, flat-bottomed green crown."""
    # Smooth pale bark: shallow grooves.
    strands = sprite_trunk(m, "tree-08", BARK_08, segments=10, flare=1.2, lobes=5, flute=0.03, step=0.5)
    skip(m, 22)  # the draws the old trunk took: the crown stays as it was
    # Spreading limbs out to the crown's lumps, under a thin, open canopy they show through.
    lumps = crown_lumps(m, "tree-08")
    crown_limbs(m, strands, lumps, BARK_08, r0=0.11, smallest=0.3, lo=1.6)
    twigs_on(m, strands, BARK_08, count=14, lo=1.6)
    skip(m, limb_draws(lumps, 0.3, 3))
    leafy_crown(m, lumps, CARDS["08"], SHADOWS["08"], (PLAIN, WARM, PLAIN), cards=600, core=0.55)
    shade_tree(m, (0, 0, 4.0), (1.8, 1.8, 1.5), leaf_dark=0.42, bark_dark=0.45, bark_top=3.2)


def tree_09(m):
    """Baobab: three massive trunks grown together on buttress roots, under a huge crown of
    orange leaves five tiles across."""
    # The sprite's trunk is three grown together: three deep lobes all the way up.
    strands = sprite_trunk(m, "tree-09", BARK_09, segments=12, flare=1.2, lobes=3, lobe_depth=0.22, flute=0.06,
                           step=0.6, roots_reach=0.2)
    skip(m, 58)  # the draws the old trunk took: the crown stays as it was
    lumps = crown_lumps(m, "tree-09")
    crown_limbs(m, strands, lumps, BARK_09, r0=0.16, smallest=0.4, lo=2.0)
    twigs_on(m, strands, BARK_09, count=10, lo=2.2)
    skip(m, limb_draws(lumps, 0.4, 5))
    leafy_crown(m, lumps, CARDS["09"], SHADOWS["09"], (PLAIN, WARM, (1.0, 0.88, 0.75)), cards=800, size=0.6,
                core=0.55)
    shade_tree(m, (0, 0, 4.5), (2.5, 2.5, 2.0), leaf_dark=0.4, bark_dark=0.4, bark_top=3.6)


# --- dead and dry trees -----------------------------------------------------------------------

def twigs(m, start, direction, length, radius, depth, wood, spread=0.7, count=2, lift=0.25, droop=0.0, flat=False):
    """Recursive bare branching. Returns the tips."""
    rng = m.rng
    steps = 3 if depth > 0 else 2
    pts = branch_path(start, direction, length, steps, rng, droop, wobble=length * 0.06)
    m.tube(pts, [radius * (1.0 - 0.7 * i / steps) for i in range(steps + 1)], wood,
           segments=5 if radius > 0.05 else 3, smooth=True)
    if depth == 0:
        return [pts[-1]]
    tips = [pts[-1]]
    d = Vector(direction).normalized()
    for _ in range(count):
        side = d.cross(Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))))
        if flat:  # spread sideways only, for twigs lying along the ground
            side.z = 0.0
        side.normalize()
        nd = (d + side * rng.uniform(0.5, 1.0) * spread + Vector((0, 0, lift))).normalized()
        at = pts[1].lerp(pts[-1], rng.uniform(0.3, 0.95))
        tips += twigs(m, at, nd, length * rng.uniform(0.5, 0.7), radius * 0.55, depth - 1, wood, spread, count, lift,
                      droop * 0.6, flat)
    return tips


def shade_wood(m, top, dark=0.5):
    def fn(f, p, n):
        return dark + (1.0 - dark) * min(1.0, max(0.0, p.z / top)) * (0.85 + 0.15 * max(0.0, n.z))
    m.shade(fn)


def dead_dry_hairy_tree(m):
    """A fallen dead tree, traced off the sprite (picture 0): a log of strands twisted together
    lying east-west, thick at its eastern root end, where a curl of broken roots rises into the
    air, and splitting at the west into two long, thin limbs whose twigs spread along the ground.
    Points are where each part shows on the sprite (on_sprite), at a height above the ground."""
    GROOVE = groove_depth("dead-dry-hairy-tree")

    def G(x, up, z):
        # A point `z` above the ground that shows `up` tiles up the sprite.
        return Vector((x, (up - z * 0.669) / 0.743, z))
    # The log: three strands twisted together, (across, up the sprite, height, radius).
    log = [(1.3, 0.17, 0.22, 0.15), (0.9, 0.14, 0.21, 0.15), (0.4, 0.11, 0.19, 0.13), (0.0, 0.08, 0.16, 0.11),
           (-0.4, 0.02, 0.13, 0.085), (-0.7, -0.03, 0.1, 0.065)]
    for k in range(3):
        ph = k * math.tau / 3
        pts = [G(x + 0.0, up, z) + Vector((0.0, 0.1 * math.cos(ph + x * 3.0), 0.08 * math.sin(ph + x * 3.0)))
               for x, up, z, _ in log]
        m.tube(pts, [r for *_, r in log], WOOD_HAIRY, segments=6, profile=bark_profile(m, 6, GROOVE))
    # The two limbs the log splits into, and the twigs off them, all along the ground:
    # (points as (across, up the sprite), radius at the start).
    limbs = [
        ([(-0.6, 0.03), (-1.0, 0.13), (-1.4, 0.2), (-1.75, 0.18), (-2.05, 0.12)], 0.055),
        ([(-0.6, -0.08), (-0.9, -0.2), (-1.25, -0.3), (-1.6, -0.35), (-1.95, -0.36), (-2.3, -0.32), (-2.6, -0.3)], 0.055),
        ([(-1.55, 0.2), (-1.7, 0.4), (-1.8, 0.52), (-1.95, 0.45)], 0.025),
        ([(-1.2, 0.17), (-1.25, 0.45), (-1.15, 0.7), (-1.0, 0.75)], 0.025),
        ([(-1.9, 0.15), (-2.3, 0.08), (-2.7, 0.2), (-3.0, 0.32)], 0.03),
        ([(-1.95, -0.36), (-2.3, -0.55), (-2.6, -0.62), (-2.85, -0.68)], 0.025),
        ([(-1.25, -0.3), (-1.1, -0.55), (-0.95, -0.8), (-0.8, -1.0)], 0.025),
        ([(-1.6, -0.35), (-1.75, -0.55), (-1.85, -0.75)], 0.02),
        ([(-2.05, 0.12), (-2.2, 0.35), (-2.35, 0.45)], 0.02),
        ([(-0.9, -0.2), (-0.75, -0.45), (-0.6, -0.55)], 0.02),
        ([(-2.6, -0.3), (-2.95, -0.2), (-3.1, -0.1)], 0.02),
    ]
    for pts, r in limbs:
        n = len(pts)
        path = [G(x, up, 0.08 * (1.0 - i / n) + 0.03) for i, (x, up) in enumerate(pts)]
        m.tube(path, [r * (1.0 - 0.6 * i / (n - 1)) for i in range(n)], WOOD_HAIRY, segments=4, profile=bark_profile(m, 4, GROOVE))
    # The root end: broken roots curling up into the air, and a couple along the ground.
    for pts, r in (([(1.0, 0.2, 0.2), (0.95, 0.6, 0.55), (1.0, 0.9, 0.85), (1.12, 0.92, 0.85)], 0.05),
                   ([(1.2, 0.2, 0.22), (1.3, 0.55, 0.5), (1.45, 0.8, 0.7), (1.62, 0.78, 0.65)], 0.05),
                   ([(1.3, 0.15, 0.2), (1.55, 0.3, 0.3), (1.75, 0.45, 0.35), (1.95, 0.35, 0.25)], 0.045),
                   ([(1.3, 0.1, 0.15), (1.6, 0.05, 0.12), (1.85, 0.15, 0.06), (2.05, 0.3, 0.02)], 0.04),
                   ([(1.1, 0.05, 0.12), (1.3, -0.1, 0.06), (1.5, -0.12, 0.02)], 0.04),
                   ([(0.8, 0.25, 0.25), (0.75, 0.5, 0.45), (0.85, 0.7, 0.6)], 0.035)):
        n = len(pts)
        m.tube([G(*p) for p in pts], [r * (1.0 - 0.7 * i / (n - 1)) for i in range(n)], WOOD_HAIRY, segments=5, profile=bark_profile(m, 5, GROOVE))
    shade_wood(m, 0.5, dark=0.4)


def dead_grey_trunk(m):
    """A dead stump, traced off the sprite (picture 0): a thick gnarled trunk on snaking roots
    that curl out over the ground, its broken top split into a tall horn curling up, one hooking
    out to the left and a short curl to the right. Points are where each part shows on the
    sprite (on_sprite)."""
    S = on_sprite
    GROOVE = groove_depth("dead-grey-trunk")
    # The trunk, twisted from three strands: (across, up the sprite, radius).
    spine = [(-0.04, -0.05, 0.2), (-0.05, 0.4, 0.18), (-0.04, 0.8, 0.16), (-0.03, 1.15, 0.13), (-0.03, 1.3, 0.1)]
    for k in range(3):
        ph = k * math.tau / 3
        pts = [S(x + 0.4 * r * math.cos(ph + u * 3.0), u, 0.4 * r * math.sin(ph + u * 3.0)) for x, u, r in spine]
        pts[0].z = -0.1
        m.tube(pts, [r * 0.8 for _, _, r in spine], WOOD_GREY, segments=6, profile=bark_profile(m, 6, GROOVE))
    # Horns: points on the sprite and their radius at the start.
    for pts, r in (([(-0.04, 1.2), (-0.02, 1.45), (0.04, 1.65), (-0.04, 1.85), (0.0, 2.0), (0.06, 2.05)], 0.08),
                   ([(-0.1, 1.2), (-0.3, 1.25), (-0.5, 1.28), (-0.68, 1.33), (-0.75, 1.48), (-0.72, 1.55)], 0.06),
                   ([(0.04, 1.3), (0.18, 1.42), (0.28, 1.45), (0.3, 1.36)], 0.05),
                   ([(-0.12, 1.25), (-0.3, 1.4), (-0.35, 1.5)], 0.035)):
        n = len(pts)
        m.tube([S(x, u, 0.0) for x, u in pts], [r * (1.0 - 0.7 * i / (n - 1)) for i in range(n)], WOOD_GREY, segments=5, profile=bark_profile(m, 5, GROOVE))
    # Roots snaking over the ground: points as (across, up the sprite) at the ground.
    base = Vector((-0.04, 0.0, 0.3))
    for pts in (((0.15, 0.15), (0.4, 0.08), (0.6, -0.02), (0.65, -0.2), (0.55, -0.33), (0.62, -0.42)),
                ((0.1, 0.0), (0.3, -0.12), (0.35, -0.3), (0.25, -0.4)),
                ((-0.2, 0.05), (-0.35, -0.15), (-0.45, -0.35), (-0.55, -0.5)),
                ((-0.25, 0.15), (-0.45, 0.15), (-0.6, 0.05), (-0.65, -0.05)),
                ((0.0, -0.05), (0.05, -0.25), (0.1, -0.45)),
                ((0.2, 0.25), (0.45, 0.3), (0.6, 0.25))):
        path = [base] + [Vector((x, u / 0.743, max(0.0, 0.18 - 0.07 * i))) for i, (x, u) in enumerate(pts)]
        n = len(path)
        m.tube(path, [0.12 * (1.0 - 0.75 * i / (n - 1)) for i in range(n)], WOOD_GREY, segments=5, profile=bark_profile(m, 5, GROOVE))
    shade_wood(m, 2.2, dark=0.45)


def on_sprite(sx, up, y=0.0):
    """A point drawn `sx` tiles right and `up` tiles up the sprite from the entity's position,
    `y` tiles north of it: Factorio's camera shows z at 0.669 and y at 0.743 of a tile."""
    return Vector((sx, y, (up - y * 0.743) / 0.669))


def dead_tree_desert(m):
    """A dead desert tree, traced off the sprite (picture 0): a pale, knotted trunk twisting up
    and to the right from snaking roots, forking at about a tile up into a long limb reaching out
    and up to the right, a tall one up the middle, a crooked one up the left and a short stub
    to the left. Points are where each part shows on the sprite (on_sprite), each limb kept near
    the plane across the camera."""
    S = on_sprite
    GROOVE = groove_depth("dead-tree-desert")
    base = S(0.08, -0.05, -0.1)
    trunk_pts = [base - Vector((0, 0, 0.15)), base + Vector((0, 0, 0.1)), S(0.2, 0.45, -0.1), S(0.33, 0.75, -0.1),
                 S(0.35, 1.0, -0.05), S(0.3, 1.15, 0.0)]
    m.tube(trunk_pts, [0.22, 0.21, 0.19, 0.16, 0.13, 0.1], WOOD_DESERT, segments=7, profile=bark_profile(m, 7, GROOVE))
    for x, u, r in ((0.32, 0.55, 0.11), (0.1, 0.25, 0.12), (0.4, 0.9, 0.09)):  # knots on the trunk
        m.blob(S(x, u, -0.15), r, WOOD_DESERT, scale=(1.0, 1.0, 1.3), jitter=0.25, subdiv=2, smooth=True)
    # Limbs: (points on the sprite, radius at the start, how far north of the trunk's plane).
    limbs = [
        ([(0.33, 1.1), (0.6, 1.17), (0.9, 1.2), (1.3, 1.27), (1.6, 1.4), (1.85, 1.62), (2.02, 1.9), (2.12, 2.18)],
         0.1, -0.05),
        ([(0.3, 1.15), (0.5, 1.4), (0.75, 1.65), (0.95, 1.95), (1.0, 2.3), (0.98, 2.6), (0.95, 2.82)], 0.075, 0.15),
        ([(0.3, 1.05), (0.15, 1.3), (0.02, 1.6), (-0.04, 1.95), (-0.06, 2.25)], 0.07, -0.15),
        ([(0.12, 1.25), (-0.1, 1.33), (-0.35, 1.42), (-0.45, 1.5)], 0.035, 0.1),
        ([(0.8, 1.75), (1.05, 1.76), (1.15, 1.6), (1.2, 1.45)], 0.025, 0.15),
        ([(1.3, 1.27), (1.4, 1.15)], 0.025, -0.05),
        ([(1.85, 1.62), (1.95, 1.75)], 0.02, -0.05),
        ([(-0.04, 1.95), (-0.15, 2.1), (-0.2, 2.25)], 0.02, -0.15),
        ([(1.0, 2.3), (1.1, 2.45)], 0.02, 0.15),
        ([(0.95, 2.82), (0.88, 2.95)], 0.015, 0.15), ([(0.95, 2.82), (1.05, 2.95)], 0.015, 0.15),
        ([(0.6, 1.5), (0.5, 1.75), (0.48, 1.9)], 0.02, 0.15),
    ]
    for pts, r, y in limbs:
        n = len(pts)
        m.tube([S(x, u, y) for x, u in pts], [r * (1.0 - 0.5 * i / (n - 1)) for i in range(n)], WOOD_DESERT,
               segments=5 if r > 0.05 else 4, profile=bark_profile(m, 5 if r > 0.05 else 4, GROOVE))
    # Knotted collars at the forks.
    for x, u, radius in ((0.32, 1.1, 0.1), (0.75, 1.65, 0.05), (1.3, 1.27, 0.05)):
        m.blob(S(x, u, -0.05), radius, WOOD_DESERT, scale=(1.15, 1.0, 0.9), jitter=0.3, subdiv=1, smooth=True)
    # Roots along the ground, out to where the sprite's end: (tip, middle) as (across, up the sprite).
    for tip, mid in (((-1.05, -0.45), (-0.45, -0.25)), ((-0.42, -0.72), (-0.3, -0.45)), ((0.82, -0.32), (0.5, -0.15)),
                     ((-0.8, 0.15), (-0.45, 0.32)), ((0.45, 0.12), (0.3, 0.18))):
        a = Vector((tip[0], tip[1] / 0.743, -0.05))
        b = Vector((mid[0], mid[1] / 0.743, 0.06))
        m.tube([base + Vector((0, 0, 0.3)), (base + b) / 2 + Vector((0, 0, 0.1)), b, a.lerp(b, 0.4) + Vector((0, 0, 0.02)), a],
               [0.11, 0.09, 0.065, 0.045, 0.0], WOOD_DESERT, segments=5, profile=bark_profile(m, 5, GROOVE))
    shade_wood(m, 3.0, dark=0.5)


def dry_hairy_tree(m):
    """A tall dry tree, traced off the sprite (picture 0) like the desert tree: one pale trunk on
    a knotted, bulbous foot, curving up and leaning left, its crown of thin limbs spreading wide
    to the left and over the top, a few drooping to the right. Fine twigs hang off the limbs."""
    S = on_sprite
    GROOVE = groove_depth("dry-hairy-tree")
    m.blob(S(0.02, 0.08, 0.0), 0.24, WOOD_DRY_HAIRY, scale=(1.0, 1.0, 0.9), jitter=0.3, subdiv=2, flat_bottom=-0.05,
           smooth=True)
    # The trunk: (across, up the sprite, radius).
    spine = [(0.02, -0.05, 0.18), (0.04, 0.3, 0.14), (0.05, 0.7, 0.11), (0.03, 1.1, 0.085), (-0.05, 1.5, 0.065),
             (-0.2, 2.0, 0.05), (-0.3, 2.4, 0.04), (-0.38, 2.8, 0.03), (-0.45, 3.0, 0.015)]
    m.tube([S(x, u, 0.0) for x, u, _ in spine], [r for _, _, r in spine], WOOD_DRY_HAIRY, segments=7, profile=bark_profile(m, 7, GROOVE))
    # Limbs: points on the sprite, the radius at their start, how far north of the trunk's plane.
    limbs = [
        ([(-0.38, 2.8), (-0.6, 3.15), (-0.9, 3.42), (-1.2, 3.56), (-1.5, 3.55), (-1.62, 3.4)], 0.025, 0.1),  # over the top
        ([(-0.3, 2.35), (-0.7, 2.6), (-1.1, 2.62), (-1.4, 2.5), (-1.62, 2.3)], 0.025, 0.25),  # wide to the left
        ([(-0.22, 2.1), (-0.6, 2.2), (-1.0, 2.2), (-1.35, 2.22), (-1.55, 2.05)], 0.022, -0.2),
        ([(-0.05, 1.5), (0.15, 1.85), (0.45, 1.95), (0.8, 1.85), (1.05, 1.6), (1.2, 1.3)], 0.03, -0.1),  # right
        ([(0.15, 1.85), (0.3, 2.15), (0.55, 2.4), (0.75, 2.55), (0.92, 2.5)], 0.022, 0.15),
        ([(0.0, 1.4), (0.3, 1.5), (0.6, 1.35), (0.9, 1.0)], 0.022, 0.3),
        ([(-0.05, 1.6), (-0.25, 1.25), (-0.4, 0.8), (-0.48, 0.5)], 0.018, -0.25),  # hanging low left
        ([(-0.2, 2.0), (-0.1, 2.35), (0.05, 2.55), (0.35, 2.62), (0.6, 2.55)], 0.02, -0.3),
        ([(-0.6, 2.2), (-0.8, 2.0), (-0.95, 1.75)], 0.015, -0.2),
        ([(-1.1, 2.62), (-1.3, 2.85), (-1.55, 2.9)], 0.015, 0.25),
    ]
    for pts, r, y in limbs:
        n = len(pts)
        path = [S(x, u, y * i / (n - 1)) for i, (x, u) in enumerate(pts)]
        m.tube(path, [r * (1.0 - 0.5 * i / (n - 1)) for i in range(n)], WOOD_DRY_HAIRY, segments=4, profile=bark_profile(m, 4, GROOVE))
        # Hair: a few fine twigs hanging off along the limb's outer half.
        for i in range(n // 2, n):
            q = path[i - 1].lerp(path[i], 0.5)
            twigs(m, q, polar(m.rng.uniform(0.0, math.tau), -0.5), 0.35, 0.01, 0, WOOD_DRY_HAIRY, droop=0.25)
    shade_wood(m, 5.0, dark=0.55)


def dry_tree(m):
    """A small dead snag: a straight broken trunk, split at the top into two splintered prongs
    side by side, the left one taller."""
    GROOVE = groove_depth("dry-tree")
    trunk(m, [(0, 0.06, -0.1), (0.0, 0.03, 0.6), (0.0, 0.0, 1.2), (0.0, 0.0, 1.35)], [0.17, 0.155, 0.145, 0.14], WOOD_DRY,
          segments=8, wobble=0.02, profile=bark_profile(m, 8, GROOVE))
    # The split: two prongs across the camera, as drawn.
    for x0, x1, top, r in ((-0.06, -0.09, 1.72, 0.075), (0.07, 0.1, 1.6, 0.065)):
        m.tube([Vector((x0, 0.0, 1.25)), Vector(((x0 + x1) / 2, 0.0, (1.25 + top) / 2)), Vector((x1, 0.0, top))],
               [r, r * 0.95, r * 0.85], WOOD_DRY, segments=6, profile=bark_profile(m, 6, GROOVE))
        # Splinters round the broken end.
        for i in range(3):
            c = i / 3 * math.tau + m.rng.uniform(-0.3, 0.3)
            off = Vector((math.cos(c), math.sin(c), 0.0)) * r * 0.6
            m.tube([Vector((x1, 0.0, top - 0.05)) + off, Vector((x1, 0.0, top)) + off * 1.1
                    + Vector((0, 0, m.rng.uniform(0.04, 0.1)))], [r * 0.5, 0.0], WOOD_DRY, segments=3, smooth=False)
    shade_wood(m, 1.6, dark=0.5)


MODELS = {
    "tree-01": tree_01, "tree-02": tree_02, "tree-03": tree_03, "tree-04": tree_04, "tree-05": tree_05,
    "tree-06": tree_06, "tree-07": tree_07, "tree-08": tree_08, "tree-09": tree_09,
    "dead-dry-hairy-tree": dead_dry_hairy_tree, "dead-grey-trunk": dead_grey_trunk,
    "dead-tree-desert": dead_tree_desert, "dry-hairy-tree": dry_hairy_tree, "dry-tree": dry_tree,
}
# Factorio's colour variants of a tree (`identifier` in trees.lua: tree-08-brown...) are separate
# prototypes with the same sprites and other leaf colours: the same model, coloured from the sprite
# with their own tint (sprite_projection.py, part_colors.py). Without one the client drew a plain
# cone in the map colour.
VARIANTS = {"tree-02-red": "tree-02", "tree-06-brown": "tree-06", "tree-08-brown": "tree-08", "tree-08-red": "tree-08",
            "tree-09-brown": "tree-09", "tree-09-red": "tree-09"}
for _variant, _base in VARIANTS.items():
    MODELS[_variant] = MODELS[_base]
# Each model is seeded from its name; a variant from its tree's, so it has the same shape.
SEED_AS = dict(VARIANTS)
