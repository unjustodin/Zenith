#!/usr/bin/env python3
"""Score Nauvis's enemy models against Factorio's own sprites, from every direction they have.

    python tools/models/creature_score.py                       # every enemy model
    python tools/models/creature_score.py big-biter big-spitter # some of them
    python tools/models/creature_score.py --frames big-biter-attack   # IoU per animation frame too
    python tools/models/creature_score.py --space               # Space Age's: demolishers, pentapods, Gleba spawners

A corpse of a biter or spitter is four models, one for each of the falls Factorio's dying sheets take
turns with round the directions (creature_pose.py): each is scored on its own four directions.

Each model is rendered from Factorio's camera (turntable.py's: orthographic, 64 px a tile,
height * cos 48 deg up the screen) for each direction its sprite has (16 for units, 1 for worms and
spawners, which are tried at 16 turns) and compared, silhouette against the sprite's alpha (shadow
layers left out), as IoU after the best nudge of a few pixels. Frame layouts (files, sizes, shifts,
scales, frame counts) are read from `factorio --dump-data` (cached in art-src/turntable/), so they
are Factorio's own.

Pictures (sprite | model, per direction) go to the git-ignored art-src/turntable/creatures/;
they are made from Factorio's sprites and are never committed. Needs the venv (as turntable.py).
"""

import json
import math
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, "tools"))
import turntable as tt  # noqa: E402

OUT = os.path.join(tt.OUT, "creatures")
DUMP = os.path.join(tt.OUT, "data-raw-dump.json")


def data_raw():
    if not os.path.exists(DUMP):
        import icon_index
        os.makedirs(tt.OUT, exist_ok=True)
        json.dump(icon_index.dump(tt.FACTORIO), open(DUMP, "w"))
    return json.load(open(DUMP))


def _layers(anim):
    """The drawn (not shadow) layers of an animation, as plain dicts."""
    if anim is None:
        return []
    if isinstance(anim, list):
        anim = anim[0]
    if "layers" in anim:
        return [ly for a in anim["layers"] for ly in _layers(a)]
    if anim.get("draw_as_shadow") or anim.get("draw_as_glow"):
        return []
    return [anim]


def _file(path):
    return path.replace("__base__/", "base/").replace("__space-age__/", "space-age/")


