"""Renders a model from Factorio's camera next to a frame of its 2D sprite, to match them.

    blender --background --factory-startup --python tools/models/compare.py -- OUT.png NAME
        --sprite=SHEET.png --frame=WxH [--index=N] [--line=L] [--shift=X,Y] [--scale=0.5]
        [--layer=SHEET.png|WxH|INDEX|LINE|X,Y[|SCALE] ...] [--rot=DEG] [--head=DEG] [--pitch=DEG]
        [--anchor=Z] [--zoom=3] [--glb=PATH] [--stretch=S] [--model-scale=S] [--palette=1]
        [--shadowless=1] [--keep-upright=1] [--diff=PATH] [--offset=DX,DZ] [--hide=PREFIX,...]

The sprite sheet is read from the player's Factorio install (`<Factorio>/data/base/graphics/
entity/...`) and only drawn into OUT.png, which belongs in a scratch folder: never commit it.
`--frame`, `--line`, `--shift` and `--scale` are copied from the prototype definition (shift in
`util.by_pixel` units); `--index` picks the frame (row-major, `--line` frames per row; 0 means
the whole sheet width). Use `--index=@X,Y` for atlases with frames at irregular pixel coordinates.
Each `--layer` stacks another sprite on top (a turret's head on its base), positioned by its own shift.

OUT.png has three panels at `--zoom`x: the sprite frame, the model rendered with the same
camera, scale and anchor (in its part colours, as the client draws it; `--palette=1` shows the
materials' own colours), and an overlay (the sprite in grey, the model's outline in red, the
sprite's in cyan, leaving out shadows baked into the sprite), with the footprint on the ground in
yellow. `--diff=PATH` also saves where the silhouettes disagree (cyan: only the sprite, red: only
the model). The average colour of each is printed, to tune materials.

`--stretch` scales north-south distances on the ground before projecting, for sprites drawn
longer north-south than the camera gives (pipes, the offshore pump: their tiles are square on
screen, so S = 1 / sin(48 degrees) = 1.346); the client does the same with the entry's `stretch`.

`--shadowless=1` leaves shadows baked into the sprite (near-black, not fully opaque pixels) out of
its silhouette before measuring the overlap (tools/models/score_world.py passes it).

`--offset=DX,DZ` moves the model in its own frame before it is turned (tiles east and south), as
the client's model_library.gd PLACEMENT_OFFSETS do for rail signals.
`--keep-upright=1` leaves `anim_upright_*` parts facing north, as the client does (the pumpjack's
frame), so stack their own layer with `--layer`. `--rot` turns the whole model (degrees clockwise seen from above: 90 faces east, like the
client), `--head` turns only the `anim_turret_head` node (for turret rotation frames).

Factorio's sprites are rendered with an orthographic camera looking down from the south. The
pitch (FACTORIO_PITCH) was fitted against round things in the sprites (the lab's ground ring,
the gun turret's toothed ring): horizontal circles show as ellipses about 0.75 as tall as wide.
The sprite's anchor (the entity's position) sits FACTORIO_ANCHOR_Z above the ground.
"""

import math
import os
import sys
import tempfile

import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import kit  # noqa: E402
import specs  # noqa: E402

MODELS_DIR = os.path.join(REPO, "client", "assets", "models")
FACTORIO_PITCH = 48.0   # degrees below the horizon
FACTORIO_ANCHOR_Z = 0.3  # tiles above the ground that the entity's position marks
BACKGROUND = (0.16, 0.22, 0.12)


def factorio_camera(scene, pitch=FACTORIO_PITCH, centre=(0.0, 0.0), width_tiles=4.0):
    """An orthographic camera looking north and down at `pitch`; `centre` is the screen point
    (tiles right, tiles up from the projected origin) at the middle of the frame."""
    data = bpy.data.cameras.new("factorio")
    data.type = "ORTHO"
    data.sensor_fit = "HORIZONTAL"
    data.ortho_scale = width_tiles
    data.clip_end = 200
    cam = bpy.data.objects.new("factorio", data)
    scene.collection.objects.link(cam)
    p = math.radians(pitch)
    forward = Vector((0, math.cos(p), -math.sin(p)))
    up = Vector((0, math.sin(p), math.cos(p)))
    cam.rotation_euler = forward.to_track_quat("-Z", "Y").to_euler()
    cam.location = Vector((centre[0], 0, 0)) + up * centre[1] - forward * 60
    scene.camera = cam
    return cam


