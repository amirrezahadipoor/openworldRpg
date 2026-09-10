#!/usr/bin/env python3
"""Phase F7 - the full economy + power balance pass.

Measures the shipped game: every number below is either read out of
data/*.json or out of the .gd sources at import time, and the player model is
the one in tools/player_model.py - the same module tools/gen_enemies.py and
tools/gen_items.py author against, so this report cannot flatter the data.

It answers the questions a balance pass is for:

  * does the player's power curve cross the monster curve where it should?
  * how long is a normal fight, and a boss fight, at each level?
  * how many kills, and how much gold, does a level cost all the way to 100?
  * is each rarity a real step up in both price and power?

It prints a report and writes reports/balance-<date>.md. It asserts nothing:
it is a measuring instrument, and the decisions that come out of it live in
DECISIONS.md.

Run:  python3 tools/balance_report.py
"""

import datetime
import json
import os
import statistics
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import player_model as M  # noqa: E402

ROOT = M.ROOT
C = M.C
TARGETS = M.TARGETS
RARITY_ORDER = M.RARITY_ORDER

## Every target violation found this run. `--check` turns them into an exit code
## so CI can hold the line the report drew.
VIOLATIONS = []


def load(path):
    return M.load(path)


ITEMS = M.ITEMS
ENEMIES = load("data/enemies.json")
ARCHETYPES = ENEMIES["archetypes"]
SPAWNS = ENEMIES["spawns"]
QUESTS = load("data/quests.json")["quests"]
TALENTS = M.TALENTS


def player(level):
    return M.player(level)


def player_damage_taken(p, raw):
    return M.damage_taken(p, raw)


def xp_to_next(level):
    return M.xp_to_next(level)


def monster(arch_id, level=None):
    """A field monster as the game will build it: its stats are its stats (no
    biome-wide multiplier any more - see DECISIONS #44), scaled only by dungeon
    depth when it is spawned on a deep floor."""
    a = ARCHETYPES[arch_id]
    band = a.get("level_band", [1, 100])
    lv = level if level is not None else M.band_mid(band)
    hp = float(a.get("max_hp", 30.0))
    dmg = float(a.get("contact_damage", 8.0))
    proj = float(a.get("projectile_damage", 0.0))
    cd = float(a.get("attack_cooldown", 1.2))
    return {
        "id": arch_id, "level": lv, "hp": hp, "dmg": dmg, "projectile": proj, "cd": cd,
        "dps": (dmg + proj * (0.5 / cd)) / cd,
        "xp": int(a.get("xp_reward", 18)),
        "gold": statistics.mean(a.get("drops", {}).get("gold", [1, 1])),
        "tier": a.get("tier", 1), "boss": bool(a.get("boss", False)),
        "floor_mult": float(a.get("floor_multiplier", 0.0)),
        "balance": a.get("balance", {}),
    }


# --- the report ---------------------------------------------------------------

