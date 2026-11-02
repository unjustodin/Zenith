#!/usr/bin/env python3
"""Colours for every part of a model, sampled once from Factorio's own sprite, so the client can
draw the model in Factorio's colours without projecting the sprite onto it at runtime.

    python tools/models/part_colors.py [names...] [--factorio DIR] [--debug DIR] [--check]

Run it after anything that rewrites a .glb (build.py, wube.py, nature/build_nature.py), like
projector_depth.py: the colours are stored in the .glb itself. Without names it does every model
with an entry in client/data/sprite_projection.json (plus DONORS below).

How a colour is chosen:

1. The model is cut into patches: triangles of one material joined across edges that bend less
   than CREASE degrees, so each face of a box, each panel of a converted Wube model, each pipe and
   each smooth dome is a patch of its own.
2. For each picture its entry has (each direction; eight frames round the turn for vehicles; every
   variation of ores), the model is rasterised from Factorio's camera exactly as the client
   projects the sprite (north-south `stretch`, `projection: top` for rails), into a buffer of
   which triangle is in front at each sprite pixel. The model is nudged up to ALIGN pixels to where
   its silhouette best fits the sprite's.
3. Each patch's pixels, eroded so outlines and neighbours don't bleed in (all of them for patches
   too thin to keep any), transparent and grazing ones dropped, are divided by the light Factorio
   painted into them (SHADE: a key light from the west and ambient, per pixel from the triangle's
   normal), so Godot doesn't light it twice.
4. Colours are the densest colour of a set of pixels in CIELAB (`mode`: lit pixels count a little
   more than crevices and painted shadows), averaged in linear light over the pixels of that hue.
   A model built by hand from the sprite (kit, nature, Space Age) rarely has its parts exactly
   where the sprite has them, but its materials say what each part is meant to be: each material
   first gets the sprite's colour nearest its palette colour (preferring pixels under its own
   parts), or the colour most pixels under its parts agree on; a patch keeps its own densest
   colour only near that (or when it is big and its pixels agree), else it counts as unseen.
   Wube's conversions are the sprites' own geometry: where their pictures fit (FREE_FIT), every
   patch keeps its own colour.
5. One small solve over the patch graph: measured patches keep their colour (weighted by how many
   pixels they had and how much those agreed), patches nobody sees take their neighbours' (those
   of the same material and the same tilt count most: a box's hidden east face takes its south
   face's colour, not its lid's), and everything leans a little to its material's colour, so one
   material reads as one paint and isolated hidden parts still get it.
6. SATURATION, EXPOSURE and a soft KNEE on the brightest, checked against client screenshots.

Stored per vertex, in linear RGB, as two extra UV sets the client reads as CUSTOM1:
    TEXCOORD_4  (r, g) / RANGE
    TEXCOORD_5  (b / RANGE, w * SHARE)   w: how much of the colour comes from the sprite (0: palette)
(normalised 16-bit, 8 bytes a vertex). The headroom lets a colour be divided by a dark baked
tint (the nature models' COLOR_0) without clipping; the shader tells this layout from the first
one (rgb and w as is, w mostly 1) by w <= SHARE.
TEXCOORD_2 and _3 (the projector visibility, bake.py) must be there for Godot to import them; a
primitive without them gets ones (= no visibility data).

DONORS: models with no sprite entry of their own (pose variants) take colours per material from a
model that has one. The inserter arms aren't among them: the client paints them in each
inserter's colour picked from its sprites (inserter_arms.gd ARM_TINTS), over the palette.

--debug DIR writes, per model, the sprite next to the patch colours re-lit with SHADE from
Factorio's camera (what the sampler saw), as PNGs for looking at (keep them out of the repo: they
show Factorio's sprites). --check reports and writes nothing. --fit-light refits SHADE.

Plain Python: numpy, scipy, pillow. The sprite sheets are read from the player's Factorio
install; only colours (numbers) end up in the repo.
"""

import argparse
import json
import math
import os
import struct
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
MODELS = os.path.join(REPO, "client", "assets", "models")
ENTRIES = os.path.join(REPO, "client", "data", "sprite_projection.json")
FACTORIO = os.environ.get("FACTORIO", r"C:\Program Files (x86)\Steam\steamapps\common\Factorio")

SIN, COS = math.sin(math.radians(48.0)), math.cos(math.radians(48.0))
VIEW = np.array([0.0, SIN, COS])  # towards Factorio's camera, glTF axes (x east, y up, z south)
CREASE = 35.0  # degrees: edges bending more than this split patches
EMPTY = -1e9

# The light Factorio's renders have painted in: ambient plus a key light from the upper left of
# the screen (west, 50 degrees up, a little towards the camera), as a factor on the albedo. Fitted
# to the median brightness of ~6000 patches of every model binned by the way they face (top 1,
# south 0.75, west 0.95, east 0.58): over many patches the paint averages out, the light stays.
LIGHT = np.array([-0.604, 0.766, 0.22])
LIGHT = LIGHT / np.linalg.norm(LIGHT)
AMBIENT = 0.625
# Overall level: the client's sun and sky light the model again, brighter than Factorio's renders;
# this keeps the model about as bright as the sprite from Factorio's view (checked against client
# screenshots against the projected sprite's look, which Factorio's view matched). Godot's sky light
# also greys colours a little: SATURATION scales their chroma back up.
# KNEE rolls off the brightest colours (light lids, cream struts): the sun lights their tops harder
# than Factorio's renders did.
EXPOSURE = 0.95
KNEE = 1.5
SATURATION = 1.12

SMOOTH = 0.35      # how strongly neighbouring patches pull together
PRIOR = 0.02       # how strongly a patch leans to its material's average
MATERIAL_PULL = 0.12  # ... and a measured one, relative to its own sample: one material reads as one
FULL_PIXELS = 40   # pixels (at 64 per tile) for a patch's sample to count fully
ALIGN = 5          # pixels: how far the model may be nudged to fit the sprite's silhouette
CROSS_MATERIAL = 0.15
TILT = 3.0

# Models without a sprite entry of their own: colours per material from another model.
DONORS = {
    "big-biter-attack": "big-biter", "big-biter-corpse": "big-biter",
    "big-spitter-attack": "big-spitter", "big-spitter-corpse": "big-spitter",
    **{"big-%s-corpse-%d" % (f, v): "big-" + f for f in ("biter", "spitter") for v in (1, 2, 3)},
    "big-worm-turret-corpse": "big-worm-turret",
    "character-corpse": "character",
}


def shade(n):
    """Factorio's painted-in light for unit normals (..., 3)."""
    return AMBIENT + (1.0 - AMBIENT) * np.clip(n @ LIGHT, 0.0, None)


def srgb_to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(c):
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


# ---------------------------------------------------------------------------------------------
# glTF binary in and out

TYPES = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
COMPONENTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


