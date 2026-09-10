#!/usr/bin/env bash
# Vendors the CC0 / CC-BY-SA source art used to build assets/tiles/atlas.png.
#
# The upstream sheets are committed to assets/source/ deliberately: the atlas
# build (tools/art/build_atlas.py) must be reproducible and every upstream
# author must stay identifiable in-repo for attribution (see CREDITS.md).
#
# Sources (all native 32 px, LPC style):
#   * LPC terrain extension ....... https://opengameart.org/content/lpc-terrain-extension
#   * [LPC] Conifers .............. https://opengameart.org/content/lpc-conifers
#   * [LPC] Forest tiles .......... https://opengameart.org/content/lpc-forest-tiles
#   * [LPC] Trees ................. https://opengameart.org/content/lpc-trees
#
# Usage:  bash tools/art/vendor_sources.sh          (idempotent)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEST="$ROOT/assets/source"
WORK="${TMPDIR:-/tmp}/rpg-art-vendor"
mkdir -p "$DEST/lpc_terrain" "$WORK"
cd "$WORK"

fetch() { # url dest
  if [ -s "$2" ]; then echo "  cached  $(basename "$2")"; return; fi
  echo "  fetch   $(basename "$2")"
  curl -fsSL --retry 3 -o "$2" "$1"
}

# OGA serves the real archive from /sites/default/files inside a span.file block.
oga_url() { # page-slug
  curl -fsSL "https://opengameart.org/content/$1" \
    | grep -oE '<a href="https://opengameart\.org/sites/default/files/[^"]+\.(zip|tar)"[^>]*download=' \
    | grep -oE 'https://[^"]+' | head -1
}

echo "== LPC terrain extension =="
fetch "https://opengameart.org/sites/default/files/lpc_terrain.tar" lpc_terrain.tar
rm -rf terrain && mkdir terrain && tar -xf lpc_terrain.tar -C terrain
for t in grass dirt water snow ice lava lavarock redsand snowwater sand; do
  cp "terrain/lpc_terrain/twosided/$t.png" "$DEST/lpc_terrain/$t.png"
done
cp terrain/lpc_terrain/COPYRIGHT "$DEST/lpc_terrain/COPYRIGHT"

echo "== [LPC] Conifers =="
u=$(oga_url lpc-conifers); fetch "$u" conifers.zip
unzip -qo conifers.zip -d conifers
cp conifers/lpc-conifers/conifers.png "$DEST/lpc_conifers.png"
cp conifers/lpc-conifers/CREDITS-conifers.txt "$DEST/"

echo "== [LPC] Forest tiles =="
u=$(oga_url lpc-forest-tiles); fetch "$u" forest.zip
unzip -qo forest.zip -d forest
cp forest/LPC_forest/forest_tiles.png "$DEST/lpc_forest_tiles.png"
cp forest/LPC_forest/credits.txt "$DEST/CREDITS-forest.txt"

echo "== [LPC] Trees =="
u=$(oga_url lpc-trees); fetch "$u" trees.zip
unzip -qo trees.zip -d trees
cp trees/lpc-trees/trees-dead.png "$DEST/lpc_trees_dead.png"
cp trees/lpc-trees/CREDITS-trees.txt "$DEST/"

echo
echo "vendored into $DEST:"
ls -la "$DEST"
