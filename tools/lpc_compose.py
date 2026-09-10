#!/usr/bin/env python3
"""Composes LPC layer spritesheets into game-ready character sheets.

Reads the vendored CC-BY-SA-3.0 LPC layers from assets/source/lpc_layers
(fetched by tools/art/vendor_lpc_layers.sh — no toolchain clone required) and
bakes layered characters into assets/lpc/<name>.png — one RGBA sheet each:

  layout: 13 cols x 20 rows of 64px frames
          rows 0-3   idle      (n w s e)
          rows 4-7   walk
          rows 8-11  slash     (melee attack)
          rows 12-15 spellcast (abilities)
          rows 16-19 hurt

Layer stack (z order): body -> pants -> shirt/armor -> boots -> hair -> weapon.

Archetypes produced:
  player_*      the four equipment variants used by the player (armour x weapon)
  npc_*         villagers / quest givers (elder, hunter, vendor)
  enemy_*       humanoid enemy bases (raider, shaman)

Enemies share one sheet per type and are tinted per archetype at runtime via
Sprite2D.modulate (see data/enemies.json body_color), which is why there is a
single raider sheet rather than one per enemy id.

Attribution: see CREDITS.md (Liberated Pixel Cup contributors, CC-BY-SA-3.0).
"""
import os
import sys

from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SRC = os.path.join(ROOT, "assets", "source", "lpc_layers")
OUT = os.path.join(ROOT, "assets", "lpc")

ANIMS = [("idle", 2), ("walk", 9), ("slash", 6), ("spellcast", 7), ("hurt", 6)]
COLS = 13
W, H = 64, 64

# Weapon sheets have no slash/spellcast variants; hold the ready pose instead.
WEAPON_ALT = {"slash": ("combat_idle", 1), "spellcast": ("combat_idle", 0)}

# --- layer stacks -----------------------------------------------------------
# Z-order matters: body -> pants -> shirt/armour -> boots -> head -> eyes ->
# hair -> weapon. Note body/bodies/* is HEADLESS; the head is a separate layer
# under head/heads/* and must be included or the sprite renders headless.
BODY_M = "body/bodies/male/%s.png"
BODY_F = "body/bodies/female/%s.png"
HEAD_M = "head/heads/human/male/%s.png"
HEAD_F = "head/heads/human/female/%s.png"
HEAD_ELDERLY = "head/heads/human/male_elderly/%s.png"
HEAD_GAUNT = "head/heads/human/male_gaunt/%s.png"
HEAD_SKELETON = "head/heads/skeleton/adult/%s.png"
HEAD_GOBLIN = "head/heads/goblin/adult/%s.png"
HEAD_ORC = "head/heads/orc/male/%s.png"
EYES = "eyes/human/adult/neutral/%s.png"
PANTS = "legs/pants/male/%s.png"
SHIRT_SHORT = "torso/clothes/shortsleeve/shortsleeve/male/%s.png"
SHIRT_LONG = "torso/clothes/longsleeve/longsleeve/male/%s.png"
ARMOR_LEATHER = "torso/armour/leather/male/%s.png"
BOOTS = "feet/boots/basic/male/%s.png"
BOOTS_REVISED = "feet/boots/revised/male/%s.png"
HAIR_BEDHEAD = "hair/bedhead/adult/%s.png"
HAIR_LONG = "hair/long/adult/%s.png"
HAIR_PLAIN = "hair/plain/adult/%s.png"
HAIR_BANGS = "hair/bangs/adult/%s.png"
SWORD = "weapon/sword/arming/universal/fg/%s/steel.png"

