#!/usr/bin/env python3
"""Measure Space Age creatures' shapes from Factorio's rotation sprites, for the Blender models.

    python tools/models/creature_hull.py [names...] [--res=0.04] [--fit]

Demolishers' heads, segments and tails (128 directions) and the pentapods' torsos (64) are
drawn by Factorio from every side, like a photo turntable (turntable.py): carving a voxel grid
with every frame's silhouette gives the visual hull. Each part is then measured as rings (slices
across its length, each a polar outline of radii) and each ring point's colour class (the
sprite's colour where that surface shows, clustered: dark rock, lit rock, lava, bone...).

Spawners and their corpses have one picture each, so they are measured as heaps instead (`relief`):
east-west columns that each match the sprite's outline, and the green egg sacs found in it.

Writes tools/models/creature_profiles.py (numbers only, nothing of the images; the models in
vulcanus.py and gleba.py loft through the rings) and, for looking at, the hulls to the
git-ignored art-src/turntable/creatures-sa/. Needs the venv and a Factorio install.
"""

import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import creature_score as cs  # noqa: E402
import turntable as tt  # noqa: E402

OUT = os.path.join(tt.OUT, "creatures-sa")
PROFILES = os.path.join(HERE, "creature_profiles.py")
CANVAS = 1024


def scaled(anim, k):
    """The animation's drawn layers with their scale and shift divided by k (a segment drawn at
    1.52 measured at 1)."""
    out = []
    for ly in cs._layers(anim):
        ly = dict(ly)
        ly["scale"] = ly.get("scale", 1.0) / k
        if ly.get("shift"):
            ly["shift"] = [c / k for c in ly["shift"]]
        out.append(ly)
    return {"layers": out}


def sources(raw):
    """name -> (animation, directions to use, frame, slicing axis, slices, angles, colour classes).

    The axis the part is sliced along: "z" (north-south: rings stand across its length) or "x"
    (east-west: a demolisher's segment is a crescent whose sides sweep back, which slices across
    its width follow). Each ring is a whole turn round the slice's own middle."""
    su, sg = raw["spider-unit"], raw["segment"]
    big = raw["segmented-unit"]["big-demolisher"]["animation"]
    stomper = su["big-stomper-pentapod"]["graphics_set"]
    strafer = su["big-strafer-pentapod"]["graphics_set"]
    return {
        "demolisher-head": (big, range(0, 128, 2), 0, "z", 56, 48, 4),
        "demolisher-segment": (scaled(sg["big-demolisher-segment-x1_52"]["animation"], 1.52), range(0, 128, 2), 0,
                               "x", 40, 36, 4),
        "demolisher-tail": (scaled(sg["big-demolisher-tail-x0_64"]["animation"], 0.64), range(0, 128, 2), 0,
                            "z", 30, 32, 4),
        "stomper-torso": (stomper["animation"], range(64), 0, "z", 30, 36, 4),
        "strafer-torso": ({"layers": [strafer["base_animation"], strafer["animation"]]}, range(64), 0, "z", 30, 36, 5),
    }


def frames_of(anim, dirs, frame):
    return [tt.frame_canvas(cs.frame_layers(anim, d, frame)) for d in dirs]


def _with_dirs(n, fn, *a):
    old = tt.N_DIR
    tt.N_DIR = n
    try:
        return fn(*a)
    finally:
        tt.N_DIR = old


def fit(masks, res):
    """The camera's handedness and north-south scale that the carved hull reprojects best with."""
    best = None
    for hand in (1, -1):
        for b in np.arange(0.55, 1.36, 0.05):
            cam = tt.Camera(b=float(b), hand=hand, anchor=0.0, size=CANVAS)
            pts = _with_dirs(len(masks), tt.carve, masks, cam, res)[0]
            if len(pts):
                s = _with_dirs(len(masks), tt.splat_iou, pts, masks, cam, res)
                if best is None or s > best[0]:
                    best = (s, hand, float(b))
    print("    camera: hand %+d  b %.2f  IoU %.3f" % (best[1], best[2], best[0]))
    return best[1], best[2]


def colours(pts, frames, cam):
    """Each surface voxel's colour from the frames where it is the nearest to the camera."""
    acc = np.zeros((len(pts), 3))
    cnt = np.zeros(len(pts))
    n = len(frames)
    for i in range(0, n, 2):
        u, v, close = cam.project(pts, 2 * math.pi * i / n)
        ui, vi = np.round(u).astype(int), np.round(v).astype(int)
        ok = (ui >= 0) & (ui < CANVAS) & (vi >= 0) & (vi < CANVAS)
        pix = np.where(ok, vi * CANVAS + ui, -1)
        sel = np.nonzero(ok)[0]
        order = sel[np.lexsort((close[sel], pix[sel]))]
        last = np.r_[pix[order][1:] != pix[order][:-1], True]
        top = np.zeros(len(pts), bool)
        top[order[last]] = True
        f = frames[i]
        use = top & (f[vi.clip(0, CANVAS - 1), ui.clip(0, CANVAS - 1), 3] > 0.9)
        acc[use] += f[vi[use], ui[use], :3]
        cnt[use] += 1
    return acc, cnt