def main():
    out = []
    p = out.append

    p("# Balance report — economy and power, whole game")
    p("")
    p("Generated %s by `tools/balance_report.py` (read-only: it measures, it does "
      "not change anything)." % datetime.date.today().isoformat())
    p("")
    p("Model: a reference player who spends one talent point per level (even "
      "split across the three branches), holds the **median** item of the rarity "
      "their level has unlocked in each of the three slots, and fights with basic "
      "attacks plus the two abilities. Monsters are read at the midpoint of their "
      "level band with the game's own `band_power_scale`.")
    p("")
    p("## Constants (parsed from the .gd sources)")
    p("")
    p("| constant | value |")
    p("|---|---|")
    for k in ["base_hp", "base_attack", "base_defense", "hp_per_level",
              "atk_per_level", "def_per_level", "attack_cooldown", "crit_mult",
              "crit_cap", "whirl_mult", "bolt_mult", "xp_base", "max_level"]:
        p("| %s | %s |" % (k, C[k]))
    p("")

    # --- player curve ---
    p("## Player power curve")
    p("")
    p("| L | gear | HP | ATK | DEF | crit | hit | DPS | hits survived (same-band) |")
    p("|---|---|---|---|---|---|---|---|---|")
    rows = []
    for level in [1, 5, 10, 15, 20, 30, 40, 50, 60, 70, 80, 90, 100]:
        pl = player(level)
        pl["xp_need"] = xp_to_next(level)
        # The band the player is standing in at this level.
        band_id = band_monster_for(level)
        m = monster(band_id, level)
        survived = pl["hp"] / player_damage_taken(pl, m["dmg"])
        sw = m["hp"] / pl["hit"]
        pl["hits_to_kill"] = sw
        pl["hits_survived"] = survived
        pl["band_enemy"] = band_id
        pl["swings_per_second"] = 1.0 / pl["cd"]
        pl["kill_seconds"] = sw * pl["cd"]
        pl["enemy"] = m
        rows.append(pl)
        p("| %d | %s | %.0f | %.0f | %.0f | %.0f%% | %.0f | %.0f | %.1f |" % (
            level, pl["gear"], pl["hp"], pl["atk"], pl["def"], pl["crit"] * 100,
            pl["hit"], pl["dps"], survived))
    p("")

    # --- the crossing ---
    p("## Does the power curve cross? (each monster at the middle of its own band)")
    p("")
    p("A monster's stats are authored at its band's midpoint, so that is where the "
      "design intent is measured. The last two columns show the same monster at the "
      "edges of its band, which is the range a player actually meets it across.")
    p("")
    p("| monster | tier | band | mid L | HP | swings | seconds | player hits survived | kills/level | swings at band start-end |")
    p("|---|---|---|---|---|---|---|---|---|---|")
    mid_rows = []
    for aid, a in ARCHETYPES.items():
        if a.get("boss"):
            continue
        band = a.get("level_band", [1, 100])
        mid = M.band_mid(band)
        m = monster(aid, mid)
        pl = player(mid)
        swings = m["hp"] / pl["hit"]
        survived = M.hits_survived(pl, m["dmg"])
        kills = M.xp_to_next(mid) / max(1, m["xp"])
        lo = m["hp"] / player(int(band[0]))["hit"]
        hi = m["hp"] / player(int(band[1]))["hit"]
        mid_rows.append({"id": aid, "tier": m["tier"], "band": band, "level": mid,
                         "swings": swings, "survival": survived, "kills": kills,
                         "hp": m["hp"], "seconds": swings * pl["cd"],
                         "edge": (lo, hi)})
        p("| %s | %d | L%d-%d | %d | %.0f | %.1f | %.1f | %.1f | %.0f | %.1f - %.1f |" % (
            aid, m["tier"], band[0], band[1], mid, m["hp"], swings, swings * pl["cd"],
            survived, kills, lo, hi))
    p("")
    flag(p, "swings", [(r["id"], r["swings"]) for r in mid_rows])
    flag(p, "survival", [(r["id"], r["survival"]) for r in mid_rows])
    flag(p, "kills_per_level", [(r["id"], r["kills"]) for r in mid_rows])
    p("")
    wide = [(r["id"], r["edge"]) for r in mid_rows if r["edge"][0] > 12.0]
    if wide:
        p("Note: a monster met at the *start* of its band takes more than 12 swings "
          "(%s) — that is the band's own difficulty slope, not a curve problem." % (
              ", ".join("%s %.0f" % (k, v[0]) for k, v in wide)))
    p("")

    # --- boss ladder ---
    p("## Boss ladder (fight length at each boss's gate level)")
    p("")
    p("| boss | gate L | HP | player DPS | seconds | hits to kill | boss hits to kill player |")
    p("|---|---|---|---|---|---|---|")
    for bid in ["goblin_king", "slag_wraith", "bone_titan", "frost_giant",
                "choir_priest", "ember_warden"]:
        if bid not in ARCHETYPES:
            continue
        gate = int(ARCHETYPES[bid].get("level_band", [1, 100])[0])
        bm = monster(bid, gate)
        pl = player(gate)
        secs = bm["hp"] / pl["dps"]
        p("| %s | %d | %.0f | %.0f | %.1f | %.0f | %.1f |" % (
            bid, gate, bm["hp"], pl["dps"], secs, bm["hp"] / pl["hit"],
            pl["hp"] / player_damage_taken(pl, bm["dmg"])))
    p("")
    boss_rows = []
    for bid in ARCHETYPES:
        if not ARCHETYPES[bid].get("boss"):
            continue
        gate = int(ARCHETYPES[bid].get("level_band", [1, 100])[0])
        boss_rows.append((bid, gate, monster(bid, gate)["hp"] / player(gate)["dps"]))
    flag(p, "boss_seconds", [(r[0], r[2]) for r in boss_rows])
    p("")

    # --- item ladder ---
    p("## Item ladder: does each rarity sit above the last?")
    p("")
    p("| rarity | items | median value | min value | max value | median stat budget | median atk-equiv | lifesteal items |")
    p("|---|---|---|---|---|---|---|---|")
    weight = {"atk": 3.0, "def": 2.5, "hp": 0.35, "mp": 0.25, "speed": 1.2, "crit": 60.0, "lifesteal": 220.0}
    ladder = {}
    for r in RARITY_ORDER:
        pool = [it for it in ITEMS.values()
                if it.get("rarity") == r and it.get("type") in ("weapon", "armor", "accessory")]
        values = sorted(int(it.get("value", 0)) for it in pool)
        budgets = sorted(sum(float(it.get(k, 0)) * w for k, w in weight.items() if k in it)
                         for it in pool)
        leech = sum(1 for it in pool if float(it.get("lifesteal", 0)) > 0)
        ladder[r] = {
            "value": statistics.median(values), "budget": statistics.median(budgets),
            "max_value": max(values), "min_value": min(values), "count": len(pool),
        }
        p("| %s | %d | %d | %d | %d | %.1f | %.1f | %d |" % (
            r, len(pool), statistics.median(values), min(values), max(values),
            statistics.median(budgets), statistics.median(budgets) / 3.0, leech))
    p("")
    p("| rarity | unlocks at L | median price | levels of income at unlock |")
    p("|---|---|---|---|")
    affordable_rows = []
    for r in RARITY_ORDER:
        lvl = M.RARITY_FROM_LEVEL[r]
        income = M.income_per_level(max(1, lvl))
        levels = ladder[r]["value"] / max(1.0, income)
        if r != "common":
            affordable_rows.append((r, levels))
        p("| %s | %d | %d | %.2f |" % (r, lvl, ladder[r]["value"], levels))
    p("")
    flag(p, "income_per_level", affordable_rows)
    p("")
    for r in RARITY_ORDER[1:]:
        prev = RARITY_ORDER[RARITY_ORDER.index(r) - 1]
        vr = ladder[r]["value"] / max(1, ladder[prev]["value"])
        br = ladder[r]["budget"] / max(0.01, ladder[prev]["budget"])
        mark = "OK " if vr >= TARGETS["value_ladder"] and br >= TARGETS["power_ladder"] else "!! "
        p("- %s**%s** vs %s: value x%.2f, budget x%.2f" % (mark, r, prev, vr, br))
    p("")

    # --- economy ---
    p("## Economy: what a level costs")
    p("")
    p("| L | XP to level | same-band kills | gold per kill | gold per level (kills) | best item affordable (value) |")
    p("|---|---|---|---|---|---|")
    for level in [5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100]:
        need = xp_to_next(level)
        m = monster(band_monster_for(level), level)
        kills = need / max(1, m["xp"])
        gold = m["gold"] * kills
        # Which items can that gold actually buy?
        affordable = [it for it in ITEMS.values() if int(it.get("value", 0)) <= gold]
        best = max((int(it.get("value", 0)) for it in affordable), default=0)
        p("| %d | %d | %.1f | %.1f | %.0f | %d |" % (level, need, kills, m["gold"], gold, best))
    p("")

    p("### Quest income as a share of a level")
    p("")
    p("| quest block | avg xp | avg gold | share of a level-up |")
    p("|---|---|---|---|")
    for label, pref in [("main chain MQ001-100", "MQ"), ("side quests SQ001-100", "SQ"),
                        ("story arc (q1-q4)", "q")]:
        ids = [q for q in QUESTS if q.startswith(pref) and (pref != "q" or "_" in q)]
        if not ids:
            continue
        xps = [int(QUESTS[q].get("reward", {}).get("xp", 0)) for q in ids]
        golds = [int(QUESTS[q].get("reward", {}).get("gold", 0)) for q in ids]
        anchors = [int(QUESTS[q].get("level_anchor", 1)) for q in ids]
        shares = [xp / max(1, xp_to_next(max(1, min(99, a)))) for xp, a in zip(xps, anchors)]
        p("| %s | %d | %d | %.0f%% |" % (
            label, statistics.mean(xps), statistics.mean(golds),
            100 * statistics.mean(shares)))
    p("")

    total_mq = sum(int(QUESTS[q].get("reward", {}).get("xp", 0)) for q in QUESTS if q.startswith("MQ"))
    total_sq = sum(int(QUESTS[q].get("reward", {}).get("xp", 0)) for q in QUESTS if q.startswith("SQ"))
    climb = sum(xp_to_next(l) for l in range(1, C["max_level"]))
    p("Total to walk the whole chain of levels 1-100: **%d xp**." % climb)
    p("The 100-step main chain pays **%d xp** (%.0f%% of the climb) and the 100 side "
      "quests pay **%d xp** (%.0f%%), so questing alone carries a player to about "
      "level %.0f with combat filling the rest." % (
          total_mq, 100.0 * total_mq / climb, total_sq, 100.0 * total_sq / climb,
          level_for_xp(total_mq + total_sq)))
    p("")

    # --- dungeon depth ---
    p("## Dungeon depth: floor scaling")
    p("")
    p("| dungeon | floors | last floor | scale at last floor | swings floor 1 -> last |")
    p("|---|---|---|---|---|")
    try:
        dungeons = load("data/dungeons.json")["dungeons"]
        for did, d in dungeons.items():
            fl = d.get("floors", [])
            fm = 0.0
            for f in fl:
                for e in f.get("enemies", []):
                    fm = max(fm, float(ARCHETYPES.get(e, {}).get("floor_multiplier", 0.0)))
            scale = 1.0 + fm * max(0, len(fl) - 1)
            ramp = _dungeon_ramp(fl)
            p("| %s | %d | L%d | x%.2f | %s |" % (did, len(fl), max(
                [int(ARCHETYPES.get(e, {}).get("level_band", [1, 100])[1]) for f in fl
                 for e in f.get("enemies", [])] or [1]), scale, ramp))
    except (OSError, KeyError) as exc:
        p("| (dungeons.json unreadable: %s) | | | |" % exc)
    p("")

    text = "\n".join(out) + "\n"
    print(text)
    os.makedirs(os.path.join(ROOT, "reports"), exist_ok=True)
    path = os.path.join(ROOT, "reports", "balance-%s.md" % datetime.date.today().isoformat())
    with open(path, "w") as f:
        f.write(text)
    sys.stderr.write("wrote %s\n" % path)


