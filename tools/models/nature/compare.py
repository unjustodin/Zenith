"""Renders nature models from Factorio's camera next to Factorio's own sprites, to match them.

    blender --background --factory-startup --python tools/models/nature/compare.py -- OUT.png
        NAME[@REF] [NAME[@REF] ...] [--pitch 48] [--zoom 1] [--factorio DIR]

Each NAME gets a row of three panels at 64 px per tile (times --zoom): Factorio's sprite, the
model rendered with the same orthographic camera and anchor, and both outlines over each other
(sprite cyan, model red, the entity's tile yellow). The sprites are read from the player's
Factorio install (`--factorio`, default: Steam's) and drawn only into OUT.png, which belongs in a
scratch folder: never commit it or anything made from it.

REF picks the sprite: a variation letter for tree-01..09 (default a; leaves are tinted with
the mean of the prototype's `colors`, as the game picks one of them at random per tree), a
picture number for dead trees and rocks (default 0), and for ores the richness stage row of the
sheet (0 = richest, default 2): ores are compared as a 4x4 tile patch, each tile a random
sheet variation in Factorio and a randomly turned and sized model like the client draws.

The mean, dark and light colours of both are printed, to tune materials. Factorio's sprites are
rendered with an orthographic camera looking north and down at about 48 degrees (horizontal
circles show as ellipses ~0.75 as tall as wide), lit from the upper left.
"""

import math
import os
import random
import re
import sys
import tempfile

import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import build_nature  # noqa: E402

FACTORIO = r"C:\Program Files (x86)\Steam\steamapps\common\Factorio"
PX = 64  # sprite pixels per tile (HR sheets drawn at scale 0.5)
BACKGROUND = (0.30, 0.31, 0.21)
DEAD = ("dead-dry-hairy-tree", "dead-grey-trunk", "dead-tree-desert", "dry-hairy-tree", "dry-tree")
ROCKS = {"big-rock": "big-rock", "huge-rock": "huge-rock", "big-sand-rock": "big-sand-rock"}
ORES = ("iron-ore", "copper-ore", "coal", "stone", "uranium-ore")


# --- images ------------------------------------------------------------------------------------

def load(path):
    """PNG -> HxWx4 float array, top row first, values as stored (sRGB)."""
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    buf = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(buf)
    bpy.data.images.remove(img)
    return buf.reshape(h, w, 4)[::-1].copy()


