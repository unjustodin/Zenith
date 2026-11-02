"""Rigs creature models converted from Wube's printable files (tools/models/wube.py) for the
client's animation.

The print files are statues: one pose each (walking, attacking, dead), every limb fused to the
body. The client animates limbs in the vertex shader (factorio_material.gdshaderinc, `rig_*`):
each vertex knows which limb it belongs to and how much it follows it, and the limb turns about
its joint. One mesh per model, so a screen full of biters is still one MultiMesh, and the joints
never tear: a vertex follows its limb from 0 at the joint to fully a little way out.

Per vertex, in TEXCOORD_0 (UV, which the material doesn't otherwise use): x = limb number
(1-12, 0 for the body), y = how much it follows the limb (0-1). Per limb, in
client/data/creature_rigs.json: the joint, the axis it swings about, the axis that lifts it, and
its gait (phase, swing, lift, pulse); see client/scripts/world/creature_models.gd.

A recipe asks for this with `"rig": {...}` (wube_recipes.py):

- `"limbs"`: {name: [joint, knee..., tip], ...} polylines in model space (tiles, glTF axes, the
  model facing north); `"body"`: polylines for the body. Every vertex goes to the nearest
  polyline. Names say what a limb is: `leg_*`, `arm_*` (jaws, a character's arms), `seg_*`
  (a worm's body), `sac_*` (a spawner's pulsing sacs).
- `"gait"`: {name: (phase offset in turns, swing degrees, lift degrees, pulse)}; `"swing"` /
  `"lift"`: {name: axis} override the default axes (swing about up and lift square to the limb
  for limbs that splay sideways; swing east-west for limbs that hang down, like a character's).
- `"soft"`: (start, end) tiles from the joint over which a vertex comes to follow its limb fully.
- `"mode"`: "walk" (the client drives the gait from the creature's speed) or "idle" (the shader
  runs it on its own, for worms and spawners, `"rate"` cycles a second).
- `"decimate": "blender"`: decimate in Blender (wube.decimate_all) instead of the plain-Python
  simplifier.
- `"material"`: the material that is rigged (others, like a shell, stay with the body);
  `"materials"`: {limb name prefix: palette material} recolours limbs (biter legs are paler).
"""

import json
import os

import numpy as np

try:
    import wube
except ImportError:
    # Inside Blender (no trimesh): models built there (mech_armor.py) use only skin_weights and
    # the rig table's writer.
    wube = None

MAX_LIMBS = 12
RIGS_JSON = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
                         "client", "data", "creature_rigs.json")


def _polyline_distance(points, line):
    line = np.asarray(line, dtype=float)
    best = np.full(len(points), np.inf)
    for a, b in zip(line[:-1], line[1:]):
        ab = b - a
        t = np.clip(((points - a) @ ab) / max(ab @ ab, 1e-12), 0.0, 1.0)
        best = np.minimum(best, np.linalg.norm(points - (a + t[:, None] * ab), axis=1))
    return best


def assign(vertices, spec):
    """(limb index per vertex, -1 for the body; follow weight per vertex)."""
    names = list(spec["limbs"])
    lines = [spec["limbs"][n] for n in names] + list(spec.get("body", []))
    dist = np.column_stack([_polyline_distance(vertices, line) for line in lines])
    nearest = dist.argmin(axis=1)
    limb = np.where(nearest < len(names), nearest, -1)
    start, end = spec.get("soft", (0.03, 0.18))
    weight = np.zeros(len(vertices))
    for i, n in enumerate(names):
        mine = limb == i
        joint = np.asarray(spec["limbs"][n][0], dtype=float)
        d = np.linalg.norm(vertices[mine] - joint, axis=1)
        t = np.clip((d - start) / max(end - start, 1e-6), 0.0, 1.0)
        weight[mine] = t * t * (3 - 2 * t)
    return limb, weight


# --- Finding limbs automatically ------------------------------------------------------------
#
# For spindly creatures (biters, spitters) the limbs are found rather than drawn: take away the
# body (`"core"`: ellipsoids ((cx, cy, cz), (rx, ry, rz))), and in what is left find the tips
# (the points furthest along the surface from where each piece meets the body); every triangle
# belongs to the tip nearest to it along the surface, so legs that touch at the knee stay apart.


def _ellipsoids(points, shapes):
    inside = np.zeros(len(points), bool)
    for centre, radii in shapes:
        d = (points - np.asarray(centre, dtype=float)) / np.asarray(radii, dtype=float)
        inside |= (d * d).sum(axis=1) <= 1.0
    return inside


