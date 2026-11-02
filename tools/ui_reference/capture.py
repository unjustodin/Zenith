"""Screenshots of Factorio's own GUI, as the reference for the 3D client's UI.

Runs the real windowed Factorio with its own config and write-data folder
(tools/ui_reference/run/, git-ignored), so your normal settings, saves and mods are never
touched. The f3d-ui-capture mod opens every window it can and screenshots it at 1920x1080 with
the GUI at 100% (game.take_screenshot{show_gui = true}); this script then kills that game and
copies the pictures to art-src/ui_reference/ in the main checkout.

    python tools/ui_reference/capture.py                    # a copy of a big save
    python tools/ui_reference/capture.py --fresh            # a new map (prefix fresh_)
    python tools/ui_reference/capture.py --only character,entity_lab

The pictures show Factorio's art: never commit them. A game window opens while it runs
(about two minutes, most of it Factorio loading).
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
RUN = HERE / "run"
MOD = HERE / "f3d-ui-capture"
DEFAULT_FACTORIO = Path(r"C:\Program Files (x86)\Steam\steamapps\common\Factorio\bin\x64\factorio.exe")
STEAM_APP_ID = "427520"


def main_checkout() -> Path:
    """The main checkout, also from a worktree: art-src/ is shared there."""
    out = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
                         cwd=REPO, capture_output=True, text=True)
    if out.returncode == 0 and out.stdout.strip():
        return Path(out.stdout.strip()).parent
    return REPO


def default_save() -> Path:
    # The newest save the menu or run-server.ps1 left in server/saves (autosaves skipped).
    saves = [p for p in (main_checkout() / "server" / "saves").glob("*.zip") if not p.name.startswith("_autosave")]
    if not saves:
        raise SystemExit("no save in server/saves: pass --save or --fresh")
    return max(saves, key=lambda p: p.stat().st_mtime)


def write_setup(factorio: Path, only: list[str], hover: bool = False, size: tuple = (1920, 1080)) -> None:
    (RUN / "mods").mkdir(parents=True, exist_ok=True)
    (RUN / "saves").mkdir(parents=True, exist_ok=True)
    read_data = (factorio.parent / ".." / ".." / "data").resolve()
    # full-screen off: a full-screen window that loses focus closes during loading
    (RUN / "config.ini").write_text(
        f"[path]\nread-data={read_data}\nwrite-data={RUN}\n\n"
        "[graphics]\nfull-screen=false\nminimize-on-focus-loss=false\n\n"
        # the research screen pauses a single-player game, which would stop the script
        "[other]\ntechnology-gui-pauses-game=false\nhide-achievement-popups=true\n\n"
        "[interface]\nshow-tips-and-tricks-notifications=false\nshow-tutorial-notifications=false\n",
        encoding="ascii")
    target = RUN / "mods" / "f3d-ui-capture"
    if target.is_symlink() or (hasattr(os.path, "isjunction") and os.path.isjunction(target)):
        os.rmdir(target)
    elif target.exists():
        shutil.rmtree(target)
    shutil.copytree(MOD, target)
    lua_list = ", ".join(json.dumps(n) for n in only)
    (target / "config.lua").write_text(
        f"return {{resolution = {{{size[0]}, {size[1]}}}, only = {{{lua_list}}}, hover = {str(hover).lower()}}}\n",
        encoding="utf-8")
    mods = ["base", "elevated-rails", "quality", "recycler", "space-age", "f3d-ui-capture"]
    (RUN / "mods" / "mod-list.json").write_text(json.dumps(
        {"mods": [{"name": m, "enabled": True} for m in mods]}, indent=1), encoding="utf-8")


def factorio_cmd(factorio: Path, *extra: str) -> list[str]:
    return [str(factorio), "--config", str(RUN / "config.ini"), "--mod-directory", str(RUN / "mods"), *extra]


def env() -> dict:
    # Started outside Steam, the Steam build restarts itself through Steam and drops its
    # arguments; these tell it Steam already launched it.
    e = dict(os.environ)
    e["SteamAppId"] = STEAM_APP_ID
    e["SteamGameId"] = STEAM_APP_ID
    return e


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--save", type=Path, help="save to copy and load (default: the newest save in server/saves)")
    ap.add_argument("--fresh", action="store_true", help="create and use a new map instead")
    ap.add_argument("--only", default="", help="comma-separated step names (substrings) to capture")
    ap.add_argument("--prefix", default=None, help="prefix for the picture names (default: fresh_ with --fresh)")
    ap.add_argument("--out", type=Path, default=None, help="where the pictures go (default: <main>/art-src/ui_reference)")
    ap.add_argument("--factorio", type=Path, default=DEFAULT_FACTORIO)
    ap.add_argument("--timeout", type=float, default=600)
    ap.add_argument("--size", default="1920x1080", help="window size and picture resolution, e.g. 1280x720 (GUI at 100%%)")
    args = ap.parse_args()

    out = args.out or main_checkout() / "art-src" / "ui_reference"
    prefix = args.prefix if args.prefix is not None else ("fresh_" if args.fresh else "")
    only = [s.strip() for s in args.only.split(",") if s.strip()]
    size = tuple(int(v) for v in args.size.lower().split("x"))
    write_setup(args.factorio, only, size=size)

    if args.fresh:
        save = RUN / "saves" / "fresh.zip"
        if save.exists():
            save.unlink()
        print("Creating a fresh map...")
        subprocess.run(factorio_cmd(args.factorio, "--create", str(save)), env=env(), timeout=600)
        if not save.exists():
            print("Map creation failed; see", RUN / "factorio-current.log")
            return 1
    else:
        source = args.save or default_save()
        save = RUN / "saves" / ("copy-" + source.name)
        shutil.copyfile(source, save)  # never load (or risk saving over) the original

    shots = RUN / "script-output" / "ui_reference"
    if shots.exists():
        shutil.rmtree(shots)

    print(f"Starting Factorio on {save.name} (a window opens; it closes by itself)...")
    proc = subprocess.Popen(factorio_cmd(args.factorio, "--load-game", str(save), "--window-size", f"{size[0]}x{size[1]}"),
                            env=env())
    print("pid", proc.pid)
    done = shots / "done.txt"
    start = time.time()
    try:
        while time.time() - start < args.timeout:
            if done.exists():
                time.sleep(2)  # the last screenshot is written after the tick that asked for it
                break
            if proc.poll() is not None:
                print("Factorio exited early; see", RUN / "factorio-current.log")
                return 1
            time.sleep(1)
        else:
            print("Timed out waiting for", done)
    finally:
        if proc.poll() is None:
            proc.kill()  # only the game this script started
            proc.wait(30)

    out.mkdir(parents=True, exist_ok=True)
    pictures = sorted(shots.glob("*.png")) if shots.exists() else []
    for png in pictures:
        shutil.copyfile(png, out / (prefix + png.name))
    # scripted checks (rules.lua) write their findings as JSON next to the pictures
    for found in (sorted(shots.glob("rules_*.json")) if shots.exists() else []):
        shutil.copyfile(found, out / (prefix + found.name))
    manifest = shots / "manifest.json"
    results = []
    if manifest.exists():
        results = json.loads(manifest.read_text(encoding="utf-8") or "[]")
        if isinstance(results, dict):
            results = list(results.values())
        # --only runs update their steps in the full list
        merged = {}
        old = out / (prefix + "manifest.json")
        if only and old.exists():
            merged = {r.get("name"): r for r in json.loads(old.read_text(encoding="utf-8"))}
        merged.update({r.get("name"): r for r in results})
        old.write_text(json.dumps(list(merged.values()), indent=1), encoding="utf-8")
    failed = [r for r in results if not r.get("ok")]
    print(f"{len(pictures)} pictures in {out}; {len(failed)} steps failed:")
    for r in failed:
        print(f"  {r.get('name')}: {r.get('error')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
