#!/usr/bin/env python3
"""Authors data/enemies.json — 14 monsters + 6 bosses, tiered and placed.

Design rules (checked by tests/monster_test.gd at runtime):

  * every archetype declares `tier` (1..6), `biome` and `level_band`
  * Phase F7: hp, damage, xp and gold are DERIVED from the player power curve
    (tools/player_model.py) evaluated at the middle of the archetype's own level
    band, not hand-picked. The hand-written table below still decides each
    monster's *relative* build inside its tier (a shaman is squishier than a
    brute, a wolf is faster than a husk); the curve decides the absolute numbers,
    so "how long does a fight take" and "how many kills is a level" are design
    inputs instead of accidents.
  * placement is data-driven: biome spawn tables only reference archetypes whose
    band covers that biome's level range, and dungeon floors only reference
    archetypes within their depth band — no monster spawns outside its band
  * loot quality scales with tier via `drops.rarity_table`
  * `lifesteal` gear is a rare-or-better find, so it only enters the pool from
    tier 3 upward (and from every boss)
  * the six bosses escalate: each one's HP/damage is a real step above the last,
    and the shipped Ember Warden remains the final, strongest fight with its
    original mechanics
"""
import collections
import json
import os
import statistics
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import player_model  # noqa: E402  (Phase F7: stats come from the power curve)


def _roles(rows):
    """Turn the authored table's hp/dmg/xp into within-tier *relative* weights.

    The hand-written numbers were a design intent ("this one is beefy"), but they
    were also the absolute truth, which is how the roster ended up dying in half a
    swing. Keeping only the ratios preserves the intent and lets the curve set the
    scale. Clamped so no single monster becomes an outlier by accident.
    """
    per = collections.defaultdict(lambda: {"hp": [], "dmg": [], "xp": [], "gold": []})
    for r in rows:
        tier = r[2]
        per[tier]["hp"].append(float(r[5]))
        per[tier]["dmg"].append(float(r[6]))
        per[tier]["xp"].append(float(r[8]))
        per[tier]["gold"].append(sum(r[9]) / 2.0)
    out = {}
    for r in rows:
        tier = r[2]
        med = {k: (statistics.median(v) if v else 1.0) for k, v in per[tier].items()}
        rol = {
            "hp": _clamp(float(r[5]) / max(0.01, med["hp"])),
            "dmg": _clamp(float(r[6]) / max(0.01, med["dmg"])),
            "xp": _clamp(float(r[8]) / max(0.01, med["xp"])),
            "gold": _clamp((sum(r[9]) / 2.0) / max(0.01, med["gold"])),
        }
        out[r[0]] = rol
    return out


def _clamp(v, lo=0.7, hi=2.0):
    ## Floor at 0.7: the authored table's squishiest roles (a 14-hp emberling, a
    ## 26-hp shaman) were 0.45 of their tier's median, which put them under two
    ## swings and near-unkillable-player territory — too far from the curve to
    ## read as a fight at all. Ceiling at 2.0 keeps any one monster from being a
    ## wall by accident. The 0.7-2.0 spread is what is left of "this one is
    ## beefy, that one is a caster".
    return max(lo, min(hi, v))


def _field_stats(mid, tier, band, rol):
    """The absolute numbers for one field monster."""
    t = player_model.monster_targets(tier, band)
    hp = t["hp"] * rol["hp"]
    dmg = t["damage"] * rol["dmg"]
    xp = t["xp"] * rol["xp"]
    gold = xp * player_model.GOLD_PER_XP * rol["gold"]
    return {
        "hp": round(hp),
        "dmg": round(dmg, 1),
        "xp": int(round(xp)),
        "gold": (int(round(gold * 0.75)), int(round(gold * 1.25))),
        "target": t,
    }


def _boss_stats(mid, tier, band, rol):
    """Bosses come straight off the ladder: seconds of reference-player damage,
    and how many of the boss's hits the player is meant to survive."""
    t = player_model.boss_targets(mid)
    xp = player_model.xp_to_next(t["level"]) * 0.35
    return {
        "hp": round(t["hp"]),
        "dmg": round(t["damage"], 1),
        "xp": int(round(xp)),
        "gold": (int(round(xp * 0.45)), int(round(xp * 0.70))),
        "target": t,
    }

