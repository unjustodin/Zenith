"""Builds the Nauvis nature models (trees, dead trees, rocks, ore tiles) and exports them as .glb.

    blender --background --factory-startup --python tools/models/nature/build_nature.py -- [names...]
        [--out DIR] [--preview FILE.png]

With no names it builds all of them. Output goes to client/assets/models/<name>.glb unless
--out says otherwise. --preview also renders the models lined up on a tile grid, for a quick
look without starting the client. Each model is seeded from its name, so rebuilding gives
identical files.

After adding new .glb files, import them: `godot --headless --path client --import`.

The models are matched to Factorio's own sprites: compare.py renders them from Factorio's camera
next to the sprite (read from the player's install, never committed) and prints both colours.
Shading lives in per-corner vertex colours (glTF COLOR_0 rgb, see geo.py); export adds the baked
weathering data (COLOR_0 alpha and TEXCOORD_1, tools/models/bake.py) that the client's Factorio
material reads (model_library.gd).
"""

import math
import os
import random
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))  # tools/models, for bake.py

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

REPO = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
TRI_BUDGET = 3000


def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)


def parse_args(argv):
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    names, out, preview = [], os.path.join(REPO, "client", "assets", "models"), None
    it = iter(argv)
    for a in it:
        if a == "--out":
            out = next(it)
        elif a == "--preview":
            preview = next(it)
        else:
            names.append(a)
    return names, out, preview


def export(obj, path):
    # Ambient occlusion (COLOR_0 alpha, next to the shading in rgb), worn edges and a random value
    # per piece (TEXCOORD_1) for the client's weathered material; see bake.py.
    import bake
    bake.bake_blender_objects([obj], keep_rgb=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=True, export_texcoords=True, export_vertex_color="ACTIVE",
                              export_extras=False)


def render_preview(objects, path):
    """Lays the models out on a grid and renders them from a Factorio-like high angle."""
    cols = 6
    spacing = 4.0
    for i, obj in enumerate(objects):
        obj.location = Vector(((i % cols) * spacing, -(i // cols) * spacing, 0.0))
    rows = (len(objects) + cols - 1) // cols
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=((cols - 1) * spacing / 2, -(rows - 1) * spacing / 2, 0.0))
    ground = bpy.context.object
    ground.scale = (cols * spacing, rows * spacing, 1.0)
    gm = bpy.data.materials.new("ground")
    gm.diffuse_color = (0.18, 0.2, 0.12, 1.0)
    ground.data.materials.append(gm)
    # One-tile grid lines would be nice; a checker is enough to judge scale.
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "MATERIAL"
    shading.show_shadows = True
    shading.show_cavity = False
    scene.render.resolution_x = 1800
    scene.render.resolution_y = 300 * rows + 300
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = cols * spacing + 1.0
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    centre = Vector(((cols - 1) * spacing / 2, -(rows - 1) * spacing / 2, 1.0))
    pitch = math.radians(50.0)
    cam.location = centre + Vector((0.0, -math.cos(pitch), math.sin(pitch))) * 40.0
    cam.rotation_euler = (math.pi / 2 - pitch, 0.0, 0.0)
    scene.camera = cam
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def registry():
    import cliffs
    import rocks
    import trees
    return {**trees.MODELS, **rocks.MODELS, **cliffs.MODELS}


def build(name, reg=None):
    """Builds one model into a new Blender object; returns (object, triangle count)."""
    from geo import Model
    import trees
    seed = trees.SEED_AS.get(name, name)
    m = Model(name, random.Random(zlib.crc32(seed.encode())))
    (reg or registry())[name](m)
    tris = m.triangles()
    return m.to_object(), tris


def main():
    registry_ = registry()
    names, out, preview = parse_args(sys.argv)
    unknown = [n for n in names if n not in registry_]
    if unknown:
        raise SystemExit("unknown model(s): %s (known: %s)" % (", ".join(unknown), ", ".join(registry_)))
    names = names or list(registry_)
    os.makedirs(out, exist_ok=True)
    clear_scene()
    built = []
    over = []
    for name in names:
        obj, tris = build(name, registry_)
        export(obj, os.path.join(out, name + ".glb"))
        lo = Vector([min(v.co[i] for v in obj.data.vertices) for i in range(3)])
        hi = Vector([max(v.co[i] for v in obj.data.vertices) for i in range(3)])
        print("%-22s %5d tris  x %5.2f..%5.2f  y %5.2f..%5.2f  z %5.2f..%5.2f"
              % (name, tris, lo.x, hi.x, lo.y, hi.y, lo.z, hi.z))
        if tris > TRI_BUDGET:
            over.append(name)
        built.append(obj)
    print("built %d model(s) into %s" % (len(built), out))
    print("next, part colours from the sprites: python tools/models/part_colors.py %s" % " ".join(names))
    if over:
        print("OVER BUDGET (%d tris): %s" % (TRI_BUDGET, ", ".join(over)))
    if preview:
        render_preview(built, os.path.abspath(preview))


if __name__ == "__main__":
    main()
