#!/usr/bin/env python3
"""Screenshots of models in the client, for review: each model alone on the mock's map, from
Factorio's view, the angled view from all four sides, a low side view and close up.

    python tools/models/review.py [names...] [--night] [--out DIR] [--dir N] [--port 34850]

For every name it starts the mock (tools/mock_server.py) with only that entity, on the
character's tile, then the windowed client with --review-shots (client/scripts/debug/
review_shots.gd), which hides the character and the HUD, saves factorio.png, north.png,
east.png, south.png, west.png, low.png and close.png cropped to the model, and quits. --night
saves night.png too (the mock's clock stopped at midnight). Shots go to art-src/shots/<name>/
(git-ignored: they show Factorio's sprites on the models). Models named like a pipe piece
(pipe-corner-up-right) are drawn as a pipe with that piece's connections.

The client needs a window (the shots are rendered); it is closed again after each model.
"""

import argparse
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, "tools"))

import specs  # noqa: E402

GODOT = os.environ.get("GODOT", os.path.expandvars(
    r"%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe"
    r"\Godot_v4.7.2-stable_win64.exe"))
# The review folder is in the main checkout (shared by every worktree).
# A worktree under <main>/.claude/worktrees/<name> finds it three levels up.
_MAIN = REPO.split(os.sep + ".claude" + os.sep + "worktrees" + os.sep)[0]
OUT = os.environ.get("F3D_SHOTS", os.path.join(_MAIN, "art-src", "shots"))

# Prototype type per model (the client picks variants, animations and lights by type).
TYPES = {
    "lab": "lab", "boiler": "boiler", "steam-engine": "generator", "gun-turret": "ammo-turret",
    "burner-mining-drill": "mining-drill", "electric-mining-drill": "mining-drill", "pumpjack": "mining-drill",
    "splitter": "splitter", "stone-wall": "wall", "offshore-pump": "offshore-pump", "pipe": "pipe",
    "pipe-to-ground": "pipe-to-ground", "storage-tank": "storage-tank", "medium-electric-pole": "electric-pole",
    "big-electric-pole": "electric-pole", "substation": "electric-pole", "small-electric-pole": "electric-pole",
    "small-lamp": "lamp", "solar-panel": "solar-panel", "accumulator": "accumulator", "radar": "radar",
    "chemical-plant": "assembling-machine", "oil-refinery": "assembling-machine",
    "assembling-machine-1": "assembling-machine", "stone-furnace": "furnace", "steel-furnace": "furnace",
    "transport-belt": "transport-belt", "underground-belt": "underground-belt",
    "wooden-chest": "container", "iron-chest": "container", "steel-chest": "container",
    "big-rock": "simple-entity", "huge-rock": "simple-entity", "big-sand-rock": "simple-entity",
    "iron-ore": "resource", "copper-ore": "resource", "coal": "resource", "stone": "resource",
}
VEHICLES = {"car": "car", "locomotive": "locomotive", "cargo-wagon": "cargo-wagon", "fluid-wagon": "fluid-wagon"}
# Heights the client flies robots at (visuals.gd FLYING): framed and aimed up there.
FLYING = {"logistic-robot": 1.2, "construction-robot": 1.2, "combat-robot": 1.4, "capture-robot": 1.6}
# Prototype types the client draws as movers (rolling stock, vehicles, robots): placed parked.
MOVER_TYPES = {"car", "locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon", "spider-vehicle",
               "construction-robot", "logistic-robot", "combat-robot", "capture-robot"}
PIPE_SHAPES = ["straight-vertical-single", "ending-up", "ending-right", "corner-up-right",
               "ending-down", "straight-vertical", "corner-down-right", "t-right",
               "ending-left", "corner-up-left", "straight-horizontal", "t-up",
               "corner-down-left", "t-left", "t-down", "cross"]  # model_library.gd PIPE_SHAPES


FACTORIO = os.environ.get("FACTORIO", r"C:\Program Files (x86)\Steam\steamapps\common\Factorio")
_PROTO_TYPES = None


def proto_types():
    """{prototype name: type} read from the install's prototype files (data/*/prototypes), so a
    model is placed as what it is (a turret, a robot, a wagon), not as a container."""
    global _PROTO_TYPES
    if _PROTO_TYPES is None:
        import re
        _PROTO_TYPES = {}
        pattern = re.compile(r'type\s*=\s*"([a-z0-9-]+)"\s*,\s*name\s*=\s*"([a-z0-9-]+)"')
        # Entity files first: an entity's item, recipe and remnants share its name.
        files = []
        for mod in ("base", "space-age", "elevated-rails", "quality"):
            root = os.path.join(FACTORIO, "data", mod, "prototypes")
            for folder, _dirs, names in os.walk(root):
                files += [os.path.join(folder, f) for f in names if f.endswith(".lua")]
        files.sort(key=lambda f: "entity" not in os.path.relpath(f, FACTORIO).lower())
        for path in files:
            text = open(path, encoding="utf-8", errors="replace").read()
            for t, n in pattern.findall(text):
                if not t.startswith(("item", "recipe", "technology")):
                    _PROTO_TYPES.setdefault(n, t)
    return _PROTO_TYPES


