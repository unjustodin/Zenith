"""Low-poly building blocks for the item models (tools/models/items.py), the icon colour sampler
and a small glTF writer. Plain Python (numpy, pillow), no Blender.

Items are drawn by the thousand on belts, so each model is a few dozen triangles with its
colours in the vertices (COLOR_0); the client draws them with one MultiMesh per item type and
one plain material. Coordinates are Godot's: x east, y up, z south; 1 unit = 1 tile; the origin
is at the bottom centre, where the item touches the belt.
"""

import colorsys
import json
import math
import os
import struct

import numpy as np
from PIL import Image

MODS = ("base", "space-age", "quality", "elevated-rails")


def find_factorio():
    env = os.environ.get("FACTORIO")
    candidates = [env] if env else []
    candidates += [
        r"C:\Program Files (x86)\Steam\steamapps\common\Factorio",
        r"C:\Program Files\Factorio",
        os.path.expanduser("~/.steam/steam/steamapps/common/Factorio"),
        os.path.expanduser("~/.local/share/Steam/steamapps/common/Factorio"),
    ]
    for c in candidates:
        if c and os.path.isdir(os.path.join(c, "data", "base", "graphics", "icons")):
            return c
    return None


# --- colours ------------------------------------------------------------------------------------

def srgb_to_linear(c):
    c = np.asarray(c, dtype=float)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def hexcol(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def scale(col, f):
    return tuple(min(1.0, max(0.0, v * f)) for v in col)


def mix(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


class Icon:
    """One item icon from Factorio's install, for picking colours. Colours are sRGB 0..1, the way
    the icon shows them. The icons' smaller mipmaps (to the right of the full-size square) are
    cut off."""

    def __init__(self, factorio, name):
        self.name = name
        self.path = None
        for mod in MODS:
            p = os.path.join(factorio, "data", mod, "graphics", "icons", name + ".png")
            if os.path.exists(p):
                self.path = p
                break
        if self.path is None:
            raise FileNotFoundError("no icon for %s" % name)
        im = Image.open(self.path).convert("RGBA")
        h = im.height
        a = np.asarray(im.crop((0, 0, h, h)), dtype=float) / 255.0
        self.size = h
        self.rgba = a
        ys, xs = np.mgrid[0:h, 0:h]
        self.u = (xs + 0.5) / h
        self.v = (ys + 0.5) / h
        opaque = a[..., 3] > 0.75
        self.mask = opaque
        rgb = a[..., :3]
        hsv = np.array([colorsys.rgb_to_hsv(*p) for p in rgb.reshape(-1, 3)]).reshape(h, h, 3)
        self.hue = hsv[..., 0] * 360.0
        self.sat = hsv[..., 1]
        self.val = hsv[..., 2]
        self.lum = rgb @ np.array([0.2126, 0.7152, 0.0722])

    def pick(self, region=None, hue=None, sat=None, val=None, lum=None, default=None):
        """Median colour of the icon's opaque pixels that pass every filter:
        region (u0, v0, u1, v1) in 0..1 of the icon (v down); hue (lo, hi) in degrees (lo > hi
        wraps through red); sat / val (lo, hi) in 0..1; lum (q_lo, q_hi), a band of the
        brightness quantiles among the pixels left. Falls back to `default`, else to fewer
        filters, when fewer than 8 pixels pass."""
        m = self.mask.copy()
        if region is not None:
            u0, v0, u1, v1 = region
            m &= (self.u >= u0) & (self.u <= u1) & (self.v >= v0) & (self.v <= v1)
        if hue is not None:
            lo, hi = hue
            hm = (self.hue >= lo) & (self.hue <= hi) if lo <= hi else (self.hue >= lo) | (self.hue <= hi)
            m &= hm
        if sat is not None:
            m &= (self.sat >= sat[0]) & (self.sat <= sat[1])
        if val is not None:
            m &= (self.val >= val[0]) & (self.val <= val[1])
        if lum is not None and m.sum() >= 8:
            ls = self.lum[m]
            lo, hi = np.quantile(ls, lum[0]), np.quantile(ls, lum[1])
            m &= (self.lum >= lo) & (self.lum <= hi)
        if m.sum() < 8:
            if default is not None:
                return default
            if hue is not None or sat is not None or val is not None:
                return self.pick(region=region, lum=lum)
            if region is not None:
                return self.pick(lum=lum)
            m = self.mask
        return tuple(float(x) for x in np.median(self.rgba[..., :3][m], axis=0))


# --- meshes -------------------------------------------------------------------------------------

class Mesh:
    """Unindexed triangles: pos (n, 3, 3), nrm (n, 3, 3), col (n, 3, 3) in sRGB."""

    def __init__(self, pos=None, nrm=None, col=None):
        self.pos = np.zeros((0, 3, 3)) if pos is None else np.asarray(pos, dtype=float)
        self.nrm = np.zeros((0, 3, 3)) if nrm is None else np.asarray(nrm, dtype=float)
        self.col = np.zeros((0, 3, 3)) if col is None else np.asarray(col, dtype=float)

    @property
    def tris(self):
        return len(self.pos)

    def __add__(self, other):
        return Mesh(np.concatenate([self.pos, other.pos]), np.concatenate([self.nrm, other.nrm]),
                    np.concatenate([self.col, other.col]))

    def copy(self):
        return Mesh(self.pos.copy(), self.nrm.copy(), self.col.copy())

    def _apply(self, m3, t=(0, 0, 0)):
        out = self.copy()
        out.pos = out.pos @ m3.T + np.asarray(t, dtype=float)
        n = out.nrm @ np.linalg.inv(m3)  # normals: inverse transpose
        out.nrm = n / np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-9)
        return out

    def move(self, x=0.0, y=0.0, z=0.0):
        out = self.copy()
        out.pos = out.pos + np.array([x, y, z])
        return out

    def scaled(self, sx, sy=None, sz=None):
        sy = sx if sy is None else sy
        sz = sx if sz is None else sz
        return self._apply(np.diag([sx, sy, sz]))

    def rot_y(self, deg):
        a = math.radians(deg)
        c, s = math.cos(a), math.sin(a)
        # Positive turns counter-clockwise seen from above (Godot's rotation about +Y).
        return self._apply(np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]]))

    def rot_x(self, deg):
        a = math.radians(deg)
        c, s = math.cos(a), math.sin(a)
        return self._apply(np.array([[1, 0, 0], [0, c, -s], [0, s, c]]))

    def rot_z(self, deg):
        a = math.radians(deg)
        c, s = math.cos(a), math.sin(a)
        return self._apply(np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]]))

    def bounds(self):
        p = self.pos.reshape(-1, 3)
        return p.min(axis=0), p.max(axis=0)

    def recolor(self, col):
        out = self.copy()
        out.col[:] = np.asarray(col, dtype=float)
        return out


