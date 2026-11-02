"""Helpers shared by the Space Age models (gleba.py, aquilo.py): sprite-space placement, lathed
shapes, swept and ribbed hoses, and the extra palette those planets need.

Factorio's camera shows a point (x, y, z) at x tiles right and SIN_P * y + COS_P * z tiles up the
screen (oil.py explains the trick): `zs` gives a part's height from where it shows in the sprite
at a chosen depth, `ys` its depth from its height.
"""

import math

import bmesh
from mathutils import Matrix, Vector

import kit

SIN_P, COS_P = math.sin(math.radians(48)), math.cos(math.radians(48))

# Extra materials, added to kit's palette when this module loads (names pick the weathering
# class in model_library.gd: "flesh" and "ice" have classes of their own).
kit.MATERIALS.update({
    # Gleba machines: olive-green paint over brown-copper pipework.
    "paint_gleba": ("6b7a3a", 0.6, 0.35, None, 0),        # biochamber / tower panels
    "paint_gleba_dark": ("4c5530", 0.65, 0.35, None, 0),
    "copper_pipe": ("7a5a44", 0.5, 0.75, None, 0),        # brown copper pipes on Gleba
    "copper_pipe_dark": ("5a4232", 0.55, 0.7, None, 0),
    "hose_orange": ("b06a30", 0.75, 0.1, None, 0),        # ribbed hoses (agricultural tower)
    "hose_tan": ("8f7550", 0.8, 0.1, None, 0),            # ribbed hoses (cryogenic plant)
    "glass_green": ("7d9a3a", 0.2, 0.1, None, 0),         # biochamber tank, nutrient slime
    "glass_smoke": ("3c403c", 0.15, 0.3, None, 0),        # agricultural tower dome
    "glass_pale": ("b8c4c8", 0.2, 0.2, None, 0),          # biolab bellows, capsules
    "steel_violet": ("6f6670", 0.55, 0.65, None, 0),      # heating tower
    "steel_violet_dark": ("4e4850", 0.6, 0.6, None, 0),
    "steel_grey": ("7c7e7e", 0.5, 0.7, None, 0),          # rocket turret, railgun
    "steel_grey_dark": ("4a4b4c", 0.55, 0.7, None, 0),
    "steel_teal": ("8a9e9c", 0.5, 0.6, None, 0),          # biolab / captive spawner metal
    "brass_dull": ("9a7c48", 0.5, 0.8, None, 0),          # heating tower burner, fittings
    "fire_glow": ("ff9a3a", 0.8, 0.0, "ff7020", 2.5),
    "glow_green": ("b8e05a", 0.6, 0.0, "9ad040", 1.0),
    "glow_purple": ("c070e0", 0.6, 0.0, "a040d0", 1.0),
    "glow_cyan": ("80f0ff", 0.4, 0.0, "40d0ff", 2.0),
    "glow_orange": ("ffb060", 0.5, 0.0, "ff8020", 1.5),
    "flesh_pink": ("a8706e", 0.7, 0.0, None, 0),          # biolab brain, spawner flesh
    "flesh_tan": ("c09a7a", 0.7, 0.0, None, 0),
    "flesh_dark": ("6e4a3c", 0.75, 0.0, None, 0),
    "flesh_red": ("8c3c34", 0.7, 0.0, None, 0),
    "flesh_purple": ("6a4870", 0.7, 0.0, None, 0),
    # Gleba plants (all "flesh": the organic weathering class).
    "flesh_stalk": ("7a6448", 0.8, 0.0, None, 0),
    "flesh_bark": ("5a4838", 0.85, 0.0, None, 0),
    "flesh_fruit": ("b03a30", 0.5, 0.0, None, 0),
    "flesh_jelly": ("b48aa0", 0.6, 0.0, None, 0),
    "flesh_lilac": ("9a84b4", 0.6, 0.0, None, 0),
    "flesh_slip": ("8a6a94", 0.6, 0.0, None, 0),
    "flesh_olive": ("7c7a3a", 0.7, 0.0, None, 0),
    "flesh_coral": ("cc6e78", 0.6, 0.0, None, 0),
    "flesh_crimson": ("98404a", 0.6, 0.0, None, 0),
    "flesh_cyan": ("a8d4d4", 0.4, 0.0, None, 0),
    "flesh_puff": ("c8a054", 0.7, 0.0, None, 0),
    "flesh_cream": ("cdbe98", 0.7, 0.0, None, 0),
    "flesh_comb": ("d8b02c", 0.6, 0.0, None, 0),
    "flesh_reed": ("6a5434", 0.8, 0.0, None, 0),
    "flesh_egg": ("5e8a2a", 0.35, 0.0, None, 0),         # Gleba spawner egg sacs
    "flesh_culture": ("6f8a34", 0.4, 0.0, None, 0),      # biochamber culture
    "flesh_shell": ("74686c", 0.75, 0.0, None, 0),       # stomper armour
    # Aquilo machines: pale blue paint, grey steel, tan hoses.
    "paint_aquilo": ("7aa0aa", 0.55, 0.45, None, 0),      # cryogenic plant / fusion blue
    "paint_aquilo_dark": ("56757e", 0.6, 0.45, None, 0),
    "paint_fusion": ("8aa4bc", 0.55, 0.45, None, 0),
    "paint_bone": ("c8c2ae", 0.6, 0.3, None, 0),          # fusion tanks, off-white housings
    "steel_cold": ("9a9ea2", 0.45, 0.8, None, 0),
    "ice": ("cfe6ee", 0.35, 0.0, None, 0),
    "ice_blue": ("8fc0d8", 0.3, 0.0, None, 0),
    "ice_shadow": ("6f9cb4", 0.4, 0.0, None, 0),
    "rock_aquilo": ("6a7078", 0.95, 0.0, None, 0),        # vent crust
    "stone_yellow": ("b8a64a", 0.9, 0.0, None, 0),        # fluorine crust
    "stone_brine": ("a4a8a0", 0.9, 0.0, None, 0),
})
kit.ALPHA.update({"glass_green": 0.7, "glass_smoke": 0.75, "glass_pale": 0.8})


