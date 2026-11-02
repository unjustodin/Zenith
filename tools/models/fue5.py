#!/usr/bin/env python3
"""Converts the FUE5 fan project's models (https://github.com/FUE5BASE/FUE5, by Hurricane and
Nuke, CC BY-NC-SA 3.0) into client models in client/assets/models/fue5/.

    python tools/models/fue5.py [names...] [--out DIR] [--yaw DEG]   # build (Blender)
    python tools/models/fue5.py --score [names...] [--glb-dir DIR]     # overlap, ours and theirs

Source files: FUE5's FBX files and the .jpg textures beside them, from
Content/MyStuff/ENTITIES/STRUCTURES and VEHICLES of its repository, in the git-ignored
art-src/fue5/raw/<STRUCTURES|VEHICLES>/<model>/ (never committed). A conversion (fue5_blender.py)
scales them to tiles (2 units a tile), turns them to face north, drops ground decals, decimates to
the triangle budget in specs.py and bakes every texture into one atlas; moving parts named in a
recipe become `anim_*` nodes. Scoring uses fit.py's silhouette overlap against Factorio's sprites.
"""

import argparse
import json
import math
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import specs  # noqa: E402

ART = os.path.normpath(os.path.join(REPO.split(os.sep + ".claude" + os.sep)[0], "art-src", "fue5"))
RAW = os.path.join(ART, "raw")
OUT_DIR = os.path.join(REPO, "client", "assets", "models", "fue5")
BLENDER = os.environ.get("BLENDER", r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe")
GENERATOR = "Zenith tools/models/fue5.py"

# Prototype -> recipe. `fbx` relative to RAW; `yaw` turns the model clockwise (seen from above) so
# its front faces north, found by scoring every quarter turn against the sprite.
RECIPES = {
    # Its two fans from the animated file's bones.
    "electric-furnace": {"fbx": ["STRUCTURES/electric-furnace/static.fbx", "STRUCTURES/electric-furnace/animated1.fbx"],
                         "yaw": 0, "bones": {"anim_spin_fan": ["spin"], "anim_spin_fan.001": ["spin_1"]}},
    "rocket-silo": {"fbx": ["STRUCTURES/rocket-silo/static.fbx"], "yaw": 90, "centre": "bbox",
                    # FUE5 sinks the hatch 1.1 tiles into a hole in its ground; ours has none, so the
                    # hatch's plate, cut to the ring's opening as the two doors, is raised to just over
                    # the ground, over a dark pit floor as ours has (the rocket waits below it).
                    "hatch": {"mats": ["mat1"], "clear": "door", "zmax": -0.6, "radius": 2.6, "lift_to": 0.03,
                              "west": "anim_door_silo_w", "east": "anim_door_silo_e"},
                    "pit": {"radius": 2.62, "z": 0.015},
                    # Its south-west corner holds a pointed pod on its side that Factorio's silo
                    # doesn't have (the owner's "side pod with rocket").
                    "drop": ["corner"],
                    # Round: matching ours (a little deeper than wide) would make its ring oval.
                    "match": False},
    # Its four wheel sets roll (movers.gd) about their middles.
    "locomotive": {"fbx": ["VEHICLES/locomotive/static.fbx"], "yaw": 270, "match_all": True,
                   "anim": {"anim_wheel_rail": ["wheel"], "anim_wheel_rail.001": ["wheel_2"],
                            "anim_wheel_rail.002": ["wheel_Instance"], "anim_wheel_rail.003": ["wheel_Instance_2"]},
                   "pivot": {"anim_wheel_rail": "bbox", "anim_wheel_rail.001": "bbox",
                             "anim_wheel_rail.002": "bbox", "anim_wheel_rail.003": "bbox"}},
    "oil-refinery": {"fbx": ["STRUCTURES/oil-refinery/static.fbx"], "yaw": 270},
}


def _static(folder, yaw=0, **more):
    return dict({"fbx": ["STRUCTURES/%s/static.fbx" % folder], "yaw": yaw}, **more)


RECIPES.update({
    "wooden-chest": _static("wooden-chest"),
    "iron-chest": _static("iron-chest"),
    "steel-chest": _static("steel-chest"),
    "small-lamp": _static("small-lamp"),
    "solar-panel": _static("solar-panel", 270),
    "stone-furnace": _static("stone-furnace"),
    "steel-furnace": _static("steel-furnace"),
    "lab": _static("lab"),
    "storage-tank": _static("storage-tank"),
    "programmable-speaker": _static("programmable-speaker", 180),
    "arithmetic-combinator": _static("arithmetic-combinator"),
    "decider-combinator": _static("decider-combinator"),
    "constant-combinator": _static("constant-combinator"),
    "accumulator": _static("accumulator"),
    "beacon": _static("beacon"),
})

WHEELS = {"anim_wheel_rail": ["wheel"], "anim_wheel_rail.001": ["wheel_2"],
          "anim_wheel_rail.002": ["wheel_Instance"], "anim_wheel_rail.003": ["wheel_Instance_2"]}
WHEEL_PIVOTS = {k: "bbox" for k in WHEELS}
# Wheel sets moved to ours (1.5 and 2.5 tiles either side of the middle, as Factorio's bogies), so
# they line up with the track and with our wagons' coupling.
WHEEL_PLACES = [{"groups": ["wheel_Instance"], "to": [0.0, None, 2.5]}, {"groups": ["wheel"], "to": [0.0, None, 1.5]},
                {"groups": ["wheel_Instance_2"], "to": [0.0, None, -1.5]}, {"groups": ["wheel_2"], "to": [0.0, None, -2.5]}]
RECIPES["locomotive"]["place"] = WHEEL_PLACES
RECIPES.update({
    # Poles: their insulators where Factorio's wires attach (wires.gd POLE_POINTS: tops for the
    # small pole, middles for the rest), not matched to our poles' size. The small pole's three
    # nearly sit at Factorio's spacing: the pole moves 0.18 north and grows to their height.
    "small-electric-pole": _static("small-electric-pole", match=False, shift=[0.035, 0.18, 0], scale=[0.9, 1, 1.07], place=[
        {"groups": ["Null_1", "Cloner_3"], "to": [0.02, 3.98, -0.18], "anchor": "top"},
        {"groups": ["Null_2_2", "Cloner_4"], "to": [0.46, 3.98, -0.18], "anchor": "top"},
        {"groups": ["Null_0", "Cloner_2"], "to": [-0.38, 3.98, -0.18], "anchor": "top"}]),
    "medium-electric-pole": _static("medium-electric-pole", match=False, scale=[0.72, 1.0, 1.0], place=[
        {"groups": ["Null_1", "Cloner_3"], "to": [0.234, 4.947, 0.0]},
        {"groups": ["Null_2_2", "Cloner_4"], "to": [0.672, 4.48, 0.0]},
        {"groups": ["Null_0", "Cloner_2"], "to": [-0.234, 4.62, 0.0]}]),
    # The big pole and substation have one insulator: it goes on the copper point, and copies of
    # it on the red and green ones. FUE5's substation is modelled 3.5 tiles wide: shrunk into its
    # 2x2 it is also stretched up 1.26x, so its tower reaches the wire points.
    "big-electric-pole": _static("big-electric-pole", match=False, place=[
        {"groups": ["Cloner"], "to": [0.0, 5.784, 0.0]},
        {"groups": ["Cloner"], "to": [0.906, 4.967, 0.0], "copy": True},
        {"groups": ["Cloner"], "to": [-0.906, 4.967, 0.0], "copy": True}]),
    "substation": _static("substation", match=False, scale=[1, 1, 1.26], place=[
        {"groups": ["Cloner_6", "Null_7"], "to": [0.0, 4.316, 0.0]},
        {"groups": ["Cloner_6", "Null_7"], "to": [0.688, 4.083, 0.0], "copy": True},
        {"groups": ["Cloner_6", "Null_7"], "to": [-0.656, 4.13, 0.0], "copy": True}]),
    "roboport": _static("roboport"),
    "train-stop": _static("train-stop", fit="width"),
    "pump": _static("pump"),
    "nuclear-reactor": _static("nuclear-reactor", 90),
    # The dish (its own file) turns on the radar's middle.
    "radar": {"fbx": ["STRUCTURES/radar/static1.fbx", "STRUCTURES/radar/static2.fbx"], "yaw": 0,
              "file_parts": {"1": "anim_spin_radar"}, "pivot": {"anim_spin_radar": "axis"}},
    # The head (its own file) turns where the mod says the turret aims.
    "gun-turret": {"fbx": ["STRUCTURES/gun-turret/static1.fbx", "STRUCTURES/gun-turret/static2.fbx"], "yaw": 0,
                   "file_parts": {"1": "anim_turret_head"}, "pivot": {"anim_turret_head": "axis"}},
    # Rotors from the animated file's bones; its arm and crane stay still.
    "centrifuge": {"fbx": ["STRUCTURES/centrifuge/static.fbx", "STRUCTURES/centrifuge/animated1.fbx"], "yaw": 0,
                   "bones": {"anim_spin_rotor": ["rotation1"], "anim_spin_rotor.001": ["updown2", "rotation2"]}},
    "steam-turbine": {"fbx": ["STRUCTURES/steam-turbine/static.fbx", "STRUCTURES/steam-turbine/animated1.fbx"],
                      "yaw": 90, "bones": {"anim_spin_turbine_fan": ["spin1"]}},
    # FUE5's rocket is 5.9 tiles tall, Factorio's (and ours) 16.9: stretched to our height, and
    # to our width separately (a uniform 2.9x would be 9 tiles wide, past the silo's opening).
    # Its base (FUE5 z 0.8) on the origin, as rockets.gd expects.
    "rocket-silo-rocket": {"fbx": ["VEHICLES/rocket/static.fbx"], "yaw": 0, "match": False,
                           "scale": [1.40, 1.40, 2.887], "shift": [0, 0, -0.796 * 0.5 * 2.887]},
    "cargo-wagon": {"fbx": ["VEHICLES/cargo-wagon/static.fbx"], "yaw": 270, "anim": WHEELS, "pivot": WHEEL_PIVOTS,
                    "match_all": True, "place": WHEEL_PLACES},
    "fluid-wagon": {"fbx": ["VEHICLES/fluid-wagon/static.fbx"], "yaw": 270, "anim": WHEELS, "pivot": WHEEL_PIVOTS,
                    "match_all": True, "place": WHEEL_PLACES},
    "electric-mining-drill": {"fbx": ["STRUCTURES/electric-mining-drill/static.fbx",
                                      "STRUCTURES/electric-mining-drill/animated1.fbx",
                                      "STRUCTURES/electric-mining-drill/animated2.fbx"], "yaw": 180,
                              "bones": {"anim_spin_drill": ["drill"]}},
})

# Entities drawn with a model per direction (model_library.gd FACING_MODELS): FUE5 has one model,
# turned for each. `kinds` renames a moving part per direction (a flywheel turning about its own
# east-west axis is `spin_flywheel`, north-south `spin_flywheel_ns`).
FACINGS = {
    "boiler": ({"fbx": ["STRUCTURES/boiler/static.fbx"], "yaw": 0}, ["", "-east", "-south", "-west"]),
    "chemical-plant": ({"fbx": ["STRUCTURES/chemical-plant/static.fbx"], "yaw": 0}, ["", "-east", "-south", "-west"]),
    "pumpjack": ({"fbx": ["STRUCTURES/pumpjack/static.fbx", "STRUCTURES/pumpjack/animated1.fbx"], "yaw": 0},
                 ["", "-east", "-south", "-west"]),
    "steam-engine": ({"fbx": ["STRUCTURES/steam-engine/static.fbx", "STRUCTURES/steam-engine/animated1.fbx",
                              "STRUCTURES/steam-engine/animated2.fbx"], "yaw": 90,
                      # Its wheels turning about FUE5's Y, across the engine: east-west once turned.
                      "bones": {"anim_spin_flywheel": ["rotate3"], "anim_spin_flywheel.001": ["rotate2"],
                                "anim_spin_flywheel.002": ["rotate4"], "anim_spin_flywheel.003": ["rotate6"],
                                "anim_spin_flywheel.004": ["rotate7"]}}, ["", "-east"]),
}


def _facings():
    for base, (recipe, sfxs) in FACINGS.items():
        for k, sfx in enumerate(sfxs):
            r = dict(recipe, yaw=recipe["yaw"] + 90 * k, spec=base)
            if k % 2 and "bones" in recipe:
                r["bones"] = {name.replace("anim_spin_flywheel", "anim_spin_flywheel_ns"): b
                              for name, b in recipe["bones"].items()}
            # Every direction is matched to the same size (our directions' median, turned with it),
            # so they stay one model turned.
            r["match_turns"] = (base, sfxs, k)
            RECIPES[base + sfx] = r


def _facing_size(base, sfxs, k):
    sizes = []
    for i, sfx in enumerate(sfxs):
        d = our_size(base + sfx)
        if d:
            sizes.append([d[1], d[0], d[2]] if i % 2 else d)
    if not sizes:
        return None
    mid = [sorted(s[a] for s in sizes)[len(sizes) // 2] for a in range(3)]
    return [mid[1], mid[0], mid[2]] if k % 2 else mid


_facings()


# FUE5 models the owner keeps ours for: never converted, even when named.
EXCLUDED = {
    # FUE5's assembler is the green tier 1 (STRUCTURES/assembling-machine): ours, Wube's print with
    # its moving gears, stays.
    "assembling-machine-1": "owner: Zenith's own model",
}


def our_size(name):
    """Our model's size (east-west, north-south, height in tiles), which FUE5's is matched to, or
    None without one."""
    path = os.path.join(REPO, "client", "assets", "models", name + ".glb")
    if not os.path.exists(path):
        return None
    import trimesh
    lo, hi = trimesh.load(path, force="scene").bounds
    d = hi - lo
    return [float(d[0]), float(d[2]), float(d[1])]


def job_for(name, recipe, out, yaw=None):
    spec = specs.SPECS.get(name) or specs.SPECS.get(recipe.get("spec", name), {})
    size = spec.get("size", (3, 3))
    return {
        "fbx": [os.path.join(RAW, *p.split("/")) for p in recipe["fbx"]],
        "out": out,
        "yaw": recipe.get("yaw", 0) if yaw is None else yaw,
        "budget": recipe.get("budget", spec.get("budget", 10000)),
        "tex": recipe.get("tex", 2048 if max(size) >= 3 else 1024 if max(size) == 2 else 512),
        "drop": recipe.get("drop", []),
        "anim": recipe.get("anim", {}),
        "bones": recipe.get("bones", {}),
        "file_parts": recipe.get("file_parts", {}),
        "fit": recipe.get("fit"),
        "overhang": spec.get("overhang", 0.0),
        "hatch": recipe.get("hatch"),
        "pit": recipe.get("pit"),
        "match": (None if not recipe.get("match", True) else
                  _facing_size(*recipe["match_turns"]) if "match_turns" in recipe else our_size(name)),
        "match_all": recipe.get("match_all", False),
        "place": recipe.get("place", []),
        "pivot": recipe.get("pivot", {}),
        "centre": recipe.get("centre"),
        "shift": recipe.get("shift", [0, 0, 0]),
        "scale": recipe.get("scale", [1, 1, 1]),
        "name": "fue5_" + name,
        "size": list(size),
        "sink": spec.get("sink", 0.0),
    }


def build(name, out_dir, yaw=None):
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, name + ".glb")
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump(job_for(name, RECIPES[name], out, yaw), f)
    run = subprocess.run([BLENDER, "--background", "--factory-startup", "--python",
                          os.path.join(HERE, "fue5_blender.py"), "--", f.name],
                         capture_output=True, text=True)
    os.unlink(f.name)
    for line in run.stdout.splitlines():
        if line.startswith("FUE5") or "Error" in line:
            print(" ", line)
    if run.returncode != 0 or not os.path.exists(out):
        print(run.stdout[-3000:], run.stderr[-3000:])
        raise SystemExit("%s: Blender failed" % name)
    return out


def score(name, glb, raw, turns=(0,)):
    """fit.py's overlap per direction, with the model turned by each of `turns` quarter turns."""
    import numpy as np
    import fit
    jobs, (v, faces) = fit.prepare(name, raw, glb)
    out = {}
    for q in turns:
        a = math.radians(90 * q)
        c, s = math.cos(a), math.sin(a)
        # Clockwise from above in glTF (x east, z south).
        vt = v.copy()
        vt[:, 0], vt[:, 2] = c * v[:, 0] - s * v[:, 2], s * v[:, 0] + c * v[:, 2]
        res = {}
        for dn, opts, mask, centre, ppt, own in jobs:
            m = fit.model_mask(vt, faces, opts, mask.shape, centre, ppt)
            res[dn] = (mask & m).sum() / max(1, (mask | m).sum())
        out[q * 90] = res
    return out, len(faces)


def render(name, glb, raw, out_dir, ours_dir):
    """compare.py's sprite | model | overlay for ours (top) and FUE5's (below), per direction."""
    import score_proto
    from PIL import Image
    os.makedirs(out_dir, exist_ok=True)
    for dn, args in score_proto.jobs_for(name, raw):
        rows = []
        for who, path in (("ours", os.path.join(ours_dir, score_proto.model_of(name, dn) + ".glb")), ("fue5", glb)):
            png = os.path.join(out_dir, "%s-%s-%s.png" % (name, dn, who))
            cmd = [BLENDER, "--background", "--factory-startup", "--python", os.path.join(HERE, "compare.py"), "--",
                   png, name, "--glb=" + path] + score_proto.camera_args(name) + args
            if who == "fue5":
                cmd.append("--palette=1")
            subprocess.run(cmd, cwd=REPO, capture_output=True, text=True)
            if os.path.exists(png):
                rows.append(Image.open(png).convert("RGB"))
        if rows:
            w = max(r.width for r in rows)
            sheet = Image.new("RGB", (w, sum(r.height for r in rows)), (30, 30, 30))
            y = 0
            for r in rows:
                sheet.paste(r, (0, y))
                y += r.height
            sheet.save(os.path.join(out_dir, "%s-%s.png" % (name, dn)))


def fix_imports(out_dir=OUT_DIR):
    """After `godot --import`: Godot's glTF importer extracts embedded pictures as files beside the
    model by default; the client reads the .glb itself, so they are kept embedded instead."""
    for f in sorted(os.listdir(out_dir)):
        path = os.path.join(out_dir, f)
        if f.endswith(".glb.import"):
            text = open(path, encoding="utf-8").read()
            if "gltf/embedded_image_handling=1" in text:
                open(path, "w", encoding="utf-8", newline="\n").write(
                    text.replace("gltf/embedded_image_handling=1", "gltf/embedded_image_handling=3"))
                print("embedded:", f)
        elif "_atlas." in f:
            os.remove(path)


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("names", nargs="*")
    ap.add_argument("--out", default=OUT_DIR)
    ap.add_argument("--yaw", type=float)
    ap.add_argument("--score", action="store_true")
    ap.add_argument("--turns", action="store_true", help="score every quarter turn")
    ap.add_argument("--glb-dir", default=OUT_DIR)
    ap.add_argument("--dump", default=os.path.join(ART, "..", "anim-vehicles", "data-raw-dump.json"))
    ap.add_argument("--render", help="side-by-side pictures into this folder (git-ignored places only)")
    ap.add_argument("--fix-imports", action="store_true", help="after godot --import: keep pictures embedded")
    a = ap.parse_args(argv)
    names = [n for n in (a.names or list(RECIPES)) if n not in EXCLUDED]
    for n in a.names:
        if n in EXCLUDED:
            print("%s: not converted (%s)" % (n, EXCLUDED[n]))
    if a.fix_imports:
        fix_imports()
        return 0
    if a.render:
        raw = json.load(open(a.dump, encoding="utf-8"))
        for n in names:
            render(n, os.path.join(a.glb_dir, n + ".glb"), raw, a.render,
                   os.path.join(REPO, "client", "assets", "models"))
        return 0
    if a.score:
        raw = json.load(open(a.dump, encoding="utf-8"))
        ours_dir = os.path.join(REPO, "client", "assets", "models")
        for n in names:
            for who, d in (("ours", ours_dir), ("fue5", a.glb_dir)):
                p = os.path.join(d, n + ".glb")
                if not os.path.exists(p):
                    continue
                r, tri = score(n, p, raw, range(4) if (a.turns and who == "fue5") else (0,))
                for yaw, res in r.items():
                    vals = list(res.values())
                    print("%-22s %-4s yaw %3d  min %.3f mean %.3f  tris %6d  %s" % (
                        n, who, yaw, min(vals), sum(vals) / len(vals), tri,
                        " ".join("%s %.2f" % kv for kv in res.items())))
        return 0
    for n in names:
        print(n)
        build(n, a.out, a.yaw)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
