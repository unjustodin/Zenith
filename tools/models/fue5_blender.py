"""Blender side of fue5.py: one FUE5 FBX (or several) to one client model.

    blender --background --factory-startup --python tools/models/fue5_blender.py -- JOB.json

JOB: {"fbx": [paths], "out": path.glb, "yaw": degrees (clockwise from above), "budget": triangles,
      "tex": atlas size, "drop": [object name prefixes], "anim": {node name: [ancestor names]},
      "pivot": {node name: [x, y, z] in tiles, or "centre"}, "centre": [x, y] in tiles or null,
      "shift": [x, y, z] tiles, "scale": [sx, sy, sz], "name": material name}

FUE5's models are Cinema 4D exports: 2 units a tile, Z up. Flat see-through ground decals
(scorch marks) are dropped. Every texture is baked into one atlas on a fresh UV map, so the
model has one material with one base colour texture (embedded in the .glb as JPEG).
"""

import json
import math
import sys

import bpy
from mathutils import Matrix, Vector

job = json.load(open(sys.argv[sys.argv.index("--") + 1]))
bpy.ops.wm.read_factory_settings(use_empty=True)
file_of = {}  # object name -> index of the FBX it came from
for i, f in enumerate(job["fbx"]):
    before = set(bpy.data.objects.keys())
    bpy.ops.import_scene.fbx(filepath=f)
    for name in set(bpy.data.objects.keys()) - before:
        file_of[name] = i


def ancestors(o):
    out = []
    p = o.parent
    while p is not None:
        out.append(p.name)
        p = p.parent
    return out


# Which moving part each mesh belongs to, from its own and its parents' names.
group_of = {}
ancestry = {}  # mesh name -> its own and its parents' names
for o in bpy.data.objects:
    if o.type != "MESH":
        continue
    names = [o.name] + ancestors(o)
    ancestry[o.name] = names
    # A whole file as one moving part (`file_parts`: {index: part}), like a turret's head.
    group_of[o.name] = job.get("file_parts", {}).get(str(file_of.get(o.name, 0)), "")
    for part, keys in job.get("anim", {}).items():
        if any(n == k or n.startswith(k + ".") for n in names for k in keys):
            group_of[o.name] = part
            break
    if any(n.startswith(p) for n in names for p in job.get("drop", [])):
        group_of[o.name] = None

# Bake each mesh into world space with its own data.
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
for o in meshes:
    o.data = o.data.copy()
    m = o.matrix_world.copy()
    o.parent = None
    o.data.transform(m)
    o.matrix_world = Matrix.Identity(4)
    for mod in list(o.modifiers):
        o.modifiers.remove(mod)


# Skinned meshes (FUE5's animated*.fbx): faces carried by a recipe's bones become that moving part
# (`bones`: {part: [bone names]}), drawn at rest; the first bone's head is the part's pivot.
pivots = {}
import bmesh  # noqa: E402
arm = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
for part, bone_names in job.get("bones", {}).items():
    if arm is None:
        break
    bone = arm.data.bones.get(bone_names[0])
    if bone is not None:
        pivots[part] = arm.matrix_world @ bone.head_local
    for o in list(meshes):
        if not o.vertex_groups or o.name not in group_of:
            continue
        ids = {g.index for g in o.vertex_groups if g.name in bone_names}
        carried = {v.index for v in o.data.vertices if v.groups and max(v.groups, key=lambda g: g.weight).group in ids}
        if not carried:
            continue
        piece = o.copy()
        piece.data = o.data.copy()
        bpy.context.collection.objects.link(piece)
        for ob, keep in ((piece, True), (o, False)):
            bm = bmesh.new()
            bm.from_mesh(ob.data)
            gone = [f for f in bm.faces if all(v.index in carried for v in f.verts) != keep]
            bmesh.ops.delete(bm, geom=gone, context="FACES")
            bm.to_mesh(ob.data)
            bm.free()
        group_of[piece.name] = part
        meshes.append(piece)


