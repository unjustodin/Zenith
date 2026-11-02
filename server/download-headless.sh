#!/usr/bin/env bash
# Downloads the free Linux headless build of Factorio into server/factorio.
# (Windows and macOS: use your installed game instead, see server/run-server.ps1.)
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
channel="${1:-stable}"
archive="$here/factorio-headless.tar.xz"

echo "Downloading Factorio headless ($channel)..."
curl -fL --retry 3 -o "$archive" "https://factorio.com/get-download/$channel/headless/linux64"
rm -rf "$here/factorio"
tar -xJf "$archive" -C "$here"
rm "$archive"
"$here/factorio/bin/x64/factorio" --version | head -n 1
