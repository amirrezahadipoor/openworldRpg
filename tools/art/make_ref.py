#!/usr/bin/env python3
"""Build the image generator's reference sheet for one character.

The pose art pipeline (tools/make_idle_frames.py) is fed a single reference image
per character: an enlarged view of the frames the *composed* sheet already has, on
the magenta chroma screen the cutter keys out. This script makes that reference, so
a character's art can always be regenerated from what the repo ships.

    python3 tools/art/make_ref.py enemy_husk slash          # -> /tmp/ref_enemy_husk_slash.png
    python3 tools/art/make_ref.py npc_elder                 # idle by default

Layout of a composed LPC sheet (assets/lpc/<name>.png): 13 columns x 20 rows of
64 px, four direction rows per animation block — idle rows 4-7, walk 8-11, slash
12-15, spellcast 16-19 — and n/w/s/e order inside a block.

Written into the repo after the scratch copy of this tool was lost with /tmp
(DECISIONS #81): a helper that only lives in a scratch directory is a helper that
disappears, and this one is the starting point of every future art batch.
"""
import argparse
import os
import sys

from PIL import Image

FRAME = 64
COLS = 13
ROWS = 20
DIRS = 4
# Which LPC columns of each block become the reference's pose rows: the frames
# the generator is asked to redraw. Idle ships two unique frames; the swing and
# the cast are sampled across their six/seven so the poses read as a sequence.
BLOCK_ROW = {"idle": 0, "slash": 2, "spellcast": 3}
PICK = {"idle": [0, 1], "slash": [0, 2, 4, 5], "spellcast": [0, 2, 4, 6]}
SCREEN = (255, 0, 255, 255)   # the chroma key the patcher expects
SCALE = 6                     # 64 px -> 384 px per cell


def build(sheet_path: str, kind: str, screen=SCREEN, scale: int = SCALE) -> Image.Image:
    sheet = Image.open(sheet_path).convert("RGBA")
    if sheet.size != (COLS * FRAME, ROWS * FRAME):
        raise ValueError("%s: expected a %dx%d LPC sheet, found %s"
                         % (sheet_path, COLS * FRAME, ROWS * FRAME, sheet.size))
    block = BLOCK_ROW[kind]
    poses = PICK[kind]
    cell = FRAME * scale
    out = Image.new("RGBA", (DIRS * cell, len(poses) * cell), screen)
    for d_i in range(DIRS):
        for p_i, col in enumerate(poses):
            x, y = col * FRAME, (block * DIRS + d_i) * FRAME
            frame = sheet.crop((x, y, x + FRAME, y + FRAME))
            frame = frame.resize((cell, cell), Image.LANCZOS)
            # Composite onto the screen: the sheet's own alpha would otherwise
            # leave the generator guessing what the background is.
            tile = Image.new("RGBA", (cell, cell), screen)
            tile.alpha_composite(frame)
            out.alpha_composite(tile, (d_i * cell, p_i * cell))
    return out.convert("RGB")


def main() -> int:
    ap = argparse.ArgumentParser(description="Reference sheet for generated pose art.")
    ap.add_argument("sheet", help="composed sheet name, e.g. enemy_husk")
    ap.add_argument("kind", nargs="?", default="idle", choices=sorted(BLOCK_ROW))
    ap.add_argument("--scale", type=int, default=SCALE)
    ap.add_argument("--out", default="")
    args = ap.parse_args()

    root = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
    name = args.sheet[:-4] if args.sheet.endswith(".png") else args.sheet
    path = os.path.join(root, "assets", "lpc", name + ".png")
    if not os.path.exists(path):
        sys.exit("no such sheet: %s" % path)
    out = args.out or "/tmp/ref_%s%s.png" % (name, "" if args.kind == "idle" else "_" + args.kind)
    build(path, args.kind, scale=args.scale).save(out)
    print("%s -> %s (%s)" % (name, out, args.kind))
    return 0


if __name__ == "__main__":
    sys.exit(main())