def zs(u, y):
    """Height of a point at depth `y` that shows `u` tiles up the screen in the sprite."""
    return (u - SIN_P * y) / COS_P


def ys(u, z):
    """Depth of a point at height `z` that shows `u` tiles up the screen in the sprite."""
    return (u - COS_P * z) / SIN_P


def px(x_px, y_px, ox, oy, z=None, y=None, ppt=128.0):
    """A point read off a reference image: pixel (x_px, y_px) with the ground origin at (ox, oy),
    `ppt` pixels per tile. Give the depth `y` to get (x, y, z), or the height `z`."""
    x = (x_px - ox) / ppt
    u = (oy - y_px) / ppt
    if y is not None:
        return (x, y, zs(u, y))
    return (x, ys(u, z), z)


def lathe(p, center, profile, mat, segs=16, axis="Z", a0=0.0, a1=360.0, matrix=None):
    """A surface of revolution: `profile` is a list of (radius, height) from bottom to top
    (outward faces on the side away from the axis), turned about `axis` through `center`.
    Points with radius 0 close the shape there. a0..a1 limits it to a sector (degrees)."""
    bm = bmesh.new()
    full = (a1 - a0) >= 359.999
    n = segs if full else segs + 1
    poles = {}
    rows = []
    for i in range(n):
        a = math.radians(a0 + (a1 - a0) * i / segs)
        c, s = math.cos(a), math.sin(a)
        row = []
        for k, (r, z) in enumerate(profile):
            if r <= 1e-6:
                if k not in poles:
                    poles[k] = bm.verts.new((0.0, 0.0, z))
                row.append(poles[k])
            else:
                row.append(bm.verts.new((r * c, r * s, z)))
        rows.append(row)
    for i in range(segs):
        A = rows[i]
        B = rows[(i + 1) % n] if full else rows[i + 1]
        for k in range(len(profile) - 1):
            quad = [A[k], B[k], B[k + 1], A[k + 1]]
            verts = []
            for v in quad:
                if v not in verts:
                    verts.append(v)
            if len(verts) >= 3:
                try:
                    bm.faces.new(verts)
                except ValueError:
                    pass
    if not full:
        for row in (rows[0], rows[-1]):
            verts = []
            for v in row:
                if v not in verts:
                    verts.append(v)
            if len(verts) >= 3:
                try:
                    f = bm.faces.new(verts)
                except ValueError:
                    continue
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    m = Matrix.Translation(center) @ kit._AXIS[axis]
    if matrix is not None:
        m = matrix @ m
    p.merge(bm, mat, m)
    bm.free()
    return p


def dome(p, center, radius, height, mat, segs=16, rings=5, base=0.0, axis="Z", matrix=None):
    """A dome (half ellipsoid) `radius` across and `height` tall on a short `base` collar."""
    prof = []
    if base > 0:
        prof.append((radius, -base))
    for i in range(rings + 1):
        t = (math.pi / 2) * i / rings
        prof.append((radius * math.cos(t), height * math.sin(t)))
    prof[-1] = (0.0, height)
    return lathe(p, center, prof, mat, segs, axis, matrix=matrix)


def catmull(points, steps=6):
    """Points through `points` along a Catmull-Rom spline, `steps` per span."""
    pts = [Vector(q) for q in points]
    if len(pts) < 3:
        return pts
    ext = [pts[0] * 2 - pts[1]] + pts + [pts[-1] * 2 - pts[-2]]
    out = []
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        for s in range(steps):
            t = s / steps
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(pts[-1])
    return out