def save(arr, path):
    h, w = arr.shape[:2]
    img = bpy.data.images.new("out", w, h, alpha=True)
    img.pixels.foreach_set(np.clip(arr, 0, 1).astype(np.float32)[::-1].ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def over(dst, src, x, y):
    """Alpha-composites src onto dst with its top-left corner at (x, y)."""
    h, w = src.shape[:2]
    H, W = dst.shape[:2]
    x0, y0, x1, y1 = max(x, 0), max(y, 0), min(x + w, W), min(y + h, H)
    if x1 <= x0 or y1 <= y0:
        return
    s = src[y0 - y:y1 - y, x0 - x:x1 - x]
    d = dst[y0:y1, x0:x1]
    a = s[..., 3:4]
    d[..., :3] = s[..., :3] * a + d[..., :3] * (1 - a)
    d[..., 3:4] = a + d[..., 3:4] * (1 - a)


def outline(mask):
    inner = mask.copy()
    inner[1:] &= mask[:-1]
    inner[:-1] &= mask[1:]
    inner[:, 1:] &= mask[:, :-1]
    inner[:, :-1] &= mask[:, 1:]
    return mask & ~inner


def hexes(arr, mask):
    px = arr[mask][:, :3]
    if not len(px):
        return "-"
    lum = px @ np.array([0.299, 0.587, 0.114])
    lo, hi = np.percentile(lum, [20, 80])

    def hx(c):
        return "#%02x%02x%02x" % tuple(int(round(min(max(v, 0.0), 1.0) * 255)) for v in c)
    return "mean %s dark %s light %s" % (hx(px.mean(0)), hx(px[lum <= lo].mean(0)), hx(px[lum >= hi].mean(0)))


# --- Factorio's sprites ------------------------------------------------------------------------

class Sprites:
    def __init__(self, root):
        self.base = os.path.join(root, "data", "base")
        self.trees_lua = open(os.path.join(self.base, "prototypes", "entity", "trees.lua"), encoding="utf-8").read()
        self.deco_lua = open(os.path.join(self.base, "prototypes", "decorative", "decoratives.lua"), encoding="utf-8").read()

    def path(self, game_path):
        return os.path.join(self.base, game_path.replace("__base__/", "").replace("/", os.sep))

    def tree_layers(self, number, letter):
        """(file, w, h, shift_x_px, shift_y_px, frames) for trunk and leaves of tree-NN variation."""
        block = self.trees_lua[self.trees_lua.index("{ -- tree-%s" % number):]
        block = block[block.index("{ -- %s" % letter):]
        out = []
        for layer in ("trunk", "leaves"):
            m = re.search(layer + r"\s*=\s*\{\s*width = (\d+),\s*height = (\d+),\s*shift = util\.by_pixel\((-?[\d.]+), (-?[\d.]+)\)", block)
            w, h, sx, sy = int(m.group(1)), int(m.group(2)), float(m.group(3)), float(m.group(4))
            f = "graphics/entity/tree/%s/tree-%s-%s-%s.png" % (number, number, letter, layer)
            out.append((f, w, h, sx * 2, sy * 2))
        return out

    def tree_tint(self, name):
        start = self.trees_lua.index("define_trees{")
        for block in re.split(r"\n  \{\n", self.trees_lua[start:])[1:]:
            t = re.search(r"type\s*=\s*(\d+)", block)
            if t and "tree-%02d" % int(t.group(1)) == name and "identifier" not in block.split("colors")[0]:
                cols = re.findall(r"\{r\s*=\s*(\d+),\s*g\s*=\s*(\d+),\s*b\s*=\s*(\d+)\}", block.split("get_water_reflection")[0])
                return np.mean(np.array(cols, float), 0) / 255.0
        return np.ones(3)

    def pictures(self, src, name):
        """[(file, w, h, shift_x_px, shift_y_px)] of a dead tree or rock's `pictures`."""
        i = src.index('name = "%s"' % name)
        j = src.find("pictures", i)
        block = src[j:src.find("\n  }", j)]
        out = []
        for m in re.finditer(r'filename = "([^"]+)",(.*?)\}', block, re.S):
            body = m.group(2)
            w = int(re.search(r"width = (\d+)", body).group(1))
            h = int(re.search(r"height = (\d+)", body).group(1))
            px = re.search(r"shift = util\.by_pixel\((-?[\d.]+), (-?[\d.]+)\)", body)
            if px:
                sx, sy = float(px.group(1)) * 2, float(px.group(2)) * 2
            else:
                t = re.search(r"shift = \{(-?[\d.]+), (-?[\d.]+)\}", body)
                sx, sy = (float(t.group(1)) * PX, float(t.group(2)) * PX) if t else (0.0, 0.0)
            out.append((m.group(1).replace("__base__/", ""), w, h, sx, sy))
        return out

    def draw(self, canvas, f, w, h, sx, sy, ax, ay, zoom, tint=None, frame=0):
        a = load(self.path(f))[:h, frame * w:(frame + 1) * w].copy()
        if tint is not None:
            a[..., :3] *= tint
        if zoom != 1:
            a = a.repeat(zoom, 0).repeat(zoom, 1)
        over(canvas, a, int(round(ax + (sx - w / 2) * zoom)), int(round(ay + (sy - h / 2) * zoom)))

    def reference(self, name, ref, size, anchor, zoom, rng):
        W, H = size
        c = np.zeros((H, W, 4), np.float32)
        ax, ay = anchor
        if name.startswith("tree-0"):
            number = name[5:7]
            tint = self.tree_tint(name)
            for i, (f, w, h, sx, sy) in enumerate(self.tree_layers(number, ref or "a")):
                self.draw(c, f, w, h, sx, sy, ax, ay, zoom, tint if i == 1 else None)
        elif name in DEAD:
            f, w, h, sx, sy = self.pictures(self.trees_lua, name)[int(ref or 0)]
            self.draw(c, "graphics/" + f.split("graphics/")[1], w, h, sx, sy, ax, ay, zoom)
        elif name in ROCKS:
            f, w, h, sx, sy = self.pictures(self.deco_lua, name)[int(ref or 0)]
            self.draw(c, "graphics/" + f.split("graphics/")[1], w, h, sx, sy, ax, ay, zoom)
        elif name in ORES:
            stage = int(ref or 2)
            sheet = load(self.path("graphics/entity/%s/%s.png" % (name, name)))
            for ty in range(-2, 2):
                for tx in range(-2, 2):
                    v = rng.randrange(8)
                    fr = sheet[stage * 128:(stage + 1) * 128, v * 128:(v + 1) * 128]
                    if zoom != 1:
                        fr = fr.repeat(zoom, 0).repeat(zoom, 1)
                    cx, cy = ax + (tx + 0.5) * PX * zoom, ay + (ty + 0.5) * PX * zoom
                    over(c, fr, int(cx - 64 * zoom), int(cy - 64 * zoom))
        return c


# --- rendering ---------------------------------------------------------------------------------

def wire_vertex_colors(obj):
    """Multiplies each material's base colour by the face-corner colour, as glTF (and Godot) do."""
    for mat in obj.data.materials:
        nt = mat.node_tree
        bsdf = nt.nodes.get("Principled BSDF")
        if bsdf is None or bsdf.inputs["Base Color"].is_linked:
            continue
        attr = nt.nodes.new("ShaderNodeVertexColor")
        attr.layer_name = "Color"
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        mix.inputs["A"].default_value = bsdf.inputs["Base Color"].default_value
        nt.links.new(attr.outputs["Color"], mix.inputs["B"])
        nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])