class Glb:
    def __init__(self, path):
        with open(path, "rb") as f:
            data = f.read()
        magic, version, _ = struct.unpack_from("<4sII", data, 0)
        if magic != b"glTF" or version != 2:
            raise ValueError("%s: not a glTF 2 binary" % path)
        offset, self.doc, self.bin = 12, None, bytearray()
        while offset < len(data):
            size, kind = struct.unpack_from("<I4s", data, offset)
            if kind == b"JSON":
                self.doc = json.loads(data[offset + 8:offset + 8 + size])
            elif kind == b"BIN\x00":
                self.bin = bytearray(data[offset + 8:offset + 8 + size])
            offset += 8 + size
        self.path = path

    def accessor(self, index):
        acc = self.doc["accessors"][index]
        n = COMPONENTS[acc["type"]]
        dtype = np.dtype(TYPES[acc["componentType"]])
        count = acc["count"]
        if "bufferView" not in acc:
            return np.zeros((count, n), dtype=np.float64)
        view = self.doc["bufferViews"][acc["bufferView"]]
        base = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        stride = view.get("byteStride", dtype.itemsize * n)
        raw = np.frombuffer(bytes(self.bin), dtype=np.uint8)
        rows = np.lib.stride_tricks.as_strided(raw[base:], shape=(count, dtype.itemsize * n), strides=(stride, 1))
        out = np.ascontiguousarray(rows).view(dtype).reshape(count, n).astype(np.float64)
        if acc.get("normalized"):
            out /= float(np.iinfo(dtype).max)
        return out

    def set_vec2(self, prim, name, values, unorm=False):
        """Writes VEC2 attribute `name` of a primitive, as floats or (unorm) as normalised 16-bit
        integers (values in 0..1, half the size): over its old data when the layout matches
        (re-running doesn't grow the file), else appended."""
        if unorm:
            data = np.round(np.clip(values, 0.0, 1.0) * 65535.0).astype("<u2")
            ctype, size = 5123, 4
        else:
            data = np.asarray(values, dtype="<f4")
            ctype, size = 5126, 8
        data = np.ascontiguousarray(data)
        attrs = prim["attributes"]
        if name in attrs:
            acc = self.doc["accessors"][attrs[name]]
            if acc["componentType"] == ctype and acc["type"] == "VEC2" and acc["count"] == len(data)                     and "bufferView" in acc and bool(acc.get("normalized")) == unorm:
                view = self.doc["bufferViews"][acc["bufferView"]]
                if view.get("byteStride", size) == size:
                    base = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
                    self.bin[base:base + data.nbytes] = data.tobytes()
                    return
        while len(self.bin) % 4:
            self.bin.append(0)
        views = self.doc.setdefault("bufferViews", [])
        views.append({"buffer": 0, "byteOffset": len(self.bin), "byteLength": data.nbytes, "target": 34962})
        self.bin += data.tobytes()
        accessors = self.doc.setdefault("accessors", [])
        acc = {"bufferView": len(views) - 1, "componentType": ctype, "count": len(data), "type": "VEC2"}
        if unorm:
            acc["normalized"] = True
        accessors.append(acc)
        attrs[name] = len(accessors) - 1

    def overwrite(self, index, values):
        """Writes values back into accessor `index` in its own layout (same count and type)."""
        acc = self.doc["accessors"][index]
        view = self.doc["bufferViews"][acc["bufferView"]]
        dtype = np.dtype(TYPES[acc["componentType"]]).newbyteorder("<")
        n = COMPONENTS[acc["type"]]
        v = np.asarray(values, dtype=np.float64).reshape(acc["count"], n)
        if acc.get("normalized"):
            v = np.round(np.clip(v, 0.0, 1.0) * np.iinfo(dtype).max)
        data = v.astype(dtype)
        base = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        stride = view.get("byteStride", dtype.itemsize * n)
        row = dtype.itemsize * n
        raw = data.tobytes()
        for i in range(acc["count"]):
            self.bin[base + i * stride:base + i * stride + row] = raw[i * row:(i + 1) * row]

    def save(self, path=None):
        while len(self.bin) % 4:
            self.bin.append(0)
        self.doc["buffers"][0]["byteLength"] = len(self.bin)
        text = json.dumps(self.doc, separators=(",", ":")).encode("utf-8")
        text += b" " * ((4 - len(text) % 4) % 4)
        total = 12 + 8 + len(text) + 8 + len(self.bin)
        with open(path or self.path, "wb") as f:
            f.write(struct.pack("<4sII", b"glTF", 2, total))
            f.write(struct.pack("<I4s", len(text), b"JSON"))
            f.write(text)
            f.write(struct.pack("<I4s", len(self.bin), b"BIN\x00"))
            f.write(bytes(self.bin))


def node_matrix(node):
    if "matrix" in node:
        return np.array(node["matrix"], dtype=np.float64).reshape(4, 4).T
    tx, ty, tz = node.get("translation", [0, 0, 0])
    qx, qy, qz, qw = node.get("rotation", [0, 0, 0, 1])
    sx, sy, sz = node.get("scale", [1, 1, 1])
    r = np.array([
        [1 - 2 * (qy * qy + qz * qz), 2 * (qx * qy - qz * qw), 2 * (qx * qz + qy * qw)],
        [2 * (qx * qy + qz * qw), 1 - 2 * (qx * qx + qz * qz), 2 * (qy * qz - qx * qw)],
        [2 * (qx * qz - qy * qw), 2 * (qy * qz + qx * qw), 1 - 2 * (qx * qx + qy * qy)]])
    m = np.eye(4)
    m[:3, :3] = r * np.array([sx, sy, sz])
    m[:3, 3] = (tx, ty, tz)
    return m


class Model:
    """A model's triangles in model space, with what each came from so colours can go back."""

    def __init__(self, glb, crease=CREASE, merge=()):
        """merge: groups of material names sampled and coloured as one material (overrides)."""
        self.glb = glb
        self.crease = crease
        doc = glb.doc
        self.prims = []  # (mesh index, prim index, prim dict)
        prim_index = {}
        tris, nrms, mats, upright, prim_of, corner_vert, tint, uvs = [], [], [], [], [], [], [], []
        self.material_names = [m.get("name", "") for m in doc.get("materials", [])]
        self.palette = []
        for m in doc.get("materials", []):
            c = m.get("pbrMetallicRoughness", {}).get("baseColorFactor", [0.7, 0.7, 0.7, 1.0])
            self.palette.append(np.array(c[:3], dtype=np.float64))
        if not self.palette:
            self.material_names, self.palette = [""], [np.array([0.7, 0.7, 0.7])]

        def visit(index, parent, up):
            node = doc["nodes"][index]
            m = parent @ node_matrix(node)
            up = up or str(node.get("name", "")).startswith("anim_upright")
            if "mesh" in node:
                for pi, prim in enumerate(doc["meshes"][node["mesh"]]["primitives"]):
                    if prim.get("mode", 4) != 4:
                        continue
                    key = (node["mesh"], pi)
                    if key not in prim_index:
                        prim_index[key] = len(self.prims)
                        self.prims.append((node["mesh"], pi, prim))
                    a = prim["attributes"]
                    pos = glb.accessor(a["POSITION"])[:, :3]
                    pos = pos @ m[:3, :3].T + m[:3, 3]
                    idx = glb.accessor(prim["indices"])[:, 0].astype(np.int64).reshape(-1, 3) if "indices" in prim \
                        else np.arange(len(pos)).reshape(-1, 3)
                    vn = None
                    if "NORMAL" in a:
                        normal_m = np.linalg.inv(m[:3, :3]).T
                        vn = glb.accessor(a["NORMAL"])[:, :3] @ normal_m.T
                    col = glb.accessor(a["COLOR_0"])[:, :3] if "COLOR_0" in a else np.ones((len(pos), 3))
                    uv = glb.accessor(a["TEXCOORD_0"])[:, :2] if "TEXCOORD_0" in a else np.zeros((len(pos), 2))
                    t = pos[idx]
                    fn = np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0])
                    if vn is not None:
                        flip = np.einsum("ij,ij->i", fn, vn[idx].sum(axis=1)) < 0.0
                        fn[flip] *= -1.0
                    tris.append(t)
                    nrms.append(fn)
                    mats.append(np.full(len(idx), prim.get("material", 0)))
                    upright.append(np.full(len(idx), up))
                    prim_of.append(np.full(len(idx), prim_index[key]))
                    corner_vert.append(idx)
                    tint.append(col[idx].mean(axis=1))
                    uvs.append(uv[idx])
            for child in node.get("children", []):
                visit(child, m, up)

        for root in doc["scenes"][doc.get("scene", 0)]["nodes"]:
            visit(root, np.eye(4), False)
        self.tris = np.concatenate(tris)
        fn = np.concatenate(nrms)
        self.area = 0.5 * np.linalg.norm(fn, axis=1)
        self.normal = fn / np.maximum(2.0 * self.area, 1e-12)[:, None]
        self.material = np.concatenate(mats)
        self.upright = np.concatenate(upright)
        self.prim_of = np.concatenate(prim_of)
        self.corner_vert = np.concatenate(corner_vert)
        self.tint = np.concatenate(tint)
        self.uv = np.concatenate(uvs)
        # Merged materials: every material of a group counts as the group's first.
        index = {n: i for i, n in enumerate(self.material_names)}
        for group in merge:
            present = [index[n] for n in group if n in index]
            for i in present[1:]:
                self.material[self.material == i] = present[0]
        self.patches()

    def patches(self):
        """Patch per triangle (one material, joined across gentle edges), and the patch graph."""
        from scipy.sparse import coo_matrix
        from scipy.sparse.csgraph import connected_components
        T = len(self.tris)
        flat = self.tris.reshape(-1, 3)
        keys = np.round(flat / 1e-4).astype(np.int64)
        _, vid = np.unique(keys, axis=0, return_inverse=True)
        vid = vid.reshape(-1, 3)
        a = np.concatenate([vid[:, 0], vid[:, 1], vid[:, 2]])
        b = np.concatenate([vid[:, 1], vid[:, 2], vid[:, 0]])
        tri = np.tile(np.arange(T), 3)
        length = np.linalg.norm(flat[np.concatenate([np.arange(T) * 3, np.arange(T) * 3 + 1, np.arange(T) * 3 + 2])]
                                - flat[np.concatenate([np.arange(T) * 3 + 1, np.arange(T) * 3 + 2, np.arange(T) * 3])], axis=1)
        lo, hi = np.minimum(a, b), np.maximum(a, b)
        order = np.lexsort((hi, lo))
        lo, hi, tri, length = lo[order], hi[order], tri[order], length[order]
        same = np.nonzero((lo[1:] == lo[:-1]) & (hi[1:] == hi[:-1]))[0]
        ta, tb = tri[same], tri[same + 1]
        ok = ta != tb
        ta, tb, el = ta[ok], tb[ok], length[same][ok]
        cos = np.einsum("ij,ij->i", self.normal[ta], self.normal[tb])
        join = (self.material[ta] == self.material[tb]) & (self.upright[ta] == self.upright[tb]) \
            & (cos > math.cos(math.radians(self.crease)))
        g = coo_matrix((np.ones(join.sum()), (ta[join], tb[join])), shape=(T, T))
        n, label = connected_components(g, directed=False)
        self.patch = label
        self.n_patches = n
        w = self.area
        self.patch_area = np.bincount(label, w, n)
        pn = np.stack([np.bincount(label, self.normal[:, k] * w, n) for k in range(3)], axis=1)
        self.patch_normal = pn / np.maximum(np.linalg.norm(pn, axis=1), 1e-12)[:, None]
        self.patch_material = np.zeros(n, dtype=np.int64)
        self.patch_material[label] = self.material
        # Boundary between patches: shared edge length per pair, and each patch's perimeter.
        pa, pb = label[ta], label[tb]
        cross = pa != pb
        pa, pb, el = pa[cross], pb[cross], el[cross]
        perim = (np.bincount(pa, el, n) + np.bincount(pb, el, n)).astype(float)
        open_edges = np.ones(len(lo), dtype=bool)
        open_edges[same] = False
        open_edges[same + 1] = False
        perim += np.bincount(label[tri[open_edges]], length[open_edges], n)
        key = np.minimum(pa, pb) * n + np.maximum(pa, pb)
        uniq, inv = np.unique(key, return_inverse=True)
        shared = np.bincount(inv, el)
        self.edges_a, self.edges_b = uniq // n, uniq % n
        self.edges_w = shared / np.maximum(np.minimum(perim[self.edges_a], perim[self.edges_b]), 1e-9)


