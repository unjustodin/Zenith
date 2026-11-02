#!/usr/bin/env python3
"""Turntable: rebuild a 3D shape from Factorio's rotation sprite sheets (an experiment).

    python tools/models/turntable.py hull    car tank gun-turret [--res 0.02] [--fit]
    python tools/models/turntable.py compare car tank gun-turret

A vehicle's or turret's 64 rotation frames are renders of one model from a fixed camera at
evenly spaced angles, like a photo turntable. Each frame's alpha is a silhouette; carving a voxel
grid with all of them gives the visual hull, which is meshed (marching cubes), smoothed and
decimated to the triangle budget. Its colours are sampled back from the frames where each face
is seen, then clustered into a few parts, each with one colour (as part_colors.py colours our
models), not a pasted texture.

Each separately drawn layer is its own part: the car's and tank's bodies and turrets, the gun
turret's head (its base is one picture, which can't be carved). Shadows are never used.

Camera (the same one sprite_projection.py and the client use): orthographic, x across at 64 px a
tile (HR sheets at scale 0.5), and up the screen `A * height - B * south` with A = cos 48 deg.
Every frame is seen from the same elevation, so silhouettes can't tell a tall model seen steeply
from a short one seen flatly: A is a gauge and stays the client's; B (how long the ground's
north-south distances are drawn) is fitted with `--fit` by how well the hull reprojects.

Everything this writes is derived from Factorio's sprites and goes to the git-ignored
art-src/turntable/ (meshes in out/, pictures beside them); nothing is written into the repo.
Needs the venv: numpy, scipy, pillow, trimesh, scikit-image, fast-simplification.
"""

import argparse
import json
import math
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import sprite_projection as sp  # noqa: E402  (frame numbers only)

FACTORIO = os.environ.get("FACTORIO", r"C:\Program Files (x86)\Steam\steamapps\common\Factorio")
OUT = os.path.join(REPO, "art-src", "turntable")
MODELS = os.path.join(REPO, "client", "assets", "models")
PPT = 64.0                      # pixels per tile of an HR frame at scale 0.5
ELEV = math.radians(48.0)
A_UP = math.cos(ELEV)           # height -> up the screen (gauge, the client's)
B_CLIENT = math.sin(ELEV)       # what the client uses for vehicles (stretch 1)
CANVAS = 640
G = "base/graphics/entity/"


# ---------------------------------------------------------------- frames

