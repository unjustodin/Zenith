#!/usr/bin/env bash
# Quick start for Zenith (Git Bash on Windows, or Linux).
#
#   ./quickstart.sh             the client's main menu (Play starts Factorio for you)
#   ./quickstart.sh <save>      straight into a save in server/saves (e.g. play), no menu
#   ./quickstart.sh mock        no Factorio needed: the mock world and the client
#   ./quickstart.sh test        run every test (bridge, mock, GDScript parse, UI)
#
# Godot is found as $GODOT, `godot` on PATH, or winget's install on Windows. The mock and the
# tests use the venv in .venv (python -m venv .venv, then pip install lupa "gdtoolkit==4.*").
set -euo pipefail
cd "$(dirname "$0")"

find_godot() {
	local console="${1:-}"
	if [ -n "${GODOT:-}" ]; then echo "$GODOT"; return; fi
	if command -v godot >/dev/null 2>&1; then command -v godot; return; fi
	local winget="${LOCALAPPDATA:-}/Microsoft/WinGet/Packages"
	local found
	found=$(ls -d "$winget"/GodotEngine.GodotEngine_*/Godot_v4*_win64${console}.exe 2>/dev/null | sort | tail -n 1 || true)
	if [ -n "$found" ]; then echo "$found"; return; fi
	echo "Godot 4.4+ not found: install it or set GODOT=/path/to/godot" >&2
	exit 1
}

python_bin() {
	if [ -x .venv/Scripts/python.exe ]; then echo .venv/Scripts/python.exe
	elif [ -x .venv/bin/python ]; then echo .venv/bin/python
	else echo python3; fi
}

GODOT_BIN=$(find_godot)
PY=$(python_bin)

# A fresh checkout has never imported the models and textures.
if [ ! -d client/.godot/imported ]; then
	echo "First run: importing assets (a minute or two)..."
	"$(find_godot _console)" --headless --path client --import >/dev/null 2>&1 || true
fi

case "${1:-}" in
	"")
		exec "$GODOT_BIN" --path client
		;;
	mock)
		"$PY" tools/mock_server.py &
		MOCK=$!
		trap 'kill $MOCK 2>/dev/null || true' EXIT
		sleep 1
		"$GODOT_BIN" --path client -- --factorio-port=34200
		;;
	test)
		"$PY" tools/mod_tests/test_bridge.py
		"$PY" tools/test_mock_server.py
		GDPARSE=.venv/Scripts/gdparse.exe; [ -x "$GDPARSE" ] || GDPARSE=.venv/bin/gdparse
		find client -name '*.gd' -print0 | xargs -0 "$GDPARSE" && echo "gdparse: all client scripts parse"
		"$(find_godot _console)" --headless --path client res://tests/ui_test.tscn -- --settings-file=user://test-settings.cfg
		;;
	-h|--help)
		sed -n '2,10p' "$0"
		;;
	*)
		exec "$GODOT_BIN" --path client -- "--menu-launch=$1"
		;;
esac
