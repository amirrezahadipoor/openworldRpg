#!/usr/bin/env python3
"""Phase E §1 data generator: settlements + dungeons.

Writes data/settlements.json (3 villages / 3 towns / 3 cities) and
data/dungeons.json (9 dungeons / 26 floors). Re-runnable; deterministic.
"""
import collections
import json
import os

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))

# --- Settlements -------------------------------------------------------------
# tier: village / town / city. `buildings` drives how much the builder lays down.
# Positions sit inside the existing world grid (chunk x -2..4, y -3..1).
SETTLEMENTS = [
    # id, name, tier, biome, faction/settlement role, position, services, npcs
    ("millhaven", "Millhaven", "village", "meadow", "The player's home village on the camp road.", (1100, 620), ["waypoint", "questboard"],
     ["elder_rowan", "wren", "merchant_bram"]),
    ("oakstead", "Oakstead", "village", "meadow", "Mill and orchard village; Meadows side-quest hub.", (300, 1200), ["waypoint", "questboard"],
     ["elder_fenwick", "merchant_bram"]),
    ("sunreach", "Sunreach City", "city", "meadow", "The Meadows' seat of law. Home of Magistrate Voss.", (1750, 1350), ["waypoint", "shop", "inn", "questboard"],
     ["magistrate_voss", "ysolde", "elder_fenwick"]),
    ("ashport", "Ashport", "town", "barrens", "Salvage town on the ash road; Kael's base.", (2850, 900), ["waypoint", "shop", "questboard"],
     ["hunter_kael", "ysolde"]),
    ("cinderhold", "Cinderhold", "town", "barrens", "Garrison town holding the line at the slag.", (3400, 300), ["waypoint", "questboard"],
     ["captain_dael"]),
    ("ashvow", "Ashvow", "city", "barrens", "The Ashen Choir's burnt seat. Half-ruined, still inhabited.", (4300, 1200), ["waypoint"],
     ["brother_ashe"]),
    ("frosthaven", "Frosthaven", "village", "frost", "Last hearth before the climb.", (200, -900), ["waypoint", "questboard"],
     ["mireille"]),
    ("kilnrest", "Kilnrest", "town", "frost", "Terraced mining town in the pass; the peaks' trade floor.", (1500, -1800), ["waypoint", "shop", "inn"],
     ["ysolde", "mireille"]),
    ("skyreach", "Skyreach Citadel", "city", "frost", "The Wardens' citadel above the clouds.", (3200, -2400), ["waypoint", "shop", "questboard"],
     ["high_warden_isolde", "captain_dael"]),
]

TIER_BUILDINGS = {"village": 6, "town": 10, "city": 16}
TIER_RADIUS = {"village": 210.0, "town": 260.0, "city": 330.0}
TIER_SAFE_RADIUS = {"village": 300.0, "town": 360.0, "city": 440.0}
BIOME_GROUND = {
    "meadow": [0.28, 0.46, 0.28],
    "barrens": [0.55, 0.47, 0.33],
    "frost": [0.33, 0.38, 0.47],
}
BIOME_ROOF = {
    "meadow": [0.52, 0.30, 0.22],
    "barrens": [0.40, 0.26, 0.20],
    "frost": [0.28, 0.32, 0.42],
}

out = collections.OrderedDict()
out["_comment"] = (
    "Phase E §1 - settlements. Each entry becomes a real scene built by "
    "scripts/world/settlement.gd (plaza, buildings, waypoint, sign, NPCs), "
    "not a recoloured biome chunk. `position` is a world pixel coordinate; "
    "`safe_radius` suppresses enemy spawners around the settlement."
)
settlements = collections.OrderedDict()
for sid, name, tier, biome, desc, pos, services, npcs in SETTLEMENTS:
    settlements[sid] = collections.OrderedDict([
        ("id", sid), ("name", name), ("tier", tier), ("biome", biome),
        ("desc", desc),
        ("position", [pos[0], pos[1]]),
        ("radius", TIER_RADIUS[tier]),
        ("safe_radius", TIER_SAFE_RADIUS[tier]),
        ("buildings", TIER_BUILDINGS[tier]),
        ("services", services),
        ("npcs", npcs),
        ("ground_color", BIOME_GROUND[biome]),
        ("roof_color", BIOME_ROOF[biome]),
    ])
out["settlements"] = settlements
out["tiers"] = collections.OrderedDict([
    ("village", {"buildings": TIER_BUILDINGS["village"], "radius": TIER_RADIUS["village"]}),
    ("town", {"buildings": TIER_BUILDINGS["town"], "radius": TIER_RADIUS["town"]}),
    ("city", {"buildings": TIER_BUILDINGS["city"], "radius": TIER_RADIUS["city"]}),
])
with open(os.path.join(ROOT, "data", "settlements.json"), "w") as f:
    json.dump(out, f, indent=2)
    f.write("\n")