def factorio_lights(scene):
    """Factorio's sprites are lit from the upper left (north-west, high), with soft fill."""
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.2
    sun.data.angle = math.radians(8)
    to_light = Vector((-0.55, 0.45, 0.75)).normalized()
    sun.rotation_euler = (-to_light).to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(sun)
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.58, 0.62, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
    scene.world = world


def set_render_engine(scene):
    for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT", "CYCLES"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    if scene.render.engine == "CYCLES":
        scene.cycles.samples = 32
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"


def image_array(path):
    """RGBA float array, top row first, as stored in the file (sRGB)."""
    img = bpy.data.images.load(path)
    img.colorspace_settings.name = "Non-Color"
    w, h = img.size
    buf = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(buf)
    bpy.data.images.remove(img)
    return buf.reshape(h, w, 4)[::-1].copy()


def save_array(arr, path):
    h, w = arr.shape[:2]
    img = bpy.data.images.new("out", w, h, alpha=True)
    img.colorspace_settings.name = "Non-Color"
    img.pixels.foreach_set(np.ascontiguousarray(arr[::-1]).ravel().astype(np.float32))
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def over(rgba, bg=BACKGROUND):
    a = rgba[..., 3:4]
    return np.concatenate([rgba[..., :3] * a + np.array(bg) * (1 - a), np.ones_like(a)], axis=2)


def outline(mask):
    m = mask
    edge = np.zeros_like(m)
    edge[1:-1, 1:-1] = m[1:-1, 1:-1] & ~(m[:-2, 1:-1] & m[2:, 1:-1] & m[1:-1, :-2] & m[1:-1, 2:])
    return edge


def draw_line(img, p0, p1, colour):
    n = int(max(abs(p1[0] - p0[0]), abs(p1[1] - p0[1]))) + 1
    for t in np.linspace(0.0, 1.0, n):
        c, r = int(round(p0[0] + (p1[0] - p0[0]) * t)), int(round(p0[1] + (p1[1] - p0[1]) * t))
        if 0 <= r < img.shape[0] and 0 <= c < img.shape[1]:
            img[r, c] = colour


def draw_footprint(img, size, project, colour=(1.0, 0.85, 0.1, 1.0)):
    """The selection box on the ground, and its centre."""
    w, d = size
    corners = [project(x, y, 0.0) for x, y in ((-w / 2, -d / 2), (w / 2, -d / 2), (w / 2, d / 2), (-w / 2, d / 2))]
    for i in range(4):
        draw_line(img, corners[i], corners[(i + 1) % 4], colour)
    for a, b in (((-0.1, 0), (0.1, 0)), ((0, -0.1), (0, 0.1))):
        draw_line(img, project(*a, 0.0), project(*b, 0.0), colour)


def mean_colour(rgba, mask=None):
    a = rgba[..., 3] > 0.5 if mask is None else mask
    if not a.any():
        return "-"
    c = rgba[a][:, :3].mean(axis=0)
    return "#%02x%02x%02x" % tuple(int(round(v * 255)) for v in c)


PART_RANGE, PART_SHARE = 4.0, 0.25  # part_colors.py RANGE and SHARE


def see_through_alpha(obj):
    """A see-through material's alpha as the client draws it (the material's own). Blender's
    importer multiplies it by COLOR_0's alpha, which holds the baked weathering (bake.py), not
    opacity, and left fish and glass nearly invisible."""
    for slot in obj.material_slots:
        mat = slot.material
        if mat is None or mat.node_tree is None:
            continue
        bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf is None or not bsdf.inputs["Alpha"].is_linked:
            continue
        src = bsdf.inputs["Alpha"].links[0].from_node
        factor = next((i.default_value for i in src.inputs if not i.is_linked), 1.0) if src.type == "MATH" else 1.0
        mat.node_tree.links.remove(bsdf.inputs["Alpha"].links[0])
        bsdf.inputs["Alpha"].default_value = factor


