#!/usr/bin/env python3
"""Phase F6 - author the world's secrets into data/secrets.json.

"Lots of secrets" means things that are *not* on the map: a hollow under a
fallen trunk, a name cut into a crypt wall, a strongbox someone buried and did not
come back for. 40 of them, spread across the three regions and the whole level
range, authored here and validated so that a secret can never be unreachable
(inside a settlement's safe ring), unreachable-in-region (in the wrong biome), or
stacked on top of another.

Kinds:
  cache     buried or hidden goods. Walk over it and it gives itself up.
  carving   cut into stone; reading it gives lore, xp, and points at the region.
  vault     a lock, not a hiding place: needs a key item or a level.
  landmark  a view. Finding it points at the nearest unvisited secret.

Run:  python3 tools/gen_secrets.py
"""

import collections
import json
import os
import random

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
CHUNK = 1024.0           # ChunkStreamer.CHUNK_SIZE
SEED = 20260910
MIN_SPACING = 260.0      # secrets never crowd each other

KINDS = ["cache", "cache", "cache", "carving", "cache", "vault", "cache",
         "landmark", "cache", "carving"]

# Named places to hang secrets off; (name, x, y, biome) with the biome derived
# from ChunkStreamer's rule: y < 0 is frost, x >= 2 chunks is barrens, else meadow.
ANCHORS_BY_REGION = {
    "meadow": [
        ("the mill race", 900, 900), ("the old sheep road", 480, 1500),
        ("the Sunreach wall", 1900, 1200), ("the mill sluice", 700, 1700),
        ("the treeline", 250, 1000), ("the ember warrens mouth", 3150, 1250),
        ("the meadow pale", 1500, 600), ("the Oakstead fold road", 500, 700),
    ],
    "barrens": [
        ("the ash verge", 2300, 700), ("the slag fields", 2700, 300),
        ("the salt pans", 3300, 1000), ("the Ashvow ditch", 4200, 1400),
        ("the ram road", 3700, 500), ("the monastery track", 3900, 1800),
        ("the glass fields", 3000, 1700), ("the ash road", 2600, 1300),
    ],
    "frost": [
        ("the Kilnrest road", 1200, -1400), ("the rimevault approach", 2100, -2600),
        ("the switchback", 2900, -1900), ("the citadel under-road", 3200, -2400),
        ("the scorched ring", 2700, -1500), ("the frost fields", 600, -1100),
        ("the hollow crypts field", 900, -1400), ("the high pass", 1800, -2100),
    ],
}

# Where each secret belongs, by index: the meadow ones are findable early, the
# frost ones only matter to a player who has come that far.
def region_for(index: int) -> str:
    if index <= 13:
        return "meadow"
    if index <= 28:
        return "barrens"
    return "frost"


def biome_at(x: float, y: float) -> str:
    if y < 0:
        return "frost"
    if x >= 2.0 * CHUNK:
        return "barrens"
    return "meadow"


# --- rewards ------------------------------------------------------------------
# Rarity by region, so a meadow cache cannot hand out a legendary.
RARITY_BY_REGION = {
    "meadow": ["common", "common", "uncommon"],
    "barrens": ["uncommon", "uncommon", "rare"],
    "frost": ["rare", "mythical", "mythical"],
}
GOLD_BY_REGION = {"meadow": (20, 90), "barrens": (120, 420), "frost": (500, 1800)}
XP_BY_REGION = {"meadow": 40, "barrens": 600, "frost": 6000}


def load(name: str) -> dict:
    with open(os.path.join(ROOT, "data", name)) as f:
        return json.load(f)


