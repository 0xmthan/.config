#!/usr/bin/env bash
# Install the Warp theme(s) in ./themes into ~/.warp/themes/
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/themes" && pwd)"
DEST="$HOME/.warp/themes"

mkdir -p "$DEST"
cp -v "$SRC"/*.yaml "$SRC"/*.jpg "$DEST/"

echo
echo "Installed to $DEST"
echo "Pick it in Warp: Settings > Appearance > Themes (theme name: Serpent)"
