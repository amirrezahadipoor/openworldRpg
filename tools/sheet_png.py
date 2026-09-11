#!/usr/bin/env python3
"""Save composed character sheets as exact-palette indexed PNGs.

A sheet is 13x20 frames of LPC art plus palette-snapped generated poses, so it
uses well under 256 distinct RGBA colours while PNG has to store it as 4 bytes
per pixel. Writing it as an indexed PNG with the sheet's own colours as the
palette shrinks it by about two thirds **with no pixel changing at all** (the
palette is built from the image, not fitted to it, so the round trip is exact).

Used by lpc_compose.py and make_idle_frames.py so the saving is not a one-off
cleanup that the next compose would undo.
"""
import numpy as np
from PIL import Image

# Indexed PNG holds 256 entries; anything richer stays RGBA rather than losing
# colour (the only sheets that could hit this are ones with soft generated art).
MAX_COLOURS = 256


def save_sheet(img: Image.Image, path: str) -> bool:
    """Write `img` to `path` as indexed PNG when that is lossless. True if indexed."""
    arr = np.asarray(img.convert("RGBA"))
    colours, inverse = np.unique(arr.reshape(-1, 4), axis=0, return_inverse=True)
    if len(colours) > MAX_COLOURS:
        img.convert("RGBA").save(path, optimize=True)
        return False
    palette = []
    for c in colours:
        palette += [int(c[0]), int(c[1]), int(c[2]), int(c[3])]
    indexed = Image.fromarray(inverse.reshape(arr.shape[:2]).astype(np.uint8), mode="P")
    indexed.putpalette(palette, rawmode="RGBA")
    indexed.save(path, optimize=True)
    return True