def merge(*meshes):
    out = Mesh()
    for m in meshes:
        if m is not None:
            out = out + m
    return out


def _flat(tris, col):
    tris = np.asarray(tris, dtype=float)
    n = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    n /= np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-12)
    nrm = np.repeat(n[:, None, :], 3, axis=1)
    c = np.asarray(col, dtype=float)
    if c.ndim == 1:
        c = np.broadcast_to(c, tris.shape).copy()
    elif c.ndim == 2:  # one colour per triangle
        c = np.repeat(c[:, None, :], 3, axis=1)
    return Mesh(tris, nrm, c)


def quads(vs, faces, col):
    """Faces as lists of vertex indices (counter-clockwise seen from outside), fanned."""
    tris, cols = [], []
    for i, f in enumerate(faces):
        fc = col[i] if isinstance(col, list) else col
        for k in range(1, len(f) - 1):
            tris.append([vs[f[0]], vs[f[k]], vs[f[k + 1]]])
            cols.append(fc)
    return _flat(tris, cols)


def box(sx, sy, sz, col, top=None, x=0.0, y=0.0, z=0.0, bottom=False):
    """A box standing on y (its base), centred on x, z. `top`: another colour for the top face.
    The bottom face is left out unless asked for (items lie on something)."""
    hx, hz = sx / 2, sz / 2
    v = [(-hx, 0, -hz), (hx, 0, -hz), (hx, 0, hz), (-hx, 0, hz),
         (-hx, sy, -hz), (hx, sy, -hz), (hx, sy, hz), (-hx, sy, hz)]
    faces = [[4, 7, 6, 5], [3, 2, 6, 7], [1, 0, 4, 5], [2, 1, 5, 6], [0, 3, 7, 4]]
    cols = [top or col, col, col, col, col]
    if bottom:
        faces.append([0, 1, 2, 3])
        cols.append(col)
    return quads(v, faces, cols).move(x, y, z)


