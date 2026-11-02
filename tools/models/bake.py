"""Per-vertex weathering data for the client's Factorio material (client/shaders/factorio_material.gdshader).

Factorio's sprites are rendered with dark ambient occlusion, grime in the crevices and worn bright
edges. The client draws those in a shader (where it isn't projecting the sprite itself), which
needs to know, per vertex, how enclosed the surface is and where its convex edges are. This module works that out from the triangles alone,
in plain numpy, so the Blender builds (kit.py, nature/) and the Wube converter (wube.py) share it:

    ao    1 = open sky, 0 = fully enclosed. Rays over the hemisphere round each corner's normal,
          marched through a voxel copy of the model, plus the ground plane, within AO_DISTANCE.
    edge  1 on worn convex edges: corners of narrow faces (bevels, rims, bolts) that bend away
          from their neighbours by more than about 30 degrees. 0 elsewhere.
    part  a random value in [0, 1) per connected piece (each box, cylinder or bolt of a kit
          model), so rust and dirt vary from piece to piece. Stable from build to build.
    vis   per direction the model can face (north, east, south, west): how much of the corner
          Factorio's camera sees, so the client projects the game's sprite only where it lands
          (client/scripts/world/sprite_projection.gd) and uses the procedural look elsewhere.

Exported layout (see client/assets/models/README.md):

    COLOR_0     rgb = albedo multiplier (1 unless a model shades itself, like the nature models),
                a = ao
    TEXCOORD_0  planar UVs in tiles (kit models; optional)
    TEXCOORD_1  (edge, part)
    TEXCOORD_2  (vis north, vis east)   how much Factorio's camera sees of the corner, for the
    TEXCOORD_3  (vis south, vis west)   model facing that way (sprite projection, see the client)

Everything is deterministic, so rebuilding unchanged models gives the same files.
"""

import math
import zlib

import numpy as np

AO_DISTANCE = 0.7   # tiles: how far away an occluder still darkens a corner
AO_RAYS = 40
# Narrow faces count as edges: a face is "narrow" when its area over its longest side (its
# width) is below EDGE_WIDTH[0], and not at all above EDGE_WIDTH[1] (tiles).
EDGE_WIDTH = (0.045, 0.11)
EDGE_ANGLE = (28.0, 42.0)  # degrees between neighbouring faces for a convex edge to wear


def _smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _normalize(v):
    n = np.linalg.norm(v, axis=-1, keepdims=True)
    return v / np.maximum(n, 1e-12)


# ---------------------------------------------------------------------------------------------
# Welding and connectivity

def weld(pos, tolerance=1e-4):
    """Ids for corner positions (N, 3) so that corners at the same place share one id."""
    keys = np.round(pos / tolerance).astype(np.int64)
    _, ids = np.unique(keys, axis=0, return_inverse=True)
    return ids.reshape(-1)


def components(vid):
    """Connected component label per triangle, from welded corner ids (T, 3)."""
    labels = np.arange(vid.max() + 1)
    while True:
        tri_min = labels[vid].min(axis=1)
        new = labels.copy()
        for k in range(3):
            np.minimum.at(new, vid[:, k], tri_min)
        new = new[new]  # pointer jumping speeds up long chains
        if np.array_equal(new, labels):
            break
        labels = new
    return labels[vid[:, 0]]


def part_random(tris, labels):
    """A stable random value in [0, 1) per component, from its rounded centroid."""
    out = np.zeros(len(tris))
    centroids = tris.mean(axis=1)
    for label in np.unique(labels):
        mask = labels == label
        c = np.round(centroids[mask].mean(axis=0), 3) + 0.0  # + 0.0 turns -0.0 into 0.0
        out[mask] = (zlib.crc32(np.asarray(c, dtype="<f8").tobytes()) & 0xffffff) / float(1 << 24)
    return out


# ---------------------------------------------------------------------------------------------
# Edges