# ---------------------------------------------------------------------------------------------
# Factorio's sprite for a picture, as the client composes it (sprite_projection.gd _compose)

class Sprites:
    def __init__(self, factorio):
        self.data = os.path.join(factorio, "data")
        self.sheets = {}

    def sheet(self, file):
        if file not in self.sheets:
            from PIL import Image
            path = os.path.join(self.data, file)
            if not os.path.exists(path):
                self.sheets[file] = None
            else:
                Image.MAX_IMAGE_PIXELS = None
                self.sheets[file] = np.asarray(Image.open(path).convert("RGBA"), dtype=np.float32) / 255.0
        return self.sheets[file]

    def frame(self, layer):
        sheet = self.sheet(layer["file"])
        if sheet is None:
            return None
        w, h = int(layer["frame"][0]), int(layer["frame"][1])
        if "xy" in layer:
            x, y = int(layer["xy"][0]), int(layer["xy"][1])
        else:
            line = int(layer.get("line", 0)) or max(1, sheet.shape[1] // max(w, 1))
            i = int(layer.get("index", 0))
            x, y = (i % line) * w, (i // line) * h
        if y + h > sheet.shape[0] or x + w > sheet.shape[1]:
            return None
        out = sheet[y:y + h, x:x + w].copy()
        if "tint" in layer:
            out[..., :3] *= np.array(layer["tint"], dtype=np.float32)
        return out

    def compose(self, layers):
        """(RGBA canvas, anchor (x, y) on it in pixels, pixels per tile), or None."""
        frames, offsets, ppt = [], [], 64.0
        lo, hi = np.array([np.inf, np.inf]), np.array([-np.inf, -np.inf])
        for layer in layers:
            f = self.frame(layer)
            if f is None:
                return None
            ppt = 32.0 / float(layer.get("scale", 0.5))
            centre = np.array(layer.get("shift", [0, 0]), dtype=np.float64) * ppt / 32.0
            size = np.array([f.shape[1], f.shape[0]], dtype=np.float64)
            frames.append(f)
            offsets.append(centre - size / 2.0)
            lo, hi = np.minimum(lo, centre - size / 2.0), np.maximum(hi, centre + size / 2.0)
        w, h = int(math.ceil(hi[0] - lo[0])), int(math.ceil(hi[1] - lo[1]))
        canvas = np.zeros((h, w, 4), dtype=np.float32)
        for f, off in zip(frames, offsets):
            x, y = np.round(off - lo).astype(int)
            fh, fw = f.shape[:2]
            fh, fw = min(fh, h - y), min(fw, w - x)
            if fh <= 0 or fw <= 0:
                continue
            src = f[:fh, :fw]
            dst = canvas[y:y + fh, x:x + fw]
            a = src[..., 3:4]
            out_a = a + dst[..., 3:4] * (1.0 - a)
            rgb = (src[..., :3] * a + dst[..., :3] * dst[..., 3:4] * (1.0 - a)) / np.maximum(out_a, 1e-6)
            canvas[y:y + fh, x:x + fw] = np.concatenate([rgb, out_a], axis=-1)
        return canvas, -lo, ppt


# ---------------------------------------------------------------------------------------------
# Rasterising from Factorio's camera

def turn(v, angle):
    """Turns (..., 3) model-space vectors as the shader does for a model facing `angle` (radians
    clockwise from north): p' = (x c + z s, y, -x s + z c) with a = -angle."""
    a = -angle
    c, s = math.cos(a), math.sin(a)
    x, y, z = v[..., 0], v[..., 1], v[..., 2]
    return np.stack([x * c + z * s, y, -x * s + z * c], axis=-1)


def project(model, sel, angle, entry):
    """(x, up, closeness) per corner of the selected triangles, and their turned normals."""
    p = turn(model.tris[sel], angle)
    n = turn(model.normal[sel], angle)
    if entry.get("projection") == "top":
        across = float(entry.get("across", 1.0))
        uv = model.uv[sel]
        cx, cy = uv[..., 0], uv[..., 1] - 1.0
        a = -angle
        c, s = math.cos(a), math.sin(a)
        cy = -cx * s + cy * c
        up = -(cy + (p[..., 2] - cy) * across)
        return np.stack([p[..., 0], up, p[..., 1]], axis=-1), n, np.array([0.0, 1.0, 0.0])
    stretch = float(entry.get("stretch", 1.0))
    x, y, z = p[..., 0], p[..., 1], p[..., 2]
    return np.stack([x, y * COS - z * SIN * stretch, y * SIN + z * COS], axis=-1), n, VIEW


def rasterise(proj, origin, size, ppt):
    """Index (into proj) of the frontmost triangle per pixel, -1 for none."""
    w, h = size
    depth = np.full((h, w), EMPTY, dtype=np.float64)
    ids = np.full((h, w), -1, dtype=np.int64)
    px = origin[0] + proj[..., 0] * ppt
    py = origin[1] - proj[..., 1] * ppt
    cl = proj[..., 2]
    e1x, e1y = px[:, 1] - px[:, 0], py[:, 1] - py[:, 0]
    e2x, e2y = px[:, 2] - px[:, 0], py[:, 2] - py[:, 0]
    area = e1x * e2y - e1y * e2x
    x0s = np.floor(px.min(axis=1)).astype(int)
    x1s = np.ceil(px.max(axis=1)).astype(int)
    y0s = np.floor(py.min(axis=1)).astype(int)
    y1s = np.ceil(py.max(axis=1)).astype(int)
    for t in np.nonzero(np.abs(area) > 1e-6)[0]:
        x0, x1 = max(x0s[t], 0), min(x1s[t], w - 1)
        y0, y1 = max(y0s[t], 0), min(y1s[t], h - 1)
        if x1 < x0 or y1 < y0:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        dx, dy = gx - px[t, 0], gy - py[t, 0]
        inv = 1.0 / area[t]
        b1 = (dx * e2y[t] - dy * e2x[t]) * inv
        b2 = (e1x[t] * dy - e1y[t] * dx) * inv
        b0 = 1.0 - b1 - b2
        inside = (b0 >= -1e-6) & (b1 >= -1e-6) & (b2 >= -1e-6)
        if not inside.any():
            continue
        d = np.where(inside, b0 * cl[t, 0] + b1 * cl[t, 1] + b2 * cl[t, 2], EMPTY)
        rd = depth[y0:y1 + 1, x0:x1 + 1]
        ri = ids[y0:y1 + 1, x0:x1 + 1]
        front = d > rd
        rd[front] = d[front]
        ri[front] = t
    return ids


def shifted(a, dx, dy, fill):
    """a moved by (dx, dy) pixels: out[y, x] = a[y - dy, x - dx]."""
    out = np.full_like(a, fill)
    h, w = a.shape[:2]
    ys, yd = (slice(0, h - dy), slice(dy, h)) if dy >= 0 else (slice(-dy, h), slice(0, h + dy))
    xs, xd = (slice(0, w - dx), slice(dx, w)) if dx >= 0 else (slice(-dx, w), slice(0, w + dx))
    out[yd, xd] = a[ys, xs]
    return out


def best_shift(model_mask, sprite_mask, align=ALIGN):
    """The nudge (dx, dy) of the model's silhouette that best overlaps the sprite's, and its
    overlap; (0, 0) unless another is clearly better."""
    def iou(dx, dy):
        m = shifted(model_mask, dx, dy, False)
        u = (m | sprite_mask).sum()
        return (m & sprite_mask).sum() / u if u else 0.0
    base = iou(0, 0)
    best = (base, 0, 0)
    for dy in range(-align, align + 1):
        for dx in range(-align, align + 1):
            if dx or dy:
                v = iou(dx, dy)
                if v > best[0]:
                    best = (v, dx, dy)
    if best[0] < base + 0.01:
        return 0, 0, base
    return best[1], best[2], best[0]


def erode(labels, r):
    """Labels where every pixel within r has the same label; -1 elsewhere."""
    keep = labels >= 0
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx or dy:
                keep &= shifted(labels, dx, dy, -2) == labels
    return np.where(keep, labels, -1)


# ---------------------------------------------------------------------------------------------
# Sampling

def pictures(entry):
    """(cell layers, turn angle) for each picture of an entry worth sampling."""
    cells = entry.get("cells", [])
    mode = entry.get("mode", "")
    if mode == "direction":
        if all(c == cells[0] for c in cells):
            # One picture whichever way it faces (the foundry): it only fits facing north.
            return [(cells[0], 0.0)]
        if "pictures" in entry:
            # The client turns the model only as far as the pictures do (model_library.gd PICTURES).
            return [(cells[d], d * math.pi / 2) for d in range(min(int(entry["pictures"]), len(cells)))]
        return [(cells[d], d * math.pi / 2) for d in range(min(4, len(cells)))]
    if mode == "rotation":
        n = len(cells)
        step = max(1, n // 8)
        return [(cells[i], i * 2 * math.pi / n) for i in range(0, n, step)]
    if mode == "variation":
        return [(c, 0.0) for c in cells]
    return [(cells[0], 0.0)] if cells else []


class Samples:
    """Delit pixel colours per patch, gathered over pictures."""

    def __init__(self, n):
        self.n = n
        self.patch, self.rgb, self.raw, self.weight = [], [], [], []

    def add(self, patch, rgb, raw, weight):
        self.patch.append(patch)
        self.rgb.append(rgb)
        self.raw.append(raw)
        self.weight.append(weight)

    def extend(self, other):
        self.patch += other.patch
        self.rgb += other.rgb
        self.raw += other.raw
        self.weight += other.weight

    def groups(self):
        """{patch: (rgb, raw, weight, lab)} of its pixels."""
        if not self.patch or not sum(len(p) for p in self.patch):
            return {}
        patch = np.concatenate(self.patch)
        order = np.argsort(patch, kind="stable")
        patch = patch[order]
        rgb, raw = np.concatenate(self.rgb)[order], np.concatenate(self.raw)[order]
        weight = np.concatenate(self.weight)[order]
        lab = to_lab(rgb)
        starts = np.flatnonzero(np.r_[True, patch[1:] != patch[:-1]])
        ends = np.r_[starts[1:], len(patch)]
        return {int(patch[s0]): (rgb[s0:e], raw[s0:e], weight[s0:e], lab[s0:e]) for s0, e in zip(starts, ends)}


MODE_RADIUS = 11.0  # CIELAB distance: pixels this close to the densest colour make up its sample
MODE_CANDIDATES = 48
# How much more a lit pixel counts than a dark one when finding a colour: (lightness / 50) ** LIT.
# Not for a Wube conversion's own patches: their crevices are patches of their own.
LIT = 0.35


def to_lab(rgb):
    """CIELAB (D65) from linear sRGB (N, 3)."""
    m = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = np.clip(rgb, 0.0, None) @ m.T / np.array([0.9505, 1.0, 1.089])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16.0 / 116.0)
    return np.stack([116.0 * f[:, 1] - 16.0, 500.0 * (f[:, 0] - f[:, 1]), 200.0 * (f[:, 1] - f[:, 2])], axis=1)


def mode(lab, weight, target=None, sigma=(30.0, 18.0), lit=LIT):
    """Mask of the pixels round the densest colour: where most of the pixels agree, so pipes,
    outlines or a neighbour's paint that land on a patch by misalignment don't muddy it. With a
    target (CIELAB), colours near it count for more: sigma = (lightness, chroma)."""
    n = len(lab)
    if n <= 3:
        return np.ones(n, dtype=bool)
    # Candidates spread through the pixels by lightness, the best scoring wins, then a few
    # mean-shift steps settle it on its cluster's centre.
    order = np.argsort(lab[:, 0], kind="stable")
    cand = lab[order[np.linspace(0, n - 1, min(MODE_CANDIDATES, n)).astype(int)]]
    pick = np.linspace(0, n - 1, min(n, 4000)).astype(int)
    # Lit pixels say more about the paint than ones in a crevice or a painted shadow, which
    # Factorio's sprites have plenty of: weigh them by lightness.
    sub, wsub = lab[pick], weight[pick] * np.clip(lab[pick, 0] / 50.0, 0.01, 2.0) ** lit
    d2 = ((cand[:, None, :] - sub[None, :, :]) ** 2).sum(axis=2)
    score = (np.exp(-d2 / (2.0 * MODE_RADIUS ** 2)) * wsub[None, :]).sum(axis=1)
    if target is not None:
        score *= affinity(cand, target, sigma)
    centre = cand[np.argmax(score)]
    for _ in range(4):
        near = ((lab - centre) ** 2).sum(axis=1) < MODE_RADIUS ** 2
        if not near.any():
            break
        centre = (lab[near] * weight[near, None]).sum(axis=0) / weight[near].sum()
    # The colour's pixels: close in hue and chroma, but over a broad range of lightness, so the
    # mean (in linear light) keeps the highlights and shade of that paint the eye averages.
    dl = np.abs(lab[:, 0] - centre[0])
    dc = ((lab[:, 1:] - centre[1:]) ** 2).sum(axis=1)
    near = (dc < BAND_CHROMA ** 2) & (dl < BAND_LIGHTNESS)
    if near.sum() < 3:
        return np.ones(n, dtype=bool)
    lo, hi = np.percentile(lab[near, 0], [8.0, 96.0])
    return near & (lab[:, 0] >= lo) & (lab[:, 0] <= hi)


BAND_CHROMA = 9.0
BAND_LIGHTNESS = 24.0


def affinity(lab, target, sigma):
    dl = lab[..., 0] - target[0]
    dc = ((lab[..., 1:] - target[1:]) ** 2).sum(axis=-1)
    return np.exp(-dl * dl / (2.0 * sigma[0] ** 2) - dc / (2.0 * sigma[1] ** 2))


def stray(a, b):
    """CIELAB distance with lightness counting half: a darker or lighter patch of one paint is
    still that paint."""
    d = np.asarray(a) - np.asarray(b)
    return float(np.sqrt((0.5 * d[0]) ** 2 + d[1] ** 2 + d[2] ** 2))


def sample(model, entry, sprites, upright=False, opts=None):
    """Samples for every patch of the model from the entry's pictures, by how far inside their
    patch the pixels are: {"strict": eroded ERODE px (at 64 per tile), "mid": one less, "all": no
    erosion}; the picture's pixels with the material in front (Field); debug shots."""
    layers = {"strict": Samples(model.n_patches), "mid": Samples(model.n_patches), "all": Samples(model.n_patches)}
    field = Field()
    sel = np.nonzero(model.upright == upright)[0]
    if len(sel) == 0:
        return layers, field, []
    opts = opts or {}
    anchor_z = float(entry.get("anchor", 0.3))
    shots = []
    chosen = pictures(entry)
    if "cells" in opts and not upright:
        chosen = [chosen[i] for i in opts["cells"] if i < len(chosen)]
    for cell, angle in chosen:
        composed = sprites.compose(cell)
        if composed is None:
            continue
        canvas, anchor, ppt = composed
        if upright:
            angle = 0.0
        proj, nrm, view = project(model, sel, angle, entry)
        facing = nrm @ view
        front = np.nonzero(facing > 0.05)[0]
        h, w = canvas.shape[:2]
        origin = (anchor[0], anchor[1] + anchor_z * COS * ppt)
        local = rasterise(proj[front], origin, (w, h), ppt)
        tri = np.where(local >= 0, front[np.maximum(local, 0)], -1)  # index into sel
        alpha = canvas[..., 3]
        dx, dy, fit = best_shift(tri >= 0, alpha > 0.5, int(opts.get("align", ALIGN)))
        tri = shifted(tri, dx, dy, -1)
        patch_img = np.where(tri >= 0, model.patch[sel[np.maximum(tri, 0)]], -1)
        r = max(1, int(round(ppt / 32.0)))
        scale = (64.0 / ppt) ** 2  # pixels counted at 64 per tile
        mid = erode(patch_img, r - 1) if r > 1 else patch_img
        for target, labels in ((layers["strict"], erode(patch_img, r)), (layers["mid"], mid), (layers["all"], patch_img)):
            ys, xs = np.nonzero((labels >= 0) & (alpha > 0.9))
            t = tri[ys, xs]
            f = facing[t]
            good = f > 0.25
            ys, xs, t, f = ys[good], xs[good], t[good], f[good]
            raw = srgb_to_linear(canvas[ys, xs, :3].astype(np.float64))
            delit = raw / shade(nrm[t])[:, None]
            target.add(model.patch[sel[t]], delit, raw, np.full(len(t), scale) * np.clip(f, 0.3, 1.0))
        # Every opaque pixel of the picture, with the material in front of it (-1: none), for
        # finding a material's colour anywhere in the sprite.
        ys, xs = np.nonzero(alpha > 0.9)
        t = tri[ys, xs]
        on = t >= 0
        light = np.where(on, shade(nrm[np.maximum(t, 0)]), shade(np.array([0.0, 1.0, 0.0])) * 0.85)
        field.add(srgb_to_linear(canvas[ys, xs, :3].astype(np.float64)) / light[:, None],
                  np.where(on, model.material[sel[np.maximum(t, 0)]], -1), scale)
        shots.append({"canvas": canvas, "tri": tri, "sel": sel, "nrm": nrm, "fit": fit, "shift": (dx, dy),
                      "proj": proj, "origin": origin, "ppt": ppt, "facing": facing})
    return layers, field, shots


class Field:
    """A picture's opaque pixels (delit, linear) and the material in front of each."""

    def __init__(self):
        self.rgb, self.material, self.weight = [], [], []

    def add(self, rgb, material, weight):
        self.rgb.append(rgb)
        self.material.append(material)
        self.weight.append(np.full(len(rgb), weight))

    def extend(self, other):
        self.rgb += other.rgb
        self.material += other.material
        self.weight += other.weight

    def arrays(self):
        if not self.rgb:
            return np.zeros((0, 3)), np.zeros(0, dtype=np.int64), np.zeros(0), np.zeros((0, 3))
        rgb = np.concatenate(self.rgb)
        pick = np.linspace(0, len(rgb) - 1, min(len(rgb), 30000)).astype(int)
        rgb = rgb[pick]
        return rgb, np.concatenate(self.material)[pick], np.concatenate(self.weight)[pick], to_lab(rgb)


# Where the model has a material in front, the sprite's pixels count fully for that material's
# colour; elsewhere in the picture (the model's parts don't sit where the sprite's do) this much.
ELSEWHERE = 0.3
# ... unless this share of the pixels under its parts agree on one colour.
AGREE = 0.5
RANGE = 4.0   # stored colour = colour / RANGE (factorio_material.gdshaderinc PART_RANGE)
SHARE = 0.25  # stored share = share * SHARE (PART_SHARE)
THIN_PIXELS = 10  # interior pixels (at 64 per tile) a patch needs to be sampled at all
LOOSE_WEIGHT = 0.5  # how much a sample from a narrow patch's less eroded pixels counts


# How far (CIELAB) a patch's own colour may stray from its material's colour in the sprite before
# it counts as a misplaced sample, for models built from the sprites by hand (kit, nature, Space
# Age). Wube's conversions are the geometry the sprites were rendered from: their patches go
# their own way.
STRAY = 20.0
FREE_FIT = 0.8  # silhouette overlap a Wube conversion needs for its patches to go their own way
# Families whose pieces stand side by side (a wall's 21 pieces fit their pictures from 0.7 to 0.96):
# coloured by material, so neighbouring pieces match.
BY_MATERIAL_FAMILIES = ("stone-wall",)


def choose(model, layers, field, free):
    """Colour (linear), pixel weight and raw colour per patch, and each material's colour.

    First each material's colour in the sprite: among all its patches' pixels, the densest
    colour near the palette's (the modeller's intent, in Factorio's actual shade). Then each
    patch's own: its densest colour near the material's. A hand-built model's patch keeps that
    only when it is within STRAY of the material's, else it counts as unseen and is filled from
    its neighbours and material; a Wube conversion's patch (`free`) keeps its own."""
    n = model.n_patches
    mean, raw, count = np.zeros((n, 3)), np.zeros((n, 3)), np.zeros(n)
    # Only pixels inside a patch: a thin part (a wire, a cable, a collar) lying on a painted body has
    # nothing but the body round its outline, so with too few of its own it counts as unseen and
    # takes its material's colour. A well-fitting Wube conversion's small patches sit where the
    # sprite has them: a few pixels do, outline and all.
    thin = 0.5 if free else THIN_PIXELS
    pixels = {p: g for p, g in layers["strict"].groups().items() if g[2].sum() >= thin}
    for p, g in layers["all" if free else "mid"].groups().items():
        if p not in pixels and g[2].sum() >= thin:
            pixels[p] = (g[0], g[1], g[2] * LOOSE_WEIGHT, g[3])
    material = {}
    f_rgb, f_mat, f_w, f_lab = field.arrays()
    for mat in np.unique(model.patch_material):
        if free:
            # Wube's geometry sits where the sprite's does: the densest colour under the material.
            ps = [p for p in pixels if model.patch_material[p] == mat]
            if not ps:
                continue
            lab = np.concatenate([pixels[p][3] for p in ps])
            w = np.concatenate([pixels[p][2] for p in ps])
            rgb = np.concatenate([pixels[p][0] for p in ps])
            sel = mode(lab, w)
        else:
            # A hand-built model's parts rarely sit exactly where the sprite has them, but its
            # materials say what each part is meant to be: the sprite's colour nearest the
            # palette's, preferably under the material's own parts.
            if not (f_mat == mat).any() and not any(model.patch_material[p] == mat for p in pixels):
                continue
            # Unless the sprite under the material's parts clearly agrees on another colour (a
            # teal body the palette calls grey): then that.
            target = to_lab(model.palette[mat][None])[0]
            under = f_mat == mat
            if under.sum() > 200:
                lw = f_w[under]
                lsel = mode(f_lab[under], lw)
                share = lw[lsel].sum() / lw.sum()
                local = f_lab[under][lsel]
                if share > AGREE and np.average(local[:, 0], weights=lw[lsel]) > 22.0:
                    rgb = f_rgb[under][lsel]
                    material[int(mat)] = to_lab((rgb * lw[lsel, None]).sum(axis=0)[None] / lw[lsel].sum())[0]
                    continue
            lab, rgb = f_lab, f_rgb
            w = f_w * np.where(under, 1.0, ELSEWHERE)
            sel = mode(lab, w, target, (28.0, 14.0))
        material[int(mat)] = to_lab(((rgb[sel] * w[sel, None]).sum(axis=0) / w[sel].sum())[None])[0]
    for p, (rgb, rawc, w, lab) in pixels.items():
        target = material.get(int(model.patch_material[p]))
        sel = mode(lab, w, target, (40.0, 28.0), lit=0.0) if free else mode(lab, w, target, (40.0, 14.0))
        c = (rgb[sel] * w[sel, None]).sum(axis=0) / w[sel].sum()
        share = w[sel].sum() / w.sum()
        sure = 1.0
        if not free and target is not None and stray(to_lab(c[None])[0], target) > STRAY:
            # Probably a misplaced sample (the material's colour and the neighbours decide), unless
            # a big patch's pixels mostly agree on it (a painted band the palette doesn't have).
            if share < 0.6 or w.sum() < 3 * FULL_PIXELS:
                continue
            sure = 0.5
        mean[p] = c
        raw[p] = (rawc[sel] * w[sel, None]).sum(axis=0) / w[sel].sum()
        # A patch whose pixels disagree (half yellow tank, half grey pipe) is less sure of itself.
        count[p] = w.sum() * (0.4 + 0.6 * share) * sure
    return mean, raw, count, material


def solve(model, measured, count, prior, prior_known):
    """Colour per patch: measured ones kept (by confidence), the rest from their neighbours, all
    leaning to the prior (their material's average). Returns the colours and how much of each
    comes from the sprite rather than the palette (prior_known: the prior came from it)."""
    from scipy.sparse import coo_matrix, diags
    from scipy.sparse.linalg import spsolve
    n = model.n_patches
    conf = np.clip(count / FULL_PIXELS, 0.0, 1.0)
    a, b = model.edges_a, model.edges_b
    same = model.patch_material[a] == model.patch_material[b]
    tilt = np.abs(model.patch_normal[a, 1] - model.patch_normal[b, 1])
    w = SMOOTH * model.edges_w * np.where(same, 1.0, CROSS_MATERIAL) * np.exp(-TILT * tilt)
    lap = coo_matrix((np.r_[-w, -w], (np.r_[a, b], np.r_[b, a])), shape=(n, n)).tocsr()
    degree = -np.asarray(lap.sum(axis=1)).ravel()
    lean = PRIOR + MATERIAL_PULL * conf
    m = (lap + diags(degree + conf + lean)).tocsc()
    out = np.stack([spsolve(m, conf * measured[:, k] + lean * prior[:, k]) for k in range(3)], axis=1)
    owed = spsolve(m, conf + lean * prior_known)  # the same with the sprite's colours 1, the palette's 0
    return np.clip(out, 0.0, 1.0), np.clip(owed, 0.0, 1.0)


def material_average(model, colour, count):
    """Per material: count-weighted average of measured patches, or None."""
    out = {}
    for mat in np.unique(model.patch_material):
        sel = (model.patch_material == mat) & (count > 0)
        if sel.any():
            wgt = np.minimum(count[sel], FULL_PIXELS * 4) * np.sqrt(model.patch_area[sel])
            out[int(mat)] = (colour[sel] * wgt[:, None]).sum(axis=0) / wgt.sum()
    return out


def colours_for(name, entries, sprites, opts=None):
    """(model, colour per patch, share from the sprite, debug shots, raw colours, pixel weights,
    corner colours or None), or None when no picture could be sampled. opts: the model's tuning
    (overrides_for)."""
    opts = overrides_for(name) if opts is None else opts
    glb = Glb(os.path.join(MODELS, name + ".glb"))
    model = Model(glb, float(opts.get("crease", CREASE)), opts.get("merge_materials", ()))
    entry = entries.get(opts.get("entry", name))
    if entry is None:
        return None
    layers = None
    field = Field()
    shots = []
    if name + ".upright" in entries:
        passes = [(entry, False), (entries[name + ".upright"], True)]
    else:
        # No separate picture for upright parts: they wear the model's.
        model.upright[:] = False
        passes = [(entry, False)]
    for e, up in passes:
        got, fi, sh = sample(model, e, sprites, upright=up, opts=opts)
        if layers is None:
            layers = got
        else:
            for k in layers:
                layers[k].extend(got[k])
        field.extend(fi)
        shots += sh
    # Wube's conversions are the sprites' own geometry, so their patches may keep their own
    # colours; not where a picture doesn't fit (the inserters' platforms, the creatures' poses).
    fits = [sh["fit"] for sh in shots]
    free = name in wube_models() and bool(fits) and float(np.median(fits)) >= FREE_FIT \
        and not name.startswith(BY_MATERIAL_FAMILIES)
    free = bool(opts.get("free", free))
    model.free = free
    measured, raw, count, material = choose(model, layers, field, free)
    if not count.any() and not material:
        return None
    averages = material_average(model, measured, count)
    for mat, lab in material.items():
        averages.setdefault(mat, from_lab(lab))
    # glTF base colours are linear already.
    prior = np.array([averages.get(int(m), model.palette[m]) for m in model.patch_material])
    known = np.array([1.0 if int(m) in averages else 0.0 for m in model.patch_material])
    colour, owed = solve(model, measured, count, prior, known)
    grade = (float(opts.get("exposure", 1.0)), float(opts.get("saturation", 1.0)))
    colour = expose(saturate(colour, grade[1]), grade[0])
    forced = apply_forced(model, colour, owed, opts, grade)
    corners = None
    two = opts.get("two_tone")
    if two:
        names = set(model.material_names) if two in ("*", True) else set(two)
        mats = [i for i, n in enumerate(model.material_names) if n in names and i not in forced]
        if mats:
            corners = two_tone(model, colour, shots, mats, grade, float(opts.get("two_tone_blur", TWO_TONE_BLUR)),
                               opts.get("two_tone_tint"))
    return model, colour, owed, shots, raw, count, corners


def hex_colour(text):
    h = text.lstrip("#")
    return srgb_to_linear(np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]))