# --- the 40 secrets -----------------------------------------------------------
# (kind, name, hint) - position is chosen by the generator from an anchor, and
# validated: right biome, outside every settlement's safe ring, not on top of an
# earlier secret.
SECRETS = [
    ("cache", "The Sluice Hollow", "A hollow under the mill race lip, packed with straw."),
    ("cache", "Shepherd's Purse", "The old sheep road keeps one stone that is not a stone."),
    ("carving", "The First Warden's Line", "Four words cut into the wall, older than the wall."),
    ("cache", "A Drover's Stash", "Someone paid a drover and never waited for the goods."),
    ("vault", "The Sealed Corner", "A corner of the Sunreach wall that was mortared twice."),
    ("cache", "Ash Verge Cache", "The ash sits thinner in one place. It was dug over."),
    ("landmark", "The Grey Overlook", "From the ridge you can see where the ash started."),
    ("cache", "Slag Glass Purse", "Glass that cooled around something worth keeping."),
    ("carving", "Names at the Smokestack", "The smelters cut their names low, where the heat was."),
    ("cache", "Salt Picker's Box", "The pans give up salt and, once, a box."),
    ("cache", "The Choir's Shed", "A shed a Choir courier used and never cleared."),
    ("vault", "The Ram Road Strongbox", "Horn-deep in the bank, where the ram road bends."),
    ("cache", "Along the Ashvow Ditch", "The ditch was dug deep in one stretch. Twice deep."),
    ("carving", "The Office of Ash", "The monastery's chapter house has a floor that answers."),
    ("cache", "The Warrens' Mouth", "Something dug its own way out, and left a purse behind."),
    ("cache", "Beekeeper's Wall", "Behind the wall, the smell of old wax and older coins."),
    ("landmark", "The Mill Stair's View", "Stand on the stair and the whole valley is chalk marks."),
    ("cache", "The Treeline Marker", "A boundary marker that is heavier at one end."),
    ("vault", "The Third Sluice Gate", "The gate that was bricked rather than repaired."),
    ("cache", "A Furrow That Rings", "One furrow on the sheep road rings underfoot."),
    ("carving", "The Kilnrest Marker", "Kilnrest's boundary stone is inscribed on the *back*."),
    ("cache", "Rime-Crack Cache", "The ice cracked in a star, and something fell in."),
    ("cache", "Frost Fodder Store", "A winter store the frost took before the family did."),
    ("vault", "The Vault Step", "One step of the Rimevault's approach is warmer than the rest."),
    ("cache", "The Herald's Pack", "A herald put his pack down and walked on without it."),
    ("landmark", "The Ring's Edge", "The scorched ring is warm from here, in every season."),
    ("cache", "Troll Path Cache", "Even trolls cache, and trolls forget."),
    ("carving", "The Switchback Names", "Climbers cut their names going up. Not all went down."),
    ("cache", "The Citadel's Cold Store", "Behind the gate-ward wall, a store nobody restocked."),
    ("vault", "The Warden's Own Box", "Small, iron, and addressed to whoever won."),
    ("cache", "Hollow Crypt Shelf", "The crypt shelving holds one jar that is not a jar."),
    ("cache", "A Defector's Tin", "Mireille's people hid more than names."),
    ("carving", "The Ledger Wall", "One wall of the archive lists everyone the Choir owed."),
    ("cache", "Cairn Cache", "A cairn of nine stones. The seventh is loose."),
    ("cache", "The Ash Road Chest", "Buried where the ash road meets the salt."),
    ("landmark", "The Long Look", "From the pass you can see all three regions at once."),
    ("vault", "The Under-Citadel Door", "A door in the under-road that answers to no key."),
    ("cache", "Herald's Second Pack", "The second herald did not need it either."),
    ("carving", "The Vessel Inscription", "The vessel was named before it was built."),
    ("cache", "The Last Cache", "Someone dug this the day the ash started and never came back."),
]