def edge_wear(tris, vid, width=None):
    """Per corner (T, 3): how worn the edge it sits on is. `width` per triangle is the width of
    the polygon it came from (area / longest side; wube.py passes each triangle's own); without
    it every face counts as narrow."""
    T = len(tris)
    e1 = tris[:, 1] - tris[:, 0]
    e2 = tris[:, 2] - tris[:, 0]
    fn = np.cross(e1, e2)
    area2 = np.linalg.norm(fn, axis=1)
    fn = fn / np.maximum(area2, 1e-12)[:, None]

    # Triangle edges keyed by their welded end points.
    a = np.concatenate([vid[:, 0], vid[:, 1], vid[:, 2]])
    b = np.concatenate([vid[:, 1], vid[:, 2], vid[:, 0]])
    opp = np.concatenate([np.full(T, 2), np.full(T, 0), np.full(T, 1)])
    tri = np.concatenate([np.arange(T)] * 3)
    lo, hi = np.minimum(a, b), np.maximum(a, b)
    order = np.lexsort((hi, lo))
    lo, hi, tri, opp = lo[order], hi[order], tri[order], opp[order]
    same = (lo[1:] == lo[:-1]) & (hi[1:] == hi[:-1])
    # Manifold edges only: exactly two triangles.
    pair = same.copy()
    pair[1:] &= ~same[:-1]
    pair[:-1] &= ~same[1:]
    i = np.nonzero(pair)[0]
    ta, tb = tri[i], tri[i + 1]
    ok = (area2[ta] > 1e-12) & (area2[tb] > 1e-12)
    i, ta, tb = i[ok], ta[ok], tb[ok]
    cos = np.clip(np.einsum("ij,ij->i", fn[ta], fn[tb]), -1.0, 1.0)
    angle = np.degrees(np.arccos(cos))
    # Convex when the far corner of one triangle lies below the other's plane.
    far_b = tris[tb, opp[i + 1]]
    side = np.einsum("ij,ij->i", fn[ta], far_b - tris[ta, 0])
    convex = np.where(side < -1e-7, angle, 0.0)
    vert_convex = np.zeros(vid.max() + 1)
    np.maximum.at(vert_convex, lo[i], convex)
    np.maximum.at(vert_convex, hi[i], convex)
    edge = _smoothstep(EDGE_ANGLE[0], EDGE_ANGLE[1], vert_convex[vid])
    if width is not None:
        edge *= (1.0 - _smoothstep(EDGE_WIDTH[0], EDGE_WIDTH[1], np.asarray(width)))[:, None]
    return edge


# ---------------------------------------------------------------------------------------------
# Ambient occlusion

def _hemisphere(n):
    """n cosine-weighted directions round +Z (a Fibonacci spiral, so no randomness)."""
    k = np.arange(n) + 0.5
    r = np.sqrt(k / n)
    phi = k * math.pi * (3.0 - math.sqrt(5.0))
    return np.stack([r * np.cos(phi), r * np.sin(phi), np.sqrt(1.0 - r * r)], axis=1)


def _voxelize(tris, voxel, lo, dims):
    """Marks every voxel a triangle passes through, then grows the shell by one voxel so rays
    marching half a voxel at a time can't slip through it."""
    grid = np.zeros(dims, dtype=bool)
    e1 = tris[:, 1] - tris[:, 0]
    e2 = tris[:, 2] - tris[:, 0]
    area = 0.5 * np.linalg.norm(np.cross(e1, e2), axis=1)
    longest = np.max(np.linalg.norm(np.stack([e1, e2, tris[:, 2] - tris[:, 1]], 1), axis=2), axis=1)
    s = voxel * 0.5
    count = np.ceil(np.maximum(2.0 * area / (s * s), 2.0 * longest / s)).astype(np.int64) + 3
    tri = np.repeat(np.arange(len(tris)), count)
    k = np.arange(len(tri)) - np.repeat(np.cumsum(count) - count, count)
    # R2 low-discrepancy points, folded into the triangle.
    u = np.mod(0.5 + k * 0.7548776662466927, 1.0)
    v = np.mod(0.5 + k * 0.5698402909980532, 1.0)
    fold = u + v > 1.0
    u[fold], v[fold] = 1.0 - u[fold], 1.0 - v[fold]
    pts = tris[tri, 0] + e1[tri] * u[:, None] + e2[tri] * v[:, None]
    pts = np.concatenate([pts, tris.reshape(-1, 3)])
    idx = np.floor((pts - lo) / voxel).astype(np.int64)
    idx = np.clip(idx, 0, np.array(dims) - 1)
    grid[idx[:, 0], idx[:, 1], idx[:, 2]] = True
    grown = grid.copy()
    for axis in range(3):
        for shift in (-1, 1):
            grown |= np.roll(grid, shift, axis=axis)
    return grown


