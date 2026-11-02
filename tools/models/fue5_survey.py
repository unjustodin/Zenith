# Blender: import every FUE5 FBX and report objects, sizes, materials and textures (JSON).
#   blender --background --factory-startup --python tools/models/fue5_survey.py -- RAW_DIR OUT.json
import bpy, sys, os, json, glob
from mathutils import Vector

RAW = sys.argv[sys.argv.index("--") + 1]
OUT = sys.argv[sys.argv.index("--") + 2]
res = {}
for f in sorted(glob.glob(os.path.join(RAW, "*", "*", "*.fbx"))):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    try:
        bpy.ops.import_scene.fbx(filepath=f)
    except Exception as e:
        res[os.path.relpath(f, RAW)] = {"error": str(e)}
        continue
    objs = []
    lo = Vector((1e9,) * 3)
    hi = Vector((-1e9,) * 3)
    tris = 0
    for o in bpy.data.objects:
        d = {"name": o.name, "type": o.type, "parent": o.parent.name if o.parent else None,
             "anim": bool(o.animation_data and o.animation_data.action)}
        if o.type == "MESH":
            me = o.data
            t = sum(len(p.vertices) - 2 for p in me.polygons)
            tris += t
            d["tris"] = t
            d["mats"] = [m.name if m else None for m in me.materials]
            d["uvs"] = [u.name for u in me.uv_layers]
            olo = Vector((1e9,) * 3)
            ohi = Vector((-1e9,) * 3)
            for v in o.bound_box:
                w = o.matrix_world @ Vector(v)
                olo = Vector(map(min, olo, w))
                ohi = Vector(map(max, ohi, w))
            d["lo"] = [round(x, 3) for x in olo]
            d["hi"] = [round(x, 3) for x in ohi]
            lo = Vector(map(min, lo, olo))
            hi = Vector(map(max, hi, ohi))
        objs.append(d)
    mats = {}
    for m in bpy.data.materials:
        imgs = []
        if m.use_nodes:
            for n in m.node_tree.nodes:
                if n.type == "TEX_IMAGE" and n.image:
                    imgs.append([os.path.basename(n.image.filepath), n.image.size[0]])
        mats[m.name] = imgs
    res[os.path.relpath(f, RAW)] = {"lo": [round(x, 3) for x in lo], "hi": [round(x, 3) for x in hi],
                                     "tris": tris, "objects": objs, "materials": mats,
                                     "actions": [a.name for a in bpy.data.actions]}
json.dump(res, open(OUT, "w"), indent=1)
