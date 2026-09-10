#!/usr/bin/env python3
"""Authors the open world as Tiled JSON maps, one per chunk (Phase 2).

World grid: chunks x -2..4, y -3..1 (35 chunks, 1024 px each, 32 px tiles).
Biomes: Verdant Meadows (south-west), Ashen Barrens (south-east),
Frosthollow Peaks (north). A mountain wall along the north edge of the
southern row has two gates; a hidden grove (secret) is sealed by a gate
opened from a lever far away in the Barrens.

Output: world/chunks/chunk_X_Y.json (canonical Tiled JSON). Then run
tools/tiled_to_godot.py to compile .tscn scenes.
"""
import json
import math
import os
import random

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "world", "chunks")
TILE = 32
GRID = 32
CHUNK = 1024

X_RANGE = range(-2, 5)
Y_RANGE = range(-3, 2)

# gid helper: biome*8 + col + 1 ; cols: 0/1 ground, 2 path, 3 hazard,
# 4 obstacle, 5 wall, 6 deco, 7 shore.
def gid(biome, col):
    return biome * 8 + col + 1


def biome_of(cx, cy):
    if cy <= -1:
        return 2
    if cx >= 2:
        return 1
    return 0


# ---- world-space feature definitions -------------------------------------

CLEARINGS = [
    (900, 300, 270),      # camp plaza
    (700, 330, 170),      # spawn
    (1700, 600, 170),     # wp_meadow
    (2900, 400, 170),     # wp_barrens
    (544, -260, 170),     # wp_frost_gate
    (2400, -1100, 180),   # wp_frost_deep
    (2700, -1500, 430),   # boss arena
    (2250, 780, 70),      # ashen lever
]

WORLD_OBJECTS = [
    dict(name="chest_meadow", type="chest", x=300, y=860, gold=50, item="health_potion"),
    dict(name="chest_barrens", type="chest", x=3500, y=760, gold=80, item="mana_potion"),
    dict(name="chest_frost", type="chest", x=1300, y=-2600, gold=120, item="health_potion"),
    dict(name="chest_secret", type="chest", x=-1600, y=500, gold=300, item="traveler_ring"),

    dict(name="sign_welcome", type="sign", x=760, y=440, title="Hazelwood Village",
         text="Welcome, traveler. The campfire to the east is safe ground. "
              "Speak with Elder Rowan if you seek purpose."),
    dict(name="sign_frost_pass", type="sign", x=544, y=130, title="Frosthollow Pass",
         text="The cold takes the careless. Whatever you hear in the white, "
              "do not answer it."),
    dict(name="sign_barrens", type="sign", x=2560, y=130, title="Ashen Barrens",
         text="Scorched by the Warden's breath. Only ember-touched things "
              "still live out east."),
    dict(name="sign_boss", type="sign", x=2560, y=-1230, title="Scorched Warning",
         text="The Ember Warden nests beyond this ridge. No torch needed — "
              "the mountain itself burns."),
    dict(name="sign_secret_hint", type="sign", x=380, y=560, title="Old Sign",
         text="West of the village the trees close into a door of stone. "
              "They say a lever in the ash lands remembers how to open it."),

    dict(name="lever_ashen", type="lever", x=2250, y=780, gate="secret_grove"),
    dict(name="secret_grove", type="gate", x=-1600, y=704),

    dict(name="wp_meadow", type="waypoint", x=1700, y=600, label="East Meadow Fire"),
    dict(name="wp_barrens", type="waypoint", x=2900, y=400, label="Ashen Camp"),
    dict(name="wp_frost_gate", type="waypoint", x=544, y=-260, label="Frosthollow Gate"),
    dict(name="wp_frost_deep", type="waypoint", x=2400, y=-1100, label="Ember Approach"),
]

# Paths: list of (x0, y0, x1, y1, half_width) in world px.
PATHS = [
    (430, 300, 3100, 364, 0),        # village -> barrens gate (rect stamp)
    (500, -260, 588, 300, 0),        # meadow gate road north-south
    (500, -960, 588, -260, 0),       # frost descent
    (500, -960, 2480, -880, 0),      # frost traverse
    (2360, -1180, 2448, -880, 0),    # approach to Ember Warden
]

POND = (1500, 820, 130, 92)          # meadow pond (ellipse)
FROST_LAKE = (1000, -2450, 170, 120)

MEADOW_GATE_X = (480, 608)           # gap in the mountain wall
BARRENS_GATE_X = (2464, 2592)


def in_clearing(x, y):
    return any((x - cx) ** 2 + (y - cy) ** 2 < r * r for cx, cy, r in CLEARINGS)


def in_path(x, y):
    for x0, y0, x1, y1, _ in PATHS:
        if min(x0, x1) - 20 <= x <= max(x0, x1) + 20 and min(y0, y1) - 20 <= y <= max(y0, y1) + 20:
            return True
    return False


