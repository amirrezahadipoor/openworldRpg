#!/usr/bin/env python3
"""Turn source art in assets/world/_src/ into 16 px world sprites.

The coin and item-drop pickups were the last vector placeholders in the world:
`assets/placeholder/gold.svg` is two concentric circles drawn by hand, and every
chest that opened threw a handful of them onto the grass next to LPC pixel art.
They worked, and they looked like a different game (audit v4 #7).

Same pipeline as the UI icons (tools/make_ui_icons.py): key the magenta screen,
trim to the artwork, pad square, downsample with nearest-neighbour so the pixel
steps survive.

Usage:
    python3 tools/make_pickup_art.py          # write assets/world/*.png
"""

from __future__ import annotations

import os
import sys

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    print("Pillow is required: pip install pillow")
    sys.exit(2)

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_ui_icons import despill, key_out, trim  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SRC = os.path.join(ROOT, "assets", "world", "_src")
OUT = os.path.join(ROOT, "assets", "world")
## 24 px: the placeholder this replaces was 16x16, but at that size the generated
## art turns to mush (a coin with a mark on it stops being a coin), and a pickup is
## meant to be readable at a glance on a phone. The world grid is 32 px, so a 24 px
## coin still reads as a small object on the ground.
SIZE = 24


def despill_purple(img) -> "Image.Image":
    """Clear the last magenta-blended pixels the shared despill rule misses.

    A spill pixel can be dark - (92, 3, 75) survived the icon tool's rule because
    that one wants r > 100 *and* b > 100 - and a single one of those on a 24 px
    sprite is a visible purple blob. Nothing in this art is purple, so "blue and
    red both well above green" is spill, whatever the brightness.
    """
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a > 0 and b > g + 30 and r > g + 30:
                px[x, y] = (0, 0, 0, 0)
    return img


def to_sprite(img) -> "Image.Image":
    img = trim(key_out(img))
    w, h = img.size
    side = max(w, h)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(img, ((side - w) // 2, (side - h) // 2), img)
    return despill_purple(despill(canvas.resize((SIZE, SIZE), Image.NEAREST)))


def main() -> int:
    if not os.path.isdir(SRC):
        print("no source art at %s" % SRC)
        return 1
    made = 0
    for name in sorted(os.listdir(SRC)):
        if not name.lower().endswith(".png"):
            continue
        sprite = to_sprite(Image.open(os.path.join(SRC, name)))
        sprite.save(os.path.join(OUT, name))
        print("  %-14s -> %dx%d" % (name, SIZE, SIZE))
        made += 1
    print("wrote %d sprites to assets/world/" % made)
    return 0


if __name__ == "__main__":
    sys.exit(main())