def apply_forced(model, colour, owed, opts, grade=(1.0, 1.0)):
    """Sets the override's forced colours on the patches of those materials; returns the
    material indices it set. "colors": {material: "#rrggbb"} is the albedo as is;
    "sprite_colors": {material: "#rrggbb"} is a colour as the sprite shows it, put through the
    same light correction (averaged over each part's triangles) and grading as a sampled one."""
    done = []
    for key, sampled in (("colors", False), ("sprite_colors", True)):
        for mname, text in (opts.get(key) or {}).items():
            if mname not in model.material_names:
                continue
            mat = model.material_names.index(mname)
            sel = model.patch_material == mat
            lin = hex_colour(text)
            if sampled:
                # The light correction averaged over each patch's triangles: a round part (a
                # cylinder, a dome) has no meaningful mean facing.
                inv = np.bincount(model.patch, model.area / shade(model.normal), model.n_patches)
                inv = inv / np.maximum(model.patch_area, 1e-12)
                c = lin[None, :] * np.where(model.patch_area > 0, inv, 1.0 / shade(model.patch_normal))[sel][:, None]
                colour[sel] = expose(saturate(c, grade[1]), grade[0])
            else:
                colour[sel] = lin
            owed[sel] = 1.0
            done.append(mat)
    return done


