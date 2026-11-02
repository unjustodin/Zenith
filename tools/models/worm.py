#!/usr/bin/env python3
"""The worm (big-worm-turret.glb), built to Factorio's own pictures of it.

    python tools/models/worm.py            # needs the venv and a Factorio install

Wube's printed worm is a slim column in a ring of spikes; Factorio's worm is a fat, ribbed
bottle with a flared head, a mouth on top and horns, standing in a plain hole (the hole is the
ground picture `integration`, not part of the worm). The print scored 0.59 against the prepared
picture and no refit of it reaches the bottle, so the worm is rebuilt from the sprites, as the
demolishers were (creature_hull.py).

What the sprites say (Factorio 2.1's worm sheets):

- The body's outline: every direction of the attack starts (frame 0) with the worm standing as
  it does prepared, facing the camera; carving a voxel grid with those 16 silhouettes from
  Factorio's camera (turntable.py) gives its radius at each height. The body is lathed through
  those radii, up to where the head narrows.
- Which side is which, from the lunges (the attack's last frames, 16 directions): it bends over
  towards its target, so the ribbed belly is its front (north, -Z, as every model faces) and the
  segmented plates its back; the mouth is on top of the head, ringed by horns: two curling out
  at the sides, one standing at the back, a pair of tusks in front of the mouth.
- The plates are what Factorio tints per tier (the mask layer): `flesh_worm` (creature_models.gd
  tints it); the belly and the face are `belly_worm`, the horns `horn_worm`, the mouth `mouth_worm`.

The client folds, raises and bends it in the shader (rig_mode 4), so it needs no limb data, only
creature_rigs.json's "worm" entry. part_colors.py samples the colours from the prepared picture
afterwards. Nothing of the sprites is written to the repo, only this geometry.
"""

import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import creature_score as cs  # noqa: E402
import turntable as tt  # noqa: E402

NAME = "big-worm-turret"
RES = 0.03          # voxel size, tiles
STEP = 0.045        # the lathe's rings, tiles apart
SIDES = 40
HEAD_R = 0.7        # the body ends where the measured radius falls under this (the head and horns go on)
RIB = 0.14          # the belly's ribs, tiles apart (about 22 up the prepared picture)
PLATE = 0.32        # the back's plates


def frames(raw):
    """The attack's first frame from its 16 directions (rgba images)."""
    anim = raw["turret"][NAME]["starting_attack_animation"]
    body = {"layers": [ly for ly in cs._layers(anim) if "mask" not in ly.get("filenames", [""])[0]]}
    return [tt.frame_canvas(cs.frame_layers(body, d, 0)) for d in range(cs.direction_count(anim))]


def profile(raw):
    """[(height, radius)] of the body, measured from the carved hull."""
    cam = tt.Camera(anchor=0.0)
    masks = [im[..., 3] > 0.5 for im in frames(raw)]
    old = tt.N_DIR
    tt.N_DIR = len(masks)  # carve() turns the model by 2 pi i / N_DIR
    try:
        pts = tt.carve(masks, cam, RES)[0]
    finally:
        tt.N_DIR = old
    r = np.hypot(pts[:, 0], pts[:, 2])
    out = []
    for y in np.arange(0.0, pts[:, 1].max(), STEP):
        s = (pts[:, 1] >= y) & (pts[:, 1] < y + STEP)
        if not s.any():
            break
        out.append((y, float(np.percentile(r[s], 99)) + RES / 2))
    rad = np.array([v for _, v in out])
    rad = np.convolve(np.pad(rad, 2, mode="edge"), np.ones(5) / 5, mode="valid")
    out = [(y, v) for (y, _), v in zip(out, rad)]
    end = next(i for i, (y, v) in enumerate(out) if y > 1.0 and v < HEAD_R)
    return out[:end]


def lathe(prof):
    """The body: rings through the profile, the belly ribbed, the back in plates with a ridge
    down the middle, closed by a dome where the head is. Returns (vertices, faces, angle of each
    vertex from the front, height)."""
    y_top, r_top = prof[-1]
    dome = [(y_top + r_top * 0.42 * math.sin(a), r_top * math.cos(a)) for a in np.linspace(0.15, 1.35, 8)]
    rings = list(prof) + dome
    th = np.linspace(0.0, 2 * math.pi, SIDES, endpoint=False)  # 0 = front (-Z), turning east
    verts, ang, hy = [], [], []
    for y, r in rings:
        front = np.clip(np.cos(th), 0.0, 1.0)
        back = np.clip(-np.cos(th), 0.0, 1.0)
        below_head = 1.0 if y < y_top - 0.15 else 0.0
        rib = 0.022 * (0.5 + 0.5 * math.cos(2 * math.pi * y / RIB)) * front ** 0.6 * below_head
        plate = 0.03 * max(0.0, math.cos(2 * math.pi * y / PLATE)) ** 4 * back ** 0.5 * below_head
        ridge = 0.06 * np.exp(-((th - math.pi) / 0.12) ** 2) * below_head
        rr = r * (1.0 - rib) - plate + ridge * (r / 1.0)
        verts += [(rr[i] * math.sin(t), y, -rr[i] * math.cos(t)) for i, t in enumerate(th)]
        ang += list(th)
        hy += [y] * SIDES
    n = len(rings)
    faces = []
    for k in range(n - 1):
        for i in range(SIDES):
            a, b = k * SIDES + i, k * SIDES + (i + 1) % SIDES
            c, d = a + SIDES, b + SIDES
            faces += [(a, c, b), (b, c, d)]
    top = len(verts)
    verts.append((0.0, rings[-1][0] + 0.02, 0.0))
    ang.append(0.0)
    hy.append(rings[-1][0])
    base = (n - 1) * SIDES
    faces += [(base + i, top, base + (i + 1) % SIDES) for i in range(SIDES)]
    return np.array(verts), np.array(faces), np.array(ang), np.array(hy), y_top, r_top