def in_ellipse(x, y, e):
    cx, cy, rx, ry = e
    return ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0


def build_chunk(cx, cy):
    biome = biome_of(cx, cy)
    rng = random.Random((cx * 73856093) ^ (cy * 19349663))
    ox, oy = cx * CHUNK, cy * CHUNK
    grid = [0] * (GRID * GRID)
    solids_stamp = set()

    def set_tile(tx, ty, g):
        if 0 <= tx < GRID and 0 <= ty < GRID:
            grid[ty * GRID + tx] = g

    def world(tx, ty):
        return ox + tx * TILE + TILE / 2, oy + ty * TILE + TILE / 2

    # 1) scattered ground texture + deco
    for ty in range(GRID):
        for tx in range(GRID):
            wx, wy = world(tx, ty)
            if in_ellipse(wx, wy, POND) or in_ellipse(wx, wy, FROST_LAKE):
                continue
            r = rng.random()
            if r < 0.30:
                set_tile(tx, ty, gid(biome, 0))
            elif r < 0.55:
                set_tile(tx, ty, gid(biome, 1))
            elif r < 0.60:
                set_tile(tx, ty, gid(biome, 6))

    # 2) biome features (obstacles / hazards)
    if biome == 0:  # meadow tree clusters
        for _ in range(rng.randint(4, 7)):
            tx, ty = rng.randint(1, GRID - 3), rng.randint(1, GRID - 3)
            for dx, dy in [(0, 0), (1, 0), (0, 1), (1, 1), (2, 0), (0, 2)]:
                if rng.random() < 0.75:
                    wx, wy = world(tx + dx, ty + dy)
                    if in_clearing(wx, wy) or in_path(wx, wy):
                        continue
                    set_tile(tx + dx, ty + dy, gid(0, 4))
                    solids_stamp.add((tx + dx, ty + dy))
        # pond
        for ty in range(GRID):
            for tx in range(GRID):
                if in_ellipse(*world(tx, ty), e=POND):
                    set_tile(tx, ty, gid(0, 3))
                    solids_stamp.add((tx, ty))
    elif biome == 1:  # barrens rocks + lava pools
        for _ in range(rng.randint(3, 6)):
            tx, ty = rng.randint(1, GRID - 2), rng.randint(1, GRID - 2)
            wx, wy = world(tx, ty)
            if in_clearing(wx, wy) or in_path(wx, wy):
                continue
            set_tile(tx, ty, gid(1, 4))
            solids_stamp.add((tx, ty))
            if rng.random() < 0.5:
                set_tile(tx + 1, ty, gid(1, 4))
                solids_stamp.add((tx + 1, ty))
        for _ in range(rng.randint(1, 2)):
            ltx, lty = rng.randint(4, GRID - 6), rng.randint(4, GRID - 6)
            for dy in range(3):
                for dx in range(3):
                    if rng.random() < 0.8:
                        wx, wy = world(ltx + dx, lty + dy)
                        if in_clearing(wx, wy) or in_path(wx, wy):
                            continue
                        set_tile(ltx + dx, lty + dy, gid(1, 3))
                        solids_stamp.add((ltx + dx, lty + dy))
    else:  # frosthollow pines + ice lake
        for _ in range(rng.randint(5, 9)):
            tx, ty = rng.randint(1, GRID - 2), rng.randint(1, GRID - 2)
            wx, wy = world(tx, ty)
            if in_clearing(wx, wy) or in_path(wx, wy):
                continue
            set_tile(tx, ty, gid(2, 4))
            solids_stamp.add((tx, ty))
        for ty in range(GRID):
            for tx in range(GRID):
                if in_ellipse(*world(tx, ty), e=FROST_LAKE):
                    set_tile(tx, ty, gid(2, 3))
                    solids_stamp.add((tx, ty))

    # 3) secret grove ring (chunk -2,0): dense tree wall around (-1600,500)
    if (cx, cy) == (-2, 0):
        gcx, gcy, grad = -1600, 500, 230
        for ty in range(GRID):
            for tx in range(GRID):
                wx, wy = world(tx, ty)
                d = math.hypot(wx - gcx, wy - gcy)
                gap = abs(wx - gcx) < 40 and wy > gcy + grad - 90  # south entrance
                if grad - 30 <= d <= grad + 45 and not gap:
                    set_tile(tx, ty, gid(0, 4))
                    solids_stamp.add((tx, ty))

    # 4) mountain wall along bottom rows of chunk row y = -1
    if cy == -1:
        for tx in range(GRID):
            wx = ox + tx * TILE + TILE / 2
            in_gate = (MEADOW_GATE_X[0] <= wx <= MEADOW_GATE_X[1]) or \
                      (BARRENS_GATE_X[0] <= wx <= BARRENS_GATE_X[1])
            if not in_gate:
                for ty in (GRID - 2, GRID - 1):
                    set_tile(tx, ty, gid(2, 5))
                    solids_stamp.add((tx, ty))

    # 5) paths (carve solids, stamp path tiles)
    for x0, y0, x1, y1, _ in PATHS:
        for ty in range(GRID):
            for tx in range(GRID):
                wx, wy = world(tx, ty)
                if (min(x0, x1) <= wx <= max(x0, x1)) and (min(y0, y1) <= wy <= max(y0, y1)):
                    set_tile(tx, ty, gid(biome, 2))
                    solids_stamp.discard((tx, ty))

    # 6) clearings: remove solids inside them (keep ground/path)
    for ty in range(GRID):
        for tx in range(GRID):
            if (tx, ty) in solids_stamp:
                wx, wy = world(tx, ty)
                if in_clearing(wx, wy):
                    grid[ty * GRID + tx] = gid(biome, 0)
                    solids_stamp.discard((tx, ty))

    # 7) objects for this chunk (world -> chunk-local coords)
    objects = []
    oid = 1
    for obj in WORLD_OBJECTS:
        lx, ly = obj["x"] - ox, obj["y"] - oy
        if 0 <= lx < CHUNK and 0 <= ly < CHUNK:
            o = {
                "id": oid, "name": obj["name"], "type": obj["type"],
                "x": lx, "y": ly, "width": 0, "height": 0, "visible": True,
                "rotation": 0,
            }
            props = []
            for key in ("gold", "item", "title", "text", "gate", "label"):
                if key in obj:
                    t = "int" if isinstance(obj[key], int) else "string"
                    props.append({"name": key, "type": t, "value": obj[key]})
            if props:
                o["properties"] = props
            objects.append(o)
            oid += 1

    # 8) enemy spawners (skip village, boss arena & immediate gate areas)
    spawner_biomes = {0: (["grunt", "emberling"], 1.0),
                      1: (["scout", "grunt"], 1.6),
                      2: (["shaman", "scout"], 2.4)}
    if (cx, cy) not in ((0, 0), (2, -2)):
        table, power = spawner_biomes[biome]
        for _ in range(rng.randint(1, 2)):
            placed = False
            for _try in range(10):
                lx = rng.randint(96, CHUNK - 96)
                ly = rng.randint(96, CHUNK - 96)
                wx, wy = ox + lx, oy + ly
                if in_clearing(wx, wy) or in_path(wx, wy):
                    continue
                tx, ty = lx // TILE, ly // TILE
                if (tx, ty) in solids_stamp or grid[ty * GRID + tx] and \
                        ((grid[ty * GRID + tx] - 1) % 8) in (3, 4, 5):
                    continue
                objects.append({
                    "id": oid, "name": f"spawn_{len(objects)}", "type": "spawner",
                    "x": lx, "y": ly, "width": 0, "height": 0, "visible": True,
                    "rotation": 0,
                    "properties": [
                        {"name": "archetype", "type": "string",
                         "value": rng.choice(table)},
                        {"name": "count", "type": "int", "value": rng.randint(1, 2)},
                        {"name": "power", "type": "float", "value": power},
                    ],
                })
                oid += 1
                placed = True
                break

    return {
        "type": "map", "version": "1.10", "tiledversion": "1.11.2",
        "orientation": "orthogonal", "renderorder": "right-down",
        "width": GRID, "height": GRID, "tilewidth": TILE, "tileheight": TILE,
        "infinite": False, "nextlayerid": 3, "nextobjectid": oid,
        "properties": [{"name": "biome", "type": "int", "value": biome}],
        "tilesets": [{
            "firstgid": 1, "name": "biome_atlas", "columns": 8,
            "tilewidth": TILE, "tileheight": TILE, "tilecount": 24,
            "image": "../../assets/tiles/atlas.png",
            "imagewidth": 256, "imageheight": 96,
        }],
        "layers": [
            {"id": 1, "name": "terrain", "type": "tilelayer",
             "width": GRID, "height": GRID, "x": 0, "y": 0,
             "visible": True, "opacity": 1, "data": grid},
            {"id": 2, "name": "objects", "type": "objectgroup",
             "visible": True, "opacity": 1, "draworder": "topdown",
             "x": 0, "y": 0, "objects": objects},
        ],
    }


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    n = 0
    for cy in Y_RANGE:
        for cx in X_RANGE:
            m = build_chunk(cx, cy)
            path = os.path.join(OUT_DIR, f"chunk_{cx}_{cy}.json")
            with open(path, "w") as f:
                json.dump(m, f, separators=(",", ":"))
            n += 1
    print(f"wrote {n} Tiled chunk maps to {OUT_DIR}")


if __name__ == "__main__":
    main()