def _face_graph(mesh, allowed):
    from scipy.sparse import coo_matrix
    adj = mesh.face_adjacency
    keep = allowed[adj[:, 0]] & allowed[adj[:, 1]]
    a, b = adj[keep, 0], adj[keep, 1]
    c = mesh.triangles_center
    w = np.linalg.norm(c[a] - c[b], axis=1) + 1e-6
    n = len(mesh.faces)
    return coo_matrix((np.concatenate([w, w]), (np.concatenate([a, b]), np.concatenate([b, a]))), shape=(n, n)).tocsr()


def find_limbs(mesh, spec):
    """Face labels (-1 body, else limb index) and limb polylines {name: [joint, tip]}."""
    from scipy.sparse.csgraph import connected_components, dijkstra
    centres = mesh.triangles_center
    core = _ellipsoids(centres, spec["core"])
    graph = _face_graph(mesh, ~core)
    _n, comp = connected_components(graph, directed=False)
    adj = mesh.face_adjacency
    touch = np.zeros(len(mesh.faces), bool)
    edge = core[adj[:, 0]] != core[adj[:, 1]]
    touch[adj[edge].reshape(-1)] = True
    touch &= ~core
    height = mesh.bounds[1][1] - mesh.bounds[0][1]
    reach_min = spec.get("reach", 0.2)
    labels = np.full(len(mesh.faces), -1)
    found = []  # [joint, tip, faces]
    for c in np.unique(comp[~core]):
        faces = np.nonzero((comp == c) & ~core)[0]
        if len(faces) < spec.get("min_faces", 40):
            continue
        hips = faces[touch[faces]]
        if len(hips) == 0:
            continue
        from_hip = dijkstra(graph, directed=False, indices=hips, min_only=True)
        d = from_hip[faces]
        tips = []
        alive = np.isfinite(d)
        while alive.any():
            k = np.argmax(np.where(alive, d, -1))
            if d[k] < reach_min:
                break
            tip = faces[k]
            tips.append(tip)
            from_tip = dijkstra(graph, directed=False, indices=tip)[faces]
            # Everything nearer this tip than to the body is its limb.
            alive &= ~(from_tip < spec.get("tip_claim", 1.2) * d)
        if not tips:
            continue
        if spec.get("debug"):
            print("piece %d faces, %d tips, reach %s" % (len(faces), len(tips), np.round(d[np.isin(faces, tips)], 2)))
        dist = np.column_stack([dijkstra(graph, directed=False, indices=t)[faces] for t in tips])
        owner = dist.argmin(axis=1)
        for i, tip in enumerate(tips):
            mine = faces[owner == i]
            if len(mine) < spec.get("min_faces", 40) or len(mine) > spec.get("max_faces", 10 ** 9):
                continue
            near = mine[np.argmin(from_hip[mine])]
            found.append([centres[near], centres[tip], mine])
    centre_x = spec.get("centre_x", 0.0)
    limbs = {}
    for kind in ("leg", "arm"):
        for side in ("l", "r"):
            mine = [f for f in found if (f[0][0] > centre_x) == (side == "r")
                    and (f[1][1] < mesh.bounds[0][1] + spec.get("ground", 0.3) * height) == (kind == "leg")]
            if kind == "arm" and spec.get("legs_only"):
                continue
            # At most `per_side` limbs a side (the shader takes 12): the biggest.
            mine = sorted(mine, key=lambda f: -len(f[2]))[:spec.get("per_side", 10)]
            for i, (joint, tip, faces) in enumerate(sorted(mine, key=lambda f: f[0][2])):
                name = "%s_%s%s" % (kind, side, "abcdefghij"[i])
                labels[faces] = len(limbs)
                limbs[name] = [[round(float(v), 4) for v in joint], [round(float(v), 4) for v in tip]]
    return labels, limbs


def vertex_labels(mesh, face_labels):
    out = np.full(len(mesh.vertices), -1)
    order = np.argsort(face_labels)  # limbs win over the body where they meet
    for k in range(3):
        out[mesh.faces[order, k]] = face_labels[order]
    return out