# --- Dungeons ----------------------------------------------------------------
# (id, name, biome, entrance position, floors, acts/notes, floor plans)
# Floor plans: (enemy table, spawners, power, boss)
# (id, name, biome, pos, floors, desc, level_band, floor plans)
# `level_band` is the level range the dungeon is authored for; every monster on
# every floor must have a level band that overlaps it (tests/items_test.gd).
# `boss: true` marks the single floor that gates the dungeon, and it must hold
# exactly one named boss.
DUNGEONS = [
    ("drowned_mill", "The Drowned Mill", "meadow", (620, 1520), 2,
     "Millhaven's old mill, flooded when the sluice broke. Rats and worse.",
     (1, 14),
     [(["grunt", "emberling"], 3, 1.0, False),
      (["goblin_king"], 1, 1.3, True)]),
    ("emberling_warrens", "Emberling Warrens", "meadow", (3150, 1400), 2,
     "Tunnels the Emberlings dug under the ash road.",
     (1, 22),
     [(["emberling", "meadow_wolf"], 5, 1.0, False),
      (["husk", "emberling"], 6, 1.7, False)]),
    ("slagworks", "The Slagworks", "barrens", (2600, 200), 3,
     "Abandoned smelting works; the Choir forges there now.",
     (8, 42),
     [(["scout", "lizard"], 4, 1.1, False),
      (["lizard", "shaman"], 5, 1.4, False),
      (["slag_wraith"], 1, 1.8, True)]),
    ("scorched_monastery", "The Scorched Monastery", "barrens", (3750, 1750), 3,
     "Brother Ashe's order held it for eighty years. Now half rubble.",
     (20, 68),
     [(["scout", "shaman"], 4, 1.2, False),
      (["lizard", "raider_brute"], 5, 1.6, False),
      # No named boss lives here (all six are accounted for elsewhere): the
      # deepest floor is an elite wave, so it is honestly flagged not-a-boss.
      (["legion", "shaman", "raider_brute"], 6, 2.2, False)]),
    ("choir_sanctum", "Choir Sanctum", "barrens", (4500, 1600), 4,
     "Beneath Ashvow: where Wren is kept and groomed as the vessel.",
     (38, 88),
     [(["legion", "shaman"], 4, 1.4, False),
      (["minotaur", "legion"], 5, 1.8, False),
      (["legion", "minotaur", "shaman"], 6, 2.2, False),
      (["choir_priest"], 1, 2.6, True)]),
    ("hollow_crypts", "The Hollow Crypts", "frost", (900, -1400), 3,
     "Older than the Wardens. Something down there still keeps accounts.",
     (55, 85),
     [(["revenant", "troll"], 4, 1.5, False),
      (["troll", "revenant"], 5, 1.9, False),
      (["bone_titan"], 1, 2.3, True)]),
    ("rimevault", "The Rimevault", "frost", (2100, -2600), 3,
     "A vault sealed with ice that was once a door.",
     (60, 90),
     [(["revenant", "troll"], 4, 1.7, False),
      (["troll", "revenant"], 5, 2.1, False),
      (["frost_giant"], 1, 2.5, True)]),
    ("wardens_ascent", "Warden's Ascent", "frost", (2900, -1900), 3,
     "The switchback climb to the citadel's undercroft.",
     (65, 100),
     [(["troll", "archon"], 5, 2.0, False),
      (["archon", "revenant"], 6, 2.4, False),
      # The Ashen Herald is an elite, not one of the six named bosses.
      (["ashen_herald", "archon"], 2, 2.8, False)]),
    ("ember_warden_keep", "Warden's Keep", "frost", (2700, -1500), 3,
     "The scorched ring. The existing three-phase Ember Warden fight lives here "
     "unchanged; only the framing around it changed in Phase E.",
     (85, 100),
     [(["archon", "troll"], 5, 2.6, False),
      (["ashen_herald", "archon", "troll"], 6, 3.0, False),
      (["ember_warden"], 1, 1.0, True)]),
]

dout = collections.OrderedDict()
dout["_comment"] = (
    "Phase E §1 - dungeons. `floor` is the 1-based floor index fed to "
    "EnemySpawner.floor_index, which multiplies enemy hp/damage/xp through the "
    "archetype's floor_multiplier (Phase E §6). `boss: true` marks the floor "
    "`level_band` is the level range the dungeon is authored for - every monster "    "on every floor must overlap it. `boss: true` marks the single floor that "    "gates the dungeon and it holds exactly one named boss. Boss floors for "    "ember_warden_keep use the existing "
    "BossArena three-phase fight - it is NOT reimplemented here."
)
dungeons = collections.OrderedDict()
total_floors = 0
for did, name, biome, pos, floors, desc, band, plans in DUNGEONS:
    assert len(plans) == floors, (did, floors, len(plans))
    fl = []
    for i, (table, spawners, power, boss) in enumerate(plans, start=1):
        fl.append(collections.OrderedDict([
            ("floor", i),
            ("name", "%s — Floor %d" % (name, i)),
            ("enemies", table),
            ("spawner_count", spawners),
            ("power_scale", power),
            ("floor_index", i),
            ("boss", boss),
            ("exit_to", "surface" if i == floors else "floor_%d" % (i + 1)),
        ]))
    total_floors += floors
    dungeons[did] = collections.OrderedDict([
        ("id", did), ("name", name), ("biome", biome), ("desc", desc),
        ("level_band", [band[0], band[1]]),
        ("position", [pos[0], pos[1]]),
        ("floors", fl),
    ])
dout["dungeons"] = dungeons
dout["floor_total"] = total_floors
with open(os.path.join(ROOT, "data", "dungeons.json"), "w") as f:
    json.dump(dout, f, indent=2)
    f.write("\n")

print("wrote data/settlements.json with %d settlements" % len(settlements))
print("wrote data/dungeons.json with %d dungeons / %d floors" % (len(dungeons), total_floors))
