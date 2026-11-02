#!/usr/bin/env python3
"""Scores the character's armour looks against Factorio's sprites, idle and running, as the client
draws them: silhouette overlap (intersection over union) in all eight directions.

    python tools/models/armour_score.py [names...] [--pictures] [--compare]

- idle: the model at rest (the client's idle is the rest pose) against the idle animation's first
  frame;
- plates: only the armour (its plates, depth-tested against the body in front of them) against
  only the add-on layer and its mask, idle: how well the plates match what the armour adds;
- run: the model posed by the client's run (turntable_anim.CharacterGait's loop, started where it
  best matches the sprite's frame 0) against every other frame of the running animation.

Each look is scored against Factorio's layers for its armour: the plain character (level1) under
the add-on (level2addon for heavy and modular armour, level3addon for power armour), masks
included. The model is placed as the client places it (no fitted scale or offset). --pictures
writes contact sheets to the git-ignored art-src/turntable/anim/ (they show Factorio's art).
--compare also runs compare.py on the idle frame north, east, south and west (its overlap and
colour, as the other model sessions' tables; panels in the git-ignored art-src/compare/armour/).
"""

import math
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import turntable as tt  # noqa: E402
import turntable_anim as ta  # noqa: E402

# Layers per animation (character-animations.lua): (file, width, height, shift), 22 frames a row,
# a row per direction.
LAYERS = {
    ("idle", 1): [("level1_idle", 92, 116, (0, -21)), ("level1_idle_mask", 56, 90, (0, -26))],
    ("idle", 2): [("level2addon_idle", 56, 86, (0.5, -27.5)), ("level2addon_idle_mask", 52, 84, (0, -28))],
    ("idle", 3): [("level3addon_idle", 74, 86, (0, -28)), ("level3addon_idle_mask", 74, 72, (0, -31.5))],
    ("run", 1): [("level1_running", 88, 132, (0, -18)), ("level1_running_mask", 78, 110, (0, -22))],
    ("run", 2): [("level2addon_running", 70, 106, (0, -25)), ("level2addon_running_mask", 70, 104, (0, -25.5))],
    ("run", 3): [("level3addon_running", 80, 108, (0, -25)), ("level3addon_running_mask", 78, 88, (0, -28.5))],
}
LEVEL = {"character": 1, "character-armor-2": 2, "character-armor-3": 3}
FRAMES = 22
RUN_FRAMES = range(0, FRAMES, 2)
# Full resolution (64 px a tile, as the HR frames and compare.py), not turntable_anim's half.
ta.PPT, ta.SIZE = tt.PPT, tt.CANVAS


def layers(anim, level):
    def fn(d, f):
        out = []
        for lv in sorted({1, level}):
            out += [ta.sp_layer("character/%s.png" % n, w, h, sh, FRAMES, d * FRAMES + f)
                    for n, w, h, sh in LAYERS[(anim, lv)]]
        return out
    return fn


def masks_for(layers_fn, dirs, frames):
    """[frame][dir] -> the sprite's outline at full resolution."""
    return [[tt.frame_canvas(layers_fn(d, f))[..., 3] > 0.5 for d in range(dirs)] for f in range(frames)]


def plates(name, fitter):
    """Idle overlap of the visible armour plates with the add-on layer alone, per direction."""
    import trimesh
    level = LEVEL[name]
    addon = [[tt.frame_canvas([ta.sp_layer("character/%s.png" % n, w, h, sh, FRAMES, d * FRAMES)
                               for n, w, h, sh in LAYERS[("idle", level)]])[..., 3] > 0.5 for d in range(8)]]
    scene = trimesh.load(os.path.join(tt.MODELS, name + ".glb"), force="scene")
    tris, flag = [], []
    for node in scene.graph.nodes_geometry:
        transform, geom = scene.graph[node]
        mesh = scene.geometry[geom].copy()
        mesh.apply_transform(transform)
        tris.append(mesh.triangles)
        armour = str(getattr(mesh.visual.material, "name", "")).startswith("armour_")
        flag.append(np.full((len(mesh.faces), 3), 1.0 if armour else 0.0))
    tris, flag = np.concatenate(tris), np.concatenate(flag)
    out = []
    for d in range(8):
        m, rgb, _ = tt.render(tris, flag, fitter.cam, 2 * math.pi * d / 8, size=tt.CANVAS, shade=False)
        out.append(tt.iou(m & (rgb[..., 0] > 0.5), addon[0][d]))
    return out


