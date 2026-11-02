"""Converts Wube's official 3D-printable Factorio models (Friday Facts #447) into client models.

    python tools/models/wube.py --list          # recipes, and which source files were found
    python tools/models/wube.py [names...]      # build models whose source files are present
    python tools/models/wube.py --raw DIR       # every source STL on its own, unassembled (to look at)

Source files: download each model set from https://www.printables.com/@WubeSoftware/models
("Download all model files") and drop the zips, or the extracted folders, anywhere under
`art-src/wube/` (git-ignored). Files are found by name, inside zips too; where a set has "High
Precision" and "High Clearance" copies of a file, High Precision is used. Printables lists the
models as CC BY-NC: check the licence on each model page. Attribution for every converted model
is written to client/assets/models/CREDITS.md.

What a conversion does (recipes in wube_recipes.py):
- millimetres to tiles (25 mm = 1 tile, the print grid's pitch) and STL's z-up to glTF's y-up;
- picks the parts it needs from print plates and drops print-only bits (grid pegs, pins);
- stands up parts printed lying down, stacks parts that print separately (belt surface on its
  frame), and turns the model to face north;
- colours each part from the shared palette in kit.py, so the models match the procedural ones
  (and `tier_paint` gets recoloured for faster belt tiers by the client);
- scales each model to Factorio's size and shape, from its sprite (the prints are stylised);
- decimates to the triangle budget in specs.py, puts the origin at the footprint centre on the
  ground, and writes client/assets/models/<name>.glb.

Plain Python (pip install numpy scipy trimesh fast-simplification), plus Blender for the
decimation if it's installed (BLENDER, on PATH, or the default Windows path): the plain-Python
simplifier is the fallback and does much worse on the dense prints.
"""

import argparse
import ast
import io
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile

import numpy as np
import trimesh

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import bake  # noqa: E402
import specs  # noqa: E402
import wube_recipes  # noqa: E402

SOURCE_DIR = os.path.join(REPO, "art-src", "wube")
MODELS_DIR = os.path.join(REPO, "client", "assets", "models")
MM_PER_TILE = 25.0
CREASE_DEGREES = 35.0
# Written into every converted model, so write_credits can tell them from procedural ones.
GENERATOR = "factorio-3d tools/models/wube.py"


# ---------------------------------------------------------------------------------------------
# Palette: the procedural models' materials, read from kit.py without Blender.

def load_palette():
    with open(os.path.join(HERE, "kit.py"), encoding="utf-8") as f:
        src = f.read()
    materials = ast.literal_eval(re.search(r"^MATERIALS = (\{.*?^\})", src, re.S | re.M).group(1))
    alpha = ast.literal_eval(re.search(r"^ALPHA = (\{.*?\})", src, re.S | re.M).group(1))
    return materials, alpha


