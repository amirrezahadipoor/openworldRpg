#!/usr/bin/env python3
"""Procedural app icon set (pure stdlib, deterministic) — Phase 1.

Renders the game emblem (campfire over crossed logs on a night-sky slate)
into:
  assets/icons/icon_{48,72,96,144,192}.png   legacy launcher icons
  assets/icons/icon_512.png                  store/release banner icon
  assets/icons/adaptive_fg_432.png           adaptive-icon foreground
  assets/icons/adaptive_bg_432.png           adaptive-icon background

All drawing happens on a 432x432 master canvas (xxxhdpi adaptive size) and
is box-sampled down for the smaller densities, keeping edges crisp.
"""
import math
import os
import struct
import zlib

OUT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "assets", "icons"))
S = 432  # master canvas


def write_png(path, w, h, rows):
    """rows: list of byte rows (RGBA)."""
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


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = [[(0, 0, 0, 0)] * w for _ in range(h)]

    def put(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y][x] = c

    def blend(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            dst = self.px[y][x]
            sa = c[3] / 255.0
            da = dst[3] / 255.0
            oa = sa + da * (1 - sa)
            if oa <= 0:
                return
            out = []
            for i in range(3):
                out.append(int((c[i] * sa + dst[i] * da * (1 - sa)) / oa))
            out.append(int(oa * 255))
            self.px[y][x] = tuple(out)

    def fill_rect(self, x0, y0, x1, y1, c, rounded=0):
        for y in range(int(y0), int(y1)):
            for x in range(int(x0), int(x1)):
                if rounded and self._corner_dist(x, y, x0, y0, x1, y1, rounded) is None:
                    continue
                self.blend(x, y, c)

    def _corner_dist(self, x, y, x0, y0, x1, y1, r):
        cx = min(max(x, x0 + r), x1 - r)
        cy = min(max(y, y0 + r), y1 - r)
        dx, dy = x - cx, y - cy
        if (x < x0 + r or x > x1 - r) and (y < y0 + r or y > y1 - r):
            return math.hypot(dx, dy) <= r
        return 1

    def circle(self, cx, cy, r, c):
        for y in range(int(cy - r), int(cy + r) + 1):
            for x in range(int(cx - r), int(cx + r) + 1):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                    self.blend(x, y, c)

    def disc_gradient(self, cx, cy, r, c0, c1):
        for y in range(int(cy - r), int(cy + r) + 1):
            for x in range(int(cx - r), int(cx + r) + 1):
                d = math.hypot(x - cx, y - cy)
                if d <= r:
                    t = d / r
                    c = tuple(int(c0[i] + (c1[i] - c0[i]) * t) for i in range(4))
                    self.blend(x, y, c)

    def poly(self, pts, c):
        ys = [p[1] for p in pts]
        for y in range(int(min(ys)), int(max(ys)) + 1):
            xs = []
            for i in range(len(pts)):
                x0, y0 = pts[i]
                x1, y1 = pts[(i + 1) % len(pts)]
                if (y0 <= y < y1) or (y1 <= y < y0):
                    t = (y - y0) / (y1 - y0) if y1 != y0 else 0
                    xs.append(x0 + t * (x1 - x0))
            xs.sort()
            for k in range(0, len(xs) - 1, 2):
                for x in range(int(xs[k]), int(xs[k + 1]) + 1):
                    self.blend(x, y, c)

    def thick_line(self, x0, y0, x1, y1, w, c):
        dx, dy = x1 - x0, y1 - y0
        n = max(int(math.hypot(dx, dy)), 1)
        for i in range(n + 1):
            t = i / n
            self.circle(x0 + dx * t, y0 + dy * t, w / 2.0, c)

    def downscale(self, size):
        """Integer box sampling to size x size."""
        assert self.w % size == 0 and self.h % size == 0
        k = self.w // size
        out = Canvas(size, size)
        for y in range(size):
            for x in range(size):
                rs = gs = bs = as_ = 0
                for dy in range(k):
                    for dx in range(k):
                        r, g, b, a = self.px[y * k + dy][x * k + dx]
                        rs += r * a
                        gs += g * a
                        bs += b * a
                        as_ += a
                if as_ > 0:
                    out.px[y][x] = (rs // as_, gs // as_, bs // as_, as_ // (k * k))
        return out

    def rows(self):
        return [bytes(v for px in row for v in px) for row in self.px]


def background():
    """Night-slate rounded square with vignette + faint stars."""
    cv = Canvas(S, S)
    for y in range(S):
        t = y / S
        base = tuple(int(a + (b - a) * t) for a, b in zip((30, 38, 54), (12, 15, 22)))
        for x in range(S):
            # vignette
            dx, dy = (x - S / 2) / (S / 2), (y - S / 2) / (S / 2)
            v = 1.0 - 0.35 * min(1.0, math.hypot(dx, dy) ** 2)
            cv.put(x, y, (int(base[0] * v), int(base[1] * v), int(base[2] * v), 255))
    # stars (deterministic)
    stars = [(63, 74), (150, 40), (300, 58), (388, 96), (96, 150), (356, 170),
             (48, 300), (402, 286), (196, 36), (258, 92)]
    for sx, sy in stars:
        cv.blend(sx, sy, (220, 228, 255, 190))
    return cv


def flame(cv, cx, cy, s):
    """Layered flame silhouette: deep orange -> yellow core."""
    def flame_pts(w, h, tip_sway):
        # teardrop flame outline built from mirrored points
        pts = []
        steps = 22
        for i in range(steps + 1):
            t = i / steps
            yy = cy + h * 0.42 - h * t
            half = w * 0.5 * math.sin(math.pi * min(1.0, t * 1.12)) * (1.0 - 0.4 * t)
            pts.append((cx - half + tip_sway * t * t, yy))
        for i in range(steps, -1, -1):
            t = i / steps
            yy = cy + h * 0.42 - h * t
            half = w * 0.5 * math.sin(math.pi * min(1.0, t * 1.12)) * (1.0 - 0.4 * t)
            pts.append((cx + half + tip_sway * t * t, yy))
        return pts

    outer = [(232, 92, 24, 255), (255, 140, 30, 255)]
    pts = flame_pts(s, s * 1.28, s * 0.06)
    ys = sorted(p[1] for p in pts)
    for y in range(int(ys[0]), int(ys[-1]) + 1):
        t = (y - ys[0]) / max(1, (ys[-1] - ys[0]))
        c = tuple(int(outer[1][i] + (outer[0][i] - outer[1][i]) * t) for i in range(3)) + (255,)
        # scanline fill at y
        xs = []
        for i in range(len(pts)):
            x0, y0 = pts[i]
            x1, y1 = pts[(i + 1) % len(pts)]
            if (y0 <= y < y1) or (y1 <= y < y0):
                tt = (y - y0) / (y1 - y0) if y1 != y0 else 0
                xs.append(x0 + tt * (x1 - x0))
        xs.sort()
        for k in range(0, len(xs) - 1, 2):
            for x in range(int(xs[k]), int(xs[k + 1]) + 1):
                cv.blend(x, y, c)
    # inner core (yellow), smaller
    core = [(255, 214, 64, 255), (255, 244, 170, 255)]
    pts2 = flame_pts(s * 0.52, s * 0.8, s * 0.04)
    ys2 = sorted(p[1] for p in pts2)
    for y in range(int(ys2[0]), int(ys2[-1]) + 1):
        t = (y - ys2[0]) / max(1, (ys2[-1] - ys2[0]))
        c = tuple(int(core[1][i] + (core[0][i] - core[1][i]) * t) for i in range(3)) + (255,)
        xs = []
        for i in range(len(pts2)):
            x0, y0 = pts2[i]
            x1, y1 = pts2[(i + 1) % len(pts2)]
            if (y0 <= y < y1) or (y1 <= y < y0):
                tt = (y - y0) / (y1 - y0) if y1 != y0 else 0
                xs.append(x0 + tt * (x1 - x0))
        xs.sort()
        for k in range(0, len(xs) - 1, 2):
            for x in range(int(xs[k]), int(xs[k + 1]) + 1):
                cv.blend(x, y, c)


def foreground():
    """Campfire emblem sized for the adaptive-icon safe zone."""
    cv = Canvas(S, S)
    cx, cy = S // 2, S // 2 + 20
    cv.disc_gradient(cx, cy - 10, 170, (255, 150, 40, 70), (255, 150, 40, 0))
    # crossed logs
    log = (92, 62, 40, 255)
    log_hi = (122, 84, 54, 255)
    cv.thick_line(cx - 95, cy + 96, cx + 95, cy + 52, 30, log)
    cv.thick_line(cx + 95, cy + 96, cx - 95, cy + 52, 30, log)
    cv.thick_line(cx - 80, cy + 88, cx + 80, cy + 58, 8, log_hi)
    cv.thick_line(cx + 80, cy + 88, cx - 80, cy + 58, 8, log_hi)
    flame(cv, cx, cy - 26, 132)
    # sparks
    for sx, sy, r in [(cx - 96, cy - 118, 4), (cx + 84, cy - 140, 5), (cx + 30, cy - 180, 3)]:
        cv.circle(sx, sy, r, (255, 200, 90, 230))
    return cv


def main():
    os.makedirs(OUT, exist_ok=True)
    bg = background()
    fg = foreground()

    # Adaptive icon layers (full-bleed background, safe-zone foreground).
    write_png(os.path.join(OUT, "adaptive_bg_432.png"), S, S, bg.rows())
    write_png(os.path.join(OUT, "adaptive_fg_432.png"), S, S, fg.rows())

    # Legacy icons: background + emblem composited, rounded corners baked in.
    master = Canvas(S, S)
    for y in range(S):
        for x in range(S):
            master.px[y][x] = bg.px[y][x]
    # scale fg to 74% and center
    inset = int(S * 0.13)
    for y in range(inset, S - inset):
        for x in range(inset, S - inset):
            sy = int((y - inset) * S / (S - 2 * inset))
            sx = int((x - inset) * S / (S - 2 * inset))
            master.blend(x, y, fg.px[sy][sx])
    # rounded-corner mask (transparent outside)
    r = 78
    for y in range(S):
        for x in range(S):
            cx = min(max(x, r), S - 1 - r)
            cy = min(max(y, r), S - 1 - r)
            if (x < r or x > S - 1 - r) and (y < r or y > S - 1 - r):
                if math.hypot(x - cx, y - cy) > r:
                    master.px[y][x] = (0, 0, 0, 0)

    write_png(os.path.join(OUT, "icon_512.png"), 512, 512,
              master.downscale(512).rows() if S % 512 == 0 else _nearest(master, 512).rows())
    for size in (192, 144, 96, 72, 48):
        cv = master.downscale(size) if S % size == 0 else _nearest(master, size)
        write_png(os.path.join(OUT, "icon_%d.png" % size), size, size, cv.rows())

    for f in sorted(os.listdir(OUT)):
        print(f, os.path.getsize(os.path.join(OUT, f)), "bytes")


def _nearest(src, size):
    out = Canvas(size, size)
    for y in range(size):
        for x in range(size):
            out.px[y][x] = src.px[int(y * src.h / size)][int(x * src.w / size)]
    return out


if __name__ == "__main__":
    main()