def moved(m):
    for k in pivots:
        pivots[k] = m @ pivots[k]


def has_image(mat):
    if mat is None or not mat.use_nodes:
        return False
    return any(n.type == "TEX_IMAGE" and n.image and n.image.size[0] > 0 for n in mat.node_tree.nodes)


def has_alpha(mat):
    if mat is None or not mat.use_nodes:
        return False
    return any(n.type == "TEX_IMAGE" and n.image and "alpha" in n.image.name.lower() for n in mat.node_tree.nodes)


for o in list(bpy.data.objects):
    if o.type != "MESH":
        bpy.data.objects.remove(o)
        continue
    zs = [v.co.z for v in o.data.vertices]
    flat = not zs or max(zs) - min(zs) < 0.06
    decal = flat and o.data.materials and all(has_alpha(m) for m in o.data.materials)
    # Effect cards whose pictures are image sequences Unreal plays (the accumulator's lightning)
    # come without a texture: left out.
    effect = o.data.materials and not any(has_image(m) for m in o.data.materials)
    if group_of.get(o.name) is None or decal or effect or not o.data.polygons:
        bpy.data.objects.remove(o)

# Units and facing: 2 units a tile, then turned so the front faces north (+Y).
yaw = math.radians(job.get("yaw", 0))
sx, sy, sz = job.get("scale", [1, 1, 1])
xf = Matrix.Diagonal((0.5 * sx, 0.5 * sy, 0.5 * sz, 1)) @ Matrix.Rotation(-yaw, 4, "Z")
for o in bpy.data.objects:
    o.data.transform(xf)
moved(xf)

lo = Vector((1e9,) * 3)
hi = Vector((-1e9,) * 3)
for o in bpy.data.objects:
    for v in o.data.vertices:
        lo = Vector(map(min, lo, v.co))
        hi = Vector(map(max, hi, v.co))
# FUE5 puts each model's origin on its footprint centre; "bbox" centres the bounds instead.
if job.get("centre") == "bbox":
    cx, cy = (lo.x + hi.x) / 2, (lo.y + hi.y) / 2
else:
    cx, cy = job.get("centre") or (0.0, 0.0)
dx, dy, dz = job.get("shift", [0, 0, 0])
move = Matrix.Translation((-cx + dx, -cy + dy, dz))
for o in bpy.data.objects:
    o.data.transform(move)
moved(move)

# Inside the footprint (check.py: an overhang of 0.03 a side), scaled evenly about the centre.
over = max(0.01, job.get("overhang", 0.0) / 2 - 0.01)  # check.py: the overhang is over the whole width
half_x, half_y = job["size"][0] / 2 + over, job["size"][1] / 2 + over
ext_x = max(abs(v.co.x) for o in bpy.data.objects for v in o.data.vertices)
ext_y = max(abs(v.co.y) for o in bpy.data.objects for v in o.data.vertices)
if job.get("fit") == "width":  # off-centre by design (a train stop's arm over the rails): only its width
    xs = [v.co.x for o in bpy.data.objects for v in o.data.vertices]
    ys = [v.co.y for o in bpy.data.objects for v in o.data.vertices]
    ext_x, ext_y = (max(xs) - min(xs)) / 2, (max(ys) - min(ys)) / 2
fit = min(1.0, half_x / ext_x, half_y / ext_y)
if fit < 1.0:
    print("FUE5 scaled by %.3f to fit its footprint" % fit)
    for o in bpy.data.objects:
        o.data.transform(Matrix.Diagonal((fit, fit, fit, 1)))
    moved(Matrix.Diagonal((fit, fit, fit, 1)))

