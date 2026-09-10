#!/usr/bin/env bash
# Vendors the real CC0/CC-BY audio used by the game, replacing the procedural
# placeholder score and SFX from tools/gen_music.py / tools/gen_sfx.py.
#
# Sources:
#   Kenney "RPG Audio", "Interface Sounds", "Impact Sounds"  — CC0
#     https://kenney.nl/assets/rpg-audio etc.
#   "Generic 8-bit JRPG Soundtrack" by Avgvst — CC-BY 3.0/4.0
#     https://opengameart.org/content/generic-8-bit-jrpg-soundtrack
#     (Attribution is required and shipped in the in-game credits screen.)
#
# Upstream archives are cached but NOT committed: unlike the tile atlas, the
# music pack is 26 MB for 11 tracks we use, so only the selected, renamed tracks
# are committed. Attribution lives in CREDITS.md.
#
# Usage:  bash tools/audio/vendor_audio.sh        (idempotent)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MUSIC="$ROOT/assets/audio/music"
SFX="$ROOT/assets/audio/sfx"
WORK="${TMPDIR:-/tmp}/rpg-audio-vendor"
mkdir -p "$MUSIC" "$SFX" "$WORK"
cd "$WORK"

fetch() { # url dest
  if [ -s "$2" ]; then echo "  cached  $(basename "$2")"; return; fi
  echo "  fetch   $(basename "$2")"
  curl -fsSL --retry 3 -o "$2" "$1"
}

kenney() { # slug
  local slug="$1"
  local url
  url=$(curl -fsSL "https://kenney.nl/assets/$slug" \
        | grep -oE "https://kenney\.nl/media/pages/assets/$slug/[^']*\.zip" | head -1)
  [ -n "$url" ] || { echo "!! could not resolve Kenney pack: $slug" >&2; exit 1; }
  fetch "$url" "$slug.zip"
  rm -rf "k_$slug"; mkdir -p "k_$slug"; unzip -qo "$slug.zip" -d "k_$slug"
}

echo "== Kenney CC0 audio packs =="
kenney rpg-audio
kenney interface-sounds
kenney impact-sounds

KR="k_rpg-audio/Audio"
KI="k_interface-sounds/Audio"
KP="k_impact-sounds/Audio"

copy_sfx() { # src_basename dest_id
  local src="$1" id="$2"
  [ -f "$src" ] || { echo "!! missing sfx source: $src" >&2; exit 1; }
  cp "$src" "$SFX/$id.ogg"
}

echo "  -- SFX (20 ids registered by AudioManager)"
copy_sfx "$KR/drawKnife2.ogg"                 attack_swing
copy_sfx "$KP/impactPunch_medium_000.ogg"     hit
copy_sfx "$KP/impactPunch_heavy_000.ogg"      player_hurt
# Audit fix pass (v0.4.0): the systems that had no sound at all.
copy_sfx "$KR/metalLatch.ogg"                  equip
copy_sfx "$KR/handleCoins.ogg"                 coin
copy_sfx "$KI/confirmation_001.ogg"            quest_accept
copy_sfx "$KI/confirmation_003.ogg"            quest_complete
copy_sfx "$KR/bookFlip1.ogg"                   secret_found
copy_sfx "$KI/error_004.ogg"                   denied
copy_sfx "$KP/footstep_grass_001.ogg"          footstep
copy_sfx "$KR/cloth2.ogg"                     dodge
copy_sfx "$KR/handleCoins.ogg"                pickup
copy_sfx "$KI/click_001.ogg"                  ui_click
copy_sfx "$KR/metalPot1.ogg"                  item_use
copy_sfx "$KR/handleCoins2.ogg"               purchase
copy_sfx "$KI/confirmation_001.ogg"           level_up
copy_sfx "$KI/glass_001.ogg"                  enemy_cast
copy_sfx "$KP/impactBell_heavy_000.ogg"       boss_roar
copy_sfx "$KR/cloth4.ogg"                     ability_whirl
copy_sfx "$KI/glass_002.ogg"                  ability_bolt

# Ambience beds are NOT vendored: they are synthesised by tools/gen_ambient.py
# (the project's own work), so there is nothing to download for them.

echo "== Generic 8-bit JRPG Soundtrack (Avgvst, CC-BY) =="
fetch "https://opengameart.org/sites/default/files/JRPG%20OST%20%28Rev%202%29.zip" jrpg-ost.zip
rm -rf jrpg; mkdir -p jrpg; unzip -qo jrpg-ost.zip -d jrpg

copy_music() { # src_basename dest_id
  local src="$1" id="$2"
  [ -f "$src" ] || { echo "!! missing music source: $src" >&2; exit 1; }
  cp "$src" "$MUSIC/$id.ogg"
}

echo "  -- score (11 ids)"
copy_music "jrpg/01 - Opening.ogg"            title
copy_music "jrpg/08 - Overworld.ogg"          meadow
copy_music "jrpg/10 - The Empire.ogg"         barrens
copy_music "jrpg/18 - Nighttide Waltz.ogg"    frost
copy_music "jrpg/06 - Rebels Be.ogg"          combat
copy_music "jrpg/14 - Barbarian King.ogg"     boss
# Audit fix pass (v0.4.0): the score had one track per biome and nothing for a
# town, a dungeon, a haven, a victory or a bad situation. Same OST, same
# attribution — just more of it selected instead of six tracks out of 25.
copy_music "jrpg/07 - Town.ogg"               town
copy_music "jrpg/15 - Dungeon.ogg"            dungeon
copy_music "jrpg/23 - Inn.ogg"                camp
copy_music "jrpg/17 - Victory.ogg"            victory
copy_music "jrpg/13 - Danger.ogg"             danger

# The procedural placeholders are superseded; remove them so they cannot be
# picked up as a silent fallback by AudioManager.
rm -f "$MUSIC"/{title,meadow,barrens,frost,combat}.wav
rm -f "$SFX"/*.wav

echo
echo "music:"; ls -la "$MUSIC"
echo "sfx:";   ls "$SFX" | tr '\n' ' '; echo