def forced_only(name, opts):
    """A model without a sprite to sample: its palette, with the override's forced colours."""
    model = Model(Glb(os.path.join(MODELS, name + ".glb")), float(opts.get("crease", CREASE)),
                  opts.get("merge_materials", ()))
    model.free = False
    colour = np.array([model.palette[m] for m in model.patch_material])
    owed = np.zeros(model.n_patches)
    grade = (float(opts.get("exposure", 1.0)), float(opts.get("saturation", 1.0)))
    if not apply_forced(model, colour, owed, opts, grade):
        return None
    return model, colour, owed


# Soft two-colour regions (override "two_tone"): each corner of those materials' parts takes the
# sprite's colour round where it lands, blurred over TWO_TONE_BLUR tiles of the same material's
# pixels so no detail shows, and kept within TWO_TONE_RANGE (CIELAB) of its part's colour.
TWO_TONE_BLUR = 0.2
TWO_TONE_RANGE = 30.0


def two_tone(model, colour, shots, mats, grade, blur, tint=None):
    """(T, 3, 3) colour per triangle corner (NaN where the part's colour stays). `tint`
    ({material name: 0..1}) scales how far those materials' corners may leave their part's hue
    and chroma (0: only lighter or darker)."""
    from scipy.ndimage import gaussian_filter
    T = len(model.tris)
    total = np.zeros((T, 3, 3))
    weight = np.zeros((T, 3))
    flagged = np.isin(model.material, mats)
    for shot in shots:
        tri, sel, nrm, canvas = shot["tri"], shot["sel"], shot["nrm"], shot["canvas"]
        ppt, (ox, oy), (dx, dy) = shot["ppt"], shot["origin"], shot["shift"]
        h, w = tri.shape
        on = tri >= 0
        t = np.maximum(tri, 0)
        mask = on & flagged[sel[t]] & (canvas[..., 3] > 0.9) & (shot["facing"][t] > 0.25)
        lin = srgb_to_linear(canvas[..., :3].astype(np.float64)) / shade(nrm[t])[..., None]
        sigma = blur * ppt
        m = gaussian_filter(mask.astype(np.float64), sigma)
        col = np.stack([gaussian_filter(np.where(mask, lin[..., k], 0.0), sigma) for k in range(3)], axis=-1)
        proj = shot["proj"]  # (len(sel), 3, 3): x, up, closeness per corner
        px = np.clip(np.round(ox + proj[..., 0] * ppt + dx - 0.5).astype(int), 0, w - 1)
        py = np.clip(np.round(oy - proj[..., 1] * ppt + dy - 0.5).astype(int), 0, h - 1)
        mine = flagged[sel][:, None] & (shot["facing"][:, None] > 0.25)
        # Only corners the camera sees: their pixel is in front from their own patch.
        seen = (tri[py, px] >= 0) & (model.patch[sel[np.maximum(tri[py, px], 0)]] == model.patch[sel][:, None])
        good = mine & seen & (m[py, px] > 0.3)
        c = col[py, px] / np.maximum(m[py, px], 1e-6)[..., None]
        total[sel] += np.where(good[..., None], c, 0.0)
        weight[sel] += good
    out = np.full((T, 3, 3), np.nan)
    has = weight > 0
    if not has.any():
        return None
    local = total[has] / weight[has][:, None]
    local = expose(saturate(local, grade[1]), grade[0])
    base = np.repeat(colour[model.patch][:, None, :], 3, axis=1)[has]
    lb, ll = to_lab(base), to_lab(local)
    d = ll - lb
    if tint:
        corner_mat = np.repeat(model.material[:, None], 3, axis=1)[has]
        for mname, k in tint.items():
            if mname in model.material_names:
                d[corner_mat == model.material_names.index(mname), 1:] *= float(k)
    dist = np.linalg.norm(d, axis=1)
    ll = lb + d * np.minimum(1.0, TWO_TONE_RANGE / np.maximum(dist, 1e-6))[:, None]
    smooth = np.stack([from_lab(c) for c in ll])
    # Smooth over each part in model space, so neighbouring corners (a cap's rim, sampled at pixels
    # either side of an outline) don't alternate into wedges, and fill the part's unseen corners
    # near seen ones.
    from scipy.spatial import cKDTree
    pos = model.tris[has]
    patch = np.repeat(model.patch[:, None], 3, axis=1)[has]
    tree = cKDTree(pos)
    radius = max(blur, 0.05)
    all_pos = model.tris.reshape(-1, 3)
    all_patch = np.repeat(model.patch[:, None], 3, axis=1).reshape(-1)
    wanted = np.repeat(np.isin(model.material, mats)[:, None], 3, axis=1).reshape(-1)
    flat = np.full((len(all_pos), 3), np.nan)
    for i in np.nonzero(wanted)[0]:
        near = tree.query_ball_point(all_pos[i], radius)
        near = [j for j in near if patch[j] == all_patch[i]]
        if not near:
            continue
        d2 = ((pos[near] - all_pos[i]) ** 2).sum(axis=1)
        wgt = np.exp(-d2 / (2.0 * (radius / 2.0) ** 2))
        flat[i] = (smooth[near] * wgt[:, None]).sum(axis=0) / wgt.sum()
    out = flat.reshape(-1, 3, 3)
    return out