def srgb_to_linear(hex_colour):
    out = []
    for i in (0, 2, 4):
        c = int(hex_colour[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return out


# ---------------------------------------------------------------------------------------------
# Source files

def file_key(name):
    """Matches file names loosely: zips and the website don't always agree on case, spaces or
    underscores ("Straight Bottom.stl", "straight_bottom.STL")."""
    return re.sub(r"[^a-z0-9]", "", name.lower())


class Sources:
    """Every .stl under the source folder, in zips or not, by file_key of its name."""

    def __init__(self, root):
        self.root = root
        self.files = {}  # name -> (label, reader)
        if os.path.isdir(root):
            for dirpath, _dirs, names in os.walk(root):
                for name in sorted(names):
                    path = os.path.join(dirpath, name)
                    if name.lower().endswith(".stl"):
                        self._add(name, os.path.relpath(path, root), lambda p=path: open(p, "rb").read())
                    elif name.lower().endswith(".zip"):
                        self._add_zip(path)

    def _add_zip(self, path):
        with zipfile.ZipFile(path) as z:
            for member in z.namelist():
                if member.lower().endswith(".stl"):
                    label = "%s!%s" % (os.path.relpath(path, self.root), member)
                    self._add(os.path.basename(member), label,
                              lambda p=path, m=member: zipfile.ZipFile(p).read(m))
                elif member.lower().endswith(".zip"):  # zips of zips
                    inner = io.BytesIO(z.read(member))
                    with zipfile.ZipFile(inner) as zz:
                        for m in zz.namelist():
                            if m.lower().endswith(".stl"):
                                label = "%s!%s!%s" % (os.path.relpath(path, self.root), member, m)
                                self._add(os.path.basename(m), label,
                                          lambda p=path, mm=member, m2=m: zipfile.ZipFile(
                                              io.BytesIO(zipfile.ZipFile(p).read(mm))).read(m2))

    def _add(self, name, label, reader):
        key = file_key(name)
        old = self.files.get(key)
        # Prefer "High Precision" copies; otherwise keep the first one found.
        if old is None or ("clearance" in old[0].lower() and "clearance" not in label.lower()):
            self.files[key] = (label, reader)

    def has(self, name):
        return file_key(name) in self.files

    def load(self, name):
        """The STL as a mesh in tiles, glTF axes (x east, y up, z south). Cached: a print plate
        that several parts are picked from is read once."""
        cache = self.__dict__.setdefault("_loaded", {})
        if name not in cache:
            cache[name] = self._load(name)
        return cache[name].copy()

    def _load(self, name):
        data = self.files[file_key(name)][1]()
        mesh = trimesh.load(io.BytesIO(data), file_type="stl", process=True)
        v = mesh.vertices / MM_PER_TILE
        mesh.vertices = np.column_stack([v[:, 0], v[:, 2], -v[:, 1]])
        mesh.fix_normals()  # the axis swap is a proper rotation, but some print files aren't wound consistently
        return mesh


# ---------------------------------------------------------------------------------------------
# Geometry helpers. Meshes are in tiles, glTF axes.

def yaw_matrix(degrees):
    """Turn about +y, counter-clockwise seen from above (Godot's Basis(UP, angle))."""
    a = np.radians(degrees)
    m = np.eye(4)
    m[0, 0], m[0, 2], m[2, 0], m[2, 2] = np.cos(a), np.sin(a), -np.sin(a), np.cos(a)
    return m


def tilt_matrix(axis, degrees):
    a = np.radians(degrees)
    c, s = np.cos(a), np.sin(a)
    m = np.eye(4)
    if axis == "x":
        m[1, 1], m[1, 2], m[2, 1], m[2, 2] = c, -s, s, c
    elif axis == "z":
        m[0, 0], m[0, 1], m[1, 0], m[1, 1] = c, -s, s, c
    elif axis == "y":
        return yaw_matrix(degrees)
    else:
        raise ValueError("tilt axis must be x, y or z")
    return m


def translate(mesh, offset):
    mesh.apply_translation(np.asarray(offset, dtype=float))


def footprint_centre(mesh):
    lo, hi = mesh.bounds
    return np.array([(lo[0] + hi[0]) / 2, lo[1], (lo[2] + hi[2]) / 2])


_SPLIT = {}


def pick_components(mesh, ranks):
    """Keep connected pieces of a print plate by rank (0 = most triangles)."""
    key = (len(mesh.faces), float(mesh.vertices.sum()))
    if key not in _SPLIT:
        _SPLIT[key] = sorted(mesh.split(only_watertight=False, repair=False), key=lambda m: -len(m.faces))
    pieces = [m.copy() for m in _SPLIT[key]]
    chosen = [pieces[r] for r in ranks if r < len(pieces)]
    if not chosen:
        raise ValueError("plate has %d pieces, none of ranks %s" % (len(pieces), ranks))
    return trimesh.util.concatenate(chosen)


def pick_in_box(mesh, box):
    """Keep the connected pieces of a print plate whose bounding-box centre lies in `box`
    (x0, y0, x1, y1), in the print file's millimetres (x, y on the plate)."""
    x0, y0, x1, y1 = box
    chosen = []
    for piece in mesh.split(only_watertight=False, repair=False):
        cx, _cy, cz = (piece.bounds[0] + piece.bounds[1]) / 2 * MM_PER_TILE
        if x0 <= cx <= x1 and y0 <= -cz <= y1:  # load() turned the plate's y into -z
            chosen.append(piece)
    if not chosen:
        raise ValueError("no pieces of the plate inside %s" % (box,))
    return trimesh.util.concatenate(chosen)


def keep_side(mesh, origin, normal):
    """The part of the mesh on the side of the plane `normal` points to. Triangles crossing the
    plane are clipped; the cut is left open (it faces the ground or a neighbour)."""
    vertices, faces = trimesh.intersections.slice_faces_plane(
        mesh.vertices, mesh.faces, plane_normal=np.asarray(normal, dtype=float),
        plane_origin=np.asarray(origin, dtype=float))[:2]
    out = trimesh.Trimesh(vertices, faces, process=True)
    out.remove_unreferenced_vertices()
    return out


def cut_below(mesh, height):
    """Removes everything lower than `height` tiles above the mesh's lowest point."""
    return keep_side(mesh, [0, mesh.bounds[0][1] + height, 0], [0, 1, 0])


def snapped(mesh, cell):
    """Vertices snapped to a grid of `cell` tiles, with the triangles that collapse removed."""
    out = trimesh.Trimesh(np.round(mesh.vertices / cell) * cell, mesh.faces, process=True)
    out.update_faces(out.nondegenerate_faces())
    out.update_faces(out.unique_faces())
    out.remove_unreferenced_vertices()
    return out


# Print files are full of slivers and near-duplicate vertices that stop the quadric simplifier
# early. Snapping to a fine grid first lets it continue; 0.004 tiles is 0.1 mm.
SNAP_CELLS = (0.004, 0.006, 0.008, 0.012, 0.016, 0.024)


def decimate(mesh, faces):
    faces = int(faces)
    if len(mesh.faces) <= faces:
        return mesh
    best = mesh
    for cell in (None,) + SNAP_CELLS:
        source = mesh if cell is None else snapped(mesh, cell)
        if len(source.faces) <= faces:
            return source
        try:
            out = source.simplify_quadric_decimation(face_count=faces, aggression=8)
        except Exception:  # very small or odd meshes: try the next grid
            continue
        if len(out.faces) and len(out.faces) < len(best.faces):
            best = out
        if len(best.faces) <= faces * 1.05:
            break
    return best


BLENDER = os.environ.get("BLENDER") or shutil.which("blender") or next(
    (p for p in (r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe",) if os.path.exists(p)), None)


def decimate_all(items):
    """[(mesh, target faces)] -> meshes. With Blender (BLENDER or on PATH), its collapse decimator
    does them all in one run: on dense print files it keeps panels, gears and pipes recognisable
    where the quadric simplifier leaves shards. Without Blender, decimate() each."""
    todo = [i for i, (m, n) in enumerate(items) if len(m.faces) > n]
    out = [m for m, _ in items]
    if not todo:
        return out
    if BLENDER:
        with tempfile.TemporaryDirectory() as tmp:
            src, dst = os.path.join(tmp, "in.npz"), os.path.join(tmp, "out.npz")
            arrays = {}
            for k, i in enumerate(todo):
                m, n = items[i]
                arrays.update({"v%d" % k: m.vertices, "f%d" % k: m.faces, "n%d" % k: np.array(int(n))})
            np.savez(src, **arrays)
            run = subprocess.run([BLENDER, "--background", "--factory-startup", "--python",
                                  os.path.join(HERE, "wube_blender_decimate.py"), "--", src, dst],
                                 capture_output=True, text=True)
            if run.returncode == 0 and os.path.exists(dst):
                with np.load(dst) as res:
                    for k, i in enumerate(todo):
                        mesh = trimesh.Trimesh(res["v%d" % k], res["f%d" % k], process=True)
                        mesh.update_faces(mesh.nondegenerate_faces())
                        out[i] = mesh
                return out
            print("Blender decimation failed, using the plain-Python one: " + (run.stderr or run.stdout)[-300:])
    for i in todo:
        out[i] = decimate(*items[i])
    return out


def shaded(mesh):
    """Smooth normals within CREASE_DEGREES, hard edges beyond: split vertices where needed."""
    return trimesh.graph.smooth_shade(mesh, angle=np.radians(CREASE_DEGREES))


# ---------------------------------------------------------------------------------------------
# glTF writer: one node, one mesh, one primitive per material. Positions, normals, indices, and
# the weathering data the client's material reads (bake.py, client/assets/models/README.md).

def baked_attributes(groups):
    """Per group, per vertex: COLOR_0 (1, 1, 1, ao), TEXCOORD_0 (planar, x and z),
    TEXCOORD_1 (edge, part), TEXCOORD_2/3 (sprite projector visibility N, E / S, W). Baked over
    the whole model at once, so parts occlude each other."""
    tris = np.concatenate([m.vertices[m.faces] for _, m in groups])
    nrms = np.concatenate([m.vertex_normals[m.faces] for _, m in groups])
    # Each triangle's width (area over longest side): big flat ones don't count as worn edges.
    sides = np.linalg.norm(tris - np.roll(tris, 1, axis=1), axis=2).max(axis=1)
    area = 0.5 * np.linalg.norm(np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0]), axis=1)
    ao, edge, part, vis = bake.bake(tris, nrms, up=1, width=area / np.maximum(sides, 1e-9),
                                    views=bake.factorio_views(up=1))
    out, t0 = [], 0
    for _, mesh in groups:
        n = len(mesh.faces)
        count = np.zeros(len(mesh.vertices))
        np.add.at(count, mesh.faces.reshape(-1), 1.0)
        count = np.maximum(count, 1.0)[:, None]

        def per_vertex(values):  # (n, 3, k) corner values -> (V, k) vertex means
            acc = np.zeros((len(mesh.vertices), values.shape[2]))
            np.add.at(acc, mesh.faces.reshape(-1), values.reshape(-1, values.shape[2]))
            return acc / count
        a = per_vertex(ao[t0:t0 + n, :, None])
        e = per_vertex(edge[t0:t0 + n, :, None])
        pt = per_vertex(np.repeat(part[t0:t0 + n, None, None], 3, axis=1))
        v = per_vertex(vis[t0:t0 + n])
        t0 += n
        ones = np.ones((len(mesh.vertices), 3))
        out.append({"COLOR_0": np.hstack([ones, a]), "TEXCOORD_0": mesh.vertices[:, [0, 2]],
                    "TEXCOORD_1": np.hstack([e, pt]), "TEXCOORD_2": v[:, 0:2], "TEXCOORD_3": v[:, 2:4]})
    return out


def write_glb(path, groups, palette, alpha, copyright_text, nodes=None, uv0=None):
    """groups: list of (material name, trimesh.Trimesh with vertex normals). `nodes`, parallel
    to groups, says which node each goes in: (name, pivot), "body" or an `anim_*` part whose
    origin is its pivot (the point it turns about). Default: all in "body". `uv0`: per group,
    (V, 2) values for TEXCOORD_0 instead of the planar UVs (a rigged creature's limbs, wube_rig.py)."""
    nodes = nodes or [("body", None)] * len(groups)
    bin_chunk = bytearray()
    buffer_views, accessors, primitives, materials = [], [], [], []

    def add_view(data, target):
        while len(bin_chunk) % 4:
            bin_chunk.append(0)
        buffer_views.append({"buffer": 0, "byteOffset": len(bin_chunk), "byteLength": len(data), "target": target})
        bin_chunk.extend(data)
        return len(buffer_views) - 1

    extra = baked_attributes(groups)
    if uv0 is not None:
        for attributes, values in zip(extra, uv0):
            attributes["TEXCOORD_0"] = values
    node_prims = {}  # node name -> (pivot, [primitive index])
    for (material, mesh), attributes, (node, pivot) in zip(groups, extra, nodes):
        origin = np.zeros(3) if pivot is None else np.asarray(pivot, dtype=float)
        node_prims.setdefault(node, (origin, []))[1].append(len(primitives))
        pos = np.ascontiguousarray(mesh.vertices - origin, dtype=np.float32)
        nrm = np.ascontiguousarray(mesh.vertex_normals, dtype=np.float32)
        idx = np.ascontiguousarray(mesh.faces.reshape(-1))
        idx = idx.astype(np.uint16 if len(pos) < 65536 else np.uint32)
        pv = add_view(pos.tobytes(), 34962)
        accessors.append({"bufferView": pv, "componentType": 5126, "count": len(pos), "type": "VEC3",
                          "min": pos.min(axis=0).tolist(), "max": pos.max(axis=0).tolist()})
        pa = len(accessors) - 1
        nv = add_view(nrm.tobytes(), 34962)
        accessors.append({"bufferView": nv, "componentType": 5126, "count": len(nrm), "type": "VEC3"})
        na = len(accessors) - 1
        iv = add_view(idx.tobytes(), 34963)
        accessors.append({"bufferView": iv, "componentType": 5123 if idx.dtype == np.uint16 else 5125,
                          "count": len(idx), "type": "SCALAR"})
        ia = len(accessors) - 1
        hex_colour, rough, metal, emit, strength = palette[material]
        mat = {"name": material, "pbrMetallicRoughness": {
            "baseColorFactor": srgb_to_linear(hex_colour) + [alpha.get(material, 1.0)],
            "metallicFactor": metal, "roughnessFactor": rough}}
        if emit:
            mat["emissiveFactor"] = srgb_to_linear(emit)
            if strength != 1.0:
                mat.setdefault("extensions", {})["KHR_materials_emissive_strength"] = {"emissiveStrength": strength}
        if material in alpha:
            mat["alphaMode"] = "BLEND"
        materials.append(mat)
        attrs = {"POSITION": pa, "NORMAL": na}
        for key, values in attributes.items():
            data = np.ascontiguousarray(values, dtype=np.float32)
            view = add_view(data.tobytes(), 34962)
            accessors.append({"bufferView": view, "componentType": 5126, "count": len(data),
                              "type": "VEC%d" % data.shape[1]})
            attrs[key] = len(accessors) - 1
        primitives.append({"attributes": attrs, "indices": ia, "material": len(materials) - 1, "mode": 4})

    gl_nodes, gl_meshes = [], []
    for node, (origin, prims) in node_prims.items():
        entry = {"name": node, "mesh": len(gl_meshes)}
        if np.any(origin):
            entry["translation"] = [float(v) for v in origin]
        gl_nodes.append(entry)
        gl_meshes.append({"name": node, "primitives": [primitives[i] for i in prims]})
    doc = {
        "asset": {"version": "2.0", "generator": GENERATOR, "copyright": copyright_text},
        "scene": 0, "scenes": [{"nodes": list(range(len(gl_nodes)))}],
        "nodes": gl_nodes,
        "meshes": gl_meshes,
        "materials": materials, "accessors": accessors, "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(bin_chunk)}],
    }
    if any("extensions" in m for m in materials):
        doc["extensionsUsed"] = ["KHR_materials_emissive_strength"]
    while len(bin_chunk) % 4:
        bin_chunk.append(0)
    doc["buffers"][0]["byteLength"] = len(bin_chunk)
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    out = struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(js) + 8 + len(bin_chunk))
    out += struct.pack("<I4s", len(js), b"JSON") + js
    out += struct.pack("<I4s", len(bin_chunk), b"BIN\0") + bytes(bin_chunk)
    with open(path, "wb") as f:
        f.write(out)


# ---------------------------------------------------------------------------------------------
# Building a recipe

def trim(mesh, half_x=None, half_z=None):
    """Cuts the mesh to |x| <= half_x and |z| <= half_z (tiles). The cuts are left open: they face
    the ground or a neighbouring entity."""
    for axis, half in ((0, half_x), (2, half_z)):
        if half is None:
            continue
        for sign in (1, -1):
            normal = [0, 0, 0]
            normal[axis] = -sign
            origin = [0, 0, 0]
            origin[axis] = sign * half
            mesh = keep_side(mesh, origin, normal)
    return mesh


def scale_matrix(factor):
    f = np.broadcast_to(np.asarray(factor, dtype=float), (3,))
    m = np.eye(4)
    m[0, 0], m[1, 1], m[2, 2] = f
    return m


def split_paint(material, mesh, paint, node="body", bounds=None):
    """Splits a part into (material, mesh, node) pieces by face: `paint` is a list of (material,
    rule) or (material, rule, node), where rule(centroids, normals, lo, hi) picks faces (bool per
    face) from what's left, first rule first; lo and hi are the part's bounds (`bounds`, else the
    mesh's), and `node` moves those faces into an `anim_*` part of their own (a logistic chest's
    hatch). A fourth element (material, dy) also leaves a copy of them behind, `dy` tiles lower, in
    that material (the dark well under the hatch, seen when it opens). The rest keeps `material` and
    `node`. build_parts also uses it to cut a part into nodes the same way (`nodes`)."""
    if not paint:
        return [(material, mesh, node)]
    out, left = [], np.ones(len(mesh.faces), dtype=bool)
    centroids, normals = mesh.triangles_center, mesh.face_normals
    lo, hi = mesh.bounds if bounds is None else bounds
    for entry in paint:
        mat, rule = entry[0], entry[1]
        pick = left & np.asarray(rule(centroids, normals, lo, hi), dtype=bool)
        if pick.any():
            out.append((mat, mesh.submesh([np.nonzero(pick)[0]], append=True), entry[2] if len(entry) > 2 else node))
            if len(entry) > 3:
                under = mesh.submesh([np.nonzero(pick)[0]], append=True)
                translate(under, [0, entry[3][1], 0])
                out.append((entry[3][0], under, node))
        left &= ~pick
    if left.any():
        out.insert(0, (material, mesh.submesh([np.nonzero(left)[0]], append=True), node))
    return out


def build_parts(recipe, sources):
    """The recipe's parts as (material, mesh), assembled in model space.

    Each part, in order: pick pieces off a print plate, drop faces (`drop`), cut away pegs, mirror,
    scale, tilt to stand it up, turn it (part `yaw`, else the recipe's), centre its footprint on
    the origin with its lowest point on the ground (unless `raw_frame`: kept where the print file
    has it), stack it on an earlier part (`on`, sinking `inset` tiles into it), nudge it by
    `offset` tiles, then `trim` it to the tile. Last, `paint` splits it into materials by face.
    `with_part`: an earlier part whose print file this one shares a frame with (the character's
    backpack sits by its body in the files): it gets exactly that part's turns and shift, then
    `spin` degrees about that part's upright axis, and `resize` scales it about the middle of its
    face towards the body (its north side).
    `nodes`: (node, rule) pairs, rules as `paint`'s, that cut faces out of the part into other
    nodes before it is painted: moving parts printed fused to the body (the assembler's gears).
    `refine`: longest edge (tiles) the part's triangles are split to first, so `paint` and `nodes`
    rules pick by place rather than by the centroids of long slivers.
    """
    placed = []
    frames = []  # per part: (rotation matrix, centre) applied to the file's coordinates
    for part in recipe["parts"]:
        if "box" in part:
            # A plain block (x0, y0, z0, x1, y1, z1 tiles, in the frame the parts are assembled
            # in, turned by the recipe's yaw): fills a hole the print leaves open (the inserter
            # platform's arm slot, which the sprite draws closed).
            x0, y0, z0, x1, y1, z1 = part["box"]
            mesh = trimesh.creation.box(extents=(x1 - x0, y1 - y0, z1 - z0))
            translate(mesh, [(x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2])
            mesh.apply_transform(yaw_matrix(part.get("yaw", recipe.get("yaw", 0))))
            frames.append((np.eye(4), np.zeros(3)))
            placed.append((part["material"], mesh, part.get("node", "body"), part.get("paint"), part.get("nodes")))
            continue
        mesh = sources.load(part["file"])
        if "pick" in part:
            mesh = pick_components(mesh, part["pick"])
        if "plate_yaw" in part:
            mesh.apply_transform(yaw_matrix(part["plate_yaw"]))
        if "pick_box" in part:
            mesh = pick_in_box(mesh, part["pick_box"])
        if "drop" in part:  # faces of print-only bits, by rule(centroids, normals, lo, hi)
            keep = ~np.asarray(part["drop"](mesh.triangles_center, mesh.face_normals, *mesh.bounds), dtype=bool)
            mesh = mesh.submesh([np.nonzero(keep)[0]], append=True)
        if "pivot" in part:
            # A moving part: the print point (x, y mm on the plate) it turns about goes to the
            # origin, and the part isn't centred (the client places it by that point).
            px, py = part["pivot"]
            translate(mesh, [-px / MM_PER_TILE, 0, py / MM_PER_TILE])
        if "cut_below" in part:
            mesh = cut_below(mesh, part["cut_below"] / MM_PER_TILE)
        if "mirror" in part:
            m = np.eye(4)
            m["xyz".index(part["mirror"]), "xyz".index(part["mirror"])] = -1
            mesh.apply_transform(m)
            mesh.invert()
        if "scale" in part:
            mesh.apply_transform(scale_matrix(part["scale"]))
        if "with_part" in part:
            rotation, centre = frames[part["with_part"]]
            mesh.apply_transform(rotation)
            translate(mesh, -centre)
            if "spin" in part:  # laid out turned about that part's upright axis (the character's backpack)
                mesh.apply_transform(yaw_matrix(part["spin"]))
            frames.append((rotation, centre))
            if "offset" in part:
                translate(mesh, part["offset"])
            if "resize" in part:  # shrunk about the middle of its face against the other part
                lo, hi = mesh.bounds
                at = np.array([(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, lo[2]])
                translate(mesh, -at)
                mesh.apply_transform(scale_matrix(part["resize"]))
                translate(mesh, at)
            placed.append((part["material"], mesh, part.get("node", "body"), part.get("paint"), part.get("nodes")))
            continue
        rotation = np.eye(4)
        for axis, degrees in part.get("tilt", []):
            rotation = tilt_matrix(axis, degrees) @ rotation
        rotation = yaw_matrix(part.get("yaw", recipe.get("yaw", 0))) @ rotation
        mesh.apply_transform(rotation)
        centre = footprint_centre(mesh)
        if part.get("raw_frame") or "pivot" in part:
            centre[0] = centre[2] = 0.0
        translate(mesh, -centre)
        frames.append((rotation, centre))
        if "on" in part:
            base = placed[part["on"]][1]
            translate(mesh, [0, base.bounds[1][1] - part.get("inset", 0.0), 0])
        if "offset" in part:
            translate(mesh, part["offset"])
        if "trim" in part:
            mesh = trim(mesh, *part["trim"])
        if "warp" in part:
            # Vertices (N, 3 tiles, placed) -> new vertices: reshapes a print where its sprite
            # differs (the inserter hand's forearm, narrower in the print).
            mesh.vertices = part["warp"](mesh.vertices.copy())
        placed.append((part["material"], mesh, part.get("node", "body"), part.get("paint"), part.get("nodes")))
    out = []
    for (material, mesh, node, paint, nodes), part in zip(placed, recipe["parts"]):
        bounds = mesh.bounds
        if "refine" in part:
            # Prints triangulate flat faces with long slivers: one picked by its centroid can
            # reach far outside the area a rule means. Split edges to at most `refine` tiles.
            v, f = trimesh.remesh.subdivide_to_size(mesh.vertices, mesh.faces, part["refine"], max_iter=12)
            mesh = trimesh.Trimesh(v, f, process=False)
        for nd, cut, _ in split_paint(node, mesh, nodes):
            out.extend(split_paint(material, cut, paint, nd, bounds))
    return out


def assemble(name, recipe, sources):
    """The whole model as (material, mesh) pieces, before decimation: parts assembled, on the
    ground, centred (or by `centre_below`), then the model-level fixes for Factorio's size and
    shape: `untaper` (widens the top by that share of the base's width per model height, for
    prints drafted narrower at the top than the sprite), `scale` (number or (x, y, z), about the
    origin on the ground), `shift` (x, z tiles: where the sprite has the entity's position) and
    `roll` (degrees about the north-south axis, before the rest)."""
    parts = build_parts(recipe, sources)
    if "roll" in recipe:
        # A pose of another model laid over (a corpse on its side): turned about the north-south
        # axis by that many degrees, then about the up axis by `roll_yaw`.
        for _material, mesh, _node in parts:
            mesh.apply_transform(tilt_matrix("z", recipe["roll"]))
            mesh.apply_transform(yaw_matrix(recipe.get("roll_yaw", 0)))
    # The model's frame is the entity's tile frame: parts are already centred on it. Make sure
    # the lowest point is on the ground.
    lowest = min(m.bounds[0][1] for _, m, _ in parts)
    for _material, mesh, _node in parts:
        translate(mesh, [0, -lowest, 0])
    if "scale" in recipe:
        # Prints aren't all at Factorio's size (creatures, the character), and some are stylised
        # (chests, belts): a number or (x, y, z), fitted to the sprite, about the origin.
        for _material, mesh, _node in parts:
            mesh.apply_transform(scale_matrix(recipe["scale"]))
    if "crater" in recipe:
        # A collapsed dome (a dead spawner): within `radius` tiles of the middle, heights sink to
        # `floor` of what they were, easing back to full height at the rim.
        radius, floor = recipe["crater"]
        for _material, mesh, _node in parts:
            v = mesh.vertices.copy()
            t = np.clip((np.hypot(v[:, 0], v[:, 2]) / radius - 0.3) / 0.7, 0.0, 1.0)
            v[:, 1] *= floor + (1.0 - floor) * t * t * (3 - 2 * t)
            mesh.vertices = v
    if "centre_below" in recipe:
        # Centre on what stands on the ground (a pole's post, not its crossarm).
        low = np.vstack([m.vertices[m.vertices[:, 1] <= recipe["centre_below"]] for _, m, _ in parts])
        lo, hi = low.min(axis=0), low.max(axis=0)
        for _material, mesh, _node in parts:
            translate(mesh, [-(lo[0] + hi[0]) / 2, 0, -(lo[2] + hi[2]) / 2])
    if recipe.get("untaper"):
        height = max(m.bounds[1][1] for _, m, _ in parts) or 1.0
        for _material, mesh, _node in parts:
            v = mesh.vertices.copy()
            grow = 1.0 + recipe["untaper"] * v[:, 1] / height
            v[:, 0] *= grow
            v[:, 2] *= grow
            mesh.vertices = v
    if "shift" in recipe:
        for _material, mesh, _node in parts:
            translate(mesh, [recipe["shift"][0], 0, recipe["shift"][1]])
    return parts


def build(name, recipe, sources, palette, alpha, out_dir):
    if "posed" in recipe:
        # Another pose of a rigged creature, from its built model (creature_pose.py).
        import creature_pose
        return creature_pose.write_posed(name, creature_pose.load_poses()[name], palette, alpha,
                                         wube_recipes.COPYRIGHT, out_dir)
    if "built_by" in recipe:
        # Not from a print after all: built from Factorio's sprites by its own script.
        module = __import__(recipe["built_by"])
        import creature_score
        path = module.build(creature_score.data_raw(), out_dir)
        return path, 0
    parts = assemble(name, recipe, sources)

    # One primitive per material and node; the triangle budget is shared by surface area.
    by_material = {}
    for material, mesh, node in parts:
        by_material.setdefault((material, node), []).append(mesh)
    merged = [(k, trimesh.util.concatenate(meshes)) for k, meshes in by_material.items()]
    budget = recipe.get("budget") or specs.SPECS.get(name, {}).get("budget", specs.LOGISTICS)
    if "skin" in recipe:
        # The character: a small skeleton the client poses (wube_rig.py, skinned rigs).
        import wube_rig
        path = os.path.join(out_dir, name + ".glb")
        tris = wube_rig.build_skinned(name, recipe, [(m, mesh) for (m, _node), mesh in merged], budget, path, palette, alpha, wube_recipes.COPYRIGHT)
        return path, tris
    if "rig" in recipe:
        # Creatures: limbs become their own nodes for the client to animate (wube_rig.py).
        import wube_rig
        path = os.path.join(out_dir, name + ".glb")
        tris = wube_rig.build_rigged(name, recipe, [(m, mesh) for (m, _node), mesh in merged], budget, path, palette, alpha, wube_recipes.COPYRIGHT)
        return path, tris
    # Shared half by surface area, half by the print's own triangle count, so small but detailed
    # parts (a pole's crossarm, a chest's coloured panels) keep their shape.
    total_area = sum(mesh.area for _, mesh in merged) or 1.0
    total_faces = sum(len(mesh.faces) for _, mesh in merged) or 1
    targets = [max(12, int(budget * 0.97 * (0.5 * mesh.area / total_area + 0.5 * len(mesh.faces) / total_faces)))
               for _, mesh in merged]
    # Small moving parts cut out of a print (`node_budgets`: node -> triangles) keep their teeth.
    floors = recipe.get("node_budgets", {})
    targets = [max(n, min(len(mesh.faces), floors.get(node, 0))) for ((_, node), mesh), n in zip(merged, targets)]
    meshes = decimate_all([(mesh, n) for (_, mesh), n in zip(merged, targets)])
    groups, nodes = [], []
    pivots = recipe.get("pivots", {})
    for ((material, node), _), mesh in zip(merged, meshes):
        groups.append((material, shaded(mesh)))
        pivot = None
        if node != "body":
            if node in pivots:
                pivot = pivots[node]
            else:  # the top centre of everything in the node: a spinning part's axis
                lo = np.min([m.bounds[0] for (_, nd), m in merged if nd == node], axis=0)
                hi = np.max([m.bounds[1] for (_, nd), m in merged if nd == node], axis=0)
                pivot = ((lo[0] + hi[0]) / 2, hi[1], (lo[2] + hi[2]) / 2)
        nodes.append((node, pivot))
    path = os.path.join(out_dir, name + ".glb")
    write_glb(path, groups, palette, alpha, wube_recipes.COPYRIGHT, nodes)
    tris = sum(len(m.faces) for _, m in groups)
    return path, tris


def write_credits(models_dir):
    """Lists every model in the folder that this script made (by its glTF generator tag)."""
    rows = []
    for fname in sorted(os.listdir(models_dir)):
        name = fname[:-4]
        if not fname.endswith(".glb") or name not in wube_recipes.RECIPES:
            continue
        with open(os.path.join(models_dir, fname), "rb") as f:
            data = f.read()
        size = struct.unpack_from("<I", data, 12)[0]
        if json.loads(data[20:20 + size])["asset"].get("generator") != GENERATOR:
            continue  # a procedural model with the same name
        recipe = wube_recipes.RECIPES[name]
        # A posed model is its source print in another pose; one built from the sprites isn't Wube's.
        recipe = wube_recipes.RECIPES[recipe["posed"]] if "posed" in recipe else recipe
        if "built_by" in recipe:
            continue
        files = sorted({p["file"] for p in recipe["parts"] if "file" in p})
        rows.append("| `%s` | %s |" % (fname, ", ".join("`%s`" % f for f in files)))
    lines = [
        "# Model credits",
        "",
        "These models are built from Wube Software's official 3D-printable Factorio models (Friday",
        "Facts #447, https://www.printables.com/@WubeSoftware/models), which Printables lists under",
        "CC BY-NC. They were converted (scaled, assembled, decimated and coloured) by",
        "`tools/models/wube.py`. Not for commercial use.",
        "",
        "| Model | Wube source files |",
        "|---|---|",
    ] + rows + [
        "",
        "Every other model in this folder is made procedurally by the scripts in `tools/models/`.",
        "",
    ]
    with open(os.path.join(models_dir, "CREDITS.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    return len(rows)


# ---------------------------------------------------------------------------------------------

def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("names", nargs="*", help="models to build (default: all with sources present)")
    parser.add_argument("--source", default=SOURCE_DIR, help="where the downloaded zips or STLs are")
    parser.add_argument("--out", default=MODELS_DIR, help="where to write .glb files")
    parser.add_argument("--list", action="store_true", help="list recipes and the source files found")
    parser.add_argument("--raw", metavar="DIR", help="convert every source STL on its own into DIR")
    args = parser.parse_args(argv)

    sources = Sources(args.source)
    palette, alpha = load_palette()
    palette.update(wube_recipes.EXTRA_MATERIALS)
    recipes = wube_recipes.RECIPES

    if args.raw:
        os.makedirs(args.raw, exist_ok=True)
        for key, (label, _reader) in sorted(sources.files.items()):
            mesh = sources.load(key)
            translate(mesh, -footprint_centre(mesh))
            out = os.path.join(args.raw, re.sub(r"[^a-z0-9]+", "-", re.split(r"[\\/!]", label)[-1].lower()[:-4]).strip("-") + ".glb")
            write_glb(out, [("steel_light", shaded(decimate(mesh, 20000)))], palette, alpha, wube_recipes.COPYRIGHT)
            print("%-45s %6d tris  %s" % (os.path.basename(out), len(mesh.faces), label))
        return 0

    if args.list:
        print("%d source STLs under %s" % (len(sources.files), args.source))
        for name, recipe in recipes.items():
            missing = [p["file"] for p in recipe["parts"] if "file" in p and not sources.has(p["file"])]
            state = "ready" if not missing else "missing " + ", ".join(missing)
            print("%-30s %s" % (name, state))
        return 0

    names = args.names or list(recipes)
    unknown = [n for n in names if n not in recipes]
    if unknown:
        print("no recipe for: " + ", ".join(unknown))
        return 1
    built, skipped = {}, []
    for name in names:
        recipe = recipes[name]
        missing = [p["file"] for p in recipe["parts"] if "file" in p and not sources.has(p["file"])]
        if missing:
            skipped.append((name, missing))
            continue
        path, tris = build(name, recipe, sources, palette, alpha, args.out)
        built[name] = path
        print("built %-30s %6d tris" % (name, tris))
    for name, missing in skipped:
        print("skip  %-30s missing %s" % (name, ", ".join(missing)))
    if built:
        print("credits: %d converted models listed in %s" % (write_credits(args.out), os.path.join(args.out, "CREDITS.md")))
        # Each part's colour from Factorio's sprite (the client's default look); needs the install.
        if os.path.abspath(args.out) == os.path.abspath(MODELS_DIR):
            try:
                import part_colors
                part_colors.main(list(built))
            except Exception as e:  # no Factorio install, no scipy: say so, the models still work
                print("part colours not sampled (%s): run tools/models/part_colors.py %s" % (e, " ".join(built)))
    if not built and not skipped:
        print("nothing to build")
    print("%d built, %d skipped (source files not found under %s)" % (len(built), len(skipped), args.source))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