def weights(vertices, labels, limbs, spec):
    start, end = spec.get("soft", (0.03, 0.18))
    w = np.zeros(len(vertices))
    for i, line in enumerate(limbs.values()):
        mine = labels == i
        d = np.linalg.norm(vertices[mine] - np.asarray(line[0], dtype=float), axis=1)
        t = np.clip((d - start) / max(end - start, 1e-6), 0.0, 1.0)
        w[mine] = t * t * (3 - 2 * t)
    return w


def limb_table(spec):
    """Per limb: joint, swing axis, lift axis, gait (phase radians, swing, lift radians, pulse)."""
    out = []
    for n, line in spec["limbs"].items():
        line = np.asarray(line, dtype=float)
        joint, tip = line[0], line[-1]
        reach = tip - joint
        flat = np.array([reach[0], 0.0, reach[2]])
        hangs = np.linalg.norm(flat) < 0.5 * abs(reach[1])
        swing = np.array(spec.get("swing", {}).get(n, (1.0, 0.0, 0.0) if hangs else (0.0, 1.0, 0.0)), dtype=float)
        if hangs:
            lift = np.array([0.0, 0.0, 1.0])
        else:
            # Turning about this raises the tip: horizontal, square to the limb.
            lift = np.cross(flat / max(np.linalg.norm(flat), 1e-9), [0.0, 1.0, 0.0])
        lift = np.array(spec.get("lift", {}).get(n, lift), dtype=float)
        phase, sw, li, pulse = spec.get("gait", {}).get(n, (0.0, 0.0, 0.0, 0.0))
        out.append({"name": n, "joint": [round(float(c), 4) for c in joint],
                    "swing": [round(float(c), 4) for c in swing / np.linalg.norm(swing)],
                    "lift": [round(float(c), 4) for c in lift / max(np.linalg.norm(lift), 1e-9)],
                    "gait": [round(phase * 2 * np.pi, 4), round(float(np.radians(sw)), 4),
                             round(float(np.radians(li)), 4), pulse]})
    return out


def limb_material(name, spec, default):
    best, best_len = default, -1
    for prefix, material in spec.get("materials", {}).items():
        if name.startswith(prefix) and len(prefix) > best_len:
            best, best_len = material, len(prefix)
    return best


def limbs_from_hips(mesh, spec):
    """Face labels and limb polylines from hand-placed marks: `"hips"`: {name: (x, y, z)} where
    each limb joins the body, and `"seeds"`: {name: (x, z)} a point over the limb's middle, seen
    from above, where it is clear of the others. Take away the body (`"core"`); every triangle left
    belongs to the seed nearest to it along the surface, so a leg is followed all the way to its
    foot even where it touches another at the knee. Pieces no seed reaches go to the nearest one."""
    from scipy.sparse.csgraph import connected_components, dijkstra
    centres = mesh.triangles_center
    core = _ellipsoids(centres, spec["core"])
    graph = _face_graph(mesh, ~core)
    _n, comp = connected_components(graph, directed=False)
    sizes = np.bincount(comp[~core], minlength=comp.max() + 1)
    # Seeds go on pieces big enough to be limbs, not on scraps the body's edge cut off.
    outside = np.nonzero(~core & (sizes[comp] >= spec.get("min_faces", 150)))[0]
    names = list(spec["hips"])
    seeds = spec.get("seeds", {})
    dists, seed_faces = [], []
    for n in names:
        if n in seeds:
            at = np.asarray(seeds[n], dtype=float)
            seed = outside[np.argmin(np.linalg.norm(centres[outside][:, [0, 2]] - at, axis=1))]
        else:
            hip = np.asarray(spec["hips"][n], dtype=float)
            seed = outside[np.argmin(np.linalg.norm(centres[outside] - hip, axis=1))]
        seed_faces.append(seed)
        dists.append(dijkstra(graph, directed=False, indices=seed))
    dists = np.column_stack(dists)
    owner = dists.argmin(axis=1)
    reached = np.isfinite(dists.min(axis=1))
    labels = np.where(reached & ~core, owner, -1)
    for k in np.unique(comp[~core & ~reached]):
        piece = np.nonzero((comp == k) & ~core)[0]
        if len(piece) < spec.get("min_faces", 150) // 3:
            continue
        gap = [np.linalg.norm(centres[piece] - centres[f], axis=1).min() for f in seed_faces]
        labels[piece] = int(np.argmin(gap))
    limbs = {}
    for i, n in enumerate(names):
        mine = np.nonzero(labels == i)[0]
        hip = np.asarray(spec["hips"][n], dtype=float)
        if len(mine) == 0:
            limbs[n] = [hip.round(4).tolist(), hip.round(4).tolist()]
            continue
        tip = centres[mine[np.argmax(np.linalg.norm(centres[mine] - hip, axis=1))]]
        limbs[n] = [hip.round(4).tolist(), [round(float(v), 4) for v in tip]]
    return labels, limbs


