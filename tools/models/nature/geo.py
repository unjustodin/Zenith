"""Low-poly mesh helpers for the procedural nature models.

Everything is built into one bmesh per model, with one material slot per colour. Geometry
follows docs/PLAN.md §4: 1 unit = 1 tile, origin at the footprint centre on the ground, north is
+Y. All randomness comes from the `random.Random` passed in, so a model rebuilds identically.

Each face corner also carries a colour (exported as glTF COLOR_0, which multiplies the material's
base colour). Materials hold the lightest tone of a part; the corner colours darken and tint it,
so one material can show the lit tips, shaded insides and colour mix of Factorio's foliage and
stone without a texture. Primitives take a `tint`; `Model.shade` darkens hidden faces at the end.
"""

import math

import bmesh
import bpy
from mathutils import Matrix, Vector, noise


def srgb(hex_color):
    """'#rrggbb' -> linear RGBA, which is what Blender's colour sockets (and glTF) expect."""
    h = hex_color.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (out[0], out[1], out[2], 1.0)


def material(name, hex_color, roughness=0.9, metallic=0.0):
    """A shared Principled material, created once per Blender session."""
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    mat = bpy.data.materials.new(name)
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = srgb(hex_color)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    mat.diffuse_color = srgb(hex_color)  # what the Workbench preview shows
    return mat


def _aim(direction):
    """Rotation turning +Z towards `direction`."""
    return Vector((0.0, 0.0, 1.0)).rotation_difference(direction.normalized()).to_matrix().to_4x4()


