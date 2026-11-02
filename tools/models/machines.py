"""Furnaces, drills, assemblers and the lab. Directional machines face north (+y): drills drop
their output on the north side. Machines that can't rotate keep their fronts (fire doors and
the like) facing south, towards the default camera, as Factorio's sprites do."""

import math

import bmesh
from mathutils import Vector

from kit import Part, R, S, T, model, rng


def octagon(half, chamfer):
    """Counter-clockwise points of a square with cut corners."""
    h, c = half, chamfer
    return [(h, -h + c), (h, h - c), (h - c, h), (-h + c, h), (-h, h - c), (-h, -h + c), (-h + c, -h), (h - c, -h)]


def stone_course(p, r, half, z0, z1, gap=None, inset=0.0, block=0.36, seed=0):
    """A ring of rough stone blocks around a square of half-size `half`, from z0 to z1.
    `gap` (x0, x1) leaves an opening in the south side."""
    mats = ("stone", "stone", "stone_dark", "stone_light")
    for side in range(4):
        n = max(2, round(2 * half / block))
        width = 2 * half / n
        for i in range(n):
            a = -half + (i + 0.5) * width + (width / 2 if seed % 2 else 0)
            if a > half - width / 4:
                a -= 2 * half
            jit = r.uniform(-0.02, 0.02)
            depth = 0.2 + r.uniform(-0.02, 0.03)
            size_along = width - 0.025
            zt = z1 + r.uniform(-0.02, 0.015)
            mat = mats[r.randrange(len(mats))]
            if side == 0:    # south
                if gap and gap[0] < a < gap[1]:
                    continue
                c, s = (a, -half + depth / 2 - jit + inset), (size_along, depth, zt - z0)
            elif side == 1:  # north
                c, s = (a, half - depth / 2 + jit - inset), (size_along, depth, zt - z0)
            elif side == 2:  # west
                c, s = (-half + depth / 2 - jit + inset, a), (depth, size_along, zt - z0)
            else:            # east
                c, s = (half - depth / 2 + jit - inset, a), (depth, size_along, zt - z0)
            p.box((c[0], c[1], (z0 + zt) / 2), s, mat, bevel=0.03)


@model("stone-furnace")
def stone_furnace():
    """Factorio's stone furnace: a squat stepped pyramid of rough blocks with a square flue on top
    and a protruding stone mouth at the front."""
    p = Part()
    r = rng(11)
    p.box((0, 0, 0.05), (1.7, 1.7, 0.1), "stone_dark", bevel=0.04)
    # A pyramid core, then courses of blocks stepping in as they rise.
    p.cyl((0, 0, 0.82), 0.78 * math.sqrt(2), 1.44, "stone_dark", segs=4, radius_top=0.4 * math.sqrt(2),
          matrix=R("Z", 45))
    courses = [(0.8, 0.1, 0.4), (0.71, 0.4, 0.7), (0.62, 0.7, 1.0), (0.53, 1.0, 1.28), (0.45, 1.28, 1.52)]
    for k, (half, z0, z1) in enumerate(courses):
        gap = (-0.32, 0.32) if k < 2 else None
        stone_course(p, r, half, z0, z1, gap=gap, seed=k, block=0.32)
    # The mouth: a stone frame standing proud of the front, a dark fire box inside.
    p.slab(-0.34, -0.92, 0.0, 0.34, -0.55, 0.7, "stone_light", bevel=0.04)
    p.slab(-0.2, -0.93, 0.1, 0.2, -0.5, 0.46, "soot")
    p.slab(-0.15, -0.8, 0.1, 0.15, -0.55, 0.2, "fire")
    p.slab(-0.38, -0.95, 0.0, 0.38, -0.85, 0.1, "stone", bevel=0.03)
    # The flue: a rim of slabs round a dark well.
    p.slab(-0.24, -0.24, 1.48, 0.24, 0.24, 1.55, "soot")
    for sx, sy, w, d in ((0, -0.31, 0.74, 0.14), (0, 0.31, 0.74, 0.14), (-0.31, 0, 0.14, 0.48), (0.31, 0, 0.14, 0.48)):
        p.box((sx, sy, 1.58), (w, d, 0.12), "stone_light", bevel=0.03)
    return p