def rings(pts, rgb, seen, axis, slices, angles):
    """[(s, centre across, centre height, [radius...], [colour...]), ...]: slices along `axis`
    (glTF's x east or z south), each a polar outline round its middle in the plane across it
    (across = x for z slices, z for x slices), angles counted from across + towards up."""
    along = 0 if axis == "x" else 2
    across = 2 if axis == "x" else 0
    s0, s1 = pts[:, along].min(), pts[:, along].max()
    edges = np.linspace(s0, s1, slices + 1)
    th = np.linspace(0.0, 2 * math.pi, angles, endpoint=False)
    out = []
    for j in range(slices):
        sel = (pts[:, along] >= edges[j]) & (pts[:, along] <= edges[j + 1])
        if sel.sum() < 4:
            continue
        p, c, s = pts[sel], rgb[sel], seen[sel]
        cu = float((p[:, across].min() + p[:, across].max()) / 2)
        cy = float((p[:, 1].min() + p[:, 1].max()) / 2)
        ang = np.mod(np.arctan2(p[:, 1] - cy, p[:, across] - cu), 2 * math.pi)
        dist = np.hypot(p[:, across] - cu, p[:, 1] - cy)
        rr, cc = [], []
        width = (th[1] - th[0]) * 0.75
        for t in th:
            m = np.abs(np.angle(np.exp(1j * (ang - t)))) <= width
            if not m.any():
                rr.append(0.0)
                cc.append(None)
                continue
            k = np.argmax(np.where(m, dist, -1))
            rr.append(float(dist[k]))
            near = m & (dist >= dist[k] - 0.12) & s
            cc.append(c[near].mean(axis=0) if near.any() else None)
        out.append(((edges[j] + edges[j + 1]) / 2, cu, cy, rr, cc))
    return out


def classify(profile, k):
    """Colour classes of the ring points (k-means in Lab), sorted dark to light; letters a, b..."""
    from scipy.cluster.vq import kmeans2
    cols = np.array([c for *_, cc in profile for c in cc if c is not None])
    lab = tt.srgb_to_lab(cols)
    np.random.seed(2)
    centres, labels = kmeans2(lab, k, minit="++", seed=2)
    order = np.argsort(centres[:, 0])
    rank = {int(o): i for i, o in enumerate(order)}
    out = []
    for z, cu, cy, rr, cc in profile:
        letters, last = [], None
        for c in cc:
            if c is not None:
                d = np.linalg.norm(centres - tt.srgb_to_lab(np.array([c]))[0], axis=1)
                last = "abcdefgh"[rank[int(np.argmin(d))]]
            letters.append(last or "a")
        out.append((round(float(z), 3), round(cu, 3), round(cy, 3), [round(r, 3) for r in rr], "".join(letters)))
    swatches = []
    for i in order:
        m = np.median(cols[labels == i], axis=0) if (labels == i).any() else np.array([0.5] * 3)
        swatches.append("%02x%02x%02x" % tuple(int(round(v * 255)) for v in np.clip(m, 0, 1)))
    return out, swatches


def measure(name, src, res, do_fit):
    from scipy import ndimage
    anim, dirs, frame, axis, slices, angles, k = src
    dirs = list(dirs)
    print("%s: %d directions" % (name, len(dirs)))
    frames = frames_of(anim, dirs, frame)
    masks = tt.masks_of(frames, dilate=1)
    if do_fit:
        hand, b = fit(masks, res * 1.5)
    else:
        hand, b = 1, tt.B_CLIENT
    cam = tt.Camera(b=b, hand=hand, anchor=0.0, size=CANVAS)
    pts, ijk, shape, origin = _with_dirs(len(masks), tt.carve, masks, cam, res)
    print("    carved %d voxels" % len(pts))
    vol = np.zeros(shape, bool)
    vol[ijk[:, 0], ijk[:, 1], ijk[:, 2]] = True
    surf = ~ndimage.binary_erosion(vol)[ijk[:, 0], ijk[:, 1], ijk[:, 2]]
    idx = np.nonzero(surf)[0]
    acc, cnt = colours(pts[idx], frames, cam)
    rgb = np.zeros((len(pts), 3))
    seen = np.zeros(len(pts), bool)
    rgb[idx[cnt > 0]] = acc[cnt > 0] / cnt[cnt > 0, None]
    seen[idx[cnt > 0]] = True
    prof, swatches = classify(rings(pts, rgb, seen, axis, slices, angles), k)
    os.makedirs(OUT, exist_ok=True)
    tt.mesh_hull(ijk, shape, origin, res, 12000).export(os.path.join(OUT, name + "-hull.glb"))
    return {"axis": axis, "rings": prof, "classes": swatches, "camera": [hand, round(float(b), 3)]}


