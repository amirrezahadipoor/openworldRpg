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
import colorsys
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
HEAD_ZOMBIE = "head/heads/zombie/adult/%s.png"
HEAD_WOLF = "head/heads/wolf/male/%s.png"
HEAD_LIZARD = "head/heads/lizard/male/%s.png"
HEAD_MINOTAUR = "head/heads/minotaur/male/%s.png"
HEAD_TROLL = "head/heads/troll/adult/%s.png"
EYES = "eyes/human/adult/neutral/%s.png"
PANTS = "legs/pants/male/%s.png"
SHIRT_SHORT = "torso/clothes/shortsleeve/shortsleeve/male/%s.png"
SHIRT_LONG = "torso/clothes/longsleeve/longsleeve/male/%s.png"
ARMOR_LEATHER = "torso/armour/leather/male/%s.png"
ARMOR_PLATE = "torso/armour/plate/male/%s.png"
ARMOR_LEGION = "torso/armour/legion/male/%s.png"
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
    # Armour is visible for the whole ladder, not just the first set: the sheet
    # is chosen from the defence of the piece being worn (player.gd
    # _armor_look), so upgrading gear is something the player can SEE.
    "player_plate_none": [BODY_M, PANTS, ARMOR_PLATE, BOOTS, HEAD_M, EYES, HAIR_BEDHEAD],
    "player_plate_sword": [BODY_M, PANTS, ARMOR_PLATE, BOOTS, HEAD_M, EYES, HAIR_BEDHEAD, SWORD],
    "player_legion_none": [BODY_M, PANTS, ARMOR_LEGION, BOOTS_REVISED, HEAD_M, EYES, HAIR_BEDHEAD],
    "player_legion_sword": [BODY_M, PANTS, ARMOR_LEGION, BOOTS_REVISED, HEAD_M, EYES, HAIR_BEDHEAD, SWORD],
    # --- NPCs: Elder Rowan (elderly), Hunter Kael, the camp vendor ---
    "npc_elder": [BODY_M, PANTS, SHIRT_LONG, BOOTS, HEAD_ELDERLY, EYES, (HAIR_LONG, {"hue": 0.0, "sat": 0.15, "val": 0.85})],
    "npc_hunter": [BODY_M, PANTS, SHIRT_LONG, BOOTS_REVISED, HEAD_M, EYES, (HAIR_BANGS, {"hue": 0.0, "sat": 0.5, "val": 0.55})],
    "npc_vendor": [BODY_M, PANTS, SHIRT_SHORT, BOOTS, HEAD_M, EYES, (HAIR_PLAIN, {"hue": 0.03, "sat": 0.9, "val": 0.7})],
    # Every named NPC gets a body of their own. Eight of the eleven used to fall
    # through settlement.gd's three-entry lookup and render as the placeholder
    # sprite, so half the cast was an untextured stand-in.
    "npc_wren": [BODY_F, PANTS, SHIRT_SHORT, BOOTS, HEAD_F, EYES, (HAIR_BANGS, {"hue": -0.04, "sat": 1.25, "val": 0.80})],
    "npc_trader": [BODY_F, PANTS, SHIRT_LONG, BOOTS_REVISED, HEAD_F, EYES, (HAIR_LONG, {"hue": -0.09, "sat": 1.2, "val": 1.15})],
    "npc_fenwick": [BODY_M, PANTS, SHIRT_LONG, BOOTS, HEAD_ELDERLY, EYES, (HAIR_PLAIN, {"hue": 0.5, "sat": 0.12, "val": 0.92})],
    "npc_ashe": [BODY_M, PANTS, SHIRT_LONG, BOOTS_REVISED, HEAD_M, EYES, (HAIR_PLAIN, {"hue": 0.02, "sat": 0.35, "val": 0.5})],
    "npc_captain": [BODY_M, PANTS, ARMOR_LEATHER, BOOTS_REVISED, HEAD_M, EYES, (HAIR_BANGS, {"hue": -0.02, "sat": 0.6, "val": 0.45})],
    "npc_magistrate": [BODY_M, PANTS, SHIRT_LONG, BOOTS, HEAD_GAUNT, EYES, (HAIR_PLAIN, {"hue": 0.0, "sat": 0.1, "val": 0.35})],
    "npc_mireille": [BODY_F, PANTS, ARMOR_LEATHER, BOOTS, HEAD_F, EYES, (HAIR_LONG, {"hue": 0.0, "sat": 1.0, "val": 1.0})],
    "npc_warden": [BODY_F, PANTS, ARMOR_LEGION, BOOTS_REVISED, HEAD_F, EYES, (HAIR_BANGS, {"hue": 0.45, "sat": 0.35, "val": 0.4})],
    # --- enemies: distinct silhouettes, tinted per archetype at runtime ---
    "enemy_raider": [BODY_M, PANTS, ARMOR_LEATHER, BOOTS, HEAD_GAUNT, EYES, HAIR_PLAIN],
    # raider_brute shares the raider *archetype* but not the silhouette.
    "enemy_raider2": [BODY_M, PANTS, SHIRT_LONG, BOOTS_REVISED, HEAD_GAUNT, EYES, HAIR_BANGS],
    "enemy_shaman": [BODY_F, PANTS, SHIRT_LONG, BOOTS, HEAD_F, EYES, HAIR_LONG],
    "enemy_goblin": [BODY_M, PANTS, SHIRT_SHORT, BOOTS, HEAD_GOBLIN, EYES],
    "enemy_skeleton": [BODY_M, PANTS, ARMOR_LEATHER, BOOTS, HEAD_SKELETON, EYES],
    "enemy_orc": [BODY_M, PANTS, ARMOR_LEATHER, BOOTS, HEAD_ORC, EYES],
    # --- Phase F2/F3: the wider monster roster -------------------------------
    # (each keeps a distinct silhouette so a new kind reads on screen)
    "enemy_husk": [BODY_M, PANTS, SHIRT_SHORT, BOOTS, HEAD_ZOMBIE, EYES],
    "enemy_wolf": [BODY_M, PANTS, SHIRT_LONG, BOOTS_REVISED, HEAD_WOLF, EYES],
    "enemy_lizard": [BODY_M, PANTS, ARMOR_LEATHER, BOOTS, HEAD_LIZARD, EYES],
    "enemy_minotaur": [BODY_M, PANTS, ARMOR_PLATE, BOOTS, HEAD_MINOTAUR, EYES],
    "enemy_troll": [BODY_M, PANTS, ARMOR_LEATHER, BOOTS, HEAD_TROLL, EYES],
    "enemy_legion": [BODY_M, PANTS, ARMOR_LEGION, BOOTS_REVISED, HEAD_SKELETON, EYES],
    "enemy_revenant": [BODY_F, PANTS, ARMOR_PLATE, BOOTS, HEAD_ZOMBIE, EYES, HAIR_LONG],
    "enemy_archon": [BODY_M, PANTS, ARMOR_LEGION, BOOTS_REVISED, HEAD_ORC, EYES, HAIR_BANGS],
    # bosses
    "boss_goblin_king": [BODY_M, PANTS, ARMOR_PLATE, BOOTS, HEAD_GOBLIN, EYES],
    "boss_slag_wraith": [BODY_M, PANTS, ARMOR_LEGION, BOOTS_REVISED, HEAD_ZOMBIE, EYES, HAIR_LONG],
    "boss_frost_giant": [BODY_M, PANTS, ARMOR_PLATE, BOOTS, HEAD_TROLL, EYES],
    "boss_bone_titan": [BODY_M, PANTS, ARMOR_LEGION, BOOTS, HEAD_SKELETON, EYES],
    "boss_choir_priest": [BODY_F, PANTS, ARMOR_LEGION, BOOTS_REVISED, HEAD_ZOMBIE, EYES, HAIR_LONG],
    "boss_ashen_herald": [BODY_M, PANTS, ARMOR_PLATE, BOOTS_REVISED, HEAD_MINOTAUR, EYES],
    # The Ember Warden — the game's final boss — carried a generic orc sheet and
    # a runtime tint. It now has its own body: plate, gaunt face, long hair and
    # a blade, unlike any other boss on the roster.
    "enemy_warden": [BODY_M, PANTS, ARMOR_PLATE, BOOTS_REVISED, HEAD_GAUNT, EYES, HAIR_LONG, SWORD],
}


