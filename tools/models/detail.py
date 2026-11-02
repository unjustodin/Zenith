"""Surface detail for the machine models: the panels, rivets, gears, grilles, cables and ribbed
hoses Factorio's sprites show on their housings, so a housing isn't a plain slab.

Each helper adds to a kit.Part and keeps inside (or a hair outside) the box it decorates, so a
detail pass leaves the model's outline, and its overlap with the sprite, where it was.
"""

import math

from mathutils import Vector

import kit
from kit import R, T

kit.MATERIALS.update({
    "wire_red": ("a8352a", 0.6, 0.1, None, 0),
    "wire_green": ("4f9a3a", 0.6, 0.1, None, 0),
    "wire_yellow": ("c8a032", 0.6, 0.1, None, 0),
    "wire_blue": ("4a5aa8", 0.6, 0.1, None, 0),
    "grime": ("2e2a26", 0.95, 0.1, None, 0),       # dark recesses, vents and slots
    "hazard_red": ("9a3424", 0.7, 0.2, None, 0),   # Space Age's red and white warning stripes
    "hazard_white": ("cfc8bc", 0.7, 0.2, None, 0),
})

# Faces: the outward axis and sign of a box's side.
_FACES = {"-y": (1, -1), "+y": (1, 1), "-x": (0, -1), "+x": (0, 1), "+z": (2, 1)}


def _face_frame(lo, hi, face):
    """(axis, sign, the two in-plane axes) of a box face."""
    axis, sign = _FACES[face]
    others = [a for a in range(3) if a != axis]
    return axis, sign, others


def panel(p, lo, hi, face, mat, margin=0.06, raise_=0.015, rivet=None, rivet_step=0.22, split=1,
          rivet_r=0.018):
    """A plate on one face of the box lo..hi (each (x, y, z)): inset `margin` from the edges,
    standing `raise_` proud (negative: a recess), cut into `split` plates along the face's first
    axis. With `rivet` (a material) a row of rivets runs along the plate's top or far edge."""
    axis, sign, (a, b) = _face_frame(lo, hi, face)
    plane = hi[axis] if sign > 0 else lo[axis]
    span_a = (lo[a] + margin, hi[a] - margin)
    span_b = (lo[b] + margin, hi[b] - margin)
    if span_a[1] <= span_a[0] or span_b[1] <= span_b[0]:
        return p
    gap = 0.03
    step = (span_a[1] - span_a[0] + gap) / split
    for k in range(split):
        a0 = span_a[0] + k * step
        a1 = a0 + step - gap
        c0, c1 = [0.0] * 3, [0.0] * 3
        c0[a], c1[a] = a0, a1
        c0[b], c1[b] = span_b
        if raise_ >= 0:
            c0[axis], c1[axis] = sorted((plane, plane + sign * raise_))
        else:
            c0[axis], c1[axis] = sorted((plane, plane + sign * raise_))
        p.slab(*c0, *c1, mat)
    if rivet:
        n = max(2, int((span_a[1] - span_a[0]) / rivet_step) + 1)
        for k in range(n):
            t = span_a[0] + (span_a[1] - span_a[0]) * k / (n - 1)
            c = [0.0] * 3
            c[a], c[b] = t, span_b[1] + margin * 0.5
            c[axis] = plane + sign * 0.006
            size = [rivet_r * 2] * 3
            size[axis] = 0.02
            p.box(tuple(c), tuple(size), rivet)
    return p


def panelled(p, lo, hi, mat, plate=None, faces=("-y", "+z", "-x", "+x"), bevel=0.05, rivet="steel_light",
             margin=0.07, split=1, rivet_faces=("-y",)):
    """A housing: the slab lo..hi with a raised plate (`plate`, else the same paint) and a rivet
    row on each of `faces`."""
    p.slab(*lo, *hi, mat, bevel=bevel)
    for f in faces:
        axis, _ = _FACES[f]
        others = [hi[k] - lo[k] for k in range(3) if k != axis]
        if min(others) < 2.5 * margin + 0.05:
            continue
        # Rivets where Factorio's camera sees them best: the south face.
        panel(p, lo, hi, f, plate or mat, margin=margin, rivet=rivet if f in rivet_faces else None, split=split)
    return p