# Rarity weights for the bonus gear roll, per tier. Relative weights inside one
# table; a table of all zeros means "this monster never drops bonus gear".
def rt(common, uncommon, rare, mythical, legendary):
    return {"common": common, "uncommon": uncommon, "rare": rare,
            "mythical": mythical, "legendary": legendary}


# Every monster also rolls from its tier's consumable pool. This is what makes
# the consumable half of the catalogue lootable instead of shop-only, and it
# keeps potion quality rising with the monster's level band.
CONSUMABLES_BY_TIER = {
    1: [["bandage", 0.12], ["health_potion", 0.18], ["mana_potion", 0.10]],
    2: [["bandage", 0.12], ["health_potion", 0.18], ["mana_potion", 0.12],
        ["elixir_of_haste", 0.06], ["ironskin_tonic", 0.05], ["focus_draught", 0.05]],
    3: [["greater_health_potion", 0.15], ["greater_mana_potion", 0.12],
        ["elixir_of_haste", 0.08], ["elixir_of_iron", 0.08]],
    4: [["greater_health_potion", 0.18], ["greater_mana_potion", 0.15],
        ["elixir_of_iron", 0.10]],
    5: [["greater_elixir", 0.12], ["chilled_greater_potion", 0.12],
        ["ward_of_ash", 0.08], ["ironskin_tonic", 0.06]],
    6: [["greater_elixir", 0.15], ["chilled_greater_potion", 0.12],
        ["phoenix_elixir", 0.06]],
}

RARITY_BY_TIER = {
    1: rt(100, 10, 0, 0, 0),
    2: rt(100, 24, 3, 0, 0),
    3: rt(100, 40, 11, 1, 0),
    4: rt(100, 55, 20, 4, 0.2),
    5: rt(100, 70, 33, 8, 1),
    6: rt(100, 85, 45, 15, 2.5),
}