def _gun_turret_head(i):
    return [sp.layer(G + "gun-turret/gun-turret-shooting-%d.png" % (i // 16 + 1), 132, 130, (0, -27.5),
                     line=2, index=(i % 16) * 2)]


def _from_entry(name, which):
    cells = sp.BUILDINGS[name]["cells"]
    return lambda i: [cells[i][which]]


# entity -> {part: (frames(i) -> [layer], node-name prefix in our .glb, or None for "the rest")}
ENTITIES = {
    "car": {"body": (_from_entry("car", 0), None), "turret": (_from_entry("car", 1), "anim_turret")},
    "tank": {"body": (_from_entry("tank", 0), None), "turret": (_from_entry("tank", 1), "anim_turret")},
    "gun-turret": {"head": (_gun_turret_head, "anim_turret")},
    "spidertron": {"body": (_from_entry("spidertron", 1), None)},
}
ANCHOR = 0.3   # the entity's position, tiles above the ground (sprite_projection's BUILDING_ANCHOR)
N_DIR = 64

_sheets = {}


def sheet(path):
    if path not in _sheets:
        _sheets[path] = np.asarray(Image.open(os.path.join(FACTORIO, "data", path)).convert("RGBA"))
    return _sheets[path]


def frame_canvas(layers):
    """The layers composited on a CANVAS x CANVAS image at 64 px a tile, the entity's position at
    its centre. Returns float RGBA in 0..1."""
    out = np.zeros((CANVAS, CANVAS, 4), np.float32)
    for ly in layers:
        img = sheet(ly["file"])
        w, h = ly["frame"]
        line = max(1, ly.get("line") or 1)
        idx = ly.get("index", 0)
        x0, y0 = (idx % line) * w, (idx // line) * h
        crop = img[y0:y0 + h, x0:x0 + w]
        k = PPT / (32.0 / ly.get("scale", 0.5))
        if abs(k - 1) > 1e-6:
            crop = np.asarray(Image.fromarray(crop).resize((max(1, round(w * k)), max(1, round(h * k))),
                                                           Image.LANCZOS))
        crop = crop.astype(np.float32) / 255.0
        ch, cw = crop.shape[:2]
        cx = CANVAS / 2 + ly["shift"][0] / 32.0 * PPT - cw / 2
        cy = CANVAS / 2 + ly["shift"][1] / 32.0 * PPT - ch / 2
        ix, iy = int(round(cx)), int(round(cy))
        a = crop[..., 3:4]
        region = out[iy:iy + ch, ix:ix + cw]
        region[..., :3] = crop[..., :3] * a + region[..., :3] * (1 - a)   # sheets are not premultiplied
        region[..., 3:4] = a + region[..., 3:4] * (1 - a)
    return out


def part_frames(entity, part):
    fn = ENTITIES[entity][part][0]
    return [frame_canvas(fn(i)) for i in range(N_DIR)]


# ---------------------------------------------------------------- camera

class Camera:
    """Orthographic view of the model turned by `phi` (clockwise from north, as Factorio's
    orientation). `up` = a * (height - anchor) - b * south; `close` orders surfaces towards the
    camera. Factorio's view: a = cos 48, b fitted; a true camera at elevation e: a = cos e, b = sin e."""

    def __init__(self, a=A_UP, b=B_CLIENT, elev=ELEV, anchor=ANCHOR, hand=1, ppt=PPT, size=CANVAS):
        self.a, self.b, self.elev, self.anchor, self.hand, self.ppt, self.size = a, b, elev, anchor, hand, ppt, size

    @staticmethod
    def true(elev_deg, **kw):
        e = math.radians(elev_deg)
        return Camera(a=math.cos(e), b=math.sin(e), elev=e, **kw)

    def project(self, p, phi):
        """p: (..., 3) glTF model space (x east, y up, z south) -> (u px, v px down, closeness)."""
        phi = phi * self.hand
        c, s = math.cos(phi), math.sin(phi)
        x, y, z = p[..., 0], p[..., 1], p[..., 2]
        wx, wz = x * c - z * s, x * s + z * c
        u = self.size / 2 + self.ppt * wx
        v = self.size / 2 - self.ppt * (self.a * (y - self.anchor) - self.b * wz)
        close = y * math.sin(self.elev) + wz * math.cos(self.elev)
        return u, v, close


def phi_of(i):
    return 2 * math.pi * i / N_DIR


# ---------------------------------------------------------------- carving

def masks_of(frames, dilate=1):
    out = []
    for f in frames:
        m = f[..., 3] > 0.5
        if dilate:
            m = ndimage.binary_dilation(m, iterations=dilate)
        out.append(m)
    return out


def carve(masks, cam, res, tol=0, bounds=None):
    """Voxel centres (N, 3) inside every silhouette (or all but `tol` of them)."""
    if bounds is None:
        r = 0.0
        top = 0.0
        for m in masks:
            ys, xs = np.nonzero(m)
            r = max(r, np.abs(xs - cam.size / 2).max() / cam.ppt, np.abs(ys - cam.size / 2).max() / cam.ppt)
            top = max(top, (cam.size / 2 - ys.min()) / cam.ppt)
        r = min(r + 0.1, cam.size / 2 / cam.ppt)
        bounds = ((-r, r), (0.0, cam.anchor + (top + cam.b * r) / cam.a + 0.1), (-r, r))
    axes = [np.arange(lo + res / 2, hi, res, dtype=np.float32) for lo, hi in bounds]
    gx, gy, gz = np.meshgrid(*axes, indexing="ij")
    pts = np.stack([gx.ravel(), gy.ravel(), gz.ravel()], axis=1)
    ijk = np.stack(np.meshgrid(*[np.arange(len(a)) for a in axes], indexing="ij"), axis=-1).reshape(-1, 3)
    miss = np.zeros(len(pts), np.int16)
    for i, m in enumerate(masks):
        u, v, _ = cam.project(pts, phi_of(i))
        ui, vi = np.round(u).astype(np.int32), np.round(v).astype(np.int32)
        ok = (ui >= 0) & (ui < m.shape[1]) & (vi >= 0) & (vi < m.shape[0])
        inside = np.zeros(len(pts), bool)
        inside[ok] = m[vi[ok], ui[ok]]
        miss += ~inside
        keep = miss <= tol
        pts, ijk, miss = pts[keep], ijk[keep], miss[keep]
    shape = tuple(len(a) for a in axes)
    origin = np.array([a[0] for a in axes])
    return pts, ijk, shape, origin


def splat_iou(pts, masks, cam, res, step=4):
    """Mean IoU of the voxels' reprojection against the silhouettes (every `step`-th view)."""
    rad = max(1, int(math.ceil(res * cam.ppt / 2)))
    st = ndimage.generate_binary_structure(2, 1)
    out = []
    for i in range(0, len(masks), step):
        u, v, _ = cam.project(pts, phi_of(i))
        img = np.zeros_like(masks[i])
        ui, vi = np.clip(np.round(u).astype(int), 0, cam.size - 1), np.clip(np.round(v).astype(int), 0, cam.size - 1)
        img[vi, ui] = True
        img = ndimage.binary_dilation(img, st, iterations=rad)
        out.append((img & masks[i]).sum() / max(1, (img | masks[i]).sum()))
    return float(np.mean(out))


def fit_camera(masks, res=0.05):
    best = None
    for hand in (1, -1):
        for b in np.arange(0.55, 1.36, 0.05):
            cam = Camera(b=float(b), hand=hand)
            pts, *_ = carve(masks, cam, res)
            if len(pts) == 0:
                continue
            score = splat_iou(pts, masks, cam, res)
            print("    hand %+d  b %.2f  voxels %7d  IoU %.3f" % (hand, b, len(pts), score))
            if best is None or score > best[0]:
                best = (score, hand, float(b))
    # refine b
    score, hand, b0 = best
    for b in np.arange(b0 - 0.04, b0 + 0.041, 0.01):
        cam = Camera(b=float(b), hand=hand)
        pts, *_ = carve(masks, cam, res)
        if len(pts):
            s = splat_iou(pts, masks, cam, res)
            if s > best[0]:
                best = (s, hand, float(b))
    print("    best: hand %+d  b %.3f  IoU %.3f" % (best[1], best[2], best[0]))
    return best


# ---------------------------------------------------------------- meshing

def mesh_hull(ijk, shape, origin, res, target_tris):
    import trimesh
    import fast_simplification
    from skimage import measure
    vol = np.zeros(shape, np.float32)
    vol[ijk[:, 0], ijk[:, 1], ijk[:, 2]] = 1.0
    vol = np.pad(vol, 2)
    vol = ndimage.gaussian_filter(vol, 1.0)
    verts, faces, _, _ = measure.marching_cubes(vol, 0.5, spacing=(res, res, res))
    verts += origin - 2 * res
    m = trimesh.Trimesh(verts, faces[:, ::-1], process=True)
    parts = m.split(only_watertight=False)
    if len(parts) > 1:
        m = max(parts, key=lambda p: len(p.faces))
    trimesh.smoothing.filter_taubin(m, iterations=10)
    if len(m.faces) > target_tris:
        v, f = fast_simplification.simplify(m.vertices.astype(np.float32), m.faces.astype(np.int64),
                                            target_reduction=1 - target_tris / len(m.faces))
        m = trimesh.Trimesh(v, f, process=True)
    m.vertices[:, 1] = np.maximum(m.vertices[:, 1], 0.0)
    return m


# ---------------------------------------------------------------- rendering

def render(tris, colors, cam, phi, size=None, light=(-0.5, 0.8, -0.35), shade=True):
    """Z-buffered splat render. tris (T, 3, 3), colors (T, 3) 0..1. Returns (mask, rgb, face id)."""
    size = size or cam.size
    u, v, cl = cam.project(tris, phi)
    e1 = tris[:, 1] - tris[:, 0]
    e2 = tris[:, 2] - tris[:, 0]
    n = np.cross(e1, e2)
    n /= np.linalg.norm(n, axis=1, keepdims=True) + 1e-12
    c, s = math.cos(phi * cam.hand), math.sin(phi * cam.hand)
    nw = np.stack([n[:, 0] * c - n[:, 2] * s, n[:, 1], n[:, 0] * s + n[:, 2] * c], axis=1)
    L = np.array(light, float)
    L /= np.linalg.norm(L)
    lam = np.abs(nw @ L) if shade else np.ones(len(tris))
    lit = colors * (0.45 + 0.65 * lam[:, None])
    edge = np.max(np.stack([np.hypot(u[:, 1] - u[:, 0], v[:, 1] - v[:, 0]),
                            np.hypot(u[:, 2] - u[:, 1], v[:, 2] - v[:, 1]),
                            np.hypot(u[:, 0] - u[:, 2], v[:, 0] - v[:, 2])]), axis=0)
    k = np.clip(np.ceil(edge / 0.6), 1, 400).astype(int)
    zb = np.full(size * size, -1e9, np.float32)
    fid = np.full(size * size, -1, np.int64)
    for kk in np.unique(k):
        sel = np.nonzero(k == kk)[0]
        a_, b_ = np.meshgrid(np.arange(kk + 1), np.arange(kk + 1), indexing="ij")
        ok = a_ + b_ <= kk
        w1, w2 = a_[ok] / kk, b_[ok] / kk
        w0 = 1 - w1 - w2
        for chunk in np.array_split(sel, max(1, len(sel) * len(w0) // 2_000_000 + 1)):
            pu = u[chunk, 0:1] * w0 + u[chunk, 1:2] * w1 + u[chunk, 2:3] * w2
            pv = v[chunk, 0:1] * w0 + v[chunk, 1:2] * w1 + v[chunk, 2:3] * w2
            pc = cl[chunk, 0:1] * w0 + cl[chunk, 1:2] * w1 + cl[chunk, 2:3] * w2
            ui, vi = np.floor(pu).astype(np.int64).ravel(), np.floor(pv).astype(np.int64).ravel()
            pc = pc.ravel().astype(np.float32)
            ids = np.repeat(chunk, len(w0))
            ok2 = (ui >= 0) & (ui < size) & (vi >= 0) & (vi < size)
            pix = vi[ok2] * size + ui[ok2]
            pc, ids = pc[ok2], ids[ok2]
            if len(pix) == 0:  # this chunk is all off the canvas
                continue
            order = np.lexsort((pc, pix))
            pix, pc, ids = pix[order], pc[order], ids[order]
            last = np.r_[pix[1:] != pix[:-1], True]
            pix, pc, ids = pix[last], pc[last], ids[last]
            better = pc > zb[pix]
            zb[pix[better]] = pc[better]
            fid[pix[better]] = ids[better]
    fid = fid.reshape(size, size)
    mask = fid >= 0
    rgb = np.zeros((size, size, 3), np.float32)
    rgb[mask] = lit[fid[mask]]
    return mask, np.clip(rgb, 0, 1), fid


def load_glb(path, prefix=None, exclude=None):
    """Triangles (T, 3, 3) and colours (T, 3) from a .glb, optionally only nodes whose name starts
    with `prefix` (or every node not starting with `exclude`)."""
    import trimesh
    scene = trimesh.load(path, force="scene")
    tris, cols = [], []
    for node in scene.graph.nodes_geometry:
        name = str(node)
        if prefix and not name.startswith(prefix):
            continue
        if exclude and name.startswith(exclude):
            continue
        transform, geom = scene.graph[node]
        mesh = scene.geometry[geom]
        v = trimesh.transformations.transform_points(mesh.vertices, transform)
        tris.append(v[mesh.faces])
        col = np.array([0.6, 0.6, 0.6])
        mat = getattr(mesh.visual, "material", None)
        if mat is not None:
            f = getattr(mat, "baseColorFactor", None)
            if f is None and hasattr(mat, "main_color"):
                f = mat.main_color
            if f is not None:
                col = np.asarray(f[:3], float) / (255.0 if np.max(f) > 1 else 1.0)
        elif getattr(mesh.visual, "kind", None) == "vertex":
            col = mesh.visual.vertex_colors[:, :3].mean(axis=0) / 255.0
        cols.append(np.tile(col, (len(mesh.faces), 1)))
    if not tris:
        return np.zeros((0, 3, 3)), np.zeros((0, 3))
    return np.concatenate(tris), np.concatenate(cols)


def iou(a, b):
    return float((a & b).sum() / max(1, (a | b).sum()))


def best_shift_iou(model, sprite, r=6):
    """IoU after the best nudge of up to r px (the client's part_colors aligns the same way)."""
    best = (iou(model, sprite), 0, 0)
    for dy in range(-r, r + 1, 2):
        for dx in range(-r, r + 1, 2):
            s = iou(np.roll(np.roll(model, dy, 0), dx, 1), sprite)
            if s > best[0]:
                best = (s, dx, dy)
    return best


# ---------------------------------------------------------------- colours

def colour_hull(mesh, frames, cam, k=7):
    """Each face's colour from the frames where it's seen, clustered into k parts (one colour each)."""
    from scipy.cluster.vq import kmeans2
    tris = mesh.vertices[mesh.faces]
    acc = np.zeros((len(tris), 3))
    cnt = np.zeros(len(tris))
    for i in range(0, N_DIR, 2):
        mask, _, fid = render(tris, np.ones((len(tris), 3)), cam, phi_of(i))
        f = frames[i]
        ok = mask & (f[..., 3] > 0.9)
        ids = fid[ok]
        np.add.at(acc, ids, f[..., :3][ok])
        np.add.at(cnt, ids, 1)
    seen = cnt > 0
    col = np.full((len(tris), 3), np.nan)
    col[seen] = acc[seen] / cnt[seen, None]
    # unseen faces (underside): take the nearest seen face's colour
    if (~seen).any() and seen.any():
        from scipy.spatial import cKDTree
        cen = tris.mean(axis=1)
        _, j = cKDTree(cen[seen]).query(cen[~seen])
        col[~seen] = col[seen][j]
    adj = mesh.face_adjacency
    # blur colours over neighbouring faces first: single faces carry the sprite's fine detail and
    # its lighting, which would scatter them over every cluster
    deg = np.bincount(adj.ravel(), minlength=len(tris)).astype(float) + 1
    for _ in range(6):
        s_ = col.copy()
        np.add.at(s_, adj[:, 0], col[adj[:, 1]])
        np.add.at(s_, adj[:, 1], col[adj[:, 0]])
        col = s_ / deg[:, None]
    lab = srgb_to_lab(col)
    np.random.seed(1)
    _, labels = kmeans2(lab, k, minit="++", seed=1)
    # tidy: majority vote over face neighbours so parts are contiguous patches
    for _ in range(12):
        votes = np.zeros((len(tris), k))
        np.add.at(votes, (adj[:, 0], labels[adj[:, 1]]), 1)
        np.add.at(votes, (adj[:, 1], labels[adj[:, 0]]), 1)
        votes[np.arange(len(tris)), labels] += 1.5
        labels = votes.argmax(axis=1)
    part_col = np.array([np.median(col[labels == j], axis=0) if (labels == j).any() else [0.5] * 3
                         for j in range(k)])
    # the sprites are lit: lift the medians a little towards albedo (the faces averaged include
    # shaded sides), so the renderer's own light doesn't darken them twice
    part_col = np.clip(part_col * 1.15, 0, 1)
    return labels, part_col


def srgb_to_lab(c):
    c = np.clip(c, 0, 1)
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    M = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = lin @ M.T / np.array([0.9505, 1.0, 1.089])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[:, 1] - 16, 500 * (f[:, 0] - f[:, 1]), 200 * (f[:, 1] - f[:, 2])], axis=1)


# ---------------------------------------------------------------- commands

def cam_file(entity):
    return os.path.join(OUT, "out", entity + ".camera.json")


def cmd_hull(entity, res, fit, budget):
    import trimesh
    os.makedirs(os.path.join(OUT, "out"), exist_ok=True)
    camj = {}
    meshes = {}
    for part in ENTITIES[entity]:
        print("%s / %s" % (entity, part))
        frames = part_frames(entity, part)
        masks = masks_of(frames)
        if fit:
            score, hand, b = fit_camera(masks)
            camj[part] = {"hand": hand, "b": b, "fit_iou": score}
        else:
            camj[part] = {"hand": 1, "b": 1.0}
        cam = Camera(b=camj[part]["b"], hand=camj[part]["hand"])
        pts, ijk, shape, origin = carve(masks, cam, res)
        print("    carved: %d voxels at %.3f" % (len(pts), res))
        mesh = mesh_hull(ijk, shape, origin, res, budget // len(ENTITIES[entity]))
        labels, part_col = colour_hull(mesh, frames, cam)
        meshes[part] = (mesh, labels, part_col)
        print("    mesh: %d triangles, %d colour parts" % (len(mesh.faces), len(part_col)))
    scene = trimesh.Scene()
    for part, (mesh, labels, part_col) in meshes.items():
        prefix = ENTITIES[entity][part][1] or "body"
        for j, col in enumerate(part_col):
            sel = np.nonzero(labels == j)[0]
            if len(sel) == 0:
                continue
            sub = mesh.submesh([sel], append=True)
            sub.visual = trimesh.visual.TextureVisuals(material=trimesh.visual.material.PBRMaterial(
                name="%s_%d" % (part, j), baseColorFactor=list(col) + [1.0], roughnessFactor=0.8, metallicFactor=0.1))
            scene.add_geometry(sub, node_name="%s_%s_%d" % (prefix, part, j), geom_name="%s_%s_%d" % (prefix, part, j))
    path = os.path.join(OUT, "out", entity + ".glb")
    scene.export(path)
    json.dump(camj, open(cam_file(entity), "w"), indent=1)
    print("wrote %s (%d triangles)" % (path, sum(len(m[0].faces) for m in meshes.values())))


def label(img, text):
    from PIL import ImageDraw
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, 8 * len(text) + 6, 14), fill=(0, 0, 0))
    d.text((3, 1), text, fill=(255, 255, 255))
    return img


def to_img(rgb, mask, bg=(48, 52, 56)):
    out = np.empty(rgb.shape, np.uint8)
    out[:] = bg
    out[mask] = (rgb[mask] * 255).astype(np.uint8)
    return out


def sprite_img(frame, bg=(48, 52, 56)):
    a = frame[..., 3:4]
    return (frame[..., :3] * a * 255 + np.array(bg) * (1 - a)).astype(np.uint8)


def crop_box(images, pad=8, bg=(48, 52, 56)):
    m = np.zeros(images[0].shape[:2], bool)
    for im in images:
        m |= np.any(im != np.array(bg, np.uint8), axis=-1)
    ys, xs = np.nonzero(m)
    return max(0, ys.min() - pad), ys.max() + pad, max(0, xs.min() - pad), xs.max() + pad


def cmd_compare(entity, dirs=(0, 8, 16, 24, 40, 56)):
    camj = json.load(open(cam_file(entity)))
    hull_path = os.path.join(OUT, "out", entity + ".glb")
    cur_path = os.path.join(MODELS, entity + ".glb")
    report = {}
    rows = []
    for part, (fn, prefix) in ENTITIES[entity].items():
        frames = part_frames(entity, part)
        masks = masks_of(frames, dilate=0)
        cam = Camera(b=camj[part]["b"], hand=camj[part]["hand"])
        cam_client = Camera(b=B_CLIENT, hand=1)
        hp = (ENTITIES[entity][part][1] or "body") + "_" + part
        ht, hc = load_glb(hull_path, prefix=hp)
        if prefix:
            ct, cc = load_glb(cur_path, prefix=prefix)
        else:
            others = [p for p in ENTITIES[entity].values() if p[1]]
            ct, cc = load_glb(cur_path, exclude=others[0][1] if others else None)
        res = {"hull": [], "current": [], "current_nudged": [], "current_client_cam": []}
        for i in range(N_DIR):
            phi = phi_of(i)
            hm, _, _ = render(ht, hc, cam, phi)
            cm, _, _ = render(ct, cc, cam, phi)
            ccm, _, _ = render(ct, cc, cam_client, phi)
            res["hull"].append(iou(hm, masks[i]))
            res["current"].append(iou(cm, masks[i]))
            res["current_nudged"].append(best_shift_iou(cm, masks[i])[0])
            res["current_client_cam"].append(best_shift_iou(ccm, masks[i])[0])
        report[part] = {k: {"mean": round(float(np.mean(v)), 3), "min": round(float(np.min(v)), 3),
                            "per_direction": [round(x, 3) for x in v]} for k, v in res.items()}
        print("%s / %s: IoU mean hull %.3f | current %.3f (nudged %.3f, client camera %.3f)" % (
            entity, part, np.mean(res["hull"]), np.mean(res["current"]), np.mean(res["current_nudged"]),
            np.mean(res["current_client_cam"])))
    # side by side picture: whole entity (all parts)
    all_frames = [frame_canvas(sum((ENTITIES[entity][p][0](i) for p in ENTITIES[entity]), [])) for i in dirs]
    cam = Camera(b=list(camj.values())[0]["b"], hand=list(camj.values())[0]["hand"])
    ht, hc = load_glb(hull_path)
    ct, cc = load_glb(cur_path)
    if entity == "gun-turret":   # compare the head only: the base is one picture, not carved
        ct, cc = load_glb(cur_path, prefix="anim_turret")
    cols = []
    for d, f in zip(dirs, all_frames):
        phi = phi_of(d)
        s = sprite_img(f)
        cm, crgb, _ = render(ct, cc, cam, phi)
        hm, hrgb, _ = render(ht, hc, cam, phi)
        cols.append([s, to_img(crgb, cm), to_img(hrgb, hm)])
    y0, y1, x0, x1 = crop_box([im for c in cols for im in c])
    tiles = []
    for d, c in zip(dirs, cols):
        col = [label(Image.fromarray(im[y0:y1, x0:x1].copy()), t) for im, t in
               zip(c, ("sprite %d/64" % d, "current", "hull"))]
        tiles.append(col)
    # other angles: low (15 deg) and side-on (0 deg), current vs hull, from the front-right
    extra = []
    for elev in (15, 0):
        for which, (t, c_) in (("current", (ct, cc)), ("hull", (ht, hc))):
            c2 = Camera.true(elev, anchor=ANCHOR, hand=cam.hand)
            m, rgb, _ = render(t, c_, c2, phi_of(8))
            m2, rgb2, _ = render(t, c_, c2, phi_of(16))
            extra.append(((to_img(rgb, m), "%s %d deg NE" % (which, elev)),
                          (to_img(rgb2, m2), "%s %d deg E" % (which, elev))))
    tw, th = x1 - x0, y1 - y0
    W = tw * len(tiles)
    sheet_img = Image.new("RGB", (W, th * 3), (30, 30, 30))
    for ci, col in enumerate(tiles):
        for ri, im in enumerate(col):
            sheet_img.paste(im, (ci * tw, ri * th))
    # extra row block, cropped tighter
    ex_imgs = [im for pair in extra for im in pair]
    arrs = [a for a, _ in ex_imgs]
    ey0, ey1, ex0, ex1 = crop_box(arrs)
    ey0 = max(0, ey0 - 14)
    ew, eh = ex1 - ex0, ey1 - ey0
    per_row = max(1, W // ew)
    nrows = math.ceil(len(arrs) / per_row)
    final = Image.new("RGB", (max(W, ew * min(per_row, len(arrs))), th * 3 + eh * nrows), (30, 30, 30))
    final.paste(sheet_img, (0, 0))
    for k, a in enumerate(arrs):
        final.paste(label(Image.fromarray(a[ey0:ey1, ex0:ex1].copy()), ex_imgs[k][1]),
                    ((k % per_row) * ew, th * 3 + (k // per_row) * eh))
    path = os.path.join(OUT, entity + "_compare.png")
    final.save(path)
    json.dump(report, open(os.path.join(OUT, entity + "_iou.json"), "w"), indent=1)
    print("wrote %s" % path)


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=("hull", "compare"))
    ap.add_argument("names", nargs="+")
    ap.add_argument("--res", type=float, default=0.02)
    ap.add_argument("--fit", action="store_true", help="fit the camera's north-south scale")
    ap.add_argument("--budget", type=int, default=9000)
    args = ap.parse_args(argv)
    for name in args.names:
        if args.cmd == "hull":
            cmd_hull(name, args.res, args.fit, args.budget)
        else:
            cmd_compare(name)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
