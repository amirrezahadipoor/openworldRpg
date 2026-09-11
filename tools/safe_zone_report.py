#!/usr/bin/env python3
"""How much of the map is safe? Measure it, don't guess it.

`data/settlements.json` declares a `safe_radius` per settlement and a
`safe_zones` list for standalone bubbles (the starting camp). Nobody had ever
added those up, so "there are too many safe zones" was an opinion. This is the
number.

Bubbles may overlap (they are subtracted as a union, not summed). The world
rectangle is the bounding box of the shipped chunks in `world/chunks/`.

Usage:
    python3 tools/safe_zone_report.py            # report
    python3 tools/safe_zone_report.py --check    # exit 1 if over the ceiling
"""

import glob
import json
import math
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
CEILING = 0.15          # agreed ceiling: under 15% of the map is no-combat ground
CHUNK = 1024
SAMPLE_STEP = 24        # px between Monte-Carlo-ish samples on a grid


def load(path):
    with open(path) as f:
        return json.load(f)


def chunk_bounds():
    xs, ys = [], []
    for path in glob.glob(os.path.join(ROOT, "world", "chunks", "chunk_*.json")):
        m = re.search(r"chunk_(-?\d+)_(-?\d+)\.json", os.path.basename(path))
        if m:
            xs.append(int(m.group(1)))
            ys.append(int(m.group(2)))
    if not xs:
        return None
    return (min(xs) * CHUNK, min(ys) * CHUNK,
            (max(xs) + 1) * CHUNK, (max(ys) + 1) * CHUNK)


def zones():
    doc = load(os.path.join(ROOT, "data", "settlements.json"))
    out = []
    for sid, s in doc.get("settlements", {}).items():
        px, py = s.get("position", [0, 0])
        out.append({
            "id": sid,
            "kind": "settlement",
            "tier": s.get("tier", "?"),
            "name": s.get("name", sid),
            "x": float(px), "y": float(py),
            "radius": float(s.get("safe_radius", 300.0)),
            "visual": float(s.get("radius", 0.0)),
        })
    for z in doc.get("safe_zones", []):
        px, py = z.get("position", [0, 0])
        out.append({
            "id": z.get("id", "zone"),
            "kind": "zone",
            "tier": "-",
            "name": z.get("name", z.get("id", "zone")),
            "x": float(px), "y": float(py),
            "radius": float(z.get("radius", 300.0)),
            "visual": 0.0,
        })
    return out


def area_of(zone):
    return math.pi * zone["radius"] ** 2


def covered(bounds, zs):
    """Grid-sample the world rectangle and count points inside any bubble."""
    x0, y0, x1, y1 = bounds
    inside = 0
    total = 0
    x = x0 + SAMPLE_STEP * 0.5
    while x < x1:
        y = y0 + SAMPLE_STEP * 0.5
        while y < y1:
            total += 1
            for z in zs:
                if (x - z["x"]) ** 2 + (y - z["y"]) ** 2 <= z["radius"] ** 2:
                    inside += 1
                    break
            y += SAMPLE_STEP
        x += SAMPLE_STEP
    return inside, total


def main():
    check = "--check" in sys.argv
    bounds = chunk_bounds()
    if bounds is None:
        print("no chunks found under world/chunks/")
        return 1
    zs = zones()
    w = bounds[2] - bounds[0]
    h = bounds[3] - bounds[1]
    world_area = float(w * h)
    inside, total = covered(bounds, zs)
    frac = inside / max(1, total)
    union_area = frac * world_area

    print("map            %d x %d px  (%.1f M px^2)" % (w, h, world_area / 1e6))
    print("safe bubbles   %d" % len(zs))
    print("")
    print("  %-12s %-10s %7s %8s %8s" % ("id", "kind", "radius", "visual", "area %"))
    for z in sorted(zs, key=lambda q: -area_of(q)):
        share = 100.0 * area_of(z) / world_area
        print("  %-12s %-10s %7.0f %8.0f %7.2f%%" % (
            z["id"], z["kind"], z["radius"], z["visual"], share))
    print("")
    print("safe area      %.3f M px^2 of %.3f M px^2 = %.2f%% of the map"
          % (union_area / 1e6, world_area / 1e6, frac * 100.0))
    print("ceiling        %.0f%%%s" % (CEILING * 100.0,
                                       "  -> OK" if frac <= CEILING else "  -> OVER"))

    tight = [z["id"] for z in zs if z["kind"] == "settlement"
             and z["radius"] > z["visual"] + 90.0]
    print("margin check   settlements whose bubble is more than 90 px wider than "
          "their own radius: %s" % (tight if tight else "none"))

    if check and frac > CEILING:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