# (id, name, tier, biome, level_band, hp, dmg, speed, xp, gold, sheet, scale,
#  behaviour, items, floor_mult, body_color)
MONSTERS = [
    # ---- Tier 1: Meadows, L1-8. The tutorial band. ----
    ("grunt", "Slime Grunt", 1, "meadow", (1, 8), 30, 8, 95, 18, (2, 6),
     "enemy_goblin", 1.0, "melee",
     [["slime_gel", 0.55], ["health_potion", 0.18], ["bread", 0.20]],
     0.11, [0.78, 0.28, 0.28]),
    ("emberling", "Emberling", 1, "meadow", (1, 8), 14, 4, 220, 14, (1, 4),
     "enemy_skeleton", 0.8, "melee",
     [["emberling_ember", 0.5], ["health_potion", 0.15], ["bone_fragment", 0.25]],
     0.09, [0.95, 0.45, 0.20]),
    ("meadow_wolf", "Meadow Wolf", 1, "meadow", (3, 10), 22, 6, 185, 20, (3, 7),
     "enemy_wolf", 0.95, "melee",
     [["torn_cloth", 0.3], ["dried_meat", 0.25], ["bone_fragment", 0.3]],
     0.10, [0.62, 0.55, 0.40]),

    # ---- Tier 2: Meadows edge / Barrens mouth, L8-20. ----
    ("scout", "Barrens Scout", 2, "barrens", (8, 20), 20, 6, 180, 22, (3, 8),
     "enemy_raider", 1.0, "melee",
     [["raider_insignia", 0.3], ["scrap_iron", 0.4], ["mana_potion", 0.22]],
     0.12, [0.85, 0.62, 0.20]),
    ("husk", "Rotting Husk", 2, "meadow", (10, 22), 46, 9, 78, 30, (5, 11),
     "enemy_husk", 1.05, "melee",
     [["bone_fragment", 0.5], ["cave_moss", 0.3], ["fetid_gland", 0.25],
      ["greater_health_potion", 0.12]],
     0.13, [0.45, 0.55, 0.40]),

    # ---- Tier 3: Barrens, L20-40. First real gear drops. ----
    ("shaman", "Frost Shaman", 3, "barrens", (20, 40), 26, 5, 82, 30, (4, 10),
     "enemy_shaman", 1.0, "ranged",
     [["shaman_charm", 0.3], ["scorched_relic", 0.25], ["mana_potion", 0.3],
      ["greater_mana_potion", 0.15]],
     0.10, [0.35, 0.62, 0.85]),
    ("lizard", "Slag Lizard", 3, "barrens", (22, 42), 58, 11, 140, 40, (6, 14),
     "enemy_lizard", 1.1, "melee",
     [["ash_shard", 0.5], ["fetid_gland", 0.35], ["emberglass_shard", 0.15],
      ["greater_health_potion", 0.18]],
     0.14, [0.55, 0.70, 0.35]),
    ("raider_brute", "Raider Brute", 3, "barrens", (24, 45), 90, 14, 105, 48, (8, 16),
     "enemy_raider2", 1.3, "melee",
     [["raider_insignia", 0.45], ["scrap_iron", 0.5], ["greater_health_potion", 0.15],
      ["warden_steel_ingot", 0.06]],
     0.15, [0.72, 0.40, 0.22]),

    # ---- Tier 4: Barrens deep / Peaks foothills, L40-65. ----
    ("minotaur", "Ash Minotaur", 4, "barrens", (40, 65), 150, 19, 120, 78, (12, 24),
     "enemy_minotaur", 1.45, "melee",
     [["ash_shard", 0.6], ["scorched_relic", 0.4], ["warden_steel_ingot", 0.12],
      ["emberglass_shard", 0.3]],
     0.16, [0.60, 0.35, 0.25]),
    ("legion", "Choir Legionnaire", 4, "barrens", (45, 68), 175, 21, 100, 88, (14, 26),
     "enemy_legion", 1.25, "melee",
     [["choir_sigil", 0.3], ["torn_cloth", 0.5], ["warden_steel_ingot", 0.15],
      ["greater_health_potion", 0.25]],
     0.17, [0.55, 0.50, 0.62]),

    # ---- Tier 5: Peaks, L65-85. ----
    ("revenant", "Frost Revenant", 5, "frost", (65, 85), 240, 27, 115, 140, (18, 34),
     "enemy_revenant", 1.3, "ranged",
     [["frost_crystal", 0.45], ["rime_core", 0.15], ["hollow_relic", 0.06],
      ["greater_mana_potion", 0.35]],
     0.16, [0.62, 0.72, 0.92]),
    # Frost's band opens at 38, but every frost monster used to start at 65 —
    # so the whole low half of the biome was either empty or filled with stray
    # meadow monsters. This is the road in: a wolf the cold got to.
    ("rime_stalker", "Rime Stalker", 4, "frost", (38, 62), 120, 17, 196, 62, (10, 20),
     "enemy_wolf", 1.05, "melee",
     [["frost_pelt", 0.45], ["chilled_greater_potion", 0.15], ["bone_fragment", 0.35]],
     0.14, [0.68, 0.78, 0.88]),
    ("troll", "Rime Troll", 5, "frost", (68, 88), 420, 34, 92, 185, (22, 42),
     "enemy_troll", 1.6, "melee",
     [["frost_crystal", 0.5], ["rime_core", 0.22], ["hollow_relic", 0.10],
      ["greater_elixir", 0.18]],
     0.18, [0.48, 0.58, 0.66]),

    # ---- Tier 6: endgame, L85-100. ----
    ("archon", "Ashen Archon", 6, "frost", (85, 100), 520, 42, 130, 260, (30, 55),
     "enemy_archon", 1.45, "ranged",
     [["choir_ledger", 0.12], ["vessel_shard", 0.15], ["rime_core", 0.4],
      ["hollow_relic", 0.25], ["phoenix_elixir", 0.08]],
     0.15, [0.85, 0.45, 0.30]),
    ("ashen_herald", "Ashen Herald", 6, "frost", (88, 100), 600, 46, 118, 300, (35, 60),
     "boss_ashen_herald", 1.5, "melee",
     [["choir_ledger", 0.15], ["vessel_shard", 0.2], ["choir_sigil", 0.5],
      ["warden_steel_ingot", 0.4]],
     0.16, [0.80, 0.50, 0.35]),
]