# A hatch cut in two (`hatch`: faces of `mats` lower than `zmax` tiles): the plate, cut to a circle of
# `radius` tiles (24 planes) and in half at x = 0, becomes the `west` and `east` parts.
hatch = job.get("hatch")
door_pieces = []
if hatch:
    for o in list(bpy.data.objects):
        mats = [m.name if m else "" for m in o.data.materials]
        bm = bmesh.new()
        bm.from_mesh(o.data)
        is_plate = lambda f: f.material_index < len(mats) and mats[f.material_index] in hatch["mats"]
        # Whatever else lies in the group the plate belongs to (`clear`: FUE5's half-open iris over
        # its hatch) goes: its dark leaves would cover the doors once raised.
        if hatch.get("clear") in ancestry.get(o.name, ()):
            others = [f for f in bm.faces if not is_plate(f)]
            if others:
                bmesh.ops.delete(bm, geom=others, context="FACES")
                bm.to_mesh(o.data)
        plate = {f.index for f in bm.faces if is_plate(f) and f.calc_center_median().z < hatch["zmax"]}
        bm.free()
        if not plate:
            continue
        for side, sign in (("west", -1.0), ("east", 1.0)):
            piece = o.copy()
            piece.data = o.data.copy()
            bpy.context.collection.objects.link(piece)
            bm = bmesh.new()
            bm.from_mesh(piece.data)
            bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index not in plate], context="FACES")
            cuts = [((0, 0, 0), (sign, 0, 0), True)]
            for k in range(24):
                a = k * math.tau / 24
                n = (math.cos(a), math.sin(a), 0)
                cuts.append(((n[0] * hatch["radius"], n[1] * hatch["radius"], 0), n, False))
            for co, no, inner in cuts:
                geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
                bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=no, clear_inner=inner, clear_outer=not inner)
            # Both sides: some of FUE5's plate faces down (it was seen from above only, through its
            # ground's hole), which left wedges of the door missing once raised.
            back = bmesh.ops.duplicate(bm, geom=bm.faces[:])
            bmesh.ops.reverse_faces(bm, faces=[f for f in back["geom"] if isinstance(f, bmesh.types.BMFace)])
            bm.to_mesh(piece.data)
            bm.free()
            group_of[piece.name] = hatch[side]
            door_pieces.append(piece)
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index in plate], context="FACES")
        bm.to_mesh(o.data)
        bm.free()

# The plate's pieces together up from where FUE5 sank them to just over the ground (`lift_to`, the
# plate's lowest point), so its layers stay as they were.
if hatch and "lift_to" in hatch and door_pieces:
    low = min(v.co.z for o in door_pieces for v in o.data.vertices)
    for o in door_pieces:
        o.data.transform(Matrix.Translation((0, 0, hatch["lift_to"] - low)))

# Nothing below the ground (FUE5's silo shaft goes 4.5 tiles down) past the spec's `sink`; after the
# hatch is taken out of it.
floor = -max(0.0, job.get("sink", 0.0) - 0.03)  # a little inside it: decimation moves points
for o in list(bpy.data.objects):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    if min((v.co.z for v in bm.verts), default=0) < floor - 1e-4:
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, floor), plane_no=(0, 0, 1), clear_inner=True)
        bm.to_mesh(o.data)
    bm.free()
    if not o.data.polygons:
        bpy.data.objects.remove(o)

# The pit under a hatch (`pit`: radius and height in tiles): a dark, grimy floor just over the
# ground, as our own silo has, since the client draws the ground over anything below it.
pit = job.get("pit")
if pit:
    mat = bpy.data.materials.new("fue5_pit")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 6.0
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.012, 0.011, 0.010, 1)
    ramp.color_ramp.elements[1].color = (0.06, 0.05, 0.04, 1)
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    bpy.ops.mesh.primitive_circle_add(vertices=48, radius=pit["radius"], fill_type="TRIFAN",
                                      location=(0, 0, pit["z"]))
    disc = bpy.context.active_object
    disc.name = "pit"
    disc.data.materials.append(mat)
    bpy.ops.object.transform_apply(location=True)
    group_of[disc.name] = ""

