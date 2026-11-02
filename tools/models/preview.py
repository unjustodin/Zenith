"""Renders exported models side by side for a quick look, without the client.

    blender --background --factory-startup --python tools/models/preview.py -- OUT.png [names...]
        [--view=game|north|top|factorio] [--cols=N] [--size=1600x1000]

Each model stands on a grey tile grid inside its footprint outline (from specs.py), with a red
tick on the outline's north edge and its name in front. `game` looks from the south-east like
the client's default camera; `north` looks from the north at the models' fronts; `top` looks
straight down with north up; `factorio` looks from the south at the pitch of Factorio's sprites
(compare.py puts a model next to its sprite).
"""

import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import kit  # noqa: E402
import specs  # noqa: E402
from compare import FACTORIO_PITCH  # noqa: E402

MODELS_DIR = os.path.join(REPO, "client", "assets", "models")


def flat_material(name, rgb):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = 1.0
    return mat


def slab(name, x0, y0, x1, y1, z, h, mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=((x0 + x1) / 2, (y0 + y1) / 2, z + h / 2))
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (abs(x1 - x0), abs(y1 - y0), h)
    obj.data.materials.append(mat)
    return obj


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    view, cols, res = "game", 0, (1600, 1000)
    out, names = None, []
    for arg in argv:
        if arg.startswith("--view="):
            view = arg.split("=", 1)[1]
        elif arg.startswith("--cols="):
            cols = int(arg.split("=", 1)[1])
        elif arg.startswith("--size="):
            res = tuple(int(v) for v in arg.split("=", 1)[1].split("x"))
        elif out is None:
            out = os.path.abspath(arg)
        else:
            names.append(arg)
    if out is None:
        print("preview: give an output .png path")
        return 1
    if not names:
        names = sorted(f[:-4] for f in os.listdir(MODELS_DIR) if f.endswith(".glb"))

    kit.clear_scene()
    scene = bpy.context.scene
    ground = flat_material("ground", (0.16, 0.2, 0.1))
    outline = flat_material("outline", (0.02, 0.02, 0.02))
    north = flat_material("north", (0.8, 0.05, 0.03))

    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    if view == "top":
        direction = Vector((0, 0, 1))
    elif view == "factorio":
        p = math.radians(FACTORIO_PITCH)
        direction = Vector((0, -math.cos(p), math.sin(p)))
    elif view == "north":
        direction = Vector((0, math.cos(math.radians(35)), math.sin(math.radians(35))))
    else:  # the client's default: yaw 45, pitch 50, from the south-east
        p = math.radians(50)
        direction = Vector((math.cos(p) * math.sin(math.radians(45)), -math.cos(p) * math.cos(math.radians(45)), math.sin(p)))
    cam.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
    if view == "top":
        cam.rotation_euler = (0, 0, 0)
    rot = cam.rotation_euler.to_matrix()
    right, up = rot @ Vector((1, 0, 0)), rot @ Vector((0, 1, 0))
    # Lay the cells out along the screen's axes, so the grid fills the frame.
    right_g = Vector((right.x, right.y, 0)).normalized()
    fwd_g = Vector((-right_g.y, right_g.x, 0))
    cols = cols or max(1, math.ceil(math.sqrt(len(names) * 1.6)))
    cell = max(max(specs.SPECS.get(n, {"size": (2, 2)})["size"]) for n in names) + 1.5
    rows = math.ceil(len(names) / cols)
    for i, name in enumerate(names):
        pos = right_g * ((i % cols) * cell) - fwd_g * ((i // cols) * cell)
        cx, cy = pos.x, pos.y
        w, d = specs.SPECS.get(name, {"size": (1, 1)})["size"]
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=os.path.join(MODELS_DIR, name + ".glb"))
        for obj in set(bpy.data.objects) - before:
            if obj.parent is None:
                obj.location += Vector((cx, cy, 0))
        t = 0.025
        slab("o", cx - w / 2, cy - d / 2, cx + w / 2, cy - d / 2 + t, 0, 0.004, outline)
        slab("o", cx - w / 2, cy + d / 2 - t, cx + w / 2, cy + d / 2, 0, 0.004, north)
        slab("o", cx - w / 2, cy - d / 2, cx - w / 2 + t, cy + d / 2, 0, 0.004, outline)
        slab("o", cx + w / 2 - t, cy - d / 2, cx + w / 2, cy + d / 2, 0, 0.004, outline)
        bpy.ops.object.text_add()
        text = bpy.context.active_object
        text.location = Vector((cx, cy, 0.01)) - right_g * (cell / 2 - 0.2) - fwd_g * (cell / 2 - 0.25)
        text.rotation_euler = (0, 0, math.atan2(right_g.y, right_g.x))
        text.data.body = name
        text.data.size = min(0.32, cell * 0.07)
        text.data.materials.append(outline)

    span = (cols + rows) * cell
    slab("ground", -span, -span, span, span, -0.01, 0.01, ground)

    # Fit the cells (ground to 2.5 tiles up) into the frame.
    pts = []
    for col in (-0.5, cols - 0.5):
        for row in (-0.5, rows - 0.5):
            for z in (0.0, 2.5):
                pts.append(right_g * (col * cell) - fwd_g * (row * cell) + Vector((0, 0, z)))
    rs, us = [p.dot(right) for p in pts], [p.dot(up) for p in pts]
    cam.location = right * (min(rs) + max(rs)) / 2 + up * (min(us) + max(us)) / 2 + direction * 60
    cam_data.ortho_scale = max(max(rs) - min(rs), (max(us) - min(us)) * res[0] / res[1]) * 1.02
    cam_data.clip_end = 200
    scene.camera = cam

    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(40), math.radians(15), math.radians(30))
    scene.collection.objects.link(sun)
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.45, 0.5, 0.55, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.7
    scene.world = world

    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.filepath = out
    for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT", "CYCLES"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    if scene.render.engine == "CYCLES":
        scene.cycles.samples = 24
    bpy.ops.render.render(write_still=True)
    print("preview: wrote %s (%s)" % (out, scene.render.engine))
    return 0


if __name__ == "__main__":
    code = main()
    sys.stdout.flush()
    sys.exit(code)