# (id, name, tier, biome, level_band, hp, dmg, speed, xp, gold, sheet, scale,
#  phases, guaranteed drops, floor_mult, body_color)
BOSSES = [
    ("goblin_king", "Skarn the Goblin King", 2, "meadow", (8, 14), 260, 12, 105,
     180, (40, 70), "boss_goblin_king", 1.7,
     [{"hp_above": 0.60, "speed_mult": 1.0, "radial": 0, "telegraph": 0.45, "charge": False},
      {"hp_above": 0.25, "speed_mult": 1.25, "radial": 6, "telegraph": 0.36, "charge": False},
      {"hp_above": 0.0, "speed_mult": 1.45, "radial": 8, "telegraph": 0.28, "charge": True}],
     [["goblin_fang", 1.0], ["iron_sword", 1.0], ["health_potion", 1.0],
      ["traveler_ring", 0.5]],
     0.05, [0.45, 0.72, 0.30]),
    ("slag_wraith", "The Slag Wraith", 3, "barrens", (20, 28), 620, 20, 118,
     420, (80, 130), "boss_slag_wraith", 1.9,
     [{"hp_above": 0.60, "speed_mult": 1.0, "radial": 4, "telegraph": 0.42, "charge": False},
      {"hp_above": 0.25, "speed_mult": 1.3, "radial": 8, "telegraph": 0.34, "charge": True},
      {"hp_above": 0.0, "speed_mult": 1.5, "radial": 10, "telegraph": 0.26, "charge": True}],
     [["emberglass_shard", 1.0], ["ashsteel_longsword", 1.0], ["choir_sigil", 0.5]],
     0.10, [0.70, 0.40, 0.35]),
    ("bone_titan", "The Bone Titan", 5, "frost", (58, 72), 1400, 30, 88,
     900, (140, 210), "boss_bone_titan", 2.1,
     [{"hp_above": 0.65, "speed_mult": 1.0, "radial": 0, "telegraph": 0.5, "charge": False},
      {"hp_above": 0.30, "speed_mult": 1.15, "radial": 8, "telegraph": 0.4, "charge": False},
      {"hp_above": 0.0, "speed_mult": 1.3, "radial": 12, "telegraph": 0.3, "charge": True}],
     [["hollow_relic", 1.0], ["choirbane_mace", 1.0], ["greater_elixir", 1.0]],
     0.11, [0.72, 0.70, 0.62]),
    ("frost_giant", "Jorunn the Frost Giant", 5, "frost", (60, 72), 2600, 42, 96,
     1700, (220, 320), "boss_frost_giant", 2.2,
     [{"hp_above": 0.60, "speed_mult": 1.0, "radial": 6, "telegraph": 0.5, "charge": False},
      {"hp_above": 0.28, "speed_mult": 1.2, "radial": 10, "telegraph": 0.38, "charge": True},
      {"hp_above": 0.0, "speed_mult": 1.4, "radial": 14, "telegraph": 0.28, "charge": True}],
     [["rime_core", 1.0], ["rimeguard_axe", 1.0], ["phoenix_elixir", 0.5]],
     0.12, [0.60, 0.78, 0.95]),
    ("choir_priest", "High Priest Cindral", 5, "barrens", (76, 88), 3600, 50, 112,
     2600, (300, 430), "boss_choir_priest", 2.0,
     [{"hp_above": 0.65, "speed_mult": 1.0, "radial": 8, "telegraph": 0.45, "charge": False},
      {"hp_above": 0.30, "speed_mult": 1.25, "radial": 12, "telegraph": 0.34, "charge": False},
      {"hp_above": 0.0, "speed_mult": 1.5, "radial": 16, "telegraph": 0.24, "charge": True}],
     [["ashen_choir_heart", 0.30], ["choir_ledger", 1.0],
      ["choir_sever", 1.0], ["bloodmoon_amulet", 0.5]],
     0.13, [0.72, 0.35, 0.55]),
    # The shipped final fight. Stats unchanged from the original data so the
    # fight still plays exactly as it always has (Phase E: mechanics untouched).
    ("ember_warden", "The Ember Warden", 6, "frost", (92, 100), 5200, 58, 128,
     4200, (400, 600), "enemy_warden", 1.7,
     [],  # Boss.gd owns the Ember Warden's phase script — see below
     [["warden_core", 1.0], ["warden_steel_ingot", 1.0],
      ["greater_health_potion", 1.0], ["worlds_end", 0.35]],
     0.0, [0.9, 0.35, 0.15]),
]