def expose(rgb, scale=1.0):
    """EXPOSURE (times scale) with a soft knee on the luminance (hue kept)."""
    y = rgb @ np.array([0.2126, 0.7152, 0.0722])
    return rgb * (EXPOSURE * scale / (1.0 + KNEE * y))[:, None]


def saturate(rgb, scale=1.0):
    """Chroma (CIELAB) scaled by SATURATION (times scale), linear in and out."""
    lab = to_lab(rgb)
    lab[:, 1:] *= SATURATION * scale
    return np.stack([from_lab(c) for c in lab]) if len(lab) else rgb


OVERRIDES_DIR = os.path.join(HERE, "part_colors_overrides")
_OVERRIDES = None


def overrides():
    """{pattern: tuning} from every tools/models/part_colors_overrides/<family>.py (its OVERRIDES
    dict; keys are model names or fnmatch patterns). See tools/models/PART_COLORS.md."""
    global _OVERRIDES
    if _OVERRIDES is None:
        import importlib.util
        _OVERRIDES = []
        if os.path.isdir(OVERRIDES_DIR):
            for fname in sorted(os.listdir(OVERRIDES_DIR)):
                if not fname.endswith(".py") or fname.startswith("_"):
                    continue
                spec = importlib.util.spec_from_file_location("part_colors_overrides." + fname[:-3],
                                                              os.path.join(OVERRIDES_DIR, fname))
                module = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(module)
                for pattern, tuning in getattr(module, "OVERRIDES", {}).items():
                    _OVERRIDES.append((pattern, dict(tuning), fname))
    return _OVERRIDES