def resample(points, step):
    """Points every `step` tiles along a polyline."""
    pts = [Vector(q) for q in points]
    out = [pts[0]]
    carry = 0.0
    for a, b in zip(pts, pts[1:]):
        d = (b - a).length
        t = step - carry
        while t <= d:
            out.append(a + (b - a) * (t / d))
            t += step
        carry = d - (t - step)
    if (out[-1] - pts[-1]).length > step * 0.3:
        out.append(pts[-1])
    else:
        out[-1] = pts[-1]
    return out


def sweep(p, points, radius, mat, segs=8, caps=True, radii=None):
    """A tube through `points` (already as smooth as wanted), radius per point from `radii`
    (a list, or a function of the point's index) or `radius`."""
    pts = [Vector(q) for q in points]
    n = len(pts)
    if n < 2:
        return p
    tangents = []
    for i in range(n):
        a = pts[max(0, i - 1)]
        b = pts[min(n - 1, i + 1)]
        tangents.append((b - a).normalized())
    normal = tangents[0].orthogonal().normalized()
    bm = bmesh.new()
    rings = []
    for i in range(n):
        t = tangents[i]
        if i > 0:
            # Parallel transport: keep the frame from twisting along the tube.
            normal = normal - t * normal.dot(t)
            if normal.length < 1e-6:
                normal = t.orthogonal()
            normal.normalize()
        binormal = t.cross(normal)
        if callable(radii):
            r = radii(i)
        elif radii is not None:
            r = radii[i]
        else:
            r = radius
        ring = []
        for k in range(segs):
            a = 2 * math.pi * k / segs
            ring.append(bm.verts.new(pts[i] + (normal * math.cos(a) + binormal * math.sin(a)) * r))
        rings.append(ring)
    for i in range(n - 1):
        A, B = rings[i], rings[i + 1]
        for k in range(segs):
            k2 = (k + 1) % segs
            bm.faces.new([A[k], A[k2], B[k2], B[k]])
    if caps:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    bm.normal_update()
    # Outward faces: flip if the first face points at the axis.
    bm.faces.ensure_lookup_table()
    f = bm.faces[0]
    centre = (pts[0] + pts[1]) / 2
    if f.normal.dot(f.calc_center_median() - centre) < 0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
    p.merge(bm, mat)
    bm.free()
    return p


def hose(p, points, radius, mat, segs=None, rib=0.08, depth=0.2, smooth=6, caps=True):
    """A ribbed (corrugated) hose along a smooth curve through `points`: a rib every `rib` tiles,
    each a ridge between two flats at (1 - depth) of the radius. Thin hoses get 6 sides."""
    if segs is None:
        segs = 6 if radius < 0.1 else 8
    path = resample(catmull(points, smooth), rib / 3)
    pattern = (1.0, 1.0 - depth, 1.0 - depth)
    radii = [radius * pattern[i % 3] for i in range(len(path))]
    return sweep(p, path, radius, mat, segs, caps, radii)


def bent(p, points, radius, mat, segs=8, smooth=5, caps=True):
    """A smooth bent pipe through `points` (no ball joints)."""
    return sweep(p, catmull(points, smooth), radius, mat, segs, caps)


def flange(p, center, radius, axis, mat="steel_dark", depth=0.05, segs=12):
    p.cyl(center, radius, depth, mat, segs=segs, axis=axis, bevel=0.01)


def blob(p, center, radius, mat, segs=10, rings=6, scale=(1, 1, 1), seed=0, wobble=0.12, matrix=None):
    """A lumpy ellipsoid (flesh, plants, ice): a UV sphere with each vertex pushed in or out a
    little by a smooth random field."""
    rnd = kit.rng(seed)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=radius)
    waves = [(Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))).normalized() * rnd.uniform(1.5, 3.5),
              rnd.uniform(0, 6.28)) for _ in range(4)]
    for v in bm.verts:
        d = v.co.normalized() if v.co.length > 0 else Vector((0, 0, 1))
        w = sum(math.sin(d.dot(k) + ph) for k, ph in waves) / len(waves)
        v.co = v.co * (1.0 + wobble * w)
    m = Matrix.Translation(center) @ kit.S(*scale)
    if matrix is not None:
        m = matrix @ m
    p.merge(bm, mat, m)
    bm.free()
    return p


def rock(p, center, size, mat, seed=0, segs=7, rings=5, jag=0.18, flat_bottom=True, matrix=None):
    """A faceted lump (icebergs, crust): a low sphere whose vertices are scaled randomly,
    flattened at the bottom so it sits on the ground."""
    rnd = kit.rng(seed)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
    for v in bm.verts:
        k = 1.0 + rnd.uniform(-jag, jag)
        v.co = v.co * k
        if flat_bottom and v.co.z < 0:
            v.co.z = 0.0
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    m = Matrix.Translation(center)
    if matrix is not None:
        m = matrix @ m
    p.merge(bm, mat, m)
    bm.free()
    return p


