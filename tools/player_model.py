#!/usr/bin/env python3
"""The player power model, in one place (Phase F7).

Both `tools/gen_enemies.py` (which authors monster stats) and
`tools/balance_report.py` (which measures the result) import this, so the game's
numbers and the report's assumptions cannot drift apart: the curves are read out
of the .gd sources at import time, and the reference build is defined once.

The model is deliberately the *player the game actually builds*:

  * one talent point per level, spent evenly across the three branches
  * the **median** item of the rarity their level has unlocked, in each of the
    three equipment slots (not the best-in-tier, which would model a lucky player)
  * basic attacks plus the two abilities, with crit averaged in

Everything else in the report (monster hp, damage, xp, gold, prices) is read from
the shipped JSON.
"""
import json
import os
import re
import statistics

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))

RARITY_ORDER = ["common", "uncommon", "rare", "mythical", "legendary"]
RARITY_BUDGET = {"common": 12.0, "uncommon": 26.0, "rare": 48.0,
                 "mythical": 78.0, "legendary": 120.0}
STAT_WEIGHT = {"atk": 3.0, "def": 2.5, "hp": 0.35, "mp": 0.25,
               "speed": 1.2, "crit": 60.0, "lifesteal": 220.0}
# The level at which a player is expected to be holding each rarity.
RARITY_FROM_LEVEL = {"common": 1, "uncommon": 15, "rare": 30, "mythical": 55, "legendary": 80}

# Gold per point of xp earned from killing things. The quest convention is
# gold = 0.55 * xp; a kill pays a little less because quests are the better pay.
GOLD_PER_XP = 0.35
# How many same-band kills a level is meant to cost, by tier. Faster for trash,
# slower for the things that look like they should hurt.
KILLS_PER_LEVEL = {1: 20, 2: 21, 3: 22, 4: 24, 5: 26, 6: 28}
# Swings to kill a field monster of that tier (before within-tier role offsets).
SWINGS = {1: 3.0, 2: 3.4, 3: 3.6, 4: 4.0, 5: 4.4, 6: 4.8}
# Monster hits the player should survive, by tier: the roster gets meaner.
SURVIVAL = {1: 14.0, 2: 13.0, 3: 12.0, 4: 11.0, 5: 10.0, 6: 9.0}
# Boss ladder: (seconds of reference-player damage, player hits survived at the
# boss's gate level). Weakest to strongest - the Ember Warden is the last word.
BOSS_TARGETS = {
    "goblin_king": (28.0, 14.0),
    "slag_wraith": (38.0, 13.0),
    "bone_titan": (50.0, 12.0),
    "frost_giant": (62.0, 11.0),
    "choir_priest": (76.0, 10.0),
    "ember_warden": (100.0, 9.0),
}
# A tier's median equipment price, as a fraction of one level's kill income at
# the level where that rarity unlocks: an item is a real purchase, not pocket money.
AFFORD_LEVELS = 0.8
# A consumable costs about what one same-band kill pays at its tier.
CONSUMABLE_KILLS = 1.0
# The level each tier's gear and consumables are priced against.
TIER_LEVEL = {1: 4, 2: 14, 3: 32, 4: 54, 5: 74, 6: 92}

# What the balance pass is aiming for. Anything outside these bands is a finding.
TARGETS = {
    "swings": (2.0, 8.0),          # player swings to kill a field monster
    "survival": (5.0, 30.0),       # monster hits the player survives
    "boss_seconds": (25.0, 120.0),
    "kills_per_level": (12.0, 45.0),
    "value_ladder": 1.25,          # each rarity costs >= this much more than the last
    "power_ladder": 1.20,          # ... and carries this much more stat budget
    "income_per_level": (0.5, 2.5),  # levels of income to afford a tier's median item
}


def load(path):
    with open(os.path.join(ROOT, path)) as f:
        return json.load(f)


def gd_const(path, pattern, cast=float):
    with open(os.path.join(ROOT, path)) as f:
        m = re.search(pattern, f.read())
    if not m:
        raise SystemExit("player_model: cannot find %r in %s" % (pattern, path))
    return cast(m.group(1))


# --- constants parsed from the code that uses them ----------------------------

C = {}
C["base_hp"] = gd_const("scripts/autoload/game_state.gd", r"var base_hp: float = ([\d.]+)")
C["base_mp"] = gd_const("scripts/autoload/game_state.gd", r"var base_mp: float = ([\d.]+)")
C["base_attack"] = gd_const("scripts/autoload/game_state.gd", r"var base_attack: float = ([\d.]+)")
C["base_defense"] = gd_const("scripts/autoload/game_state.gd", r"var base_defense: float = ([\d.]+)")
C["hp_per_level"] = gd_const("scripts/autoload/game_state.gd",
                             r"return base_hp \+ \(level - 1\) \* ([\d.]+)")