def _fill(shell):
    """Solid voxels: the shell plus everything it closes off from the outside. The outside is
    grown from the grid's border along straight lines through empty voxels, a few times over,
    which reaches round corners quickly."""
    empty = ~shell
    outside = np.zeros_like(shell)
    outside[0, :, :] = outside[-1, :, :] = True
    outside[:, 0, :] = outside[:, -1, :] = True
    outside[:, :, 0] = outside[:, :, -1] = True
    outside &= empty
    for _ in range(64):
        before = int(outside.sum())
        for axis in range(3):
            n = shell.shape[axis]
            shape = [1, 1, 1]
            shape[axis] = n
            idx = np.arange(n, dtype=np.int32).reshape(shape)
            for flip in (False, True):
                o = np.flip(outside, axis) if flip else outside
                s = np.flip(shell, axis) if flip else shell
                last_out = np.maximum.accumulate(np.where(o, idx, -1), axis=axis)
                last_shell = np.maximum.accumulate(np.where(s, idx, -1), axis=axis)
                reach = last_out > last_shell
                outside |= (np.flip(reach, axis) if flip else reach) & empty
        if int(outside.sum()) == before:
            break
    return ~outside


class _Voxels:
    """A solid voxel copy of the model for marching rays: occlusion and projector visibility."""

    def __init__(self, tris, up):
        flat = tris.reshape(-1, 3)
        extent = flat.max(axis=0) - flat.min(axis=0)
        self.voxel = float(np.clip(extent.max() / 140.0, 0.012, 0.045))
        self.lo = flat.min(axis=0) - 3 * self.voxel
        self.dims = np.array([int(d) for d in np.ceil((extent + 6 * self.voxel) / self.voxel)])
        self.solid = _fill(_voxelize(tris, self.voxel, self.lo, tuple(self.dims)))
        self.up = up
        self.size = float(np.linalg.norm(extent)) + 1.0

    def first_hit(self, origin, d, ts, escape=10):
        """Distance along each ray (origins (C, 3), directions (C, R, 3)) to the first solid voxel
        or the ground, sampled at `ts`; inf for none. Rays that start inside a part (a corner
        where two parts meet) and don't get out within `escape` samples are blocked at once;
        ones that do count only what they meet afterwards."""
        pts = origin[:, None, None, :] + d[:, :, None, :] * ts[None, None, :, None]  # (C, R, S, 3)
        idx = np.floor((pts - self.lo) / self.voxel).astype(np.int64)
        inside = np.all((idx >= 0) & (idx < self.dims), axis=-1)
        idx = np.clip(idx, 0, self.dims - 1)
        hit = (self.solid[idx[..., 0], idx[..., 1], idx[..., 2]] & inside) | (pts[..., self.up] < 0.0)
        k = np.arange(len(ts))
        free = np.where((~hit).any(axis=2), np.argmax(~hit, axis=2), len(ts))
        after = hit & (k[None, None, :] > free[..., None])
        first = np.where(after.any(axis=2), np.argmax(after, axis=2), len(ts))
        t = np.where(first < len(ts), ts[np.minimum(first, len(ts) - 1)], np.inf)
        return np.where(free > escape, 0.0, t)


def _unique_corners(tris, normals):
    """Corners at the same place with the same normal get the same answer: do each once."""
    flat_pos = tris.reshape(-1, 3)
    flat_nrm = _normalize(normals.reshape(-1, 3))
    key = np.concatenate([np.round(flat_pos / 1e-4), np.round(flat_nrm / 1e-3)], axis=1).astype(np.int64)
    _, first, inverse = np.unique(key, axis=0, return_index=True, return_inverse=True)
    return flat_pos[first], flat_nrm[first], inverse.reshape(-1)


