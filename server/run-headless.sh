#!/usr/bin/env bash
# Runs Factorio as a headless server with the Zenith bridge mod and Lua UDP enabled.
# The 3D client then connects to it over localhost.
#
#   server/download-headless.sh            # once: fetch the free Linux headless build
#   server/run-headless.sh                 # new map at server/saves/world.zip, or load it
#   server/run-headless.sh my-base.zip     # load an existing save (the mod is added to it)
#
# Environment overrides:
#   FACTORIO        path to the factorio binary (default: server/factorio/bin/x64/factorio)
#   F3D_UDP_PORT    port Factorio listens on for the 3D client (default 34200)
#   F3D_GAME_PORT   multiplayer port for normal Factorio clients (default 34197)
#   F3D_RCON_PORT   RCON port for tools/rcon.py and tools/live_check.py (default 34198)
#   MAP_GEN         map-gen-settings.json to use when creating a new map
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(dirname "$here")"
factorio="${FACTORIO:-$here/factorio/bin/x64/factorio}"
save="${1:-$here/saves/world.zip}"
udp_port="${F3D_UDP_PORT:-34200}"
game_port="${F3D_GAME_PORT:-34197}"
rcon_port="${F3D_RCON_PORT:-34198}"
data="$here/data"
mods="$data/mods"

if [[ ! -x "$factorio" ]]; then
  echo "Factorio not found at $factorio" >&2
  echo "Run server/download-headless.sh, or set FACTORIO=/path/to/factorio/bin/x64/factorio" >&2
  exit 1
fi

# Keep the server's settings, logs and mods apart from any normal Factorio install,
# so it can run next to the game without "another instance is running" errors.
mkdir -p "$mods" "$(dirname "$save")"
read_data="$(cd "$(dirname "$factorio")/../.." && pwd)/data"
cat > "$data/config.ini" <<EOF
[path]
read-data=$read_data
write-data=$data
EOF

# Link the mod from the repo, so edits apply on the next restart.
ln -sfn "$repo/mod/factorio-3d-bridge" "$mods/factorio-3d-bridge"

# RCON lets tools/rcon.py send console commands; the password stays in the untracked data folder.
if [[ ! -f "$data/rcon-password.txt" ]]; then
  # od reads exactly 12 bytes; `tr </dev/urandom | head` would die of SIGPIPE under pipefail.
  od -An -N12 -tx1 /dev/urandom | tr -d ' \n' > "$data/rcon-password.txt"
fi

common=(--config "$data/config.ini" --mod-directory "$mods")

if [[ ! -f "$save" ]]; then
  echo "Creating a new map at $save"
  "$factorio" "${common[@]}" --create "$save" ${MAP_GEN:+--map-gen-settings "$MAP_GEN"}
fi

echo "Starting headless Factorio: 3D client UDP on 127.0.0.1:$udp_port, game port $game_port, RCON $rcon_port"
exec "$factorio" "${common[@]}" \
  --start-server "$save" \
  --server-settings "$here/server-settings.json" \
  --enable-lua-udp "$udp_port" \
  --port "$game_port" \
  --bind 127.0.0.1 \
  --rcon-bind "127.0.0.1:$rcon_port" \
  --rcon-password "$(cat "$data/rcon-password.txt")"