# Our model's size (`match`: [east-west, north-south, height] in tiles; `match_all`: every axis
# exactly, for rolling stock that must fill its length and couple as ours do): an axis more than
# MATCH_SLACK off is scaled to ours, all of them alike when that is enough; a horizontal axis is
# never squeezed under 0.9 of the footprint (ours are drawn shallow where the sprite's camera
# foreshortens them) nor stretched past what check.py allows.
MATCH_SLACK = 0.08
match = job.get("match")
if match:
    vs = [v.co for o in bpy.data.objects for v in o.data.vertices]
    cur = [max(v[i] for v in vs) - min(v[i] for v in vs) for i in range(3)]
    s = [m / c if c > 1e-6 else 1.0 for m, c in zip(match, cur)]
    if not job.get("match_all"):
        s = [k if abs(k - 1.0) > MATCH_SLACK else 1.0 for k in s]
        for i in (0, 1):
            low = 0.9 * job["size"][i] / cur[i]
            high = (job["size"][i] + job.get("overhang", 0.03) - 0.01) / cur[i]
            s[i] = min(max(s[i], min(low, 1.0)), max(high, 1.0))
        if max(s) / min(s) <= 1.0 + MATCH_SLACK:
            s = [(s[0] * s[1] * s[2]) ** (1 / 3)] * 3
    print("FUE5 matched to ours: x%.3f x%.3f x%.3f" % tuple(s))
    m = Matrix.Diagonal((s[0], s[1], s[2], 1))
    for o in bpy.data.objects:
        o.data.transform(m)
    moved(m)

# Parts put where the client expects them (`place`: groups of FUE5's objects by name, moved so
# their `anchor` (top or middle) is at `to`, glTF tiles x east, y up, z south; `copy` adds one
# instead): a pole's insulators on Factorio's wire connection points (wires.gd POLE_POINTS).
for entry in job.get("place", []):
    chosen = [o for o in list(bpy.data.objects)
              if any(n == g or n.startswith(g + ".") for n in ancestry.get(o.name, ()) for g in entry["groups"])]
    if not chosen:
        print("FUE5 place: nothing named", entry["groups"])
        continue
    if entry.get("copy"):
        copies = []
        for o in chosen:
            c = o.copy()
            c.data = o.data.copy()
            bpy.context.collection.objects.link(c)
            group_of[c.name] = group_of.get(o.name, "")
            copies.append(c)
        chosen = copies
    vs = [v.co for o in chosen for v in o.data.vertices]
    lo = Vector([min(v[i] for v in vs) for i in range(3)])
    hi = Vector([max(v[i] for v in vs) for i in range(3)])
    at = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, hi.z if entry.get("anchor") == "top" else (lo.z + hi.z) / 2))
    tx, ty, tz = entry["to"]  # null keeps that coordinate
    goal = Vector((at.x if tx is None else tx, at.y if tz is None else -tz, at.z if ty is None else ty))
    step = Matrix.Translation(goal - at)
    for o in chosen:
        o.data.transform(step)

# One object per group: the body, and each moving part.
groups = {}
for o in list(bpy.data.objects):
    groups.setdefault(group_of[o.name], []).append(o)
objs = {}
for g, members in groups.items():
    bpy.ops.object.select_all(action="DESELECT")
    for o in members:
        o.select_set(True)
    bpy.context.view_layer.objects.active = members[0]
    if len(members) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = g or "body"
    objs[g] = ob

# Triangle budget: decimate every object by the same ratio.
def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)

total = sum(tris(o) for o in objs.values())
budget = job.get("budget", 10000)
print("FUE5 triangles", total, "budget", budget)
if total > budget:
    # Small pieces (a plate cut as doors, a fan) keep every triangle: collapsing their few would
    # open holes. The rest share what is left of the budget.
    small = [o for o in objs.values() if tris(o) < 300]
    big = [o for o in objs.values() if o not in small]
    ratio = max(0.01, (budget - sum(tris(o) for o in small)) / max(1, sum(tris(o) for o in big)))
    for o in big:
        mod = o.modifiers.new("dec", "DECIMATE")
        mod.ratio = ratio
        mod.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier=mod.name)
    print("FUE5 decimated to", sum(tris(o) for o in objs.values()))