def setup_scene(pitch, size, anchor, zoom):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "Standard"
    W, H = size
    scene.render.resolution_x, scene.render.resolution_y = W, H
    scene.render.resolution_percentage = 100
    data = bpy.data.cameras.new("factorio")
    data.type = "ORTHO"
    data.sensor_fit = "HORIZONTAL"
    data.ortho_scale = W / (PX * zoom)
    data.clip_start, data.clip_end = 0.1, 200.0
    # Put the world origin at the anchor pixel.
    data.shift_x = (W / 2 - anchor[0]) / W
    data.shift_y = (anchor[1] - H / 2) / W
    cam = bpy.data.objects.new("factorio", data)
    scene.collection.objects.link(cam)
    p = math.radians(pitch)
    forward = Vector((0.0, math.cos(p), -math.sin(p)))
    cam.rotation_euler = forward.to_track_quat("-Z", "Y").to_euler()
    cam.location = -forward * 60.0
    scene.camera = cam
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    # Roughly the client's daylight (main.gd): sun energy 1.1 and ambient 0.6 in Godot's units.
    sun.data.energy = 3.45
    sun.data.angle = math.radians(5)
    to_light = Vector((-0.55, 0.45, 0.75)).normalized()
    sun.rotation_euler = (-to_light).to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(sun)
    world = bpy.data.worlds.new("w")
    if not world.node_tree:
        world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.75, 0.78, 0.82, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
    scene.world = world


def render(path):
    scene = bpy.context.scene
    scene.render.filepath = path
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    bpy.ops.render.render(write_still=True)
    return load(path)


def clear():
    for coll in (bpy.data.objects, bpy.data.meshes, bpy.data.cameras, bpy.data.lights, bpy.data.worlds):
        for item in list(coll):
            coll.remove(item)


