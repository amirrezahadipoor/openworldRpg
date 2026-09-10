#!/usr/bin/env bash
# Vendors the LPC character layer PNGs used to compose NPC and enemy sprites.
#
# Source: Universal LPC Spritesheet Character Generator
#         https://github.com/LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator
#         Generator: GPL-3.0.  Art layers: CC-BY-SA 3.0 / GPL (per layer).
#
# Only the specific layers we composite are fetched, into a mirrored tree under
# assets/source/lpc_layers/, so tools/lpc_compose.py can rebuild every character
# sheet offline and every upstream author stays identifiable in-repo.
#
# Usage:  bash tools/art/vendor_lpc_layers.sh        (idempotent)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEST="$ROOT/assets/source/lpc_layers"
BASE="https://raw.githubusercontent.com/LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator/master/spritesheets"

# Animations present in the composed sheet layout (see tools/lpc_compose.py).
ANIMS=(idle walk slash spellcast hurt)

# Layer stacks we composite. Each entry is a path prefix; <anim>.png is appended.
LAYERS=(
  # NOTE: body/bodies/* is HEADLESS in this generator — the head is a separate
  # layer under head/heads/*. Omitting it produces a headless sprite, which is
  # exactly the bug this list previously caused.
  body/bodies/male
  body/bodies/female
  head/heads/human/male
  head/heads/human/female
  head/heads/human/male_elderly
  head/heads/human/male_gaunt
  head/heads/skeleton/adult
  head/heads/goblin/adult
  head/heads/orc/male
  head/heads/zombie/adult
  head/heads/wolf/male
  head/heads/lizard/male
  head/heads/minotaur/male
  head/heads/troll/adult
  eyes/human/adult/neutral
  legs/pants/male
  torso/clothes/shortsleeve/shortsleeve/male
  torso/clothes/longsleeve/longsleeve/male
  torso/armour/leather/male
  torso/armour/plate/male
  torso/armour/legion/male
  feet/boots/basic/male
  feet/boots/revised/male
  hair/bedhead/adult
  hair/long/adult
  hair/plain/adult
  hair/bangs/adult
)

# Weapons live one level deeper: <prefix>/<anim>/steel.png
WEAPONS=(
  weapon/sword/arming/universal/fg
)

mkdir -p "$DEST"
ok=0; skip=0; fail=0

get() { # url dest
  local url="$1" dest="$2"
  if [ -s "$dest" ]; then skip=$((skip + 1)); return 0; fi
  if curl -fsSL --retry 3 --create-dirs -o "$dest" "$url"; then
    ok=$((ok + 1))
    return 0
  fi
  echo "  !! failed: $url" >&2
  rm -f "$dest"
  fail=$((fail + 1))
  return 1
}

echo "== LPC character layers -> assets/source/lpc_layers =="
for layer in "${LAYERS[@]}"; do
  for anim in "${ANIMS[@]}"; do
    get "$BASE/$layer/$anim.png" "$DEST/$layer/$anim.png"
  done
done

# Weapon sheets are incomplete upstream (no slash/spellcast variants). That is
# expected: tools/lpc_compose.py falls back to combat_idle for those poses
# (WEAPON_ALT), so a missing weapon layer is not a hard failure — a missing
# BODY layer would be.
weapon_missing=()
for layer in "${WEAPONS[@]}"; do
  for anim in "${ANIMS[@]}" combat_idle; do
    if ! get "$BASE/$layer/$anim/steel.png" "$DEST/$layer/$anim/steel.png"; then
      weapon_missing+=("$anim")
    fi
  done
done
if [ "${#weapon_missing[@]}" -gt 0 ]; then
  echo "  note: weapon sheets absent upstream for: ${weapon_missing[*]} (uses combat_idle fallback)"
  fail=$((fail - ${#weapon_missing[@]}))
fi

echo "  fetched $ok, cached $skip, failed $fail"
[ "$fail" -eq 0 ] || { echo "!! some layers failed to download" >&2; exit 1; }
echo "  total files: $(find "$DEST" -name '*.png' | wc -l)"
