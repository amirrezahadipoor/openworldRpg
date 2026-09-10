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


def frost_line_f(cx):
    """Unrounded frost line, in chunk units (for the per-tile meander)."""
    return -1.0 + math.sin(cx * 0.9 + 0.4) * 1.2


def barrens_line_f(cy):
    """Unrounded barrens line, in chunk units."""
    return 2.0 + math.sin(cy * 1.1 - 0.7) * 1.2


def tile_biome(cx, cy, wx, wy):
    """Per-tile biome: the chunk-level border, meandered at tile scale.

    Biome *ownership* is decided per chunk (that is what the game reads for
    music, ambience and spawn tables), but painting the ground from the chunk
    decision alone gave every seam a 32-tile stair-step edge. Here the same
    border is evaluated with a smooth noise offset of up to ~0.4 chunk in both
    axes, so the ground changes over a handful of tiles and reads as a coast.
    """
    jx = (value_noise(wx, wy, 640.0, seed=97) - 0.5) * 0.8
    jy = (value_noise(wx, wy, 640.0, seed=61) - 0.5) * 0.8
    if cy + jy <= frost_line_f(cx + jx):
        return 2
    if cx + jx >= barrens_line_f(cy + jy):
        return 1
    return 0


def neighbour_tile_biome(cx, cy, wx, wy, base):
    """The differing biome at an adjacent tile, or -1 (for the blend band)."""
    for dx, dy in ((44.0, 0.0), (-44.0, 0.0), (0.0, 44.0), (0.0, -44.0)):
        other = tile_biome(cx, cy, wx + dx, wy + dy)
        if other != base:
            return other
    return -1


def _wobble(v, phase, amp=1.2, freq=0.9):
    """Smooth, deterministic border offset.

    The world used to be three rectangles: `cy <= -1` was winter, `cx >= 2` was
    desert, everything else was meadow, with borders a player could walk along in
    a straight line. The lines now breathe with a slow sinusoid, so biomes
    interlock without the border breaking up into single-chunk islands.
    """
    return int(round(math.sin(v * freq + phase) * amp))


def frost_line(cx):
    """Chunk row where winter starts, drifting around y = -1."""
    return -1 + _wobble(cx, 0.4)


def barrens_line(cy):
    """Chunk column where the barrens start, drifting around x = 2."""
    return 2 + _wobble(cy, -0.7, freq=1.1)


def biome_of(cx, cy):
    if cy <= frost_line(cx):
        return 2
    if cx >= barrens_line(cy):
        return 1
    return 0


def edge_biome(cx, cy):
    """The neighbouring biome a chunk sits against, or None when it is interior.

    Edge chunks get a scatter of the other side's ground tile, which is what
    turns a border into a transition.
    """
    here = biome_of(cx, cy)
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        if biome_of(cx + dx, cy + dy) != here:
            return biome_of(cx + dx, cy + dy)
    return None


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


# ---- deterministic world-space value noise ---------------------------------
# Sampled from WORLD coordinates (not chunk-local) so terrain patches continue
# seamlessly across chunk borders instead of showing a hard seam at every
# 1024 px boundary.

def _hash2(ix, iy, seed):
    n = (ix * 374761393 + iy * 668265263 + seed * 1442695040888963407) & 0xFFFFFFFFFFFF
    n = (n ^ (n >> 13)) * 1274126177 & 0xFFFFFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFFFF) / float(0xFFFFFF)


def value_noise(x, y, scale, seed=1337):
    """Smooth bilinear value noise in [0, 1], continuous over world space."""
    fx, fy = x / scale, y / scale
    ix, iy = math.floor(fx), math.floor(fy)
    tx, ty = fx - ix, fy - iy
    sx = tx * tx * (3 - 2 * tx)
    sy = ty * ty * (3 - 2 * ty)
    n00 = _hash2(ix, iy, seed)
    n10 = _hash2(ix + 1, iy, seed)
    n01 = _hash2(ix, iy + 1, seed)
    n11 = _hash2(ix + 1, iy + 1, seed)
    a = n00 + (n10 - n00) * sx
    b = n01 + (n11 - n01) * sx
    return a + (b - a) * sy