C["atk_per_level"] = gd_const("scripts/autoload/game_state.gd", r"base_attack \+ \(level - 1\) \* ([\d.]+)")
C["def_per_level"] = gd_const("scripts/autoload/game_state.gd", r"base_defense \+ \(level - 1\) \* ([\d.]+)")
C["crit_mult"] = gd_const("scripts/player/player.gd", r"const CRIT_MULT := ([\d.]+)")
C["attack_cooldown"] = gd_const("scripts/player/player.gd", r"const ATTACK_COOLDOWN := ([\d.]+)")
C["whirl_mult"] = gd_const("scripts/player/player.gd", r"const WHIRL_MULT := ([\d.]+)")
C["whirl_cd"] = gd_const("scripts/player/player.gd", r"const WHIRL_COOLDOWN := ([\d.]+)")
C["bolt_mult"] = gd_const("scripts/player/player.gd", r"const BOLT_MULT := ([\d.]+)")
C["bolt_cd"] = gd_const("scripts/player/player.gd", r"const BOLT_COOLDOWN := ([\d.]+)")
C["crit_cap"] = gd_const("scripts/autoload/game_state.gd",
                         r'clampf\(equipment_bonus\("crit"\) \+ talent_sum\("crit"\), 0\.0, ([\d.]+)\)')
C["xp_base"] = gd_const("scripts/autoload/game_state.gd", r"const XP_BASE: float = ([\d.]+)")
C["xp_exp_early"] = gd_const("scripts/autoload/game_state.gd", r"const XP_EXP_EARLY: float = ([\d.]+)")
C["xp_exp_mid"] = gd_const("scripts/autoload/game_state.gd", r"const XP_EXP_MID: float = ([\d.]+)")
C["xp_exp_late"] = gd_const("scripts/autoload/game_state.gd", r"const XP_EXP_LATE: float = ([\d.]+)")
C["xp_seg1"] = gd_const("scripts/autoload/game_state.gd", r"const XP_SEG1_END: int = (\d+)", int)
C["xp_seg2"] = gd_const("scripts/autoload/game_state.gd", r"const XP_SEG2_END: int = (\d+)", int)
C["max_level"] = gd_const("scripts/autoload/game_state.gd", r"const XP_MAX_LEVEL: int = (\d+)", int)

ITEMS = load("data/items.json")["items"]
TALENTS = load("data/talents.json")["branches"]


def xp_to_next(level):
    """Mirrors GameState.xp_to_next() line for line, seams included."""
    if level >= C["max_level"]:
        return 0
    seg1 = int(round(C["xp_base"] * (C["xp_seg1"] ** C["xp_exp_early"])))
    seg2 = int(round(seg1 * (((C["xp_seg2"] - 1) / C["xp_seg1"]) ** C["xp_exp_mid"])))
    if level <= C["xp_seg1"]:
        return int(round(C["xp_base"] * (level ** C["xp_exp_early"])))
    if level <= C["xp_seg2"]:
        return int(round(seg1 * (((level - 1) / C["xp_seg1"]) ** C["xp_exp_mid"])))
    return int(round(seg2 * (((level - 1) / C["xp_seg2"]) ** C["xp_exp_late"])))


def talent_effects(level, split=None):
    """Talent effects unlocked at `level` with one point per level spent."""
    if split is None:
        pts = max(0, level - 1)
        per = pts // 3
        split = [min(per, 20), min(per, 20), min(pts - 2 * per, 20)]
    out = {"atk": 0.0, "def": 0.0, "hp": 0.0, "mp": 0.0, "crit": 0.0, "lifesteal": 0.0}
    mults = {"atk_cd": 1.0, "dmg_taken": 1.0, "gold": 1.0, "xp": 1.0}
    for branch, points in zip(TALENTS, split):
        for node in branch["nodes"]:
            if int(node.get("req_points", 1)) > points:
                continue
            if int(node.get("req_level", 1)) > level:
                continue
            for k, v in node.get("effects", {}).items():
                if k in out:
                    out[k] += float(v)
                elif k in mults:
                    mults[k] *= float(v)
    return out, mults


