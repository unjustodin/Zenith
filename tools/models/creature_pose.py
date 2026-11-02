#!/usr/bin/env python3
"""Poses of Nauvis's enemies (attacking, dead) made from their own rigged walking model, fitted
to Factorio's sprites.

    python tools/models/creature_pose.py --fit big-biter-corpse    # search the pose, write the .glb
    python tools/models/creature_pose.py big-biter-corpse          # write the .glb from the stored pose
    python tools/models/creature_pose.py                           # every posed model

Wube printed a biter attacking and dead, and a spitter dead, but those statues don't take the
sprites' poses: Factorio's dead biter lies rolled on its side with its legs drawn up, about as big
as a live one (the dead print is curled and two thirds the size: IoU 0.33). So each pose here is
the walking model (Wube's print, rigged by wube_rig.py, long legs and all) posed on the same rig
the client animates: every leg turned about its joint by a swing and a lift (as the shader's
rig_mode 1) and folded at a knee, the body rolled, pitched and turned about its middle, set on the
ground (what sinks in is pressed flat) and scaled. The numbers are found by searching for the pose
whose silhouettes overlap the sprite's frame best over its directions (turntable_anim.py's point
splats at half resolution), starting from a coarse grid of body rolls and pitches, and kept in
creature_poses.py (numbers only). wube.py builds these models through `write_posed` after their
source (recipes with `"posed"` in wube_recipes.py). The worm's corpse is the worm (worm.py) fallen
over the same way, without legs. Each corpse's body move also goes to client/data/creature_poses.json
for the client's dying animation.

The silhouettes come from Factorio's install and stay in the git-ignored art-src/turntable/.
"""

import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import creature_score as cs  # noqa: E402
import turntable as tt  # noqa: E402
import turntable_anim as ta  # noqa: E402

POSES_PY = os.path.join(HERE, "creature_poses.py")
FIT_DIRS = (0, 2, 4, 6, 8, 10, 12, 14)


# Factorio's biters and spitters don't die the same way in every direction: their dying sheets
# hold four falls, taking turns round the 16 directions (direction d falls the (d mod 4)th way:
# on its side, on its back...), each the same 3D fall turned with the direction. So each corpse is
# four models, "-corpse" for directions 0, 4, 8, 12 and "-corpse-1" to "-corpse-3" for the others;
# the client picks by the direction it died facing (creatures.gd).
CORPSE_VARIANTS = 4


def corpse_model(base, variant):
    return base if variant == 0 else "%s-%d" % (base, variant)


def targets(raw):
    """model -> (source model, animation, frame, options). Options: `coarse` [(roll, pitch[, yaw])]
    to start from, `limit` how far a leg may turn (radians), `scale` (lo, hi), `dirs` the sprite's
    directions this model stands for (default: all)."""
    u, c = raw["unit"], raw["corpse"]
    lying = [(r, p) for r in np.radians(np.arange(-180, 180, 20)) for p in np.radians((-45, -20, 0, 20, 45))]
    standing = [(0.0, p) for p in np.radians((-35, -20, -10, 0, 10, 20))]
    biter_attack = u["big-biter"]["attack_parameters"]["animation"]
    spitter_attack = u["big-spitter"]["attack_parameters"]["animation"]
    out = {}
    # A dead spitter lies burst open on its belly, its plates up (the silhouette alone would as
    # soon roll it on its side, which shows its legs instead): its roll is kept within 40 degrees.
    belly = math.radians(40)
    for family in ("biter", "spitter"):
        anim = c["big-%s-corpse" % family]["animation"]
        for v in range(CORPSE_VARIANTS):
            opts = {"coarse": lying, "limit": 1.6, "scale": (0.85, 1.1), "dirs": list(range(v, 16, CORPSE_VARIANTS))}
            if family == "spitter":
                opts.update(coarse=[s for s in lying if abs(s[0]) <= belly], roll=(-belly, belly))
            out[corpse_model("big-%s-corpse" % family, v)] = ("big-" + family, anim, cs.frame_count(anim) - 1, opts)
    return dict(out, **{
        # The worm fallen out of its hole (one picture: its turn is searched too).
        "big-worm-turret-corpse": ("big-worm-turret", c["big-worm-corpse"]["animation"],
                                   cs.frame_count(c["big-worm-corpse"]["animation"]) - 1,
                                   {"coarse": [(r, p, y) for r in np.radians((0, 90, -90)) for p in np.radians((-90, -70, 70, 90))
                                               for y in np.radians(np.arange(0, 360, 45))],
                                    "limit": 0.1, "scale": (0.8, 1.1)}),
        # The bite at its furthest (frame 5 of 11), the spit at the top of the rear (frame 13 of 14).
        "big-biter-attack": ("big-biter", biter_attack, 5, {"coarse": standing, "limit": 1.2, "scale": (0.9, 1.1)}),
        "big-spitter-attack": ("big-spitter", spitter_attack, 13,
                               {"coarse": standing + [(0.0, p) for p in np.radians((-50, -65))], "limit": 1.2,
                                "scale": (0.9, 1.1)}),
    })