class Model:
    """One model being built: a bmesh plus its material list."""

    def __init__(self, name, rng):
        self.name = name
        self.rng = rng
        self.bm = bmesh.new()
        self.materials = []
        self._up_faces = []
        self.color = self.bm.loops.layers.color.new("Color")
        self._uv = None
        self._card_normals = []  # per leaf card: the normal its corners carry (see `card`)
        self._card_id = None
        self._card_faces = []

    def mat(self, material_):
        if material_ not in self.materials:
            self.materials.append(material_)
        return self.materials.index(material_)

    def _tag(self, verts, material_, smooth, tint=None, vary=0.0):
        """Sets material, smoothing and corner colour of the faces just made from `verts`.
        `vary` darkens each face by a random amount up to that fraction (leafy speckle)."""
        index = self.mat(material_)
        self.bm.verts.index_update()
        faces = sorted({f for v in verts for f in v.link_faces}, key=lambda f: sorted(v.index for v in f.verts))
        t = tint or (1.0, 1.0, 1.0)
        for f in faces:
            f.material_index = index
            f.smooth = smooth
            k = 1.0 - self.rng.uniform(0.0, vary) if vary else 1.0
            c = (t[0] * k, t[1] * k, t[2] * k, 1.0)
            for loop in f.loops:
                loop[self.color] = c
        return faces

    def shade(self, fn):
        """Multiplies every face corner's colour by `fn(face, position, normal)`: a factor, or an
        (r, g, b) multiplier (ambient occlusion, lighter tops, colour bands). Evaluated per corner,
        so shading ramps smoothly along long faces. Runs after all parts are built."""
        self.bm.normal_update()
        for f in self.bm.faces:
            for loop in f.loops:
                n = loop.vert.normal if f.smooth else f.normal
                k = fn(f, loop.vert.co, n)
                if not isinstance(k, tuple):
                    k = (k, k, k)
                c = loop[self.color]
                loop[self.color] = (c[0] * k[0], c[1] * k[1], c[2] * k[2], 1.0)

    # --- primitives ---------------------------------------------------------------------------

    def blob(self, center, radius, material_, scale=(1.0, 1.0, 1.0), jitter=0.18, subdiv=2,
             flat_bottom=None, spin=None, tint=None, vary=0.0, smooth=False, tilt=0.4):
        """A lumpy faceted sphere: canopy clumps, boulders, ore chunks.

        `jitter` pushes each vertex in or out by up to that fraction of the radius, using
        smooth noise so neighbouring facets stay coherent. `flat_bottom` (world z) squashes
        anything below it onto that plane, for things that sit on the ground.
        """
        rng = self.rng
        spin = rng.uniform(0.0, math.tau) if spin is None else spin
        rot = Matrix.Rotation(spin, 4, "Z") @ Matrix.Rotation(rng.uniform(-tilt, tilt), 4, "X")
        seed = Vector((rng.uniform(-100, 100), rng.uniform(-100, 100), rng.uniform(-100, 100)))
        made = bmesh.ops.create_icosphere(self.bm, subdivisions=subdiv, radius=1.0)
        verts = made["verts"]
        sx, sy, sz = scale
        for v in verts:
            d = v.co.copy()
            n = noise.noise(d * 1.7 + seed)  # roughly -1..1
            r = radius * (1.0 + jitter * n + jitter * 0.5 * rng.uniform(-1.0, 1.0))
            p = rot @ Vector((d.x * sx, d.y * sy, d.z * sz))
            v.co = Vector(center) + p * r
            if flat_bottom is not None and v.co.z < flat_bottom:
                v.co.z = flat_bottom
        self._tag(verts, material_, smooth, tint, vary)
        return verts

    def chop(self, verts, center, planes):
        """Flattens a blob against cutting planes, giving the crisp facets of broken stone.

        Each plane is (normal, fraction): vertices further out along the normal than that
        fraction of the blob's extent in that direction are pushed back onto the plane.
        """
        c = Vector(center)
        for normal, fraction in planes:
            n = Vector(normal).normalized()
            extent = max((v.co - c).dot(n) for v in verts)
            limit = extent * fraction
            for v in verts:
                d = (v.co - c).dot(n)
                if d > limit:
                    v.co -= n * (d - limit)

    def disc(self, center, radius, material_, sides=10, jitter=0.12, tint=None):
        """A flat, ragged polygon facing up: a stain on the ground."""
        c = Vector(center)
        a0 = self.rng.uniform(0.0, math.tau)
        verts = []
        for k in range(sides):
            a = a0 + k / sides * math.tau
            r = radius * (1.0 + self.rng.uniform(-jitter, jitter))
            verts.append(self.bm.verts.new(c + Vector((math.cos(a) * r, math.sin(a) * r, 0.0))))
        self._up_faces.append(self.bm.faces.new(verts))
        self._tag(verts, material_, False, tint)
        return verts

    def cone(self, base, height, radius, material_, segments=7, top_radius=0.0, jitter=0.0,
             tilt=(0.0, 0.0), tint=None, vary=0.0):
        """A (truncated) cone standing on `base`: conifer tiers, sprouts."""
        rng = self.rng
        m = (Matrix.Translation(Vector(base))
             @ Matrix.Rotation(tilt[0], 4, "X") @ Matrix.Rotation(tilt[1], 4, "Y")
             @ Matrix.Rotation(rng.uniform(0.0, math.tau), 4, "Z")
             @ Matrix.Translation((0.0, 0.0, height / 2.0)))
        made = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=True, segments=segments,
                                     radius1=radius, radius2=top_radius, depth=height, matrix=m)
        verts = made["verts"]
        if jitter:
            for v in verts:
                v.co += Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.5, 0.5))) * jitter
        self._tag(verts, material_, False, tint, vary)
        return verts

    def tube(self, points, radii, material_, segments=6, smooth=True, cap_start=False, tint=None, profile=None):
        """A tapered tube along a polyline: trunks, branches, twigs. Closes to a point when the
        last radius is 0. `profile(i, k, angle)`, if given, returns (radius factor, colour factor)
        for ring i's vertex k, at that angle round the tube (from its first side: +x for an upright
        tube): bark's ridges and grooves, buttresses."""
        bm = self.bm
        rings = []
        ref = Vector((1.0, 0.0, 0.0))
        twist = self.rng.uniform(0.0, math.tau)
        pts = [Vector(p) for p in points]
        shades = {}
        for i, p in enumerate(pts):
            if i == 0:
                t = pts[1] - pts[0]
            elif i == len(pts) - 1:
                t = pts[-1] - pts[-2]
            else:
                t = (pts[i + 1] - pts[i]).normalized() + (pts[i] - pts[i - 1]).normalized()
            t.normalize()
            # A frame that turns smoothly along the tube (avoids ring twisting at bends).
            side = ref - t * ref.dot(t)
            if side.length < 1e-4:
                side = Vector((0.0, 1.0, 0.0)) - t * t.y
            side.normalize()
            ref = side
            up = t.cross(side)
            r = radii[i]
            if r <= 0.0:
                rings.append([bm.verts.new(p)])
                continue
            ring = []
            for k in range(segments):
                a = twist + k / segments * math.tau
                f = 1.0
                if profile is not None:
                    f, c = profile(i, k, a)
                ring.append(bm.verts.new(p + (side * math.cos(a) + up * math.sin(a)) * r * f))
                if profile is not None:
                    shades[ring[-1]] = c
            rings.append(ring)
        all_verts = []
        for a, b in zip(rings, rings[1:]):
            all_verts += a
            if len(b) == 1:
                for k in range(segments):
                    bm.faces.new((a[k], a[(k + 1) % segments], b[0]))
            else:
                for k in range(segments):
                    bm.faces.new((a[k], a[(k + 1) % segments], b[(k + 1) % segments], b[k]))
        all_verts += rings[-1]
        if len(rings[-1]) > 1:
            bm.faces.new(rings[-1])
        if cap_start:
            bm.faces.new(list(reversed(rings[0])))
        faces = self._tag(all_verts, material_, smooth, tint)
        if shades:
            for f in faces:
                for loop in f.loops:
                    k = shades.get(loop.vert, 1.0)
                    c = loop[self.color]
                    loop[self.color] = (c[0] * k, c[1] * k, c[2] * k, 1.0)
        return all_verts

    def card(self, center, size, facing, material_, tint=None, spin=None, normal=None, stretch=1.0):
        """A leaf card: one square, `size` tiles across, facing `facing`, with UVs 0-1 over it.
        The client cuts the leaves out of it (factorio_material_leaf.gdshader) and draws both
        sides; `normal` (the crown's outward direction there) is what both sides are lit by, so
        the cards shade like one leafy mass rather than a heap of flat squares."""
        bm = self.bm
        if self._uv is None:
            self._uv = bm.loops.layers.uv.new("UVMap")
            self._card_id = bm.faces.layers.int.new("card")
        f = Vector(facing).normalized()
        spin = self.rng.uniform(0.0, math.tau) if spin is None else spin
        rot = _aim(f) @ Matrix.Rotation(spin, 4, "Z")
        h = size / 2.0
        corners = [Vector((-h, -h * stretch, 0.0)), Vector((h, -h * stretch, 0.0)), Vector((h, h * stretch, 0.0)),
                   Vector((-h, h * stretch, 0.0))]
        verts = [bm.verts.new(Vector(center) + (rot @ c.to_4d()).to_3d()) for c in corners]
        face = bm.faces.new(verts)
        for loop, uv in zip(face.loops, ((0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0))):
            loop[self._uv].uv = uv
        self._card_normals.append(Vector(normal or f).normalized())
        face[self._card_id] = len(self._card_normals)
        self._card_faces.append((face, f))  # keeps its winding facing `facing`
        self._tag(verts, material_, False, tint)
        return face

    # --- output -------------------------------------------------------------------------------

    def triangles(self):
        return sum(len(f.verts) - 2 for f in self.bm.faces)

    def to_object(self):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces[:])
        for f in self._up_faces:  # single flat faces have no inside to point away from
            if f.normal.z < 0.0:
                f.normal_flip()
        for f, facing in self._card_faces:
            f.normal_update()
            if f.normal.dot(facing) < 0.0:
                f.normal_flip()
        mesh = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        if self._card_normals:
            # Leaf cards carry the crown's normal on every corner (glTF exports corner normals);
            # zero leaves every other corner's normal as Blender works it out.
            ids = [0] * len(mesh.polygons)
            mesh.attributes["card"].data.foreach_get("value", ids)
            normals = [(0.0, 0.0, 0.0)] * len(mesh.loops)
            for poly, card in zip(mesh.polygons, ids):
                if card:
                    n = tuple(self._card_normals[card - 1])
                    for li in poly.loop_indices:
                        normals[li] = n
            mesh.normals_split_custom_set(normals)
            mesh.attributes.remove(mesh.attributes["card"])
        mesh.color_attributes.active_color_name = "Color"
        mesh.color_attributes.render_color_index = mesh.color_attributes.active_color_index
        for m in self.materials:
            mesh.materials.append(m)
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        return obj


def bend(points, rng, amount):
    """Wobbles the inner points of a polyline sideways, for less ruler-straight wood."""
    out = [Vector(points[0])]
    for p in points[1:-1]:
        out.append(Vector(p) + Vector((rng.uniform(-amount, amount), rng.uniform(-amount, amount), 0.0)))
    out.append(Vector(points[-1]))
    return out


def branch_path(start, direction, length, steps, rng, droop=0.0, wobble=0.08):
    """Points along a branch from `start`, heading `direction`, sagging by `droop` at the end."""
    d = Vector(direction).normalized()
    pts = [Vector(start)]
    for i in range(1, steps + 1):
        f = i / steps
        p = Vector(start) + d * (length * f)
        p.z -= droop * f * f
        if i < steps:
            p += Vector((rng.uniform(-wobble, wobble), rng.uniform(-wobble, wobble), rng.uniform(-wobble, wobble)))
        pts.append(p)
    return pts


def polar(angle, elevation):
    """Unit vector at compass `angle` (radians, from +X) tilted up by `elevation`."""
    c = math.cos(elevation)
    return Vector((math.cos(angle) * c, math.sin(angle) * c, math.sin(elevation)))