def bevel_box(sx, sy, sz, bevel, col, top=None, x=0.0, y=0.0, z=0.0):
    """A box with its top edges chamfered by `bevel` (plates, bricks, bars)."""
    hx, hz = sx / 2, sz / 2
    b = min(bevel, hx * 0.9, hz * 0.9, sy * 0.9)
    v = [(-hx, 0, -hz), (hx, 0, -hz), (hx, 0, hz), (-hx, 0, hz),
         (-hx, sy - b, -hz), (hx, sy - b, -hz), (hx, sy - b, hz), (-hx, sy - b, hz),
         (-hx + b, sy, -hz + b), (hx - b, sy, -hz + b), (hx - b, sy, hz - b), (-hx + b, sy, hz - b)]
    faces = [[3, 2, 6, 7], [1, 0, 4, 5], [2, 1, 5, 6], [0, 3, 7, 4],  # sides
             [7, 6, 10, 11], [5, 4, 8, 9], [6, 5, 9, 10], [4, 7, 11, 8],  # chamfers
             [8, 11, 10, 9]]  # top
    t = top or col
    cols = [col] * 4 + [mix(col, t, 0.5)] * 4 + [t]
    return quads(v, faces, cols).move(x, y, z)


def prism(radius, height, n, col, cap=None, r_top=None, smooth=True, bottom=False, start=0.0):
    """An n-sided cylinder (or frustum with r_top) standing on y = 0 along +y."""
    r_top = radius if r_top is None else r_top
    a = [start + 2 * math.pi * i / n for i in range(n)]
    lo = [(radius * math.cos(t), 0.0, radius * math.sin(t)) for t in a]
    hi = [(r_top * math.cos(t), height, r_top * math.sin(t)) for t in a]
    tris, nrms = [], []
    slope = (radius - r_top) / max(height, 1e-9)
    for i in range(n):
        j = (i + 1) % n
        tris += [[lo[i], hi[j], lo[j]], [lo[i], hi[i], hi[j]]]
        if smooth:
            ni = np.array([math.cos(a[i]), slope, math.sin(a[i])])
            nj = np.array([math.cos(a[j]), slope, math.sin(a[j])])
            ni /= np.linalg.norm(ni)
            nj /= np.linalg.norm(nj)
            nrms += [[ni, nj, nj], [ni, ni, nj]]
    side = _flat(tris, col)
    if smooth:
        side.nrm = np.array(nrms)
    cap_tris = []
    if r_top > 1e-6:
        c = (0.0, height, 0.0)
        cap_tris += [[c, hi[(i + 1) % n], hi[i]] for i in range(n)]
    out = side + _flat(cap_tris, cap or col) if cap_tris else side
    if bottom:
        c = (0.0, 0.0, 0.0)
        out = out + _flat([[c, lo[i], lo[(i + 1) % n]] for i in range(n)], col)
    return out


def lying(mesh, axis="x"):
    """Turns a mesh built along +y to lie along x or z, resting on y = 0 (for prisms of
    radius r, lift by r afterwards)."""
    return mesh.rot_z(-90) if axis == "x" else mesh.rot_x(90)