class PoseRig:
    """The walking rig's legs (swing and lift at the hip, as the client's rig turns them, and a
    knee: the outer part of the leg folding about the lift axis), then the body: pitch (about
    east-west), roll (about north-south), yaw (about up), all about the body's middle, and how far
    it sits into the ground. The lowest point is put on the ground first."""

    BODY = ["pitch", "roll", "yaw", "sink"]
    KNEE = 0.45  # the knee, as a share of the leg's reach from the hip

    def __init__(self, source, pts, limit):
        # Only a walking rig has limbs in its vertices (TEXCOORD_0); a worm's UVs are plain.
        rig = ta.RIGS.get(source, {})
        self.limbs = rig.get("limbs", []) if rig.get("mode") == "walk" else []
        k = len(self.limbs)
        self.n = 3 * k + len(self.BODY)
        self.step0 = np.array([0.3] * (3 * k) + [0.12, 0.12, 0.1, 0.04])
        self.lo = np.array([-limit] * (3 * k) + [-math.pi, -2 * math.pi, -math.pi, -0.3])
        self.hi = np.array([limit] * (3 * k) + [math.pi, 2 * math.pi, math.pi, 0.0])
        lo, hi = pts.min(axis=0), pts.max(axis=0)
        self.pivot = np.array([(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2])

    def param_names(self):
        out = []
        for l in self.limbs:
            out += [l["name"] + ".swing", l["name"] + ".lift", l["name"] + ".knee"]
        return out + self.BODY

    def pose(self, pts, uv, x):
        p = pts.copy()
        limb = np.round(uv[:, 0]).astype(int) - 1
        w = uv[:, 1]
        for i, l in enumerate(self.limbs):
            sel = (limb == i) & (w > 0)
            sw, li, kn = x[3 * i:3 * i + 3]
            if not sel.any() or (sw == 0 and li == 0 and kn == 0):
                continue
            j = np.asarray(l["joint"], float)
            q = p[sel] - j
            if kn != 0:
                d = np.linalg.norm(q, axis=1)
                reach = d.max()
                near = np.abs(d - self.KNEE * reach) < 0.06 * reach
                if near.any():
                    knee = q[near].mean(axis=0)
                    t = np.clip((d - self.KNEE * reach) / (0.12 * reach), 0.0, 1.0)
                    q = knee + ta.rodrigues(q - knee, l["lift"], kn * t * t * (3 - 2 * t))
            q = ta.rodrigues(q, l["lift"], li * w[sel])
            q = ta.rodrigues(q, l["swing"], sw * w[sel])
            p[sel] = j + q
        pitch, roll, yaw, sink = x[-4:]
        q = p - self.pivot
        ones = np.ones(len(q))
        q = ta.rodrigues(q, (1.0, 0.0, 0.0), pitch * ones)
        q = ta.rodrigues(q, (0.0, 0.0, 1.0), roll * ones)
        q = ta.rodrigues(q, (0.0, 1.0, 0.0), yaw * ones)
        p = q + self.pivot
        p[:, 1] -= p[:, 1].min() - sink
        # What sinks in is pressed flat on the ground (the client's ground would hide it anyway).
        p[:, 1] = np.maximum(p[:, 1], 0.0)
        return p


def masks(anim, frame, dirs):
    """{direction: mask at the fitting resolution} of one frame."""
    out = {}
    for d in dirs:
        a = tt.frame_canvas(cs.frame_layers(anim, d, frame))[..., 3]
        out[d] = a.reshape(ta.SIZE, 2, ta.SIZE, 2).mean(axis=(1, 3)) > 0.5
    return out


class Fitter(ta.Fitter):
    """turntable_anim's fitter over some of the directions, with the scale bounded and searched
    with the pose."""

    def __init__(self, rig, pts, uv, mk, ndirs, dirs, scale):
        super().__init__(rig, pts, uv, [mk], ndirs, 0.0)
        self.dirs, self.scale_range = list(dirs), scale

    def ious(self, x, f=0):
        p = self.placed(x)
        return [tt.iou(self.silhouette(p, d), self.masks[0][d]) for d in self.dirs]

    def place(self, x):
        """The best dx, dz for pose x at scale 1 (the sprite's shift isn't the model's middle)."""
        self.calib = np.array([1.0, 0.0, 0.0])
        best = self.score(x, 0)
        for step in (0.2, 0.08, 0.03):
            improved = True
            while improved:
                improved = False
                for k in (1, 2):
                    for sgn in (1, -1):
                        old = self.calib.copy()
                        self.calib[k] += sgn * step
                        s = self.score(x, 0)
                        if s > best + 1e-4:
                            best, improved = s, True
                        else:
                            self.calib = old
        return best

    def search(self, x, rounds=4):
        best = self.score(x, 0)
        for scale in (1.0, 0.5, 0.25, 0.12):
            improved, r = True, 0
            while improved and r < rounds:
                improved, r = False, r + 1
                for k in range(self.rig.n + 3):
                    for sgn in (1, -1):
                        y, c = x.copy(), self.calib.copy()
                        if k < self.rig.n:
                            y[k] = np.clip(y[k] + sgn * self.rig.step0[k] * scale, self.rig.lo[k], self.rig.hi[k])
                        else:  # scale, dx, dz
                            c[k - self.rig.n] += sgn * (0.05, 0.08, 0.08)[k - self.rig.n] * scale
                            c[0] = np.clip(c[0], *self.scale_range)
                        old = self.calib
                        self.calib = c
                        s = self.score(y, 0)
                        if s > best + 1e-4:
                            x, best = y, s
                            improved = True
                        else:
                            self.calib = old
        return x, best


def fit(name, raw):
    source, anim, frame, opts = targets(raw)[name]
    pts, uv, _col, tris, _tc, _tu = ta.load_points(os.path.join(tt.MODELS, source + ".glb"))
    rig = PoseRig(source, tris.reshape(-1, 3), opts["limit"])
    if "roll" in opts:  # e.g. a corpse that lies on its belly, not on its side
        rig.lo[-3], rig.hi[-3] = opts["roll"]
    ndirs = cs.direction_count(anim)
    every = opts.get("dirs", list(range(ndirs)))
    mk = masks(anim, frame, every)
    fitter = Fitter(rig, pts, uv, mk, ndirs, [d for d in FIT_DIRS if d in every] or every, opts["scale"])
    start = []
    for c in opts["coarse"]:
        x = np.zeros(rig.n)
        x[-4], x[-3] = c[1], c[0]
        if len(c) > 2:
            x[-2] = c[2]
        s = fitter.place(x)
        start.append((s, x, fitter.calib.copy()))
    start.sort(key=lambda s: -s[0])
    print("%s: from %s frame %d; best starts %s" % (name, source, frame,
                                                     ", ".join("%.3f" % s[0] for s in start[:3])))
    best = None
    fitter.dirs = [d for d in every if d % 2 == 0 or d % 4 == 3] if len(every) > 4 else every
    for s0, x, calib in start[:4]:
        fitter.calib = calib
        x, s = fitter.search(x)
        print("  start %.3f -> %.3f" % (s0, s))
        if best is None or s > best[0]:
            best = (s, x, fitter.calib.copy())
    s, x, calib = best
    fitter.calib = calib
    fitter.dirs = every
    print("  its %d directions: %.3f" % (len(every), fitter.score(x, 0)))
    return {"source": source, "frame": frame, "scale": round(float(calib[0]), 4),
            "offset": [round(float(calib[1]), 4), round(float(calib[2]), 4)],
            "pose": {n: round(float(v), 4) for n, v in zip(rig.param_names(), x) if abs(v) > 1e-6}}


def load_poses():
    if not os.path.exists(POSES_PY):
        return {}
    scope = {}
    exec(open(POSES_PY, encoding="utf-8").read(), scope)
    return scope["POSES"]


def save_poses(poses):
    import pprint
    with open(POSES_PY, "w", encoding="utf-8") as f:
        f.write('"""Poses of the enemies\' attack and corpse models, fitted to Factorio\'s sprites by\n'
                'tools/models/creature_pose.py --fit (numbers only). Angles in radians; legs as the\n'
                'client\'s rig turns them (creature_rigs.json), the body about its middle."""\n\n')
        f.write("POSES = " + pprint.pformat(poses, width=110, sort_dicts=True) + "\n")


def _read_glb(path):
    """[(material name, vertices, faces, limb uv)] of a rigged model."""
    import trimesh
    scene = trimesh.load(path, force="scene")
    out = []
    for node in scene.graph.nodes_geometry:
        transform, geom = scene.graph[node]
        mesh = scene.geometry[geom].copy()
        mesh.apply_transform(transform)
        uv = getattr(mesh.visual, "uv", None)
        uv = np.zeros((len(mesh.vertices), 2)) if uv is None else np.column_stack([uv[:, 0], 1 - uv[:, 1]])
        mat = getattr(mesh.visual, "material", None)
        out.append((getattr(mat, "name", None) or "flesh_biter", np.asarray(mesh.vertices), np.asarray(mesh.faces), uv))
    return out


def write_posed(name, entry, palette, alpha, copyright_text, out_dir=tt.MODELS):
    """The source model in the stored pose, written as a still model (no rig)."""
    import trimesh
    import wube
    src = _read_glb(os.path.join(out_dir, entry["source"] + ".glb"))
    allv = np.concatenate([v for _, v, _, _ in src])
    rig = PoseRig(entry["source"], allv, math.pi)
    x = np.zeros(rig.n)
    for k, n in enumerate(rig.param_names()):
        x[k] = entry["pose"].get(n, 0.0)
    alluv = np.concatenate([u for _, _, _, u in src])
    posed = rig.pose(allv, alluv, x) * entry["scale"]
    posed[:, 0] += entry["offset"][0]
    posed[:, 2] += entry["offset"][1]
    groups, at = [], 0
    for material, v, f, _ in src:
        mesh = trimesh.Trimesh(posed[at:at + len(v)], f, process=False)
        at += len(v)
        groups.append((material, wube.shaded(mesh)))
    path = os.path.join(out_dir, name + ".glb")
    wube.write_glb(path, groups, palette, alpha, copyright_text)
    if os.path.abspath(out_dir) == os.path.abspath(tt.MODELS) and "-corpse" in name:
        write_fall(name, rig, x, allv, alluv, posed, entry)
    return path, sum(len(m.faces) for _, m in groups)


def write_fall(name, rig, x, verts, uv, posed, entry):
    """The body's move from the source's rest pose to this one, for the client's dying animation
    (creatures.gd turns the live model this way over the corpse's dying time, then swaps in the
    corpse): the body's middle at rest and posed, the turn as a quaternion (x, y, z, w; glTF and
    Godot share axes) and the scale. Legs aside, it is exact."""
    import json
    pitch, roll, yaw = x[-4], x[-3], x[-2]

    def rot(axis, a):
        axis = np.asarray(axis, float)
        k = np.array([[0, -axis[2], axis[1]], [axis[2], 0, -axis[0]], [-axis[1], axis[0], 0]])
        return np.eye(3) + math.sin(a) * k + (1 - math.cos(a)) * k @ k
    r = rot((0, 1, 0), yaw) @ rot((0, 0, 1), roll) @ rot((1, 0, 0), pitch)
    body = np.round(uv[:, 0]).astype(int) < 1 if rig.limbs else np.ones(len(uv), bool)  # not the limbs
    to = posed[body].mean(axis=0) if body.any() else posed.mean(axis=0)
    at = verts[body].mean(axis=0) if body.any() else verts.mean(axis=0)
    w = math.sqrt(max(0.0, 1.0 + r[0, 0] + r[1, 1] + r[2, 2])) / 2
    q = [(r[2, 1] - r[1, 2]) / (4 * w), (r[0, 2] - r[2, 0]) / (4 * w), (r[1, 0] - r[0, 1]) / (4 * w), w] \
        if w > 1e-6 else list(_quat_any(r))
    path = os.path.join(tt.REPO, "client", "data", "creature_poses.json")
    table = json.load(open(path, encoding="utf-8")) if os.path.exists(path) else {}
    table[name] = {"from": entry["source"], "at": [round(float(c), 4) for c in at],
                   "to": [round(float(c), 4) for c in to], "turn": [round(float(c), 5) for c in q],
                   "scale": entry["scale"]}
    with open(path, "w", encoding="utf-8") as f:
        f.write("{\n" + ",\n".join('  "%s": %s' % (k, json.dumps(table[k])) for k in sorted(table)) + "\n}\n")


def _quat_any(r):
    """A quaternion for a half-turn (the trace formula divides by ~0)."""
    i = int(np.argmax(np.diag(r)))
    j, k = (i + 1) % 3, (i + 2) % 3
    s = math.sqrt(max(0.0, 1.0 + r[i, i] - r[j, j] - r[k, k])) * 2
    q = [0.0, 0.0, 0.0, (r[k, j] - r[j, k]) / s]
    q[i], q[j], q[k] = s / 4, (r[j, i] + r[i, j]) / s, (r[k, i] + r[i, k]) / s
    return q


def main(argv):
    do_fit = "--fit" in argv
    names = [a for a in argv if not a.startswith("--")]
    raw = cs.data_raw()
    poses = load_poses()
    names = names or list(targets(raw))
    import wube
    import wube_recipes
    palette, alpha = wube.load_palette()
    palette.update(wube_recipes.EXTRA_MATERIALS)
    for name in names:
        if do_fit:
            found = fit(name, raw)
            poses = load_poses()  # another fit may have saved meanwhile: keep its entries
            poses[name] = found
            save_poses(poses)
        path, tris = write_posed(name, poses[name], palette, alpha, wube_recipes.COPYRIGHT)
        print("wrote %s (%d tris)" % (os.path.relpath(path, tt.REPO), tris))


if __name__ == "__main__":
    main(sys.argv[1:])
