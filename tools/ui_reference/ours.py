"""Screenshots of the 3D client's equivalent of each Factorio reference picture.

Runs the windowed client (1920x1080, borderless, UI scale 100%) against the mock server once
per window, opened with the client's debug options, and saves art-src/ui_reference/ours/<name>.png
in the main checkout. Start the mock first on the port you pass:

    python tools/mock_server.py --port 35310 --reach 200 --machine-gallery
    python tools/ui_reference/ours.py --factorio-port 35310 --port 35311 [names...]

compare.py then puts both sides on one page. The client reads Factorio's GUI art and icons from
your install, so these pictures stay out of git too.
"""

import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
sys.path.insert(0, str(HERE))
from capture import main_checkout  # noqa: E402

GODOT = Path(os.environ.get("LOCALAPPDATA", "")) / "Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe"

# reference name -> the client's options that show the same thing ([] = just the game and HUD).
# Entity windows open the nearest entity of that prototype (--open=<name>); the mock has a
# few of each kind, so prototypes it lacks have no picture of ours.
SHOTS: dict[str, list[str]] = {
    "hud": [],
    "hud_research": [],
    "hud_crafting_queue": ["--ui-craft=iron-gear-wheel:5"],
    "hud_cursor_building": ["--ui-hold=assembling-machine-1"],
    "hud_cursor_item": ["--ui-hold=iron-plate"],
    "hud_chat": ["--chat=A second line with an icon."],
    "alt_mode": ["--alt-mode"],
    "remote_view": ["--remote=20,0"],
    "map_view": ["--ui=map"],
    "character": ["--ui=inventory"],
    "character_tab": ["--ui=character"],
    "armor_grid": ["--ui=armor"],
    "production": ["--stats=item"],
    "kills": ["--stats=kill"],
    "trains": ["--ui=trains"],
    "players": ["--ui=players"],
    "research_tree": ["--ui=research"],
    "esc_menu": ["--menu=esc"],
    # the mock's inventory: 3 blueprint, 4 deconstruction planner, 5 upgrade planner; its game
    # library's record 2 is a book
    "blueprint": ["--ui-planner=3"],
    "deconstruction_planner": ["--ui-planner=4"],
    "upgrade_planner": ["--ui-planner=5"],
    "blueprint_book": ["--ui-game-record=2"],
    "blueprint_library": ["--ui=library"],
    # hover.py's pictures (art-src/ui_reference/hover/)
    "click_shortcut_expand": ["--ui=shortcut-chooser"],
    "click_quickbar_page": ["--ui=page-chooser"],
    "hover_entity_alt_48": ["--alt-mode", "--ui-hover=1125,745"],
    "map_view_zoomed_in": ["--ui=map", "--map-zoom=24"],
    "space_map": ["--ui=space-platform"],
    "logistic_networks": ["--ui=networks"],
    "factoriopedia_item": ["--pedia=item:iron-plate"],
    "factoriopedia_entity": ["--pedia=entity:assembling-machine-1"],
    "factoriopedia_recipe": ["--pedia=recipe:iron-gear-wheel"],
    "research_tree_researched": ["--ui=research", "--research=automation"],
    "global_electric_network": ["--stats=electric"],
    "achievements": ["--ui=achievements"],
    "bonuses": ["--ui=bonuses"],
    "permissions": ["--ui=permissions"],
    "alerts_config": ["--ui=alerts"],
    # later captures (capture.py / hover.py)
    "factoriopedia_fluid": ["--pedia=fluid:water"],
    "factoriopedia_planet": ["--pedia=planet:vulcanus"],
    "factoriopedia_tile": ["--pedia=tile:grass-1"],
    "trains_nauvis": ["--ui=trains", "--start=40,0"],
    "logistic_networks_click": ["--ui=networks"],
}
MOCK_ENTITIES = ["wooden-chest", "requester-chest", "storage-chest", "assembling-machine-1", "stone-furnace",
    "lab", "boiler", "steam-engine", "burner-inserter", "inserter", "splitter", "gun-turret", "roboport",
    "arithmetic-combinator", "constant-combinator", "small-lamp", "small-electric-pole", "train-stop",
    "decider-combinator", "selector-combinator", "programmable-speaker", "display-panel", "pump", "power-switch"]