def cylinder_x(radius, length, n, col, cap=None, smooth=True):
    """A cylinder lying along x, centred, resting on y = 0."""
    return prism(radius, length, n, col, cap, smooth=smooth, bottom=True).move(0, -length / 2, 0) \
        .rot_z(-90).move(0, radius, 0)


def cylinder_z(radius, length, n, col, cap=None, smooth=True):
    return prism(radius, length, n, col, cap, smooth=smooth, bottom=True).move(0, -length / 2, 0) \
        .rot_x(90).move(0, radius, 0)


def extrude(outline, height, col, top=None, y=0.0):
    """A flat shape (x, z points in the order circle() gives them, star-shaped about their
    centroid) pulled up to `height`."""
    pts = [(float(x), float(z)) for x, z in outline]
    cx = sum(p[0] for p in pts) / len(pts)
    cz = sum(p[1] for p in pts) / len(pts)
    n = len(pts)
    tris_side, tris_top = [], []
    for i in range(n):
        x0, z0 = pts[i]
        x1, z1 = pts[(i + 1) % n]
        a, b = (x0, y, z0), (x1, y, z1)
        c, d = (x1, y + height, z1), (x0, y + height, z0)
        tris_side += [[a, c, b], [a, d, c]]
        tris_top.append([(cx, y + height, cz), (x1, y + height, z1), (x0, y + height, z0)])
    return _flat(tris_side, col) + _flat(tris_top, top or col)


def ring(outer, inner, height, col, top=None, y=0.0):
    """The band between two outlines with the same number of points (in circle() order):
    gears, coils, frames."""
    n = len(outer)
    sides, tops = [], []
    for i in range(n):
        j = (i + 1) % n
        o0 = (outer[i][0], y, outer[i][1])
        o1 = (outer[j][0], y, outer[j][1])
        O0 = (outer[i][0], y + height, outer[i][1])
        O1 = (outer[j][0], y + height, outer[j][1])
        i0 = (inner[i][0], y, inner[i][1])
        i1 = (inner[j][0], y, inner[j][1])
        I0 = (inner[i][0], y + height, inner[i][1])
        I1 = (inner[j][0], y + height, inner[j][1])
        sides += [[o0, O1, o1], [o0, O0, O1], [i0, i1, I1], [i0, I1, I0]]
        tops += [[I0, O1, O0], [I0, I1, O1]]
    return _flat(sides, col) + _flat(tops, top or col)


def circle(r, n, start=0.0):
    return [(r * math.cos(start + 2 * math.pi * i / n), r * math.sin(start + 2 * math.pi * i / n))
            for i in range(n)]


def rock(sx, sy, sz, col, seed, points=11, flat_base=True, round_=False):
    """A lump of ore or stone: the convex hull of random points on a squashed sphere, one
    flat-shaded facet each, every facet's shade jittered a little."""
    from scipy.spatial import ConvexHull

    rng = np.random.default_rng(seed)
    p = rng.normal(size=(points, 3))
    p /= np.linalg.norm(p, axis=1, keepdims=True)
    if round_:  # chunky lumps: points spread evenly round the sphere, little dents
        k = np.arange(points) + 0.5
        phi = np.arccos(1 - 2 * k / points)
        theta = np.pi * (1 + 5 ** 0.5) * k + rng.uniform(0, 6.3)
        p = np.stack([np.cos(theta) * np.sin(phi), np.cos(phi), np.sin(theta) * np.sin(phi)], axis=1)
        p += rng.normal(scale=0.18, size=p.shape)
    p *= rng.uniform(0.8 if round_ else 0.75, 1.0, size=(points, 1))
    p *= np.array([sx / 2, sy / 2, sz / 2])
    if flat_base:
        p[:, 1] = np.maximum(p[:, 1], -sy * 0.3)
    hull = ConvexHull(p)
    tris = []
    centre = p.mean(axis=0)
    for f in hull.simplices:
        a, b, c = p[f]
        if np.dot(np.cross(b - a, c - a), a - centre) < 0:
            b, c = c, b
        tris.append([a, b, c])
    tris = np.array(tris)
    shade = rng.uniform(0.82, 1.12, size=len(tris))
    cols = np.clip(np.outer(shade, col), 0, 1)
    m = _flat(tris, cols)
    lo, hi = m.bounds()
    m = m.move(*(-(lo + hi) / 2))
    m = m.scaled(*(np.array([sx, sy, sz]) / np.maximum(hi - lo, 1e-9)))  # fill the size asked for
    return m.move(0, sy / 2, 0)