def reference_gear(level, slot_weights=None):
    """The median item of the rarity `level` has unlocked, per slot."""
    rarity = "common"
    for r in RARITY_ORDER:
        if level >= RARITY_FROM_LEVEL[r]:
            rarity = r
    def spent(it):
        return sum(float(it.get(k, 0)) * w for k, w in STAT_WEIGHT.items() if k in it)
    gear = {}
    for slot in ["weapon", "armor", "accessory"]:
        pool = [it for it in ITEMS.values()
                if it.get("slot") == slot and it.get("rarity") == rarity]
        if not pool:
            continue
        pool.sort(key=spent)
        gear[slot] = pool[len(pool) // 2]
    return rarity, gear


def player(level):
    """The reference player at `level`: dict of the stats the game will compute."""
    tal, mults = talent_effects(level)
    rarity, gear = reference_gear(level)
    g = {"atk": 0.0, "def": 0.0, "hp": 0.0, "crit": 0.0, "lifesteal": 0.0}
    for slot in ["weapon", "armor", "accessory"]:
        for k in g:
            g[k] += float(gear.get(slot, {}).get(k, 0))

    hp = C["base_hp"] + (level - 1) * C["hp_per_level"] + tal["hp"] + g["hp"]
    atk = C["base_attack"] + (level - 1) * C["atk_per_level"] + tal["atk"] + g["atk"]
    dfs = C["base_defense"] + (level - 1) * C["def_per_level"] + tal["def"] + g["def"]
    crit = min(C["crit_cap"], g["crit"] + tal["crit"])
    cd = C["attack_cooldown"] * mults.get("atk_cd", 1.0)
    hit = atk * (1.0 + crit * (C["crit_mult"] - 1.0))
    dps = hit / cd
    abilities = (atk * C["whirl_mult"]) / max(0.01, C["whirl_cd"]) \
        + (atk * C["bolt_mult"]) / C["bolt_cd"]
    return {
        "level": level, "hp": hp, "atk": atk, "def": dfs, "crit": crit,
        "lifesteal": min(0.5, g["lifesteal"] + tal["lifesteal"]),
        "hit": hit, "cd": cd, "dps": dps + abilities,
        "basic_dps": dps, "gear": rarity,
        "gold_mult": mults.get("gold", 1.0),
    }


def damage_taken(p, raw):
    return max(1.0, raw - p["def"] * 0.5)


def hits_survived(p, raw):
    return p["hp"] / damage_taken(p, raw)


def band_mid(band):
    return int(round((int(band[0]) + int(band[1])) / 2.0))


def tier_of(items_by_id, item_id):
    return int(items_by_id.get(item_id, {}).get("tier", 1))


def rarity_at(level):
    rarity = "common"
    for r in RARITY_ORDER:
        if level >= RARITY_FROM_LEVEL[r]:
            rarity = r
    return rarity


def median(values):
    return statistics.median(values) if values else 0.0


# --- economy helpers (Phase F7) ------------------------------------------------

def income_per_level(level):
    """Gold a player earns killing their way through one level at `level`
    (the same 25-kills-per-level the report measures)."""
    return xp_to_next(level) * GOLD_PER_XP


def gold_per_kill(level, kills=25):
    return xp_to_next(level) / float(kills) * GOLD_PER_XP


def median_price(rarity):
    """The median price of one item of `rarity`: a fraction of one level's income
    at the level where that rarity unlocks. Replaces the hand-picked constants so
    prices track the economy they are spent in.

    Common gear is the exception, anchored to three kills at its tier level: the
    first hour of the game should be able to buy a better club, and "0.8 levels of
    income" at level 1 is pocket lint either way.
    """
    if rarity == "common":
        return int(round(3.0 * gold_per_kill(TIER_LEVEL[1])))
    return int(round(AFFORD_LEVELS * income_per_level(RARITY_FROM_LEVEL[rarity])))


def consumable_price(tier):
    return max(8, int(round(CONSUMABLE_KILLS * gold_per_kill(TIER_LEVEL[tier]))))


def monster_targets(tier, band):
    """The numbers a field monster of `tier` at the middle of `band` should have
    to hit the swings/survival/kills targets. gen_enemies.py scales its authored
    within-tier roles against these."""
    mid = band_mid(band)
    p = player(mid)
    return {
        "level": mid,
        "hp": p["hit"] * SWINGS[tier],
        "damage": p["hp"] / SURVIVAL[tier] + p["def"] * 0.5,
        "xp": xp_to_next(mid) / float(KILLS_PER_LEVEL[tier]),
        "gold_per_xp": GOLD_PER_XP,
        "player": p,
    }


def boss_targets(boss_id):
    """(hp, damage) for a boss at its gate level, from the ladder targets."""
    seconds, survival = BOSS_TARGETS[boss_id]
    gate = int(load("data/enemies.json")["archetypes"][boss_id]["level_band"][0])
    p = player(gate)
    return {
        "level": gate,
        "hp": p["dps"] * seconds,
        "damage": p["hp"] / survival + p["def"] * 0.5,
        "player": p,
    }