# Atlas: a fresh UV map over every object, packed together, each texture baked into it.
size = job.get("tex", 2048)
atlas = bpy.data.images.new("atlas", size, size)
for o in objs.values():
    src = o.data.uv_layers[0].name if o.data.uv_layers else None
    o["src_uv"] = src or ""
    uv = o.data.uv_layers.new(name="atlas")
    o.data.uv_layers.active = uv
for mat in bpy.data.materials:
    if not mat.use_nodes:
        continue
    nt = mat.node_tree
    for n in list(nt.nodes):
        if n.type == "TEX_IMAGE" and not n.inputs["Vector"].is_linked:
            uvn = nt.nodes.new("ShaderNodeUVMap")
            uvn.uv_map = "UVMap"
            nt.links.new(uvn.outputs["UV"], n.inputs["Vector"])
    target = nt.nodes.new("ShaderNodeTexImage")
    target.image = atlas
    nt.nodes.active = target
# UV maps named per object: point each texture at its object's own map.
for o in objs.values():
    for mat in o.data.materials:
        if mat and mat.use_nodes:
            for n in mat.node_tree.nodes:
                if n.type == "UVMAP":
                    n.uv_map = o["src_uv"]

bpy.ops.object.select_all(action="DESELECT")
for o in objs.values():
    o.select_set(True)
bpy.context.view_layer.objects.active = next(iter(objs.values()))
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.002, area_weight=0.0, scale_to_bounds=False)
bpy.ops.uv.pack_islands(margin=0.002)
bpy.ops.object.mode_set(mode="OBJECT")

scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 1
scene.render.bake.use_pass_direct = False
scene.render.bake.use_pass_indirect = False
scene.render.bake.use_pass_color = True
scene.render.bake.margin = 6
bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, use_clear=True, margin=6)

# One material: the atlas on the atlas map.
mat = bpy.data.materials.new(job.get("name", "fue5"))
mat.use_nodes = True
nt = mat.node_tree
bsdf = nt.nodes["Principled BSDF"]
bsdf.inputs["Roughness"].default_value = 0.7
bsdf.inputs["Metallic"].default_value = 0.0
tex = nt.nodes.new("ShaderNodeTexImage")
tex.image = atlas
nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
atlas.file_format = "JPEG"
for o in objs.values():
    o.data.materials.clear()
    o.data.materials.append(mat)
    for uv in list(o.data.uv_layers):
        if uv.name != "atlas":
            o.data.uv_layers.remove(uv)
    o.data.uv_layers["atlas"].name = "UVMap"

# Moving parts: their origin on the pivot.
for g, o in objs.items():
    if not g:
        continue
    piv = job.get("pivot", {}).get(g, "bone" if g in pivots else "centre")
    if piv == "bone":
        piv = list(pivots[g])
    elif piv == "axis":  # on the model's vertical middle line, at the part's foot
        piv = [0.0, 0.0, min(v.co.z for v in o.data.vertices)]
    elif piv == "bbox":
        vs = [v.co for v in o.data.vertices]
        piv = [(min(v[i] for v in vs) + max(v[i] for v in vs)) / 2 for i in range(3)]
    elif piv == "centre":
        vs = [v.co for v in o.data.vertices]
        c = sum(vs, Vector()) / len(vs)
        piv = [c.x, c.y, min(v.z for v in vs)]
    p = Vector(piv)
    o.data.transform(Matrix.Translation(-p))
    o.location = p

bpy.ops.export_scene.gltf(filepath=job["out"], export_format="GLB", export_image_format="JPEG",
                          export_jpeg_quality=88, export_yup=True, export_apply=True,
                          export_animations=False, export_skins=False, export_morph=False,
                          export_cameras=False, export_lights=False)
print("FUE5 wrote", job["out"], {g or "body": tris(o) for g, o in objs.items()})