# `"long_legs"`: the print's legs are folded under the body, where the sprite's are long and
# splayed. The print's legs are replaced by plain two-segment legs, hip to knee to foot, one per
# limb at its hip: {pair letter: (knee out, knee forward, knee up, foot out, foot forward)} in
# tiles, measured from the hip in the built model's frame (after `scale`; out is away from the
# body's middle, forward is north). `"body"`: (scale, raise): the body and shell are scaled about
# the hips' middle and lifted, so the legs carry it at the sprite's height. `"leg_radius"`:
# (thigh, shin at the knee, shin at the foot).

def _body_moved(v, spec):
    scale, lift = spec["long_legs_body"]
    c = np.asarray(spec["long_legs_centre"], dtype=float)
    return c + (np.asarray(v, dtype=float) - c) * scale + np.array([0.0, lift, 0.0])


def _segment(a, b, r0, r1, sections=8):
    """A tapered tube from a to b (radii r0, r1), closed at both ends."""
    import trimesh
    a, b = np.asarray(a, float), np.asarray(b, float)
    d = b - a
    length = np.linalg.norm(d)
    ring = np.linspace(0, 2 * np.pi, sections, endpoint=False)
    unit = np.column_stack([np.cos(ring), np.sin(ring), np.zeros(sections)])
    verts = np.vstack([unit * r0, unit * r1 + [0, 0, length], [[0, 0, 0], [0, 0, length]]])
    faces = []
    for i in range(sections):
        j = (i + 1) % sections
        faces += [[i, j, sections + j], [i, sections + j, sections + i],
                   [2 * sections, j, i], [2 * sections + 1, sections + i, sections + j]]
    m = trimesh.Trimesh(verts, np.array(faces), process=False)
    z = d / length
    x = np.cross([0.0, 1.0, 0.0], z)
    x = x / np.linalg.norm(x) if np.linalg.norm(x) > 1e-6 else np.array([1.0, 0.0, 0.0])
    y = np.cross(z, x)
    t = np.eye(4)
    t[:3, 0], t[:3, 1], t[:3, 2], t[:3, 3] = x, y, z, a
    m.apply_transform(t)
    return m


def long_legs(mesh, flabels, limbs, spec):
    """The body without the print's legs, moved by `long_legs_body`, plus new legs (see above)."""
    import trimesh
    body = mesh.submesh([np.nonzero(flabels < 0)[0]], append=True, repair=False)
    body.vertices = _body_moved(body.vertices, spec)
    r_thigh, r_knee, r_foot = spec.get("leg_radius", (0.06, 0.05, 0.025))
    pieces, labels, out = [body], [np.full(len(body.faces), -1)], {}
    for i, name in enumerate(limbs):
        hip = _body_moved([spec["hips"][name]], spec)[0]
        side = -1.0 if name[4] == "l" else 1.0
        ko, kf, ku, fo, ff = spec["long_legs"][name[5]]
        knee = hip + np.array([side * ko, ku, -kf])
        foot = np.array([hip[0] + side * fo, 0.0, hip[2] - ff])
        leg = trimesh.util.concatenate([
            trimesh.creation.icosphere(subdivisions=1, radius=r_thigh * 1.1).apply_translation(hip),
            _segment(hip, knee, r_thigh, r_knee),
            trimesh.creation.icosphere(subdivisions=1, radius=r_knee * 1.15).apply_translation(knee),
            _segment(knee, foot, r_knee, r_foot)])
        pieces.append(leg)
        labels.append(np.full(len(leg.faces), i))
        out[name] = [hip.round(4).tolist(), foot.round(4).tolist()]
    return trimesh.util.concatenate(pieces), np.concatenate(labels), out


def label_mesh(mesh, spec):
    """(face labels: -1 body, else limb index; {limb name: polyline})."""
    if "hips" in spec:
        return limbs_from_hips(mesh, spec)
    if "core" in spec:
        return find_limbs(mesh, spec)
    limb, _w = assign(mesh.triangles_center, spec)
    return limb, spec["limbs"]