def slots(p, lo, hi, face, count, mat="grime", depth=0.012, along=0, fill=0.55):
    """Vent slots (thin dark bars) across one face of the box lo..hi; `along` 0 lays them along
    the face's first axis (stacked up the second), 1 the other way."""
    axis, sign, (a, b) = _face_frame(lo, hi, face)
    plane = hi[axis] if sign > 0 else lo[axis]
    run, stack = (a, b) if along == 0 else (b, a)
    m = 0.06
    s0, s1 = lo[stack] + m, hi[stack] - m
    pitch = (s1 - s0) / count
    for k in range(count):
        c0, c1 = [0.0] * 3, [0.0] * 3
        c0[run], c1[run] = lo[run] + m, hi[run] - m
        c0[stack] = s0 + k * pitch + pitch * (1 - fill) / 2
        c1[stack] = c0[stack] + pitch * fill
        c0[axis], c1[axis] = sorted((plane, plane + sign * depth))
        p.slab(*c0, *c1, mat)
    return p


def gear(p, center, r, z0, z1, mat, teeth=None, hub="steel_dark", holes=0, hole_mat="grime", segs=24):
    """A flat gear lying on its face from z0 to z1: a disc, teeth round its rim (one every 0.1
    tiles), a raised hub and `holes` dark cut-outs round it."""
    x, y = center
    h = z1 - z0
    p.cyl((x, y, (z0 + z1) / 2), r, h, mat, segs=segs)
    n = teeth or max(10, round(2 * math.pi * r / 0.1))
    for k in range(n):
        a = 360.0 * k / n
        p.box((0, 0, 0), (0.06, 0.05, h * 0.9), mat, matrix=T(x, y, (z0 + z1) / 2) @ R("Z", a) @ T(r + 0.02, 0, 0))
    p.cyl((x, y, z1 + 0.02), r * 0.28, 0.06, hub, segs=max(6, segs // 2))
    for k in range(holes):
        a = 2 * math.pi * (k + 0.5) / holes
        p.cyl((x + r * 0.6 * math.cos(a), y + r * 0.6 * math.sin(a), z1 + 0.002), r * 0.17, 0.006, hole_mat, segs=8)
    return p


def cable(p, points, r, mat, segs=5):
    """A thin cable through `points`, smoothly bent."""
    import space_kit
    return space_kit.bent(p, points, r, mat, segs=segs, smooth=4)


def hose_arc(p, center, radius, z, a0, a1, r, mat, rib=0.15, steps=None):
    """A ribbed hose bent along a circle about `center` (x, y) at height `z`, from angle a0 to a1
    (degrees)."""
    import space_kit
    n = steps or max(4, int(abs(a1 - a0) / 12))
    pts = []
    for k in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * k / n)
        pts.append((center[0] + radius * math.cos(a), center[1] + radius * math.sin(a), z))
    return space_kit.hose(p, pts, r, mat, segs=6, rib=rib, depth=0.18, smooth=3)


def ribbed_drum(p, center, r, length, mat, rib_mat, axis="X", ribs=5, segs=18):
    """A drum lying along `axis` with raised bands round it."""
    p.cyl(center, r, length, mat, segs=segs, axis=axis, bevel=0.02)
    i = "XYZ".index(axis)
    for k in range(ribs):
        c = list(center)
        c[i] += -length / 2 + length * (k + 0.5) / ribs
        p.cyl(tuple(c), r * 1.04, length / ribs * 0.22, rib_mat, segs=segs, axis=axis)
    return p


def coil(p, center, r, z0, z1, mat, turns=None, wire=0.025):
    """A copper coil: stacked rings of wire round a post from z0 to z1."""
    x, y = center
    n = turns or max(3, int((z1 - z0) / (wire * 2.6)))
    for k in range(n):
        z = z0 + (z1 - z0) * (k + 0.5) / n
        p.cyl((x, y, z), r + wire, wire * 2, mat, segs=8, caps=False)
    return p


def cage(p, center, r, mat, rings=3, wire=0.018, segs=12):
    """A wire ball: `rings` great circles through the poles and an equator."""
    cx, cy, cz = center
    for k in range(rings):
        p.cyl((0, 0, 0), r, wire * 2, mat, segs=segs, caps=False,
              matrix=T(cx, cy, cz) @ R("Z", 180.0 * k / rings) @ R("X", 90))
    p.cyl((cx, cy, cz), r, wire * 2, mat, segs=segs, caps=False)
    return p


def rivet_line(p, a, b, n, axis, mat="steel_light", r=0.018):
    """`n` rivets from point a to point b, their heads facing along `axis`."""
    A, B = Vector(a), Vector(b)
    for k in range(n):
        q = A.lerp(B, k / max(1, n - 1))
        size = [r * 2] * 3
        size["XYZ".index(axis)] = 0.02
        p.box(tuple(q), tuple(size), mat)
    return p


def stripes(p, lo, hi, face, count, mats=("hazard_red", "hazard_white"), slant=0.6, depth=0.012):
    """Diagonal warning stripes across one face of the box lo..hi: `count` slanted bands in turn
    of `mats` standing `depth` proud, `slant` the shear across the band's height."""
    from mathutils import Matrix
    axis, sign, (a, b) = _face_frame(lo, hi, face)
    plane = hi[axis] if sign > 0 else lo[axis]
    cols = [[0.0] * 3 for _ in range(3)]
    cols[0][a], cols[1][b], cols[2][axis] = 1.0, 1.0, float(sign)
    origin = [0.0] * 3
    origin[a], origin[b], origin[axis] = lo[a], lo[b], plane
    m = Matrix(((cols[0][0], cols[1][0], cols[2][0], origin[0]),
                (cols[0][1], cols[1][1], cols[2][1], origin[1]),
                (cols[0][2], cols[1][2], cols[2][2], origin[2]),
                (0, 0, 0, 1)))
    width, hgt = hi[a] - lo[a], hi[b] - lo[b]
    w = width / count
    sh = slant * hgt
    for k in range(count):
        x0 = k * w - sh / 2
        pts = [(x0, 0), (x0 + w, 0), (x0 + w + sh, hgt), (x0 + sh, hgt)]
        pts = [(min(max(x, 0.0), width), y) for x, y in pts]
        pts = [q for i, q in enumerate(pts) if q != pts[i - 1]]
        if len(pts) < 3:
            continue
        if abs(pts[1][0] - pts[0][0]) < 1e-4 and abs(pts[2][0] - pts[3][0]) < 1e-4:
            continue
        p.prism(pts, 0.0, depth, mats[k % len(mats)], matrix=m)
    return p


def spring(p, a, b, r, mat, turns=8, wire=0.02):
    """A coil spring from point a to point b: rings of wire along the line."""
    A, B = Vector(a), Vector(b)
    d = B - A
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    for k in range(turns):
        q = A.lerp(B, (k + 0.5) / turns)
        p.cyl((0, 0, 0), r, wire * 2, mat, segs=8, caps=False, matrix=T(*q) @ rot)
    return p


def girder(p, a, b, width, height, mat, up=(0, 0, 1), bay=0.16, chord=0.035, web=0.022):
    """An open lattice girder from a to b: four corner chords (a box `width` across and `height`
    along `up`) with zig-zag webs on its two side faces and its top, so the sky shows through the
    triangles as in Factorio's truss sprites."""
    A, B = Vector(a), Vector(b)
    x = (B - A).normalized()
    z = Vector(up) - x * x.dot(Vector(up))
    if z.length < 1e-6:
        z = x.orthogonal()
    z.normalize()
    y = z.cross(x)
    hw, hh = width / 2 - chord / 2, height / 2 - chord / 2
    corners = [(sy, sz) for sy in (-hw, hw) for sz in (-hh, hh)]
    for sy, sz in corners:
        off = y * sy + z * sz
        p.beam(tuple(A + off), tuple(B + off), chord, chord, mat, up=tuple(z))
    n = max(1, round((B - A).length / bay))
    for k in range(n):
        t0, t1 = k / n, (k + 1) / n
        P0, P1 = A.lerp(B, t0), A.lerp(B, t1)
        lo, hi = (P0, P1) if k % 2 == 0 else (P1, P0)
        for sy in (-hw, hw):   # side faces: from the bottom chord up to the top one
            p.beam(tuple(lo + y * sy - z * hh), tuple(hi + y * sy + z * hh), web, web * 0.8, mat, up=tuple(y))
        p.beam(tuple(lo + z * hh - y * hw), tuple(hi + z * hh + y * hw), web, web * 0.8, mat, up=tuple(z))
    for t in (0.0, 1.0):   # end frames
        P = A.lerp(B, t)
        p.beam(tuple(P - y * hw + z * hh), tuple(P + y * hw + z * hh), chord, chord, mat, up=tuple(z))
        p.beam(tuple(P - y * hw - z * hh), tuple(P + y * hw - z * hh), chord, chord, mat, up=tuple(z))
    return p