def entity_for(name):
    """(prototype name, type, extra) for a model name."""
    if name.startswith("pipe-") and name[5:] in PIPE_SHAPES:
        return "pipe", "pipe", {"pc": PIPE_SHAPES.index(name[5:])}
    if name.startswith("tree-") or "tree" in name or name.endswith("-trunk"):
        return name, "tree", {}
    if name.endswith("-curve-left") or name.endswith("-curve-right"):
        return name.rsplit("-curve-", 1)[0], "transport-belt", {"s": "l" if name.endswith("left") else "r"}
    if name.startswith("underground-belt-"):
        return "underground-belt", "underground-belt", {"u": "i" if name.endswith("input") else "o"}
    etype = TYPES.get(name) or proto_types().get(name)
    if etype is None and name.endswith("-ne"):  # rail pieces' diagonal models
        etype = proto_types().get(name[:-3])
    if etype is not None:
        extra = {"a": 1000} if etype == "resource" else {}
        return name, etype, extra
    return name, "container", {}


def aim_for(name):
    """Height (tiles) the side views look at: the area-weighted mean height of the model's surface,
    so an elevated rail's views aim at its deck, not the ground under it; None without a model."""
    path = os.path.join(REPO, "client", "assets", "models", name + ".glb")
    if not os.path.exists(path):
        return None
    import numpy as np
    import trimesh
    mesh = trimesh.load(path, force="mesh")
    if len(mesh.faces) == 0:
        return None
    y = mesh.triangles_center[:, 1]
    top = mesh.bounds[1][1]
    if top <= 0.0:  # lies under the ground (a fish in the water)
        return float(np.average(y, weights=mesh.area_faces))
    return float(np.clip(np.average(y, weights=mesh.area_faces), 0.25 * top, 0.9 * top))


def box_for(name):
    """What to frame: the model's own extent (from its .glb), centred on its position."""
    path = os.path.join(REPO, "client", "assets", "models", name + ".glb")
    if os.path.exists(path):
        import trimesh
        lo, hi = trimesh.load(path, force="scene").bounds
        if hi[1] <= 0.0:  # under the ground (a fish in the water): the crop starts at the ground
            return 1.5, 1.5, 0.5
        return (max(2 * abs(lo[0]), 2 * abs(hi[0]), 0.5), max(2 * abs(lo[2]), 2 * abs(hi[2]), 0.5),
                max(hi[1], 0.3))
    spec = specs.SPECS.get(name, {"size": (1, 1)})
    w, d = spec["size"]
    h = max(w, d)
    if "tree" in name or name.endswith("-trunk"):
        w, d, h = 4.0, 4.0, 6.0
    elif "pole" in name or name == "substation":
        h = 5.0 if name != "small-electric-pole" else 3.5
    elif name in VEHICLES:
        h = 3.0
    return w, d, h


def _proto(ms, proto, etype):
    """Adds a prototype the mock doesn't have."""
    if proto not in ms.EID:
        w, d = specs.SPECS.get(proto, {"size": (1, 1)})["size"]
        ms.ENTITY_PROTOS.append((proto, VEHICLES.get(proto, etype), w, d, (128, 128, 128)))
        ms.EID[proto] = len(ms.ENTITY_PROTOS)
        ms.ETYPE[proto] = ms.ENTITY_PROTOS[-1][1]
        ms.ESIZE[proto] = (w, d)


