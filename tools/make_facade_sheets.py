#!/usr/bin/env python3
"""Builds settlement building-facade atlases from generated art (H6.1).

The problem
-----------
A settlement's houses were procedural `Polygon2D` shapes: a wall quad, two roof
slopes and a door rectangle, tinted per biome. They read as cardboard cut-outs
next to LPC terrain and 64 px characters, and no amount of polygon tweaking fixes
that — the fix is art, on the 32 px world grid.

This tool
---------
Takes one generated sheet per biome family (`assets/tiles/_facade_src/<family>.png`,
a single row of complete buildings drawn on the magenta chroma screen the art
pipeline keys against) and turns it into:

  * `assets/tiles/facades/<family>.png` — an atlas of whole buildings, every one
    snapped to a whole number of 32 px tiles in both axes, so a house can be
    placed on the tile grid instead of floating between pixels;
  * `data/facades.json` — the manifest the game reads: per family, the atlas path
    and one region per building (plus its size in tiles).

Buildings are baked whole rather than assembled from wall/roof tiles: a generated
tileset cannot be trusted to seam (corners, slopes and ridge lines all have to
line up exactly), while a whole building only has to be cut out and scaled. What
the tool guarantees is therefore the part that matters — every building lands on
the grid, in a shared palette, with its baseline (the row of pixels that touches
the ground) preserved so houses sit on the plaza rather than hover over it.

Usage
-----
    python3 tools/make_facade_sheets.py            # every source found
    python3 tools/make_facade_sheets.py meadow     # named families
    python3 tools/make_facade_sheets.py --check    # verify manifest + atlases

Fallback: a biome with no family in the manifest keeps the old polygon houses, so
adding a family is purely additive (settlement.gd handles both).
"""
import json
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from make_idle_frames import key_out  # noqa: E402  (shared chroma key + despill)

SRC_DIR = os.path.join(ROOT, "assets", "tiles", "_facade_src")
OUT_DIR = os.path.join(ROOT, "assets", "tiles", "facades")
MANIFEST = os.path.join(ROOT, "data", "facades.json")

TILE = 32
MIN_TILES = (2, 2)          # a house smaller than this is not a house
MAX_TILES = (4, 3)          # nor is anything the generator drew too large
MEDIAN_TILES = 3            # the family's typical building is this many tiles wide
ATLAS_COLS = 3
COLOURS = 48                # palette size handed to the quantiser
ALPHA_CUTOFF = 120
EXIT_OK, EXIT_PROBLEM = 0, 1


def _runs(occupied, min_size: int = 4) -> list:
    """Group an occupied/empty projection into (start, end) runs of occupied."""
    runs = []
    start = None
    for i, filled in enumerate(occupied):
        if filled and start is None:
            start = i
        elif not filled and start is not None:
            if i - start >= min_size:
                runs.append((start, i))
            start = None
    if start is not None and len(occupied) - start >= min_size:
        runs.append((start, len(occupied)))
    return runs


def split_buildings(img: Image.Image) -> list:
    """Cut the generated row of buildings into per-building boxes."""
    alpha = np.asarray(img.getchannel("A"), dtype=np.uint8) > ALPHA_CUTOFF
    boxes = []
    for y0, y1 in _runs(alpha.any(axis=1).tolist(), min_size=8):
        band = alpha[y0:y1, :]
        for x0, x1 in _runs(band.any(axis=0).tolist(), min_size=8):
            sub = band[:, x0:x1]
            ys, xs = np.nonzero(sub)
            boxes.append((x0 + int(xs.min()), y0 + int(ys.min()),
                          x0 + int(xs.max()) + 1, y0 + int(ys.max()) + 1))
    if not boxes:
        raise ValueError("no buildings found on the chroma screen")
    return boxes


