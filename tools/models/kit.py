"""Shared modelling kit for the procedural models: materials, primitives and export.

Everything here runs inside Blender (bpy, bmesh). Coordinates are Blender's: x east, y north,
z up, 1 unit = 1 tile, origin at the footprint centre on the ground (docs/PLAN.md §4).

A model function builds one or more `Part`s. A part is a bmesh with a material list; every
primitive added to it is created at the origin, bevelled, then moved into place, so model code
reads as "a box this big, here". Parts named `anim_*` stay separate nodes (with their pivot as
the node origin) so the client can animate them later; everything else is one node.
"""

import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

import bake

# ---------------------------------------------------------------------------------------------
# Materials. Colours are sRGB hex (what a colour picker shows); glTF wants linear.

MATERIALS = {
    # name: (sRGB hex, roughness, metallic, emission hex or None, emission strength)
    "steel": ("8a8c8e", 0.45, 0.85, None, 0),
    "steel_dark": ("4a4c4f", 0.55, 0.8, None, 0),
    "steel_black": ("26272a", 0.6, 0.7, None, 0),
    "steel_light": ("b4b5b2", 0.4, 0.85, None, 0),
    "rust": ("6e3f22", 0.85, 0.35, None, 0),
    "rubber": ("2a2826", 0.9, 0.0, None, 0),
    "belt_surface": ("3c3a36", 0.8, 0.1, None, 0),
    # The tier colour of belts, undergrounds and splitters. The client swaps this one material
    # for the red/blue/green tiers, so keep the name.
    "tier_paint": ("e2a82a", 0.5, 0.4, None, 0),
    "paint_grey": ("7d8079", 0.6, 0.45, None, 0),
    "paint_green": ("6f7a5a", 0.6, 0.35, None, 0),
    "paint_blue": ("4f6a86", 0.55, 0.45, None, 0),
    "paint_cream": ("c9c3ad", 0.6, 0.25, None, 0),
    "hazard": ("d9a521", 0.55, 0.3, None, 0),
    "hazard_black": ("1f1f1f", 0.7, 0.2, None, 0),
    "copper": ("b86a3c", 0.4, 0.95, None, 0),
    "brass": ("b39545", 0.4, 0.9, None, 0),
    "wood": ("8a5f35", 0.85, 0.0, None, 0),
    "wood_dark": ("5e3e22", 0.9, 0.0, None, 0),
    "stone": ("8c7d68", 0.95, 0.0, None, 0),
    "stone_dark": ("5f5446", 0.95, 0.0, None, 0),
    "stone_light": ("a49580", 0.95, 0.0, None, 0),
    "concrete": ("8f8d86", 0.95, 0.0, None, 0),
    "soot": ("1c1a18", 0.95, 0.0, None, 0),
    "glass": ("5d8fb0", 0.15, 0.2, None, 0),
    "fire": ("ff8a2a", 0.8, 0.0, "ff6a10", 2.0),
    "glow_blue": ("8fd4ff", 0.4, 0.0, "4fb4ff", 1.5),
    "arc_blue": ("b8f0ff", 0.4, 0.0, "58d8ff", 4.0),   # electric arcs (kit.arc), shown only while lit
    "lamp_red": ("c0301c", 0.4, 0.0, "ff2a10", 0.6),
    "lamp_green": ("4e8a3a", 0.4, 0.0, "6cff4a", 0.8),   # chemical plant's pump light
    "ceramic": ("ddd8c8", 0.5, 0.0, None, 0),
    # Picked against the 2D sprites of the machines that use them.
    "glass_dark": ("585d5b", 0.15, 0.25, None, 0),    # lab dome panes
    "frame_cream": ("cfc2a6", 0.55, 0.35, None, 0),   # lab dome struts
    "rust_orange": ("97562d", 0.8, 0.3, None, 0),     # rust streaks on light paint
    "rust_brown": ("6a4a33", 0.85, 0.4, None, 0),     # rusty housings (turret, drill chute)
    "paint_red": ("8e2a1f", 0.6, 0.2, None, 0),
    "olive_steel": ("7a7862", 0.5, 0.6, None, 0),     # boiler body
    "olive_dark": ("4a4636", 0.6, 0.6, None, 0),
    "tank_white": ("cdc8b6", 0.6, 0.25, None, 0),     # steam engine cylinders
    "blue_steel": ("8f979b", 0.45, 0.7, None, 0),     # gun turret receiver
    "violet_steel": ("635c62", 0.6, 0.6, None, 0),    # burner drill legs
    "copper_dull": ("8f6240", 0.5, 0.8, None, 0),     # small pipes on the boiler
    "bronze": ("86704a", 0.5, 0.8, None, 0),          # steam engine gears
    "rust_light": ("8a6550", 0.85, 0.4, None, 0),     # burner drill chute
    "pale_blue": ("8c9ea4", 0.5, 0.5, None, 0),       # burner drill fuel box
    "wood_light": ("ad8a52", 0.8, 0.0, None, 0),      # wooden chest frame
    "iron_rust": ("6e5848", 0.75, 0.55, None, 0),     # iron chest panels
    "wood_orange": ("94592b", 0.75, 0.0, None, 0),    # small electric pole post
}