def ground_gid(biome, wx, wy, edge=None):
    """Clustered ground variation.

    ground_a and ground_b are subtle tone variants, so broad noise patches read
    as natural terrain rather than as a checkerboard. The `deco` sprite is kept
    rare (~4%) so it stays a detail instead of a repeating icon grid.
    """
    broad = value_noise(wx, wy, 300.0, seed=11)
    detail = value_noise(wx, wy, 110.0, seed=23)
    v = broad * 0.75 + detail * 0.25
    # Transition band: along a border, patches of the neighbour's ground break up
    # the straight line between two biomes.
    if edge is not None and value_noise(wx, wy, 220.0, seed=53) > 0.72:
        return gid(edge, 0)
    if v < 0.52:
        return gid(biome, 0)
    if value_noise(wx, wy, 58.0, seed=37) > 0.96:
        return gid(biome, 6)          # rare deco fleck
    return gid(biome, 1)


def path_distance(wx, wy):
    """Distance in world px from (wx, wy) to the nearest road centreline."""
    best = 1e9
    for x0, y0, x1, y1, _ in PATHS:
        dx, dy = x1 - x0, y1 - y0
        seg2 = dx * dx + dy * dy
        if seg2 == 0:
            t = 0.0
        else:
            t = max(0.0, min(1.0, ((wx - x0) * dx + (wy - y0) * dy) / seg2))
        px, py = x0 + t * dx, y0 + t * dy
        best = min(best, math.hypot(wx - px, wy - py))
    return best


# --- micro-locations ---------------------------------------------------------
# Between the villages, the dungeons and the boss gates there was a great deal
# of ground with nothing to arrive at. These are the small named places: a well,
# a gallows oak, a ferryman's rest, a slag chapel, two vaults that need a lever.
# Each stamps its own tile feature (so it reads from a distance) and carries a
# sign with its own text.
#   kind: ring | well | ruins | walls | trees | pit
MICRO_LOCATIONS = [
    (360, 900, "well", "Hollow Well",
     "The well is dry and someone has bricked it over from the inside. The bricks are newer than the village."),
    (-120, 1560, "trees", "The Gallows Oak",
     "There is a rope still over the branch, cut rather than untied. Nobody in Millhaven claims the tree."),
    (1240, 1700, "pit", "Ferryman's Rest",
     "A punt with no river under it, hauled this far inland and left. The oars are worn smooth."),
    (1840, 1180, "ruins", "Watchtower Foot",
     "Only the foot survives, and the foot is one course of stone taller than the wall it watched."),
    (2160, 260, "ring", "The Standing Stones",
     "Nine stones in a ring, the tenth face-down in the grass. The lever beside the fallen one is not old."),
    (3320, 1420, "ruins", "Slag Chapel",
     "A chapel built out of furnace slag by people who had nothing else. The door is ajar and the hinges are warm."),
    (4520, 620, "pit", "Cinder Well",
     "A shaft that breathes. Something down there has been keeping a fire going for a long time."),
    (2980, -180, "pit", "Two Roads Stone",
     "Where the mill road meets the ash road. Every traveller scratches a mark; the stone is nearly illegible."),
    (900, -1420, "trees", "Rime Orchard",
     "Fruit trees that froze standing and never fell. The apples are still on them, grey and hard."),
    (1720, -2380, "walls", "The Long Ladder",
     "A frozen scaffold up the cliff face, one rung short of the top. Rungs have been added from below, recently."),
    (-880, -2760, "ruins", "Hermit's Chimney",
     "One chimney standing in the snow with no house left around it, and smoke coming out of it."),
    (-1560, -1200, "pit", "The Quiet Mile",
     "A mile of road where nothing has been allowed to grow. The silence has an edge to it, like a held breath."),
    (3900, -2500, "walls", "Frostbound Gate",
     "A gate in a wall that goes nowhere, closed from this side, with the keyhole on the far side."),
    (-420, 480, "pit", "The Last Milepost",
     "The last stone marker before the valley ends. Someone has carved their own distance, wrong by a wide margin."),
]

# Two small places hide a cache behind a lever (lever -> gate -> chest).
MICRO_VAULTS = {
    "The Standing Stones": dict(gate="vault_stones", lever=(2280, 320), chest=(2090, 190),
                                gold=340, item="traveler_ring"),
    "Hermit's Chimney": dict(gate="vault_chimney", lever=(-960, -2680), chest=(-800, -2768),
                             gold=420, item="frostbind_ring"),
}