def snap_layout(boxes: list) -> list:
    """Decide every building's size in whole tiles, keeping their proportions.

    The generator returns its own scale (a sheet is whatever size it felt like),
    so absolute pixels mean nothing here: what matters is how big each building
    is *relative to the rest of its family*. The typical building in a family
    becomes MEDIAN_TILES wide and everything else keeps its ratio to that, then
    each size is rounded to whole tiles and clamped into house range. Sizing each
    building independently (round(pixels / 32)) would flatten a village of
    cottages and a hall into the same box.
    """
    widths = [(b[2] - b[0]) for b in boxes]
    median = float(sorted(widths)[len(widths) // 2]) if widths else 1.0
    out = []
    for box in boxes:
        w = float(box[2] - box[0])
        h = float(box[3] - box[1])
        tw = int(round(MEDIAN_TILES * w / max(1.0, median)))
        tw = max(MIN_TILES[0], min(MAX_TILES[0], tw))
        th = int(round(tw * (h / max(1.0, w))))
        th = max(MIN_TILES[1], min(MAX_TILES[1], th))
        out.append((tw, th))
    return out


def cut_building(img: Image.Image, box: tuple, tiles: tuple) -> Image.Image:
    """Crop, rescale to the snapped tile size, and harden the alpha edge."""
    piece = img.crop(box).resize((tiles[0] * TILE, tiles[1] * TILE), Image.LANCZOS)
    arr = np.asarray(piece, dtype=np.uint8).copy()
    arr[..., 3] = np.where(arr[..., 3] > ALPHA_CUTOFF, 255, 0).astype(np.uint8)
    arr[arr[..., 3] == 0] = (0, 0, 0, 0)
    return Image.fromarray(arr, "RGBA")


def quantise(pieces: list) -> list:
    """Give a family one palette, so its houses look like one village.

    Quantising the buildings together (instead of one at a time) is the point:
    the generator returns a slightly different brown for every roof, and a town
    made of twelve slightly different browns reads as noise at 32 px.

    The palette is computed over the *opaque pixels* of the family, then applied
    back through a colour lookup. (Quantising a strip built by pasting the pieces
    side by side looks equivalent but is not: a strip of tall buildings is mostly
    transparent padding, and those padding pixels would eat the palette.)
    """
    arrays = [np.asarray(p, dtype=np.uint8) for p in pieces]
    opaque = np.concatenate([a[a[..., 3] > 0][:, :3] for a in arrays if (a[..., 3] > 0).any()])
    uniq = np.unique(opaque, axis=0)
    mosaic = Image.new("RGB", (len(uniq), 1))
    mosaic.putdata([(int(r), int(g), int(b)) for r, g, b in uniq])
    palette = np.asarray(mosaic.quantize(colors=COLOURS, method=Image.MEDIANCUT)
                         .convert("RGB"), dtype=np.uint8)[0]
    lookup = {tuple(int(c) for c in u): palette[i] for i, u in enumerate(uniq)}

    out = []
    for arr in arrays:
        flat = arr.reshape(-1, 4).copy()
        solid = flat[:, 3] > 0
        colours = flat[solid][:, :3]
        uq, inverse = np.unique(colours, axis=0, return_inverse=True)
        mapped = np.array([lookup.get(tuple(int(c) for c in u),
                                      np.array((0, 0, 0), dtype=np.uint8))
                           for u in uq], dtype=np.uint8)
        flat[np.flatnonzero(solid)[:, None], np.arange(3)] = mapped[inverse]
        out.append(Image.fromarray(flat.reshape(arr.shape), "RGBA"))
    return out


def build_family(name: str, src_path: str, out_path: str) -> dict:
    """One generated sheet -> one atlas + one manifest entry."""
    src = key_out(Image.open(src_path))
    boxes = split_buildings(src)
    pieces = []
    for box, tiles in zip(boxes, snap_layout(boxes)):
        pieces.append((tiles, cut_building(src, box, tiles)))
    pieces.sort(key=lambda t: (t[0][1], t[0][0]))       # short houses first
    pieces = [(t, p) for t, p in zip([t for t, _ in pieces], quantise([p for _, p in pieces]))]

    rows = (len(pieces) + ATLAS_COLS - 1) // ATLAS_COLS
    col_w = [0] * ATLAS_COLS
    row_h = [0] * rows
    for i, (tiles, piece) in enumerate(pieces):
        c, r = i % ATLAS_COLS, i // ATLAS_COLS
        col_w[c] = max(col_w[c], piece.width)
        row_h[r] = max(row_h[r], piece.height)
    col_x = [0]
    for w in col_w[:-1]:
        col_x.append(col_x[-1] + w)
    row_y = [0]
    for h in row_h[:-1]:
        row_y.append(row_y[-1] + h)

    atlas = Image.new("RGBA", (sum(col_w), sum(row_h)), (0, 0, 0, 0))
    houses = []
    for i, (tiles, piece) in enumerate(pieces):
        c, r = i % ATLAS_COLS, i // ATLAS_COLS
        pos = (col_x[c], row_y[r])
        atlas.paste(piece, pos, piece)
        houses.append({
            "region": [pos[0], pos[1], piece.width, piece.height],
            "tiles": [tiles[0], tiles[1]],
        })
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    atlas.save(out_path, optimize=True)
    return {
        "sheet": "res://" + os.path.relpath(out_path, ROOT).replace(os.sep, "/"),
        "houses": houses,
    }


def _sources() -> list:
    if not os.path.isdir(SRC_DIR):
        return []
    return sorted(f[:-4] for f in os.listdir(SRC_DIR) if f.endswith(".png"))


def _load_manifest() -> dict:
    if not os.path.exists(MANIFEST):
        return {}
    with open(MANIFEST, "r", encoding="utf-8") as fh:
        return json.load(fh)


def _save_manifest(families: dict) -> None:
    with open(MANIFEST, "w", encoding="utf-8") as fh:
        json.dump({"families": families}, fh, indent=1, sort_keys=True)
        fh.write("\n")


def check() -> bool:
    """Every family must have grid-aligned houses inside its own atlas."""
    families = _load_manifest().get("families", {})
    problems = []
    if not families:
        problems.append("manifest %s has no families" % os.path.relpath(MANIFEST, ROOT))
    for name, entry in sorted(families.items()):
        sheet = entry.get("sheet", "").replace("res://", "")
        houses = entry.get("houses", [])
        path = os.path.join(ROOT, sheet)
        if not os.path.exists(path):
            problems.append("%s: atlas %s is missing" % (name, sheet))
            continue
        atlas = Image.open(path).convert("RGBA")
        if not houses:
            problems.append("%s: no houses" % name)
        for i, h in enumerate(houses):
            x, y, w, hh = h["region"]
            if w % TILE or hh % TILE:
                problems.append("%s/house %d: region is not on the 32 px grid" % (name, i))
            if x + w > atlas.width or y + hh > atlas.height:
                problems.append("%s/house %d: region spills out of the atlas" % (name, i))
                continue
            cell = atlas.crop((x, y, x + w, y + hh))
            if cell.getbbox() is None:
                problems.append("%s/house %d: region is empty" % (name, i))
            elif (h.get("tiles") or [0, 0]) != [w // TILE, hh // TILE]:
                problems.append("%s/house %d: tile size disagrees with the region" % (name, i))
    for p in problems:
        print("  PROBLEM: %s" % p)
    if problems:
        print("FACADE ART: FAILED (%d problems)" % len(problems))
        return False
    houses = sum(len(e.get("houses", [])) for e in families.values())
    print("FACADE ART: PASS (%d families, %d buildings)" % (len(families), houses))
    return True


def main() -> None:
    if "--check" in sys.argv[1:]:
        sys.exit(EXIT_OK if check() else EXIT_PROBLEM)
    want = [a for a in sys.argv[1:] if not a.startswith("-")] or _sources()
    if not want:
        sys.exit("no facade sources in %s" % os.path.relpath(SRC_DIR, ROOT))
    families = _load_manifest().get("families", {})
    failed = []
    for name in want:
        src_path = os.path.join(SRC_DIR, name + ".png")
        if not os.path.exists(src_path):
            failed.append("%s: no source at %s" % (name, src_path))
            continue
        entry = build_family(name, src_path, os.path.join(OUT_DIR, name + ".png"))
        families[name] = entry
        sizes = ", ".join("%dx%d" % tuple(h["tiles"]) for h in entry["houses"])
        print("  %-10s %d buildings (%s)" % (name, len(entry["houses"]), sizes))
    _save_manifest(families)
    if failed:
        for f in failed:
            print("  PROBLEM: %s" % f)
        sys.exit(EXIT_PROBLEM)


if __name__ == "__main__":
    main()