def zone_materials(mesh, mats, spec):
    """`"zones"`: [(material, zone), ...] recolours the triangles in a zone, last match wins (a
    spawner's dirt skirt, its paler dome). A zone is ("below", y), an ellipsoid
    ((cx, cy, cz), (rx, ry, rz)) or ("rule", fn(centres, normals) -> bool per face), in the model's
    frame after scaling."""
    centres = mesh.triangles_center
    mats = mats.astype(object)
    for material, zone in spec.get("zones", []):
        if zone[0] == "rule":
            inside = np.asarray(zone[1](centres, mesh.face_normals), dtype=bool)
        elif zone[0] == "below":
            inside = centres[:, 1] < zone[1]
        else:
            inside = _ellipsoids(centres, [zone])
        mats[inside] = material
    return mats


def default_gait(limbs, spec):
    """Legs walk in two alternating tripods (front and back legs of one side with the middle leg
    of the other); arms (jaws) keep still while walking."""
    gait = {}
    swing, lift = spec.get("leg_swing", 22.0), spec.get("leg_lift", 18.0)
    for n in limbs:
        kind, rest = n.split("_", 1)
        if kind == "leg" and len(rest) == 2 and rest[1] in "abcdefghij":
            order = "abcdefghij".index(rest[1])
            gait[n] = (0.5 * ((order + (rest[0] == "r")) % 2), swing, lift, 0.0)
    gait.update(spec.get("gait", {}))
    return gait


def scaled_spec(spec, k):
    """The rig's marks are given in the print's frame (before the recipe's `scale`)."""
    out = dict(spec)
    if k == 1.0:
        return out
    if "core" in spec:
        out["core"] = [(tuple(c * k for c in centre), tuple(r * k for r in radii)) for centre, radii in spec["core"]]
    for key in ("hips", "seeds"):
        if key in spec:
            out[key] = {n: tuple(c * k for c in v) for n, v in spec[key].items()}
    for key in ("limbs",):
        if key in spec:
            out[key] = {n: [tuple(c * k for c in p) for p in line] for n, line in spec[key].items()}
    if "body" in spec:
        out["body"] = [[tuple(c * k for c in p) for p in line] for line in spec["body"]]
    start, end = spec.get("soft", (0.03, 0.18))
    out["soft"] = (start * k, end * k)
    if "zones" in spec:
        out["zones"] = [(m, z if z[0] == "rule" else ("below", z[1] * k) if z[0] == "below"
                         else (tuple(c * k for c in z[0]), tuple(r * k for r in z[1])))
                        for m, z in spec["zones"]]
    return out


def build_rigged(name, recipe, merged, budget, out_path, palette, alpha, copyright_text):
    """wube.build's last step for a rigged recipe: decimate, find the limbs, recolour them, write
    the limb data into TEXCOORD_0 and the limb table into creature_rigs.json. Returns the
    triangle count."""
    spec = scaled_spec(recipe["rig"], recipe.get("scale", 1.0))
    rigged = spec.get("material")
    total_area = sum(mesh.area for _, mesh in merged) or 1.0
    groups, limb_uv = [], []
    limbs = None
    targets = [max(12, int(budget * 0.97 * mesh.area / total_area)) for _, mesh in merged]
    if spec.get("decimate") == "blender":
        # Blender's decimator keeps thin plates (the character's tools) as plates, where the
        # plain-Python one leaves them as spikes.
        meshes = wube.decimate_all([(mesh, n) for (_, mesh), n in zip(merged, targets)])
    else:
        meshes = [wube.decimate(mesh, n) for (_, mesh), n in zip(merged, targets)]
    for (material, _), mesh in zip(merged, meshes):
        if rigged not in (None, material):
            if "long_legs" in spec:
                mesh = mesh.copy()
                mesh.vertices = _body_moved(mesh.vertices, spec)
            groups.append((material, wube.shaded(mesh)))
            limb_uv.append(np.zeros((len(groups[-1][1].vertices), 2)))
            continue
        flabels, limbs = label_mesh(mesh, spec)
        if "long_legs" in spec:
            mesh, flabels, limbs = long_legs(mesh, flabels, limbs, spec)
        if len(limbs) > MAX_LIMBS:
            raise ValueError("%s: %d limbs, the shader takes %d" % (name, len(limbs), MAX_LIMBS))
        names = list(limbs)
        mats = np.array([material if i < 0 else limb_material(names[i], spec, material) for i in flabels])
        mats = zone_materials(mesh, mats, spec)
        # Labels and weights belong to positions: the copies of a vertex that shading and
        # material boundaries split apart must move together, or the creature tears open there.
        from scipy.spatial import cKDTree
        vl_all = vertex_labels(mesh, flabels)
        w_all = weights(mesh.vertices, vl_all, limbs, spec)
        tree = cKDTree(mesh.vertices)
        for m in dict.fromkeys(mats.tolist()):
            faces = np.nonzero(mats == m)[0]
            sub = mesh.submesh([faces], append=True, repair=False)
            shaded = wube.shaded(sub)
            assert len(shaded.faces) == len(faces)
            _d, near = tree.query(shaded.vertices)
            vl, w = vl_all[near], w_all[near]
            groups.append((m, shaded))
            limb_uv.append(np.column_stack([vl + 1.0, np.where(vl >= 0, w, 0.0)]))
    wube.write_glb(out_path, groups, palette, alpha, copyright_text, uv0=limb_uv)
    spec["limbs"] = limbs or {}
    spec["gait"] = default_gait(spec["limbs"], spec)
    write_rig_table(name, spec)
    return sum(len(m.faces) for _, m in groups)