def relief_sources(raw):
    """name -> (animation, frame, footprint depth / width, flat height or None). Spawners and their
    corpses have one picture: they are measured as heaps (or a splash on the ground) whose every
    east-west column matches the sprite's outline."""
    s, c = raw["unit-spawner"], raw["corpse"]
    return {
        "gleba-spawner": ({"layers": [s["gleba-spawner"]["graphics_set"]["animations"][0]]}, 0, 1.0, None),
        "gleba-spawner-small": ({"layers": [s["gleba-spawner-small"]["graphics_set"]["animations"][0]]}, 0, 1.0, None),
        "gleba-spawner-corpse": (c["gleba-spawner-corpse"]["animation"], 0, None, 0.06),
    }


def relief(name, src, step=0.0625):
    """Columns (x, centre z, half depth, height) and sacs (x, y, z, radius) of a heap seen in one
    picture. Each column is a half-ellipse across the ground: its south edge where the sprite's
    outline ends at the bottom of that column, its depth from a round footprint (`ratio` of the
    width), its height so its top shows where the outline's top is. A flat splash's columns are
    every stretch of the outline down each column, laid flat on the ground at a fixed height.
    Sacs are the sprite's green egg sacs, each set into the heap where its middle shows."""
    from scipy import ndimage
    anim, frame, ratio, flat = src
    f = tt.frame_canvas(cs.frame_layers(anim, 0, frame))
    mask = f[..., 3] > 0.5
    lab, n = ndimage.label(mask)
    if n > 1:  # the heap is the biggest piece; specks and drips aside
        sizes = ndimage.sum(mask, lab, range(1, n + 1))
        keep = 1 + int(np.argmax(sizes))
        mask = lab == keep if flat is None else ndimage.binary_closing(mask, iterations=2)
    ppt, a, b = tt.PPT, tt.A_UP, tt.B_CLIENT
    cx = CANVAS / 2
    cols_px = np.nonzero(mask.any(axis=0))[0]
    x_min, x_max = (cols_px.min() - cx) / ppt, (cols_px.max() + 1 - cx) / ppt
    half_w = (x_max - x_min) / 2
    x_mid = (x_max + x_min) / 2
    cols = []
    for x in np.arange(x_min + step / 2, x_max, step):
        u = int(round(cx + x * ppt))
        if flat is not None:
            inside = mask[:, u]
            edges = np.flatnonzero(np.diff(np.r_[0, inside.astype(np.int8), 0]))
            for v0, v1 in zip(edges[::2], edges[1::2]):
                z0, z1 = (v0 - cx) / ppt / b, (v1 - cx) / ppt / b
                cols.append((round(float(x), 3), round(float(z0 + z1) / 2, 3), round(float(z1 - z0) / 2, 3), flat))
            continue
        run = np.nonzero(mask[:, max(0, u - 1):u + 2].any(axis=1))[0]
        if len(run) == 0:
            continue
        # Screen heights (tiles up the screen from the entity's position).
        s_top, s_bot = (cx - run.min()) / ppt, (cx - run.max()) / ppt
        k = max(0.0, 1.0 - ((x - x_mid) / half_w) ** 2)
        d = max(0.05, ratio * half_w * math.sqrt(k))
        zc = -s_bot / b - d
        top = s_top + b * zc
        h = math.sqrt(max(0.0, top * top - (b * d) ** 2)) / a
        cols.append((round(float(x), 3), round(float(zc), 3), round(float(d), 3), round(float(h), 3)))
    if flat is None and len(cols) > 4:
        # Neighbouring columns' heights and middles evened out over a quarter of a tile, so the
        # heap is round from behind too (single sacs at the outline's top make spikes).
        arr = np.array(cols)
        for j in (1, 3):
            arr[:, j] = np.convolve(np.pad(arr[:, j], 2, mode="edge"), np.ones(5) / 5, "valid")
        cols = [tuple(round(float(v), 3) for v in row) for row in arr]
    sacs = []
    if flat is None:
        # Blurred: the sacs are veined with the membrane's orange. Hue past 60 degrees: the sacs
        # are yellow-green, the membrane round them orange.
        rgb = np.stack([ndimage.gaussian_filter(f[..., k], 5) for k in range(3)], axis=-1)
        mx, mn = rgb.max(axis=-1), rgb.min(axis=-1)
        hue = np.degrees(np.arctan2(math.sqrt(3) * (rgb[..., 1] - rgb[..., 2]),
                                    2 * rgb[..., 0] - rgb[..., 1] - rgb[..., 2])) % 360
        green = mask & (hue > 60) & (hue < 160) & (mx - mn > 0.04)
        green = ndimage.binary_fill_holes(ndimage.binary_opening(green, iterations=3))
        # Sacs touch: each is the largest disc left in the green, biggest first; the veins
        # over them hide its rim, so each is drawn bigger than its green.
        yy, xx = np.mgrid[0:mask.shape[0], 0:mask.shape[1]]
        covered = np.zeros_like(mask)
        for _ in range(12):
            dist = ndimage.distance_transform_edt(green & ~covered)
            py, px = np.unravel_index(np.argmax(dist), dist.shape)
            rad = float(dist[py, px])
            if rad < 0.15 * ppt:
                break
            covered |= (yy - py) ** 2 + (xx - px) ** 2 <= (rad * 1.4) ** 2
            r = rad / ppt * 1.4
            x, s = (px - cx) / ppt, (cx - py) / ppt
            _, zc, d, h = min(cols, key=lambda c: abs(c[0] - x))
            # The front-most point of that column's ellipse that shows at screen height s.
            best = None
            for t in np.linspace(0.0, math.pi / 2, 40):
                z, y = zc + d * math.cos(t), h * math.sin(t)
                if best is None or abs(a * y - b * z - s) < best[0]:
                    best = (abs(a * y - b * z - s), y, z)
            _, y, z = best
            sacs.append((round(float(x), 3), round(float(max(r * 0.6, y - r * 0.4)), 3), round(float(z), 3),
                         round(float(r), 3)))
    print("%s: %d columns, %d sacs" % (name, len(cols), len(sacs)))
    return {"columns": cols, "bulbs": sacs}


