#!/usr/bin/env python3
"""Turn the source art in assets/ui/icons/_src/ into 32x32 LPC-style UI icons.

The HUD's buttons used bare geometric SVGs from assets/placeholder/, which read
as "programmer art" next to the rest of the game. The source PNGs in `_src/` are
generated art on a flat magenta screen; this script keys that screen out, trims
to the artwork, pads it square and downsamples to the same 32 px grid the tiles
and sprites use, with nearest-neighbour so the pixel steps survive.

Usage:
    python3 tools/make_ui_icons.py          # rewrite assets/ui/icons/*.png
"""

import os
import sys

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    print("Pillow is required: pip install pillow")
    sys.exit(2)

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
SRC = os.path.join(ROOT, "assets", "ui", "icons", "_src")
OUT = os.path.join(ROOT, "assets", "ui", "icons")
SIZE = 32
# The toast / boss-intro plaque, sliced 9-way. Wider than tall, and it keeps its
# corners intact because the stylebox stretches only the middle.
BANNER_SRC = os.path.join(ROOT, "assets", "ui", "_src", "banner9.png")
BANNER_OUT = os.path.join(ROOT, "assets", "ui", "banner9.png")
BANNER_SIZE = (192, 64)
# The chroma screen. Anything close to this in hue *and* strongly saturated is
# background; the icons themselves are warm browns/greys and never hit it.
KEY = (255, 0, 255)
KEY_TOLERANCE = 96
# Sources are kept at half the generated resolution: they are only ever keyed and
# shrunk to 32 px, and the full-size sheets cost 8.6 MB of the repo budget for
# pixels no output can show (see the workspace size rule in DECISIONS #69).


def key_out(img):
    """Remove the magenta screen, including the soft pink fringe around the art.

    A straight distance test leaves a purple halo where the artwork antialiases
    into the screen — visible on the whirlwind's motion arcs. So the test is in
    two parts: near-exact screen colour, and then "pink enough" (both red and
    blue high while green is low), which is what a fringe pixel looks like and
    what none of the warm-brown icon art is.
    """
    img = img.convert("RGBA")
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            near_screen = (abs(r - KEY[0]) < KEY_TOLERANCE
                           and abs(g - KEY[1]) < KEY_TOLERANCE
                           and abs(b - KEY[2]) < KEY_TOLERANCE)
            fringed = r > 120 and b > 110 and g < 110 and (r + b) > 2.1 * g
            if near_screen or fringed:
                px[x, y] = (0, 0, 0, 0)
            else:
                px[x, y] = (r, g, b, a)
    return img


def trim(img):
    bbox = img.getbbox()
    return img.crop(bbox) if bbox else img


def despill(img):
    """Clear the last magenta-blended pixels left where the art meets the screen.

    Downsampling keeps a handful of magenta-tinted edge pixels, which is visible
    at button size. Nothing in this icon set is purple, so "red and blue both
    dominate green" is a safe rule for what is spill rather than art.
    """
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            if r > 100 and b > 100 and g < 0.55 * min(r, b):
                px[x, y] = (0, 0, 0, 0)
    return img


def to_icon(img):
    img = key_out(img)
    img = trim(img)
    w, h = img.size
    side = max(w, h)
    # A one-pixel margin so the outline is not clipped by the button edge.
    canvas = Image.new("RGBA", (side + 2, side + 2), (0, 0, 0, 0))
    canvas.paste(img, ((side - w) // 2 + 1, (side - h) // 2 + 1), img)
    # Kept square (with the 1 px margin) rather than re-trimmed: TextureButton's
    # KEEP_ASPECT_CENTERED then scales every icon by the same factor, so no icon
    # silently renders smaller than its neighbours.
    return despill(canvas.resize((SIZE, SIZE), Image.NEAREST))


def make_banner():
    if not os.path.exists(BANNER_SRC):
        return None
    img = despill(trim(key_out(Image.open(BANNER_SRC))))
    img = img.resize(BANNER_SIZE, Image.LANCZOS)
    # Re-key after scaling: resampling can pull a little screen colour in.
    img = despill(img)
    img.save(BANNER_OUT)
    return BANNER_OUT


def main():
    if not os.path.isdir(SRC):
        print("no source art at %s" % SRC)
        return 1
    os.makedirs(OUT, exist_ok=True)
    made = []
    for name in sorted(os.listdir(SRC)):
        if not name.lower().endswith(".png"):
            continue
        icon = to_icon(Image.open(os.path.join(SRC, name)))
        dest = os.path.join(OUT, name)
        icon.save(dest)
        made.append(name)
        print("  %-16s -> %dx%d" % (name, SIZE, SIZE))
    print("wrote %d icons to assets/ui/icons/" % len(made))
    banner = make_banner()
    print("  banner9.png      -> %s" % ("%dx%d" % BANNER_SIZE if banner else "missing source"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