def frame_layers(anim, direction, frame):
    """turntable.frame_canvas layers for one frame of one direction (Factorio's frame order:
    direction-major, `frame_count` frames each; stripes or sprite_load files of lines x line)."""
    out = []
    for ly in _layers(anim):
        n = ly.get("frame_count", 1) or 1
        f = min(frame, n - 1)
        if ly.get("repeat_count"):
            f = 0
        k = direction * n + f
        # A sliced sheet has `slice` frames a row (one direction a row), whatever line_length says.
        line = ly.get("slice") or ly.get("line_length") or n
        if "filenames" in ly:
            per = (ly.get("lines_per_file") or 1) * line
            path, idx = ly["filenames"][k // per], k % per
        elif "stripes" in ly:
            # One stripe per direction: width_in_frames frames side by side.
            stripe = ly["stripes"][direction]
            path, idx, line = stripe["filename"], f, stripe.get("width_in_frames", n)
        else:
            path, idx = ly["filename"], k
        sh = ly.get("shift") or [0, 0]
        out.append({"file": _file(path), "frame": [ly["width"], ly["height"]], "line": line, "index": idx,
                    "shift": [sh[0] * 32.0, sh[1] * 32.0], "scale": ly.get("scale", 1.0)})
    return out


def frame_count(anim):
    ls = _layers(anim)
    return max((ly.get("frame_count", 1) or 1) for ly in ls) if ls else 1


def direction_count(anim):
    ls = _layers(anim)
    return max((ly.get("direction_count", 1) or 1) for ly in ls) if ls else 1


def references(raw):
    """model -> (animation, frame or None for every frame, note)."""
    u, c, t, s = raw["unit"], raw["corpse"], raw["turret"], raw["unit-spawner"]

    def corpse_end(anim):
        return frame_count(anim) - 1
    refs = {
        "big-biter": (u["big-biter"]["run_animation"], 0, "run, frame 0"),
        "big-biter-attack": (u["big-biter"]["attack_parameters"]["animation"], None, "attack, best frame"),
        "big-biter-corpse": (c["big-biter-corpse"]["animation"], corpse_end(c["big-biter-corpse"]["animation"]),
                             "corpse, last dying frame"),
        "big-spitter": (u["big-spitter"]["run_animation"], 0, "run, frame 0"),
        "big-spitter-attack": (u["big-spitter"]["attack_parameters"]["animation"], None, "attack, best frame"),
        "big-spitter-corpse": (c["big-spitter-corpse"]["animation"], corpse_end(c["big-spitter-corpse"]["animation"]),
                               "corpse, last dying frame"),
        "big-worm-turret": (t["big-worm-turret"]["prepared_animation"], 0, "prepared, frame 0"),
        "big-worm-turret-corpse": (c["big-worm-corpse"]["animation"], corpse_end(c["big-worm-corpse"]["animation"]),
                                   "corpse, last dying frame"),
        "biter-spawner": (s["biter-spawner"]["graphics_set"]["animations"], 0, "idle, frame 0"),
    }
    if "biter-spawner-corpse" in c:
        refs["biter-spawner-corpse"] = (c["biter-spawner-corpse"]["animation"],
                                        corpse_end(c["biter-spawner-corpse"]["animation"]), "corpse, last dying frame")
    return refs


def scaled(anim, k):
    """The animation's drawn layers with scale and shift divided by k: a segment Factorio draws
    at 1.52 compared with the model built at 1."""
    out = []
    for ly in _layers(anim):
        ly = dict(ly)
        ly["scale"] = ly.get("scale", 1.0) / k
        if ly.get("shift"):
            ly["shift"] = [c / k for c in ly["shift"]]
        out.append(ly)
    return {"layers": out}


def space_references(raw):
    """Space Age's creatures: model -> (animation, frame, note, options). Options: `step` scores
    every n-th direction (demolishers have 128), `exclude` leaves out the model's nodes starting
    with it (a pentapod's legs: Factorio draws them as separate entities, posed where they step),
    `centre` lines the render up with the sprite by their centres before the usual nudge (a
    torso floats at its bobbing height)."""
    u, c, s, su, sg = raw["unit"], raw["corpse"], raw["unit-spawner"], raw["spider-unit"], raw["segment"]
    stomper = su["big-stomper-pentapod"]["graphics_set"]
    strafer = su["big-strafer-pentapod"]["graphics_set"]
    legs = {"exclude": "anim_leg", "centre": True}
    return {
        "demolisher-head": (raw["segmented-unit"]["big-demolisher"]["animation"], 0, "head, big (x1)", {"step": 2}),
        "demolisher-segment": (scaled(sg["big-demolisher-segment-x1_52"]["animation"], 1.52), 0,
                               "segment x1.52 drawn at x1", {"step": 2}),
        "demolisher-tail": (scaled(sg["big-demolisher-tail-x0_64"]["animation"], 0.64), 0, "tail x0.64 drawn at x1",
                            {"step": 2}),
        "big-stomper-pentapod": (stomper["animation"], 0, "torso (legs left out)", legs),
        "big-strafer-pentapod": ({"layers": [strafer["base_animation"], strafer["animation"]]}, 0,
                                 "torso (legs left out)", legs),
        "big-wriggler-pentapod": (u["big-wriggler-pentapod"]["run_animation"], 0, "run, frame 0", {}),
        "gleba-spawner": (s["gleba-spawner"]["graphics_set"]["animations"], 0, "idle, frame 0", {}),
        "gleba-spawner-small": (s["gleba-spawner-small"]["graphics_set"]["animations"], 0, "idle, frame 0", {}),
        "gleba-spawner-corpse": (c["gleba-spawner-corpse"]["animation"], 0, "corpse", {}),
    }


def masks_for(anim, frame, dirs=None):
    dirs = dirs if dirs is not None else range(direction_count(anim))
    frames = [tt.frame_canvas(frame_layers(anim, d, frame)) for d in dirs]
    return frames, [f[..., 3] > 0.5 for f in frames]


def _centred(render, mask):
    """The render (mask, rgb, ...) moved so its silhouette's centre is on the sprite's."""
    ys, xs = np.nonzero(render[0])
    ty, tx = np.nonzero(mask)
    if len(ys) == 0 or len(ty) == 0:
        return render
    dy, dx = int(round(ty.mean() - ys.mean())), int(round(tx.mean() - xs.mean()))
    return tuple(np.roll(np.roll(a, dy, 0), dx, 1) for a in render)


def score(model, anim, frame, cam, per_frame=False, path=None, opts=None):
    opts = opts or {}
    path = path or os.path.join(tt.MODELS, model + ".glb")
    tris, cols = tt.load_glb(path, exclude=opts.get("exclude"))
    dirs = direction_count(anim)
    used = opts.get("dirs") or list(range(0, dirs, opts.get("step", 1)))
    frames_to_try = range(frame_count(anim)) if frame is None else [frame]
    best = None
    for f in frames_to_try:
        imgs, masks = masks_for(anim, f, used)
        if dirs > 1:
            renders = [tt.render(tris, cols, cam, 2 * math.pi * d / dirs) for d in used]
            if opts.get("centre"):
                renders = [_centred(r, m) for r, m in zip(renders, masks)]
            ious = [tt.best_shift_iou(r[0], m)[0] for r, m in zip(renders, masks)]
            turn = 0
        else:
            # One picture: the model may have been turned any way; take its best turn of 16.
            trial = []
            for k in range(16):
                r = tt.render(tris, cols, cam, 2 * math.pi * k / 16)
                trial.append((tt.best_shift_iou(r[0], masks[0])[0], k, r))
            iou_, turn, r = max(trial, key=lambda x: x[0])
            renders, ious = [r], [iou_]
        mean = float(np.mean(ious))
        if per_frame:
            print("    frame %2d: IoU %.3f" % (f, mean))
        if best is None or mean > best[0]:
            best = (mean, f, ious, imgs, renders, turn)
    return best


def contact(model, best, note):
    mean, f, ious, imgs, renders, turn = best
    show = list(range(len(imgs)))[:: max(1, len(imgs) // 8)]
    cols = []
    for d in show:
        s = tt.sprite_img(imgs[d])
        m = tt.to_img(renders[d][1], renders[d][0])
        cols.append((s, m, ious[d], d))
    y0, y1, x0, x1 = tt.crop_box([im for c in cols for im in c[:2]])
    tw, th = x1 - x0, y1 - y0
    sheet = Image.new("RGB", (tw * len(cols), th * 2), (30, 30, 30))
    for i, (s, m, v, d) in enumerate(cols):
        sheet.paste(tt.label(Image.fromarray(s[y0:y1, x0:x1].copy()), "sprite dir %d" % d), (i * tw, 0))
        sheet.paste(tt.label(Image.fromarray(m[y0:y1, x0:x1].copy()), "model %.2f" % v), (i * tw, th))
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, model + ".png")
    sheet.save(path)
    return path


def main(argv):
    per_frame = "--frames" in argv
    names = [a for a in argv if not a.startswith("--")]
    raw = data_raw()
    refs = {k: v + ({},) for k, v in references(raw).items()}
    # A corpse is four models, each for the directions its fall is drawn in (creature_pose.py).
    import creature_pose
    for family in ("biter", "spitter"):
        anim, frame, note, _ = refs["big-%s-corpse" % family]
        for v in range(creature_pose.CORPSE_VARIANTS):
            refs[creature_pose.corpse_model("big-%s-corpse" % family, v)] = (
                anim, frame, note + ", directions %d mod 4" % v, {"dirs": list(range(v, 16, creature_pose.CORPSE_VARIANTS))})
    space = space_references(raw)
    refs.update(space)
    if "--space" in argv or any(n in space for n in names):
        # Demolishers are bigger than the default canvas.
        tt.CANVAS = 1024
        names = names or list(space)
    cam = tt.Camera(anchor=0.0, size=tt.CANVAS)
    report = {}
    for model in names or [k for k in refs if k not in space]:
        if model not in refs or not os.path.exists(os.path.join(tt.MODELS, model + ".glb")):
            print("%s: no model or no reference" % model)
            continue
        anim, frame, note, opts = refs[model]
        best = score(model, anim, frame, cam, per_frame, opts=opts)
        mean, f, ious = best[0], best[1], best[2]
        path = contact(model, best, note)
        report[model] = {"iou_mean": round(mean, 3), "iou_min": round(float(np.min(ious)), 3), "frame": f,
                         "directions": len(ious), "reference": note, "per_direction": [round(v, 3) for v in ious]}
        print("%-24s IoU mean %.3f  min %.3f  (%d directions, %s, frame %d)  %s" % (
            model, mean, np.min(ious), len(ious), note, f, os.path.relpath(path, REPO)))
    os.makedirs(OUT, exist_ok=True)
    out = os.path.join(OUT, "scores.json")
    old = json.load(open(out)) if os.path.exists(out) else {}
    old.update(report)
    json.dump(old, open(out, "w"), indent=1)


if __name__ == "__main__":
    main(sys.argv[1:])