ARCHETYPES = {
    # --- player equipment variants (existing behaviour, unchanged) ---
    "player_none_none": [BODY_M, PANTS, SHIRT_SHORT, BOOTS, HEAD_M, EYES, HAIR_BEDHEAD],
    "player_none_sword": [BODY_M, PANTS, SHIRT_SHORT, BOOTS, HEAD_M, EYES, HAIR_BEDHEAD, SWORD],
    "player_leather_none": [BODY_M, PANTS, ARMOR_LEATHER, BOOTS, HEAD_M, EYES, HAIR_BEDHEAD],
    "player_leather_sword": [BODY_M, PANTS, ARMOR_LEATHER, BOOTS, HEAD_M, EYES, HAIR_BEDHEAD, SWORD],
    # --- NPCs: Elder Rowan (elderly), Hunter Kael, the camp vendor ---
    "npc_elder": [BODY_M, PANTS, SHIRT_LONG, BOOTS, HEAD_ELDERLY, EYES, HAIR_LONG],
    "npc_hunter": [BODY_M, PANTS, SHIRT_LONG, BOOTS_REVISED, HEAD_M, EYES, HAIR_BANGS],
    "npc_vendor": [BODY_M, PANTS, SHIRT_SHORT, BOOTS, HEAD_M, EYES, HAIR_PLAIN],
    # --- enemies: distinct silhouettes, tinted per archetype at runtime ---
    "enemy_raider": [BODY_M, PANTS, ARMOR_LEATHER, BOOTS, HEAD_GAUNT, EYES, HAIR_PLAIN],
    "enemy_shaman": [BODY_F, PANTS, SHIRT_LONG, BOOTS, HEAD_F, EYES, HAIR_LONG],
    "enemy_goblin": [BODY_M, PANTS, SHIRT_SHORT, BOOTS, HEAD_GOBLIN, EYES],
    "enemy_skeleton": [BODY_M, PANTS, ARMOR_LEATHER, BOOTS, HEAD_SKELETON, EYES],
    "enemy_orc": [BODY_M, PANTS, ARMOR_LEATHER, BOOTS, HEAD_ORC, EYES],
}


def load_layer(rel: str):
    p = os.path.join(SRC, rel)
    if not os.path.exists(p):
        return None
    return Image.open(p).convert("RGBA")


def paste_frames(sheet: Image.Image, layer: Image.Image, frames: int, d_i: int,
                 row: int, src_anim: str, src_frame: int | None) -> None:
    """Copy frames for one direction/row out of a per-animation layer sheet."""
    rows_in_file = layer.size[1] // H
    src_row = d_i if rows_in_file >= 4 else 0
    sy = src_row * H
    n = frames if src_frame is not None else min(frames, layer.size[0] // W)
    for f in range(n):
        src_col = src_frame if src_frame is not None else f
        sx = src_col * W
        if sx + W > layer.size[0] or sy + H > layer.size[1]:
            continue
        crop = layer.crop((sx, sy, sx + W, sy + H))
        sheet.paste(crop, (f * W, row * H), crop)


def compose(layers: list[str], out_path: str) -> int:
    rows = len(ANIMS) * 4
    sheet = Image.new("RGBA", (COLS * W, rows * H), (0, 0, 0, 0))
    missing: list[str] = []

    for a_i, (anim, frames) in enumerate(ANIMS):
        for d_i in range(4):
            row = a_i * 4 + d_i
            for template in layers:
                is_weapon = "weapon/" in template
                src_anim, src_frame = anim, None
                path_anim = anim
                if is_weapon and anim in WEAPON_ALT:
                    path_anim, src_frame = WEAPON_ALT[anim]

                layer = load_layer(template % path_anim)
                if layer is None:
                    if not is_weapon:
                        missing.append(template % path_anim)
                    continue
                paste_frames(sheet, layer, frames, d_i, row, src_anim, src_frame)

    if missing:
        # A missing body/clothing layer means a half-built character — fail loudly
        # rather than shipping an invisible or headless sprite.
        sys.exit(f"{os.path.basename(out_path)}: missing layers: {sorted(set(missing))}")

    sheet.save(out_path, optimize=True)
    return os.path.getsize(out_path)


def main() -> None:
    want = sys.argv[1:] or sorted(ARCHETYPES)
    unknown = [w for w in want if w not in ARCHETYPES]
    if unknown:
        sys.exit(f"unknown archetype(s): {unknown}\nknown: {sorted(ARCHETYPES)}")

    if not os.path.isdir(SRC):
        sys.exit(f"missing {SRC}\nrun: bash tools/art/vendor_lpc_layers.sh")

    os.makedirs(OUT, exist_ok=True)
    for name in want:
        size = compose(ARCHETYPES[name], os.path.join(OUT, name + ".png"))
        print(f"  {name:24s} {size // 1024:4d} KB")


if __name__ == "__main__":
    main()