# Which biome spawns which monsters, and at what level, is derived from the
# roster so it can never drift out of sync.
BIOME_LEVEL = {"meadow": (1, 22), "barrens": (8, 68), "frost": (38, 100)}

# Archetype -> fight pattern (scripts/enemies/enemy.gd). Anything unlisted walks
# straight at the player.
PATTERNS = {
    "meadow_wolf": "skirmish", "emberling": "skirmish", "scout": "skirmish",
    "lizard": "skirmish", "rime_stalker": "skirmish",
    "raider_brute": "charger", "minotaur": "charger", "troll": "charger",
    "ashen_herald": "charger",
    "shaman": "caster", "revenant": "caster", "archon": "caster",
    "grunt": "melee", "husk": "melee", "legion": "melee",
}


def main() -> None:
    out = collections.OrderedDict()
    out["_comment"] = (
        "Monster roster. Every archetype declares tier (1-6), biome and level_band; "
        "spawn placement is derived from those, so nothing can spawn outside its band. "
        "`drops.rarity_table` holds relative weights for one bonus gear roll — better "
        "tiers weight rare/mythical/legendary higher, and lifesteal only exists on "
        "rare-or-better items, so leeching gear is a genuine late-game find. "
        "`floor_multiplier` scales hp/damage/xp per dungeon floor. Bosses list their "
        "phases; the Ember Warden's phases live in scripts/enemies/boss.gd and are "
        "deliberately NOT restated here."
    )
    arch = collections.OrderedDict()

    roles = _roles(MONSTERS)
    for (mid, name, tier, biome, band, hp, dmg, speed, xp, gold, sheet, scale,
         behaviour, items, floor_mult, color) in MONSTERS:
        st = _field_stats(mid, tier, band, roles[mid])
        arch[mid] = _entry(mid, name, tier, biome, band, st["hp"], st["dmg"], speed,
                           st["xp"], st["gold"], sheet, scale, behaviour, items,
                           floor_mult, color, RARITY_BY_TIER[tier], boss=False,
                           phases=[],
                           balance=_balance_note(tier, band, st, roles[mid]))

    for (mid, name, tier, biome, band, hp, dmg, speed, xp, gold, sheet, scale,
         phases, items, floor_mult, color) in BOSSES:
        PATTERNS.setdefault(mid, "boss")
        boss_table = rt(0, 100, 60 + tier * 12, 10 * tier, 1.5 * tier)
        if mid == "ember_warden":
            boss_table = rt(0, 0, 100, 100, 25)
        st = _boss_stats(mid, tier, band, None)
        arch[mid] = _entry(mid, name, tier, biome, band, st["hp"], st["dmg"], speed,
                           st["xp"], st["gold"], sheet, scale, "boss", items,
                           floor_mult, color, boss_table, boss=True, phases=phases,
                           balance=_balance_note(tier, band, st, None, boss=True))

    # --- spawn placement tables (biome -> archetypes whose band overlaps) ----
    spawns = collections.OrderedDict()
    for biome, (lo, hi) in BIOME_LEVEL.items():
        ids = []
        for mid, e in arch.items():
            if e.get("boss"):
                continue
            if e["biome"] != biome:
                continue
            bl, bh = e["level_band"]
            if bh >= lo and bl <= hi and bl <= hi and bh >= lo:
                ids.append(mid)
        spawns[biome] = collections.OrderedDict([
            ("level_band", [lo, hi]),
            ("archetypes", sorted(ids, key=lambda i: arch[i]["tier"])),
        ])
    out["spawns"] = spawns
    out["biome_level_band"] = collections.OrderedDict(
        (b, list(v)) for b, v in BIOME_LEVEL.items())
    out["archetypes"] = arch

    path = os.path.join(ROOT, "data", "enemies.json")
    with open(path, "w") as f:
        json.dump(out, f, indent=2)
        f.write("\n")

    monsters = [k for k, v in arch.items() if not v.get("boss")]
    bosses = [k for k, v in arch.items() if v.get("boss")]
    print("wrote %s" % path)
    print("  %d monsters, %d bosses" % (len(monsters), len(bosses)))
    for b, v in spawns.items():
        print("  %-8s L%02d-%02d: %s" % (b, v["level_band"][0], v["level_band"][1],
                                          ", ".join(v["archetypes"])))
    print("  boss escalation (hp):", [int(arch[b]["max_hp"]) for b in bosses])
    print("  derived from the player curve at each band's midpoint:")
    for b, v in arch.items():
        if v.get("boss"):
            continue
        bal = v["balance"]
        print("    %-14s L%02d-%02d hp %6d  dmg %6.1f  xp %6d  (%.1f swings, %.1f hits "
              "survived, %.0f kills/level)" % (
                  b, v["level_band"][0], v["level_band"][1], int(v["max_hp"]),
                  v["contact_damage"], v["xp_reward"], bal["swings"], bal["survival"],
                  player_model.KILLS_PER_LEVEL[int(v["tier"])]))
    for b in bosses:
        bal = arch[b]["balance"]
        print("    %-14s gate L%3d hp %6d  dmg %6.1f  (%.0f s fight, %.1f hits survived)" % (
            b, arch[b]["level_band"][0], int(arch[b]["max_hp"]), arch[b]["contact_damage"],
            bal["seconds"], bal["survival"]))


