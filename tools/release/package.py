"""Builds the download players get: the client exported with Godot, with the bridge mod and the
server scripts beside it, zipped as dist/Zenith-<version>-<platform>.zip. Uploads nothing.

    python3 tools/release/package.py [--godot <godot exe>] [--platform windows|linux|all]

Needs Godot's export templates for the same version as the editor (Godot: Editor → Manage Export
Templates, or the .tpz from Godot's releases page unpacked into its templates folder). The
exported client finds `mod/` and `server/` next to its own executable (client/scripts/menu/paths.gd),
so the zip unpacks into one folder that runs as it is.
"""

import argparse
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
MOD = ROOT / "mod" / "factorio-3d-bridge"
PRESETS = {"windows": ("Windows Desktop", "Zenith.exe"), "linux": ("Linux", "Zenith.x86_64")}
SERVER_FILES = ["server-settings.json", "run-server.ps1", "run-headless.sh", "download-headless.sh"]
# The models from Wube's printable release (CC BY-NC) and from FUE5 (CC BY-NC-SA) ship inside the game:
# their per-model lists and licence terms go beside it, as the licences ask.
DOCS = [("LICENSE", "LICENSE.txt"), ("CREDITS.md", "CREDITS.md"), ("docs/USER-GUIDE.md", "USER-GUIDE.md"),
        ("docs/ADDONS.md", "ADDONS.md"), ("client/assets/models/CREDITS.md", "MODEL-CREDITS.md"),
        ("client/assets/models/fue5/README.md", "FUE5-MODELS.md")]
ADDONS_README = """Zenith add-ons go here: each a .zip as you downloaded it (no need to unpack it), or a folder
with its addon.json (or put them in Zenith's user data folder, which keeps them across updates).
The Add-ons menu (main menu, Esc menu, Settings) lists them, with a switch, settings and keys for
each. ADDONS.md says how to write one.
"""

START_HERE = """Zenith {version}: Factorio in 3D

You need Factorio 2.1 (Space Age optional) installed on this computer. Zenith reads Factorio's
graphics, sounds and fonts from your own copy and never copies them.

1. Start {exe}.
2. Single player -> New game (or Load game for one of your saves). Zenith starts Factorio in the
   background with the bridge mod from the mod folder here, and connects by itself.
3. If Factorio isn't found, set its folder in Settings -> Factorio install.

Ctrl+F9 opens the same game in Factorio itself; Ctrl+F9 there comes back.
USER-GUIDE.md has the controls and everything else. Bug reports are welcome on the project's
issue tracker.
"""


def default_godot():
    local = os.environ.get("LOCALAPPDATA", "")
    found = list(pathlib.Path(local, "Microsoft", "WinGet", "Packages").glob(
        "GodotEngine.GodotEngine*/Godot_v*_console.exe")) if local else []
    return str(found[0]) if found else (shutil.which("godot") or "godot")


def export(godot, preset, out_exe):
    out_exe.parent.mkdir(parents=True, exist_ok=True)
    cmd = [godot, "--headless", "--path", str(ROOT / "client"), "--export-release", preset, str(out_exe)]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0 or not out_exe.exists():
        log = (result.stdout + result.stderr)[-2000:]
        if "template" in log.lower():
            sys.exit(f"Godot's export templates are missing for {preset}: install them (Editor -> Manage "
                     f"Export Templates) and run this again.\n{log}")
        sys.exit(f"export of {preset} failed:\n{log}")


def package(godot, platform, version):
    preset, exe = PRESETS[platform]
    folder = ROOT / "dist" / f"Zenith-{version}-{platform}"
    if folder.exists():
        shutil.rmtree(folder)
    export(godot, preset, folder / exe)
    shutil.copytree(MOD, folder / "mod" / "factorio-3d-bridge",
                    ignore=shutil.ignore_patterns("__pycache__", ".DS_Store", "Thumbs.db"))
    (folder / "server").mkdir()
    for name in SERVER_FILES:
        shutil.copy2(ROOT / "server" / name, folder / "server" / name)
    for src, dst in DOCS:
        shutil.copy2(ROOT / src, folder / dst)
    (folder / "START HERE.txt").write_text(START_HERE.format(version=version, exe=exe), encoding="utf-8")
    (folder / "addons").mkdir()
    (folder / "addons" / "README.txt").write_text(ADDONS_README, encoding="utf-8")
    out = folder.parent / f"{folder.name}.zip"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for p in sorted(folder.rglob("*")):
            if p.is_file():
                z.write(p, f"{folder.name}/{p.relative_to(folder).as_posix()}")
    print(f"wrote {out} ({out.stat().st_size // (1024 * 1024)} MB)")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--godot", default=default_godot())
    parser.add_argument("--platform", choices=["windows", "linux", "all"], default="windows")
    args = parser.parse_args()
    version = json.loads((MOD / "info.json").read_text())["version"]
    # The game shows its version from project.godot: a download must say the same as its mod.
    shown = re.search(r'^config/version="([^"]*)"', (ROOT / "client" / "project.godot").read_text(), re.M)
    if not shown or shown.group(1) != version:
        sys.exit(f"client/project.godot config/version ({shown.group(1) if shown else 'missing'}) "
                 f"doesn't match the mod's info.json ({version}): set both to the release's version")
    for platform in (PRESETS if args.platform == "all" else [args.platform]):
        package(args.godot, platform, version)


if __name__ == "__main__":
    main()