# Materials that are see-through (exported with alpha blending).
ALPHA = {"glass": 0.45}


def srgb_to_linear(hex_colour):
    out = []
    for i in (0, 2, 4):
        c = int(hex_colour[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return out


def material(name):
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    hex_colour, rough, metal, emit, strength = MATERIALS[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*srgb_to_linear(hex_colour), 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit:
        bsdf.inputs["Emission Color"].default_value = (*srgb_to_linear(emit), 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    if name in ALPHA:
        bsdf.inputs["Alpha"].default_value = ALPHA[name]
        mat.surface_render_method = "BLENDED"
    mat.diffuse_color = (*srgb_to_linear(hex_colour), ALPHA.get(name, 1.0))
    return mat


# ---------------------------------------------------------------------------------------------
# Transform helpers.

def T(x=0.0, y=0.0, z=0.0):
    return Matrix.Translation((x, y, z))


def R(axis, degrees):
    """Rotation about 'X', 'Y' or 'Z' (degrees, right-handed: +Z turns x towards y)."""
    return Matrix.Rotation(math.radians(degrees), 4, axis)


def S(x, y, z):
    m = Matrix.Identity(4)
    m[0][0], m[1][1], m[2][2] = x, y, z
    return m


_AXIS = {"X": R("Y", 90), "Y": R("X", -90), "Z": Matrix.Identity(4)}


# ---------------------------------------------------------------------------------------------
# Parts.

class Part:
    def __init__(self, name="body", pivot=(0.0, 0.0, 0.0)):
        self.name = name
        self.pivot = Vector(pivot)
        self.bm = bmesh.new()
        self.mats = []
        # Optional fn(co) -> (u, v) replacing the planar UVs (rails store their centre line).
        self.uv_fn = None
        # Edges sharper than this (degrees) shade hard; organic low-poly parts raise it.
        self.sharp_angle = 35.0

    # -- plumbing --------------------------------------------------------------------------

    def _mat_index(self, mat):
        if mat not in self.mats:
            if mat not in MATERIALS:
                raise KeyError("unknown material %r" % mat)
            self.mats.append(mat)
        return self.mats.index(mat)

    def merge(self, src, mat, matrix=Matrix.Identity(4), mats=None):
        """Copies the faces of bmesh `src` into this part, transformed by `matrix`. Faces use
        `mat`, or `mats[face.material_index]` when a list is given."""
        flip = matrix.to_3x3().determinant() < 0
        vmap = {}
        for v in src.verts:
            vmap[v] = self.bm.verts.new(matrix @ v.co)
        for f in src.faces:
            verts = [vmap[v] for v in f.verts]
            if flip:
                verts.reverse()
            try:
                nf = self.bm.faces.new(verts)
            except ValueError:
                continue  # duplicate face
            nf.material_index = self._mat_index(mats[f.material_index] if mats else mat)
        return self

    def add_part(self, other, matrix=Matrix.Identity(4)):
        """Copies another Part (with its materials) into this one."""
        return self.merge(other.bm, None, matrix, mats=other.mats)

    # -- primitives ------------------------------------------------------------------------

    def box(self, center, size, mat, bevel=0.0, matrix=None, rz=0.0):
        """Axis-aligned box `size` (x, y, z) centred on `center`, optionally bevelled, turned
        `rz` degrees about its own centre, then transformed by `matrix`."""
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
        if bevel > 0:
            _bevel(bm, min(bevel, min(size) * 0.45))
        m = T(*center) @ R("Z", rz)
        if matrix is not None:
            m = matrix @ m
        self.merge(bm, mat, m)
        bm.free()
        return self

    def slab(self, x0, y0, z0, x1, y1, z1, mat, bevel=0.0, matrix=None):
        """Box given by its two corners."""
        c = ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
        s = (abs(x1 - x0), abs(y1 - y0), abs(z1 - z0))
        return self.box(c, s, mat, bevel, matrix)

    def cyl(self, center, radius, depth, mat, segs=12, axis="Z", bevel=0.0, radius_top=None,
            matrix=None, caps=True):
        """Cylinder (or cone/frustum with `radius_top`) along `axis`, centred on `center`."""
        bm = bmesh.new()
        r2 = radius if radius_top is None else radius_top
        bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=segs,
                              radius1=radius, radius2=r2, depth=depth)
        if bevel > 0:
            _bevel(bm, min(bevel, depth * 0.45, radius * 0.45))
        m = T(*center) @ _AXIS[axis]
        if matrix is not None:
            m = matrix @ m
        self.merge(bm, mat, m)
        bm.free()
        return self

    def sphere(self, center, radius, mat, segs=12, rings=6, scale=(1, 1, 1), matrix=None,
               hemisphere=False):
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=radius)
        if hemisphere:
            bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -1e-4], context="VERTS")
            edges = [e for e in bm.edges if e.is_boundary]
            if edges:
                bmesh.ops.holes_fill(bm, edges=edges, sides=0)
        m = T(*center) @ S(*scale)
        if matrix is not None:
            m = matrix @ m
        self.merge(bm, mat, m)
        bm.free()
        return self

    def prism(self, points, z0, z1, mat, bevel=0.0, matrix=None):
        """A polygon (list of (x, y), counter-clockwise) extruded from z0 to z1."""
        bm = bmesh.new()
        bottom = [bm.verts.new((x, y, z0)) for x, y in points]
        top = [bm.verts.new((x, y, z1)) for x, y in points]
        bm.faces.new(list(reversed(bottom)))
        bm.faces.new(top)
        n = len(points)
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new([bottom[i], bottom[j], top[j], top[i]])
        if bevel > 0:
            _bevel(bm, bevel)
        self.merge(bm, mat, matrix or Matrix.Identity(4))
        bm.free()
        return self

    def side_prism(self, points, x0, x1, mat, bevel=0.0, matrix=None):
        """A profile in the y-z plane (list of (y, z), counter-clockwise seen from +x) extruded
        along x from x0 to x1. Handy for ramps and sloped housings."""
        m = T(x0, 0, 0) @ R("Y", 90) @ R("Z", 90)
        # In the prism's own frame, (px, py) -> (y, z) and z -> x after the two turns.
        local = [(y, z) for y, z in points]
        return self.prism(local, 0.0, x1 - x0, mat, bevel, (matrix or Matrix.Identity(4)) @ m)

    def ring_band(self, center, r0, r1, z0, z1, a0, a1, mat, segs=8, bevel=0.0):
        """A solid annular sector: radii r0..r1, heights z0..z1, angles a0..a1 (degrees,
        counter-clockwise from +x) around `center` (x, y)."""
        bm = bmesh.new()
        cx, cy = center
        rows = []
        for i in range(segs + 1):
            a = math.radians(a0 + (a1 - a0) * i / segs)
            c, s = math.cos(a), math.sin(a)
            rows.append([bm.verts.new((cx + r * c, cy + r * s, z)) for r, z in
                         ((r0, z0), (r1, z0), (r1, z1), (r0, z1))])
        for i in range(segs):
            a, b = rows[i], rows[i + 1]
            for k in range(4):
                k2 = (k + 1) % 4
                bm.faces.new([a[k], a[k2], b[k2], b[k]])
        bm.faces.new(rows[0])
        bm.faces.new(list(reversed(rows[-1])))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        if bevel > 0:
            _bevel(bm, bevel)
        self.merge(bm, mat)
        bm.free()
        return self

    def tube(self, p0, p1, radius, mat, segs=8, radius_top=None, caps=True, bevel=0.0):
        """Cylinder from point p0 to p1 (any direction)."""
        a, b = Vector(p0), Vector(p1)
        d = b - a
        m = T(*((a + b) / 2)) @ Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=segs, radius1=radius,
                              radius2=radius if radius_top is None else radius_top, depth=d.length)
        if bevel > 0:
            _bevel(bm, min(bevel, d.length * 0.45, radius * 0.45))
        self.merge(bm, mat, m)
        bm.free()
        return self

    def pipe(self, points, radius, mat, segs=8, joints=True):
        """A bent pipe through `points`, with a ball at each bend so the elbows look closed."""
        for a, b in zip(points, points[1:]):
            self.tube(a, b, radius, mat, segs)
        if joints:
            for p in points[1:-1]:
                self.sphere(p, radius, mat, segs=segs, rings=max(3, segs // 2))
        return self

    def beam(self, p0, p1, width, thick, mat, up=(0, 0, 1), bevel=0.0):
        """A box from p0 to p1, `width` across and `thick` along `up` (made square to the beam)."""
        a, b = Vector(p0), Vector(p1)
        x = (b - a).normalized()
        z = Vector(up) - x * x.dot(Vector(up))
        if z.length < 1e-6:
            z = x.orthogonal()
        z.normalize()
        y = z.cross(x)
        m = Matrix((
            (x.x, y.x, z.x, 0),
            (x.y, y.y, z.y, 0),
            (x.z, y.z, z.z, 0),
            (0, 0, 0, 1)))
        return self.box((0, 0, 0), ((b - a).length, width, thick), mat, bevel, matrix=T(*((a + b) / 2)) @ m)

    def poly(self, points, mat, thick=0.0):
        """A flat polygon through `points` (counter-clockwise seen from its front), optionally
        given a thickness behind it."""
        bm = bmesh.new()
        front = [bm.verts.new(p) for p in points]
        f = bm.faces.new(front)
        if thick > 0:
            bm.normal_update()
            n = f.normal.copy()
            back = [bm.verts.new(Vector(p) - n * thick) for p in points]
            bm.faces.new(list(reversed(back)))
            k = len(points)
            for i in range(k):
                j = (i + 1) % k
                bm.faces.new([front[j], front[i], back[i], back[j]])
        self.merge(bm, mat)
        bm.free()
        return self

    def bolt(self, center, mat="steel_light", radius=0.025, depth=0.02, axis="Z"):
        return self.cyl(center, radius, depth, mat, segs=6, axis=axis)

    def bolts_ring(self, center, ring_radius, count, mat="steel_light", radius=0.022, axis="Z",
                   depth=0.02, start=0.0):
        cx, cy, cz = center
        for i in range(count):
            a = math.radians(start) + 2 * math.pi * i / count
            if axis == "Z":
                p = (cx + ring_radius * math.cos(a), cy + ring_radius * math.sin(a), cz)
            elif axis == "Y":
                p = (cx + ring_radius * math.cos(a), cy, cz + ring_radius * math.sin(a))
            else:
                p = (cx, cy + ring_radius * math.cos(a), cz + ring_radius * math.sin(a))
            self.bolt(p, mat, radius, depth, axis)
        return self

    def hazard_stripes(self, x0, x1, y, z0, z1, depth=0.01, count=6, face="-y"):
        """Yellow/black diagonal-ish stripes as alternating thin plates on a vertical face."""
        w = (x1 - x0) / count
        sign = -1 if face == "-y" else 1
        for i in range(count):
            mat = "hazard" if i % 2 == 0 else "hazard_black"
            self.slab(x0 + i * w, y, z0, x0 + (i + 1) * w, y + sign * depth, z1, mat)
        return self

    # -- whole-part operations -------------------------------------------------------------

    def transform(self, matrix):
        bmesh.ops.transform(self.bm, matrix=matrix, verts=self.bm.verts)
        if matrix.to_3x3().determinant() < 0:
            bmesh.ops.reverse_faces(self.bm, faces=self.bm.faces)
        return self

    def warp(self, fn):
        """Moves every vertex to fn(co) -> (x, y, z). Used to bend straight pieces round curves;
        keep the pieces small, since faces stay flat."""
        for v in self.bm.verts:
            v.co = Vector(fn(v.co.copy()))
        self.bm.normal_update()
        return self

    def mirror_x(self):
        return self.transform(S(-1, 1, 1))

    def mirror_y(self):
        return self.transform(S(1, -1, 1))

    def triangles(self):
        return sum(len(f.verts) - 2 for f in self.bm.faces)


def _bevel(bm, offset, min_angle=40.0):
    """Chamfers the sharp edges of a primitive (one segment, the low-poly bevel look)."""
    edges = []
    for e in bm.edges:
        if len(e.link_faces) == 2:
            a = e.link_faces[0].normal.angle(e.link_faces[1].normal, 0.0)
            if math.degrees(a) > min_angle:
                edges.append(e)
    if edges:
        bmesh.ops.bevel(bm, geom=edges, offset=offset, offset_type="OFFSET", segments=1,
                        profile=0.5, affect="EDGES", clamp_overlap=True)


def rng(seed):
    return random.Random(seed)


def arc(part, p0, p1, seed, kinks=5, jitter=0.06, width=0.025, mat="arc_blue"):
    """An electric arc from p0 to p1: thin glowing beams zigzagging between kinks (the sparks of
    Factorio's charge and discharge animations, lit by the client while they play)."""
    r = rng(seed)
    a, b = Vector(p0), Vector(p1)
    pts = [a]
    for k in range(1, kinks):
        q = a.lerp(b, k / kinks)
        pts.append(q + Vector((r.uniform(-jitter, jitter), r.uniform(-jitter, jitter), r.uniform(-jitter, jitter))))
    pts.append(b)
    for q0, q1 in zip(pts, pts[1:]):
        part.beam(tuple(q0), tuple(q1), width, width, mat)
    return part


# ---------------------------------------------------------------------------------------------
# Scene and export.

def clear_scene():
    for coll in (bpy.data.objects, bpy.data.meshes, bpy.data.materials, bpy.data.images,
                 bpy.data.cameras, bpy.data.lights):
        coll_items = list(coll)
        if coll_items:
            bpy.data.batch_remove(coll_items)


def _box_uvs(bm):
    """Planar UVs from the dominant normal axis, 1 unit = 1 tile (TEXCOORD_0). Not used for
    textures yet, but gives the importer something for tangents and a belt surface a coordinate
    along y. The baked weathering data goes in a second UV map (TEXCOORD_1, bake.py)."""
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for loop in f.loops:
            co = loop.vert.co
            if ax == 2:
                loop[uv].uv = (co.x, co.y)
            elif ax == 1:
                loop[uv].uv = (co.x, co.z)
            else:
                loop[uv].uv = (co.y, co.z)


def part_to_object(part):
    bm = part.bm
    if part.pivot.length > 0:
        bmesh.ops.translate(bm, vec=-part.pivot, verts=bm.verts)
    bm.normal_update()
    # Each polygon's width before it becomes triangles: narrow ones (bevels, rims) are the edges
    # that wear bright in the client's material (bake.py).
    width = bm.faces.layers.float.new(bake.WIDTH_ATTRIBUTE)
    for f in bm.faces:
        f[width] = bake.polygon_width([v.co for v in f.verts])
    # Triangulate here with fixed rules: left to the exporter, quads whose diagonals are equal
    # (all over a sphere) split either way from run to run, and the .glb files churn.
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="FIXED", ngon_method="EAR_CLIP")
    _box_uvs(bm)
    if part.uv_fn is not None:
        uv = bm.loops.layers.uv.verify()
        for f in bm.faces:
            for loop in f.loops:
                loop[uv].uv = part.uv_fn(loop.vert.co)
    mesh = bpy.data.meshes.new(part.name)
    bm.to_mesh(mesh)
    for name in part.mats:
        mesh.materials.append(material(name))
    for poly in mesh.polygons:
        poly.use_smooth = True
    mesh.set_sharp_from_angle(angle=math.radians(part.sharp_angle))
    obj = bpy.data.objects.new(part.name, mesh)
    obj.location = part.pivot
    bpy.context.scene.collection.objects.link(obj)
    return obj


def export(parts, path):
    clear_scene()
    objects = [part_to_object(part) for part in parts]
    # matrix_world only takes the pivots' locations after an update: without it the bake saw
    # every anim_* part at the origin, buried in the body (a turret's head baked black).
    bpy.context.view_layer.update()
    # Ambient occlusion, worn edges and a random value per piece, for the client's weathered
    # material: COLOR_0 alpha and TEXCOORD_1 (bake.py, client/assets/models/README.md).
    bake.bake_blender_objects(objects)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=False, export_apply=True,
        export_yup=True, export_materials="EXPORT", export_cameras=False, export_lights=False,
        export_animations=False, export_extras=False, export_texcoords=True,
        export_normals=True, export_tangents=False, export_vertex_color="ACTIVE")


# ---------------------------------------------------------------------------------------------
# Model registry: model modules decorate one function per output file.

REGISTRY = {}


def model(name):
    def wrap(fn):
        if name in REGISTRY:
            raise ValueError("model %s registered twice" % name)
        REGISTRY[name] = fn
        return fn
    return wrap


def as_parts(result):
    if isinstance(result, Part):
        return [result]
    return list(result)
