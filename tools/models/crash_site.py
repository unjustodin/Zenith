"""The crash site on Nauvis: the wrecked spaceship, its scattered wreckage and the two cargo pods
(crash-site-chest-1/2). Modelled from Factorio's sprites (base/graphics/entity/crash-site-*); nothing
here rotates, so each piece is modelled as its one picture shows it.

Each wreck is built piece by piece from its picture: bent panels, frame members, ribbed ducts,
engine nacelles. A flat piece's outline is read off the sprite in screen tiles (x right, up from
the entity's position; OUTLINES at the end) and laid onto the piece's own plane, lying on the
ground, leaning or standing as the picture shows it. Factorio's camera looks north and down at 48
degrees, so a point z tiles up shows z * cos(48) tiles up the screen and a point y tiles north
y * sin(48); round parts (nacelles, pods, ducts) are placed the same way from where the picture
shows them.

Paint and metal are separate materials so each takes its own colour from the sprite: the weathered
yellow paint, grey and beige panels, rusty frames, bare burnt steel and the soot-dark insides.

The hull isn't left as flat slabs: rounded() (below) rounds their shoulders, bulges their sides,
swells each panel and dents the plates, moving vertices only along Factorio's camera ray, so the
outline that camera sees (and every score) stays exactly as traced. The yellow plating's seams are
the sprites' own (traced by trace_seams.py into crash_seams.py), cut into it as dark grooves.
"""

import math
import random

from mathutils import Matrix, Vector

from crash_seams import SEAMS
from kit import MATERIALS, Part, R, T, model

# The wreck's olive-yellow paint and the burnt, bare steel of its torn edges (from the sprites).
MATERIALS.setdefault("paint_wreck", ("b39a2c", 0.55, 0.35, None, 0))
MATERIALS.setdefault("steel_burnt", ("6b6156", 0.7, 0.6, None, 0))
MATERIALS.setdefault("steel_scorched", ("3d3833", 0.8, 0.5, None, 0))
# The same paint where it is still bright yellow (loose panels and fins, the pods, the hull's
# plates), sampled from each sprite rather than given the family's one dark olive.
MATERIALS.setdefault("wreck_yellow", ("b89d3c", 0.55, 0.35, None, 0))
# The bare, dirty steel of the engines' cowlings, intake lips and bent straps, and the grey
# machinery between the hull's plates (housings, pumps, grilles).
MATERIALS.setdefault("wreck_metal", ("a39d8c", 0.6, 0.6, None, 0))
MATERIALS.setdefault("wreck_machine", ("6f6c62", 0.7, 0.55, None, 0))

SIN, COS = math.sin(math.radians(48.0)), math.cos(math.radians(48.0))
ANCHOR = 0.3  # the entity's position is the projection of this height (compare.py)


def screen(sx, up, z):
    """The point `z` tiles up that Factorio's camera shows at (sx, up) screen tiles."""
    return (sx, (up - COS * (z - ANCHOR)) / SIN, z)


def plate(p, outline, mat, tilt=0.0, yaw=0.0, thick=0.1, lift=0.0, at=None, bevel=0.0):
    """A plate whose face towards the camera shows as `outline` (screen tiles). Its plane is
    turned `yaw` degrees about the vertical and tilted `tilt` degrees up towards the north (0
    lies flat, 90 stands facing south); it is `thick` deep behind its face. The plane passes
    through the point `at`, or else sits with its lowest corner `lift` above the ground. Returns
    a function from screen (sx, up[, out]) to the point on the face, `out` tiles in front."""
    rot = R("Z", yaw) @ R("X", tilt)
    u, w, n = (Vector([rot[r][c] for r in range(3)]) for c in range(3))
    uy, wy = SIN * u.y + COS * u.z, SIN * w.y + COS * w.z  # how far up the screen each axis goes
    det = u.x * wy - w.x * uy

    def solve(o, sx, up):
        bx, by = sx - o.x, up - (SIN * o.y + COS * (o.z - ANCHOR))
        return (bx * wy - w.x * by) / det, (u.x * by - uy * bx) / det

    def low(o):
        zs = [(o + u * a + w * b).z for a, b in (solve(o, *q) for q in outline)]
        return min(zs) - max(0.0, n.z) * thick

    if at is not None:
        o = Vector(at)
    else:  # the lowest corner moves linearly with the origin's height (standing: its depth)
        d = Vector((0, 0, 1)) if abs(n.z) > 0.05 else Vector((0, 1, 0))
        l0, l1 = low(Vector()), low(d)
        o = d * ((lift - l0) / (l1 - l0))
    m = T(*o) @ rot
    p.prism([solve(o, *q) for q in outline], -thick, 0.0, mat, bevel=bevel, matrix=m)

    def on(sx, up, out=0.0):
        a, b = solve(o, sx, up)
        q = o + u * a + w * b + n * out
        return (q.x, q.y, q.z)
    return on


def pieces(outlines, label):
    """The outlines traced for `label` (a piece the sprite shows in several bits has several)."""
    return [v for k, v in outlines.items() if k.rstrip("0123456789") == label]


def duct(p, points, radius, mat, rib_mat=None, pitch=0.09):
    """A ribbed duct or hose through `points`, with a rib every `pitch` tiles."""
    p.pipe(points, radius, mat, segs=10)
    for a, b in zip(points, points[1:]):
        a, b = Vector(a), Vector(b)
        k = max(1, int((b - a).length / pitch))
        for i in range(k):
            q, d = a + (b - a) * ((i + 0.5) / k), (b - a) * (0.12 / k)
            p.tube(q - d, q + d, radius * 1.13, rib_mat or mat, segs=10)


def disc(p, centre, normal, radius, depth, mat, segs=18, radius_top=None):
    """A short cylinder on `centre`, its axis along `normal`."""
    c, n = Vector(centre), Vector(normal).normalized() * (depth / 2)
    p.tube(c - n, c + n, radius, mat, segs=segs, radius_top=radius_top)