def ambient_occlusion(vox, pos, nrm, distance=AO_DISTANCE, rays=AO_RAYS):
    """Ambient occlusion per corner (positions and normals (N, 3)): rays over the hemisphere,
    weighted by cosine, blocked by the model or the ground within `distance`."""
    # A frame round each normal, turned by a per-corner angle so the ray pattern doesn't band.
    helper = np.where(np.abs(nrm[:, 2:3]) < 0.9, np.array([[0.0, 0.0, 1.0]]), np.array([[1.0, 0.0, 0.0]]))
    t1 = _normalize(np.cross(nrm, helper))
    t2 = np.cross(nrm, t1)
    spin = np.mod(np.sin(pos @ np.array([12.9898, 78.233, 37.719])) * 43758.5453, 1.0) * 2.0 * math.pi
    c, s = np.cos(spin)[:, None], np.sin(spin)[:, None]
    t1, t2 = c * t1 + s * t2, -s * t1 + c * t2
    hemi = _hemisphere(rays)
    # Rays leave from a little above the surface, clear of the corner's own (grown) voxels even
    # when they set off almost along the surface.
    lift = vox.voxel * 2.5
    step = vox.voxel * 0.5
    ts = np.arange(0.0, distance + step, step)
    out = np.empty(len(pos))
    chunk = max(1, 400000 // (rays * len(ts)))
    for i0 in range(0, len(pos), chunk):
        p = pos[i0:i0 + chunk]
        n, a1, a2 = nrm[i0:i0 + chunk], t1[i0:i0 + chunk], t2[i0:i0 + chunk]
        d = (hemi[None, :, 0:1] * a1[:, None] + hemi[None, :, 1:2] * a2[:, None]
             + hemi[None, :, 2:3] * n[:, None])  # (C, R, 3)
        t = vox.first_hit(p + n * lift, d, ts)
        occl = np.where(t < distance, 1.0 - (t / distance) ** 2, 0.0)
        out[i0:i0 + chunk] = 1.0 - occl.mean(axis=1)
    return out


# A long face's corners can all sit where it meets something (a pipe barrel's end rings inside
# its flange and cap) and bake dark, though most of the face is open: the face then interpolates
# dark all along. Corners of faces longer than LONG_FACE tiles are lifted to at least LIFT times
# the occlusion at the face's middle.
LONG_FACE = 0.3
LIFT = 0.8


def lift_long_faces(vox, tris, ao):
    """ao (T, 3) per triangle corner, lifted on long faces (see LONG_FACE); returns a copy."""
    tris = np.asarray(tris, dtype=np.float64)
    e = np.stack([tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 1], tris[:, 0] - tris[:, 2]], axis=1)
    long = np.linalg.norm(e, axis=2).max(axis=1) > LONG_FACE
    out = np.array(ao, dtype=np.float64)
    if not long.any():
        return out
    t = tris[long]
    n = np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0])
    n = _normalize(n)
    mid = ambient_occlusion(vox, t.mean(axis=1), n)
    out[long] = np.maximum(out[long], LIFT * mid[:, None])
    return out


