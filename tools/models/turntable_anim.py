#!/usr/bin/env python3
"""Turntable animation: fit our rigged models' poses to Factorio's animated sprite sheets (an
experiment, beside turntable.py).

    python tools/models/turntable_anim.py big-biter      # run: 16 directions x 16 frames
    python tools/models/turntable_anim.py character      # running: 8 directions x 22 frames
    python tools/models/turntable_anim.py gun-turret     # raising: 4 directions x 5 frames
    python tools/models/turntable_anim.py --gait big-biter character   # one loop in the client's terms

Every frame of an animation is drawn from several directions, so each frame is a small turntable.
Rather than carve a hull per frame (16 views at most, and thin legs carve badly), this poses the
model we already have, on the rig the client already drives, and searches its joint angles for
the pose whose silhouettes overlap the frame's best across all directions (mean IoU), starting
from the previous frame's pose:

- big-biter: the rig in client/data/creature_rigs.json (tools/models/wube_rig.py): six legs,
  each turned about its joint by a lift and a swing angle (as the shader's rig_mode 1 does),
  plus the body's height and pitch;
- character: its skeleton (character_pose.gd): thighs, shins, upper arms, forearms, spine and
  head swung about X (Euler YXZ, as Basis.from_euler), the root's height and twist;
- gun-turret: the head (anim_turret_*) sinking into the base: one height per frame.

First the model is calibrated once (scale and offset on the ground) against all frames at rest.

Writes to the git-ignored art-src/turntable/anim/: <name>.json (keyframes: per frame the angles,
and the IoU per direction; for the biter also the first-harmonic gait per leg in the client's
terms: phase, swing, lift), <name>_contact.png (sprite | fitted pose from Factorio's camera |
from a low angle) and <name>.gif. Everything here is derived from Factorio's sprites.
"""

import json
import math
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import turntable as tt  # noqa: E402

REPO = tt.REPO
OUT = os.path.join(tt.OUT, "anim")
RIGS = json.load(open(os.path.join(REPO, "client", "data", "creature_rigs.json"), encoding="utf-8"))
PPT = 32.0          # fitting resolution: half the HR frames'
SIZE = 320
G = "base/graphics/entity/"


# ---------------------------------------------------------------- sprites

