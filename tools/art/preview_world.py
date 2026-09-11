#!/usr/bin/env python3
"""Renders real world chunks with the built atlas, exactly as the game would.

Mirrors the GID decoding in scripts/world/chunk_renderer.gd (ATLAS_COLS):

    col = (gid - 1) % 11 ;  row = (gid - 1) / 11

so the output is a faithful preview of what the player sees, without needing a
GPU. Used to validate tile choices during the art pass.

Usage:
    python3 tools/art/preview_world.py                     # all 3 biomes
    python3 tools/art/preview_world.py chunk_0_0          # one chunk
    python3 tools/art/preview_world.py chunk_0_0 --zoom 3 --out /tmp/x.png
"""
from __future__ import annotations

import argparse
import json
import os
import sys

from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
ATLAS = os.path.join(ROOT, "assets", "tiles", "atlas.png")
CHUNKS = os.path.join(ROOT, "world", "chunks")

TILE = 32
BIOME_NAMES = ["Verdant Meadows", "Ashen Barrens", "Frosthollow Peaks"]
BASE_COLORS = [(61, 107, 64), (140, 122, 94), (84, 97, 120)]  # mirrors chunk_renderer base_color


def render_chunk(name: str, atlas: Image.Image, draw_objects: bool = True) -> Image.Image:
    path = os.path.join(CHUNKS, f"{name}.json")
    with open(path) as f:
        m = json.load(f)

    gw, gh = m["width"], m["height"]
    tsize = m["tilewidth"]
    biome = 0
    for p in m.get("properties", []):
        if p.get("name") == "biome":
            biome = int(p["value"])

    img = Image.new("RGB", (gw * tsize, gh * tsize), BASE_COLORS[biome])
    layer = next(l for l in m["layers"] if l["name"] == "terrain")
    data = layer["data"]
    assert len(data) == gw * gh

    for i, gid in enumerate(data):
        if gid <= 0:
            continue
        col = (gid - 1) % 11
        row = (gid - 1) // 11
        cell = atlas.crop((col * TILE, row * TILE, col * TILE + TILE, row * TILE + TILE))
        img.paste(cell, ((i % gw) * tsize, (i // gw) * tsize))

    if draw_objects:
        from PIL import ImageDraw
        d = ImageDraw.Draw(img, "RGBA")
        for layer in m["layers"]:
            if layer.get("type") != "objectgroup":
                continue
            for o in layer["objects"]:
                x, y = int(o["x"]), int(o["y"])
                t = o.get("type", "")
                color = {
                    "chest": (255, 215, 0, 220), "sign": (245, 245, 245, 220),
                    "waypoint": (255, 120, 40, 230), "lever": (120, 220, 255, 230),
                    "gate": (200, 120, 255, 230), "spawner": (255, 70, 70, 200),
                }.get(t, (255, 0, 255, 200))
                d.ellipse([x - 6, y - 6, x + 6, y + 6], fill=color, outline=(0, 0, 0, 255))
                d.text((x + 8, y - 6), t, fill=(255, 255, 255, 255))
    return img


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("chunks", nargs="*", default=[])
    ap.add_argument("--zoom", type=int, default=2)
    ap.add_argument("--out", default="/tmp/world_preview.png")
    ap.add_argument("--no-objects", action="store_true")
    args = ap.parse_args()

    atlas = Image.open(ATLAS).convert("RGBA")

    # default: one representative chunk per biome
    names = args.chunks or ["chunk_0_0", "chunk_2_0", "chunk_0_-2"]
    tiles = [render_chunk(n, atlas, not args.no_objects) for n in names]

    z = args.zoom
    gap = 16
    w = sum(t.width for t in tiles) * z + gap * (len(tiles) + 1)
    h = max(t.height for t in tiles) * z + gap * 2 + 24
    out = Image.new("RGB", (w, h), (18, 18, 22))
    from PIL import ImageDraw
    d = ImageDraw.Draw(out)
    x = gap
    for n, t in zip(names, tiles):
        out.paste(t.resize((t.width * z, t.height * z), Image.NEAREST), (x, gap + 24))
        biome = 0
        with open(os.path.join(CHUNKS, f"{n}.json")) as f:
            for p in json.load(f).get("properties", []):
                if p.get("name") == "biome":
                    biome = int(p["value"])
        d.text((x, gap + 6), f"{n}  ·  {BIOME_NAMES[biome]}", fill=(255, 230, 120))
        x += t.width * z + gap

    out.save(args.out)
    print(f"wrote {args.out} ({out.width}x{out.height})  chunks: {', '.join(names)}")


if __name__ == "__main__":
    main()