def overrides_for(name):
    """The tuning for one model: every matching entry merged, exact names last (they win)."""
    import fnmatch
    out = {}
    matches = [(p != name, p, t) for p, t, _ in overrides() if p == name or fnmatch.fnmatchcase(name, p)]
    for _, _, tuning in sorted(matches, key=lambda m: (not m[0], m[1])):
        out.update(tuning)
    return out


_WUBE = None


def wube_models():
    """Names of the models converted from Wube's printable files (wube_recipes.py)."""
    global _WUBE
    if _WUBE is None:
        sys.path.insert(0, HERE)
        try:
            import wube_recipes
            _WUBE = set(wube_recipes.RECIPES)
        except Exception:
            _WUBE = set()
    return _WUBE


def from_lab(lab):
    """Linear sRGB from CIELAB (D65)."""
    fy = (lab[0] + 16.0) / 116.0
    f = np.array([fy + lab[1] / 500.0, fy, fy - lab[2] / 200.0])
    xyz = np.where(f > 0.206893, f ** 3, (f - 16.0 / 116.0) / 7.787) * np.array([0.9505, 1.0, 1.089])
    m = np.array([[3.2406, -1.5372, -0.4986], [-0.9689, 1.8758, 0.0415], [0.0557, -0.2040, 1.0570]])
    return np.clip(m @ xyz, 0.0, None)


def donor_colours(name, donor_model, donor_colour):
    """Per-material average colours from a donor model, for a model without a sprite entry."""
    glb = Glb(os.path.join(MODELS, name + ".glb"))
    model = Model(glb)
    names = donor_model.material_names
    by_name = {}
    for mat in np.unique(donor_model.patch_material):
        sel = donor_model.patch_material == mat
        wgt = donor_model.patch_area[sel]
        by_name[names[mat]] = (donor_colour[sel] * wgt[:, None]).sum(axis=0) / max(wgt.sum(), 1e-12)
    colour = np.zeros((model.n_patches, 3))
    owed = np.zeros(model.n_patches)
    for p in range(model.n_patches):
        mname = model.material_names[model.patch_material[p]]
        if mname in by_name:
            colour[p] = by_name[mname]
            owed[p] = 1.0
        else:
            colour[p] = model.palette[model.patch_material[p]]
    return model, colour, owed


def lift_occlusion(model):
    """Applies bake.py's long-face occlusion lift to the model's COLOR_0 alpha, so models baked
    before it (a pipe barrel dark from end to end) are fixed without a rebuild. Idempotent."""
    sys.path.insert(0, HERE)
    import bake
    glb = model.glb
    if not any("COLOR_0" in prim["attributes"] for _, _, prim in model.prims):
        return
    ao = np.ones((len(model.tris), 3))
    cols = {}
    for k, (_m, _p, prim) in enumerate(model.prims):
        if "COLOR_0" in prim["attributes"]:
            c = glb.accessor(prim["attributes"]["COLOR_0"])
            cols[k] = c
            sel = np.nonzero(model.prim_of == k)[0]
            if c.shape[1] > 3:
                ao[sel] = c[model.corner_vert[sel], 3]
    vox = bake._Voxels(model.tris, 1)
    lifted = bake.lift_long_faces(vox, model.tris, ao)
    for k, c in cols.items():
        if c.shape[1] < 4:
            continue
        sel = np.nonzero(model.prim_of == k)[0]
        new = c[:, 3].copy()
        for j in range(3):
            np.maximum.at(new, model.corner_vert[sel, j], lifted[sel, j])
        if np.any(new > c[:, 3] + 1e-4):
            c[:, 3] = new
            glb.overwrite(model.prims[k][2]["attributes"]["COLOR_0"], c)


def write(model, colour, owed, corners=None):
    """Stores the patch colours per vertex (TEXCOORD_4, _5) and saves the .glb. corners: optional
    (T, 3, 3) colours per triangle corner that replace the patch's (NaN: keep it)."""
    glb = model.glb
    lift_occlusion(model)
    corner_colour = np.repeat(colour[model.patch][:, None, :], 3, axis=1)
    if corners is not None:
        corner_colour = np.where(np.isnan(corners), corner_colour, corners)
    tri_colour = colour[model.patch]
    tri_owed = owed[model.patch]
    # The nature models shade themselves through COLOR_0's rgb, which the client multiplies in:
    # store the colour over the patch's average of it, so the result averages to the sample.
    tint_sum = np.zeros((model.n_patches, 3))
    np.add.at(tint_sum, model.patch, model.tint * model.area[:, None])
    patch_tint = tint_sum / np.maximum(model.patch_area, 1e-12)[:, None]
    patch_tint = np.where(model.patch_area[:, None] > 0, patch_tint, 1.0)
    # Leaf cards (nature/geo.py `card`) are a patch each, shaded light to dark across the crown:
    # divided by one tint for the whole material instead, so the crown keeps that shading. The
    # sample is what the sprite shows, mostly the crown's outside, so it is the outer, lighter
    # cards' tint (the upper quartile) that brings it back, and the inner ones go darker than it.
    for mat, mname in enumerate(model.material_names):
        cards = model.patch_material == mat
        if mname.startswith("leafcard") and cards.any():
            tints = patch_tint[cards]
            lum = tints @ np.array([0.2126, 0.7152, 0.0722])
            mean = tints.mean(axis=0)
            patch_tint[cards] = mean * np.quantile(lum, 0.75) / max(float(mean @ np.array([0.2126, 0.7152, 0.0722])), 1e-6)
    corner_colour = corner_colour / np.maximum(patch_tint[model.patch], 0.05)[:, None, :]
    for k, (_mesh, _pi, prim) in enumerate(model.prims):
        sel = np.nonzero(model.prim_of == k)[0]
        count = glb.accessor(prim["attributes"]["POSITION"]).shape[0]
        acc = np.zeros((count, 4))
        hits = np.zeros(count)
        verts = model.corner_vert[sel]
        for c in range(3):
            np.add.at(acc[:, :3], verts[:, c], corner_colour[sel, c])
            np.add.at(acc[:, 3], verts[:, c], tri_owed[sel])
            np.add.at(hits, verts[:, c], 1.0)
        acc /= np.maximum(hits, 1.0)[:, None]
        # Headroom: rgb / RANGE (hue kept if a colour still goes over), share * SHARE, which also
        # tells this layout from the first one's (rgb and share as is, shares mostly 1).
        rgb = acc[:, :3] / RANGE
        rgb /= np.maximum(rgb.max(axis=1), 1.0)[:, None]
        acc = np.concatenate([rgb, acc[:, 3:4] * SHARE], axis=1)
        attrs = prim["attributes"]
        for name in ("TEXCOORD_2", "TEXCOORD_3"):
            if name not in attrs:
                glb.set_vec2(prim, name, np.ones((count, 2)))
        if "TEXCOORD_1" not in attrs:
            glb.set_vec2(prim, "TEXCOORD_1", np.tile([0.0, 0.5], (count, 1)))
        if "TEXCOORD_0" not in attrs:
            glb.set_vec2(prim, "TEXCOORD_0", np.zeros((count, 2)))
        glb.set_vec2(prim, "TEXCOORD_4", acc[:, 0:2], unorm=True)
        glb.set_vec2(prim, "TEXCOORD_5", acc[:, 2:4], unorm=True)
    glb.save()