def place_ore_patch(obj, rng):
    """4x4 tiles of the ore model, each turned and sized like chunk_view.gd's _model_transform."""
    objs = []
    for ty in range(-2, 2):
        for tx in range(-2, 2):
            o = obj if not objs else obj.copy()
            if objs:
                bpy.context.scene.collection.objects.link(o)
            size = 0.9 + 0.2 * rng.random()
            # Factorio y (south) is Blender -y.
            o.matrix_world = (Matrix.Translation((tx + 0.5, -(ty + 0.5), 0.0))
                              @ Matrix.Rotation(rng.uniform(0, math.tau), 4, "Z")
                              @ Matrix.Diagonal((size, size, size * 0.85, 1.0)))
            objs.append(o)
    return objs


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    out, pitch, zoom, root, names = None, 48.0, 1, FACTORIO, []
    it = iter(argv)
    for a in it:
        if a == "--pitch":
            pitch = float(next(it))
        elif a == "--zoom":
            zoom = int(next(it))
        elif a == "--factorio":
            root = next(it)
        elif out is None:
            out = os.path.abspath(a)
        else:
            names.append(a)
    sprites = Sprites(root)
    reg = build_nature.registry()
    rows = []
    tmp = tempfile.mkdtemp()
    for spec in names:
        name, _, ref = spec.partition("@")
        if name.startswith("tree-0") or name == "dry-hairy-tree" or name == "dead-tree-desert":
            tiles, anchor_t = (7, 8), (3.5, 6.8)
        elif name in ORES:
            tiles, anchor_t = (5, 5), (2.5, 2.5)
        else:
            tiles, anchor_t = (6, 5), (3.0, 3.6)
        size = (tiles[0] * PX * zoom, tiles[1] * PX * zoom)
        anchor = (anchor_t[0] * PX * zoom, anchor_t[1] * PX * zoom)
        ref_img = sprites.reference(name, ref, size, anchor, zoom, random.Random(7))
        clear()
        setup_scene(pitch, size, anchor, zoom)
        obj, tris = build_nature.build(name, reg)
        wire_vertex_colors(obj)
        if name in ORES:
            place_ore_patch(obj, random.Random(7))
        model = render(os.path.join(tmp, "m.png"))
        bg = np.zeros(ref_img.shape, np.float32)
        bg[..., :3], bg[..., 3] = BACKGROUND, 1.0
        a, b = bg.copy(), bg.copy()
        over(a, ref_img, 0, 0)
        over(b, model, 0, 0)
        ms, mm = ref_img[..., 3] > 0.5, model[..., 3] > 0.5
        c = np.full(ref_img.shape, 0.5, np.float32)
        c[..., 3] = 1.0
        c[ms] = (0.62, 0.62, 0.62, 1.0)
        tile = np.zeros(ms.shape, bool)
        t = PX * zoom
        sp = math.sin(math.radians(pitch))
        x0, x1 = int(anchor[0] - t / 2), int(anchor[0] + t / 2)
        y0, y1 = int(anchor[1] - t * sp / 2), int(anchor[1] + t * sp / 2)
        tile[y0:y1, x0:x1] = True
        c[outline(tile)] = (1.0, 0.9, 0.1, 1.0)
        c[outline(ms)] = (0.1, 0.9, 1.0, 1.0)
        c[outline(mm)] = (1.0, 0.15, 0.1, 1.0)
        rows.append(np.concatenate([a, b, c], 1))

        def ext(mask):
            if not mask.any():
                return "empty"
            r, q = np.where(mask.any(1))[0], np.where(mask.any(0))[0]
            return "x %+.2f..%+.2f up %+.2f..%+.2f" % ((q.min() - anchor[0]) / t, (q.max() - anchor[0]) / t,
                                                       (anchor[1] - r.max()) / t, (anchor[1] - r.min()) / t)
        # Silhouette overlap, leaving out the shadow some sprites have drawn in (near black).
        body = ms & (ref_img[..., :3].max(axis=2) > 0.06)
        iou = (body & mm).sum() / max(1, (body | mm).sum())
        print("COMPARE %-22s %5d tris  silhouette overlap %.2f" % (spec, tris, iou))
        print("  sprite  %s  %s" % (ext(ms), hexes(ref_img, ref_img[..., 3] > 0.9)))
        print("  model   %s  %s" % (ext(mm), hexes(model, model[..., 3] > 0.9)))
    width = max(r.shape[1] for r in rows)
    sheet = np.concatenate([np.pad(r, ((0, 4), (0, width - r.shape[1]), (0, 0))) for r in rows], 0)
    save(sheet, out)
    print("saved", out)


if __name__ == "__main__":
    main()