# --- Skinned rigs ---------------------------------------------------------------------------
#
# The character needs more than limbs swinging about one joint each: knees and elbows bend, the
# spine leans, the head turns, and its arms hold a pickaxe or a gun out in front. A recipe with
# `"skin": {...}` gets a small skeleton instead: every vertex follows up to two bones, blended by
# how near it is to each, so the surface stretches across a joint instead of tearing open there.
# The weights are a function of position alone, so the copies of a vertex that smooth shading
# and material boundaries split apart always move together (the old rig's holes came from those
# copies following different limbs).
#
# Per vertex, in TEXCOORD_0: x = bone a + 16 * bone b, y = a's weight (b gets the rest). The
# client poses the bones on the CPU (client/scripts/player/character_pose.gd) and hands the
# material each bone's matrix (rig_mode 3, factorio_material.gdshaderinc).
#
# `"bones"`: [(name, parent or None, head, tail, radius), ...], index 0 the root. A bone turns
# about its head; a vertex's distance to a bone is measured to the segment head-tail, divided by
# its radius (a number, or (rx, ry, rz) for a flattened one like the chest). `"fixed"`:
# {material: bone} for parts that follow one bone rigidly (the backpack). `"penalty"`:
# fn(vertices) -> {bone: extra distance per vertex}, smooth in position, keeps a bone off
# surfaces it happens to be near (a hanging hand off the thigh beside it). `"band"`: how far
# (in radius units) the blend between two bones reaches.

def skin_weights(vertices, bones, penalty=None, band=0.5):
    """(bone a, bone b, weight of a) per vertex."""
    v = np.asarray(vertices, dtype=float)
    d = np.empty((len(v), len(bones)))
    for i, (_name, _parent, head, tail, radius) in enumerate(bones):
        head, tail = np.asarray(head, dtype=float), np.asarray(tail, dtype=float)
        ab = tail - head
        t = np.clip(((v - head) @ ab) / max(ab @ ab, 1e-12), 0.0, 1.0)
        off = v - (head + t[:, None] * ab)
        d[:, i] = np.linalg.norm(off / np.asarray(radius, dtype=float), axis=1)
    if penalty is not None:
        index = {b[0]: i for i, b in enumerate(bones)}
        for name, extra in penalty(v).items():
            d[:, index[name]] += extra
    order = np.argsort(d, axis=1)
    a, b = order[:, 0], order[:, 1]
    rows = np.arange(len(v))
    t = np.clip((d[rows, b] - d[rows, a]) / band, 0.0, 1.0)
    return a, b, 0.5 + 0.5 * t * t * (3 - 2 * t)