def _paint_bank(grid, grid_n, world, biome, solids_stamp, ellipse):
    """Paint a shore tile on the ground directly above a body of water.

    The shore tile is drawn with its water band along the bottom edge, so placing
    it on the tile *above* water puts the two edges together.
    """
    for ty in range(grid_n - 1):
        for tx in range(grid_n):
            wx, wy = world(tx, ty)
            if in_ellipse(wx, wy, ellipse):
                continue
            x2, y2 = world(tx, ty + 1)
            if not in_ellipse(x2, y2, ellipse):
                continue
            grid[ty * grid_n + tx] = gid(biome, 7)
            solids_stamp.discard((tx, ty))



# --- roster-backed spawn tables --------------------------------------------
# Read once: data/enemies.json is the roster's own source of truth for which
# monsters belong to which biome and level band.
_ROSTER_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "..", "..", "data", "enemies.json")


def roster_spawn_table(biome):
    """Archetypes the roster says live in `biome`, weakest first.

    Falls back to the old two-name lists only if the roster cannot be read, so a
    generator run never produces an empty world.
    """
    try:
        with open(_ROSTER_PATH) as f:
            spawns = json.load(f)["spawns"][biome]["archetypes"]
        if spawns:
            return list(spawns)
    except (OSError, KeyError, ValueError):
        pass
    return {"meadow": ["grunt", "emberling"],
            "barrens": ["scout", "grunt"],
            "frost": ["shaman", "scout"]}.get(biome, ["grunt"])