def level_for_xp(total):
    acc, lv = 0, 1
    while lv < C["max_level"]:
        acc += xp_to_next(lv)
        if acc > total:
            return float(lv) + 1.0 - (acc - total) / max(1, xp_to_next(lv))
        lv += 1
    return float(C["max_level"])


def _dungeon_ramp(floors):
    """How much tougher the last floor is than the first, in player swings, using
    the reference player at the dungeon's own opening level. A dungeon should ramp;
    it should not become a wall or a corridor of speed bumps."""
    if not floors:
        return "-"
    first = [e for e in floors[0].get("enemies", []) if e in ARCHETYPES and not ARCHETYPES[e].get("boss")]
    # The last *monster* floor: dungeon last floors are boss arenas, and the boss
    # has its own ladder above — the ramp is about the walk, not the door.
    last_index = len(floors) - 1
    last_ids = []
    while last_index >= 0 and not last_ids:
        last_ids = [e for e in floors[last_index].get("enemies", [])
                    if e in ARCHETYPES and not ARCHETYPES[e].get("boss")]
        if not last_ids:
            last_index -= 1
    if not first or not last_ids or last_index <= 0:
        return "-"
    def swings_of(aid, floor_index):
        """Swings to kill, measured against a player who is levelled for that
        floor — the point of a dungeon ramp is that both sides grow."""
        a = ARCHETYPES[aid]
        lvl = M.band_mid(a.get("level_band", [1, 100]))
        scale = 1.0 + float(a.get("floor_multiplier", 0.0)) * max(0, floor_index)
        return float(a.get("max_hp", 30.0)) * scale / player(lvl)["hit"]

    lo = min(swings_of(a, 0) for a in first)
    hi = max(swings_of(a, last_index) for a in last_ids)
    return "%.1f -> %.1f" % (lo, hi)


