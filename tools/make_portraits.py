#!/usr/bin/env python3
"""Dialogue portraits for every named NPC, cut from the composed LPC sheets.

The game shipped with no art in the dialogue box at all: `dialogue_box.gd` drew
a name label and a paragraph, so eleven characters were a name and a paragraph.
Rather than invent a second art pipeline, this cuts the head-and-shoulders out
of the *same* sheet the NPC walks around with, so the portrait can never
disagree with the sprite standing in the world.

Source frame: the south-facing idle pose (row 2 of the 13x20 / 64px grid, column
0) — the pose an NPC is in when you walk up and talk to them. Every portrait uses
the same crop box so the cast is framed consistently.

Output: assets/portraits/<npc_id>.png, 120px tall (nearest-neighbour upscale, to
keep the pixel edges crisp), transparent background.

Run: python3 tools/make_portraits.py     (after tools/lpc_compose.py)
"""
import json
import os
import sys

from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
ASSETS = os.path.join(ROOT, "assets", "lpc")
OUT = os.path.join(ROOT, "assets", "portraits")

# 64px LPC frame, row = block * 4 + dir_row (idle block 0, south-facing row 2).
FRAME = 64
ROW_WIDTH = 13
SOUTH_IDLE_ROW = 2

# Head + shoulders inside one 64px frame. LPC puts the head around y 6..30 for
# an adult body; the shoulders start just under it.
CROP = (16, 6, 48, 42)      # left, top, right, bottom -> 32 x 36 head+shoulders
SCALE = 4                   # -> 128 x 144, pixel edges kept crisp


def portrait_from_sheet(path: str, out_path: str) -> bool:
    if not os.path.exists(path):
        return False
    sheet = Image.open(path).convert("RGBA")
    left, top, right, bottom = CROP
    # Offset into the south-facing row: row 2 of the idle block is the pose that
    # faces the camera. (Without the offset this silently crops the north-facing
    # pose and every portrait is the back of someone's head.)
    y0 = SOUTH_IDLE_ROW * FRAME
    box = (left, y0 + top, right, y0 + bottom)
    if sheet.size[0] < right or sheet.size[1] < (y0 + bottom):
        return False
    frame = sheet.crop(box)
    frame = frame.resize((frame.size[0] * SCALE, frame.size[1] * SCALE), Image.NEAREST)
    frame.save(out_path, optimize=True)
    return True


def main() -> None:
    roster_path = os.path.join(ROOT, "data", "npcs.json")
    with open(roster_path) as f:
        roster = json.load(f)["npcs"]

    os.makedirs(OUT, exist_ok=True)
    written, missing = [], []
    for npc_id, entry in roster.items():
        sheet = str(entry.get("sheet", ""))
        if sheet == "":
            missing.append("%s: no sheet in data/npcs.json" % npc_id)
            continue
        src = os.path.join(ROOT, sheet.replace("res://", ""))
        dst = os.path.join(OUT, "%s.png" % npc_id)
        if portrait_from_sheet(src, dst):
            written.append("%s <- %s (%d KB)" % (npc_id, os.path.basename(src),
                                                 os.path.getsize(dst) // 1024))
        else:
            missing.append("%s: cannot crop %s" % (npc_id, src))

    for w in written:
        print("  " + w)
    if missing:
        for m in missing:
            print("  MISSING " + m, file=sys.stderr)
        sys.exit("make_portraits: %d NPC(s) without a portrait" % len(missing))
    print("wrote %d portraits to %s" % (len(written), OUT))


if __name__ == "__main__":
    main()
