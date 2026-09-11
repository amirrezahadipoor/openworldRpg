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

# Weapons. Upstream splits a weapon across films of two canvas sizes:
#   * hold films  64 px, one per animation (idle / walk / hurt / combat_idle)
#   * attack      128 px ("slash_128" / "slash_oversize"), six frames per
#                 direction, drawn at 2x so the swing leaves the body's own box,
#                 split into a behind half and a front half
# Our composer halves the 128 px frames back onto the 64 px grid and composites
# the attack twice (under the body, then over it) — see WEAPONS in lpc_compose.py.
# Every weapon lays its files out slightly differently, so these are exact paths.
WEAPONS=(
  weapon/sword/arming/universal/fg/idle/steel.png
  weapon/sword/arming/universal/fg/walk/steel.png
  weapon/sword/arming/universal/fg/hurt/steel.png
  weapon/sword/arming/universal/fg/combat_idle/steel.png
  weapon/sword/arming/attack_slash/fg.png
  weapon/sword/arming/attack_slash/bg.png
  weapon/blunt/mace/walk/mace.png
  weapon/blunt/mace/hurt/mace.png
  weapon/blunt/mace/attack_slash/mace.png
  weapon/blunt/mace/attack_slash/behind/mace.png
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
for rel in "${WEAPONS[@]}"; do
  get "$BASE/$rel" "$DEST/$rel"
done

# Every armed sheet needs an attack animation; that one is not optional.
for need in \
  "weapon/sword/arming/attack_slash/fg.png" \
  "weapon/sword/arming/attack_slash/bg.png" \
  "weapon/blunt/mace/attack_slash/mace.png" \
  "weapon/blunt/mace/attack_slash/behind/mace.png"; do
  if [ ! -s "$DEST/$need" ]; then
    echo "  !! missing $need — armed characters would swing with nothing" >&2
    exit 1
  fi
done

echo "  fetched $ok, cached $skip, failed $fail"
[ "$fail" -eq 0 ] || { echo "!! some layers failed to download" >&2; exit 1; }
echo "  total files: $(find "$DEST" -name '*.png' | wc -l)"
