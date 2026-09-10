#!/usr/bin/env python3
"""Composes LPC layer spritesheets into game-ready character sheets.

Reads raw CC-BY-SA-3.0 LPC layers from the (toolchain-only) clone at
/tmp/rpg-toolchain/lpc-gen and bakes layered characters into
assets/lpc/player_<armor>_<weapon>.png — one RGBA sheet each:

  layout: 13 cols x 20 rows of 64px frames
          rows 0-3   idle      (n w s e)
          rows 4-7   walk
          rows 8-11  slash     (melee attack)
          rows 12-15 spellcast (abilities)
          rows 16-19 hurt

Layer stack (z order): body -> pants -> shirt/armor -> boots -> hair -> weapon.
Equipment variants: armor none|leather, weapon none|sword  (4 sheets).
Attribution: see CREDITS.md (Liberated Pixel Cup contributors, CC-BY-SA-3.0).
"""
import os
import glob
from PIL import Image

SRC = "/tmp/rpg-toolchain/lpc-gen/spritesheets"
OUT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "assets", "lpc"))

ANIMS = [("idle", 2), ("walk", 9), ("slash", 6), ("spellcast", 7), ("hurt", 6)]
DIRS = ["n", "w", "s", "e"]
COLS = 13
W, H = 64, 64


def load_layer(rel):
    p = os.path.join(SRC, rel)
    if not os.path.exists(p):
        return None
    return Image.open(p).convert("RGBA")


def paste_frame(dst, layer, anim, frames, d_i, f, row, src_anim=None, src_frame=None):
    """Copy one 64px frame from a compact per-anim layer sheet."""
    a = src_anim or anim
    fr = src_frame if src_frame is not None else f
    img_h = layer.size[1]
    rows_in_file = img_h // H
    src_row = d_i if rows_in_file >= 4 else 0
    sx = fr * W
    sy = src_row * H
    if sx + W > layer.size[0]:
        return
    crop = layer.crop((sx, sy, sx + W, sy + H))
    dst.paste(crop, (f * W, row * H), crop)


# Weapon fallback: hold the ready pose during attack/cast rows.
WEAPON_ALT = {"slash": ("combat_idle", 1), "spellcast": ("combat_idle", 0)}


def compose(layers, out_path):
    rows = len(ANIMS) * 4
    sheet = Image.new("RGBA", (COLS * W, rows * H), (0, 0, 0, 0))
    for a_i, (anim, frames) in enumerate(ANIMS):
        for d_i in range(4):
            row = a_i * 4 + d_i
            for rel in layers:
                is_weapon = "weapon/" in rel
                src_anim, src_frame = None, None
                path_anim = anim
                if is_weapon and anim in WEAPON_ALT:
                    path_anim, src_frame = WEAPON_ALT[anim]
                    src_anim = path_anim
                layer = load_layer(rel % path_anim)
                if layer is None:
                    continue
                n = frames if src_frame is not None else min(frames, layer.size[0] // W)
                for f in range(n):
                    paste_frame(sheet, layer, anim, frames, d_i, f, row,
                                src_anim=src_anim, src_frame=src_frame)
    sheet.save(out_path, optimize=True)
    return os.path.getsize(out_path)


def main():
    os.makedirs(OUT, exist_ok=True)
    base = [
        "body/bodies/male/%s.png",
        "legs/pants/male/%s.png",
        "torso/clothes/shortsleeve/shortsleeve/male/%s.png",
        "feet/boots/basic/male/%s.png",
        "hair/bedhead/adult/%s.png",
    ]
    variants = {
        "player_none_none": base,
        "player_none_sword": base + ["weapon/sword/arming/universal/fg/%s/steel.png"],
        "player_leather_none": [base[0], base[1],
                                "torso/armour/leather/male/%s.png",
                                base[3], base[4]],
        "player_leather_sword": [base[0], base[1],
                                 "torso/armour/leather/male/%s.png",
                                 base[3], base[4],
                                 "weapon/sword/arming/universal/fg/%s/steel.png"],
    }
    for name, layers in variants.items():
        size = compose(layers, os.path.join(OUT, name + ".png"))
        print(name, size // 1024, "KB")


if __name__ == "__main__":
    main()