def use_part_colours(obj):
    """Draws the part colours part_colors.py stored in TEXCOORD_4/5 over the palette, as the
    client's factorio_material shader does (mostly diffuse), so the render's colour can be
    compared with the sprite's. Blender's importer flips v, hence the 1 - y."""
    uvs = obj.data.uv_layers
    if len(uvs) < 6:
        return
    for slot in obj.material_slots:
        if slot.material is None:
            continue
        mat = slot.material.copy()
        slot.material = mat
        nt = mat.node_tree
        bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf is None:
            continue

        def uv_parts(layer):
            node = nt.nodes.new("ShaderNodeUVMap")
            node.uv_map = uvs[layer].name
            sep = nt.nodes.new("ShaderNodeSeparateXYZ")
            nt.links.new(node.outputs["UV"], sep.inputs[0])
            flip = nt.nodes.new("ShaderNodeMath")
            flip.operation = "SUBTRACT"
            flip.inputs[0].default_value = 1.0
            nt.links.new(sep.outputs["Y"], flip.inputs[1])
            return sep.outputs["X"], flip.outputs[0]

        r, g = uv_parts(4)
        b, a = uv_parts(5)
        rgb = nt.nodes.new("ShaderNodeCombineXYZ")
        for out, inp in zip((r, g, b), rgb.inputs):
            nt.links.new(out, inp)
        scaled = nt.nodes.new("ShaderNodeVectorMath")
        scaled.operation = "SCALE"
        nt.links.new(rgb.outputs[0], scaled.inputs[0])
        scaled.inputs["Scale"].default_value = PART_RANGE
        share = nt.nodes.new("ShaderNodeMath")
        share.operation = "MULTIPLY"
        share.use_clamp = True
        nt.links.new(a, share.inputs[0])
        share.inputs[1].default_value = 1.0 / PART_SHARE
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        nt.links.new(share.outputs[0], mix.inputs["Factor"])
        base = bsdf.inputs["Base Color"]
        if base.links:
            nt.links.new(base.links[0].from_socket, mix.inputs["A"])
        else:
            mix.inputs["A"].default_value = base.default_value
        nt.links.new(scaled.outputs[0], mix.inputs["B"])
        result = mix.outputs["Result"]
        # The nature models shade themselves through COLOR_0's rgb, which the client multiplies
        # in (factorio_material's `tint`); every other model's is white.
        if obj.data.color_attributes:
            attr = nt.nodes.new("ShaderNodeVertexColor")
            attr.layer_name = obj.data.color_attributes[0].name
            tinted = nt.nodes.new("ShaderNodeMix")
            tinted.data_type = "RGBA"
            tinted.blend_type = "MULTIPLY"
            tinted.inputs["Factor"].default_value = 1.0
            nt.links.new(result, tinted.inputs["A"])
            nt.links.new(attr.outputs["Color"], tinted.inputs["B"])
            result = tinted.outputs["Result"]
        nt.links.new(result, base)
        bsdf.inputs["Roughness"].default_value = 0.85
        bsdf.inputs["Metallic"].default_value *= 0.1


def outside(mask, clear):
    """Pixels not in `mask` that connect, through other such pixels, to a `clear` pixel on the
    frame's edge (a frame may cut through the entity: those edge pixels don't count)."""
    free = ~mask
    out = np.zeros_like(mask)
    for edge in ((0, slice(None)), (-1, slice(None)), (slice(None), 0), (slice(None), -1)):
        out[edge] = free[edge] & clear[edge]
    while True:
        grown = out.copy()
        grown[1:] |= out[:-1]
        grown[:-1] |= out[1:]
        grown[:, 1:] |= out[:, :-1]
        grown[:, :-1] |= out[:, 1:]
        grown &= free
        if (grown == out).all():
            return out
        out = grown