# Factorio draws the burner drill's stand the same in all four directions (its legs splayed to the
# corners as seen from the south, the back pair level across the top): only the output duct and
# the fuel box move round with the direction. So the stand doesn't turn: each direction is a model
# of its own (burner-mining-drill, -east, -south, -west; model_library.gd picks it, PICTURES keeps
# it unturned), the stand fitted once to all four pictures, the duct and box turned to face.
# Stand: the head's height, the feet (x out, y to the front, y to the back), the auger's radius.
# Each picture also sits a few pixels off the entity's position: per direction, (x east, y north).
HEAD_Z, FOOT, AUGER, LEG, SCORCH = 1.2, (0.88, -0.72, 0.94), 0.045, (0.32, 0.09), 0.16
# Leg curves (front, back): the control point as shares of the foot's x, y and the head's height.
# The head's gear pair on each face: (x along the face, height, radius, material).
GEARS = ((-0.1, 0.06, 0.21, "bronze"), (0.17, -0.14, 0.16, "steel_light"))
LEG_ARCH, LEG_SEGS = ((0.2, 0.2, 1.0), (0.5, 0.5, 0.6)), 6
BACK_FOOT_Z = 0.06
# Per direction: how far the duct reaches out, and where the fuel box stands.
# Per direction: how far the duct reaches out, where the fuel box stands, and the duct's mouth:
# its height, its width (x the north duct's) and how far it sits to the left of the head, seen
# facing out along it (each picture draws it its own way: the east one ends high, the south one
# is broad and to the east of the head).
DRILL_PARTS = [(1.0, (0.5, -0.55), 0.28, 1.0, 0.3), (1.0, (-0.25, -0.55), 0.28, 1.0, 0.3),
               (1.0, (-0.45, 0.35), 0.28, 1.4, 0.45), (1.0, (0.0, -0.35), 0.28, 1.0, 0.3)]
DRILL_FACINGS = (("", 0, (0.04, -0.05)), ("-east", 1, (0.0, 0.04)), ("-south", 2, (0.0, 0.04)), ("-west", 3, (0.02, 0.02)))


def _burner_drill_stand(p, head_z):
    """The legs, posts and head: the same from every side."""
    # Legs: a broad violet rail with a dark groove, bowed as Factorio draws them: the front pair
    # arch out from under the head to feet just inside the front corners, the back pair run out
    # nearly level (from Factorio's camera the bar across the top, its ends curling down) and drop
    # to feet at the back corners. A quadratic curve from the head through a control point
    # (`LEG_ARCH`: share of the foot's x and y, share of the head's height) to the foot.
    for sx in (-1, 1):
        for sy in (-1, 1):
            a = Vector((sx * 0.2, sy * 0.2, head_z))
            f = Vector((sx * FOOT[0], FOOT[1] if sy < 0 else FOOT[2], 0.06 if sy < 0 else BACK_FOOT_Z))
            kx, ky, kz = LEG_ARCH[0] if sy < 0 else LEG_ARCH[1]
            c = Vector((f.x * kx, f.y * ky, head_z * kz))
            pts = [a * (1 - t) ** 2 + c * 2 * t * (1 - t) + f * t * t for t in (i / LEG_SEGS for i in range(LEG_SEGS + 1))]
            out = Vector((f.x, f.y, 0)).normalized()
            side = Vector((-out.y, out.x, 0))
            for q0, q1 in zip(pts, pts[1:]):
                d = (q1 - q0).normalized()
                up = d.cross(side).normalized()
                if up.z < 0:
                    up = -up
                e = d * LEG[1] * 0.5  # overlap the pieces so the bends show no gaps
                p.beam(q0 - e, q1 + e, LEG[0], LEG[1], "violet_steel", up=up)
                p.beam(q0 + up * LEG[1] / 2 - e, q1 + up * LEG[1] / 2 + e, LEG[0] * 0.44, 0.02, "steel_black", up=up)
            if sy < 0:
                p.box((f.x, f.y, 0.025), (0.14, 0.14, 0.05), "steel_dark", bevel=0.015)
        # A thin post from each back leg down to the ground (Factorio draws them at the back in
        # every direction).
        px, py = sx * 0.6, 0.22
        p.slab(px - 0.035, py - 0.035, 0.0, px + 0.035, py + 0.035, head_z - 0.12, "violet_steel")
        p.slab(px - 0.06, py - 0.06, 0.0, px + 0.06, py + 0.06, 0.04, "steel_dark")
    p.cyl((0, -0.3, 0.005), SCORCH, 0.01, "soot", segs=12)  # the scorched hole, south of the middle
    # The head: a dark gearbox on a violet frame, gears on all four faces, hoses and a post.
    p.slab(-0.3, -0.3, head_z - 0.38, 0.3, 0.3, head_z + 0.14, "steel_dark", bevel=0.04)
    p.slab(-0.34, -0.34, head_z - 0.06, 0.34, 0.34, head_z + 0.02, "violet_steel", bevel=0.02)
    p.slab(-0.26, -0.26, head_z + 0.14, 0.26, 0.26, head_z + 0.2, "steel_black", bevel=0.02)
    p.cyl((0.14, 0.12, head_z + 0.26), 0.11, 0.04, "bronze", segs=12)
    p.pipe([(0.2, -0.3, head_z + 0.05), (0.3, -0.34, head_z + 0.2), (0.05, -0.2, head_z + 0.3),
            (-0.15, 0.1, head_z + 0.25)], 0.035, "steel_black", segs=6)
    p.pipe([(-0.3, -0.15, head_z), (-0.42, 0.0, head_z - 0.2), (-0.32, 0.18, head_z - 0.35)],
           0.03, "steel_black", segs=6)