def load_layer(rel: str, adjust: dict | None = None):
    """Load a layer, optionally recolouring it.

    LPC layers ship pre-coloured, so every character composed from the same hair
    (or cloth) layer comes out the same person. `adjust` shifts the layer's own
    pixels — hue/sat/val multipliers applied only where the layer has alpha —
    which is how the eleven NPCs get eleven different heads of hair without a
    second art pipeline. (adjust=None leaves the layer alone.)
    """
    p = os.path.join(SRC, rel)
    if not os.path.exists(p):
        return None
    img = Image.open(p).convert("RGBA")
    if not adjust:
        return img
    dh = float(adjust.get("hue", 0.0))
    ds = float(adjust.get("sat", 1.0))
    dv = float(adjust.get("val", 1.0))
    px = img.load()
    for y in range(img.size[1]):
        for x in range(img.size[0]):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
            h = (h + dh) % 1.0
            s = min(1.0, s * ds)
            v = min(1.0, v * dv)
            r2, g2, b2 = colorsys.hsv_to_rgb(h, s, v)
            px[x, y] = (int(r2 * 255), int(g2 * 255), int(b2 * 255), a)
    return img


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


def assert_complete(name: str, layers: list[str]) -> None:
    """Guard against the bug that shipped in the original player sprite.

    body/bodies/* in the LPC generator is HEADLESS — the head is a separate
    layer under head/heads/*. The original tools/lpc_compose.py omitted it, so
    the player — the most visible character in the game — rendered with hair
    floating above a headless torso. Headless CI could not see it; it was only
    caught by rendering the real game (tools/art/capture_screenshot.gd).

    Every archetype must therefore include a head layer, and a face-bearing one
    must pair it with eyes, or the composite is wrong by construction.
    """
    flat = [l[0] if isinstance(l, tuple) else l for l in layers]
    has_head = any(l.startswith("head/heads/") for l in flat)
    has_eyes = any("eyes/" in l for l in flat)
    has_body = any("body/bodies/" in l for l in flat)
    problems = []
    if not has_body:
        problems.append("no body layer")
    if not has_head:
        problems.append("NO HEAD LAYER (sprite would render headless)")
    if has_head and not has_eyes and "skeleton" not in " ".join(flat):
        problems.append("head without eyes layer")
    if problems:
        sys.exit(f"{name}: " + "; ".join(problems))


def compose(layers: list[str], out_path: str) -> int:
    rows = len(ANIMS) * 4
    sheet = Image.new("RGBA", (COLS * W, rows * H), (0, 0, 0, 0))
    missing: list[str] = []

    for a_i, (anim, frames) in enumerate(ANIMS):
        for d_i in range(4):
            row = a_i * 4 + d_i
            for spec in layers:
                template, adjust = spec if isinstance(spec, tuple) else (spec, None)
                is_weapon = "weapon/" in template
                src_anim, src_frame = anim, None
                path_anim = anim
                if is_weapon and anim in WEAPON_ALT:
                    path_anim, src_frame = WEAPON_ALT[anim]

                layer = load_layer(template % path_anim, adjust)
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
        assert_complete(name, ARCHETYPES[name])
        size = compose(ARCHETYPES[name], os.path.join(OUT, name + ".png"))
        print(f"  {name:24s} {size // 1024:4d} KB")


if __name__ == "__main__":
    main()
