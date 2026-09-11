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

Generated pose art: if a source exists in assets/lpc/_idle_src/<name>.png (idle
frames, H5.5) or assets/lpc/_attack_src/<name>.png (a four-pose attack, H7.2),
make_idle_frames.patch_sheet() fills the matching block of every direction row.
Recomposing a sheet therefore does not silently throw that art away, and because
the block ends up entirely made of generated art, the weapon films are skipped
for that block (SKIP_WEAPON_BLOCKS) — otherwise the LPC sword would be drawn on
top of the sword baked into the generated pose.

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
WEAPON_ALT = {}   # legacy fallback for a hold-only weapon; see WEAPONS above

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
# --- weapons -----------------------------------------------------------------
# An armed character's weapon is not one sheet: upstream splits it into films
# with different canvas sizes, and the attack is the one that matters.
#
#   hold films    64 px canvas, one per animation  (idle / walk / hurt / combat)
#   attack films  128 px canvas ("slash_128" / "slash_oversize" in the upstream
#                 sheet definitions), six frames per direction, drawn at 2x so
#                 the swing can leave the character's own 64 px box
#
# Both the front and the "behind" half of the attack exist, because a swing goes
# behind the body on some frames and in front on others (zPos 9 vs 150). So an
# attack frame is composited twice: once under the character, once over it.
#
# Frames come in LPC's own direction order (n, w, s, e) down the rows.
WEAPONS = {
    "blade": {
        "idle":   ("weapon/sword/arming/universal/fg/idle/steel.png", 0, 1.0),
        "walk":   ("weapon/sword/arming/universal/fg/walk/steel.png", None, 1.0),
        "hurt":   ("weapon/sword/arming/universal/fg/hurt/steel.png", None, 1.0),
        "attack": ("weapon/sword/arming/attack_slash/fg.png", None, 0.5),
        "attack_bg": ("weapon/sword/arming/attack_slash/bg.png", None, 0.5),
    },
    "mace": {
        "idle":   ("weapon/blunt/mace/walk/mace.png", 0, 1.0),
        "walk":   ("weapon/blunt/mace/walk/mace.png", None, 1.0),
        "hurt":   ("weapon/blunt/mace/hurt/mace.png", None, 1.0),
        "attack": ("weapon/blunt/mace/attack_slash/mace.png", None, 0.5),
        "attack_bg": ("weapon/blunt/mace/attack_slash/behind/mace.png", None, 0.5),
    },
}
# Which film plays in each of our animation blocks.
WEAPON_BLOCK_FILM = {
    "idle": "idle",
    "walk": "walk",
    "slash": "attack",      # the actual swing
    "spellcast": "idle",    # armed archetypes never cast; hold instead of popping
    "hurt": "hurt",
}


def weapon_layer(kind: str, part: str) -> tuple:
    """A marker entry in an ARCHETYPES stack: this character carries a weapon."""
    return ("weapon", kind, part)