def _burner_drill_gears(head_z):
    """The head's gears, a pair on each face, each its own moving part (`anim_gear_bmd_ns` turns
    about the north-south axis, `_ew` about east-west: model_library.gd CYCLES rocks them to and
    fro, as Factorio's 32 frames play forward then backward), and the rod that bobs on top."""
    out = []
    for turn in (0, 90, 180, 270):
        face = R("Z", turn) @ T(0, -0.31, head_z - 0.1)
        axis = "ns" if turn in (0, 180) else "ew"
        for k, (x, z, rad, mat) in enumerate(GEARS):
            m = face @ T(x, 0, z)
            centre = m @ Vector((0, 0, 0))
            g = Part("anim_gear_bmd_%s_%d%d" % (axis, turn // 90, k), pivot=tuple(centre))
            # Meshing gears turn opposite ways: the small one's teeth run the other way round.
            g.cyl((0, 0, 0), rad, 0.04, mat, segs=12, axis="Y", matrix=m)
            g.cyl((0, 0, 0), rad * 0.35, 0.07, "steel_dark", segs=8, axis="Y", matrix=m)
            for t in range(9):
                g.box((0, 0, 0), (0.05, 0.035, 0.05), mat, matrix=m @ R("Y", t * 40 + 20 * k) @ T(0, 0, rad + 0.02))
            if k:
                g.name = g.name.replace("gear_bmd", "gear_bmd_r")
            out.append(g)
    rod = Part("anim_slide_bmd_rod", pivot=(0.0, 0.03, head_z + 0.2))
    rod.slab(-0.05, -0.02, head_z + 0.2, 0.05, 0.08, head_z + 0.5, "pale_blue", bevel=0.01)
    out.append(rod)
    return out


def _burner_drill_duct(head_z, reach, low_z=0.28, width=1.0, left=0.3):
    """The output duct, laid out facing north: rusty, closed, widening down from the head to an
    open mouth over the output spot (`reach` tiles north of the middle)."""
    p = Part()
    top, low = Vector((-left, 0.3, head_z - 0.15)), Vector((-left, reach, low_z))
    axis = (low - top).normalized()
    up = Vector((0, 0, 1)) - axis * axis.z
    up.normalize()
    side = axis.cross(up)
    k = Part()
    hw = 0.17 * width
    k.prism([(-hw, -0.13), (hw, -0.13), (hw, 0.13), (-hw, 0.13)], 0.0, 1.0, "rust_light")
    for v in k.bm.verts:
        w = 1.0 + 0.4 * v.co.z
        v.co = top + (low - top) * v.co.z + side * v.co.x * w + up * v.co.y * w
    p.add_part(k)
    p.beam(low - axis * 0.05, low + axis * 0.01, 0.52 * width, 0.4, "rust_brown", up=up)
    p.beam(low, low + axis * 0.015, 0.4 * width, 0.28, "soot", up=up)
    return p


def burner_mining_drill(facing=0, offset=(0.0, 0.0), reach=1.02, box=(0.48, -0.5), low_z=0.28, width=1.0, left=0.3):
    """Factorio's 2.x burner drill facing north, east, south or west (`facing` quarter turns):
    four grooved rail legs running straight out from a gear head to feet at the corners, posts
    under the back pair, gears on the head, an auger turning down into its hole, a rusty duct
    sloping down to the output spot on the side it faces and a tall fuel box (`box`: where each
    picture draws it, x east and y north)."""
    p = Part()
    _burner_drill_stand(p, HEAD_Z)
    p.add_part(_burner_drill_duct(HEAD_Z, reach, low_z, width, left), R("Z", -90 * facing))
    # The tall pale-blue fuel box, its dark door to the south.
    bx, by = box
    p.slab(bx - 0.08, by - 0.08, 0.0, bx + 0.08, by + 0.08, 0.85, "pale_blue", bevel=0.02)
    p.slab(bx - 0.06, by - 0.09, 0.35, bx + 0.06, by - 0.08, 0.75, "steel_dark")
    # The fire seen through the bottom of the door: it flickers while the drill burns fuel.
    p.slab(bx - 0.045, by - 0.095, 0.38, bx + 0.045, by - 0.085, 0.47, "fire")
    # The auger, turning down into its hole.
    pivot_z = HEAD_Z - 0.38
    drill = Part("anim_spin_drill", pivot=(0.0, 0.0, pivot_z))
    bottom = 0.0
    drill.cyl((0, 0, (pivot_z + bottom) / 2), 0.06, pivot_z - bottom, "steel_dark", segs=8)
    steps = 30
    for i in range(steps):
        z = bottom + 0.05 + (pivot_z - bottom - 0.1) * i / steps
        drill.box((AUGER, 0, 0), (2 * AUGER, 0.06, 0.03), "steel_dark",
                  matrix=T(0, 0, z) @ R("Z", i * 40.0) @ R("X", 25))
    shift = T(offset[0], offset[1], 0)
    parts = [p, drill] + _burner_drill_gears(HEAD_Z)
    for part in parts:
        part.transform(shift)
        part.pivot = part.pivot + Vector((offset[0], offset[1], 0))
    return parts


for _suffix, _facing, _offset in DRILL_FACINGS:
    model("burner-mining-drill" + _suffix)(lambda f=_facing, o=_offset: burner_mining_drill(f, o, *DRILL_PARTS[f]))


@model("electric-mining-drill")
def electric_mining_drill():
    p = Part()
    # Base plinth and a sloped body (a square frustum).
    p.prism(octagon(1.4, 0.25), 0.0, 0.22, "steel_dark", bevel=0.03)
    p.cyl((0, 0, 0.55), 1.27 * math.sqrt(2), 0.66, "paint_blue", segs=4, radius_top=0.9 * math.sqrt(2),
          matrix=R("Z", 45), bevel=0.04)
    p.prism(octagon(0.95, 0.2), 0.88, 0.98, "steel", bevel=0.02)
    # Hazard stripes along the south face of the plinth, corner bolts.
    p.hazard_stripes(-0.9, 0.9, -1.4, 0.05, 0.18, depth=0.012, count=10)
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.cyl((sx * 1.05, sy * 1.05, 0.27), 0.1, 0.1, "steel", segs=8)
            p.bolt((sx * 1.05, sy * 1.05, 0.33))
    # Motor housings either side of the tower.
    for sx in (-1, 1):
        p.slab(sx * 0.95, -0.45, 0.6, sx * 0.55, 0.35, 1.25, "steel_dark", bevel=0.04)
        p.cyl((sx * 0.75, -0.05, 1.3), 0.14, 0.12, "steel", segs=10)
        for z in (0.75, 0.95, 1.15):
            p.slab(sx * 0.96, -0.35, z, sx * 0.94, 0.25, z + 0.06, "steel_black")
    # Central tower; the head on top turns while mining.
    p.cyl((0, 0, 1.2), 0.5, 0.45, "steel", segs=16, bevel=0.03)
    p.cyl((0, 0, 1.47), 0.56, 0.1, "steel_dark", segs=16, bevel=0.02)
    p.bolts_ring((0, 0, 1.53), 0.48, 10)
    # Output spout over the north edge.
    p.slab(-0.3, 0.9, 0.3, 0.3, 1.3, 0.75, "paint_blue", bevel=0.03)
    p.side_prism([(1.25, 0.32), (1.47, 0.22), (1.47, 0.36), (1.25, 0.6)], -0.24, 0.24, "steel_dark", bevel=0.01)
    p.slab(-0.31, 0.95, 0.62, 0.31, 1.31, 0.7, "hazard")
    head = Part("anim_spin_drill", pivot=(0.0, 0.0, 1.52))
    head.cyl((0, 0, 1.62), 0.36, 0.2, "steel_dark", segs=12, bevel=0.02)
    for a in (0, 120, 240):
        head.box((0.22, 0, 1.76), (0.36, 0.1, 0.1), "steel_light", matrix=R("Z", a), bevel=0.015)
    head.cyl((0, 0, 1.86), 0.12, 0.12, "steel", segs=10)
    return [p, head]


@model("assembling-machine-1")
def assembling_machine_1():
    p = Part()
    p.prism(octagon(1.4, 0.3), 0.0, 0.2, "steel_dark", bevel=0.03)
    p.prism(octagon(1.3, 0.3), 0.2, 1.0, "paint_green", bevel=0.04)
    p.prism(octagon(1.36, 0.32), 1.0, 1.1, "paint_grey", bevel=0.02)
    # Panels on each face, with vents and bolts.
    for rot in (0, 90, 180, 270):
        m = R("Z", rot)
        p.slab(-0.55, -1.33, 0.32, 0.55, -1.3, 0.88, "paint_grey", matrix=m)
        for z in (0.45, 0.6, 0.75):
            p.slab(-0.42, -1.345, z, 0.42, -1.33, z + 0.06, "steel_black", matrix=m)
        for x in (-0.48, 0.48):
            for z in (0.38, 0.82):
                p.cyl((x, -1.34, z), 0.022, 0.02, "steel_light", segs=6, axis="Y", matrix=m)
    p.hazard_stripes(-0.8, 0.8, -1.3, 0.22, 0.3, depth=0.012, count=10)
    # Corner columns.
    for a in (45, 135, 225, 315):
        r = math.radians(a)
        p.cyl((1.12 * math.cos(r), 1.12 * math.sin(r), 0.65), 0.1, 0.9, "steel", segs=8, bevel=0.02)
    # Top deck: a round work table under a crane-like arm cluster.
    p.cyl((0, 0, 1.18), 0.85, 0.16, "steel_light", segs=20, bevel=0.03)
    p.cyl((0, 0, 1.28), 0.7, 0.04, "steel_black", segs=20)
    for a in (0, 90, 180, 270):
        r = math.radians(a + 45)
        p.box((1.0 * math.cos(r), 1.0 * math.sin(r), 1.2), (0.3, 0.3, 0.2), "steel_dark", bevel=0.03, rz=a + 45)
    # A pipe feeding the table from the north-east corner.
    p.cyl((0.85, 0.85, 1.35), 0.07, 0.5, "copper", segs=8)
    arms = Part("anim_spin_arms", pivot=(0.0, 0.0, 1.3))
    arms.cyl((0, 0, 1.55), 0.16, 0.5, "steel_dark", segs=10, bevel=0.02)
    for a in (0, 120, 240):
        m = R("Z", a)
        arms.box((0.3, 0, 1.72), (0.5, 0.1, 0.1), "paint_grey", matrix=m, bevel=0.02)
        arms.box((0.52, 0, 1.55), (0.08, 0.08, 0.32), "steel", matrix=m)
        arms.box((0.52, 0, 1.38), (0.14, 0.14, 0.06), "hazard", matrix=m)
    arms.cyl((0, 0, 1.84), 0.1, 0.08, "steel", segs=10)
    return [p, arms]


def geodesic_dome(radius, squash=1.0, turn=0.0):
    """A two-frequency geodesic hemisphere: (vertices, triangles, edges), the equator on z=0."""
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=2, radius=radius)
    verts = [Vector((v.co.x, v.co.y, v.co.z)) for v in bm.verts]
    tris = [tuple(v.index for v in f.verts) for f in bm.faces if all(v.co.z > -1e-4 for v in f.verts)]
    bm.free()
    rot = R("Z", turn)
    verts = [(rot @ Vector((v.x, v.y, max(v.z, 0.0) * squash))) for v in verts]
    edges = set()
    for t in tris:
        for i in range(3):
            a, b = t[i], t[(i + 1) % 3]
            edges.add((min(a, b), max(a, b)))
    return verts, tris, sorted(edges)


@model("lab")
def lab():
    """A geodesic glass dome on the ground: cream struts with rust at the edges over dark panes,
    a dark band of panes round the bottom with steel gussets where the struts meet the footing
    ring, red canisters between some (Factorio's lab sprite). The sprite was drawn with tiles
    foreshortened north-south, so under the projection's stretch the dome that fits it is an
    oval, 3 tiles across and about 2.3 deep.

    While it researches Factorio fills the dome with a blue light that swells and fades (lab.png
    and lab-light.png, 33 frames at 1/3 speed: 1.65 s a loop). The glass panes above the band are
    `anim_glow_lab`, in the emissive `glow_blue`: their colour stays the sprite's, they glow blue,
    breathing, while the lab works and go dark when it's idle."""
    p = Part()
    panes = Part("anim_glow_lab")
    radius = 1.47
    verts, tris, edges = geodesic_dome(radius, squash=1.01, turn=9)
    used = sorted({i for t in tris for i in t})
    # The lowest row of panes is the dark band round the base in the sprite.
    band_z = 0.42
    p.ring_band((0, 0), radius - 0.14, radius + 0.0, 0.0, 0.08, 0, 360, "steel_black", segs=24)
    for t in tris:
        a, b, c = (verts[i] for i in t)
        centre = (a + b + c) / 3
        n = (b - a).cross(c - a).normalized()
        if n.dot(centre) < 0:
            b, c = c, b
            n = -n
        pts = [centre + (v - centre) * 0.97 - n * 0.03 for v in (a, b, c)]
        if centre.z > band_z:
            panes.poly(pts, "glow_blue", thick=0.02)
        else:
            p.poly(pts, "steel_black", thick=0.02)
    # Struts: a rusty core with a cream cap, square to the dome's surface; plain dark steel round
    # the bottom band.
    for a, b in edges:
        va, vb = verts[a], verts[b]
        mid = (va + vb) / 2
        up = mid.normalized()
        low = min(va.z, vb.z) < 1e-4
        if low and max(va.z, vb.z) < 1e-4:
            up = (Vector((mid.x, mid.y, 0)).normalized() + Vector((0, 0, 0.3))).normalized()
        if low:
            p.beam(va, vb, 0.11, 0.07, "steel_dark", up=up)
            continue
        p.beam(va, vb, 0.15, 0.06, "rust_orange", up=up)
        p.beam(va + up * 0.025, vb + up * 0.025, 0.1, 0.035, "frame_cream", up=up)
    # Hubs where struts meet; steel gussets (little pyramids) on the footing ring.
    for i in used:
        v = verts[i]
        n = v.normalized()
        if v.z < 1e-4:
            out = Vector((n.x, n.y, 0)).normalized()
            side = Vector((-out.y, out.x, 0))
            base = v - out * 0.01
            top = base + Vector((0, 0, 0.5)) - out * 0.12
            p.poly([base - side * 0.2, base + side * 0.2, top], "steel", thick=0.05)
            p.poly([base + side * 0.2 - out * 0.12, base - side * 0.2 - out * 0.12, top - out * 0.04], "steel", thick=0.05)
            p.bolt(base + out * 0.01 + Vector((0, 0, 0.16)), axis="Z", radius=0.03)
        else:
            p.tube(v, v + n * 0.08, 0.08, "frame_cream", segs=6)
    for a in (200, 340, 20, 160, 300):
        r = math.radians(a)
        p.box((1.35 * math.cos(r), 1.35 * math.sin(r), 0.2), (0.14, 0.14, 0.32), "paint_red", rz=a, bevel=0.02)
    # Lift the dome so the struts on the ground ring don't dip below it. It stays round: the lab's
    # sprite is drawn with the ground foreshortened, so its projection entry isn't stretched.
    p.transform(T(0, 0, 0.05))
    panes.transform(T(0, 0, 0.05))
    return [p, panes]