def sprite_mask(sprite, shadowless=False):
    """The sprite's silhouette: alpha over half its highest (fish are drawn see-through). With
    `shadowless`, leaves out shadows baked into the picture (dead trees, rocks, wrecks): near-black
    pixels that aren't fully opaque, which the model can't cast in an unlit render."""
    a = sprite[..., 3]
    mask = a > 0.5 * min(1.0, float(a.max()) or 1.0)
    if shadowless and a.max() > 0.6:  # a see-through picture is the thing itself, not its shadow
        mask &= ~((sprite[..., :3].max(axis=2) < 0.07) & (a < 0.95))
    return mask


def load_model(path, rot, head, stretch=1.0, model_scale=1.0, keep_upright=False, part_colours=True, offset=(0.0, 0.0)):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = set(bpy.data.objects) - before
    for obj in new:
        if obj.type == "MESH":
            see_through_alpha(obj)
    if part_colours:
        for obj in new:
            if obj.type == "MESH":
                use_part_colours(obj)
    turn = Matrix.Rotation(math.radians(-rot), 4, "Z")
    for obj in new:
        if obj.name.startswith("anim_turret_head") and head:
            obj.matrix_world = Matrix.Rotation(math.radians(-head), 4, "Z") @ obj.matrix_world
    bpy.context.view_layer.update()
    squash = Matrix.Diagonal((1.0, stretch, 1.0, 1.0))
    sizing = Matrix.Translation((offset[0], -offset[1], 0.0)) @ Matrix.Diagonal((model_scale, model_scale, model_scale, 1.0))
    for obj in new:
        if obj.parent is None:
            upright = keep_upright and obj.name.startswith("anim_upright")
            obj.matrix_world = squash @ (Matrix.Identity(4) if upright else turn) @ sizing @ obj.matrix_world