def write(table, reliefs):
    lines = ['"""Space Age creatures\' shapes, measured from Factorio\'s rotation sprites by',
             'tools/models/creature_hull.py (the visual hull of every direction\'s silhouette): numbers only.',
             '',
             'Each part is {"axis", "rings", "classes"}: sliced along glTF\'s x (east) or z (south; the part',
             'faces north). A ring is (s, centre across, centre height, radii, colour classes): s along the',
             'axis in tiles, its centre in the plane across it (across is x for z slices, z for x slices),',
             'radii at evenly spaced angles all the way round from across +, towards up, and one letter',
             'per radius for the colour seen there, `classes` giving each letter\'s median sprite colour,',
             'darkest first.',
             '"""', '', 'PROFILES = {']
    for name, prof in table.items():
        lines.append("    %r: {" % name)
        lines.append("        'axis': %r, 'classes': %r, 'camera': %r," % (prof["axis"], prof["classes"], prof["camera"]))
        lines.append("        'rings': [")
        for ring in prof["rings"]:
            lines.append("            %r," % (ring,))
        lines.append("        ],")
        lines.append("    },")
    lines.append("}")
    lines += ["", "# Spawners and their corpses, one picture each: east-west columns (x, centre z, half depth,",
              "# height: a half-ellipse across the ground under each) and egg sacs (x, height, z, radius).",
              "RELIEFS = {"]
    for name, r in reliefs.items():
        lines.append("    %r: {" % name)
        lines.append("        'columns': [")
        for i in range(0, len(r["columns"]), 3):
            lines.append("            " + " ".join("%r," % (c,) for c in r["columns"][i:i + 3]))
        lines.append("        ],")
        lines.append("        'bulbs': %r," % (r["bulbs"],))
        lines.append("    },")
    lines.append("}")
    with open(PROFILES, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def main(argv):
    res = 0.04
    for a in argv:
        if a.startswith("--res="):
            res = float(a.split("=")[1])
    names = [a for a in argv if not a.startswith("--")]
    tt.CANVAS = CANVAS
    src = sources(cs.data_raw())
    rsrc = relief_sources(cs.data_raw())
    table, reliefs = {}, {}
    if os.path.exists(PROFILES):
        import creature_profiles
        table = dict(creature_profiles.PROFILES)
        reliefs = dict(getattr(creature_profiles, "RELIEFS", {}))
    for name in names or list(src) + list(rsrc):
        if name in rsrc:
            reliefs[name] = relief(name, rsrc[name])
        else:
            table[name] = measure(name, src[name], res, "--fit" in argv)
    write(table, reliefs)
    print("wrote %s" % PROFILES)


if __name__ == "__main__":
    main(sys.argv[1:])