def biter_layers(d, f):
    k = d * 16 + f
    return [sp_layer("biter/biter-run-%d.png" % (k // 64 + 1), 398, 310, (-1, -5), 8, k % 64),
            sp_layer("biter/biter-run-mask1-%d.png" % (k // 64 + 1), 238, 182, (-1, -37), 8, k % 64)]


def character_layers(d, f):
    return [sp_layer("character/level1_running.png", 88, 132, (0, -18), 22, d * 22 + f)]


def turret_layers(d, f):
    return [sp_layer("gun-turret/gun-turret-raising.png", 130, 126, (0, -26.5), 5, d * 5 + f)]


def sp_layer(file, w, h, shift, line, index, scale=0.5):
    return {"file": G + file, "frame": [w, h], "line": line, "index": index, "shift": list(shift), "scale": scale}


def masks_for(layers_fn, dirs, frames):
    """[frame][dir] -> bool mask at PPT (downsampled from the 64 px a tile frames)."""
    out = []
    for f in range(frames):
        row = []
        for d in range(dirs):
            img = tt.frame_canvas(layers_fn(d, f))
            a = img[..., 3]
            a = a.reshape(SIZE, 2, SIZE, 2).mean(axis=(1, 3))
            row.append(a > 0.5)
        out.append(row)
    return out


# ---------------------------------------------------------------- models as point clouds

def load_points(path, density=3.0, prefix=None):
    """Points on the model's surface, about `density` a pixel at PPT, with each point's rig data:
    (points (N, 3), uv (N, 2) with the glTF V flipped back, colour (N, 3)), plus the triangles
    and their colours and per-vertex uv for the pictures."""
    import trimesh
    scene = trimesh.load(path, force="scene")
    P, U, C, T, TC, TU = [], [], [], [], [], []
    for node in scene.graph.nodes_geometry:
        if prefix and not str(node).startswith(prefix):
            continue
        transform, geom = scene.graph[node]
        mesh = scene.geometry[geom].copy()
        mesh.apply_transform(transform)
        uv = getattr(mesh.visual, "uv", None)
        uv = np.zeros((len(mesh.vertices), 2)) if uv is None else np.column_stack([uv[:, 0], 1 - uv[:, 1]])
        col = np.array([0.6, 0.6, 0.6])
        mat = getattr(mesh.visual, "material", None)
        f_ = getattr(mat, "baseColorFactor", None) if mat is not None else None
        if f_ is not None:
            col = np.asarray(f_[:3], float) / (255.0 if np.max(f_) > 1 else 1.0)
        n = int(mesh.area * PPT * PPT * density) + 100
        pts, fi = trimesh.sample.sample_surface(mesh, n, seed=1)
        bary = trimesh.triangles.points_to_barycentric(mesh.triangles[fi], pts)
        corner = mesh.faces[fi, np.argmax(bary, axis=1)]
        P.append(pts)
        U.append(uv[corner])
        C.append(np.tile(col, (len(pts), 1)))
        T.append(mesh.triangles)
        TC.append(np.tile(col, (len(mesh.faces), 1)))
        TU.append(uv[mesh.faces])
    return (np.concatenate(P), np.concatenate(U), np.concatenate(C),
            np.concatenate(T), np.concatenate(TC), np.concatenate(TU))


def rodrigues(p, axis, ang):
    """Rotate points p (N, 3) about unit axis (3,) by per-point angles ang (N,)."""
    c, s = np.cos(ang)[:, None], np.sin(ang)[:, None]
    a = np.asarray(axis, float)
    return p * c + np.cross(a, p) * s + a * (p @ a)[:, None] * (1 - c)


# ---------------------------------------------------------------- rigs

class BiterRig:
    """rig_mode 1 in factorio_material.gdshaderinc, with the gait's angles free per frame."""

    def __init__(self, name):
        self.limbs = RIGS[name]["limbs"]
        self.names = [l["name"] for l in self.limbs] + ["body_dy", "body_pitch"]
        self.n = 2 * len(self.limbs) + 2
        self.step0 = np.array([0.3] * (2 * len(self.limbs)) + [0.05, 0.08])
        self.lo = np.array([-1.0] * (2 * len(self.limbs)) + [-0.4, -0.4])
        self.hi = -self.lo

    def param_names(self):
        out = []
        for l in self.limbs:
            out += [l["name"] + ".swing", l["name"] + ".lift"]
        return out + ["body_dy", "body_pitch"]

    def pose(self, pts, uv, x):
        p = pts.copy()
        limb = np.round(uv[:, 0]).astype(int) - 1
        w = uv[:, 1]
        for i, l in enumerate(self.limbs):
            sel = (limb == i) & (w > 0)
            if not sel.any():
                continue
            j = np.asarray(l["joint"], float)
            q = p[sel] - j
            q = rodrigues(q, l["lift"], x[2 * i + 1] * w[sel])
            q = rodrigues(q, l["swing"], x[2 * i] * w[sel])
            p[sel] = j + q
        # body: pitch about the x axis through the middle at the hips' height, then bob
        piv = np.array([0.0, 0.9, 0.0])
        p = piv + rodrigues(p - piv, (1.0, 0.0, 0.0), np.full(len(p), x[-1]))
        p[:, 1] += x[-2]
        return p


def euler_yxz(e):
    """Basis.from_euler(Vector3(x, y, z)) with Godot's default order YXZ: R = Ry * Rx * Rz."""
    x, y, z = e
    cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
    Rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    Rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return Ry @ Rx @ Rz


class CharacterRig:
    """character_pose.gd: bones turned about their heads, children with their parents; each
    vertex follows bone a (weight) and bone b (1 - weight), coded in UV.x = a + 16 b."""
    FREE = [("root", 1), ("spine", 0), ("head", 0), ("thigh_r", 0), ("shin_r", 0), ("thigh_l", 0), ("shin_l", 0),
            ("upper_arm_r", 0), ("forearm_r", 0), ("upper_arm_l", 0), ("forearm_l", 0)]

    def __init__(self):
        rig = RIGS["character"]
        self.bones = rig["bones"]
        self.index = {b["name"]: i for i, b in enumerate(self.bones)}
        self.n = len(self.FREE) + 1
        self.step0 = np.array([0.15] + [0.25] * (len(self.FREE) - 1) + [0.03])
        self.lo = np.array([-0.6] + [-2.2] * (len(self.FREE) - 1) + [-0.3])
        self.hi = np.array([0.6] + [2.2] * (len(self.FREE) - 1) + [0.3])

    def param_names(self):
        return ["%s.%s" % (b, "xyz"[k]) for b, k in self.FREE] + ["root_dy"]

    def skins(self, x):
        turns = np.zeros((len(self.bones), 3))
        for (b, k), v in zip(self.FREE, x[:-1]):
            turns[self.index[b], k] = v
        out = []
        for i, b in enumerate(self.bones):
            r = euler_yxz(turns[i])
            h = np.asarray(b["head"], float)
            local = np.eye(4)
            local[:3, :3] = r
            local[:3, 3] = h - r @ h
            parent = out[b["parent"]] if b["parent"] >= 0 else self.root(x)
            out.append(parent @ local)
        return out

    @staticmethod
    def root(x):
        m = np.eye(4)
        m[1, 3] = x[-1]
        return m

    def pose(self, pts, uv, x):
        sk = self.skins(x)
        code = np.round(uv[:, 0]).astype(int)
        a, b = code % 16, code // 16
        w = uv[:, 1]
        hom = np.column_stack([pts, np.ones(len(pts))])
        M = np.stack(sk)  # (B, 4, 4)
        pa = np.einsum("nij,nj->ni", M[np.clip(a, 0, len(sk) - 1)], hom)[:, :3]
        pb = np.einsum("nij,nj->ni", M[np.clip(b, 0, len(sk) - 1)], hom)[:, :3]
        return pb + (pa - pb) * w[:, None]


class TurretRig:
    """The gun turret's head sinking into its base: one height."""

    def __init__(self):
        self.n = 1
        self.step0 = np.array([0.15])
        self.lo, self.hi = np.array([-1.5]), np.array([0.3])

    def param_names(self):
        return ["head_dy"]

    def pose(self, pts, uv, x):
        p = pts.copy()
        p[:, 1] += x[0]
        return p


# ---------------------------------------------------------------- fitting

class Fitter:
    def __init__(self, rig, pts, uv, masks, ndirs, anchor):
        self.rig, self.pts, self.uv, self.masks, self.ndirs = rig, pts, uv, masks, ndirs
        self.cam = tt.Camera(anchor=anchor, ppt=PPT, size=SIZE, b=math.sin(tt.ELEV))
        self.calib = np.array([1.0, 0.0, 0.0])   # scale, dx, dz (tiles, model space)
        self.st = ndimage.generate_binary_structure(2, 2)

    def silhouette(self, p, d):
        u, v, _ = self.cam.project(p, 2 * math.pi * d / self.ndirs)
        ui, vi = np.round(u).astype(int), np.round(v).astype(int)
        ok = (ui >= 0) & (ui < SIZE) & (vi >= 0) & (vi < SIZE)
        img = np.zeros((SIZE, SIZE), bool)
        img[vi[ok], ui[ok]] = True
        return ndimage.binary_closing(img, self.st)

    def placed(self, x):
        p = self.rig.pose(self.pts, self.uv, x)
        s, dx, dz = self.calib
        p = p * s
        p[:, 0] += dx
        p[:, 2] += dz
        return p

    def ious(self, x, f):
        p = self.placed(x)
        return [tt.iou(self.silhouette(p, d), self.masks[f][d]) for d in range(self.ndirs)]

    def score(self, x, f):
        return float(np.mean(self.ious(x, f)))

    def calibrate(self, frames):
        x0 = np.zeros(self.rig.n)
        best = (np.mean([self.score(x0, f) for f in frames]), self.calib.copy())
        for step in (0.1, 0.05, 0.02, 0.01):
            improved = True
            while improved:
                improved = False
                for k in range(3):
                    for sgn in (1, -1):
                        c = best[1].copy()
                        c[k] += sgn * step * (1 if k else 1.5)
                        self.calib = c
                        s = np.mean([self.score(x0, f) for f in frames])
                        if s > best[0] + 1e-4:
                            best = (s, c)
                            improved = True
        self.calib = best[1]
        return best[0]

    def fit_frame(self, f, x0):
        x = x0.copy()
        best = self.score(x, f)
        for scale in (1.0, 0.5, 0.25, 0.12):
            improved = True
            rounds = 0
            while improved and rounds < 4:
                improved = False
                rounds += 1
                for k in range(self.rig.n):
                    for sgn in (1, -1):
                        y = x.copy()
                        y[k] = np.clip(y[k] + sgn * self.rig.step0[k] * scale, self.rig.lo[k], self.rig.hi[k])
                        s = self.score(y, f)
                        if s > best + 1e-4:
                            x, best = y, s
                            improved = True
        return x, best


# ---------------------------------------------------------------- pictures

def render_pose(fitter, tris, tcol, tuv, x, cam, phi, size):
    """Pose the triangles' corners as the points are posed, and render them."""
    flat = tris.reshape(-1, 3)
    uvf = tuv.reshape(-1, 2)
    p = fitter.rig.pose(flat, uvf, x)
    s, dx, dz = fitter.calib
    p = p * s
    p[:, 0] += dx
    p[:, 2] += dz
    m, rgb, _ = tt.render(p.reshape(-1, 3, 3), tcol, cam, phi, size=size)
    return tt.to_img(rgb, m)


def contact_sheet(name, layers_fn, fitter, tris, tcol, tuv, xs, ious, show_dirs, nframes, ndirs):
    big = tt.Camera(anchor=fitter.cam.anchor, b=math.sin(tt.ELEV))
    low = tt.Camera.true(12, anchor=fitter.cam.anchor)
    rows = []
    for d in show_dirs:
        phi = 2 * math.pi * d / ndirs
        r_s, r_f, r_l = [], [], []
        for f in range(nframes):
            r_s.append(tt.sprite_img(tt.frame_canvas(layers_fn(d, f))))
            r_f.append(render_pose(fitter, tris, tcol, tuv, xs[f], big, phi, tt.CANVAS))
            r_l.append(render_pose(fitter, tris, tcol, tuv, xs[f], low, phi, tt.CANVAS))
        rows.append((d, r_s, r_f, r_l))
    y0, y1, x0, x1 = tt.crop_box([im for r in rows for grp in r[1:] for im in grp])
    tw, th = x1 - x0, y1 - y0
    sheet = Image.new("RGB", (tw * nframes, th * 3 * len(rows)), (30, 30, 30))
    gif = []
    for ri, (d, r_s, r_f, r_l) in enumerate(rows):
        for f in range(nframes):
            for k, (grp, t) in enumerate(((r_s, "sprite d%d f%d" % (d, f)),
                                          (r_f, "fit %.2f" % ious[f][d]), (r_l, "low 12deg"))):
                im = tt.label(Image.fromarray(grp[f][y0:y1, x0:x1].copy()), t)
                sheet.paste(im, (f * tw, (ri * 3 + k) * th))
    for f in range(nframes):
        g = Image.new("RGB", (tw * 3 * len(rows), th), (30, 30, 30))
        for ri, (d, r_s, r_f, r_l) in enumerate(rows):
            for k, grp in enumerate((r_s, r_f, r_l)):
                g.paste(Image.fromarray(grp[f][y0:y1, x0:x1].copy()), ((ri * 3 + k) * tw, 0))
        gif.append(g)
    sheet.save(os.path.join(OUT, name + "_contact.png"))
    gif[0].save(os.path.join(OUT, name + ".gif"), save_all=True, append_images=gif[1:], duration=70, loop=0)


def harmonic(values):
    """First harmonic of a loop: (mean, amplitude, phase) with value ~ mean + amp * sin(t + phase)."""
    n = len(values)
    t = 2 * math.pi * np.arange(n) / n
    v = np.asarray(values)
    a = 2 * np.mean(v * np.sin(t))
    b = 2 * np.mean(v * np.cos(t))
    return float(v.mean()), float(math.hypot(a, b)), float(math.atan2(b, a))


ENTITIES = {
    "big-biter": dict(layers=biter_layers, dirs=16, frames=16, anchor=0.0, show=(4, 10, 0)),
    "character": dict(layers=character_layers, dirs=8, frames=22, anchor=0.0, show=(2, 7, 4)),
    "gun-turret": dict(layers=turret_layers, dirs=4, frames=5, anchor=tt.ANCHOR, show=(0, 1, 2, 3)),
}


def run(name):
    os.makedirs(OUT, exist_ok=True)
    e = ENTITIES[name]
    print("%s: cutting %d x %d frames" % (name, e["dirs"], e["frames"]))
    masks = masks_for(e["layers"], e["dirs"], e["frames"])
    path = os.path.join(tt.MODELS, name + ".glb")
    prefix = "anim_turret" if name == "gun-turret" else None
    pts, uv, col, tris, tcol, tuv = load_points(path, prefix=prefix)
    rig = {"big-biter": lambda: BiterRig("big-biter"), "character": CharacterRig, "gun-turret": TurretRig}[name]()
    fitter = Fitter(rig, pts, uv, masks, e["dirs"], e["anchor"])
    print("  %d surface points; rest pose IoU %.3f" % (len(pts), np.mean([fitter.score(np.zeros(rig.n), f)
                                                                        for f in range(e["frames"])])))
    calib_frames = range(e["frames"]) if name != "gun-turret" else [e["frames"] - 1]
    c = fitter.calibrate(list(calib_frames))
    print("  calibrated: scale %.3f, dx %.3f, dz %.3f -> rest IoU %.3f" % (*fitter.calib, c))
    xs, ious, rest = [], [], []
    x = np.zeros(rig.n)
    for f in range(e["frames"]):
        rest.append(fitter.score(np.zeros(rig.n), f))
        x, s = fitter.fit_frame(f, x)
        xs.append(x.copy())
        ious.append(fitter.ious(x, f))
        print("  frame %2d: IoU rest %.3f -> fitted %.3f" % (f, rest[-1], s))
    if name != "gun-turret":
        # a second pass, each frame starting from both neighbours' poses, smooths out early mistakes
        for f in list(range(e["frames"])):
            for src in (xs[f - 1], xs[(f + 1) % e["frames"]]):
                y, s = fitter.fit_frame(f, src)
                if s > np.mean(ious[f]) + 1e-4:
                    xs[f], ious[f] = y, fitter.ious(y, f)
    out = {"entity": name, "directions": e["dirs"], "frames": e["frames"],
           "calibration": {"scale": fitter.calib[0], "dx": fitter.calib[1], "dz": fitter.calib[2]},
           "params": rig.param_names(),
           "keyframes": [[round(float(v), 4) for v in x] for x in xs],
           "iou_rest": [round(v, 3) for v in rest],
           "iou_fitted": [[round(v, 3) for v in r] for r in ious],
           "iou_fitted_mean": [round(float(np.mean(r)), 3) for r in ious]}
    if name == "big-biter":
        gait = {}
        for i, l in enumerate(rig.limbs):
            sw = harmonic([x[2 * i] for x in xs])
            li = harmonic([x[2 * i + 1] for x in xs])
            gait[l["name"]] = {"swing": [round(v, 3) for v in sw], "lift": [round(v, 3) for v in li],
                               "client_now": l["gait"]}
        out["gait_first_harmonic"] = gait
    if name == "character":
        out["first_harmonic"] = {n: [round(v, 3) for v in harmonic([x[k] for x in xs])]
                                 for k, n in enumerate(rig.param_names())}
    json.dump(out, open(os.path.join(OUT, name + ".json"), "w"), indent=1)
    print("  mean IoU: rest %.3f, fitted %.3f" % (np.mean(rest), np.mean([np.mean(r) for r in ious])))
    contact_sheet(name, e["layers"], fitter, tris, tcol, tuv, xs, ious, e["show"], e["frames"], e["dirs"])
    print("  wrote %s" % os.path.join(OUT, name + "_contact.png"))


# ---------------------------------------------------------------- gait mode
#
# Per-frame poses are free to wander: a leg's silhouette from the side looks the same whichever
# leg is forward, and a knee can bend the wrong way and still fill the outline. In gait mode the
# whole loop is one small set of numbers in the client's own form (a sine per joint, the left
# side half a loop behind the right, knees that only fold), fitted to every frame at once.

class CharacterGait:
    NAMES = ["thigh_mean", "thigh_amp", "phase", "shin_mean", "shin_fold", "shin_phase", "arm_mean", "arm_amp",
             "arm_phase", "forearm_mean", "forearm_amp", "spine_lean", "head", "hip_twist", "bob_mean", "bob_amp",
             "bob_phase"]
    # The client's run (character_anim.gd _run), retuned against these sprites; it was
    # [0.12, 0.72, 0.0, -0.25, 1.15, 0.0, 0.1, 0.75, pi, 1.25, 0.25, -0.32, 0.22, 0.1, -0.05, 0.03, 0.0].
    G0 = [-0.03, 0.7, 0.0, -0.81, 1.15, -0.3, -0.4, 1.2, math.pi + 0.6, 1.35, 0.6, -0.02, -0.05, -0.06, -0.013, -0.04,
          0.4]
    STEP = [0.15, 0.2, 0.6, 0.15, 0.3, 0.6, 0.15, 0.2, 0.6, 0.2, 0.15, 0.1, 0.1, 0.05, 0.03, 0.02, 0.8]

    def frames(self, g, n):
        out = []
        for f in range(n):
            t = 2 * math.pi * f / n + g[2]
            x = np.zeros(12)
            x[0] = g[13] * math.sin(t)                       # root twist (y)
            x[1], x[2] = g[11], g[12]                        # spine lean, head
            x[3] = g[0] + g[1] * math.sin(t)                 # thigh_r
            x[5] = g[0] - g[1] * math.sin(t)                 # thigh_l
            x[4] = g[3] - g[4] * max(0.0, math.cos(t + g[5])) ** 1.5   # shin_r folds only
            x[6] = g[3] - g[4] * max(0.0, -math.cos(t + g[5])) ** 1.5
            x[7] = g[6] + g[7] * math.sin(t + g[8])          # upper_arm_r
            x[9] = g[6] - g[7] * math.sin(t + g[8])          # upper_arm_l
            x[8] = g[9] + g[10] * math.sin(t + g[8])         # forearm_r
            x[10] = g[9] - g[10] * math.sin(t + g[8])
            x[11] = g[14] + g[15] * math.cos(2 * t + g[16])  # root_dy
            out.append(x)
        return out


class BiterGait:
    """The shader's own gait (rig_mode 1): per leg a phase, a swing and a lift
    (swing = S sin(t + phase), lift = L max(0, cos(t + phase))), and the body's bob."""

    def __init__(self, rig):
        self.rig = rig
        self.NAMES = []
        self.G0, self.STEP = [], []
        for l in rig.limbs:
            self.NAMES += [l["name"] + ".phase", l["name"] + ".swing", l["name"] + ".lift"]
            self.G0 += [l["gait"][0], l["gait"][1], l["gait"][2]]
            self.STEP += [0.6, 0.12, 0.12]
        self.NAMES += ["bob_mean", "bob_amp", "bob_phase", "pitch"]
        self.G0 += [0.0, 0.02, 0.0, 0.0]
        self.STEP += [0.03, 0.02, 0.8, 0.05]

    def frames(self, g, n):
        out = []
        k = len(self.rig.limbs)
        for f in range(n):
            t = 2 * math.pi * f / n
            x = np.zeros(2 * k + 2)
            for i in range(k):
                ph, sw, li = g[3 * i:3 * i + 3]
                x[2 * i] = sw * math.sin(t + ph)
                x[2 * i + 1] = li * max(0.0, math.cos(t + ph))
            x[-2] = g[3 * k] + g[3 * k + 1] * math.cos(2 * t + g[3 * k + 2])
            x[-1] = g[3 * k + 3]
            out.append(x)
        return out


def fit_gait(fitter, model, nframes, frame_step=2, dir_step=1):
    g = np.array(model.G0, float)
    sub = list(range(0, nframes, frame_step))
    dirs = list(range(0, fitter.ndirs, dir_step))

    def score(g):
        xs = model.frames(g, nframes)
        tot = []
        for f in sub:
            p = fitter.placed(xs[f])
            tot += [tt.iou(fitter.silhouette(p, d), fitter.masks[f][d]) for d in dirs]
        return float(np.mean(tot))

    best = score(g)
    print("  gait start IoU %.3f" % best)
    for scale in (1.0, 0.5, 0.25):
        for _round in range(3):
            improved = False
            for k in range(len(g)):
                for sgn in (1, -1):
                    h = g.copy()
                    h[k] += sgn * model.STEP[k] * scale
                    s = score(h)
                    if s > best + 1e-4:
                        g, best, improved = h, s, True
            print("  gait step %.2f: IoU %.3f" % (scale, best))
            if not improved:
                break
    return g


def run_gait(name):
    e = ENTITIES[name]
    masks = masks_for(e["layers"], e["dirs"], e["frames"])
    pts, uv, col, tris, tcol, tuv = load_points(os.path.join(tt.MODELS, name + ".glb"))
    rig = BiterRig("big-biter") if name == "big-biter" else CharacterRig()
    fitter = Fitter(rig, pts, uv, masks, e["dirs"], e["anchor"])
    free = os.path.join(OUT, name + ".json")
    if os.path.exists(free):
        c = json.load(open(free))["calibration"]
        fitter.calib = np.array([c["scale"], c["dx"], c["dz"]])
    else:
        fitter.calibrate(list(range(e["frames"])))
    model = BiterGait(rig) if name == "big-biter" else CharacterGait()
    g0 = np.array(model.G0, float)
    if name == "character":
        # The client's loop starts anywhere: score it from the sprite's frame 0's point in the loop.
        def at(ph):
            h = g0.copy()
            h[2] = ph
            xs_ = model.frames(h, e["frames"])
            return np.mean([np.mean(fitter.ious(xs_[f], f)) for f in range(0, e["frames"], 2)])
        g0[2] = max(np.linspace(-math.pi, math.pi, 25), key=at)
    client = model.frames(g0, e["frames"])
    g = fit_gait(fitter, model, e["frames"], dir_step=2 if name == "big-biter" else 1)
    xs = model.frames(g, e["frames"])
    ious = [fitter.ious(x, f) for f, x in enumerate(xs)]
    ious_client = [float(np.mean(fitter.ious(x, f))) for f, x in enumerate(client)]
    out = {"entity": name, "mode": "gait", "gait_names": model.NAMES,
           "gait": [round(float(v), 4) for v in g], "client_gait": [round(float(v), 4) for v in model.G0],
           "params": rig.param_names(), "keyframes": [[round(float(v), 4) for v in x] for x in xs],
           "iou_fitted": [[round(v, 3) for v in r] for r in ious],
           "iou_fitted_mean": [round(float(np.mean(r)), 3) for r in ious],
           "iou_client_gait_mean": [round(v, 3) for v in ious_client]}
    json.dump(out, open(os.path.join(OUT, name + "_gait.json"), "w"), indent=1)
    print("  %s gait: IoU client's gait %.3f -> fitted gait %.3f" % (
        name, np.mean(ious_client), np.mean([np.mean(r) for r in ious])))
    for n_, v0, v in zip(model.NAMES, model.G0, g):
        print("    %-16s client %+.3f  fitted %+.3f" % (n_, v0, v))
    contact_sheet(name + "_gait", e["layers"], fitter, tris, tcol, tuv, xs, ious, e["show"], e["frames"], e["dirs"])


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    for n in args or list(ENTITIES):
        if "--gait" in sys.argv:
            run_gait(n)
        else:
            run(n)