def sprite_layer(spec, px_per_tile, scale=None):
    """`PATH|WxH|index|line|sx,sy[|scale]` -> RGBA frame and centre offset; index may be `@x,y`.
    A layer drawn at another scale than the first (`scale`) is resampled to it."""
    path, frame, index, line, shift, *own = spec.split("|")
    fw, fh = (int(v) for v in frame.split("x"))
    sheet = image_array(path)
    if index.startswith("@"):
        x, y = (int(v) for v in index[1:].split(","))
    else:
        index, line = int(index), int(line)
        if line <= 0:
            line = max(1, sheet.shape[1] // fw)
        col, row = index % line, index // line
        x, y = col * fw, row * fh
    sx, sy = (float(v) * px_per_tile / 32.0 for v in shift.split(","))
    f = sheet[y:y + fh, x:x + fw]
    if own and scale and abs(float(own[0]) - scale) > 1e-6:
        k = float(own[0]) / scale
        rows = np.minimum((np.arange(int(round(fh * k))) / k).astype(int), fh - 1)
        cols = np.minimum((np.arange(int(round(fw * k))) / k).astype(int), fw - 1)
        f = f[rows][:, cols]
    return f, (sx, sy)


def padded(layers, lo_x, lo_y, hi_x, hi_y, share=0.15):
    """The stacked frames' bounds grown by a margin on each side the picture doesn't touch."""
    pad = share * max(hi_x - lo_x, hi_y - lo_y)
    touch = {"l": False, "t": False, "r": False, "b": False}
    for f, (ox, oy) in layers:
        a = f[..., 3] > 0.5
        x0, y0 = ox - f.shape[1] / 2, oy - f.shape[0] / 2
        touch["l"] |= abs(x0 - lo_x) < 1 and a[:, 0].any()
        touch["t"] |= abs(y0 - lo_y) < 1 and a[0, :].any()
        touch["r"] |= abs(x0 + f.shape[1] - hi_x) < 1 and a[:, -1].any()
        touch["b"] |= abs(y0 + f.shape[0] - hi_y) < 1 and a[-1, :].any()
    return (lo_x - (0 if touch["l"] else pad), lo_y - (0 if touch["t"] else pad),
            hi_x + (0 if touch["r"] else pad), hi_y + (0 if touch["b"] else pad))


def compose(layers):
    """Stacks sprite layers (first at the bottom) on one canvas. Returns the canvas and the
    canvas centre's offset from the anchor in pixels (x right, y down)."""
    lo_x = min(o[0] - f.shape[1] / 2 for f, o in layers)
    lo_y = min(o[1] - f.shape[0] / 2 for f, o in layers)
    hi_x = max(o[0] + f.shape[1] / 2 for f, o in layers)
    hi_y = max(o[1] + f.shape[0] / 2 for f, o in layers)
    # A margin round the frame, so whatever of the model sticks out of it counts against it,
    # except past an edge the picture itself runs into (the market's roof is cut off at the top).
    lo_x, lo_y, hi_x, hi_y = padded(layers, lo_x, lo_y, hi_x, hi_y)
    w, h = int(math.ceil(hi_x - lo_x)), int(math.ceil(hi_y - lo_y))
    canvas = np.zeros((h, w, 4), dtype=np.float32)
    for f, (ox, oy) in layers:
        x0, y0 = int(round(ox - f.shape[1] / 2 - lo_x)), int(round(oy - f.shape[0] / 2 - lo_y))
        region = canvas[y0:y0 + f.shape[0], x0:x0 + f.shape[1]]
        a = f[..., 3:4]
        region[..., :3] = f[..., :3] * a + region[..., :3] * (1 - a)
        region[..., 3:4] = a + region[..., 3:4] * (1 - a)
    return canvas, ((lo_x + hi_x) / 2, (lo_y + hi_y) / 2)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = {"index": "0", "line": "0", "shift": "0,0", "scale": "0.5", "rot": "0", "head": "0",
            "pitch": str(FACTORIO_PITCH), "zoom": "3", "anchor": str(FACTORIO_ANCHOR_Z), "stretch": "1",
            "model-scale": "1"}
    pos, extra = [], []
    for arg in argv:
        if arg.startswith("--layer="):
            extra.append(arg.split("=", 1)[1])
        elif arg.startswith("--") and "=" in arg:
            k, v = arg[2:].split("=", 1)
            opts[k] = v
        else:
            pos.append(arg)
    if len(pos) != 2 or "sprite" not in opts or "frame" not in opts:
        print(__doc__)
        return 1
    out, name = os.path.abspath(pos[0]), pos[1]
    zoom = int(opts["zoom"])
    px_per_tile = 32.0 / float(opts["scale"])
    pitch = float(opts["pitch"])
    specs_ = ["|".join((opts["sprite"], opts["frame"], opts["index"], opts["line"], opts["shift"]))] + extra
    sprite, (ox, oy) = compose([sprite_layer(s, px_per_tile, float(opts["scale"])) for s in specs_])
    fh, fw = sprite.shape[:2]
    sprite = np.repeat(np.repeat(sprite, zoom, axis=0), zoom, axis=1)

    kit.clear_scene()
    scene = bpy.context.scene
    load_model(opts.get("glb") or os.path.join(MODELS_DIR, name + ".glb"), float(opts["rot"]),
               float(opts["head"]), float(opts["stretch"]), float(opts["model-scale"]),
               opts.get("keep-upright") == "1", "palette" not in opts,
               tuple(float(v) for v in opts.get("offset", "0,0").split(",")))
    # `--hide=PREFIX[,PREFIX]` leaves out the nodes so named (and what hangs under them): parts
    # the picture doesn't draw, as the thruster's exhaust plume, dark while it is idle.
    for prefix in filter(None, opts.get("hide", "").split(",")):
        for obj in [o for o in bpy.data.objects if o.name.startswith(prefix)]:
            for child in [obj] + list(obj.children_recursive):
                if child.name in bpy.data.objects:
                    bpy.data.objects.remove(child, do_unlink=True)
    # The frame's centre is the entity's position plus the shift (screen y points down); the
    # position itself is the projection of a point FACTORIO_ANCHOR_Z above the ground.
    sin_p, cos_p = math.sin(math.radians(pitch)), math.cos(math.radians(pitch))
    cx, cy = ox / px_per_tile, -oy / px_per_tile + float(opts["anchor"]) * cos_p
    factorio_camera(scene, pitch, (cx, cy), fw / px_per_tile)
    factorio_lights(scene)
    set_render_engine(scene)
    scene.render.film_transparent = True
    scene.render.resolution_x, scene.render.resolution_y = fw * zoom, fh * zoom
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    tmp = os.path.join(tempfile.gettempdir(), "f3d-compare-%d.png" % os.getpid())
    scene.render.filepath = tmp
    bpy.ops.render.render(write_still=True)
    render = image_array(tmp)
    os.remove(tmp)

    k = px_per_tile * zoom

    def project(x, y, z):
        return (fw * zoom / 2 + (x - cx) * k, fh * zoom / 2 - (y * float(opts["stretch"]) * sin_p + z * cos_p - cy) * k)

    size = specs.SPECS.get(name, {"size": (1, 1)})["size"]
    if round(float(opts["rot"]) / 90) % 2:
        size = size[::-1]
    # Some sheets (the pipe kit, heat pipes, the inserters' platforms, many Space Age buildings)
    # bake their shadow in: black (to 6/255 on the platforms) and see-through, which isn't the
    # entity's silhouette. Black paint is nearly opaque (a chimney mouth: 0.976).
    shadow = (sprite[..., :3].max(axis=2) <= 6 / 255) & (sprite[..., 3] < 0.95)
    shadow |= (sprite[..., :3].max(axis=2) < 0.04) & (sprite[..., 3] < 0.6)
    # A baked shadow lies outside the entity; dark pixels walled in by it (crevices between
    # hoses) are the entity itself.
    shadow &= outside(sprite_mask(sprite) & ~shadow, sprite[..., 3] < 0.5)
    # A picture that is see-through all over (fish: black at alpha 0.36) is the thing itself.
    if sprite[..., 3].max() <= 0.6:
        shadow[:] = False
    # A see-through model (fish) is measured as the see-through picture: over half its highest alpha.
    s_mask = sprite_mask(sprite, "shadowless" in opts) & ~shadow
    r_mask = render[..., 3] > 0.5 * min(1.0, float(render[..., 3].max()) or 1.0)
    grey = over(sprite)[..., :3].mean(axis=2, keepdims=True) * 0.8
    overlay = np.concatenate([np.repeat(grey, 3, axis=2), np.ones_like(grey)], axis=2)
    overlay[outline(s_mask)] = (0.1, 0.9, 1.0, 1.0)
    overlay[outline(r_mask)] = (1.0, 0.15, 0.1, 1.0)
    gap = np.ones((fh * zoom, 4 * zoom, 4), dtype=np.float32)
    left = over(sprite)
    draw_footprint(left, size, project)
    draw_footprint(overlay, size, project)
    save_array(np.concatenate([left, gap, over(render), gap, overlay], axis=1), out)
    if opts.get("diff"):
        # Where the silhouettes disagree: cyan only in the sprite, red only in the model.
        diff = np.concatenate([np.repeat(grey * 0.6, 3, axis=2), np.ones_like(grey)], axis=2)
        diff[s_mask & ~r_mask] = (0.1, 0.9, 1.0, 1.0)
        diff[r_mask & ~s_mask] = (1.0, 0.15, 0.1, 1.0)
        draw_footprint(diff, size, project)
        save_array(diff, os.path.abspath(opts["diff"]))
    iou = (s_mask & r_mask).sum() / max(1, (s_mask | r_mask).sum())
    print("compare: wrote %s  sprite %s  model %s  silhouette overlap %.2f" % (
        out, mean_colour(sprite, s_mask), mean_colour(render), iou))
    return 0


if __name__ == "__main__":
    code = main()
    sys.stdout.flush()
    sys.exit(code)
