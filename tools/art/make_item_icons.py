#!/usr/bin/env python3
"""Split generated item-icon sprite sheets into individual transparent PNGs.

Input:  assets/source/item_sheets/<type>._sheet.png  (a cols x rows grid of icons
        on a flat #FF00FF magenta background, ordered exactly like data/items.json).
Output: assets/items/<item_id>.png, a SIZE x SIZE transparent icon, one per id.

The source sheets are produced by an image generator (see reports); this tool
only removes the magenta key, finds each icon in its grid cell, and normalises
every icon to the same box so the inventory lines up regardless of generator
dimensions. Re-running is idempotent.
"""
import json
import os
import sys
from collections import deque

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ITEMS_JSON = os.path.join(ROOT, "data", "items.json")
SRC_DIR = os.path.join(ROOT, "assets", "source", "item_sheets")
OUT_DIR = os.path.join(ROOT, "assets", "items")
SIZE = 64
FIT = 58  # px box the artwork is scaled into inside the 64 px tile

# cols x rows per type sheet
GRID = {
    "consumable": (5, 3),
    "material": (5, 5),
    "accessory": (5, 5),
    "armor": (5, 6),
    "weapon": (5, 7),
}


def is_magenta(px):
    r, g, b = px[0], px[1], px[2]
    return r > 170 and b > 150 and g < 130 and (r - g) > 60


def remove_key(img):
    """Return RGBA image with the magenta background flood-removed from the edges."""
    img = img.convert("RGBA")
    w, h = img.size
    px = img.load()
    bg = bytearray(w * h)

    def flood(sx, sy):
        q = deque()
        if 0 <= sx < w and 0 <= sy < h and not bg[sy * w + sx] and is_magenta(px[sx, sy]):
            bg[sy * w + sx] = 1
            q.append((sx, sy))
        while q:
            x, y = q.popleft()
            for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if 0 <= nx < w and 0 <= ny < h and not bg[ny * w + nx] and is_magenta(px[nx, ny]):
                    bg[ny * w + nx] = 1
                    q.append((nx, ny))

    for x in range(w):
        flood(x, 0); flood(x, h - 1)
    for y in range(h):
        flood(0, y); flood(w - 1, y)

    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    op = out.load()
    for y in range(h):
        for x in range(w):
            i = y * w + x
            if bg[i]:
                continue
            r, g, b, a = px[x, y]
            # Kill any residual key-colour fringe on the outline.
            if r > 200 and b > 190 and g < 150:
                continue
            op[x, y] = (r, g, b, a)
    return out


def content_bbox(img):
    bbox = img.getbbox()
    return bbox


def main():
    items = json.load(open(ITEMS_JSON))["items"]
    os.makedirs(OUT_DIR, exist_ok=True)
    made = 0
    for typ, (cols, rows) in GRID.items():
        sheet_path = os.path.join(SRC_DIR, f"{typ}_sheet.png")
        if not os.path.exists(sheet_path):
            print(f"[skip] {typ}: no sheet ({sheet_path})")
            continue
        ids = [k for k, v in items.items() if v.get("type") == typ]
        sheet = Image.open(sheet_path)
        # Key the whole sheet once.
        keyed = remove_key(sheet)
        W, H = keyed.size
        cw, ch = W / cols, H / rows
        for i, iid in enumerate(ids):
            cr, rr = i % cols, i // cols
            cell = (int(cr * cw), int(rr * ch), int((cr + 1) * cw), int((rr + 1) * ch))
            tile = keyed.crop(cell)
            bbox = content_bbox(tile)
            if bbox is None:
                print(f"  [warn] empty cell for {iid}")
                continue
            art = tile.crop(bbox)
            scale = min(FIT / art.width, FIT / art.height, 1.0)
            if art.width > FIT or art.height > FIT:
                art = art.resize(
                    (max(1, int(art.width * scale)), max(1, int(art.height * scale))),
                    Image.LANCZOS,
                )
            canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
            canvas.paste(art, ((SIZE - art.width) // 2, (SIZE - art.height) // 2), art)
            canvas.save(os.path.join(OUT_DIR, f"{iid}.png"))
            made += 1
        print(f"[ok] {typ}: {len(ids)} icons from {os.path.basename(sheet_path)}")
    print(f"done: {made} icons in {OUT_DIR}")


if __name__ == "__main__":
    sys.exit(main())