def build_chunk(cx, cy):
    biome = biome_of(cx, cy)          # chunk ownership: music, ambience, spawn tables
    edge = edge_biome(cx, cy)         # kept for the chunk-level fallbacks below
    rng = random.Random((cx * 73856093) ^ (cy * 19349663))
    ox, oy = cx * CHUNK, cy * CHUNK
    grid = [0] * (GRID * GRID)
    solids_stamp = set()

    def set_tile(tx, ty, g):
        if 0 <= tx < GRID and 0 <= ty < GRID:
            grid[ty * GRID + tx] = g

    def world(tx, ty):
        return ox + tx * TILE + TILE / 2, oy + ty * TILE + TILE / 2

    # 1) clustered ground texture + deco flecks (noise-driven, seamless).
    #    NOTE: the discarded rng.random() call keeps the RNG stream byte-identical
    #    to the previous per-tile-random generator, so every downstream feature
    #    (tree clusters, boulders, lava pools, enemy spawners) lands on exactly
    #    the same tile as before. This change is purely cosmetic.
    for ty in range(GRID):
        for tx in range(GRID):
            wx, wy = world(tx, ty)
            if in_ellipse(wx, wy, POND) or in_ellipse(wx, wy, FROST_LAKE):
                continue
            rng.random()
            tb = tile_biome(cx, cy, wx, wy)
            nb = neighbour_tile_biome(cx, cy, wx, wy, tb)
            set_tile(tx, ty, ground_gid(tb, wx, wy, None if nb < 0 else nb))

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
        # ...and its bank: the atlas has had a shore column since the tileset was
        # written and never used it, so every pond ended in a hard edge.
        _paint_bank(grid, GRID, world, 0, solids_stamp, POND)
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
        _paint_bank(grid, GRID, world, 2, solids_stamp, FROST_LAKE)

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

    # 5) roads. The carve region is deliberately the FULL path bounding box —
    #    identical to the original generator, so traversal is unchanged — while
    #    the painted track is narrower with a noise-perturbed edge, so roads
    #    read as roads instead of as a paved rectangle.
    for ty in range(GRID):
        for tx in range(GRID):
            wx, wy = world(tx, ty)
            for x0, y0, x1, y1, _ in PATHS:
                if (min(x0, x1) <= wx <= max(x0, x1)) and (min(y0, y1) <= wy <= max(y0, y1)):
                    solids_stamp.discard((tx, ty))
                    break
    for ty in range(GRID):
        for tx in range(GRID):
            wx, wy = world(tx, ty)
            wobble = (value_noise(wx, wy, 70.0, seed=71) - 0.5) * 15.0
            if path_distance(wx, wy) + wobble < 30.0:
                set_tile(tx, ty, gid(tile_biome(cx, cy, wx, wy), 2))

    # 6) clearings: remove solids and keep the plaza floor open (roads survive)
    for ty in range(GRID):
        for tx in range(GRID):
            wx, wy = world(tx, ty)
            if not in_clearing(wx, wy):
                continue
            solids_stamp.discard((tx, ty))
            g = grid[ty * GRID + tx]
            if g and ((g - 1) % 8) in (3, 4, 5, 6):
                grid[ty * GRID + tx] = gid(tile_biome(cx, cy, wx, wy), 0)

    

    # 6b) micro-locations: stamp the tile feature, add the sign (and any vault)
    micro_objects = []
    for mx, my, kind, mname, mtext in MICRO_LOCATIONS:
        if not (ox - 192 <= mx < ox + CHUNK + 192 and oy - 192 <= my < oy + CHUNK + 192):
            continue
        lcx, lcy = int((mx - ox) // TILE), int((my - oy) // TILE)

        def put(tx, ty, col, solid=True):
            if 0 <= tx < GRID and 0 <= ty < GRID:
                set_tile(tx, ty, gid(tile_biome(cx, cy, *world(tx, ty)), col))
                if solid:
                    solids_stamp.add((tx, ty))

        if kind == "ring":
            for k in range(9):
                a = math.tau * k / 9.0
                put(lcx + int(round(math.cos(a) * 4)), lcy + int(round(math.sin(a) * 4)), 4)
        elif kind == "well":
            for k in range(8):
                a = math.tau * k / 8.0
                put(lcx + int(round(math.cos(a) * 2)), lcy + int(round(math.sin(a) * 2)), 4)
            put(lcx, lcy, 3, solid=False)
        elif kind == "ruins":
            for k in range(7):
                put(lcx - 3 + k, lcy - 3, 5)
                if k % 2 == 0:
                    put(lcx - 3 + k, lcy + 3, 5)
        elif kind == "walls":
            for k in range(5):
                for tx, ty in ((lcx - 3 + k, lcy - 3), (lcx - 3 + k, lcy + 3),
                               (lcx - 3, lcy - 3 + k), (lcx + 3, lcy - 3 + k)):
                    if k in (0, 4) or k % 2 == 0:
                        put(tx, ty, 5)
        elif kind == "trees":
            for k in range(6):
                a = math.tau * k / 6.0 + 0.4
                put(lcx + int(round(math.cos(a) * 3)), lcy + int(round(math.sin(a) * 3)), 4)
        elif kind == "pit":
            for dx in range(-2, 3):
                for dy in range(-2, 3):
                    if abs(dx) + abs(dy) <= 2:
                        put(lcx + dx, lcy + dy, 3, solid=False)

        micro_objects.append(dict(name="micro_%s" % mname.lower().replace(" ", "_"),
                                  type="sign", x=mx + 30, y=my, title=mname, text=mtext))
        vault = MICRO_VAULTS.get(mname)
        if vault:
            micro_objects.append(dict(name=vault["gate"], type="gate",
                                      x=mx - 96, y=my + 96))
            micro_objects.append(dict(name="lever_%s" % vault["gate"], type="lever",
                                      x=vault["lever"][0], y=vault["lever"][1],
                                      gate=vault["gate"], label=mname))
            micro_objects.append(dict(name="chest_%s" % vault["gate"], type="chest",
                                      x=vault["chest"][0], y=vault["chest"][1],
                                      gold=vault["gold"], item=vault["item"]))

# 7) objects for this chunk (world -> chunk-local coords)
    objects = []
    oid = 1
    for obj in list(WORLD_OBJECTS) + micro_objects:
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
    #
    # The archetype tables come from the roster itself (data/enemies.json
    # `spawns`), not from a list baked into this file. Until the v3 audit the
    # overworld read two hardcoded names per biome, so ten of the fourteen
    # monsters — wolves, husks, lizards, brutes, minotaurs, legionaries,
    # revenants, trolls, archons and the Ashen Herald — existed in the data and
    # never once appeared on the map. `power` stays a per-biome difficulty dial.
    spawner_biomes = {0: (roster_spawn_table("meadow"), 1.0),
                      1: (roster_spawn_table("barrens"), 1.6),
                      2: (roster_spawn_table("frost"), 2.4)}
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