def intake(p, front, normal, radius, lip="wreck_metal", blades=16, back=0.08):
    """An engine's intake at `front`, opening along `normal`, as the sprites draw it: a thick
    rolled lip of bare metal round a deep dark throat, the turbine's blades a crown of short
    vanes round the throat's wall and a small hub at the bottom. The lip's crown is `back` radii
    behind `front`."""
    import space_kit
    r = radius
    n = Vector(normal).normalized()
    f = Vector(front) - n * back * r
    m = T(*f) @ Vector((0, 0, 1)).rotation_difference(n).to_matrix().to_4x4()
    segs = 24 if r > 0.7 else 18
    # Outside up over the lip and down into the throat, so every face looks out of the metal.
    space_kit.lathe(p, (0, 0, 0), [(r * 1.03, -0.32 * r), (r * 1.07, -0.1 * r), (r * 1.04, 0.03 * r),
                                   (r * 0.95, 0.07 * r), (r * 0.86, 0.02 * r), (r * 0.82, -0.1 * r)],
                    lip, segs=segs, matrix=m)
    space_kit.lathe(p, (0, 0, 0), [(r * 0.82, -0.1 * r), (r * 0.8, -0.55 * r), (r * 0.3, -0.6 * r),
                                   (r * 0.2, -0.5 * r), (0.0, -0.42 * r)], "steel_scorched", segs=segs, matrix=m)
    side = n.orthogonal().normalized()
    for k in range(blades):
        q = Matrix.Rotation(math.radians(360.0 * k / blades), 3, n) @ side
        t = n.cross(q)
        a, b = f + q * r * 0.79 - n * r * 0.5, f + q * r * 0.52 - n * r * 0.28 + t * r * 0.08
        p.beam(tuple(a), tuple(b), 0.035 * r / 0.5, 0.02, "steel_burnt", up=tuple(t))
    for k in range(blades // 2):   # bolts round the lip
        q = Matrix.Rotation(math.radians(360.0 * (k + 0.5) / (blades // 2)), 3, n) @ side
        p.sphere(tuple(f + q * r * 1.0 + n * 0.06 * r), 0.022 * r / 0.5, "steel_light", segs=5, rings=3)


def nacelle(p, front, normal, length, radius, body=1.0, mat="wreck_yellow", blades=16, nose=0.0,
            nose_mat="wreck_metal", back=0.08):
    """An engine nacelle: its intake at `front` opening along `normal`, behind it a cowling
    `length` long and `body` times the intake's radius; its first `nose` tiles bare metal."""
    f, n = Vector(front), Vector(normal).normalized()
    segs = 20 if radius > 0.7 else 16
    if nose > 0:   # the same taper, in two pieces
        mid = radius * 1.03 + (radius * body - radius * 1.03) * (nose - 0.1) / (length - 0.1)
        # Open at the front: a cap there would close the intake's throat.
        p.tube(f - n * nose, f - n * 0.1, mid, nose_mat, segs=segs, radius_top=radius * 1.03, caps=False)
        p.tube(f - n * length, f - n * nose, radius * body, mat, segs=segs, radius_top=mid)
    else:
        p.tube(f - n * length, f - n * 0.1, radius * body, mat, segs=segs, radius_top=radius * 1.03, caps=False)
        disc(p, f - n * (length - 0.01), n, radius * body, 0.02, mat, segs=segs)
    intake(p, f, n, radius, blades=blades, back=back)


def densify(p, size):
    """Splits the part's big faces into triangles no more than about `size` across, so the part
    colours' soft two-tone regions (part_colors `two_tone`) have corners inside them to carry the
    sprite's grime, scorch and worn paint; small details keep their few faces."""
    import bmesh
    bm = p.bm
    for _ in range(10):
        # Only faces Factorio's camera sees (it looks north and down): the sprite has nothing for
        # the others.
        bm.normal_update()
        big = [f for f in bm.faces if f.calc_area() > size * size * 0.5 and f.normal.z > -0.2 and f.normal.y < 0.2]
        if not big:
            break
        tris = set(bmesh.ops.triangulate(bm, faces=big)["faces"])
        # Split only edges inside the big faces, so the walls round them keep their own faces
        # (an edge split there leaves the wall an n-gon with points in a row, which renders holed).
        edges = [e for e in {e for f in tris for e in f.edges}
                 if e.calc_length() > size and all(f in tris for f in e.link_faces)]
        if edges:
            bmesh.ops.subdivide_edges(bm, edges=edges, cuts=1, use_grid_fill=False)
        else:   # no inner edge left to split: a point in each big face's middle
            bmesh.ops.poke(bm, faces=[f for f in tris if f.calc_area() > size * size])
            break
    return p


def pod(p, hatch, back, r_hatch, r_back):
    """A cargo pod as the sprites draw it: a barrel of worn yellow plates from its hatch end to its
    back, girt by dark bands with bolt heads along them, the hatch a bolted round door of rings
    round a boss. The barrel is cut into short lengths so the part colours' two-tone regions can
    put the sprite's dark wear and lit paint along it."""
    h, b = Vector(hatch), Vector(back)
    n = (h - b).normalized()
    end = h - n * 0.05
    k = 6
    for i in range(k):
        t0, t1 = i / k, (i + 1) / k
        p.tube(b.lerp(end, t0), b.lerp(end, t1), r_back + (r_hatch - r_back) * t0, "wreck_yellow", segs=20,
               radius_top=r_back + (r_hatch - r_back) * t1, caps=(i in (0, k - 1)))
    side = n.orthogonal().normalized()
    for t in (0.2, 0.5, 0.8):
        c, rad = b + (h - b) * t, (r_back + (r_hatch - r_back) * t) * 1.03
        disc(p, c, n, rad, 0.1, "steel_burnt", segs=20)
        for j in range(8):
            q = Matrix.Rotation(math.radians(45.0 * j + 20.0 * t), 3, n) @ side
            if q.z > -0.6:   # none under the barrel, in the ground
                p.sphere(tuple(c + n * 0.06 + q * rad), 0.028, "steel_light", segs=5, rings=3)
    disc(p, h - n * 0.04, n, r_hatch * 0.97, 0.08, "steel_burnt", segs=20)
    disc(p, h - n * 0.01, n, r_hatch * 0.8, 0.04, "steel_scorched", segs=20)
    disc(p, h, n, r_hatch * 0.62, 0.05, "steel_light", segs=18)
    disc(p, h + n * 0.02, n, r_hatch * 0.42, 0.04, "steel_scorched", segs=16)
    disc(p, h + n * 0.04, n, r_hatch * 0.2, 0.06, "steel_light", segs=12)
    for j in range(12):
        q = Matrix.Rotation(math.radians(30.0 * j), 3, n) @ side
        p.sphere(h + q * r_hatch * 0.88, 0.03, "steel_light", segs=6, rings=3)
    q = Matrix.Rotation(math.radians(100.0), 3, n) @ side   # the latch on the rim
    p.box(tuple(h - n * 0.02 + q * r_hatch * 0.95), (0.08, 0.08, 0.08), "steel_light")


def _inside(poly, x, y):
    """Point in polygon (screen tiles), even-odd rule."""
    c = False
    n = len(poly)
    for i in range(n):
        (x0, y0), (x1, y1) = poly[i], poly[i - 1]
        if (y0 > y) != (y1 > y) and x < x0 + (x1 - x0) * (y - y0) / (y1 - y0):
            c = not c
    return c


def clip_x(poly, x, keep_left):
    """The part of polygon `poly` (screen tiles) left (or right) of the line sx = x."""
    def side(q):
        return (q[0] <= x) if keep_left else (q[0] >= x)
    out = []
    for i in range(len(poly)):
        a, b = poly[i - 1], poly[i]
        if side(b):
            if not side(a):
                t = (x - a[0]) / (b[0] - a[0])
                out.append((x, a[1] + (b[1] - a[1]) * t))
            out.append(b)
        elif side(a):
            t = (x - a[0]) / (b[0] - a[0])
            out.append((x, a[1] + (b[1] - a[1]) * t))
    return out


def strap(p, on, points, width=0.17, mat="wreck_metal"):
    """A bent strap of the hull's frame: a flat band through screen points (sx, up, out), each
    `out` tiles off the face `on`, standing edge-on to nothing in particular (as torn steel does)."""
    q = [on(*t) for t in points]
    for a, b in zip(q, q[1:]):
        p.beam(a, b, width, 0.035, mat, up=(0, -0.6, 0.8))
    for a in q[1:-1]:
        p.sphere(a, width * 0.32, mat, segs=6, rings=3)


def chain(p, top, bottom, links=5, mat="wreck_metal"):
    """A hanging chain of flat link plates from `top` to `bottom`, each with its dark hole."""
    A, B = Vector(top), Vector(bottom)
    for k in range(links):
        a, b = A.lerp(B, k / links), A.lerp(B, (k + 0.85) / links)
        up = (0, -1, 0) if k % 2 == 0 else (1, 0, 0)
        p.beam(tuple(a), tuple(b), 0.09, 0.025, mat, up=up)
        c = a.lerp(b, 0.5)
        p.beam(tuple(c - (b - a) * 0.25), tuple(c + (b - a) * 0.25), 0.04, 0.03, "steel_scorched", up=up)


def mesh_net(p, on, x0, x1, u0, u1, out=0.04, pitch=0.12, mat="steel_scorched"):
    """The torn wire mesh the sprite shows over open bays: thin wires both ways on a face."""
    k = int((x1 - x0) / pitch)
    for i in range(k + 1):
        x = x0 + (x1 - x0) * i / k
        p.beam(on(x, u0, out), on(x, u1, out), 0.012, 0.012, mat)
    k = int((u1 - u0) / pitch)
    for i in range(k + 1):
        u = u0 + (u1 - u0) * i / k
        p.beam(on(x0, u, out), on(x1, u, out), 0.012, 0.012, mat)


def seams(p, on, lines, width=0.035, mat="steel_scorched", out=0.015, rivets=0.0, strips=True):
    """Lines the sprite draws on a face (plate seams, the edges of recessed panels): dark strips
    through screen points, standing `out` proud of the face `on`; with `rivets` a rivet head every
    that many tiles along them. Without `strips` only the rivets (the seams themselves cut as
    grooves, rounded())."""
    normal = tuple(Vector(on(0, 0, 1)) - Vector(on(0, 0, 0)))   # flat on the face
    for line in lines:
        for a, b in zip(line, line[1:] if strips else ()):   # in short pieces, to follow a face rounded() curves
            k = max(1, int(math.hypot(b[0] - a[0], b[1] - a[1]) / 0.4 + 0.5))
            for i in range(k):
                p.beam(on(a[0] + (b[0] - a[0]) * i / k, a[1] + (b[1] - a[1]) * i / k, out),
                       on(a[0] + (b[0] - a[0]) * (i + 1) / k, a[1] + (b[1] - a[1]) * (i + 1) / k, out),
                       width, 0.02, mat, up=normal)
        if rivets:
            for a, b in zip(line, line[1:]):
                n = max(1, int(math.hypot(b[0] - a[0], b[1] - a[1]) / rivets))
                for i in range(n + 1):
                    t = i / n
                    p.sphere(on(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, out + 0.01), 0.017,
                             "steel_light", segs=5, rings=3)


def plating(p, on, outline, seed, col=(0.55, 1.0), row=(0.35, 0.8), patch=0.3, seam="steel_scorched",
            paint="wreck_yellow", skip=(), pillows=False, strips=True):
    """The sprite's panelled skin on a plate's face: panels in columns of random widths, their
    seams as dark strips standing a hair proud (only where they lie on the face), and some panels
    doubled by a raised patch plate. `on` is what plate() returned for that face; nothing goes
    inside the `skip` polygons (open bays the sprite shows machinery in). Returns the panels as
    (x0, u0, x1, u1, height) in screen tiles; with `pillows` the patch plates aren't added as flat
    plates but given a higher bulge (rounded() swells every panel); without `strips` no seams are
    laid (they're cut as grooves instead)."""
    panels = []
    r = random.Random(seed)
    face = outline
    normal = tuple(Vector(on(0, 0, 1)) - Vector(on(0, 0, 0)))   # seams lie flat on the face

    def inside(x, y):
        return _inside(face, x, y) and not any(_inside(s, x, y) for s in skip)
    xs = [q[0] for q in outline]
    ys = [q[1] for q in outline]
    x = min(xs) + r.uniform(0.0, col[0])
    cols = [min(xs)]
    while x < max(xs):
        cols.append(x)
        x += r.uniform(*col)
    cols.append(max(xs))
    step = 0.12

    def seam_line(a, b):
        """Dark strips along a to b (screen), in short runs that stay on the face."""
        if not strips:
            return
        n = max(1, int(math.hypot(b[0] - a[0], b[1] - a[1]) / step))
        run = None
        for k in range(n + 1):
            t = k / n
            q = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
            ok = inside(*q)
            if ok and run is None:
                run = q
            if (not ok or k == n) and run is not None:
                end = q if ok else (a[0] + (b[0] - a[0]) * (k - 1) / n, a[1] + (b[1] - a[1]) * (k - 1) / n)
                length = math.hypot(end[0] - run[0], end[1] - run[1])
                if length > 0.05:
                    # In short pieces, so they follow the face once rounded() curves it.
                    k = max(1, int(length / 0.45 + 0.5)) if pillows else 1
                    for i in range(k):
                        q0 = (run[0] + (end[0] - run[0]) * i / k, run[1] + (end[1] - run[1]) * i / k)
                        q1 = (run[0] + (end[0] - run[0]) * (i + 1) / k, run[1] + (end[1] - run[1]) * (i + 1) / k)
                        p.beam(on(*q0, out=0.012), on(*q1, out=0.012), 0.032, 0.025, seam, up=normal)
                run = None

    for c0, c1 in zip(cols, cols[1:]):
        if c0 > min(xs):
            seam_line((c0, min(ys)), (c0, max(ys)))
        u = min(ys) + r.uniform(0.0, row[0])
        rows = [min(ys)]
        while u < max(ys):
            rows.append(u)
            seam_line((c0, u), (c1, u))
            u += r.uniform(*row)
        rows.append(max(ys))
        for u0, u1 in zip(rows, rows[1:]):
            raised = False
            if r.random() < patch:
                m = 0.08
                quad = [(c0 + m, u0 + m), (c1 - m, u0 + m), (c1 - m, u1 - m), (c0 + m, u1 - m)]
                if all(inside(*q) for q in quad) and c1 - c0 > 0.3 and u1 - u0 > 0.25:
                    raised = True
                    if not pillows:
                        p.poly([on(*q, out=0.035) for q in quad], paint, thick=0.03)
            panels.append((c0, u0, c1, u1, 2.2 if raised else 1.0))
    return panels


# ---------------------------------------------------------------------------------------------
# Rounded hull. plate() builds flat slabs; Factorio's ship is rounded, bulging plating. Every
# vertex here moves only along the ray of Factorio's camera (VIEW), so the picture that camera
# sees keeps exactly its outline (the silhouette scores can't change) while the shapes round off
# for every other view: the slabs' south shoulders are rounded, their south walls bulge like a
# fuselage, their tops dome, each panel of the plating swells between its seams and the plates
# carry dents; leaning and lying plates bow. Details already placed on a face (seams, rivets,
# hatches, straps) move with it.

VIEW = Vector((0.0, COS, -SIN))   # the camera's ray, into the picture


def _scr(co):
    return co.x, SIN * co.y + COS * (co.z - ANCHOR)


def _smooth(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


class Dents:
    """Shallow dents (and a few bumps) scattered over a piece's screen box (a, b, c, d)."""

    def __init__(self, seed, box, count, depth):
        r = random.Random(seed)
        x0, u0, x1, u1 = box
        self.d = [(r.uniform(x0, x1), r.uniform(u0, u1), r.uniform(0.18, 0.45),
                   depth * r.uniform(0.4, 1.0) * (1 if r.random() < 0.7 else -0.6)) for _ in range(count)]

    def __call__(self, sx, su):
        out = 0.0
        for x, u, rad, a in self.d:
            q = ((sx - x) ** 2 + (su - u) ** 2) / (rad * rad)
            if q < 4.0:
                out += a * math.exp(-q)
        return out


def _pillow(panels, amp, sx, su):
    for x0, u0, x1, u1, k in panels:
        if x0 <= sx <= x1 and u0 <= su <= u1:
            fx = math.sin(math.pi * (sx - x0) / (x1 - x0)) if x1 > x0 else 0.0
            fu = math.sin(math.pi * (su - u0) / (u1 - u0)) if u1 > u0 else 0.0
            return amp * k * (max(fx, 0.0) * max(fu, 0.0)) ** 0.6
    return 0.0


def _seg_dist(p, a, b):
    d = b - a
    t = min(1.0, max(0.0, ((p.x - a.x) * d.x + (p.y - a.y) * d.y) / d.length_squared))
    return (Vector((p.x, p.y)) - (a + d * t)).length


class Slab:
    """A flat plate() (tilt 0, lift 0) to round: its outline in screen tiles and thickness; `r`
    the shoulders' radius, `dome` how far the top swells, `barrel` the south walls."""

    def __init__(self, outline, thick, r=0.4, dome=0.2, barrel=0.15, panels=(), pillow=0.05, dents=None, coarse=1.0,
                 ramp=None, join=(), join_width=0.9):
        self.T, self.coarse = thick, coarse
        # (x0, x1, height): east of screen x0 the top sinks to `height` at x1, the walls leaning
        # with it (each point along its own ray), so a taller slab meets its lower neighbour.
        self.ramp = ramp
        # Slabs this one runs up into: its top near its north edges bends back along the ray
        # onto the wall behind it, so a lower slab and the one behind are one curved side.
        self.join, self.join_width = list(join), join_width
        self.r = min(r, 0.7 * thick)
        self.dome, self.barrel, self.panels, self.pillow, self.dents = dome, barrel, list(panels), pillow, dents
        self.plan = [Vector(screen(x, u, thick)[:2]) for x, u in outline]
        area = sum(a.x * b.y - b.x * a.y for a, b in zip(self.plan, self.plan[1:] + self.plan[:1]))
        self.edges = []
        for i in range(len(self.plan)):
            a, b = self.plan[i - 1], self.plan[i]
            d = b - a
            if d.length < 1e-6:
                continue
            n = Vector((d.y, -d.x)).normalized() * (1 if area > 0 else -1)   # outward
            self.edges.append((a, b, n))
        xs, us = [q[0] for q in outline], [q[1] for q in outline]
        self.box = (min(xs) - 0.05, min(us) - COS * thick - 0.05, max(xs) + 0.05, max(us) + 0.05)

    def size_at(self, co):
        """How finely the surface is split round `co`: finest on the rounded shoulders."""
        if co.z >= self.T - self.r - 0.05:
            for a, b, n in self.edges:
                if n.y <= -0.25 and _seg_dist(co.xy, a, b) < self.r + 0.08:
                    return max(0.12, self.r * 0.3) * min(self.coarse, 1.7)
        return (0.3 if co.z > self.T - 0.01 else 0.65) * self.coarse

    def hit(self, co):
        """(how far in front of the slab's surface `co` lies along VIEW, its move along VIEW), or
        None where no surface of the slab is just behind it."""
        return self.cast(co, -0.04, 0.35)

    def cast(self, co, lo, hi):
        """As hit(), for a surface between `lo` and `hi` along VIEW from `co`."""
        sx, su = _scr(co)
        x0, u0, x1, u1 = self.box
        if not (x0 <= sx <= x1 and u0 <= su <= u1):
            return None
        cross = []
        for a, b, n in self.edges:
            if (a.x > co.x) != (b.x > co.x):
                cross.append((a.y + (co.x - a.x) * (b.y - a.y) / (b.x - a.x), (a, b, n)))
        cross.sort(key=lambda c: c[0])
        t_top, t_ground = (co.z - self.T) / SIN, co.z / SIN
        best = None
        for (ya, ea), (yb, _) in zip(cross[0::2], cross[1::2]):
            ts, te = max((ya - co.y) / COS, t_top), min((yb - co.y) / COS, t_ground)
            if ts < te - 1e-6 and lo <= ts <= hi and (best is None or ts < best[0]):
                best = (ts, ts <= t_top + 1e-6, ea)
        if best is None:
            return None
        ts, on_top, edge = best
        return max(ts, 0.0), self.shift(co + VIEW * ts, on_top, edge, sx, su)

    def join_t(self, co):
        """How far along VIEW a point near this slab's north edges moves to meet the slab behind."""
        if not self.join:
            return 0.0
        d = min((_seg_dist(co.xy, a, b) for a, b, n in self.edges if n.y > 0.25), default=9.0)
        w = 1.0 - _smooth(0.0, self.join_width, d)
        if w <= 0.0:
            return 0.0
        ts = [h[0] + h[1] for h in (s.cast(co, 0.0, 4.0) for s in self.join) if h is not None]
        return w * min(ts) if ts else 0.0

    def ramp_t(self, sx, z):
        """How far along VIEW the ramp moves a point of this slab at screen x `sx`, `z` up."""
        if self.ramp is None:
            return 0.0
        x0, x1, height = self.ramp
        return _smooth(x0, x1, sx) * (self.T - height) / SIN * min(1.0, max(0.0, z / self.T))

    def shift(self, X, on_top, edge, sx, su):
        r, T = self.r, self.T
        lam = 0.0
        for a, b, n in self.edges:   # the shoulders along south-facing edges, rounded
            if n.y > -0.25 or r < 0.02:
                continue
            d = b - a
            s = ((X.x - a.x) * d.x + (X.y - a.y) * d.y) / d.length_squared
            if not -0.02 <= s <= 1.02:
                continue
            h0 = (X.x - a.x) * n.x + (X.y - a.y) * n.y
            if h0 <= -r or X.z <= T - r or h0 > 0.05:
                continue
            ch, cz = h0 + r, X.z - (T - r)
            c0 = ch * ch + cz * cz - r * r
            if c0 <= 0:
                continue
            dh, dz = COS * n.y, -SIN   # VIEW across the edge
            qa, qb = dh * dh + dz * dz, 2 * (ch * dh + cz * dz)
            disc = qb * qb - 4 * qa * c0
            if disc >= 0:
                lam = max(lam, (-qb - math.sqrt(disc)) / (2 * qa))
        bulge = -self.dents(sx, su) if self.dents else 0.0
        if on_top:
            dist = min(_seg_dist(X.xy, a, b) for a, b, n in self.edges)
            bulge += self.dome * _smooth(0.0, 1.6, dist)
            bulge += _pillow(self.panels, self.pillow, sx, su) * _smooth(0.0, 0.25, dist)
        elif edge is not None:
            bulge += self.barrel * max(0.0, -edge[2].y) * math.sin(math.pi * min(1.0, max(0.0, X.z / T)))
        return lam - bulge + self.ramp_t(sx, X.z) + (self.join_t(X) if on_top else 0.0)


class Sheet:
    """A thin plate() to bow towards the camera: `on` from plate(), its screen outline and
    thickness; `bow` tiles at the middle across `axis` (a screen direction), panels and dents."""

    def __init__(self, on, outline, thick, bow=0.08, axis=(0.0, 1.0), panels=(), pillow=0.03, dents=None):
        self.o = Vector(on(0, 0, 0))
        self.n = (Vector(on(0, 0, 1)) - self.o).normalized()
        self.outline, self.thick, self.bow = outline, thick, bow
        self.panels, self.pillow, self.dents = list(panels), pillow, dents
        self.ax = Vector(axis).normalized()
        proj = [q[0] * self.ax.x + q[1] * self.ax.y for q in outline]
        self.lo, self.hi = min(proj), max(proj)
        xs, us = [q[0] for q in outline], [q[1] for q in outline]
        self.box = (min(xs) - 0.06, min(us) - 0.06, max(xs) + 0.06, max(us) + 0.06)
        self.ok = abs(self.n.dot(VIEW)) > 0.15   # one seen edge-on can't bow along the ray

    def size_at(self, co):
        return 0.22
    def hit(self, co):
        if not self.ok:
            return None
        sx, su = _scr(co)
        x0, u0, x1, u1 = self.box
        if not (x0 <= sx <= x1 and u0 <= su <= u1):
            return None
        if not any(_inside(self.outline, sx + dx, su + du)
                   for dx, du in ((0, 0), (0.05, 0), (-0.05, 0), (0, 0.05), (0, -0.05))):
            return None
        dn = (co - self.o).dot(self.n)
        if not -self.thick - 0.03 <= dn <= 0.3:
            return None
        q = ((sx * self.ax.x + su * self.ax.y) - self.lo) / max(1e-6, self.hi - self.lo) * 2.0 - 1.0
        bulge = self.bow * max(0.0, 1.0 - q * q) + _pillow(self.panels, self.pillow, sx, su)
        if self.dents:
            bulge -= self.dents(sx, su)
        return max(dn, 0.0), -bulge * _smooth(0.0, 0.3, co.z)   # what touches the ground stays on it


def _lay_rails(f, n, o, u, w, pts, grid, size):
    """The rails inside face `f` (normal n, origin o, axes u, w; its corners `pts` in that
    frame), as 2D pieces at the face's local spacing, clipped to its outline."""
    dn = VIEW.dot(n)
    if abs(dn) < 0.05:
        return []
    xs, us = zip(*(_scr(v.co) for v in f.verts))

    def onto(q):   # the point on the face Factorio's camera shows at screen q
        p0 = Vector(screen(q.x, q.y, 0.0))
        c = p0 + VIEW * ((o - p0).dot(n) / dn)
        return Vector(((c - o).dot(u), (c - o).dot(w))), c
    poly = [(q.x, q.y) for q in pts]
    out = []
    for r0, r1 in grid.near(min(xs), min(us), max(xs), max(us)):
        (a, ca), (b, cb) = onto(r0), onto(r1)
        k = max(1, math.ceil((cb - ca).length / max(0.05, size(f, (ca + cb) / 2))))
        for i in range(k):
            q0, q1 = a.lerp(b, i / k), a.lerp(b, (i + 1) / k)
            ts = [0.0, 1.0]
            for j in range(len(pts)):
                c = _cross(q0, q1, pts[j - 1], pts[j])
                if c:
                    ts.append(min(1.0, max(0.0, c[0])))
            ts.sort()
            for t0, t1 in zip(ts, ts[1:]):
                if t1 - t0 > 1e-6:
                    m = q0.lerp(q1, (t0 + t1) / 2)
                    if _inside(poly, m.x, m.y):
                        out.append((q0.lerp(q1, t0), q0.lerp(q1, t1)))
    return out


def _remesh(p, layer, surfaces, rails=()):
    """Re-triangulates the tagged faces: edges cut to the surface's size_at, and the faces
    Factorio's camera sees filled with points at that spacing (constrained Delaunay), so the
    curves have corners to bend at and the flat parts stay coarse. `rails` (screen polylines,
    _rails()) are laid into the seen faces as edges, cut where they cross the faces' edges so
    neighbouring faces share those points."""
    import bmesh
    from mathutils import geometry
    bm = p.bm
    bm.normal_update()
    faces = [f for f in bm.faces if f[layer] > 0]
    # A slab's south walls take a material of their own (`<paint>_side`, the same paint): once
    # the shoulder is rounded, top and wall are one smooth surface, and the part colours would
    # give it one colour where the sprite has a lit top and a shadowed side.
    for f in faces:
        if isinstance(surfaces[f[layer] - 1], Slab) and abs(f.normal.z) < 0.5 and f.normal.y < 0:
            base = p.mats[f.material_index]
            MATERIALS.setdefault(base + "_side", MATERIALS[base])
            f.material_index = p._mat_index(base + "_side")

    def size(f, co):
        return surfaces[f[layer] - 1].size_at(co)

    def seen(f):
        return f.normal.dot(VIEW) < -0.05
    grid = _Grid(rails)
    for e in list({e for f in faces for e in f.edges}):
        a, b = e.verts[0].co.copy(), e.verts[1].co.copy()
        length = (b - a).length
        if length < 1e-6:
            continue
        cuts, t = [], 0.0   # walked along the edge at the local spacing
        while True:
            q = a.lerp(b, t)
            t += min(size(f, q) for f in e.link_faces if f[layer] > 0) / length
            if t > 1.0 - 0.4 * min(size(f, b) for f in e.link_faces if f[layer] > 0) / length:
                break
            cuts.append(t)
        if rails and any(f[layer] > 0 and seen(f) for f in e.link_faces):
            sa, sb = Vector(_scr(a)), Vector(_scr(b))
            hits = []
            if (sb - sa).length > 1e-4:
                for r0, r1 in grid.near(min(sa.x, sb.x), min(sa.y, sb.y), max(sa.x, sb.x), max(sa.y, sb.y)):
                    c = _cross(sa, sb, r0, r1)
                    if c and 1e-3 < c[0] < 1 - 1e-3:
                        hits.append(c[0])
            if hits:   # the rails' crossings, and no spacing cut crowding them
                gap = 0.35 * min(size(f, a) for f in e.link_faces if f[layer] > 0) / length
                cuts = sorted(set([t for t in cuts if all(abs(t - h) > gap for h in hits)] + hits))
                cuts = [t for i, t in enumerate(cuts) if i == 0 or t - cuts[i - 1] > 1e-4]
        va, cur, tcur = e.verts[0], e.verts[1], 1.0
        for t in reversed(cuts):   # from the far end back
            edge = next(x for x in va.link_edges if x.other_vert(va) is cur)
            cur, tcur = bmesh.utils.edge_split(edge, va, t / tcur)[1], t
    bm.normal_update()
    for f in [f for f in bm.faces if f[layer] > 0]:
        n = f.normal.copy()
        if n.length < 0.5:
            continue
        u = n.orthogonal().normalized()
        w = n.cross(u)
        o = f.verts[0].co.copy()
        ring = list(f.verts)
        pts = [Vector(((v.co - o).dot(u), (v.co - o).dot(w))) for v in ring]
        extra = []
        pieces = _lay_rails(f, n, o, u, w, pts, grid, size) if rails and seen(f) else []
        north = isinstance(surfaces[f[layer] - 1], Slab) and n.y > 0.3 and abs(n.z) < 0.3
        if n.dot(VIEW) < -0.05 or north:   # seen, or a back wall rounded(): points inside at the local spacing
            xs, ys = [q.x for q in pts], [q.y for q in pts]
            poly = [(q.x, q.y) for q in pts]
            for s in (0.1, 0.2, 0.4):
                gx = math.floor(min(xs) / s) * s
                while gx < max(xs):
                    gy = math.floor(min(ys) / s) * s
                    while gy < max(ys):
                        co = o + u * gx + w * gy
                        local = size(f, co)
                        q = Vector((gx, gy))
                        if (local < 2 * s if s == 0.1 else s <= local < 2 * s) and _inside(poly, gx, gy) and \
                                min(_seg_dist(q, pts[i - 1], pts[i]) for i in range(len(pts))) > 0.45 * s and \
                                all(_seg_dist(q, c0, c1) > 0.45 * s for c0, c1 in pieces
                                    if abs(c0.x - gx) < 2 * s + 1 and abs(c0.y - gy) < 2 * s + 1):
                            extra.append(q)
                        gy += s
                    gx += s
        if len(ring) == 3 and not extra and not pieces:
            continue
        coords = pts + extra
        index = {}

        def at(q):   # a rail point's index: the face's own corner there, else one point per place
            near = min(range(len(pts)), key=lambda i: (pts[i] - q).length_squared)
            if (pts[near] - q).length < 2e-3:
                return near
            key = (round(q.x, 5), round(q.y, 5))
            if key not in index:
                index[key] = len(coords)
                coords.append(q)
            return index[key]
        edges = [(at(c0), at(c1)) for c0, c1 in pieces]
        edges = [e for e in edges if e[0] != e[1]]
        out = geometry.delaunay_2d_cdt(coords, edges, [list(range(len(pts)))], 1, 1e-6)
        overts, _, ofaces, oorig = out[0], out[1], out[2], out[3]
        bverts = []
        for i, q in enumerate(overts):
            src = min(oorig[i]) if oorig[i] else None
            if src is not None and src < len(ring):
                bverts.append(ring[src])
            else:
                bverts.append(bm.verts.new(o + u * q.x + w * q.y))
        mat, key, smooth = f.material_index, f[layer], f.smooth
        bm.faces.remove(f)
        for tri in ofaces:
            vs = [bverts[i] for i in tri]
            if len(set(vs)) < 3:
                continue
            try:
                nf = bm.faces.new(vs)
            except ValueError:
                continue
            nf.material_index, nf[layer], nf.smooth = mat, key, smooth
            if nf.calc_area() > 0 and (nf.normal_update() or True) and nf.normal.dot(n) < 0:
                nf.normal_flip()


def rounded(p, surfaces, grooves=None):
    """Splits the faces Factorio's camera sees of the queued slabs and sheets into triangles as
    small as their curves need (each surface's size_at), then moves every vertex of the part
    along VIEW as the surface just behind it moves."""
    import bmesh
    bm = p.bm
    layer = bm.faces.layers.int.get("crash_round")
    slab_verts = set()
    rails, middles = _rails(grooves or ())
    if layer is not None:
        _remesh(p, layer, surfaces, rails)
        bm.normal_update()
        slab_verts = {v for f in bm.faces if f[layer] > 0 and isinstance(surfaces[f[layer] - 1], Slab)
                      for v in f.verts}
        owner = {v: surfaces[f[layer] - 1] for f in bm.faces if f[layer] > 0 for v in f.verts}
        back = {}   # the slabs' north walls' vertices
        for f in bm.faces:
            if f[layer] > 0 and isinstance(surfaces[f[layer] - 1], Slab) and f.normal.y > 0.3 and abs(f.normal.z) < 0.3:
                for v in f.verts:
                    back[v] = surfaces[f[layer] - 1]
    else:
        back, owner = {}, {}

    # Islands (each primitive), so a detail lying partly on a face moves as one.
    bm.verts.index_update()
    parent = list(range(len(bm.verts)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    for e in bm.edges:
        a, b = find(e.verts[0].index), find(e.verts[1].index)
        if a != b:
            parent[a] = b
    islands = {}
    for v in bm.verts:
        islands.setdefault(find(v.index), []).append(v)
    unmoved = set(slab_verts)
    for verts in islands.values():
        moves = {}
        for v in verts:
            best = None
            for s in surfaces:
                h = s.hit(v.co)
                if h is not None and (best is None or h[0] < best[0]):
                    best = h
            if best is not None:
                moves[v] = best[1]
                unmoved.discard(v)
        if not moves:
            continue
        if any(v in slab_verts for v in verts):   # a slab: its back stays where it is
            for v, d in moves.items():
                v.co += VIEW * d
            continue
        # Each vertex as the face behind it; what overhangs the face goes as its part on average.
        # Big things (engines, hoses) only touch the faces and stay as they are.
        lo = Vector([min(v.co[i] for v in verts) for i in range(3)])
        hi = Vector([max(v.co[i] for v in verts) for i in range(3)])
        if (hi - lo).length > 1.5 and len(moves) < len(verts):
            continue
        mean = sum(moves.values()) / len(moves)
        for v in verts:
            v.co += VIEW * moves.get(v, mean)
    # The north walls Factorio never shows bulge north too, rounding the hull's back; never so
    # far that they'd rise above the top's north edge in Factorio's picture.
    for v in unmoved:   # a joined slab's north walls go onto the wall behind (hidden there)
        s = owner.get(v)
        if isinstance(s, Slab) and s.join:
            v.co += VIEW * (0.97 * s.join_t(v.co))
    for v, s in back.items():
        if s.join:
            continue
        z = min(max(v.co.z, 0.0), s.T)
        v.co.y += max(0.0, min(s.barrel * 1.5 * math.sin(math.pi * z / s.T), 0.85 * (s.T - z) * COS / SIN))
    for v in unmoved:   # the back, rims and bottom follow a ramp too
        s = owner.get(v)
        if isinstance(s, Slab):
            v.co += VIEW * s.ramp_t(v.co.x, v.co.z)
    bm.normal_update()
    if layer is not None:
        _groove_finish(p, layer, middles)
        bm.faces.layers.int.remove(layer)
    return p


# Plate seams cut as grooves: Factorio's plating has crisp dark seams between clean plates, which
# thin strips standing on the surface couldn't give (too thin for the part colours to keep them
# dark, and a pixel off the sprite's lines when traced by hand). The lines are traced from the
# sprites (trace_seams.py -> crash_seams.py). _remesh() lays each as three rails (its middle and
# both rims, GROOVE_WIDTH apart on the screen) into the faces Factorio's camera sees, as edges of
# their triangulation, so a groove costs a few triangles a step instead of cutting through every
# triangle it crosses; after rounding, _groove_finish() presses the middle GROOVE_DEPTH back along
# the camera's ray into a V-shaped channel and gives its faces a dark material of their own. In
# Factorio's picture the channel lies exactly on the sprite's line.
GROOVE_WIDTH = 0.05
GROOVE_DEPTH = 0.03
MIN_SEAM = 0.2   # tiles: shorter traced lines are scratches and rivet rows
MATERIALS.setdefault("soot_seam", ("221d18", 0.9, 0.3, None, 0))


def _rails(lines, half=GROOVE_WIDTH / 2):
    """Each seam's middle and its two rims (mitred offsets), as screen polylines; and the middles."""
    rails, middles = [], []
    for line in lines:
        L = [Vector(q) for q in line]
        L = [q for i, q in enumerate(L) if i == 0 or (q - L[i - 1]).length > 1e-4]
        if len(L) < 2 or sum((b - a).length for a, b in zip(L, L[1:])) < MIN_SEAM:
            continue
        normals = [Vector((a.y - b.y, b.x - a.x)).normalized() for a, b in zip(L, L[1:])]
        left, right = [], []
        for i, q in enumerate(L):
            ns = normals[max(0, i - 1):i + 1]
            m = sum(ns, Vector((0.0, 0.0))).normalized()
            k = half / max(0.5, m.dot(ns[0]))
            left.append(q + m * k)
            right.append(q - m * k)
        rails += [L, left, right]
        middles.append(L)
    return rails, middles


def _cross(p0, p1, q0, q1):
    """Where segments p0-p1 and q0-q1 cross: (t along p, s along q), or None."""
    d, e = p1 - p0, q1 - q0
    den = d.x * e.y - d.y * e.x
    if abs(den) < 1e-12:
        return None
    w = q0 - p0
    t, s = (w.x * e.y - w.y * e.x) / den, (w.x * d.y - w.y * d.x) / den
    return (t, s) if -1e-9 <= t <= 1 + 1e-9 and -1e-9 <= s <= 1 + 1e-9 else None


class _Grid:
    """Screen segments bucketed by 0.5-tile cells, for quick lookups by box."""

    def __init__(self, polylines):
        self.cells = {}
        for line in polylines:
            for a, b in zip(line, line[1:]):
                for cx in range(math.floor(min(a.x, b.x) * 2), math.floor(max(a.x, b.x) * 2) + 1):
                    for cy in range(math.floor(min(a.y, b.y) * 2), math.floor(max(a.y, b.y) * 2) + 1):
                        self.cells.setdefault((cx, cy), []).append((a, b))

    def near(self, x0, y0, x1, y1):
        out = {}
        for cx in range(math.floor(x0 * 2), math.floor(x1 * 2) + 1):
            for cy in range(math.floor(y0 * 2), math.floor(y1 * 2) + 1):
                for seg in self.cells.get((cx, cy), ()):
                    out[id(seg)] = seg
        return list(out.values())


def _groove_finish(p, layer, middles, half=GROOVE_WIDTH / 2, depth=GROOVE_DEPTH):
    """Presses the grooves _remesh() laid into channels and paints them soot_seam."""
    import numpy as np
    bm = p.bm
    segs = [(a, b) for line in middles for a, b in zip(line, line[1:])]
    if not segs:
        return
    faces = [f for f in bm.faces if f[layer] > 0 and f.normal.dot(VIEW) < -0.02]
    verts = list({v for f in faces for v in f.verts})
    pts = np.array([_scr(v.co) for v in verts])
    A = np.array([tuple(a) for a, b in segs])
    B = np.array([tuple(b) for a, b in segs])
    dist = np.full(len(verts), 9.0)
    for i in range(0, len(A), 128):   # distance from each vertex to the nearest seam (screen tiles)
        a, ab = A[i:i + 128], B[i:i + 128] - A[i:i + 128]
        t = np.clip(((pts[:, None, :] - a[None]) * ab[None]).sum(-1) / np.maximum((ab * ab).sum(-1), 1e-12)[None], 0, 1)
        q = a[None] + t[..., None] * ab[None]
        dist = np.minimum(dist, np.sqrt(((pts[:, None, :] - q) ** 2).sum(-1)).min(1))
    dmap = dict(zip(verts, dist))
    seam = p._mat_index("soot_seam")
    for f in faces:
        ds = [dmap[v] for v in f.verts]
        if max(ds) <= half + 0.003 and min(ds) < half * 0.5:
            f.material_index = seam
    for v, dv in dmap.items():
        if dv < half:   # never into the ground
            v.co += VIEW * min(depth * (1.0 - dv / half), max(0.0, v.co.z) / SIN)
    bm.normal_update()


def _tag(p, n0, key):
    """Marks the faces added since the part had `n0` as surface number `key` - 1 of rounded()."""
    layer = p.bm.faces.layers.int.get("crash_round") or p.bm.faces.layers.int.new("crash_round")
    p.bm.faces.ensure_lookup_table()
    for i in range(n0, len(p.bm.faces)):
        p.bm.faces[i][layer] = key


def slab(p, outline, mat, thick, surfaces, bevel=0.0, **kw):
    """plate() a flat slab and queue it for rounded(); returns plate()'s `on` and the Slab."""
    n0 = len(p.bm.faces)
    on = plate(p, outline, mat, thick=thick, bevel=bevel)
    _tag(p, n0, len(surfaces) + 1)
    s = Slab(outline, thick, **kw)
    surfaces.append(s)
    return on, s


def sheet(p, outline, mat, surfaces, bow=0.08, axis=(0.0, 1.0), dents=None, panels=(), pillow=0.03, **kw):
    """plate() a thin plate and queue it to be bowed by rounded(); returns plate()'s `on` and the Sheet."""
    n0 = len(p.bm.faces)
    on = plate(p, outline, mat, **kw)
    _tag(p, n0, len(surfaces) + 1)
    s = Sheet(on, outline, kw.get("thick", 0.1), bow=bow, axis=axis, dents=dents, panels=panels, pillow=pillow)
    surfaces.append(s)
    return on, s


def box_of(outline):
    xs, us = [q[0] for q in outline], [q[1] for q in outline]
    return (min(xs), min(us), max(xs), max(us))


@model("crash-site-chest-1")
def chest_1():
    """The longer cargo pod lying east-west, tapering to the east, its hatch at the west end turned
    a little towards the camera."""
    p = Part()
    pod(p, screen(-0.46, -0.17, 0.48), screen(0.68, -0.06, 0.3), 0.48, 0.3)
    return p


@model("crash-site-chest-2")
def chest_2():
    """The shorter, fatter pod lying from the north-west, its hatch to the south-east."""
    p = Part()
    pod(p, screen(0.36, -0.31, 0.47), screen(-0.49, 0.06, 0.38), 0.47, 0.38)
    return p


@model("crash-site-spaceship-wreck-small-1")
def wreck_small_1():
    """A torn hull plate bent in two, its rusty foot standing in the ground and its grey top
    leaning back, a strip of lattice frame across it and a loose bar lying to the north-west."""
    p = Part()
    o = OUTLINES["small-1"]
    plate(p, o["rod"], "steel_light", thick=0.05)
    sf = []
    foot, _ = sheet(p, o["lower"], "rust_brown", sf, bow=0.05, axis=(1.0, 0.3), tilt=85.0, yaw=18.0, thick=0.08,
                    dents=Dents(41, box_of(o["lower"]), 3, 0.03))
    top, _ = sheet(p, o["upper"], "paint_grey", sf, bow=0.08, axis=(1.0, 0.6), tilt=45.0, yaw=18.0, thick=0.08,
                   at=foot(0.05, -0.06), dents=Dents(42, box_of(o["upper"]), 3, 0.03))
    a0, a1 = foot(-0.62, -0.5, 0.06), foot(0.32, -0.1, 0.06)
    b0, b1 = foot(-0.55, -0.64, 0.06), foot(0.36, -0.24, 0.06)
    p.beam(a0, a1, 0.04, 0.04, "steel_scorched")
    p.beam(b0, b1, 0.04, 0.04, "steel_scorched")
    for k in range(9):
        t0, t1 = k / 9, (k + 1) / 9
        p.beam([a0[i] + (a1[i] - a0[i]) * t0 for i in range(3)], [b0[i] + (b1[i] - b0[i]) * t1 for i in range(3)],
               0.025, 0.025, "steel_scorched")
    # The grey top's seams and torn edge, the foot's scorched rivet line.
    seams(p, top, [[(-0.5, 0.33), (0.35, 0.05)], [(0.0, 0.7), (0.15, 0.1)]], rivets=0.12)
    seams(p, foot, [[(-0.6, -0.3), (0.6, -0.05)], [(-0.2, -0.8), (0.6, -0.55)]], rivets=0.14)
    rounded(p, sf)
    densify(p, 0.1)
    return p


@model("crash-site-spaceship-wreck-small-2")
def wreck_small_2():
    """A thick chunk of hull lying in the dirt, a torn hatch in its top, its plates' seams and a
    fleck of the yellow paint left at its west end."""
    p = Part()
    sf = []
    chunk = OUTLINES["small-2"]["chunk"]
    on, _ = slab(p, chunk, "paint_grey", 0.42, sf, bevel=0.03, r=0.22, dome=0.08, barrel=0.06,
                 dents=Dents(43, box_of(chunk), 4, 0.04))
    p.prism([on(*q)[:2] for q in ((0.24, -0.27), (0.42, -0.2), (0.4, -0.08), (0.22, -0.13))], 0.42, 0.43,
            "steel_scorched")
    p.beam(on(0.22, -0.13, 0.04), on(0.4, -0.08, 0.1), 0.18, 0.03, "steel_light")   # the hatch's bent lid
    seams(p, on, [[(-0.55, -0.15), (0.2, -0.05)], [(-0.15, -0.45), (-0.05, -0.05)], [(0.2, -0.3), (0.5, -0.1)]],
          rivets=0.1)
    p.poly([on(x, u, 0.015) for x, u in ((-0.7, -0.27), (-0.5, -0.4), (-0.42, -0.12), (-0.6, -0.12))],
           "wreck_yellow", thick=0.01)
    rounded(p, sf)
    densify(p, 0.1)
    return p


@model("crash-site-spaceship-wreck-small-3")
def wreck_small_3():
    """Scattered pieces: a fat ribbed duct curled round on the ground, a flat bracket with its
    hub, a curved cowling standing up, a block of hull and a short bellows."""
    import space_kit
    p = Part()
    o = OUTLINES["small-3"]
    sf = []
    sheet(p, o["shroud"], "steel_light", sf, bow=0.12, axis=(1.0, 0.0), tilt=70.0, thick=0.08)
    blk, _ = slab(p, o["block"], "paint_grey", 0.25, sf, bevel=0.03, r=0.14, dome=0.05, barrel=0.04,
                  dents=Dents(44, box_of(o["block"]), 2, 0.03))
    seams(p, blk, [[(0.55, 0.5), (0.95, 0.85)], [(0.75, 0.48), (1.1, 0.75)]])
    plate(p, o["mid"], "steel_burnt", thick=0.1)
    # Under the duct, the dark ground of its shadowed coils (the hose's outline).
    plate(p, o["hose"], "steel_scorched", tilt=25.0, thick=0.1)
    space_kit.hose(p, [screen(x, u, 0.18) for x, u in ((-0.82, -0.66), (-0.74, -0.4), (-0.52, -0.3), (-0.3, -0.36),
                                                    (-0.15, -0.42))],
                   0.138, "steel_light", segs=10, rib=0.07, depth=0.12, smooth=4)
    space_kit.hose(p, [screen(0.9, 0.06, 0.12), screen(1.12, 0.36, 0.12)], 0.136, "steel_light", segs=8, rib=0.06,
                   depth=0.15)
    p.cyl(screen(-0.05, -0.2, 0.12), 0.08, 0.06, "steel_burnt", segs=10)   # the bracket's hub
    rounded(p, sf)
    return p


@model("crash-site-spaceship-wreck-small-4")
def wreck_small_4():
    """A hull rib torn out and bent over, lying tilted: its flange round the outside, its web
    with lightening holes inside."""
    p = Part()
    o = OUTLINES["small-4"]["frame"]
    sf = []
    on, _ = sheet(p, o, "rust_brown", sf, bow=0.07, axis=(1.0, 1.0), tilt=35.0, thick=0.08,
                  dents=Dents(45, box_of(o), 3, 0.03))
    # The flange's inner edge: a dark line inside the rib's long outer edge.
    seams(p, on, [[(0.6, -0.4), (0.9, -0.15), (0.98, 0.1), (0.5, 0.5), (0.0, 0.85), (-0.4, 0.78), (-0.78, 0.3)]],
          width=0.04, out=0.01)
    for x, u in ((0.1, 0.75), (0.55, 0.42), (0.85, 0.1)):   # lightening holes
        c = Vector(on(x, u, 0.012))
        p.cyl(tuple(c), 0.07, 0.01, "steel_scorched", segs=10, matrix=None)
    rounded(p, sf)
    densify(p, 0.1)
    return p


@model("crash-site-spaceship-wreck-small-5")
def wreck_small_5():
    """A yellow panel lying tilted, a ram on its mounting and a bent rib standing on it, a torn
    bracket beside it to the east; the panel's seams and a recessed plate on it."""
    p = Part()
    o = OUTLINES["small-5"]
    sf = []
    on, _ = sheet(p, o["panel"], "wreck_yellow", sf, bow=0.08, axis=(1.0, 0.2), tilt=15.0, thick=0.18,
                  dents=Dents(46, box_of(o["panel"]), 3, 0.03))
    # The two dark seams the sprite draws across it, and the bare silver plate at its west tip.
    seams(p, on, [[(-0.55, 0.29), (-0.1, 0.02)], [(-0.27, -0.06), (0.24, 0.03)]], width=0.05, rivets=0.1,
          strips=False)
    p.poly([on(x, u, 0.02) for x, u in ((-0.84, 0.26), (-0.75, 0.18), (-0.47, 0.29), (-0.55, 0.37))],
           "steel_light", thick=0.02)
    plate(p, o["rib"], "wreck_metal", tilt=80.0, thick=0.06)
    plate(p, o["frag"], "steel_burnt", tilt=80.0, thick=0.06)
    p.tube(screen(-0.47, 0.5, 0.3), screen(-0.1, 0.84, 0.45), 0.09, "steel_light", segs=10)
    p.tube(screen(-0.5, 0.45, 0.28), screen(-0.38, 0.55, 0.32), 0.11, "steel_burnt", segs=10)   # its collar
    p.sphere(screen(-0.07, 0.87, 0.47), 0.1, "steel_light", segs=10, rings=5)
    rounded(p, sf, grooves=SEAMS["small-5"])
    densify(p, 0.09)
    return p


@model("crash-site-spaceship-wreck-small-6")
def wreck_small_6():
    """A yellow fin plate lying almost flat, the seams and recessed lines of its skin as the
    sprite draws them."""
    p = Part()
    sf = []
    fin = OUTLINES["small-6"]["fin"]
    on, _ = sheet(p, fin, "wreck_yellow", sf, bow=0.07, axis=(0.5, 1.0), tilt=8.0, thick=0.1,
                  dents=Dents(47, box_of(fin), 3, 0.03))
    seams(p, on, [[(0.22, 0.02), (0.5, -0.08), (1.12, -0.5)], [(0.15, -0.12), (0.95, -0.6)],
                  [(0.6, 0.1), (0.95, -0.12)], [(0.98, 0.0), (1.2, -0.12)]], rivets=0.12, strips=False)
    p.beam(on(0.1, 0.2, 0.01), on(0.1, -0.15, 0.01), 0.04, 0.03, "steel_scorched")   # the tear between plates
    rounded(p, sf, grooves=SEAMS["small-6"])
    densify(p, 0.09)
    return p


@model("crash-site-spaceship-wreck-medium-1")
def wreck_medium_1():
    """A radiator block lying on its back: a thick rusty frame round a deep opening, two rows of
    cooling fins standing in it."""
    p = Part()
    o = OUTLINES["medium-1"]["block"]
    hole = [(-0.88, 0.45), (-0.55, 0.78), (0.05, 0.82), (0.45, 0.55), (0.42, 0.05), (0.1, -0.18), (-0.5, -0.12),
            (-0.85, 0.2)]
    # The frame: the block's outline with the opening cut out, as two halves (cut from the
    # opening's west and east corners to the outline), so the fins inside show as the sprite
    # draws them.
    def area(q):
        return sum(q[i - 1][0] * q[i][1] - q[i][0] * q[i - 1][1] for i in range(len(q)))
    h = hole if area(hole) * area(o) > 0 else hole[::-1]   # both the same way round
    hw, he = h.index(hole[0]), h.index(hole[3])

    def near(q):
        return min(range(len(o)), key=lambda i: (o[i][0] - q[0]) ** 2 + (o[i][1] - q[1]) ** 2)

    def walk(poly, a, b, step):
        out, i = [poly[a]], a
        while i != b:
            i = (i + step) % len(poly)
            out.append(poly[i])
        return out
    iw, ie = near(h[hw]), near(h[he])
    sf = []
    for k, (a, b, c, d) in enumerate(((iw, ie, he, hw), (ie, iw, hw, he))):
        half = walk(o, a, b, 1) + walk(h, c, d, -1)
        slab(p, half, "steel_burnt", 0.42, sf, r=0.2, dome=0.05, barrel=0.06,
             dents=Dents(48 + k, box_of(half), 3, 0.03))
    floor = plate(p, hole, "steel_scorched", thick=0.12)
    for row, (u, x0, x1) in enumerate(((0.4, -0.6, 0.1), (0.1, -0.4, 0.26))):
        for k in range(7):
            x = x0 + (x1 - x0) * k / 6
            c = Vector(floor(x, u))
            p.box((c.x, c.y, 0.2), (0.05, 0.24, 0.16), "steel_light", rz=12.0 + row * 6)
    rounded(p, sf)
    return p


@model("crash-site-spaceship-wreck-medium-2")
def wreck_medium_2():
    """One engine torn off and lying on its tail: a bulging egg-shaped cowling, its intake and
    turbine blades turned up towards the camera, a stub of its mount to the east."""
    p = Part()
    n = Vector((0.35, -0.45, 0.82)).normalized()
    across = (Vector((1, 0, 0)) - n * n.x).normalized()
    frame = Matrix((across, n.cross(across), n)).transposed().to_4x4()
    centre = Vector(screen(-0.12, -0.18, 0.76))
    # The cowling: an egg open at its front round the intake (a closed one would cap the throat).
    import space_kit
    prof = [(math.sin(math.radians(a)), math.cos(math.radians(a))) for a in (180 - 12.5 * k for k in range(13))]
    space_kit.lathe(p, (0, 0, 0), [(0.0, -1.0)] + prof[1:], "rust_light", segs=24,
                    matrix=T(*centre) @ frame @ Matrix.Diagonal((0.93, 0.75, 0.73, 1.0)))
    intake(p, centre + n * 0.68, n, 0.55, blades=28, back=0.0)
    p.cyl((0, 0, 0), 0.07, 0.3, "steel_burnt", segs=8, axis="X", matrix=T(*screen(0.85, -0.25, 0.6)))
    densify(p, 0.12)
    return p


@model("crash-site-spaceship-wreck-medium-3")
def wreck_medium_3():
    """A wing panel torn off and leaning back, its riveted yellow skin with a recessed panel and
    the bare steel leading edge towards the camera, a bent flap at its foot."""
    p = Part()
    sf = []
    wing = OUTLINES["medium-3"]["wing"]
    on, _ = sheet(p, wing, "wreck_yellow", sf, bow=0.14, axis=(1.0, 0.0), tilt=40.0, thick=0.1,
                  dents=Dents(50, box_of(wing), 4, 0.035))
    p.beam(on(-0.86, 1.62, 0.02), on(-0.93, -0.5, 0.02), 0.14, 0.06, "paint_grey")
    seams(p, on, [[(-0.75, 1.15), (0.2, 0.88)], [(-0.8, 0.2), (-0.45, 0.1)], [(0.25, 0.1), (0.55, 0.05)],
                  [(-0.75, -0.3), (-0.45, -0.25)]], rivets=0.12, strips=False)
    p.prism([(-0.7, -0.3), (0.05, -0.55), (0.1, -0.35), (-0.65, -0.1)], 0.0, 0.05, "wreck_yellow",
            matrix=T(*on(-0.3, -0.75, 0.04)) @ R("X", 20.0) @ T(0.3, 0.3, 0))
    rounded(p, sf, grooves=SEAMS["medium-3"])
    densify(p, 0.13)
    return p


@model("crash-site-spaceship-wreck-big-1")
def wreck_big_1():
    """A tail fin standing in the ground facing the camera on its root fairing, a stub with a red
    navigation light reaching west; the recessed channel down its face and its riveted seams."""
    p = Part()
    o = OUTLINES["big-1"]
    sf = []
    root, _ = sheet(p, o["root"], "wreck_yellow", sf, bow=0.12, axis=(0.0, 1.0), tilt=90.0, thick=0.55)
    on, _ = sheet(p, o["fin"], "wreck_yellow", sf, bow=0.1, axis=(1.0, 0.0), tilt=90.0, thick=0.2,
                  at=(0.0, -0.85, 0.0), dents=Dents(51, box_of(o["fin"]), 5, 0.035))
    p.sphere(on(-1.04, -0.08, 0.06), 0.08, "lamp_red", segs=8, rings=4)
    p.tube(on(-0.95, -0.12, 0.1), on(-0.35, -0.05, 0.1), 0.1, "wreck_yellow", segs=10)
    seams(p, on, [[(0.52, 1.95), (0.32, 0.42), (0.95, -0.22), (0.98, -0.6)], [(-0.45, 0.25), (0.05, -0.1),
                                                                              (0.35, -0.55)]],
          width=0.1, mat="steel_scorched", out=0.012)
    seams(p, on, [[(0.6, 1.5), (1.3, 1.4)], [(0.48, 0.95), (1.28, 0.9)], [(1.15, 1.7), (1.12, 0.1)],
                  [(0.35, 0.42), (1.2, 0.18)], [(-0.75, -0.05), (-0.2, -0.35)]], rivets=0.12, strips=False)
    seams(p, root, [[(-0.85, -0.75), (1.38, -0.75)]], rivets=0.15, strips=False)
    rounded(p, sf, grooves=SEAMS["big-1"])
    densify(p, 0.25)
    return p


@model("crash-site-spaceship-wreck-big-2")
def wreck_big_2():
    """Two engine nacelles torn off together, intakes up and to the north-west: thick bare-metal
    lips round open throats with their blades, blue-grey steel noses, then the yellow cowling with
    its riveted plates and a bent brace across it."""
    p = Part()
    sf = []
    hull = OUTLINES["big-2"]["hull"]
    on, _ = slab(p, hull, "wreck_yellow", 0.8, sf, bevel=0.04, r=0.3, dome=0.15, barrel=0.14, coarse=3.0,
                 dents=Dents(52, box_of(hull), 5, 0.04))
    seams(p, on, [[(0.0, -0.6), (0.8, 0.2)], [(-0.4, 0.0), (0.55, 0.85)], [(0.35, -0.3), (1.1, -0.2)],
                  [(-0.9, -0.3), (-0.2, -0.6)]], rivets=0.12)
    n = (-0.45, 0.35, 0.82)
    nacelle(p, screen(-0.95, 1.7, 2.0), n, 1.8, 0.6, body=1.15, mat="wreck_yellow", nose=0.75, nose_mat="paint_blue",
            back=0.0)
    nacelle(p, screen(-0.85, 0.72, 1.66), n, 1.5, 0.55, body=1.25, mat="wreck_yellow", nose=0.7,
            nose_mat="paint_blue", back=0.0)
    nv = Vector(n).normalized()
    for f, r in ((Vector(screen(-0.95, 1.7, 2.0)), 0.6 * 1.13), (Vector(screen(-0.85, 0.72, 1.66)), 0.55 * 1.22)):
        disc(p, f - nv * 0.8, nv, r * 1.04, 0.1, "steel_burnt", segs=20)   # the clamp where the nose meets the cowling
    p.beam(screen(0.3, 0.85, 1.6), screen(1.1, -0.1, 0.8), 0.07, 0.07, "steel_light")
    rounded(p, sf)
    densify(p, 0.45)
    return p


@model("crash-site-spaceship")
def spaceship():
    """The crashed ship, lying west-east: two big engines at the west end, the cockpit with its
    red-lit console and tall fin in the middle, a sensor head on the hull, a burst-open tail to
    the east, torn plates, a loose fin and a wing lying round it. Its skin as the sprite draws it:
    yellow panels between dark seams, patch plates over some, the belly's worn zig-zag bands.
    Where the hull has burst the sprite shows its insides, and so does the model: grey machinery,
    grilles and pipes under the cockpit round the red-lit core, black ribbed hoses hanging to the
    ground, bent steel straps of the frame arching over the east half's open bays, chains and torn
    mesh, bare-metal engine noses."""
    import detail
    import space_kit
    p = Part()
    o = OUTLINES["spaceship"]
    # Open bays in the east half (dark, under the straps) and over the engines' backs.
    bays_e = [[(3.3, -0.1), (4.6, 0.0), (4.6, 1.5), (3.35, 1.45)],
              [(5.45, -0.1), (6.0, 0.0), (6.1, 1.3), (5.5, 1.3)]]
    bay_w = [(-5.38, -0.2), (-4.3, -0.25), (-4.3, 0.7), (-5.38, 0.75)]
    # The hull in three heights: the cockpit's tall west half, the lower east half and the bulging
    # plates along its south side; then the burst tail. The belly west of x -1.05 is the burst
    # bay: grey machinery, not paint.
    seed = 11
    faces = {}
    belly = sorted(pieces(o, "apron"), key=len, reverse=True)
    parts = [("hull_w", q, "wreck_yellow", 2.6) for q in pieces(o, "hull_w")]
    parts += [("hull_e", q, "wreck_yellow", 2.0) for q in pieces(o, "hull_e")]
    parts += [("apron", clip_x(belly[0], -1.05, False), "wreck_yellow", 1.2),
              ("bay", clip_x(belly[0], -1.05, True), "wreck_machine", 0.4)]
    # The bay's floor is low so its machinery shows; the debris spread south of it keeps the
    # outline the tall belly had (its wall reached 0.55 screen tiles further down).
    parts += [("debris", [(x, u - 0.55) for x, u in clip_x(belly[0], -1.05, True)], "wreck_machine", 0.35)]
    parts += [("apron1", q, "wreck_yellow", 0.3) for q in belly[1:]]
    parts += [("tail_e", q, "wreck_yellow", 0.6) for q in pieces(o, "tail_e")]
    # The hull's slabs are rounded at the end (rounded()): shoulders, bulging sides, domed tops,
    # swollen panels and dents, as Factorio's hull is drawn.
    surfaces = []
    # The cockpit half sinks to the east half's height where they meet (ramp), and the belly's
    # top runs up into the hull's side (join): one fuselage, not stacked blocks.
    hulls = []
    rounding = {"hull_w": dict(r=0.6, dome=0.3, barrel=0.3, ramp=(-0.9, 0.98, 2.0)),
                "hull_e": dict(r=0.55, dome=0.3, barrel=0.28),
                "apron": dict(r=0.45, dome=0.2, barrel=0.18, join=hulls, join_width=1.0),
                "apron1": dict(r=0.2, dome=0.06, barrel=0.04), "tail_e": dict(r=0.35, dome=0.12, barrel=0.1)}
    for label, q, mat, thick in parts:
        if label not in rounding:
            faces[label] = plate(p, q, mat, thick=thick)
            continue
        seed += 1
        on, s = slab(p, q, mat, thick, surfaces, dents=Dents(seed, box_of(q), int(4 + thick * 6), 0.06),
                     **rounding[label])
        if label in ("hull_w", "hull_e"):
            hulls.append(s)
        faces[label] = on
        if label in ("hull_w", "hull_e", "apron", "apron1"):
            skip = bays_e if label == "hull_e" else [bay_w] if label == "hull_w" else []
            # The seams are the sprite's own, cut as grooves (rounded()); the panels only swell.
            s.panels = plating(p, on, q, seed, skip=skip, pillows=True, strips=False)
    on, s = sheet(p, o["fin_nw"], "wreck_yellow", surfaces, bow=0.12, axis=(1.0, -0.6), tilt=75.0, thick=0.2,
                  dents=Dents(31, box_of(o["fin_nw"]), 5, 0.04))
    s.panels = plating(p, on, o["fin_nw"], 3, col=(0.35, 0.6), row=(0.3, 0.55), pillows=True, strips=False)
    # The fin's bare-metal panel with its circuit-like raised lines (the sprite's grey inset).
    p.poly([on(x, u, 0.03) for x, u in ((-7.6, 2.3), (-6.5, 1.55), (-5.3, 1.95), (-6.4, 3.0), (-7.2, 3.3))],
           "wreck_metal", thick=0.02)
    on, s = sheet(p, o["fin_mid"], "wreck_yellow", surfaces, bow=0.1, axis=(1.0, 0.0), tilt=80.0, thick=0.2,
                  at=screen(-3.0, 2.0, 2.4), dents=Dents(32, box_of(o["fin_mid"]), 4, 0.04))
    s.panels = plating(p, on, o["fin_mid"], 4, col=(0.4, 0.7), row=(0.3, 0.6), pillows=True, strips=False)
    for a, b in (((-3.3, 3.8), (-3.2, 2.4)), ((-3.2, 2.4), (-2.3, 2.3)), ((-2.6, 3.7), (-2.3, 2.3))):
        p.beam(on(*a, 0.04), on(*b, 0.04), 0.07, 0.03, "steel_scorched")   # its dark inset frame
    on, s = sheet(p, o["radar"], "steel_light", surfaces, bow=0.16, axis=(1.0, 0.0), tilt=80.0, thick=0.15,
                  at=screen(1.0, 2.6, 2.0))
    plating(p, on, o["radar"], 5, col=(0.3, 0.5), row=(0.25, 0.4), patch=0.0, seam="steel_burnt", pillows=True)
    for k in range(9):   # the sensor head's comb
        p.beam(on(0.5 + k * 0.15, 2.62, 0.02), on(0.5 + k * 0.15, 2.45, 0.12), 0.03, 0.03, "steel_burnt")
    for label, mat, tilt in (("wing_s", "wreck_yellow", 8.0), ("debris_sw", "wreck_metal", 20.0),
                             ("debris_s", "steel_burnt", 0.0)):
        for q in pieces(o, label):
            if label == "wing_s" and len(q) > 12:
                on, s = sheet(p, q, mat, surfaces, bow=0.07, axis=(0.7, 0.7), tilt=tilt, thick=0.12,
                              dents=Dents(33, box_of(q), 5, 0.04))
                s.panels = plating(p, on, q, 6, col=(0.4, 0.8), row=(0.3, 0.6), pillows=True, strips=False)
                p.poly([on(x, u, 0.03) for x, u in ((-1.7, -6.0), (-0.9, -6.0), (-0.8, -5.55), (-1.6, -5.6))],
                       "wreck_metal", thick=0.02)
            else:
                plate(p, q, mat, tilt=tilt, thick=0.12)

    # The two engines, intakes to the west-south-west: bare-metal noses, then yellow cowlings
    # banded with riveted plates, grey rods along their backs.
    n = Vector((-0.72, -0.65, 0.0)).normalized()
    for front, length in ((screen(-8.35, -0.3, 1.25), 3.4), (screen(-6.9, -1.75, 1.15), 2.4)):
        nacelle(p, front, n, length, 0.8, body=1.4, blades=24, nose=1.2)
        f = Vector(front)
        for t in (0.45, 0.9, 1.4, 1.9):
            if t < length - 0.2:
                disc(p, f - n * t, n, 0.8 * 1.4 * 1.03 + 0.01, 0.1, "steel_burnt", segs=20)
        for t in (0.9, 1.4):   # rivet rows round the bands
            for k in range(12):
                q = Matrix.Rotation(math.radians(30.0 * k), 3, n) @ Vector((0, 0, 1))
                if q.z > -0.6:   # none under the cowling, in the ground
                    p.sphere(tuple(f - n * t + q * 1.16), 0.03, "steel_light", segs=5, rings=3)
    for a, b in (((-6.9, 0.55, 2.2), (-4.6, 0.95, 2.3)), ((-6.6, 0.25, 2.0), (-4.5, 0.6, 2.1)),
                 ((-5.8, -0.35, 1.9), (-4.4, 0.1, 2.0))):
        p.tube(screen(*a), screen(*b), 0.05, "wreck_metal", segs=6)
    on = faces["hull_w"]
    p.poly([on(x, u, 0.01) for x, u in bay_w], "wreck_machine", thick=0.01)
    mesh_net(p, on, -4.9, -4.35, 0.0, 0.65, out=0.05)

    # The burst side under the cockpit: dark innards round the red-lit core, the frame's broken
    # ribs, a lattice girder across the glow and the spring beside it.
    inside = plate(p, [(-3.45, -1.25), (-1.3, -1.25), (-1.3, 0.55), (-3.45, 0.5)], "steel_scorched", tilt=90.0,
                   thick=0.05, at=(0.0, -1.45, 0.0))
    p.sphere(inside(-2.6, -0.8, 0.05), 0.45, "lamp_red", segs=14, rings=7, scale=(1.0, 0.45, 1.1))
    for k in range(5):
        x = -3.2 + k * 0.4
        p.beam(inside(x, -1.2, 0.1), inside(x + 0.1, 0.3, 0.12), 0.06, 0.05, "steel_burnt")
    for k in range(7):
        p.tube(inside(-2.7, -1.0 + k * 0.1, 0.12), inside(-2.7, -1.0 + k * 0.1, 0.32), 0.3,
               "steel_scorched", segs=12, caps=False)
    detail.girder(p, inside(-3.25, -0.55, 0.45), inside(-2.2, -1.1, 0.45), 0.18, 0.14, "wreck_metal", up=(0, -1, 0))
    detail.girder(p, inside(-3.0, -1.05, 0.4), inside(-2.3, -0.5, 0.4), 0.14, 0.12, "wreck_metal", up=(0, -1, 0))
    # The machinery at the core's foot, between it and the bay's floor.
    detail.panelled(p, (-3.45, -1.9, 0.0), (-1.3, -1.45, 0.72), "wreck_machine", plate="wreck_metal", faces=("-y",),
                    split=3)
    detail.spring(p, inside(-3.25, 0.85, 0.3), inside(-3.25, -0.3, 0.3), 0.1, "wreck_metal", turns=11, wire=0.022)
    # The belly's burst bay: a grey housing with its grille and a pump drum by it, pipes and
    # black ribbed hoses hanging to the ground; a bent yellow plate standing up at its west end.
    bay = faces["bay"]
    lo, hi = (-4.6, -5.0, 0.4), (-3.25, -4.2, 1.4)
    detail.panelled(p, lo, hi, "wreck_machine", plate="wreck_metal", faces=("-y", "+z"), rivet="steel_light")
    detail.slots(p, (lo[0] + 0.05, lo[1], 0.5), (lo[0] + 0.65, hi[1], 1.3), "-y", 7, mat="steel_scorched", depth=0.04)
    c = Vector(screen(-2.6, -3.15, 0.82))
    detail.ribbed_drum(p, (c.x, c.y + 0.15, 0.82), 0.42, 1.0, "wreck_machine", "steel_burnt", axis="X", ribs=4)
    for x, u, s in ((-2.2, -1.9, (0.5, 0.4, 0.5)), (-1.6, -1.7, (0.4, 0.5, 0.7)), (-3.0, -2.0, (0.45, 0.35, 0.4))):
        c = bay(x, u, s[2] / 2)
        p.box(c, s, "wreck_machine", bevel=0.03)   # housings and pumps round the core
        p.box((c[0], c[1] - s[1] / 2, c[2]), (s[0] * 0.7, 0.03, s[2] * 0.6), "steel_scorched")
    plate(p, [(-4.75, -2.45), (-3.7, -2.35), (-3.6, -0.95), (-4.2, -0.8), (-4.75, -1.15)], "wreck_yellow",
          tilt=78.0, yaw=-12.0, thick=0.08, at=bay(-4.2, -2.3, 0.1))
    for pts, r in (([(-4.62, -3.9, 0.05), (-4.68, -3.0, 0.6), (-4.5, -1.9, 1.2)], 0.05),
                   ([(-3.0, -2.35, 1.25), (-1.8, -2.45, 1.25), (-1.3, -2.2, 1.3), (-1.1, -1.3, 1.6),
                     (-1.3, -0.6, 2.0)], 0.06)):
        space_kit.bent(p, [screen(*q) for q in pts], r, "wreck_metal", segs=6)
    for pts, r in (([bay(-1.25, -2.3, 0.1), screen(-1.0, -3.0, 0.7), screen(-0.95, -4.05, 0.14)], 0.13),
                   ([bay(-1.6, -2.5, 0.1), screen(-1.55, -3.4, 0.5), screen(-1.9, -4.0, 0.15),
                     screen(-2.3, -4.15, 0.15)], 0.12),
                   ([bay(-2.0, -2.0, 0.1), screen(-2.1, -2.8, 0.9), screen(-2.4, -3.7, 0.3)], 0.09)):
        space_kit.hose(p, pts, r, "rubber", rib=0.09, depth=0.18, smooth=5)
    # The beak-shaped plate jutting south-west from under the cockpit.
    on, s = sheet(p, [(-3.0, 0.2), (-0.55, 0.55), (-0.45, 0.0), (-1.6, -0.4), (-2.55, -0.9), (-2.95, -0.7)],
                  "wreck_yellow", surfaces, bow=0.12, axis=(0.3, 1.0), tilt=30.0, thick=0.12,
                  at=screen(-1.8, 0.0, 2.15), dents=Dents(34, (-3.0, -0.9, -0.45, 0.55), 3, 0.04))
    p.beam(on(-2.9, 0.1, 0.07), on(-0.6, 0.45, 0.07), 0.05, 0.02, "steel_scorched")
    p.beam(on(-2.8, -0.65, 0.07), on(-1.6, -0.3, 0.07), 0.05, 0.02, "steel_scorched")

    # The belly's worn zig-zag bands of bare metal, stitched with rivets.
    on = faces["apron"]
    for band in ([(-0.05, -3.95), (0.3, -3.2), (0.95, -2.7), (1.9, -2.65), (2.2, -2.2)],
                 [(0.1, -4.2), (0.6, -3.6), (1.05, -3.15), (1.9, -3.1), (2.35, -2.6)]):
        for a, b in zip(band, band[1:]):
            p.beam(on(*a, 0.02), on(*b, 0.02), 0.14, 0.025, "wreck_metal")
            for t in (0.25, 0.5, 0.75):
                q = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
                p.sphere(on(*q, 0.045), 0.025, "steel_scorched", segs=5, rings=3)

    # The east half: dark open bays with torn mesh, the frame's bent steel straps arching over
    # them, chains hanging from the burst side, round tanks among the plates.
    on = faces["hull_e"]
    for q in bays_e:
        p.poly([on(x, u, 0.01) for x, u in q], "steel_scorched", thick=0.01)
    mesh_net(p, on, 3.4, 4.5, 0.0, 1.4, out=0.08)
    tail = faces["tail_e"]
    mesh_net(p, tail, 6.2, 7.15, -0.5, 0.35, out=0.05)
    for pts in ([(1.6, 1.2, 0.1), (1.8, 1.95, 0.25), (2.05, 2.3, 0.15)],
                [(3.1, 2.3, 0.1), (3.0, 1.7, 0.3), (3.3, 0.9, 0.35), (3.0, 0.0, 0.25), (2.75, -0.8, 0.1)],
                [(4.4, 1.8, 0.1), (5.05, 1.8, 0.2), (5.4, 1.45, 0.3), (5.58, 0.7, 0.3), (5.4, -0.2, 0.3),
                 (5.3, -0.8, 0.15)],
                [(3.7, 1.55, 0.2), (4.5, 1.5, 0.3), (4.4, 0.5, 0.35), (4.1, -0.2, 0.2)],
                [(1.15, 0.4, 0.15), (1.4, -0.3, 0.2), (1.25, -0.95, 0.1)]):
        strap(p, on, pts)
    for face, x, u0 in ((on, 3.85, -0.35), (on, 4.3, -0.6), (tail, 6.6, -0.75)):
        top = face(x, u0, 0.05)
        chain(p, top, (top[0], top[1] - 0.1, max(0.05, top[2] - 0.75)))
    # Under the straps the burst side wall is open too: dark machinery with its gear wheels.
    side = plate(p, [(2.95, -0.45), (4.65, -0.4), (4.65, -1.55), (2.95, -1.6)], "steel_scorched", tilt=90.0,
                 thick=0.03, at=(0.0, -2.14, 0.0))
    for x, u, r in ((3.35, -0.95, 0.28), (4.15, -1.15, 0.22), (3.85, -0.6, 0.15)):
        c = Vector(side(x, u, 0.02))
        disc(p, c, (0, -1, 0), r, 0.06, "wreck_machine", segs=16)
        disc(p, c + Vector((0, -0.04, 0)), (0, -1, 0), r * 0.35, 0.05, "steel_burnt", segs=10)
        for k in range(int(r * 40)):   # teeth
            a = 2 * math.pi * k / int(r * 40)
            p.box((c.x + math.cos(a) * (r + 0.02), c.y, c.z + math.sin(a) * (r + 0.02)), (0.05, 0.05, 0.05),
                  "wreck_machine")
    p.box(tuple(Vector(side(4.4, -0.75, 0.12))), (0.35, 0.2, 0.3), "wreck_machine", bevel=0.02)
    for x, u in ((2.45, 2.15), (2.9, 1.6)):   # domed hatches on the east half's roof
        c = on(x, u, 0.0)
        p.cyl(c, 0.17, 0.05, "steel_burnt", segs=12)
        p.sphere((c[0], c[1], c[2] + 0.02), 0.13, "wreck_metal", segs=10, rings=4, hemisphere=True)
    for x, u in ((1.55, -0.2), (2.35, 0.3)):   # the round yellow tanks low on the burst side
        c = on(x, u, 0.0)
        p.tube((c[0] - 0.38, c[1] - 0.15, c[2] - 0.2), (c[0] + 0.38, c[1] - 0.15, c[2] - 0.2), 0.28,
               "wreck_yellow", segs=12)

    for x, u in ((-2.2, 1.75), (-1.6, 1.7), (-1.0, 1.65)):
        p.sphere(screen(x, u, 2.7), 0.12, "lamp_red", segs=8, rings=4)
    # Domed hatches and a post on the cockpit's roof.
    for x, u in ((-1.95, 1.2), (-0.6, 1.25), (0.45, 1.35)):
        c = screen(x, u, 2.62)
        p.cyl(c, 0.2, 0.06, "steel_burnt", segs=14)
        p.sphere((c[0], c[1], c[2] + 0.03), 0.15, "steel_scorched", segs=12, rings=4, hemisphere=True)
    p.cyl(screen(1.0, 1.5, 2.8), 0.07, 0.4, "steel_light", segs=8)
    # Cables hanging from the burst side and over the hull.
    for k, (a, b) in enumerate((((-1.3, -0.3), (-0.6, -2.4)), ((0.3, -0.2), (0.9, -2.0)),
                                ((2.2, 0.0), (2.6, -1.6)), ((3.5, 0.1), (3.2, -1.4)),
                                ((4.8, 0.3), (5.3, -1.3)))):
        top, foot = screen(a[0], a[1], 2.0), screen(b[0], b[1], 0.05)
        mid = ((top[0] + foot[0]) / 2 + 0.2, (top[1] + foot[1]) / 2 - 0.3, (top[2] + foot[2]) / 2 - 0.3)
        space_kit.bent(p, [top, mid, foot], 0.035 + 0.01 * (k % 2), "rubber", segs=6)
    duct(p, [screen(-1.6, -3.0, 0.3), screen(-1.2, -3.8, 0.26), screen(-0.6, -4.3, 0.24)], 0.2, "rubber")
    rounded(p, surfaces, grooves=SEAMS["spaceship"])
    densify(p, 0.5)
    return p


# The flat pieces' outlines as the sprites show them, in screen tiles (see plate()).
OUTLINES = {
    "small-1": {
        "rod": [(-0.09, 1.03), (-0.11, 1.05), (-0.39, 0.96), (-0.99, 0.47), (-0.98, 0.42), (-0.94, 0.41)],
        "upper": [(0.54, 0.08), (0.4, 0.73), (0.31, 0.85), (0.25, 0.88), (0.16, 0.87), (-0.54, 0.36),
            (-0.6, 0.25), (-0.6, 0.16), (-0.65, 0.09), (-0.66, -0.17), (-0.62, -0.23)],
        "lower": [(0.09, -0.84), (0.23, -0.84), (0.44, -0.79), (0.56, -0.69), (0.61, -0.68), (0.66, -0.71),
            (0.73, -0.62), (0.76, -0.33), (0.71, -0.22), (0.53, 0.02), (-0.61, -0.24), (-0.65, -0.28),
            (-0.62, -0.36), (-0.71, -0.44), (-0.68, -0.48), (-0.69, -0.58), (-0.59, -0.68), (-0.31, -0.79),
            (-0.27, -0.77), (-0.12, -0.85), (0.03, -0.87)],
    },
    "small-2": {
        "chunk": [(0.08, -0.32), (0.19, -0.29), (0.22, -0.3), (0.34, -0.21), (0.47, -0.15), (0.56, -0.15),
            (0.62, -0.09), (0.52, -0.01), (0.28, 0.01), (0.25, 0.04), (-0.09, -0.04), (-0.34, -0.02),
            (-0.42, -0.07), (-0.5, -0.07), (-0.62, -0.15), (-0.73, -0.27), (-0.69, -0.34), (-0.55, -0.43),
            (-0.31, -0.51)],
    },
    "small-3": {
        "shroud": [(0.14, 0.35), (0.18, 0.39), (0.1, 0.53), (0.12, 0.67), (0.05, 0.77), (-0.05, 0.81),
            (-0.15, 0.73), (-0.16, 0.64), (-0.2, 0.61), (-0.18, 0.42), (-0.12, 0.34), (0.08, 0.34)],
        "block": [(0.72, 0.45), (0.77, 0.41), (0.8, 0.46), (0.83, 0.45), (1.02, 0.63), (1.11, 0.65),
            (1.16, 0.7), (1.2, 0.8), (0.95, 0.93), (0.84, 0.9), (0.81, 0.91), (0.78, 0.88), (0.62, 0.88),
            (0.43, 0.47), (0.53, 0.4), (0.58, 0.45), (0.62, 0.45), (0.66, 0.4)],
        "mid": [(-0.01, -0.34), (0.07, -0.3), (0.12, -0.22), (0.12, -0.12), (0.15, -0.05), (0.2, -0.01),
            (0.23, -0.02), (0.3, 0.05), (0.19, 0.15), (0.12, 0.16), (0, 0.13), (-0.06, 0.16), (-0.16, 0.12),
            (-0.17, 0.13), (-0.22, 0.1), (-0.38, 0.07), (-0.4, 0.05), (-0.36, 0.01), (-0.14, 0.02),
            (-0.12, -0), (-0.12, -0.06), (-0.19, -0.16), (-0.31, -0.09), (-0.39, -0.07), (-0.51, -0.11),
            (-0.51, -0.42), (-0.48, -0.45), (-0.05, -0.45)],
        "hose": [(-0.79, -0.75), (-0.76, -0.58), (-0.72, -0.54), (-0.66, -0.59), (-0.58, -0.57),
            (-0.55, -0.54), (-0.48, -0.56), (-0.45, -0.51), (-0.41, -0.57), (-0.3, -0.56), (-0.17, -0.57),
            (-0.02, -0.45), (0.01, -0.3), (-0.16, -0.15), (-0.2, -0.16), (-0.31, -0.09), (-0.55, -0.09),
            (-0.59, -0.15), (-0.66, -0.15), (-0.7, -0.23), (-0.77, -0.25), (-0.79, -0.31), (-0.85, -0.38),
            (-0.85, -0.42), (-0.88, -0.45), (-0.91, -0.7), (-0.83, -0.79)],
    },
    "small-4": {
        "frame": [(0.23, -0.52), (0.28, -0.46), (0.27, -0.52), (0.3, -0.54), (0.38, -0.52), (0.44, -0.46),
            (0.41, -0.53), (0.44, -0.56), (0.5, -0.52), (0.59, -0.56), (0.67, -0.46), (0.82, -0.36),
            (0.88, -0.25), (0.96, -0.19), (1.01, -0.08), (1.1, -0), (1.1, 0.03), (1.07, 0.16), (0.98, 0.27),
            (0.5, 0.63), (0, 0.98), (-0.22, 0.99), (-0.44, 0.9), (-0.62, 0.72), (-0.93, 0.3), (-0.93, 0.2),
            (-0.86, 0.16), (-0.77, 0.3), (-0.69, 0.35), (-0.66, 0.3), (-0.62, 0.34), (-0.52, 0.34),
            (-0.48, 0.31), (-0.52, 0.24), (-0.63, 0.2), (-0.63, 0.12), (-0.71, -0.05), (-0.71, -0.08),
            (-0.67, -0.1), (-0.62, -0.02), (-0.58, -0.07), (-0.52, -0.09), (-0.43, 0.05), (-0.38, 0.22),
            (-0.16, 0.38), (-0.08, 0.38), (-0.02, 0.5), (0.03, 0.56), (0.17, 0.51), (0.34, 0.37), (0.52, 0.27),
            (0.65, 0.14), (0.66, 0.01), (0.63, 0.09), (0.39, 0.3), (0.37, 0.28), (0.37, 0.2), (0.33, 0.16),
            (0.22, 0.23), (0.21, 0.28), (0.25, 0.34), (0.3, 0.34), (0.33, 0.3), (0.35, 0.33), (0.22, 0.43),
            (0.09, 0.27), (0.41, -0), (0.41, -0.09), (0.37, -0.19), (0.12, -0.48), (0.09, -0.55),
            (0.11, -0.57)],
    },
    "small-5": {
        "panel": [(0.36, 0.01), (0.48, 0.01), (0.51, 0.03), (0.45, 0.19), (0.46, 0.33), (0.4, 0.36),
            (0.4, 0.48), (0.48, 0.59), (0.45, 0.62), (0.27, 0.62), (0.22, 0.56), (0.16, 0.54), (0.09, 0.6),
            (0, 0.6), (-0.53, 0.52), (-0.59, 0.41), (-0.77, 0.34), (-0.85, 0.27), (-0.85, 0.23), (-0.81, 0.2),
            (-0.8, 0.21), (-0.77, 0.16), (-0.73, 0.16), (-0.5, 0.01), (-0.34, -0.04), (-0.31, -0.09),
            (0.06, -0.1)],
        "rib": [(0.46, 0.12), (0.45, 0.23), (0.48, 0.3), (0.4, 0.33), (0.4, 0.41), (0.52, 0.61), (0.52, 0.67),
            (0.5, 0.69), (0.41, 0.65), (0.3, 0.63), (0.22, 0.52), (0.17, 0.52), (0.13, 0.48), (0.13, 0.12),
            (0.16, 0.1), (0.44, 0.1)],
        "frag": [(0.66, -0.16), (0.81, 0.06), (0.77, 0.12), (0.89, 0.16), (0.94, 0.23), (0.88, 0.3),
            (0.73, 0.35), (0.66, 0.5), (0.56, 0.56), (0.54, 0.53), (0.54, 0.41), (0.59, 0.27), (0.59, -0.08),
            (0.56, -0.14), (0.61, -0.2)],
    },
    "small-6": {
        "fin": [(1.25, -0.73), (1.45, -0.53), (1.48, -0.45), (1.3, -0.19), (1.17, -0.04), (1.03, -0.07),
            (1.04, -0.03), (0.98, 0.02), (0.89, 0.06), (0.83, 0.12), (0.7, 0.16), (0.53, 0.16), (0.5, 0.23),
            (0.22, 0.21), (0.08, 0.24), (-0.19, 0.2), (-0.22, 0.16), (-0.27, 0.18), (-0.38, 0.12),
            (-0.34, 0.08), (-0.35, -0.05), (-0.31, -0.09), (-0.16, -0.12), (0, -0.21), (0.19, -0.21),
            (0.31, -0.29), (0.32, -0.34), (0.41, -0.41), (1.03, -0.73), (1.2, -0.74)],
    },
    "medium-1": {
        "block": [(-0.02, -0.23), (0.09, -0.15), (0.16, -0.16), (0.19, -0.13), (0.42, -0.15), (0.47, -0.21),
            (0.7, -0.21), (0.83, -0.16), (0.96, -0.03), (1.05, 0.17), (0.36, 1.02), (0.08, 0.94), (0.05, 0.91),
            (-0.02, 0.93), (-0.89, 0.66), (-0.97, 0.62), (-1.12, 0.45), (-1.07, 0.27), (-0.98, 0.11),
            (-0.8, -0.02), (-0.62, -0.23), (-0.38, -0.32)],
    },
    "medium-3": {
        "wing": [(0.41, -1.25), (0.18, -1.06), (0.16, -0.91), (0.35, -0.75), (0.38, -0.67), (0.37, -0.55),
            (0.46, -0.48), (0.51, -0.39), (0.51, -0.3), (0.56, -0.19), (0.54, -0.11), (0.57, -0.06),
            (0.54, 0.09), (0.6, 0.17), (0.59, 0.36), (0.48, 0.58), (0.32, 0.73), (0.3, 0.8), (0.15, 0.91),
            (0.18, 0.95), (0.18, 1.05), (0.14, 1.09), (-0.83, 1.68), (-0.87, 1.64), (-0.9, 1.41),
            (-0.79, 1.08), (-0.77, 0.84), (-0.88, 0.25), (-0.88, -0), (-0.98, -0.53), (-0.31, -0.96),
            (-0.23, -0.99), (-0.2, -0.96), (-0.08, -1.07), (0.23, -1.26), (0.39, -1.3)],
    },
    "big-1": {
        "fin": [(1.4, -0.59), (1.41, -0.36), (1.4, 1.56), (1.3, 1.77), (0.89, 2.13), (0.69, 2.26),
            (0.52, 2.26), (0.38, 2.14), (-0.34, 0.36), (-0.7, -0.06), (-0.92, 0.04), (-1.02, -0.04),
            (-1.06, -0.02), (-1.12, -0.12), (-1.08, -0.2), (-0.87, -0.3), (-0.9, -0.42), (-0.87, -0.45),
            (-0.88, -0.59), (-0.86, -0.62), (1.38, -0.62)],
        "root": [(0.39, -1.12), (0.55, -1.13), (0.77, -1.07), (1.16, -1.07), (1.2, -1.02), (1.33, -1.02),
            (1.38, -0.95), (1.4, -0.47), (1.38, -0.45), (-0.86, -0.45), (-0.88, -0.47), (-0.88, -0.77),
            (-0.85, -0.81), (-0.85, -1), (-0.81, -1.1), (0.05, -1.15)],
    },
    "big-2": {
        "hull": [(0.33, -0.73), (0.42, -0.71), (0.48, -0.66), (0.56, -0.66), (0.62, -0.62), (0.72, -0.63),
            (0.74, -0.61), (0.73, -0.56), (0.8, -0.51), (0.91, -0.46), (1.02, -0.48), (1.05, -0.28),
            (1.09, -0.23), (1.23, -0.16), (1.23, 0.08), (1.12, 0.16), (1.03, 0.12), (0.94, 0.25), (0.71, 0.47),
            (0.71, 0.55), (0.63, 0.66), (0.63, 0.73), (0.69, 0.8), (0.76, 0.95), (0.71, 1), (0.71, 1.08),
            (0.63, 1.19), (0.63, 1.23), (0.44, 1.46), (0.33, 1.51), (0.3, 1.48), (0.4, 1.41), (0.36, 1.41),
            (0.12, 1.65), (-0.09, 1.62), (-0.13, 1.58), (-0.42, 0.74), (-1.27, 0.39), (-1.24, 0.34),
            (-1.26, 0.22), (-1.23, 0.16), (-0.91, -0.33), (-0.73, -0.51), (-0.58, -0.65), (-0.45, -0.71),
            (-0.16, -0.71), (-0.06, -0.74)],
    },
    "spaceship": {
        "fin_nw": [(-4.88, 1.88), (-4.85, 1.92), (-6.85, 3.75), (-6.84, 3.8), (-7.16, 4.15), (-7.2, 4.14),
            (-7.72, 4.84), (-8.09, 4.95), (-8.31, 4.88), (-8.71, 4.56), (-8.8, 4.39), (-8.84, 4.11),
            (-8.77, 3.94), (-7.76, 2.3), (-6.41, 1.49)],
        "fin_mid": [(-1.01, 2.02), (-1.23, 2.52), (-1.32, 2.55), (-2.42, 3.96), (-2.62, 4.05), (-3.27, 4.05),
            (-3.42, 4.01), (-3.54, 3.89), (-3.39, 2.9), (-4.16, 3.18), (-4.53, 3.12), (-4.66, 3.05),
            (-3.77, 2.28), (-3.56, 1.93), (-3.38, 1.93)],
        "radar": [(1.79, 2.81), (2.07, 3.16), (2.13, 3.44), (1.81, 3.91), (1.28, 3.99), (1.08, 3.98),
            (0.63, 3.58), (0.52, 3.16), (0.1, 2.67), (0.16, 2.62), (0.36, 2.6), (1.73, 2.6)],
        "wing_s0": [(-2.6, -5.47), (-2.56, -5.38), (-2.52, -5.16), (-2.58, -5.09), (-2.63, -5.12),
            (-2.69, -5.37), (-3.06, -5.44), (-3, -5.55), (-2.75, -5.57)],
        "wing_s1": [(-1.14, -6.96), (-0.3, -6.09), (-0.26, -5.95), (-0.18, -5.89), (-0.18, -5.78),
            (-0.11, -5.8), (-0.07, -5.77), (-0.07, -5.53), (0.09, -5.36), (0.08, -5.09), (-0.94, -5.09),
            (-0.93, -5.14), (-1.06, -5.23), (-1.67, -5.34), (-1.77, -5.41), (-1.97, -5.41), (-2.22, -5.52),
            (-2.35, -5.64), (-2.6, -6.56), (-2.98, -6.66), (-2.92, -6.76), (-2.52, -6.87), (-1.33, -7.02)],
        "debris_sw0": [(-7.02, -2.85), (-6.84, -2.91), (-6.58, -2.88), (-6.53, -2.93), (-6.25, -2.93),
            (-6.17, -2.85), (-6.09, -2.9), (-5.78, -2.73), (-5.77, -2.66), (-5.45, -2.39), (-5.52, -2.29),
            (-5.83, -2.54), (-5.89, -2.29), (-7.34, -2.29), (-7.42, -2.35), (-7.64, -2.31), (-7.89, -2.43),
            (-8.08, -2.63), (-8.32, -2.72), (-8.28, -2.76), (-8.22, -2.71), (-8.17, -2.74), (-7.97, -2.63),
            (-7.84, -2.9), (-7.55, -3.02), (-7.27, -3.02)],
        "debris_sw1": [(-7.28, -4.4), (-7, -4.41), (-6.73, -4.34), (-6.19, -4.07), (-6.07, -3.95),
            (-5.98, -3.48), (-5.86, -3.43), (-5.79, -3.48), (-5.74, -3.69), (-5.63, -3.86), (-5.42, -3.91),
            (-5.4, -3.8), (-5.54, -3.69), (-5.59, -3.45), (-5.4, -3.36), (-5.4, -3.27), (-5.56, -3.18),
            (-5.62, -3.23), (-5.78, -3.1), (-5.98, -3.13), (-6.03, -3.04), (-6.11, -3.01), (-7.08, -3.02),
            (-7.5, -3.24), (-7.55, -3.21), (-7.59, -3.27), (-7.53, -3.34), (-7.46, -3.31), (-7.4, -3.58),
            (-7.43, -4.06), (-7.52, -4.38), (-7.33, -4.45)],
        "debris_s0": [(0.07, -5.41), (0.1, -5.12), (0.2, -5.06), (0.17, -4.74), (-0.97, -4.74), (-0.96, -4.89),
            (-1.01, -4.94), (-0.94, -5.15), (-1.06, -5.23), (-1.23, -5.24), (-1.25, -5.29), (-1.67, -5.34),
            (-1.77, -5.41), (-1.97, -5.41), (-2.18, -5.52), (-0.06, -5.54)],
        "debris_s1": [(-2.56, -5.39), (-2.52, -5.23), (-2.59, -5.05), (-2.65, -5.31), (-2.73, -5.39),
            (-2.71, -5.52), (-2.66, -5.54)],
        "debris_s2": [(-3.43, -5.47), (-3.61, -5.15), (-3.62, -5.23), (-3.79, -5.27), (-3.62, -5.54),
            (-3.47, -5.54)],
        "tail_e": [(6.11, -1.7), (6.5, -1.7), (7, -1.57), (7.05, -1.6), (7.2, -1.52), (7.2, -1.39),
            (7.01, -1.2), (7.14, -1.16), (7.27, -1.05), (6.93, -0.95), (6.88, -0.67), (7.1, -0.61),
            (6.93, -0.55), (6.87, -0.3), (7.39, -0.13), (7.48, -0.05), (7.45, 0.27), (7.36, 0.43),
            (6.29, 0.55), (6.38, 0.72), (6.41, 0.91), (6.29, 0.95), (6.35, 1.09), (6.23, 1.21), (6.11, 1.21),
            (6.06, 1.16), (6.02, 1.21), (5.93, 1.19), (6.12, 1), (6.13, 0.89), (6.06, 0.76), (5.95, 0.85),
            (5.79, 0.88), (5.79, -0.98), (5.83, -1.05), (5.97, -1.07), (6.05, -1.13), (6.08, -1.1),
            (6.13, -1.16), (5.95, -1.18), (5.89, -1.29), (5.79, -1.3), (5.83, -1.46), (5.97, -1.48),
            (6.05, -1.54), (6.08, -1.51), (6.13, -1.56), (5.95, -1.59), (5.89, -1.7), (5.79, -1.7),
            (5.81, -1.93)],
        "apron0": [(-3.83, -3.77), (-3.27, -3.77), (-3.17, -3.68), (-2.97, -3.66), (-2.58, -3.43),
            (-2.54, -3.48), (-2.71, -3.64), (-2.67, -3.68), (-2.58, -3.69), (-2.39, -3.54), (-2.22, -3.48),
            (-2.2, -3.4), (-2.08, -3.4), (-2.07, -3.55), (-1.88, -3.63), (-1.72, -3.59), (-1.41, -3.32),
            (-1.32, -3.48), (-1.17, -3.62), (-0.85, -3.34), (-0.94, -3.3), (-0.89, -3.23), (-0.62, -3.18),
            (-0.27, -2.84), (-0.18, -3.05), (-0.18, -3.22), (-0.27, -3.27), (-0.56, -3.29), (-0.63, -3.34),
            (-0.61, -3.37), (-0.33, -3.48), (0.31, -3.6), (0.56, -3.76), (0.78, -3.81), (0.92, -3.74),
            (1.03, -3.57), (1.12, -3.55), (1.05, -3.52), (1.06, -3.44), (1.19, -3.46), (1.48, -3.19),
            (1.59, -3.21), (1.66, -3.15), (1.88, -3.09), (2.56, -2.5), (2.84, -1.7), (2.8, -1.66),
            (2.14, -1.65), (2.03, -1.71), (2.02, -1.63), (1.92, -1.68), (1.89, -1.63), (1.73, -1.62),
            (-2.7, -1.35), (-3.03, -1.37), (-3.19, -1.32), (-5.39, -1.2), (-5.41, -1.45), (-5.29, -1.56),
            (-5.24, -1.72), (-5.27, -2.14), (-5.2, -2.21), (-5.11, -2.19), (-5.03, -2.24), (-4.98, -2.36),
            (-5.05, -2.8), (-5.24, -2.97), (-4.98, -3.07), (-4.87, -2.88), (-4.81, -2.65), (-4.68, -2.83),
            (-4.66, -3.06), (-4.51, -3.34), (-4.48, -3.53), (-4.37, -3.59), (-4.23, -3.77), (-3.95, -3.84)],
        "apron1": [(-0.37, -3.77), (-0.75, -3.63), (-2.06, -3.81), (-2.25, -3.57), (-2.4, -3.72),
            (-2.37, -3.77), (-2.48, -3.83), (-2.33, -3.96), (-2.25, -3.96), (-2.14, -3.85), (-1.95, -3.85),
            (-1.84, -3.96), (-1.86, -3.84), (-1.77, -3.84), (-1.75, -3.93), (-1.7, -3.84), (-1.67, -3.88),
            (-1.66, -3.82), (-1.55, -3.81), (-1.55, -3.91), (-1.48, -3.81), (-1.41, -3.91), (-1.43, -3.8),
            (-1.31, -3.77), (-1.31, -3.87), (-1.27, -3.79), (-1.2, -3.88), (-1.11, -3.82), (-1.11, -3.94),
            (-0.61, -3.96)],
        "hull_w": [(0.98, 2.62), (0.66, 2.62), (0.58, 2.32), (0.23, 2.31), (0.56, 2.26), (0.53, 2.18),
            (0.27, 1.99), (-0.67, 1.59), (-0.81, 1.62), (-1.22, 2.56), (-3.66, 2.13), (-3.65, 2.03),
            (-3.49, 1.86), (-3.62, 1.74), (-3.92, 1.7), (-4.11, 1.73), (-4.1, 1.53), (-4.32, 1.39),
            (-4.15, 1.19), (-4.19, 0.76), (-4.64, 0.79), (-5.07, 1.05), (-5.07, 1.5), (-4.78, 1.51),
            (-4.8, 1.62), (-4.73, 1.57), (-4.59, 1.63), (-4.45, 1.62), (-4.43, 1.66), (-4.59, 1.82),
            (-4.81, 2.01), (-5.41, 1.98), (-5.41, 1.52), (-5.23, 1.55), (-5.18, 1.52), (-5.21, 1.11),
            (-5.41, 1.16), (-5.39, -0.27), (-3.5, -0.38), (-3.4, 0.5), (-1.4, 0.55), (-1.3, -0.51), (0.98, -0.65)],
        "hull_e": [(2.91, -0.88), (3.18, -0.73), (3.15, -0.56), (3.19, -0.51), (3.42, -0.41), (3.8, -0.38),
            (4.06, -0.29), (4.36, -0.38), (4.38, -0.11), (4.52, -0.04), (4.67, -0.04), (4.98, -0.34),
            (4.9, -0.56), (5.02, -0.73), (5.58, -0.91), (5.75, -1.04), (5.8, -1.02), (5.8, -0.36),
            (5.28, -0.34), (5.09, -0.14), (5.19, -0.15), (5.2, -0.02), (5.34, 0.02), (5.41, 0.24),
            (5.64, 0.18), (5.8, 0.23), (5.8, 0.89), (5.58, 0.98), (5.57, 1.08), (5.51, 1.11), (5.52, 1.48),
            (5.67, 1.3), (5.8, 1.27), (5.8, 1.52), (5.73, 1.64), (5.73, 1.83), (5.5, 1.9), (5.25, 2.12),
            (5.03, 2.15), (4.64, 1.99), (4.48, 1.99), (4.44, 1.9), (3.84, 1.93), (3.66, 2.32), (3.5, 2.38),
            (3.3, 2.38), (3.23, 2.49), (3.09, 2.56), (2.97, 2.46), (1.88, 2.46), (1.76, 2.72), (1.93, 2.97),
            (1.91, 3.01), (1.02, 3.01), (0.99, -1.03), (2.81, -1.12)],
    },
}