def main() -> None:
    items = load("items.json")["items"]
    settlements = load("settlements.json")["settlements"]
    rng = random.Random(SEED)

    out = collections.OrderedDict()
    out["_comment"] = (
        "Phase F6 - the world's secrets. Positions are authored here (seeded, so "
        "they are stable across regenerations) and validated: every secret sits in "
        "the biome its region declares, outside every settlement's safe ring, and "
        "at least %.0f units from every other secret. Discovery raises the flag "
        "`secret_<id>` and counts in GameState." % MIN_SPACING
    )

    secrets = collections.OrderedDict()
    placed: list = []
    problems = []

    for i, (kind, name, hint) in enumerate(SECRETS, start=1):
        sid = "SEC%02d" % i
        want_region = region_for(i)
        anchors = ANCHORS_BY_REGION[want_region]
        pick = None
        for attempt in range(900):
            ax, ay = anchors[(i + attempt) % len(anchors)][1:]
            ang = rng.uniform(0, 6.283185)
            dist = rng.uniform(140.0, 900.0)
            x = ax + dist * 0.9659 * (1 if rng.random() < 0.5 else -1)
            y = ay + dist * 0.2588 * (1 if rng.random() < 0.5 else -1)
            biome = biome_at(x, y)
            if biome_at(x, y) != want_region:
                continue
            if not safe(x, y, settlements):
                continue
            if too_close(x, y, placed):
                continue
            pick = (x, y, biome)
            break
        if pick is None:
            problems.append("%s (%s) could not be placed" % (sid, name))
            continue
        x, y, biome = pick
        placed.append((x, y))

        gold_lo, gold_hi = GOLD_BY_REGION[biome]
        rarity = rng.choice(RARITY_BY_REGION[biome])
        pool = sorted([iid for iid, it in items.items()
                       if it["rarity"] == rarity
                       and it["type"] in ("weapon", "armor", "accessory", "consumable")])
        reward_items = [rng.choice(pool)] if pool else []
        if kind == "cache" and rng.random() < 0.35:
            pool2 = sorted([iid for iid, it in items.items()
                            if it["rarity"] == "common" and it["type"] == "consumable"])
            if pool2:
                reward_items.append(rng.choice(pool2))

        s = collections.OrderedDict()
        s["name"] = name
        s["kind"] = kind
        s["biome"] = biome
        s["region"] = biome
        s["position"] = [int(round(x)), int(round(y))]
        s["hint"] = hint
        s["text"] = lore(kind, name, hint)
        s["reward"] = collections.OrderedDict([
            ("xp", XP_BY_REGION[biome] // (2 if kind == "carving" else 1)),
            ("gold", rng.randint(gold_lo, gold_hi) if kind != "carving" else gold_lo // 2),
            ("items", reward_items),
        ])
        if kind == "vault":
            # A vault is a lock: it needs a level *and* a key from the world.
            s["requires"] = collections.OrderedDict([
                ("level", {"meadow": 8, "barrens": 40, "frost": 80}[biome]),
                ("item", key_for(biome, items, rng)),
            ])
        if kind == "carving":
            s["carving_lines"] = lore_lines(name)
        secrets[sid] = s

    out["secrets"] = secrets
    out["counts"] = collections.OrderedDict([
        ("total", len(secrets)),
        ("by_kind", collections.Counter(s["kind"] for s in secrets.values())),
        ("by_biome", collections.Counter(s["biome"] for s in secrets.values())),
        ("find_radius", 96),
    ])

    if problems:
        for p in problems:
            print("  ERROR %s" % p)
        raise SystemExit("gen_secrets: %d problem(s)" % len(problems))

    path = os.path.join(ROOT, "data", "secrets.json")
    with open(path, "w") as f:
        json.dump(out, f, indent=2)
        f.write("\n")
    print("wrote %s" % path)
    print("  %d secrets: %s" % (len(secrets), " ".join(
        "%s %d" % (k, v) for k, v in sorted(out["counts"]["by_kind"].items()))))
    print("  by region: %s" % " ".join(
        "%s %d" % (k, v) for k, v in sorted(out["counts"]["by_biome"].items())))
    tight = min(min(dist_between(a, b) for b in placed if a != b) for a in placed)
    print("  closest pair: %.0f units apart (floor %.0f)" % (tight, MIN_SPACING))


def dist_between(a, b) -> float:
    return ((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2) ** 0.5


def safe(x: float, y: float, settlements: dict) -> bool:
    for v in settlements.values():
        pos = v["position"]
        r = float(v.get("radius", 300.0)) * 1.6
        if dist_between((x, y), (pos[0], pos[1])) < r:
            return False
    return True


def too_close(x: float, y: float, placed: list) -> bool:
    return any(dist_between((x, y), p) < MIN_SPACING for p in placed)


def key_for(biome: str, items: dict, rng) -> str:
    """A vault key: something that drops in that region and is not itself a key."""
    want = {"meadow": ["torn_cloth", "bone_fragment"],
            "barrens": ["raider_insignia", "choir_sigil"],
            "frost": ["hollow_relic", "rime_core"]}[biome]
    pool = [w for w in want if w in items]
    return rng.choice(pool) if pool else ""


def lore(kind: str, name: str, hint: str) -> str:
    if kind == "carving":
        return "%s You copy it down before the light goes." % hint
    if kind == "vault":
        return "%s It is locked, and it was locked by someone in a hurry." % hint
    if kind == "landmark":
        return "%s You mark what you can see." % hint
    return hint


def lore_lines(name: str) -> list:
    return [
        "The stone is cut in three hands. The oldest is the deepest.",
        "A name, a date, and a promise: 'we will keep it, so you can sleep'.",
        "Whoever cut the last line cut it badly, and cut it anyway.",
    ]


if __name__ == "__main__":
    main()