def _balance_note(tier, band, st, rol, boss=False):
    """The targets this entry was authored to hit, stored in the data so the
    report and any future retune can see the intent, not just the result."""
    p = st["target"]["player"]
    note = collections.OrderedDict()
    note["level"] = st["target"]["level"]
    note["lifesteal_on_gear"] = False
    if boss:
        note["seconds"] = round(st["hp"] / max(1.0, p["dps"]), 1)
        note["survival"] = round(p["hp"] / max(1.0, st["dmg"] - p["def"] * 0.5), 1)
    else:
        note["swings"] = round(st["target"]["hp"] / max(1.0, p["hit"]), 1)
        note["survival"] = round(p["hp"] / max(1.0, st["dmg"] - p["def"] * 0.5), 1)
    return note


def _entry(mid, name, tier, biome, band, hp, dmg, speed, xp, gold, sheet, scale,
           behaviour, items, floor_mult, color, rarity_table, boss, phases,
           balance=None):
    e = collections.OrderedDict()
    e["display_name"] = name
    e["tier"] = tier
    e["biome"] = biome
    e["level_band"] = [band[0], band[1]]
    e["max_hp"] = float(hp)
    e["move_speed"] = float(speed)
    e["contact_damage"] = float(dmg)
    e["chase_radius"] = 300.0 + tier * 40.0
    e["attack_radius"] = 56.0 if behaviour == "melee" else 320.0
    e["attack_cooldown"] = round(1.35 - tier * 0.10, 2)
    e["xp_reward"] = int(xp)
    e["body_color"] = color
    e["behavior"] = behaviour
    # Movement/attack style. `behavior` says how it attacks (melee/ranged/boss);
    # `pattern` says how it *carries itself* — see DECISIONS #54. Kept here so a
    # roster regeneration cannot silently flatten every monster back into one
    # brain, which is exactly what happened before the v2 audit caught it.
    e["pattern"] = PATTERNS.get(mid, "melee")
    if behaviour == "ranged":
        e["projectile_damage"] = float(dmg)
        e["projectile_speed"] = 240.0 + tier * 12.0
    e["floor_multiplier"] = float(floor_mult)
    if balance is not None:
        e["balance"] = balance
    e["sheet"] = "res://assets/lpc/%s.png" % sheet
    e["sprite_scale"] = float(scale)
    if boss:
        e["boss"] = True
        e["phases"] = phases
        e["rarity_weight"] = tier + 1
    # Signature materials first, then the tier's consumable pool (skipping
    # anything the hand-written table already lists).
    table = [[i, float(c)] for i, c in items]
    listed = set(i for i, _ in table)
    for cid, chance in CONSUMABLES_BY_TIER[tier]:
        if cid not in listed:
            table.append([cid, float(chance)])
    drops = collections.OrderedDict()
    drops["gold"] = [int(gold[0]), int(gold[1])]
    drops["items"] = table
    drops["rarity_table"] = rarity_table
    e["drops"] = drops
    return e


if __name__ == "__main__":
    main()