def score(name, pictures=False):
    level = LEVEL[name]
    idle = masks_for(layers("idle", level), 8, 1)
    run = masks_for(layers("run", level), 8, FRAMES)
    pts, uv, _col, tris, tcol, tuv = ta.load_points(os.path.join(tt.MODELS, name + ".glb"))
    rig = ta.CharacterRig()
    fitter = ta.Fitter(rig, pts, uv, idle, 8, 0.0)
    rest = np.zeros(rig.n)
    idle_ious = fitter.ious(rest, 0)
    plate_ious = plates(name, fitter) if level > 1 else []
    fitter.masks = run
    gait = ta.CharacterGait()
    g = np.array(gait.G0, float)

    def run_ious(phase):
        h = g.copy()
        h[2] = phase
        xs = gait.frames(h, FRAMES)
        return [fitter.ious(xs[f], f) for f in RUN_FRAMES], xs

    phase = max(np.linspace(-math.pi, math.pi, 25), key=lambda p: np.mean(run_ious(p)[0]))
    ious, xs = run_ious(phase)
    per_dir = np.mean(np.asarray(ious), axis=0)
    if pictures:
        os.makedirs(ta.OUT, exist_ok=True)
        full = [fitter.ious(x, f) for f, x in enumerate(xs)]
        ta.contact_sheet(name + "_run", layers("run", level), fitter, tris, tcol, tuv, xs, full, (0, 2, 4, 6),
                         FRAMES, 8)
    return idle_ious, plate_ious, list(per_dir)


def compare(name):
    """compare.py on the idle frame each way: [(direction, overlap, sprite colour, model colour)]."""
    import gallery
    out_dir = os.path.join(gallery.REPO, "art-src", "compare", "armour")
    os.makedirs(out_dir, exist_ok=True)

    def one(i):
        d = 2 * i  # N, E, S, W of the eight
        sheet, *rest = gallery.BUILDINGS[name]
        args = [re.sub(r"\|0\|22\|", "|%d|22|" % (22 * d), a) for a in rest]
        cmd = [gallery.BLENDER, "--background", "--factory-startup", "--python", "tools/models/compare.py", "--",
               os.path.join(out_dir, "%s-%s.png" % (name, "NESW"[i])), name,
               "--sprite=" + os.path.join(gallery.FACTORIO, sheet), *args, "--index=%d" % (22 * d), "--rot=%d" % (90 * i)]
        run = subprocess.run(cmd, cwd=gallery.REPO, capture_output=True, text=True)
        m = re.search(r"sprite (\S+)\s+model (\S+)\s+silhouette overlap ([\d.]+)", run.stdout)
        return ("NESW"[i], float(m.group(3)), m.group(1), m.group(2)) if m else ("NESW"[i], None, "", "")

    with ThreadPoolExecutor(4) as pool:
        return list(pool.map(one, range(4)))


def main(argv):
    names = [a for a in argv if not a.startswith("--")] or list(LEVEL)
    print("%-20s %-46s %s" % ("model", "idle N NE E SE S SW W NW (mean)", "run (mean)"))
    for n in names:
        idle, plate, run = score(n, "--pictures" in argv)
        print("%-20s %s (%.2f)   %s (%.2f)" % (n, " ".join("%.2f" % v for v in idle), np.mean(idle),
                                             " ".join("%.2f" % v for v in run), np.mean(run)))
        if plate:
            print("    plates against the add-on, idle: %s (%.2f)" % (" ".join("%.2f" % v for v in plate), np.mean(plate)))
        if "--compare" in argv and n != "character" or "--compare" in argv and len(names) == 1:
            print("    compare.py idle: " + "  ".join("%s %s" % (d, "err" if v is None else "%.2f (%s / %s)" % (v, a, b))
                                                    for d, v, a, b in compare(n)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
