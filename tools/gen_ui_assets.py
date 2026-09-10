#!/usr/bin/env python3
"""Procedural 9-patch style UI frames (pure stdlib) — Phase 10 polish.

Outputs 28x28 pixel-art frames used by ui/theme.tres as StyleBoxTexture:
  assets/ui/panel9.png   dark parchment-slate with aged-gold trim
  assets/ui/button9.png  raised slate button with pale trim
"""
import os
import struct
import zlib

OUT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "assets", "ui"))
S = 28


def write_png(path, w, h, rows):
    def chunk(tag, data):
        out = struct.pack(">I", len(data)) + tag + data
        out += struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        return out

    raw = b"".join(b"\x00" + bytes(r) for r in rows)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def frame(border, border_hi, corner, fill, fill_a, hi_line):
    px = [[(0, 0, 0, 0)] * S for _ in range(S)]
    for y in range(S):
        for x in range(S):
            c = (fill[0], fill[1], fill[2], fill_a)
            edge = min(x, y, S - 1 - x, S - 1 - y)
            if edge == 0:
                c = (0, 0, 0, 0)  # rounded pixel corner
            elif edge == 1:
                c = border
            elif edge == 2:
                c = border_hi
            elif y == 3:
                c = (hi_line[0], hi_line[1], hi_line[2], min(255, fill_a + 40))
            corner_d = 0
            for cx, cy in [(2, 2), (S - 3, 2), (2, S - 3), (S - 3, S - 3)]:
                if abs(x - cx) <= 1 and abs(y - cy) <= 1:
                    corner_d = max(corner_d, 2 - max(abs(x - cx), abs(y - cy)))
            if corner_d == 2:
                c = corner
            elif corner_d == 1:
                c = tuple(min(255, v + 24) for v in border_hi[:3]) + (255,)
            px[y][x] = c
    return [bytes(v for p in row for v in p) for row in px]


def main():
    os.makedirs(OUT, exist_ok=True)
    write_png(os.path.join(OUT, "panel9.png"), S, S, frame(
        border=(196, 158, 74, 255),
        border_hi=(120, 96, 44, 255),
        corner=(240, 210, 130, 255),
        fill=(14, 17, 26, 238),
        fill_a=238,
        hi_line=(46, 54, 74),
    ))
    write_png(os.path.join(OUT, "button9.png"), S, S, frame(
        border=(126, 140, 168, 255),
        border_hi=(70, 80, 100, 255),
        corner=(200, 214, 240, 255),
        fill=(38, 46, 64, 250),
        fill_a=250,
        hi_line=(72, 84, 110),
    ))
    for f in sorted(os.listdir(OUT)):
        print(f, os.path.getsize(os.path.join(OUT, f)), "bytes")


if __name__ == "__main__":
    main()