def shade_by_height(mesh, low=0.72, ground=0.0, top=None):
    """Cheap baked occlusion: corners near what the item rests on are darker (the wear and
    grime Factorio's icons show at their bases)."""
    out = mesh.copy()
    y = out.pos[..., 1]
    hi = top if top is not None else max(float(y.max()), 1e-6)
    f = low + (1.0 - low) * np.clip((y - ground) / max(hi - ground, 1e-6), 0, 1)
    out.col = np.clip(out.col * f[..., None], 0, 1)
    return out


# --- glTF ---------------------------------------------------------------------------------------

def write_glb(path, mesh, name):
    """One mesh, one node, one material (its colours are in COLOR_0, linear as glTF wants)."""
    pos = mesh.pos.reshape(-1, 3).astype(np.float32)
    nrm = mesh.nrm.reshape(-1, 3).astype(np.float32)
    col = np.concatenate([srgb_to_linear(np.clip(mesh.col.reshape(-1, 3), 0, 1)),
                          np.ones((len(pos), 1))], axis=1).astype(np.float32)
    count = len(pos)
    if count > 65535:
        raise ValueError("%s: too many vertices" % name)
    # Weld identical corners (same position, normal and colour) to keep the file small.
    key = np.concatenate([np.round(pos, 5), np.round(nrm, 4), np.round(col, 4)], axis=1)
    uniq, index = np.unique(key, axis=0, return_inverse=True)
    index = index.reshape(-1).astype(np.uint16)
    pos, nrm, col = uniq[:, 0:3].astype(np.float32), uniq[:, 3:6].astype(np.float32), uniq[:, 6:10].astype(np.float32)
    nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
    blobs = [index.tobytes(), pos.tobytes(), nrm.tobytes(), col.tobytes()]
    views, offset, binary = [], 0, b""
    for i, blob in enumerate(blobs):
        pad = (-len(blob)) % 4
        views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(blob),
                      "target": 34963 if i == 0 else 34962})
        binary += blob + b"\0" * pad
        offset += len(blob) + pad
    doc = {
        "asset": {"version": "2.0", "generator": "Factorio 3D tools/models/items.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": name, "mesh": 0}],
        "meshes": [{"name": name, "primitives": [{
            "attributes": {"POSITION": 1, "NORMAL": 2, "COLOR_0": 3}, "indices": 0, "material": 0}]}],
        "materials": [{"name": "item", "pbrMetallicRoughness": {
            "baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.0, "roughnessFactor": 0.8}}],
        "accessors": [
            {"bufferView": 0, "componentType": 5123, "count": int(len(index)), "type": "SCALAR"},
            {"bufferView": 1, "componentType": 5126, "count": int(len(pos)), "type": "VEC3",
             "min": pos.min(axis=0).tolist(), "max": pos.max(axis=0).tolist()},
            {"bufferView": 2, "componentType": 5126, "count": int(len(pos)), "type": "VEC3"},
            {"bufferView": 3, "componentType": 5126, "count": int(len(pos)), "type": "VEC4"},
        ],
        "bufferViews": views,
        "buffers": [{"byteLength": len(binary)}],
    }
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * ((-len(js)) % 4)
    out = struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(js) + 8 + len(binary))
    out += struct.pack("<I4s", len(js), b"JSON") + js
    out += struct.pack("<I4s", len(binary), b"BIN\0") + binary
    with open(path, "wb") as f:
        f.write(out)
    return int(len(index) // 3)