def separate(mesh, a, b, w, groups, region):
    """Cuts a fused print apart where two groups of bones meet inside `region` (fn(points) ->
    bool): the triangles that span from one group to the other are taken out and each hole left
    is closed with a fan, so a hand resting on the hip comes away from it whole instead of
    pulling a sheet of skin along. Returns (mesh, a, b, w) with the caps' vertices weighted like
    their rims."""
    import trimesh
    owner = np.zeros(len(mesh.vertices))
    for k, group in enumerate(groups):
        member = np.isin(a, group) * w + np.isin(b, group) * (1.0 - w)
        owner += k * member
    # Inside the region every vertex goes wholly to the side it mostly follows, and the
    # triangles between the sides go.
    inside = region(mesh.vertices)
    arm = owner > 0.5
    a, b, w = a.copy(), b.copy(), w.copy()
    for k, group in enumerate(groups):
        mine = inside & (arm == (k == 1))
        a_in, b_in = np.isin(a, group), np.isin(b, group)
        # Blends within a side (knee, elbow) stay; a blend across the sides goes to this side's bone.
        only_a = mine & a_in & ~b_in
        only_b = mine & b_in & ~a_in
        b[only_a] = a[only_a]
        w[only_a] = 1.0
        a[only_b] = b[only_b]
        w[only_b] = 1.0
    f = mesh.faces
    cut = (arm[f].any(axis=1) != arm[f].all(axis=1)) & inside[f].all(axis=1)
    if not cut.any():
        return mesh, a, b, w
    keep = f[~cut]
    # Boundary edges of the kept faces that the cut opened (edges used once now, twice before).
    def edge_counts(faces):
        e = np.sort(faces[:, [0, 1, 1, 2, 2, 0]].reshape(-1, 2), axis=1)
        u, c = np.unique(e, axis=0, return_counts=True)
        return {tuple(x): n for x, n in zip(u, c)}
    before, after = edge_counts(f), edge_counts(keep)
    # Directed rim edges, as the caps run them (the other way round from the kept faces). A rim
    # vertex can sit on two holes (where they touch), so rims are walked edge by edge.
    out_edges = {}
    for tri in keep:
        for i in range(3):
            u, v = int(tri[i]), int(tri[(i + 1) % 3])
            key = (min(u, v), max(u, v))
            if after.get(key) == 1 and before.get(key) == 2:
                out_edges.setdefault(v, []).append(u)
    loops = []
    for start in list(out_edges):
        while out_edges.get(start):
            # Walk until the path comes back on itself; the stretch since then is one hole.
            path, at = [start], {start: 0}
            while True:
                nexts = out_edges.get(path[-1])
                if not nexts:
                    break  # back at the start with nothing left, or an open rim: nothing to close
                v = nexts.pop()
                if v in at:
                    k = at[v]
                    loops.append(path[k:])
                    for x in path[k + 1:]:
                        del at[x]
                    path = path[:k + 1]
                    continue
                at[v] = len(path)
                path.append(v)
    verts = list(mesh.vertices)
    a, b, w = list(a), list(b), list(w)
    caps = []
    holes = 0
    for loop in loops:
        if len(loop) < 3:
            continue
        holes += 1
        # A rim that runs along both sides (where the print's surfaces overlap) is closed in
        # pieces, one fan per stretch of one side, so no cap reaches across. Each stretch takes
        # the next one's first vertex too, so the rim edges between the sides are closed as well.
        side = owner[loop] > 0.5
        if side.all() or not side.any():
            runs = [loop]
        else:
            k0 = int(np.nonzero(side != np.roll(side, 1))[0][0])
            turned = loop[k0:] + loop[:k0]
            runs, run = [], [turned[0]]
            for prev, v in zip(turned[:-1], turned[1:]):
                run.append(v)
                if (owner[v] > 0.5) != (owner[prev] > 0.5):
                    runs.append(run)
                    run = [v]
            run.append(turned[0])
            runs.append(run)
            # A stretch of one vertex makes no fan: it joins the stretch before it.
            merged = []
            for run in runs:
                if merged and len(run) < 3:
                    merged[-1] = merged[-1] + run[1:]
                else:
                    merged.append(run)
            if len(merged) > 1 and len(merged[0]) < 3:
                merged[-1] = merged[-1] + merged.pop(0)[1:]
            runs = merged
            if len(runs) == 1:
                runs = [runs[0][:-1]]  # all one stretch again: the whole loop
        for run in runs:
            if len(run) < 3:
                continue
            c = len(verts)
            centre = mesh.vertices[run].mean(axis=0)
            verts.append(centre)
            j = run[int(np.argmin(np.linalg.norm(mesh.vertices[run] - centre, axis=1)))]
            a.append(a[j]); b.append(b[j]); w.append(w[j])
            for i in range(len(run)):
                caps.append([run[i], run[(i + 1) % len(run)], c])
    faces = np.vstack([keep, np.asarray(caps, dtype=keep.dtype).reshape(-1, 3)])
    out = trimesh.Trimesh(np.asarray(verts), faces, process=False)
    print("  separated: %d triangles cut, %d holes capped" % (int(cut.sum()), holes))
    return out, np.asarray(a), np.asarray(b), np.asarray(w)