# ---------------------------------------------------------------------------------------------
# Debug pictures: the sprite next to the patch colours lit as Factorio lights them

def debug_image(name, model, colour, shots, out_dir, corners=None):
    """<out_dir>/<name>.png: each sampled picture (up to four) side by side, the sprite above and
    below the colours as stored (grading, roll-off and two-tone included), lit about as the client
    shows them from Factorio's view: a top face at its colour, the rest by SHADE relative to it."""
    from PIL import Image
    os.makedirs(out_dir, exist_ok=True)
    bg = np.array([0.35, 0.33, 0.3])
    columns, gaps = [], []
    for shot in shots[:4]:
        canvas, tri, sel, nrm = shot["canvas"], shot["tri"], shot["sel"], shot["nrm"]
        h, w = tri.shape
        relit = np.tile(bg, (h, w, 1))
        on = tri >= 0
        t = tri[on]
        tri_colour = colour[model.patch]
        if corners is not None:
            mean = np.nanmean(np.where(np.isnan(corners), tri_colour[:, None, :], corners), axis=1)
            tri_colour = mean
        top = shade(np.array([0.0, 1.0, 0.0]))
        relit[on] = linear_to_srgb(tri_colour[sel[t]] * (shade(nrm[t]) / top)[:, None])
        a = canvas[..., 3:4]
        top = canvas[..., :3] * a + bg * (1 - a)
        columns.append(np.concatenate([top, np.ones((4, w, 3)), relit], axis=0))
        both = on & (canvas[..., 3] > 0.5)
        if both.any():
            gaps.append(float(np.linalg.norm(to_lab(srgb_to_linear(top[both])) - to_lab(srgb_to_linear(relit[both])), axis=1).mean()))
    if gaps:
        # How far the colours as the client paints them are from the sprite's under them (CIELAB
        # delta E, mean over the pixels both cover): tools/models/score_world.py's colour column.
        print("%-34s colour gap %.1f" % (name, sum(gaps) / len(gaps)))
    if not columns:
        return
    height = max(c.shape[0] for c in columns)
    columns = [np.pad(c, ((0, height - c.shape[0]), (0, 6), (0, 0)), constant_values=1.0) for c in columns]
    img = np.concatenate(columns, axis=1)
    Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).save(os.path.join(out_dir, name + ".png"))


# ---------------------------------------------------------------------------------------------

def fit_light(results):
    """Prints the light (azimuth, elevation, ambient) that best explains how bright patches are by
    the way they face, over every model: the patches' median brightness per facing (top, south,
    west, east, ...) relative to the top's. Over thousands of patches the paint averages out and
    the light painted into the sprites remains. results: (model, raw colour, pixel weight)."""
    n = np.concatenate([m.patch_normal[c > 20] for m, _, c in results])
    lum = np.concatenate([r[c > 20] @ np.array([0.2126, 0.7152, 0.0722]) for _, r, c in results])
    w = np.concatenate([np.sqrt(m.patch_area[c > 20]) for m, _, c in results])
    ok = lum > 1e-4
    n, lum, w = n[ok], np.log(lum[ok]), w[ok]

    def wmedian(x, wt):
        o = np.argsort(x)
        cw = np.cumsum(wt[o])
        return x[o][np.searchsorted(cw, cw[-1] / 2)]

    up = (n[:, 1] > 0.5) & (n[:, 1] < 0.85)
    side = np.abs(n[:, 1]) < 0.3
    bins = {"top": n[:, 1] > 0.9, "south": n[:, 2] > 0.85, "west": n[:, 0] < -0.85, "east": n[:, 0] > 0.85,
            "up-south": up & (n[:, 2] > 0.5), "up-west": up & (n[:, 0] < -0.5), "up-east": up & (n[:, 0] > 0.5),
            "south-west": side & (n[:, 0] < -0.5) & (n[:, 2] > 0.5), "south-east": side & (n[:, 0] > 0.5) & (n[:, 2] > 0.5)}
    stats = []
    for name, sel in bins.items():
        if sel.sum() < 20:
            continue
        mean = (n[sel] * w[sel, None]).sum(axis=0)
        stats.append((name, mean / np.linalg.norm(mean), wmedian(lum[sel], w[sel]), math.sqrt(sel.sum())))
    if not stats or stats[0][0] != "top":
        print("not enough patches")
        return
    top_n, top_l = stats[0][1], stats[0][2]
    best = None
    for az in range(0, 360, 5):
        for el in range(5, 90, 5):
            L = np.array([math.cos(math.radians(el)) * math.sin(math.radians(az)), math.sin(math.radians(el)),
                          -math.cos(math.radians(el)) * math.cos(math.radians(az))])
            for amb in np.arange(0.1, 0.96, 0.025):
                s_top = amb + (1 - amb) * max(0.0, top_n @ L)
                err = sum(wt * (l - top_l - math.log((amb + (1 - amb) * max(0.0, nn @ L)) / s_top)) ** 2
                          for _, nn, l, wt in stats)
                if best is None or err < best[0]:
                    best = (err, az, el, amb, L)
    _, az, el, amb, L = best
    for name, nn, l, _ in stats:
        print("  %-11s %.3f of the top's brightness" % (name, math.exp(l - top_l)))
    print("%d patches: azimuth %d (0 north, 90 east), elevation %d, ambient %.3f, LIGHT %s"
          % (len(n), az, el, amb, np.round(L, 3)))


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("names", nargs="*")
    parser.add_argument("--factorio", default=FACTORIO)
    parser.add_argument("--debug", help="folder for sprite / sampled colour comparison PNGs")
    parser.add_argument("--check", action="store_true", help="report only, write nothing")
    parser.add_argument("--fit-light", action="store_true", help="fit the painted-in light (writes nothing)")
    args = parser.parse_args(argv)
    entries = json.load(open(ENTRIES, encoding="utf-8"))
    if not os.path.isdir(os.path.join(args.factorio, "data", "base")):
        print("no Factorio install at %s (--factorio)" % args.factorio)
        return 1
    sprites = Sprites(args.factorio)
    names = args.names or sorted(n for n in entries if "." not in n and os.path.exists(os.path.join(MODELS, n + ".glb")))
    if not args.names:  # and the models without an entry that an override colours
        names += sorted(n[:-4] for n in os.listdir(MODELS) if n.endswith(".glb") and n[:-4] not in entries
                        and n[:-4] not in DONORS and overrides_for(n[:-4]))
    names += [] if args.names else sorted(DONORS)
    done = {}
    fits = []
    for name in names:
        path = os.path.join(MODELS, name + ".glb")
        if not os.path.exists(path):
            continue
        opts = overrides_for(name)
        corners = None
        if name not in entries and name not in DONORS and "entry" not in opts:
            r = forced_only(name, opts)
            if r is None:
                print("%-34s no sprite entry" % name)
                continue
            model, colour, owed = r
            print("%-34s %5d patches, forced colours only (no sprite entry), tuned: %s"
                  % (name, model.n_patches, ", ".join(sorted(opts))))
            if not args.check and not args.fit_light:
                write(model, colour, owed)
            continue
        if name in DONORS:
            donor = DONORS[name]
            if donor not in done:
                r = colours_for(donor, entries, sprites)
                if r is None:
                    continue
                done[donor] = (r[0], r[1])
            model, colour, owed = donor_colours(name, *done[donor])
            corners = None
            print("%-34s %5d patches, colours from %s" % (name, model.n_patches, donor))
        else:
            r = colours_for(name, entries, sprites)
            if r is None:
                r = forced_only(name, opts)
                if r is None:
                    print("%-34s no picture sampled" % name)
                    continue
                model, colour, owed = r
                print("%-34s %5d patches, forced colours only (nothing sampled), tuned: %s"
                      % (name, model.n_patches, ", ".join(sorted(opts))))
                if not args.check and not args.fit_light:
                    write(model, colour, owed)
                continue
            model, colour, owed, shots, raw, count, corners = r
            done[name] = (model, colour)
            fit = " ".join("%.2f%s" % (s["fit"], "" if s["shift"] == (0, 0) else "(%+d,%+d)" % s["shift"]) for s in shots[:4])
            tuned = overrides_for(name)
            print("%-34s %5d patches, %5d seen, %s, fit %s%s" % (name, model.n_patches, int((count > 0).sum()),
                                                                  "own colours" if model.free else "by material", fit,
                                                                  ", tuned: " + ", ".join(sorted(tuned)) if tuned else ""))
            if args.fit_light:
                fits.append((model, raw, count))
            if args.debug:
                debug_image(name, model, colour, shots, args.debug, corners)
        if not args.check and not args.fit_light:
            write(model, colour, owed, corners)
    if args.fit_light:
        fit_light(fits)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
