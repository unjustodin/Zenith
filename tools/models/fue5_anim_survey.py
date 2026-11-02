# Blender: what moves in FUE5's animated FBX files: per bone, its head (tiles, after the 2-units-a-tile
# scale), the vertices it carries, and how its pose changes over the action (rotation axis and
# angle, translation), sampled across the frames.
#   blender --background --factory-startup --python tools/models/fue5_anim_survey.py -- RAW_DIR OUT.json
import bpy, sys, os, json, glob
from mathutils import Vector

RAW = sys.argv[sys.argv.index("--") + 1]
OUT = sys.argv[sys.argv.index("--") + 2]
res = {}
for f in sorted(glob.glob(os.path.join(RAW, "*", "*", "animated*.fbx"))) + sorted(glob.glob(os.path.join(RAW, "*", "*", "static.fbx"))):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=f)
    scene = bpy.context.scene
    arms = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    animated = [o for o in bpy.data.objects if o.animation_data and o.animation_data.action]
    if not arms and not animated:
        continue
    entry = {"bones": {}, "objects": {}}
    acts = [a for a in bpy.data.actions]
    lo, hi = 0, 0
    if acts:
        lo, hi = (int(x) for x in acts[0].frame_range)
    entry["frames"] = [lo, hi]
    frames = list(range(lo, hi + 1, max(1, (hi - lo) // 24)))
    for arm in arms:
        counts = {}
        for o in bpy.data.objects:
            if o.type == "MESH":
                names = {g.index: g.name for g in o.vertex_groups}
                for v in o.data.vertices:
                    if v.groups:
                        g = max(v.groups, key=lambda g: g.weight)
                        counts[names[g.group]] = counts.get(names[g.group], 0) + 1
        for b in arm.pose.bones:
            mats = []
            for fr in frames:
                scene.frame_set(fr)
                mats.append((arm.matrix_world @ b.matrix).copy())
            m0 = mats[0]
            maxang, axis, maxmove = 0.0, None, 0.0
            for m in mats[1:]:
                d = (m0.to_quaternion().inverted() @ m.to_quaternion())
                ax, ang = d.to_axis_angle()
                if abs(ang) > maxang:
                    maxang, axis = abs(ang), [round(x, 2) for x in (m0.to_3x3() @ ax).normalized()]
                maxmove = max(maxmove, (m.translation - m0.translation).length)
            entry["bones"][b.name] = {"head": [round(x / 2, 3) for x in m0.translation], "verts": counts.get(b.name, 0),
                                      "angle": round(maxang, 3), "axis": axis, "move": round(maxmove / 2, 3),
                                      "parent": b.parent.name if b.parent else None}
    for o in animated:
        if o.type == "ARMATURE":
            continue
        mats = []
        for fr in frames:
            scene.frame_set(fr)
            mats.append(o.matrix_world.copy())
        m0 = mats[0]
        maxang, axis, maxmove = 0.0, None, 0.0
        for m in mats[1:]:
            d = (m0.to_quaternion().inverted() @ m.to_quaternion())
            ax, ang = d.to_axis_angle()
            if abs(ang) > maxang:
                maxang, axis = abs(ang), [round(x, 2) for x in (m0.to_3x3() @ ax).normalized()]
            maxmove = max(maxmove, (m.translation - m0.translation).length)
        entry["objects"][o.name] = {"loc": [round(x / 2, 3) for x in m0.translation], "angle": round(maxang, 3),
                                    "axis": axis, "move": round(maxmove / 2, 3),
                                    "children": [c.name for c in o.children][:20]}
    res[os.path.relpath(f, RAW)] = entry
json.dump(res, open(OUT, "w"), indent=1)