def build_skinned(name, recipe, merged, budget, out_path, palette, alpha, copyright_text):
    """wube.build's last step for a skinned recipe: decimate, weight every vertex, cut apart
    where `"separate"` says, recolour by zone, write the bone table into creature_rigs.json.
    Returns the triangle count."""
    from scipy.spatial import cKDTree
    spec = recipe["skin"]
    bones = spec["bones"]
    index = {bone[0]: i for i, bone in enumerate(bones)}
    total_area = sum(mesh.area for _, mesh in merged) or 1.0
    targets = [max(12, int(budget * 0.97 * mesh.area / total_area)) for _, mesh in merged]
    meshes = wube.decimate_all([(mesh, n) for (_, mesh), n in zip(merged, targets)])
    groups, uv = [], []
    for (material, _), mesh in zip(merged, meshes):
        if material in spec.get("fixed", {}):
            a = np.full(len(mesh.vertices), index[spec["fixed"][material]])
            b, w = a, np.ones(len(a))
        else:
            a, b, w = skin_weights(mesh.vertices, bones, spec.get("penalty"), spec.get("band", 0.5))
            for names, region in spec.get("separate", []):
                group_sets = [[index[n] for n in g] for g in names]
                mesh, a, b, w = separate(mesh, a, b, w, group_sets, region)
        if material == spec.get("material"):
            mats = zone_materials(mesh, np.full(len(mesh.faces), material), spec)
        else:
            mats = np.full(len(mesh.faces), material, dtype=object)
        tree = cKDTree(mesh.vertices)
        for m in dict.fromkeys(mats.tolist()):
            sub = mesh.submesh([np.nonzero(mats == m)[0]], append=True, repair=False)
            shaded = wube.shaded(sub)
            # Shading splits vertices along hard edges: each copy keeps its original's weights.
            _d, near = tree.query(shaded.vertices)
            groups.append((m, shaded))
            uv.append(np.column_stack([a[near] + 16.0 * b[near], w[near]]))
    # Armour plates (armour_looks.py): each follows its bone rigidly, one primitive per material.
    plates = {}
    for material, mesh, bone in spec.get("armour", lambda _bones: [])(bones):
        shaded = wube.shaded(mesh)
        code = index[bone]
        plates.setdefault(material, []).append((shaded, np.column_stack(
            [np.full(len(shaded.vertices), code + 16.0 * code), np.ones(len(shaded.vertices))])))
    for material, items in plates.items():
        groups.append((material, wube.trimesh.util.concatenate([m for m, _ in items])))
        uv.append(np.vstack([u for _, u in items]))
    wube.write_glb(out_path, groups, palette, alpha, copyright_text, uv0=uv)
    write_pose_table(name, bones)
    return sum(len(m.faces) for _, m in groups)


def write_pose_table(name, bones):
    """A skeleton's entry in creature_rigs.json (character_pose.gd reads it)."""
    index = {bone[0]: i for i, bone in enumerate(bones)}
    table = {}
    if os.path.exists(RIGS_JSON):
        with open(RIGS_JSON, encoding="utf-8") as f:
            table = json.load(f)
    table[name] = {"mode": "pose", "bones": [
        {"name": n, "parent": -1 if p is None else index[p], "head": [round(float(c), 4) for c in h],
         "tail": [round(float(c), 4) for c in t]} for n, p, h, t, _r in bones]}
    _write_table(table)


def write_rig_table(name, spec):
    table = {}
    if os.path.exists(RIGS_JSON):
        with open(RIGS_JSON, encoding="utf-8") as f:
            table = json.load(f)
    table[name] = {"mode": spec.get("mode", "walk"), "rate": spec.get("rate", 1.0), "limbs": limb_table(spec)}
    _write_table(table)


def _write_table(table):
    with open(RIGS_JSON, "w", encoding="utf-8", newline=NL) as f:
        f.write("{" + NL)
        items = sorted(table.items())
        for k, (n, entry) in enumerate(items):
            f.write("  %s: %s%s%s" % (json.dumps(n), json.dumps(entry, separators=(", ", ": ")),
                                      "," if k + 1 < len(items) else "", NL))
        f.write("}" + NL)


NL = chr(10)