def ring(p, center, r_in, r_out, z0, z1, mat, segs=16, a0=0.0, a1=360.0):
    """A flat annulus or ring wall (a ring_band all round, as one lathe)."""
    return lathe(p, (center[0], center[1], 0.0),
                 [(r_in, z0), (r_out, z0), (r_out, z1), (r_in, z1), (r_in, z0)], mat, segs, a0=a0, a1=a1)


def stalk(p, points, r0, r1, mat, segs=8, smooth=5, caps=True):
    """A tapering stem through `points` (smoothed), radius r0 at the start to r1 at the end."""
    path = catmull(points, smooth)
    n = len(path)
    return sweep(p, path, r0, mat, segs, caps, [r0 + (r1 - r0) * i / max(1, n - 1) for i in range(n)])



def profile_loft(p, profile, mats, scale=1.0, smooth=1, cap=0.5, lift=0.0, matrix=None):
    """A creature's part lofted through the rings creature_hull.py measured from Factorio's
    rotation sprites (creature_profiles.PROFILES[name]): slices along the part (east-west or
    north-south), each a polar outline round its middle. `mats` gives a material per colour
    class letter ("a" darkest); each face takes the class most of its corners have. The ends are
    capped with a ring `cap` of the size half a slice further out; nothing goes under the ground
    (once lifted by `lift`). `smooth` passes of a 3-tap blur round and along the rings take the
    voxel steps off."""
    rings = profile["rings"]
    along_x = profile["axis"] == "x"
    n = len(rings[0][3])
    radii = [list(r[3]) for r in rings]
    for rr in radii:  # empty angle bins take their neighbours' radius
        for i, r in enumerate(rr):
            if r <= 0.0:
                good = [rr[j % n] for j in (i - 1, i + 1) if rr[j % n] > 0.0]
                rr[i] = sum(good) / len(good) if good else 0.05
    for _ in range(smooth):
        out = []
        for k, rr in enumerate(radii):
            prev, nxt = radii[max(0, k - 1)], radii[min(len(radii) - 1, k + 1)]
            out.append([0.4 * rr[i] + 0.15 * (rr[(i - 1) % n] + rr[(i + 1) % n]) + 0.15 * (prev[i] + nxt[i])
                        for i in range(n)])
        radii = out
    angles = [2 * math.pi * i / n for i in range(n)]
    ss = [r[0] for r in rings]
    ds = (ss[-1] - ss[0]) / max(1, len(ss) - 1)
    loops = [(ss[0] - ds * 0.5, rings[0][1], rings[0][2], [r * cap for r in radii[0]], rings[0][4])]
    loops += [(r[0], r[1], r[2], radii[k], r[4]) for k, r in enumerate(rings)]
    loops.append((ss[-1] + ds * 0.5, rings[-1][1], rings[-1][2], [r * cap for r in radii[-1]], rings[-1][4]))

    def gltf_to_blender(x, y, z):
        return Vector((x * scale, -z * scale, max(0.0, (y + lift) * scale)))

    bm = bmesh.new()
    vl, letters = [], []
    for s_, cu, cy, rr, cls in loops:
        row = []
        for a, r in zip(angles, rr):
            u, h = cu + r * math.cos(a), cy + r * math.sin(a)
            row.append(bm.verts.new(gltf_to_blender(s_, h, u) if along_x else gltf_to_blender(u, h, s_)))
        vl.append(row)
        letters.append(cls)
    order = sorted(set("".join(letters)))
    index = {c: i for i, c in enumerate(order)}

    def face(vs, cls):
        try:
            f = bm.faces.new(vs)
        except ValueError:
            return
        votes = {}
        for c in cls:
            votes[c] = votes.get(c, 0) + 1
        f.material_index = index[max(sorted(votes), key=votes.get)]

    for k in range(len(vl) - 1):
        for i in range(n):
            j = (i + 1) % n
            face([vl[k][i], vl[k + 1][i], vl[k + 1][j], vl[k][j]],
                 [letters[k][i], letters[k + 1][i], letters[k + 1][j], letters[k][j]])
    for k in (0, len(vl) - 1):
        ring_ = vl[k]
        c = bm.verts.new(sum((v.co for v in ring_), Vector()) / n)
        for i in range(n):
            j = (i + 1) % n
            face([ring_[i], c, ring_[j]], letters[k][i] + letters[k][j])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    p.merge(bm, None, matrix if matrix is not None else Matrix.Identity(4), mats=[mats[c] for c in order])
    bm.free()
    return p