def flag(p, name, pairs):
    """Print target compliance for one metric: every point inside the band, or the
    exact ones that are not. This is the report's whole job — no asserts."""
    lo, hi = TARGETS[name]
    bad = [(k, v) for k, v in pairs if not (lo <= v <= hi)]
    if not bad:
        p("Target %s in [%g, %g]: **all points inside**." % (name.replace("_", " "), lo, hi))
        return
    p("Target %s in [%g, %g]: **outside at** %s" % (
        name.replace("_", " "), lo, hi, ", ".join("%s %.2f" % b for b in bad)))
    VIOLATIONS.append((name, bad))


def band_monster_for(level):
    """The monster the player is actually fighting at this level: the toughest
    archetype whose band contains the level, in the highest biome that has one."""
    best, best_tier = None, -1
    for aid, a in ARCHETYPES.items():
        if a.get("boss"):
            continue
        band = a.get("level_band", [1, 100])
        if band[0] <= level <= band[1] and int(a.get("tier", 1)) > best_tier:
            best, best_tier = aid, int(a.get("tier", 1))
    return best or "grunt"





if __name__ == "__main__":
    main()
    if "--check" in sys.argv and VIOLATIONS:
        print("")
        print("BALANCE CHECK: FAILED — %d target(s) outside their band:" % len(VIOLATIONS))
        for name, bad in VIOLATIONS:
            print("  %s: %s" % (name, ", ".join("%s %.2f" % b for b in bad)))
        sys.exit(1)
    if "--check" in sys.argv:
        print("")
        print("BALANCE CHECK: PASSED — every measured target is inside its band.")