ARCHETYPES = {
    # --- player equipment variants (existing behaviour, unchanged) ---
    "player_none_none": [BODY_M, PANTS, SHIRT_SHORT, BOOTS, HEAD_M, EYES, HAIR_BEDHEAD],
    "player_none_sword": [BODY_M, PANTS, SHIRT_SHORT, BOOTS, HEAD_M, EYES, HAIR_BEDHEAD, weapon_layer("blade", "fg"), weapon_layer("blade", "bg")],
    "player_leather_none": [BODY_M, PANTS, ARMOR_LEATHER, BOOTS, HEAD_M, EYES, HAIR_BEDHEAD],
    "player_leather_sword": [BODY_M, PANTS, ARMOR_LEATHER, BOOTS, HEAD_M, EYES, HAIR_BEDHEAD, weapon_layer("blade", "fg"), weapon_layer("blade", "bg")],
    # Armour is visible for the whole ladder, not just the first set: the sheet
    # is chosen from the defence of the piece being worn (player.gd
    # _armor_look), so upgrading gear is something the player can SEE.
    "player_plate_none": [BODY_M, PANTS, ARMOR_PLATE, BOOTS, HEAD_M, EYES, HAIR_BEDHEAD],
    "player_plate_sword": [BODY_M, PANTS, ARMOR_PLATE, BOOTS, HEAD_M, EYES, HAIR_BEDHEAD, weapon_layer("blade", "fg"), weapon_layer("blade", "bg")],
    "player_legion_none": [BODY_M, PANTS, ARMOR_LEGION, BOOTS_REVISED, HEAD_M, EYES, HAIR_BEDHEAD],
    "player_legion_sword": [BODY_M, PANTS, ARMOR_LEGION, BOOTS_REVISED, HEAD_M, EYES, HAIR_BEDHEAD, weapon_layer("blade", "fg"), weapon_layer("blade", "bg")],
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
    # --- the town cast: one body each for the nine local NPCs added so that no
    # named character stands in two places at once (see DECISIONS #54). Reuses the
    # same layer recipe as the rest of the cast with its own hair/torso so a
    # village herbalist does not look like the camp vendor.
    "npc_herbalist": [BODY_F, PANTS, SHIRT_LONG, BOOTS, HEAD_F, EYES, (HAIR_LONG, {"hue": 0.28, "sat": 0.9, "val": 0.75})],
    "npc_factor": [BODY_M, PANTS, SHIRT_LONG, BOOTS_REVISED, HEAD_GAUNT, EYES, (HAIR_PLAIN, {"hue": 0.09, "sat": 0.25, "val": 0.6})],
    "npc_smith": [BODY_M, PANTS, ARMOR_LEATHER, BOOTS_REVISED, HEAD_M, EYES, (HAIR_BANGS, {"hue": 0.0, "sat": 0.4, "val": 0.3})],
    "npc_trapper": [BODY_F, PANTS, SHIRT_SHORT, BOOTS_REVISED, HEAD_F, EYES, (HAIR_LONG, {"hue": 0.02, "sat": 0.35, "val": 0.45})],
    "npc_sister": [BODY_F, PANTS, SHIRT_LONG, BOOTS, HEAD_F, EYES, (HAIR_PLAIN, {"hue": 0.55, "sat": 0.15, "val": 0.7})],
    "npc_clerk": [BODY_M, PANTS, SHIRT_LONG, BOOTS, HEAD_GAUNT, EYES, (HAIR_BANGS, {"hue": 0.6, "sat": 0.12, "val": 0.5})],
    "npc_sorrel": [BODY_F, PANTS, SHIRT_LONG, BOOTS, HEAD_ELDERLY, EYES, (HAIR_PLAIN, {"hue": 0.42, "sat": 0.2, "val": 0.95})],
    "npc_widow": [BODY_F, PANTS, SHIRT_LONG, BOOTS_REVISED, HEAD_F, EYES, (HAIR_LONG, {"hue": 0.95, "sat": 0.5, "val": 0.5})],
    "npc_adept": [BODY_F, PANTS, ARMOR_LEATHER, BOOTS, HEAD_F, EYES, (HAIR_BANGS, {"hue": 0.62, "sat": 0.55, "val": 0.65})],
    "npc_miller": [BODY_M, PANTS, SHIRT_LONG, BOOTS_REVISED, HEAD_M, EYES, (HAIR_PLAIN, {"hue": 0.12, "sat": 0.55, "val": 0.8})],
    "npc_quartermaster": [BODY_M, PANTS, ARMOR_LEGION, BOOTS_REVISED, HEAD_GAUNT, EYES, (HAIR_PLAIN, {"hue": 0.08, "sat": 0.2, "val": 0.55})],
    "npc_relicmonger": [BODY_M, PANTS, SHIRT_LONG, BOOTS_REVISED, HEAD_M, EYES, (HAIR_BANGS, {"hue": 0.9, "sat": 0.75, "val": 0.6})],
    "npc_dockhand": [BODY_F, PANTS, SHIRT_SHORT, BOOTS, HEAD_F, EYES, (HAIR_PLAIN, {"hue": 0.06, "sat": 0.8, "val": 0.5})],
    # --- enemies: distinct silhouettes, tinted per archetype at runtime ---
    # Anything that attacks with a physical blow carries a weapon that actually
    # swings (BLADE / MACE ship attack_slash frames); the beasts (wolf, husk,
    # lizard) attack with claws and the casters (shaman, revenant, archon, the
    # two spell bosses) cast with empty hands, which is what their spellcast
    # block draws. Before this, only the player and the Ember Warden held
    # anything at all: fifteen archetypes punched. See DECISIONS #67.
    "enemy_raider": [BODY_M, PANTS, ARMOR_LEATHER, BOOTS, HEAD_GAUNT, EYES, HAIR_PLAIN, weapon_layer("blade", "fg"), weapon_layer("blade", "bg")],
    # raider_brute shares the raider *archetype* but not the silhouette.
    "enemy_raider2": [BODY_M, PANTS, SHIRT_LONG, BOOTS_REVISED, HEAD_GAUNT, EYES, HAIR_BANGS, weapon_layer("mace", "fg"), weapon_layer("mace", "bg")],
    "enemy_shaman": [BODY_F, PANTS, SHIRT_LONG, BOOTS, HEAD_F, EYES, HAIR_LONG],
    "enemy_goblin": [BODY_M, PANTS, SHIRT_SHORT, BOOTS, HEAD_GOBLIN, EYES, weapon_layer("blade", "fg"), weapon_layer("blade", "bg")],
    "enemy_skeleton": [BODY_M, PANTS, ARMOR_LEATHER, BOOTS, HEAD_SKELETON, EYES, weapon_layer("blade", "fg"), weapon_layer("blade", "bg")],
    "enemy_orc": [BODY_M, PANTS, ARMOR_LEATHER, BOOTS, HEAD_ORC, EYES],
    # --- Phase F2/F3: the wider monster roster -------------------------------
    # (each keeps a distinct silhouette so a new kind reads on screen)
    "enemy_husk": [BODY_M, PANTS, SHIRT_SHORT, BOOTS, HEAD_ZOMBIE, EYES],
    "enemy_wolf": [BODY_M, PANTS, SHIRT_LONG, BOOTS_REVISED, HEAD_WOLF, EYES],
    "enemy_lizard": [BODY_M, PANTS, ARMOR_LEATHER, BOOTS, HEAD_LIZARD, EYES],
    "enemy_minotaur": [BODY_M, PANTS, ARMOR_PLATE, BOOTS, HEAD_MINOTAUR, EYES, weapon_layer("mace", "fg"), weapon_layer("mace", "bg")],
    "enemy_troll": [BODY_M, PANTS, ARMOR_LEATHER, BOOTS, HEAD_TROLL, EYES, weapon_layer("mace", "fg"), weapon_layer("mace", "bg")],
    "enemy_legion": [BODY_M, PANTS, ARMOR_LEGION, BOOTS_REVISED, HEAD_SKELETON, EYES, weapon_layer("blade", "fg"), weapon_layer("blade", "bg")],
    "enemy_revenant": [BODY_F, PANTS, ARMOR_PLATE, BOOTS, HEAD_ZOMBIE, EYES, HAIR_LONG],
    "enemy_archon": [BODY_M, PANTS, ARMOR_LEGION, BOOTS_REVISED, HEAD_ORC, EYES, HAIR_BANGS],
    # bosses
    "boss_goblin_king": [BODY_M, PANTS, ARMOR_PLATE, BOOTS, HEAD_GOBLIN, EYES, weapon_layer("mace", "fg"), weapon_layer("mace", "bg")],
    "boss_slag_wraith": [BODY_M, PANTS, ARMOR_LEGION, BOOTS_REVISED, HEAD_ZOMBIE, EYES, HAIR_LONG],
    "boss_frost_giant": [BODY_M, PANTS, ARMOR_PLATE, BOOTS, HEAD_TROLL, EYES, weapon_layer("mace", "fg"), weapon_layer("mace", "bg")],
    "boss_bone_titan": [BODY_M, PANTS, ARMOR_LEGION, BOOTS, HEAD_SKELETON, EYES, weapon_layer("blade", "fg"), weapon_layer("blade", "bg")],
    "boss_choir_priest": [BODY_F, PANTS, ARMOR_LEGION, BOOTS_REVISED, HEAD_ZOMBIE, EYES, HAIR_LONG],
    "boss_ashen_herald": [BODY_M, PANTS, ARMOR_PLATE, BOOTS_REVISED, HEAD_MINOTAUR, EYES, weapon_layer("blade", "fg"), weapon_layer("blade", "bg")],
    # The Ember Warden — the game's final boss — carried a generic orc sheet and
    # a runtime tint. It now has its own body: plate, gaunt face, long hair and
    # a blade, unlike any other boss on the roster.
    "enemy_warden": [BODY_M, PANTS, ARMOR_PLATE, BOOTS_REVISED, HEAD_GAUNT, EYES, HAIR_LONG, weapon_layer("blade", "fg"), weapon_layer("blade", "bg")],
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


def weapon_column_ok(name: str, anim: str, col: int) -> bool:
    """May the LPC weapon film be composited into this column of this block?

    A generated pose is drawn with the character's weapon already in hand (that
    is what the generator is asked for), so compositing the film over it too
    would draw two swords. But a block is not necessarily all-generated: the
    idle patch only fills columns 2-3, and when a sheet has no idle art at all
    (its old poses were pruned because the character picked up a weapon) columns
    0-1 are still plain LPC frames — those need the film, or the idle loop pops
    between a bare hand and a sword. So the answer is per column, derived from
    the same source folders and column layout make_idle_frames.py patches with.
    """
    patcher = _idle_patcher()
    if patcher is None or anim not in patcher.SRC_DIRS:
        return True          # walk/hurt/spellcast are never generated art
    src = os.path.join(patcher.SRC_DIRS[anim], name + ".png")
    if not os.path.exists(src):
        return True
    first = patcher.FIRST_COL[anim]
    return col < first or col >= first + patcher.KEEP_COLS[anim]


def paste_weapon(sheet: Image.Image, kind: str, part: str, anim: str, d_i: int,
                 row: int, frames: int, name: str = "") -> int:
    """Composite one weapon film into a block. Returns frames actually pasted.

    The film's canvas decides the geometry: 64 px frames paste 1:1, 128 px frames
    (the attacks) are halved, which lands them exactly back on the character's own
    grid — the oversize canvas is the same picture at 2x, so the swing arc simply
    has room to leave the body's box.
    """
    spec_table = WEAPONS.get(kind, {})
    film = WEAPON_BLOCK_FILM.get(anim, "idle")
    if part == "bg":
        film = film + "_bg" if film == "attack" else film
    spec = spec_table.get(film)
    if spec is None:
        return 0
    path, src_frame, scale = spec
    layer = load_layer(path)
    if layer is None:
        return 0
    cell = W
    if scale != 1.0:
        layer = layer.resize((max(1, int(layer.width * scale)), max(1, int(layer.height * scale))),
                             Image.NEAREST)
        cell = int(round(W * scale))
    src_row = d_i if layer.size[1] // cell >= 4 else 0
    pasted = 0
    for f in range(frames):
        if name and not weapon_column_ok(name, anim, f):
            continue
        src_col = src_frame if src_frame is not None else f
        if src_col * cell + cell > layer.size[0] or src_row * cell + cell > layer.size[1]:
            continue
        crop = layer.crop((src_col * cell, src_row * cell, src_col * cell + cell, src_row * cell + cell))
        if crop.getbbox() is None:
            continue
        if cell != W:
            crop = crop.resize((W, H), Image.NEAREST)
        sheet.paste(crop, (f * W, row * H), crop)
        pasted += 1
    return pasted


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
    name = os.path.basename(out_path)[:-4]      # for weapon_skips()
    rows = len(ANIMS) * 4
    sheet = Image.new("RGBA", (COLS * W, rows * H), (0, 0, 0, 0))
    missing: list[str] = []

    # A weapon composites in three passes per block: its "behind" film under the
    # character, the character, then its front film over it — a swing crosses the
    # body on some frames and must not be flattened onto one side of it.
    behind = [l for l in layers if _is_weapon(l) and _weapon_part(l) == "bg"]
    weapon_fg = [l for l in layers if _is_weapon(l) and _weapon_part(l) == "fg"]
    body = [l for l in layers if not _is_weapon(l)]

    for a_i, (anim, frames) in enumerate(ANIMS):
        for d_i in range(4):
            row = a_i * 4 + d_i
            for spec in behind + body + weapon_fg:
                if _is_weapon(spec):
                    paste_weapon(sheet, spec[1], _weapon_part(spec), anim, d_i, row, frames, name)
                    continue
                template, adjust = spec if isinstance(spec, tuple) else (spec, None)
                layer = load_layer(template % anim, adjust)
                if layer is None:
                    missing.append(template % anim)
                    continue
                paste_frames(sheet, layer, frames, d_i, row, anim, None)

    if missing:
        # A missing body/clothing layer means a half-built character — fail loudly
        # rather than shipping an invisible or headless sprite.
        sys.exit(f"{os.path.basename(out_path)}: missing layers: {sorted(set(missing))}")

    sheet.save(out_path, optimize=True)
    return os.path.getsize(out_path)


def _is_weapon(spec) -> bool:
    return isinstance(spec, tuple) and len(spec) == 3 and spec[0] == "weapon"


def _weapon_part(spec) -> str:
    return spec[2] if _is_weapon(spec) else ""


def _idle_patcher():
    """tools/make_idle_frames.py, or None when it (or its deps) is unavailable.

    Composing a character is still the headline job of this script, so a missing
    optional dependency must not stop a plain recompose.
    """
    try:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import make_idle_frames  # noqa: PLC0415  (optional, imported on use)
        return make_idle_frames
    except ImportError:
        return None


def check() -> bool:
    """Verify every weapon film exists and every armed sheet really swings.

    Three failures matter here, and none of them is visible in a diff:
      * a weapon film path that no longer exists upstream (the swing silently
        becomes a bare-handed lunge);
      * an attack film whose canvas is not 2x the hold films (it would paste
        misaligned — the whole reason the 128 px split exists);
      * a composed sheet whose attack block is identical to its walk block,
        i.e. the character animates a stride where an attack should be.
    """
    problems = []
    for kind, films in sorted(WEAPONS.items()):
        for name, spec in sorted(films.items()):
            path, _frame, scale = spec
            full = os.path.join(SRC, path)
            if not os.path.exists(full):
                problems.append("%s/%s: missing film %s" % (kind, name, path))
                continue
            img = Image.open(full)
            cells = (img.width // W, img.height // H)
            if name.startswith("attack") and scale != 0.5:
                problems.append("%s/%s: attack film is not the oversize canvas" % (kind, name))
            if name.startswith("attack") and cells[0] < 6:
                problems.append("%s/%s: attack film has %d frames, need 6"
                                % (kind, name, cells[0]))
            if not name.startswith("attack") and scale != 1.0:
                problems.append("%s/%s: hold film should paste 1:1" % (kind, name))
    for arch, stack in sorted(ARCHETYPES.items()):
        if not any(_is_weapon(spec) for spec in stack):
            continue
        sheet_path = os.path.join(OUT, arch + ".png")
        if not os.path.exists(sheet_path):
            problems.append("%s: no composed sheet" % arch)
            continue
        sheet = Image.open(sheet_path).convert("RGBA")
        for d_i in range(4):
            walk = sheet.crop((0, (1 * 4 + d_i) * H, COLS * W, (1 * 4 + d_i + 1) * H))
            busy = (2 * 4 + d_i) * H
            slash = sheet.crop((0, busy, COLS * W, busy + H))
            if slash.getbbox() is None:
                problems.append("%s/dir %d: attack block is empty" % (arch, d_i))
                continue
            diff = _block_difference(walk, slash)
            if diff < 3.0:
                problems.append("%s/dir %d: attack block looks like a walk (%.1f)"
                                % (arch, d_i, diff))
    for problem in problems:
        print("  PROBLEM: %s" % problem)
    if problems:
        print("ANIM CHECK: FAILED (%d problems)" % len(problems))
        return False
    armed = sum(1 for stack in ARCHETYPES.values() if any(_is_weapon(s) for s in stack))
    print("ANIM CHECK: PASSED — %d weapons, %d armed characters swing in 4 directions"
          % (len(WEAPONS), armed))
    return True


def _block_difference(a: Image.Image, b: Image.Image) -> float:
    import numpy as np
    aa = np.asarray(a.convert("RGBA"), dtype=np.int16)
    bb = np.asarray(b.convert("RGBA"), dtype=np.int16)
    solid = (aa[..., 3] > 40) | (bb[..., 3] > 40)
    if not solid.any():
        return 0.0
    return float(np.abs(aa[..., :3][solid] - bb[..., :3][solid]).mean())


def main() -> None:
    if "--check" in sys.argv[1:]:
        sys.exit(0 if check() else 1)
    want = [a for a in sys.argv[1:] if not a.startswith("-")] or sorted(ARCHETYPES)
    unknown = [w for w in want if w not in ARCHETYPES]
    if unknown:
        sys.exit(f"unknown archetype(s): {unknown}\nknown: {sorted(ARCHETYPES)}")

    if not os.path.isdir(SRC):
        sys.exit(f"missing {SRC}\nrun: bash tools/art/vendor_lpc_layers.sh")

    os.makedirs(OUT, exist_ok=True)
    idle = _idle_patcher()
    patched: list = []
    for name in want:
        assert_complete(name, ARCHETYPES[name])
        size = compose(ARCHETYPES[name], os.path.join(OUT, name + ".png"))
        note = ""
        if idle is not None:
            entry = idle.patch_sheet(name) if any(
                os.path.exists(os.path.join(d, name + ".png")) for d in idle.SRC_DIRS.values()
            ) else {}
            if entry:
                note = "  + generated " + "/".join(sorted(entry)) + " art"
        patched.append(name)
        print(f"  {name:24s} {size // 1024:4d} KB{note}")
    if idle is not None:
        idle.refresh_manifest(patched)


if __name__ == "__main__":
    main()
