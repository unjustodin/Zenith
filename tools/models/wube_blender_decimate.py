"""Run by tools/models/wube.py inside Blender: decimates meshes with Blender's collapse decimator,
which keeps print models' shapes far better than the plain-Python quadric simplifier at the
ratios the client needs (a 470k-triangle print down to 10k).

    blender --background --factory-startup --python wube_blender_decimate.py -- IN.npz OUT.npz

IN.npz holds v0, f0, n0 (target triangles), v1, f1, n1, ...; OUT.npz the same without targets.
"""

import sys

import bmesh
import bpy
import numpy as np

src, out = sys.argv[sys.argv.index("--") + 1:][:2]
data = np.load(src)
result = {}
i = 0
while "v%d" % i in data:
    v, f, n = data["v%d" % i], data["f%d" % i], int(data["n%d" % i])
    mesh = bpy.data.meshes.new("m%d" % i)
    mesh.from_pydata(v.tolist(), [], f.tolist())
    mesh.validate()
    obj = bpy.data.objects.new("m%d" % i, mesh)
    bpy.context.scene.collection.objects.link(obj)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(mesh)
    bm.free()
    if len(mesh.polygons) > n:
        mod = obj.modifiers.new("decimate", "DECIMATE")
        mod.ratio = n / len(mesh.polygons)
        mod.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier="decimate")
    mesh = obj.data
    mesh.calc_loop_triangles()
    verts = np.empty(len(mesh.vertices) * 3, dtype=np.float64)
    mesh.vertices.foreach_get("co", verts)
    tris = np.empty(len(mesh.loop_triangles) * 3, dtype=np.int64)
    mesh.loop_triangles.foreach_get("vertices", tris)
    result["v%d" % i] = verts.reshape(-1, 3)
    result["f%d" % i] = tris.reshape(-1, 3)
    i += 1
np.savez(out, **result)
print("decimated %d meshes" % i)