def projector_visibility(vox, pos, nrm, view):
    """How much of each corner Factorio's camera sees from direction `view` (unit vector from the
    model towards the camera): 1 where nothing is in the way, 0 where another part hides it or
    the face looks away. A few rays in a narrow cone soften the edges of the hidden areas."""
    view = _normalize(np.asarray(view, dtype=np.float64))
    helper = np.array([1.0, 0.0, 0.0]) if abs(view[2]) > 0.9 else np.array([0.0, 0.0, 1.0])
    a = _normalize(np.cross(view, helper))
    b = np.cross(view, a)
    spread = math.tan(math.radians(2.5))
    dirs = _normalize(np.array([view, view + a * spread, view - a * spread, view + b * spread, view - b * spread]))
    step = vox.voxel
    ts = np.arange(0.0, vox.size + step, step)
    lift = vox.voxel * 2.5
    out = np.empty(len(pos))
    chunk = max(1, 400000 // (len(dirs) * len(ts)))
    for i0 in range(0, len(pos), chunk):
        p, n = pos[i0:i0 + chunk], nrm[i0:i0 + chunk]
        d = np.broadcast_to(dirs[None], (len(p), len(dirs), 3))
        t = vox.first_hit(p + n * lift, d, ts, escape=4)
        out[i0:i0 + chunk] = np.isinf(t).mean(axis=1)
    return np.where(nrm @ view > 0.0, out, 0.0)


def factorio_views(pitch=48.0, up=2):
    """Directions towards Factorio's camera (orthographic, looking north and down at `pitch`) in
    model space, for an entity facing north, east, south and west: a model turned to face east
    sees the camera off its right side. Blender axes (up=2: x east, y north, z up) or glTF and
    Godot ones (up=1: x east, y up, z south)."""
    p = math.radians(pitch)
    out = []
    for d in range(4):
        a = math.radians(90.0 * d)
        x, y = math.cos(p) * math.sin(a), -math.cos(p) * math.cos(a)
        out.append((x, y, math.sin(p)) if up == 2 else (x, math.sin(p), -y))
    return out


# ---------------------------------------------------------------------------------------------

def bake(tris, normals, up=2, width=None, views=None):
    """Everything the shader needs, per corner of each triangle.

    tris, normals: (T, 3, 3) arrays of corner positions and normals in model space (tiles, ground
    at height 0 along axis `up`). width: optional (T,) width of the polygon each triangle came
    from (see edge_wear). views: directions towards the sprite projector (factorio_views()).
    Returns ao (T, 3), edge (T, 3), part (T,) and vis (T, 3, len(views)), all in [0, 1]."""
    tris = np.asarray(tris, dtype=np.float64)
    normals = np.asarray(normals, dtype=np.float64)
    vid = weld(tris.reshape(-1, 3)).reshape(-1, 3)
    vox = _Voxels(tris, up)
    pos, nrm, inverse = _unique_corners(tris, normals)
    ao = ambient_occlusion(vox, pos, nrm)[inverse].reshape(-1, 3)
    ao = lift_long_faces(vox, tris, ao)
    vis = [projector_visibility(vox, pos, nrm, v)[inverse].reshape(-1, 3) for v in (views or [])]
    vis = np.stack(vis, axis=2) if vis else np.zeros(tris.shape[:2] + (0,))
    edge = edge_wear(tris, vid, width)
    part = part_random(tris, components(vid))
    return ao, edge, part, vis


def polygon_width(points):
    """Area over longest side of a planar polygon (list of 3D points): a bevel strip's width."""
    p = np.asarray(points, dtype=np.float64)
    area = 0.5 * np.linalg.norm(sum(np.cross(p[i], p[(i + 1) % len(p)]) for i in range(len(p))))
    longest = max(np.linalg.norm(p[(i + 1) % len(p)] - p[i]) for i in range(len(p)))
    return area / max(longest, 1e-9)


# ---------------------------------------------------------------------------------------------
# Blender: bake into mesh objects before glTF export. Imported lazily so plain Python can use
# the functions above.

COLOR_ATTRIBUTE = "Color"
UV_MAPS = ("UVMap", "Data", "ViewNE", "ViewSW")
WIDTH_ATTRIBUTE = "bake_width"


def bake_blender_objects(objects, keep_rgb=False):
    """Bakes everything into each mesh object in `objects` (all together, so parts occlude one
    another), in world space with Blender's z up:

    - corner colour attribute COLOR_ATTRIBUTE: rgb kept (keep_rgb, the nature models' shading) or
      white, alpha = ao. Made the active and render colour, so the exporter writes it as COLOR_0.
    - UV maps after the planar one (TEXCOORD_0): "Data" = (edge, part) as TEXCOORD_1, "ViewNE" =
      projector visibility facing north and east as TEXCOORD_2, "ViewSW" = south and west as
      TEXCOORD_3.

    A face float attribute WIDTH_ATTRIBUTE (set before triangulating, see kit.part_to_object)
    gives each face its polygon's width; without it, each polygon's own width is used."""
    import bpy  # noqa: F401  (only to fail early outside Blender)

    tris_all, nrm_all, width_all, spans = [], [], [], []
    for obj in objects:
        mesh = obj.data
        mesh.calc_loop_triangles()
        mw = np.array(obj.matrix_world)
        rot = mw[:3, :3]
        nl = len(mesh.loops)
        co = np.empty(len(mesh.vertices) * 3)
        mesh.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3) @ rot.T + mw[:3, 3]
        loop_vert = np.empty(nl, dtype=np.int64)
        mesh.loops.foreach_get("vertex_index", loop_vert)
        cn = np.empty(nl * 3)
        mesh.corner_normals.foreach_get("vector", cn)
        cn = _normalize(cn.reshape(-1, 3) @ rot.T)
        lt = mesh.loop_triangles
        tri_loops = np.empty(len(lt) * 3, dtype=np.int64)
        lt.foreach_get("loops", tri_loops)
        tri_loops = tri_loops.reshape(-1, 3)
        tri_poly = np.empty(len(lt), dtype=np.int64)
        lt.foreach_get("polygon_index", tri_poly)
        attr = mesh.attributes.get(WIDTH_ATTRIBUTE)
        if attr is not None and attr.domain == "FACE":
            poly_width = np.empty(len(mesh.polygons))
            attr.data.foreach_get("value", poly_width)
        else:
            poly_width = np.array([polygon_width([co[loop_vert[i]] for i in p.loop_indices]) for p in mesh.polygons])
        tris_all.append(co[loop_vert[tri_loops]])
        nrm_all.append(cn[tri_loops])
        width_all.append(poly_width[tri_poly])
        spans.append((obj, tri_loops))
    if not tris_all:
        return
    ao, edge, part, vis = bake(np.concatenate(tris_all), np.concatenate(nrm_all), up=2,
                               width=np.concatenate(width_all), views=factorio_views(up=2))

    t0 = 0
    for obj, tri_loops in spans:
        mesh = obj.data
        n = len(tri_loops)
        nl = len(mesh.loops)
        flat = tri_loops.reshape(-1)

        def per_loop(values, default):
            out = np.full(nl, default, dtype=np.float64)
            out[flat] = values[t0:t0 + n].reshape(-1)
            return out

        loop_ao = per_loop(ao, 1.0)
        loop_edge = per_loop(edge, 0.0)
        loop_part = per_loop(np.repeat(part[:, None], 3, axis=1), 0.0)
        loop_vis = [per_loop(vis[..., k], 0.0) for k in range(4)]
        t0 += n

        rgb = np.ones((nl, 3))
        old = mesh.color_attributes.get(COLOR_ATTRIBUTE)
        if old is not None:
            if keep_rgb and old.domain == "CORNER":
                buf = np.empty(nl * 4)
                old.data.foreach_get("color", buf)  # linear, whatever the storage type
                rgb = buf.reshape(-1, 4)[:, :3]
            mesh.color_attributes.remove(old)
        col = mesh.color_attributes.new(COLOR_ATTRIBUTE, "FLOAT_COLOR", "CORNER")
        col.data.foreach_set("color", np.concatenate([rgb, loop_ao[:, None]], axis=1).reshape(-1))
        mesh.color_attributes.active_color = col
        mesh.color_attributes.render_color_index = mesh.color_attributes.active_color_index
        if len(mesh.uv_layers) == 0:
            mesh.uv_layers.new(name=UV_MAPS[0])
        for name, (u, v) in zip(UV_MAPS[1:], ((loop_edge, loop_part), (loop_vis[0], loop_vis[1]),
                                              (loop_vis[2], loop_vis[3]))):
            uv = mesh.uv_layers.new(name=name)
            # The glTF exporter writes Blender's v as 1 - v; store it flipped so the file has v.
            uv.data.foreach_set("uv", np.stack([u, 1.0 - v], axis=1).reshape(-1))
        if mesh.attributes.get(WIDTH_ATTRIBUTE) is not None:
            mesh.attributes.remove(mesh.attributes[WIDTH_ATTRIBUTE])
