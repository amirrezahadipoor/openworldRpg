#!/usr/bin/env python3
"""Builds the world tile atlas (assets/tiles/atlas.png) from real LPC source art.

Replaces the former procedural placeholder atlas (tools/worldgen/make_tileset.py).
The GID contract is UNCHANGED, so the renderer, the Tiled JSON chunks and the
chunk streamer all keep working without modification:

    layout : 11 columns x 3 biome rows, 32 px tiles  ->  352 x 96 px
    columns: 0 ground_a  1 ground_b  2 path  3 hazard
             4 obstacle (solid)  5 wall/cliff (solid)  6 deco  7 shore
             8-10 decor scatter variants (meadow/barrens/frost each get three)
    rows   : 0 Verdant Meadows  1 Ashen Barrens  2 Frosthollow Peaks
    gid    : biome * 11 + col + 1     (0 = empty -> renderer base colour)

Every output tile is fully opaque: sprites and transition edges are composited
onto the biome's ground fill, so a tile can never reveal the renderer's base
colour through its corners.

Source art (all native 32 px, LPC style — matches the 64 px LPC characters
already shipped in assets/lpc/):

  * "LPC terrain extension"  (CC-BY-SA 3.0 / GPL)  assets/source/lpc_terrain/
  * "[LPC] Conifers"         (CC-BY-SA 3.0 / GPL)  assets/source/lpc_conifers.png
  * "[LPC] Forest tiles"     (CC-BY-SA 3.0 / GPL)  assets/source/lpc_forest_tiles.png
  * "[LPC] Trees"            (CC-BY-SA 3.0 / GPL)  assets/source/lpc_trees_dead.png

See CREDITS.md for full attribution. Recolour/tint composites below are
derivative works and stay under the same CC-BY-SA 3.0 terms.

Run:  python3 tools/art/build_atlas.py
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SRC = os.path.join(ROOT, "assets", "source")
OUT = os.path.join(ROOT, "assets", "tiles", "atlas.png")

TILE = 32
COLS, ROWS = 11, 3   # 0-7 as before, 8-10 are the decor scatter variants

_sheets: dict[str, Image.Image] = {}


def sheet(name: str) -> Image.Image:
    """Load (and cache) a source sheet as RGBA."""
    if name not in _sheets:
        path = os.path.join(SRC, name)
        if not os.path.exists(path):
            sys.exit(f"missing source sheet: {path}\nrun: bash tools/art/vendor_sources.sh")
        _sheets[name] = Image.open(path).convert("RGBA")
    return _sheets[name]


def tile(name: str, row: int, col: int) -> Image.Image:
    return sheet(name).crop((col * TILE, row * TILE, col * TILE + TILE, row * TILE + TILE))


def fill(name: str) -> Image.Image:
    """The solid interior tile of an LPC terrain autotile sheet.

    Verified across every sheet in assets/source/lpc_terrain: (5,2) and (3,1)
    are the only fully opaque (seamless-fill) cells.
    """
    return tile(name, 5, 2)


def over(base: Image.Image, sprite: Image.Image, tint=None) -> Image.Image:
    """Composite `sprite` onto opaque `base`. Result is always fully opaque."""
    out = base.copy()
    if tint is not None:
        arr = np.array(sprite).astype(np.int16)
        arr[..., 0] = np.clip(arr[..., 0] * tint[0] + tint[3], 0, 255)
        arr[..., 1] = np.clip(arr[..., 1] * tint[1] + tint[4], 0, 255)
        arr[..., 2] = np.clip(arr[..., 2] * tint[2] + tint[5], 0, 255)
        sprite = Image.fromarray(arr.astype(np.uint8), "RGBA")
    out.alpha_composite(sprite)
    return out


def tint_flat(img: Image.Image, mult=(1.0, 1.0, 1.0)) -> Image.Image:
    """Palette-shift an opaque tile — used for subtle biome variants."""
    arr = np.array(img).astype(np.float32)
    arr[..., 0] *= mult[0]
    arr[..., 1] *= mult[1]
    arr[..., 2] *= mult[2]
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def recolor(img: Image.Image, black=(0, 0, 0), white=(255, 255, 255), mix: float = 1.0) -> Image.Image:
    """Remap a tile's luminance onto a new colour ramp, preserving alpha.

    This is how one authored rock/soil texture is repurposed per biome without
    hand-painting: e.g. meadow dirt -> dark volcanic ash (Barrens) or
    blue-grey packed snow (Frosthollow). `mix` blends back toward the original.
    """
    rgb = img.convert("RGB")
    lum = np.array(rgb.convert("L")).astype(np.float32) / 255.0
    out = np.empty((*lum.shape, 3), dtype=np.float32)
    for ch in range(3):
        out[..., ch] = black[ch] + (white[ch] - black[ch]) * lum
    if mix < 1.0:
        out = out * mix + np.array(rgb).astype(np.float32) * (1.0 - mix)
    rgba = np.dstack([np.clip(out, 0, 255), np.array(img)[..., 3]]).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")


def find_transition(name: str, top_kind: str, bottom_kind: str, base: Image.Image) -> Image.Image:
    """Recover an LPC terrain transition tile (e.g. grass -> water) by scoring
    the average colour of each tile's top and bottom halves, then composite it
    over `base` so the result is opaque."""
    kinds = {
        # (kind) -> (channel-dominance signature, target brightness)
        "grass": ("g", 30),
        "water": ("b", 40),
        "lava": ("r", 60),
        "sand": ("r", 15),
        "snow": ("n", 235),
    }

    def score(kind: str, r: float, g: float, b: float) -> float:
        dom, target = kinds[kind]
        if dom == "g":
            return abs((g - max(r, b)) - target)
        if dom == "b":
            return abs((b - max(r, g)) - target)
        if dom == "r":
            return abs((r - max(g, b)) - target)
        return abs(min(r, g, b) - target) * 3  # 'n' = near-neutral bright

    img = sheet(name)
    arr = np.array(img).astype(np.float32)
    cols, rows = img.size[0] // TILE, img.size[1] // TILE
    best, best_score = None, float("inf")
    for r in range(rows):
        for c in range(cols):
            blk = arr[r * TILE:(r + 1) * TILE, c * TILE:(c + 1) * TILE]
            if (blk[..., 3] > 8).mean() < 0.55:      # need a tile with real coverage
                continue
            top = blk[: TILE // 2].reshape(-1, 4)[:, :3].mean(axis=0)
            bot = blk[TILE // 2:].reshape(-1, 4)[:, :3].mean(axis=0)
            s = score(top_kind, *top) + score(bottom_kind, *bot)
            if s < best_score:
                best_score, best = s, (r, c)
    if best is None:
        return base.copy()
    return over(base, tile(name, *best))


def darkest_fill(name: str) -> Image.Image:
    """The darkest *fully opaque* tile of a sheet — used as the rock/cliff face.

    Chosen by measurement rather than a hard-coded index so it survives any
    upstream re-export. Recoloured per biome via `recolor`.
    """
    img = sheet(name)
    arr = np.array(img)
    cols, rows = img.size[0] // TILE, img.size[1] // TILE
    best, best_lum = None, 1e9
    for r in range(rows):
        for c in range(cols):
            blk = arr[r * TILE:(r + 1) * TILE, c * TILE:(c + 1) * TILE]
            if blk[..., 3].min() != 255:          # must be a seamless fill
                continue
            lum = blk[..., :3].mean()
            if lum < best_lum:
                best_lum, best = lum, (r, c)
    assert best is not None, f"no opaque fill tile found in {name}"
    return tile(name, *best)


def canopy(name: str, row0: int, col0: int, span: int = 2) -> Image.Image:
    """Dense forest texture: average a seamless block of canopy tiles down to
    one 32 px tile, then re-sharpen toward the source palette."""
    patch = tile(name, row0, col0)
    box = sheet(name).crop((col0 * TILE, row0 * TILE, (col0 + span) * TILE, (row0 + span) * TILE))
    small = box.resize((TILE, TILE), Image.LANCZOS)
    return Image.blend(patch, small, 0.45)


def build_recipes():
    # ---- terrain fills (all fully opaque) ----
    grass = fill("lpc_terrain/grass.png")
    dirt = fill("lpc_terrain/dirt.png")
    water = fill("lpc_terrain/water.png")
    snow = fill("lpc_terrain/snow.png")
    ice = fill("lpc_terrain/ice.png")
    lava = fill("lpc_terrain/lava.png")
    lavarock = fill("lpc_terrain/lavarock.png")
    sand = fill("lpc_terrain/sand.png")

    # ---- sprites (verified single-tile, self-contained) ----
    # Obstacles are single self-contained tree sprites. Dense canopy masks were
    # tried first and rejected: in a real render a repeated 32 px canopy reads as
    # a dark rectangle, not a forest. At the world's ~1.3% obstacle density a
    # tree sprite reads as scattered woodland, which is what we want.
    tree_green = tile("lpc_conifers.png", 2, 6)        # small green pine
    tree_snow = tile("lpc_conifers.png", 9, 6)         # its snow-laden counterpart
    dead_thicket = tile("lpc_trees_dead.png", 2, 0)    # bare dead scrub
    twigs = tile("lpc_trees_dead.png", 2, 0)         # bare twigs, reads as dead scrub
    rock_face = darkest_fill("lpc_forest_tiles.png") # rock/chasm face, recoloured per biome
    flowers = tile("lpc_forest_tiles.png", 0, 2)     # grass tile with scattered flowers
    rocks_small = tile("lpc_forest_tiles.png", 1, 11)  # small boulder cluster
    boulder = tile("lpc_forest_tiles.png", 1, 10)      # large boulder

    # Ashen Barrens: ash-grey volcanic soil, not the raw (salmon) LPC redsand.
    ash = recolor(dirt, black=(26, 24, 25), white=(126, 118, 112))
    ash_path = recolor(dirt, black=(22, 21, 22), white=(108, 101, 96))
    ash_rock = recolor(rock_face, black=(14, 13, 14), white=(104, 100, 98))
    # Frosthollow: blue-grey rock + packed-snow track, never meadow green.
    frost_rock = recolor(rock_face, black=(38, 46, 60), white=(198, 208, 224))
    frost_path = recolor(dirt, black=(120, 130, 146), white=(232, 238, 246))

    # ground_b is a SUBTLE tone variant in every biome. Feature sprites (flowers,
    # scrub, boulders) live in the rare `deco` column instead: a sprite stamped at
    # 30% density reads as a repeating icon grid, not as terrain.
    return [
        # ---------------- Biome 0: Verdant Meadows ----------------
        [
            grass,                                                        # 0 ground_a
            tint_flat(grass, (0.93, 1.00, 0.94)),                         # 1 ground_b (subtle tone)
            recolor(dirt, black=(78, 66, 50), white=(160, 141, 116)),   # 2 path (dirt trail)
            water,                                                        # 3 hazard (pond)
            over(grass, tree_green),                                      # 4 obstacle (solid)
            rock_face,                                                    # 5 wall/cliff (solid)
            flowers,                                                      # 6 deco (flower meadow)
            find_transition("lpc_terrain/water.png", "grass", "water", grass),  # 7 shore
            # 8-10: the scatter. One deco column at 4% read as a repeating icon,
            # and the biomes were measured at 0.15% decor overall - flat ground as
            # far as the eye could see (v3 audit §2). Three variants per biome,
            # scattered independently in the generator, read as terrain again.
            flowers,                                                      # 8 deco: flowers
            over(grass, rocks_small),                                     # 9 deco: pebbles
            over(grass, tint_flat(flowers, (1.12, 1.04, 0.86))),          # 10 deco: dry flowers
        ],
        # ---------------- Biome 1: Ashen Barrens ----------------
        [
            ash,                                                          # 0 ground_a
            recolor(dirt, black=(30, 28, 29), white=(140, 131, 124)),     # 1 ground_b (ash tone)
            ash_path,                                                     # 2 path (ash track)
            lava,                                                         # 3 hazard (lava)
            over(ash, recolor(dead_thicket, black=(38, 33, 30), white=(146, 136, 128))),  # 4 obstacle (solid)
            ash_rock,                                                     # 5 wall/cliff (basalt, solid)
            over(ash, twigs),                                             # 6 deco (dead scrub)
            find_transition("lpc_terrain/lava.png", "sand", "lava", ash), # 7 shore (lava rim)
            over(ash, twigs),                                             # 8 deco: dead scrub
            over(ash, recolor(rocks_small, black=(24, 22, 22), white=(132, 124, 118))),  # 9 deco: ash stones
            over(ash, recolor(dead_thicket, black=(30, 27, 26), white=(112, 104, 98))),  # 10 deco: charred stump
        ],
        # ---------------- Biome 2: Frosthollow Peaks ----------------
        [
            snow,                                                         # 0 ground_a
            tint_flat(snow, (0.96, 0.98, 1.03)),                          # 1 ground_b (subtle drift)
            frost_path,                                                   # 2 path (packed snow)
            ice,                                                          # 3 hazard (frozen lake)
            over(snow, tree_snow),                                        # 4 obstacle (solid)
            frost_rock,                                                   # 5 cliff (solid)
            over(snow, recolor(boulder, black=(60, 68, 82), white=(214, 224, 238))),  # 6 deco (boulder)
            find_transition("lpc_terrain/snowwater.png", "snow", "water", snow),  # 7 shore
            over(snow, recolor(rocks_small, black=(70, 80, 96), white=(226, 234, 246))),  # 8 deco: stones
            over(snow, recolor(twigs, black=(58, 66, 80), white=(206, 216, 232))),        # 9 deco: dead brush
            over(snow, recolor(boulder, black=(64, 74, 90), white=(238, 244, 252))),      # 10 deco: boulder
        ],
    ]


def main() -> None:
    recipes = build_recipes()
    canvas = Image.new("RGBA", (COLS * TILE, ROWS * TILE), (0, 0, 0, 255))
    for biome, row_tiles in enumerate(recipes):
        assert len(row_tiles) == COLS, f"biome {biome} has {len(row_tiles)} tiles, expected {COLS}"
        for col, t in enumerate(row_tiles):
            if t.size != (TILE, TILE):
                t = t.resize((TILE, TILE), Image.NEAREST)
            canvas.paste(t, (col * TILE, biome * TILE))

    # sanity: no tile may be transparent (it would reveal the renderer base colour)
    alpha = np.array(canvas)[..., 3]
    if alpha.min() != 255:
        bad = int((alpha < 255).sum())
        sys.exit(f"atlas has {bad} non-opaque pixels — every tile must be opaque")

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    canvas.save(OUT, optimize=True)
    print(f"wrote {OUT} ({canvas.size[0]}x{canvas.size[1]}, {os.path.getsize(OUT)} bytes)")

    # Standalone 32x32 tiles for code that needs a single tiling texture.
    # (An AtlasTexture + texture_repeat repeats the WHOLE atlas, not one cell —
    # verified the hard way — so these are emitted separately.)
    props_dir = os.path.join(os.path.dirname(OUT), "props")
    os.makedirs(props_dir, exist_ok=True)
    for name, (col, row) in {"camp_ground": (2, 0)}.items():
        cell = canvas.crop((col * TILE, row * TILE, col * TILE + TILE, row * TILE + TILE))
        path = os.path.join(props_dir, name + ".png")
        cell.save(path, optimize=True)
        print(f"wrote {path} ({os.path.getsize(path)} bytes)")


if __name__ == "__main__":
    main()
