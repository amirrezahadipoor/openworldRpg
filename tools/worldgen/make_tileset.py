#!/usr/bin/env python3
"""Procedurally renders the world tile atlas (pure stdlib, deterministic).

Layout: 8 columns x 3 biome rows, 32 px tiles (256 x 96 PNG).
Columns:
  0 ground_a   1 ground_b   2 path       3 hazard (solid)
  4 obstacle (solid)        5 wall/cliff (solid)   6 deco (walkable)
  7 shore/edge
Rows (biomes): 0 Verdant Meadows, 1 Ashen Barrens, 2 Frosthollow Peaks.
GID convention shared with the converter + ChunkStreamer:
  gid = biome * 8 + col + 1   (0 = empty -> renderer base color)
"""
import struct
import zlib
import os
import random

TILE = 32
COLS = 8
ROWS = 3
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "tiles", "atlas.png")

# Palette per biome: [ground, ground_dark, path, hazard, obstacle, wall, deco]
PALETTES = [
    # Verdant Meadows
    dict(ground=(74, 117, 66), dark=(63, 102, 56), path=(146, 122, 84),
         hazard=(58, 108, 138), obstacle=(39, 74, 38), wall=(88, 84, 74),
         deco=(214, 190, 92)),
    # Ashen Barrens
    dict(ground=(118, 96, 74), dark=(102, 82, 62), path=(84, 66, 52),
         hazard=(196, 92, 34), obstacle=(72, 60, 52), wall=(58, 50, 46),
         deco=(168, 148, 120)),
    # Frosthollow Peaks
    dict(ground=(206, 214, 224), dark=(184, 194, 208), path=(150, 158, 172),
         hazard=(128, 168, 198), obstacle=(52, 74, 84), wall=(96, 104, 118),
         deco=(232, 240, 248)),
]


def write_png(path, w, h, rows):
    """rows: list of byte rows (RGB)."""
    def chunk(tag, data):
        out = struct.pack(">I", len(data)) + tag + data
        out += struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        return out

    raw = b"".join(b"\x00" + bytes(r) for r in rows)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)


class Tile:
    def __init__(self, rng):
        self.px = [[(0, 0, 0)] * TILE for _ in range(TILE)]
        self.rng = rng

    def fill(self, c):
        for y in range(TILE):
            for x in range(TILE):
                self.px[y][x] = c

    def put(self, x, y, c):
        if 0 <= x < TILE and 0 <= y < TILE:
            self.px[y][x] = c

    def vary(self, base, amt=14):
        """Fill with per-pixel jitter."""
        for y in range(TILE):
            for x in range(TILE):
                d = self.rng.randint(-amt, amt)
                self.px[y][x] = tuple(max(0, min(255, ch + d)) for ch in base)

    def speckle(self, color, n, lo=0, hi=TILE):
        for _ in range(n):
            self.put(self.rng.randint(lo, hi - 1), self.rng.randint(lo, hi - 1), color)

    def circle(self, cx, cy, r, color):
        for y in range(TILE):
            for x in range(TILE):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                    self.px[y][x] = color

    def hline(self, y, color, x0=0, x1=TILE):
        for x in range(x0, x1):
            self.put(x, y, color)


def ground_tile(p, rng, alt):
    t = Tile(rng)
    t.vary(p["ground"] if not alt else p["dark"], 10)
    t.speckle(p["dark"], 14)
    t.speckle(tuple(min(255, c + 26) for c in p["ground"]), 8)
    return t


def path_tile(p, rng):
    t = Tile(rng)
    t.vary(p["path"], 12)
    t.speckle(tuple(max(0, c - 22) for c in p["path"]), 12)
    return t