def horn(root, direction, length, radius, curl, sides=10, rings=9):
    """A tapering horn from `root` along `direction`, bending towards `curl` as it goes."""
    d = np.asarray(direction, float)
    d /= np.linalg.norm(d)
    c = np.asarray(curl, float)
    pts, out = [], []
    p = np.asarray(root, float)
    for k in range(rings):
        t = k / (rings - 1)
        pts.append(p.copy())
        step = d + c * t * 1.6
        p = p + step / np.linalg.norm(step) * length / (rings - 1)
    verts, faces = [], []
    for k, p in enumerate(pts):
        nxt = pts[min(k + 1, rings - 1)] - pts[max(k - 1, 0)]
        nxt /= np.linalg.norm(nxt)
        u = np.cross(nxt, [0.0, 1.0, 0.0] if abs(nxt[1]) < 0.9 else [1.0, 0.0, 0.0])
        u /= np.linalg.norm(u)
        v = np.cross(nxt, u)
        r = radius * (1.0 - k / (rings - 1)) ** 0.8 + 0.006
        for i in range(sides):
            a = 2 * math.pi * i / sides
            verts.append(p + r * (math.cos(a) * u + math.sin(a) * v))
    for k in range(rings - 1):
        for i in range(sides):
            a, b = k * sides + i, k * sides + (i + 1) % sides
            faces += [(a, a + sides, b), (b, a + sides, b + sides)]
    verts.append(pts[0])
    faces += [(len(verts) - 1, i, (i + 1) % sides) for i in range(sides)][::-1]
    return np.array(verts), np.array(faces)


def disc(centre, normal, radius, sides=16):
    n = np.asarray(normal, float)
    n /= np.linalg.norm(n)
    u = np.cross(n, [1.0, 0.0, 0.0])
    u /= np.linalg.norm(u)
    v = np.cross(n, u)
    c = np.asarray(centre, float)
    verts = [c + n * 0.01] + [c + radius * (math.cos(a) * u + math.sin(a) * v)
                              for a in np.linspace(0, 2 * math.pi, sides, endpoint=False)]
    faces = [(0, 1 + (i + 1) % sides, 1 + i) for i in range(sides)]
    return np.array(verts), np.array(faces)


def build(raw, out_dir=tt.MODELS):
    import trimesh
    import wube
    import wube_recipes
    prof = profile(raw)
    v, f, ang, hy, y_top, r_top = lathe(prof)
    body = trimesh.Trimesh(v, f, process=True)
    body.fix_normals()
    # Each face's material by where it is: the front third below the head is belly, the head's
    # front too (the face round the mouth); the rest are the tinted plates.
    cen = body.vertices[body.faces].mean(axis=1)
    th = np.arctan2(cen[:, 0], -cen[:, 2])
    front = np.abs(th) < math.radians(62)
    head = cen[:, 1] > y_top - 0.25
    belly = (front & ~head) | (head & (cen[:, 2] < 0.25 * r_top))
    h = y_top + 0.4 * r_top  # the dome's top
    parts = [("belly_worm", body.submesh([np.nonzero(belly)[0]], append=True, repair=False)),
             ("flesh_worm", body.submesh([np.nonzero(~belly)[0]], append=True, repair=False))]
    s = r_top
    horns = [
        # the side horns: out sideways from the head's rim, curling up and a little back
        horn((-0.85 * s, y_top + 0.05, -0.05), (-1.0, 0.35, 0.0), 0.9 * s, 0.2 * s, (0.2, 0.9, 0.2)),
        horn((0.85 * s, y_top + 0.05, -0.05), (1.0, 0.35, 0.0), 0.9 * s, 0.2 * s, (-0.2, 0.9, 0.2)),
        # the back horn, standing up behind the mouth
        horn((0.0, h - 0.12, 0.35 * s), (0.0, 1.0, 0.25), 0.75 * s, 0.13 * s, (0.0, 0.3, -0.4)),
        # the tusks in front of the mouth, down over the face
        horn((-0.16 * s, h - 0.08, -0.52 * s), (-0.1, 0.4, -1.0), 0.55 * s, 0.1 * s, (0.0, -1.2, -0.2)),
        horn((0.16 * s, h - 0.08, -0.52 * s), (0.1, 0.4, -1.0), 0.55 * s, 0.1 * s, (0.0, -1.2, -0.2)),
    ]
    for hv, hf in horns:
        parts.append(("horn_worm", trimesh.Trimesh(hv, hf, process=True)))
    mv, mf = disc((0.0, h - 0.035, -0.12 * s), (0.0, 1.0, -0.35), 0.2 * s)
    parts.append(("mouth_worm", trimesh.Trimesh(mv, mf, process=True)))
    palette, alpha = wube.load_palette()
    palette.update(wube_recipes.EXTRA_MATERIALS)
    by = {}
    for m, mesh in parts:
        by.setdefault(m, []).append(mesh)
    groups = [(m, wube.shaded(trimesh.util.concatenate(ms))) for m, ms in by.items()]
    path = os.path.join(out_dir, NAME + ".glb")
    wube.write_glb(path, groups, palette, alpha, "Zenith; shape measured from Factorio's worm sprites")
    print("wrote %s: %d triangles, body to %.2f tiles (radius %.2f at the base, %.2f at the head)" % (
        os.path.relpath(path, tt.REPO), sum(len(m.faces) for _, m in groups), h, prof[0][1], r_top))
    return path


if __name__ == "__main__":
    build(cs.data_raw())