def serve(name, port, daytime, direction, mover=None, row=1, gap=5.0):
    """The mock with one entity on the character's tile, working all the time; `mover` (a
    prototype name: cargo-pod, rocket-silo-rocket) parked on it, to open its hatches."""
    import mock_server as ms
    proto, etype, extra = entity_for(name)
    _proto(ms, proto, etype)
    w, d = ms.ESIZE[proto]
    # In the middle of a chunk (chunks load around it evenly) and well inside the mock's clearing.
    x = 16.0 if round(w) % 2 == 0 else 16.5
    y = 16.0 if round(d) % 2 == 0 else 16.5
    game = ms.MockGame(1, 0.0, 25000, (x, y))
    game.always_working = True
    # The starter base sets up what the mock's tick expects (fluids, heat, the unplugged lamp);
    # then everything in it goes.
    game.build_starter_base()
    game.entities, game.by_chunk = {}, {}
    game.belt, game.inserters, game.ground = [], [], []
    game.fluids, game.heat, game.wired = {}, {}, {}
    if etype == "fish":  # a pond to swim in
        for dy in range(-7, 8):
            for dx in range(-7, 8):
                game.tile_overrides[(int(x) + dx, int(y) + dy)] = "water"
    if daytime is not None:
        game.daytime = lambda: daytime
    # The mock's train runs on its line far to the north; it has to stay (tick_trains).
    trains = [m for m in game.movers if m["kind"] == "train"]
    if proto in VEHICLES or etype in MOVER_TYPES:
        game.movers = trains + [{"unit": 600, "name": proto, "kind": "parked", "x": x, "y": y, "o": direction / 16.0,
                        "speed": 0.0, "oriented": True}]
    else:
        game.movers = trains
        if mover:
            _proto(ms, mover, mover)
            game.movers.append({"unit": 601, "name": mover, "kind": "parked", "x": x, "y": y, "o": 0.0,
                                "speed": 0.0, "oriented": True})
        e = game.add(ms.Entity(game._unit(), proto, x, y, direction, dict(extra)))
        if "pc" in extra:
            e.extra["pc"] = extra["pc"]
        if row > 1:
            # A row of them east-west, each wired to the next with copper, red and green, as the
            # mod lists them (a pole's neighbours by unit), to see where wires meet the model.
            line = [e] + [game.add(ms.Entity(game._unit(), proto, x + gap * k, y, direction, dict(extra)))
                          for k in range(1, row)]
            for i, pole in enumerate(line):
                near = [o.unit for o in line[max(0, i - 1):i + 2] if o is not pole]
                pole.extra.update({"w": near, "r": near, "g": near})
    game.run("127.0.0.1", port)


def shoot(name, args):
    out = os.path.join(args.out, name)
    os.makedirs(out, exist_ok=True)
    mock = subprocess.Popen([sys.executable, os.path.abspath(__file__), "--serve", name, "--port", str(args.port),
                             "--dir", str(args.dir)] + (["--daytime", "0.5"] if args.night else [])
                            + (["--mover", args.mover] if args.mover else [])
                            + (["--row", str(args.row), "--row-gap", str(args.row_gap)] if args.row > 1 else []),
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(1.0)
        w, d, h = box_for(name)
        w += (args.row - 1) * args.row_gap
        fly = FLYING.get(entity_for(name)[1], 0.0)
        h += fly
        views = ["night"] if args.night else (args.views.split(",") if args.views else
                                              ["factorio", "north", "east", "south", "west", "low", "close"])
        aim = aim_for(name)
        if fly:
            aim = fly + (aim if aim is not None else 0.3)
        cmd = [GODOT, "--path", os.path.join(REPO, "client"), "--resolution", "1600x1000", "--",
               "--factorio-port=%d" % args.port, "--port=%d" % (args.port + 1), "--borderless", "--clean-shot",
               "--review-shots=%s@%g" % (out, args.wait), "--review-box=%g,%g,%g" % (w, d, h),
               "--review-views=" + ",".join(views)] + (["--review-aim=%g" % aim] if aim is not None else []) + args.client_arg
        run = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
        errors = [l for l in (run.stdout + run.stderr).splitlines() if "ERROR" in l or "SCRIPT ERROR" in l]
        saved = [l for l in run.stdout.splitlines() if l.startswith("review shot")]
        print("%-28s %d shots%s" % (name, len(saved), ("  " + errors[0][:150]) if errors else ""))
    finally:
        mock.kill()


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("names", nargs="*")
    parser.add_argument("--out", default=OUT)
    parser.add_argument("--port", type=int, default=34850)
    parser.add_argument("--dir", type=int, default=0, help="direction (0 north, 4 east, 8 south, 12 west)")
    parser.add_argument("--night", action="store_true")
    parser.add_argument("--wait", type=float, default=14.0, help="seconds before the first shot")
    parser.add_argument("--views", help="comma-separated views (default: all seven); `close+0.3` is the close view "
                        "again 0.3 s later (saved as close+0.3.png), to see machines move")
    parser.add_argument("--mover", help="park a mover of this prototype on the model (cargo-pod, rocket-silo-rocket), "
                        "which opens its hatches")
    parser.add_argument("--client-arg", action="append", default=[],
                        help="extra argument for the client, e.g. --client-arg=--model-look=sprite")
    parser.add_argument("--row", type=int, default=1, help="a row of N, wired together (copper, red, green)")
    parser.add_argument("--row-gap", type=float, default=5.0, help="tiles between the row's entities")
    parser.add_argument("--serve", help=argparse.SUPPRESS)
    parser.add_argument("--daytime", type=float, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    if args.serve:
        serve(args.serve, args.port, args.daytime, args.dir, args.mover, args.row, args.row_gap)
        return 0
    for name in args.names:
        shoot(name, args)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