def hazard_tile(p, rng, biome):
    t = Tile(rng)
    t.fill(p["hazard"])
    if biome == 0:  # water: wave crests
        for k in range(4):
            y = 4 + k * 8
            for x in range(0, TILE, 8):
                t.hline(y, tuple(min(255, c + 30) for c in p["hazard"]), x + 1, x + 5)
    elif biome == 1:  # lava: bright cracks
        for _ in range(10):
            x, y = rng.randint(2, 28), rng.randint(2, 28)
            for k in range(rng.randint(3, 6)):
                t.put(x + k, y, (255, 200, 90))
                t.put(x + k, y + 1, (232, 130, 40))
    else:  # ice: sheen streaks
        for _ in range(6):
            x, y = rng.randint(2, 24), rng.randint(2, 26)
            for k in range(6):
                t.put(x + k, y - k // 2, (235, 246, 255))
    return t


def obstacle_tile(p, rng, biome):
    """Solid obstacle: tree canopy / boulder / snowed pine."""
    t = Tile(rng)
    t.vary(p["ground"], 8)
    if biome == 0:  # tree canopy
        t.circle(16, 15, 13, p["obstacle"])
        t.circle(13, 12, 6, tuple(min(255, c + 18) for c in p["obstacle"]))
        t.circle(20, 19, 5, tuple(max(0, c - 12) for c in p["obstacle"]))
    elif biome == 1:  # boulder
        t.circle(16, 17, 12, p["obstacle"])
        t.circle(12, 13, 5, tuple(min(255, c + 20) for c in p["obstacle"]))
        t.circle(21, 20, 4, tuple(max(0, c - 14) for c in p["obstacle"]))
    else:  # snowed pine
        t.circle(16, 16, 12, p["obstacle"])
        t.circle(16, 12, 8, (224, 232, 240))
        t.circle(16, 20, 7, tuple(max(0, c - 10) for c in p["obstacle"]))
    return t


def wall_tile(p, rng):
    t = Tile(rng)
    t.vary(p["wall"], 6)
    for y in (0, 10, 21, 31):
        t.hline(min(y, TILE - 1), tuple(max(0, c - 26) for c in p["wall"]))
    for _ in range(8):
        x, y = rng.randint(1, 30), rng.randint(1, 30)
        t.put(x, y, tuple(max(0, c - 34) for c in p["wall"]))
    return t


def deco_tile(p, rng, biome):
    t = Tile(rng)
    t.vary(p["ground"], 10)
    if biome == 0:  # flowers
        for _ in range(5):
            x, y = rng.randint(3, 28), rng.randint(3, 28)
            t.put(x, y, p["deco"])
            t.put(x + 1, y, (226, 226, 230))
            t.put(x, y + 1, (60, 96, 50))
    elif biome == 1:  # bones / ash
        for _ in range(4):
            x, y = rng.randint(4, 26), rng.randint(4, 26)
            for k in range(4):
                t.put(x + k, y + (k % 2), p["deco"])
    else:  # snow sparkle
        for _ in range(10):
            t.put(rng.randint(2, 29), rng.randint(2, 29), p["deco"])
    return t


def shore_tile(p, rng):
    t = Tile(rng)
    t.vary(p["path"], 8)
    t.hline(28, p["hazard"])
    t.hline(29, p["hazard"])
    t.hline(30, tuple(min(255, c + 20) for c in p["hazard"]), 0, 20)
    t.hline(31, p["hazard"], 4, 30)
    return t


def main():
    rng = random.Random(1234)
    canvas = [[(0, 0, 0)] * (COLS * TILE) for _ in range(ROWS * TILE)]
    builders = [ground_tile, ground_tile, path_tile, hazard_tile,
                obstacle_tile, wall_tile, deco_tile, shore_tile]
    for biome, p in enumerate(PALETTES):
        for col in range(COLS):
            if col in (0, 1):
                t = builders[col](p, rng, col == 1)
            elif col in (4, 6):
                t = builders[col](p, rng, biome)
            elif col == 3:
                t = builders[col](p, rng, biome)
            else:
                t = builders[col](p, rng)
            for y in range(TILE):
                for x in range(TILE):
                    canvas[biome * TILE + y][col * TILE + x] = t.px[y][x]
    rows = [bytes(v for px in row for v in px) for row in canvas]
    out = os.path.normpath(OUT)
    write_png(out, COLS * TILE, ROWS * TILE, rows)
    print("wrote", out, os.path.getsize(out), "bytes")


if __name__ == "__main__":
    main()