# The mock's machine gallery (mock_server.py --machine-gallery --reach 200, tools/mock_machines.py):
# every production machine whose window Factorio's pictures show.
MOCK_ENTITIES += ["iron-chest", "steel-chest", "passive-provider-chest", "active-provider-chest", "buffer-chest",
    "assembling-machine-2", "assembling-machine-3", "oil-refinery", "chemical-plant", "steel-furnace", "electric-furnace",
    "burner-mining-drill", "electric-mining-drill", "pumpjack", "nuclear-reactor", "heat-exchanger", "offshore-pump",
    "accumulator", "radar", "beacon", "foundry", "electromagnetic-plant", "cryogenic-plant", "biochamber", "recycler",
    "crusher", "biolab", "big-mining-drill", "heating-tower", "captive-biter-spawner", "fusion-reactor",
    "fusion-generator", "agricultural-tower", "rocket-silo", "cargo-landing-pad"]
for _name in MOCK_ENTITIES:
    SHOTS["entity_" + _name.replace("-", "_")] = ["--open=" + _name]
SHOTS["entity_car"] = ["--open=601"]  # the mock's parked car (a mover)
SHOTS["entity_locomotive"] = ["--open=700"]  # the mock's train
SHOTS["entity_cargo_wagon"] = ["--open=701"]
# mock_vehicles.py: the tank and spidertron (movers), the artillery, pipes and tank of its gallery row
SHOTS["entity_tank"] = ["--open=602"]
SHOTS["entity_spidertron"] = ["--open=610"]
for _name in ["artillery-turret", "artillery-wagon", "storage-tank", "pipe", "pipe-to-ground", "heat-pipe", "land-mine"]:
    SHOTS["entity_" + _name.replace("-", "_")] = ["--open=" + _name]
# hover.py's popups: the decider's signal-or-constant chooser, a constant combinator signal's
# "Set request", the locomotive's "Change train group"
SHOTS["click_decider_constant"] = ["--open=decider-combinator", "--ui-press=SecondOperand"]
SHOTS["click_constant_signal"] = ["--open=constant-combinator", "--ui-press=Signals"]
SHOTS["click_train_group"] = ["--open=700", "--ui-press=ChangeGroup"]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("names", nargs="*", help="only these (default: all)")
    ap.add_argument("--factorio-port", type=int, default=35310)
    ap.add_argument("--port", type=int, default=35311)
    ap.add_argument("--godot", type=Path, default=GODOT)
    ap.add_argument("--delay", type=float, default=9.0, help="seconds before the screenshot")
    ap.add_argument("--out", type=Path, default=None)
    ap.add_argument("--size", default="1920x1080", help="window size, e.g. 1280x720")
    ap.add_argument("--ui-scale", default="1", help="the client's UI scale (Factorio picks 75%% by itself at 1280x720)")
    args = ap.parse_args()

    out = args.out or main_checkout() / "art-src" / "ui_reference" / "ours"
    out.mkdir(parents=True, exist_ok=True)
    run = HERE / "run"
    run.mkdir(exist_ok=True)
    settings = run / "ours-settings.cfg"
    names = args.names or list(SHOTS)
    for name in names:
        if name not in SHOTS:
            print("unknown:", name)
            continue
        # Fresh settings each time (Alt-mode, for one, is saved when turned on). Factorio shows no
        # control hints in these pictures either.
        settings.write_text("[interface]\n\nshow_help=false\nalt_mode=false\n", encoding="utf-8")
        png = out / f"{name}.png"
        if png.exists():
            png.unlink()
        cmd = [str(args.godot), "--path", str(REPO / "client"), "--resolution", args.size, "--",
            f"--factorio-port={args.factorio_port}", f"--port={args.port}", "--borderless", f"--ui-scale={args.ui_scale}",
            f"--settings-file={settings.as_posix()}", f"--screenshot={png.as_posix()}@{args.delay}", *SHOTS[name]]
        proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        start = time.time()
        while time.time() - start < args.delay + 25 and not png.exists():
            time.sleep(0.5)
        time.sleep(1.0)
        proc.kill()  # only the client this script started
        proc.wait(20)
        print(name, "ok" if png.exists() else "MISSING")
    return 0


if __name__ == "__main__":
    sys.exit(main())
