"""Builds the mod's zip for the Factorio mod portal: dist/factorio-3d-bridge_<version>.zip, with
everything in one folder named factorio-3d-bridge_<version>, as the game and the portal expect.
It doesn't upload anything.

    python3 tools/release/build_mod_zip.py
"""

import json
import pathlib
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
MOD = ROOT / "mod" / "factorio-3d-bridge"
SKIP = {".DS_Store", "Thumbs.db"}


def main():
    info = json.loads((MOD / "info.json").read_text())
    folder = f"{info['name']}_{info['version']}"
    out = ROOT / "dist" / f"{folder}.zip"
    out.parent.mkdir(exist_ok=True)
    files = sorted(p for p in MOD.rglob("*") if p.is_file() and p.name not in SKIP and "__pycache__" not in p.parts)
    for needed in ("info.json", "control.lua", "changelog.txt", "thumbnail.png", "locale/en/locale.cfg"):
        if not (MOD / needed).exists():
            raise SystemExit(f"missing {needed} in {MOD}")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for p in files:
            z.write(p, f"{folder}/{p.relative_to(MOD).as_posix()}")
    print(f"wrote {out} ({len(files)} files, {out.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
