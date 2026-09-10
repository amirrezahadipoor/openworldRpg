#!/usr/bin/env python3
"""Authors data/items.json — 100+ items across five rarity tiers.

Design rules (enforced by tools/gen_items.py's own self-check AND by
tests/items_test.gd at runtime):

  * every item fits its rarity's stat budget (weighted, see ItemsDB.STAT_WEIGHT)
  * `lifesteal` only appears on rare-or-better gear, and only as a *chance*
    affix — it is rolled at drop time (see EnemyDB.roll_drops), never on a
    common/uncommon item
  * the tier ordering must be a strict power ordering: the *average* weighted
    stat total of tier N must be below that of tier N+1
  * every item is referenced by at least one drop table, shop or quest reward
    (checked by tests/items_test.gd against data/enemies.json + data/quests.json)
"""
import collections
import json
import os
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import player_model  # noqa: E402  (Phase F7: prices come from the economy curve)

WEIGHT = {"atk": 3.0, "def": 2.5, "hp": 0.35, "mp": 0.25,
          "speed": 1.2, "mp_regen": 25.0, "crit": 60.0, "lifesteal": 220.0}
BUDGET = {"common": 12.0, "uncommon": 26.0, "rare": 48.0,
          "mythical": 78.0, "legendary": 120.0}

# (id, name, type, slot, rarity, stats, desc)
# Stat keys: atk def hp mp speed mp_regen crit lifesteal
ITEMS = [
    # ---------------- COMMON: starter / disposable ----------------
    ("wooden_club", "Wooden Club", "weapon", "weapon", "common", {"atk": 3},
     "A branch with ambitions."),
    ("rusty_dagger", "Rusty Dagger", "weapon", "weapon", "common", {"atk": 4},
     "Sharp enough for slimes. Barely."),
    ("short_sword", "Short Sword", "weapon", "weapon", "common", {"atk": 4},
     "A trusty blade. Better than sharp words."),
    ("hunting_knife", "Hunting Knife", "weapon", "weapon", "common", {"atk": 3, "crit": 0.05},
     "Kael's spare. Good for skinning, fine for stabbing."),
    ("farmers_pitchfork", "Farmer's Pitchfork", "weapon", "weapon", "common", {"atk": 4},
     "Millhaven issue. Smells of hay."),
    ("miners_pick", "Miner's Pick", "weapon", "weapon", "common", {"atk": 3, "hp": 8},
     "Kilnrest steel. Doubles as a climbing tool."),
    ("cloth_tunic", "Cloth Tunic", "armor", "armor", "common", {"def": 2, "hp": 8},
     "Home-woven. Better than nothing."),
    ("leather_armor", "Leather Armor", "armor", "armor", "common", {"def": 3},
     "Boiled leather. Smells like adventure."),
    ("padded_hood", "Padded Hood", "armor", "armor", "common", {"def": 2, "hp": 10},
     "Keeps the ash out of your eyes."),
    ("travelers_boots", "Traveler's Boots", "armor", "armor", "common", {"def": 1, "speed": 6},
     "Broken in by someone who never came back."),
    ("copper_ring", "Copper Ring", "accessory", "accessory", "common", {"hp": 12},
     "Warm to the touch for no good reason."),
    ("simple_charm", "Simple Charm", "accessory", "accessory", "common", {"mp": 12},
     "A knot of string and a prayer."),
    ("wooden_talisman", "Wooden Talisman", "accessory", "accessory", "common", {"def": 2, "hp": 6},
     "Carved with a name worn smooth."),
    ("health_potion", "Health Potion", "consumable", "", "common", {},
     "Restores 40 HP."),
    ("mana_potion", "Mana Potion", "consumable", "", "common", {},
     "Restores 30 MP."),
    ("bread", "Loaf of Bread", "consumable", "", "common", {},
     "Restores 15 HP. Tastes like a kitchen."),
    ("bandage", "Clean Bandage", "consumable", "", "common", {},
     "Stops the bleeding. Mostly."),

    # ---------------- UNCOMMON: the working adventurer ----------------
    ("iron_sword", "Iron Sword", "weapon", "weapon", "uncommon", {"atk": 8},
     "Forged in the Barrens. Keeps its edge."),
    ("barrens_scimitar", "Barrens Scimitar", "weapon", "weapon", "uncommon", {"atk": 7, "crit": 0.06},
     "Curved for salvage work. Works on people too."),
    ("frost_hatchet", "Frost Hatchet", "weapon", "weapon", "uncommon", {"atk": 6, "speed": 5},
     "Chips ice and armor alike."),
    ("wardens_spear", "Warden's Spear", "weapon", "weapon", "uncommon", {"atk": 7, "def": 2},
     "Issued by the Citadel. Long reach, longer history."),
    ("mill_hammer", "Mill Hammer", "weapon", "weapon", "uncommon", {"atk": 7, "speed": -4},
     "Heavy. Slow. Final."),
    ("scavengers_blade", "Scavenger's Blade", "weapon", "weapon", "uncommon", {"atk": 6, "hp": 20},
     "Ground down from something larger."),
    ("chain_vest", "Chain Vest", "armor", "armor", "uncommon", {"def": 6, "hp": 12},
     "Rings of Ashport salvage."),
    ("hunters_cloak", "Hunter's Cloak", "armor", "armor", "uncommon", {"def": 4, "speed": 8},
     "Grey as the ash road at dawn."),
    ("frosthide_jerkin", "Frosthide Jerkin", "armor", "armor", "uncommon", {"def": 5, "hp": 20},
     "The hide still hates the cold."),
    ("quilted_gambeson", "Quilted Gambeson", "armor", "armor", "uncommon", {"def": 7},
     "Thirty layers of cloth. Surprisingly stubborn."),
    ("ember_ward_pendant", "Ember Ward Pendant", "accessory", "accessory", "uncommon", {"def": 3, "mp": 20},
     "Keeps the heat off your neck."),
    ("traveler_ring", "Traveler's Ring", "accessory", "accessory", "uncommon", {"speed": 12},
     "Lightens the road ahead."),
    ("scholars_lens", "Scholar's Lens", "accessory", "accessory", "uncommon", {"mp": 24, "mp_regen": 0.3},
     "Brother Ashe ground it himself."),
    ("trappers_belt", "Trapper's Belt", "accessory", "accessory", "uncommon", {"hp": 24},
     "Hooks for everything you'll ever need."),
    ("greater_health_potion", "Greater Health Potion", "consumable", "", "uncommon", {},
     "Restores 90 HP."),
    ("greater_mana_potion", "Greater Mana Potion", "consumable", "", "uncommon", {},
     "Restores 70 MP."),
    ("elixir_of_haste", "Elixir of Haste", "consumable", "", "uncommon", {},
     "A short burst of speed for the long walk home. +30% move speed for 10s."),
    ("ironskin_tonic", "Ironskin Tonic", "consumable", "", "uncommon", {},
     "Chalk and iron filings. Takes 35% off everything that lands for 12s."),
    ("focus_draught", "Focus Draught", "consumable", "", "uncommon", {},
     "Restores 8 MP a second for 12s. Tastes like cold metal."),

    # ---------------- RARE: first real power ----------------
    ("ashsteel_longsword", "Ashsteel Longsword", "weapon", "weapon", "rare",
     {"atk": 13, "crit": 0.07}, "Quenched in slag. It remembers being slag."),
    ("rimeguard_axe", "Rimeguard Axe", "weapon", "weapon", "rare", {"atk": 12, "def": 3},
     "Cold enough to bite through whatever it hits."),
    ("choirbane_mace", "Choirbane Mace", "weapon", "weapon", "rare", {"atk": 13, "hp": 20},
     "Made for breaking rites, and the ribcages that perform them."),
    ("warden_steel_saber", "Warden-Steel Saber", "weapon", "weapon", "rare",
     {"atk": 11, "crit": 0.10}, "Citadel-forged. The edge knows its business."),
    ("leechthorn_dagger", "Leechthorn Dagger", "weapon", "weapon", "rare",
     {"atk": 8, "lifesteal": 0.04}, "It drinks. You mend."),
    ("emberglass_blade", "Emberglass Blade", "weapon", "weapon", "rare",
     {"atk": 12, "mp": 20}, "Volcanic glass, still faintly warm."),
    ("slaghide_cuirass", "Slaghide Cuirass", "armor", "armor", "rare",
     {"def": 10, "hp": 35}, "Hide tanned in the Slagworks. Nothing chews through it."),
    ("frostguard_plate", "Frostguard Plate", "armor", "armor", "rare",
     {"def": 12, "speed": -4}, "Loud, cold, and worth it."),
    ("cinderweave_robe", "Cinderweave Robe", "armor", "armor", "rare",
     {"def": 6, "mp": 40, "mp_regen": 0.4}, "Woven with thread that will not burn."),
    ("nightsilhouette_cloak", "Nightsilhouette Cloak", "armor", "armor", "rare",
     {"def": 5, "speed": 16}, "You are harder to see. That is the point."),
    ("bloodbound_ring", "Bloodbound Ring", "accessory", "accessory", "rare",
     {"lifesteal": 0.05, "hp": 20}, "A promise between you and your own pulse."),
    ("ashwalkers_torc", "Ashwalker's Torc", "accessory", "accessory", "rare",
     {"def": 4, "hp": 30}, "Worn by everyone who walked the slag and came back."),
    ("seers_eye", "Seer's Eye", "accessory", "accessory", "rare",
     {"mp": 45, "mp_regen": 0.5}, "It blinks when you are not looking."),
    ("duelists_signet", "Duelist's Signet", "accessory", "accessory", "rare",
     {"crit": 0.12, "atk": 3}, "Won, not bought."),
    ("chilled_greater_potion", "Chilled Greater Potion", "consumable", "", "rare", {},
     "Restores 180 HP. Goes down cold."),

    # ---------------- MYTHICAL: build-defining ----------------
    ("wardens_oath", "Warden's Oath", "weapon", "weapon", "mythical",
     {"atk": 20, "def": 5, "crit": 0.08}, "Sworn weapon of the Citadel. It has opinions."),
    ("choir_sever", "Choir-Sever", "weapon", "weapon", "mythical",
     {"atk": 22, "hp": 30}, "Built by someone who had heard enough singing."),
    ("hollowfang", "Hollowfang", "weapon", "weapon", "mythical",
     {"atk": 16, "lifesteal": 0.07}, "The teeth of the Crypts, set in a hilt."),
    ("rimevault_greatsword", "Rimevault Greatsword", "weapon", "weapon", "mythical",
     {"atk": 23, "speed": -6}, "Heavy as a closing door."),
    ("emberheart_axe", "Emberheart Axe", "weapon", "weapon", "mythical",
     {"atk": 19, "mp": 40, "crit": 0.10}, "The head is a coal that never went out."),
    ("vein_drinker", "Vein-Drinker", "weapon", "weapon", "mythical",
     {"atk": 15, "lifesteal": 0.09}, "The Choir's own blade, turned around."),
    ("monastery_aegis", "Monastery Aegis", "armor", "armor", "mythical",
     {"def": 18, "hp": 60}, "Half of it is rubble, and it still holds."),
    ("vesselward_plate", "Vesselward Plate", "armor", "armor", "mythical",
     {"def": 16, "hp": 70, "speed": -4}, "Made to keep something in, originally."),
    ("choir_shroud", "Choir Shroud", "armor", "armor", "mythical",
     {"def": 10, "mp": 70, "mp_regen": 0.7}, "It hums if you stand too still."),
    ("ashveil_mantle", "Ashveil Mantle", "armor", "armor", "mythical",
     {"def": 9, "speed": 24, "hp": 30}, "You leave no tracks in the ash."),
    ("heart_of_the_warden", "Heart of the Warden", "accessory", "accessory", "mythical",
     {"hp": 80, "def": 6}, "Still beating. Politely."),
    ("vessel_splinter", "Vessel's Splinter", "accessory", "accessory", "mythical",
     {"mp": 80, "mp_regen": 0.8}, "A shard of someone who was almost a god."),
    ("bloodmoon_amulet", "Bloodmoon Amulet", "accessory", "accessory", "mythical",
     {"lifesteal": 0.08, "hp": 40}, "Hangs heavy on the nights it matters."),
    ("duskwarden_ring", "Duskwarden Ring", "accessory", "accessory", "mythical",
     {"crit": 0.18, "atk": 6}, "Duelists retired on this ring's reputation alone."),

    # ---------------- LEGENDARY: the endgame ----------------
    ("embers_of_millhaven", "Embers of Millhaven", "weapon", "weapon", "legendary",
     {"atk": 28, "def": 8, "crit": 0.10, "hp": 25},
     "Forged from what was left of the village. It is warm."),
    ("worlds_end", "World's End", "weapon", "weapon", "legendary",
     {"atk": 32, "speed": -8, "hp": 40}, "Somebody ended a war with this. Twice."),
    ("sanguine_covenant", "Sanguine Covenant", "weapon", "weapon", "legendary",
     {"atk": 26, "lifesteal": 0.12}, "The pact is simple: it feeds, you live."),
    ("lifedrinker_cleaver", "Lifedrinker Cleaver", "weapon", "weapon", "legendary",
     {"atk": 28, "lifesteal": 0.10, "hp": 40}, "Drawn from the Choir's own vault."),
    ("skyrend_spear", "Skyrend Spear", "weapon", "weapon", "legendary",
     {"atk": 29, "crit": 0.15}, "Cast down from the Citadel at something large."),
    ("wardens_last_stand", "Warden's Last Stand", "armor", "armor", "legendary",
     {"def": 28, "hp": 110}, "The Citadel's last set. It fits you, which is strange."),
    ("choirbreakers_regalia", "Choirbreaker's Regalia", "armor", "armor", "legendary",
     {"def": 22, "hp": 90, "speed": 10}, "Worn by the one who finally said no."),
    ("frosthollow_crown", "Frosthollow Crown", "armor", "armor", "legendary",
     {"def": 20, "mp": 90, "mp_regen": 1.0}, "Cold enough to be a defence."),
    ("wrens_locket", "Wren's Locket", "accessory", "accessory", "legendary",
     {"hp": 100, "def": 10, "speed": 12}, "She threw it to you on the stairs."),
    ("new_dawn_band", "Band of the New Dawn", "accessory", "accessory", "legendary",
     {"atk": 12, "def": 12, "hp": 40, "mp": 40}, "Made from the ring that started all this."),
    ("ashen_choir_heart", "Ashen Choir Heart", "accessory", "accessory", "legendary",
     {"lifesteal": 0.15, "hp": 60}, "It never stopped singing. Now it sings for you."),

    # ---------------- MATERIALS / TROPHIES (the Fetch-quest economy) -------
    # No stats, so no budget cost; value is what makes them worth carrying and
    # what the shops buy. Each one drops from a specific monster family.
    ("slime_gel", "Slime Gel", "material", "", "common", {}, "Sticky, faintly warm, sells fine."),
    ("emberling_ember", "Emberling Ember", "material", "", "common", {}, "A coal that stays lit in your pocket."),
    ("ash_shard", "Ash Shard", "material", "", "common", {}, "Sharpened volcanic glass. Everywhere out here."),
    ("bone_fragment", "Bone Fragment", "material", "", "common", {}, "Old. Longer than a person's."),
    ("torn_cloth", "Torn Cloth", "material", "", "common", {}, "Choir vestments, mostly. Ashport buys them."),
    ("grain_sack", "Sack of Grain", "material", "", "common", {}, "Oakstead's mill still turns."),
    ("cave_moss", "Cave Moss", "material", "", "common", {}, "Glows faintly. Alchemists argue about why."),
    ("scrap_iron", "Scrap Iron", "material", "", "common", {}, "Held together by rust and hope."),
    ("goblin_fang", "Goblin Fang", "material", "", "uncommon", {}, "Worn as a necklace by someone who no longer needs it."),
    ("raider_insignia", "Raider Insignia", "material", "", "uncommon", {}, "Barrens scouts wear these. Cinderhold pays for them."),
    ("shaman_charm", "Shaman Charm", "material", "", "uncommon", {}, "It hums when the Choir is near."),
    ("frost_crystal", "Frost Crystal", "material", "", "uncommon", {}, "Cold that does not melt."),
    ("scorched_relic", "Scorched Relic", "material", "", "uncommon", {}, "Somebody's act of faith, twice burned."),
    ("fetid_gland", "Fetid Gland", "material", "", "uncommon", {}, "Sells better than it smells. Barely."),
    ("choir_sigil", "Choir Sigil", "material", "", "rare", {}, "Proof of rank in the Ashen Choir."),
    ("warden_steel_ingot", "Warden-Steel Ingot", "material", "", "rare", {}, "Skyreach alloy. Rationed for forty years."),
    ("emberglass_shard", "Emberglass Shard", "material", "", "rare", {}, "Cut from the Slagworks' own floor."),
    ("rime_core", "Rime Core", "material", "", "rare", {}, "The heart of a thing that lived in the ice."),
    ("hollow_relic", "Hollow Relic", "material", "", "mythical", {}, "From the Crypts. It remembers your name."),
    ("vessel_shard", "Vessel Shard", "material", "", "mythical", {}, "A splinter of someone groomed to be a god."),
    ("choir_ledger", "Choir Ledger", "material", "", "mythical", {}, "Names, dates, and what was done to them."),
    ("warden_core", "Warden Core", "material", "", "legendary", {}, "The Warden's binding, cut loose at last."),
    ("first_flame", "The First Flame", "material", "", "legendary", {}, "Whatever lit the Slagworks. Still lit."),

    # ---------------- more gear, filling the tiers -------------------------
    ("bonecrusher_maul", "Bonecrusher Maul", "weapon", "weapon", "common", {"atk": 3, "crit": 0.02}, "Crypt-issue. Blunt on purpose."),
    ("slingshot", "Bone Slingshot", "weapon", "weapon", "common", {"atk": 2, "speed": 3}, "For children, and for slimes."),
    ("quilted_cap", "Quilted Cap", "armor", "armor", "common", {"def": 2, "hp": 6}, "Better than a bare head."),
    ("hide_wraps", "Hide Wraps", "armor", "armor", "common", {"def": 2}, "Wrapped until the swelling went down."),
    ("tin_ring", "Tin Ring", "accessory", "accessory", "common", {"def": 1, "mp": 6}, "Worthless. Sentimental."),
    ("dried_meat", "Dried Meat", "consumable", "", "common", {}, "Restores 20 HP. Chewy."),
    ("scout_trappings", "Scout's Trappings", "armor", "armor", "uncommon", {"def": 4, "speed": 10}, "Cut for running. You will run."),
    ("shaman_wrap", "Shaman's Wrap", "armor", "armor", "uncommon", {"def": 3, "mp": 22}, "Frosthollow wool, blessed in a way you can't verify."),
    ("dungeoneers_helm", "Dungeoneer's Helm", "armor", "armor", "uncommon", {"def": 6, "hp": 8}, "A lamp bracket, mostly."),
    ("pickpockets_ring", "Pickpocket's Ring", "accessory", "accessory", "uncommon", {"speed": 9, "crit": 0.04}, "Sized for someone else's finger."),
    ("smugglers_satchel", "Smuggler's Satchel", "accessory", "accessory", "uncommon", {"hp": 18, "speed": 4}, "False bottom, obviously."),
    ("elixir_of_iron", "Elixir of Iron", "consumable", "", "uncommon", {}, "Tastes like a forge. Restores 40 HP and 40 MP."),
    ("warden_pike", "Warden Pike", "weapon", "weapon", "rare", {"atk": 12, "def": 4}, "Formation weapon. One person can hold a stair."),
    ("choir_stiletto", "Choir Stiletto", "weapon", "weapon", "rare", {"atk": 10, "crit": 0.13}, "Made for a rite that required no noise."),
    ("slagplate_greaves", "Slagplate Greaves", "armor", "armor", "rare", {"def": 9, "hp": 25}, "Walk through the slag. Slowly."),
    ("archivists_spectacles", "Archivist's Spectacles", "accessory", "accessory", "rare", {"mp": 30, "mp_regen": 0.6}, "Let you read what the Choir wanted forgotten."),
    ("greater_elixir", "Greater Elixir", "consumable", "", "rare", {}, "Restores 150 HP and 90 MP."),
    ("vessels_judgement", "Vessel's Judgement", "weapon", "weapon", "mythical", {"atk": 19, "def": 5, "mp": 25}, "It was meant for Wren. It answered to you."),
    ("cryptwarden_shield", "Cryptwarden Shield", "armor", "armor", "mythical", {"def": 20, "hp": 65}, "The Crypts' own door, cut down to fit an arm."),
    ("skyrunners_anklet", "Skyrunner's Anklet", "accessory", "accessory", "mythical", {"speed": 30, "hp": 20}, "Citadel couriers wear these up the switchbacks."),
    ("ward_of_ash", "Ward of Ash", "consumable", "", "rare", {},
     "Halves the damage you take for 10s. Something in it is still warm."),
    ("phoenix_elixir", "Phoenix Draught", "consumable", "", "mythical", {},
     "Restores 320 HP. If you fall while it is in your pack, it burns instead of you."),
    ("dawnbreaker", "Dawnbreaker", "weapon", "weapon", "legendary", {"atk": 31, "crit": 0.14, "hp": 30}, "It only rises once a day. You only need it once."),
    ("aegis_of_millhaven", "Aegis of Millhaven", "armor", "armor", "legendary", {"def": 26, "hp": 105}, "The camp's fire, and everyone who warmed at it."),]

CONSUMABLE_NAMES = {}


def weighted(stats: dict) -> float:
    return sum(abs(float(v)) * WEIGHT[k] for k, v in stats.items())


def main() -> None:
    out = collections.OrderedDict()
    out["_comment"] = (
        "Item catalogue. `rarity` is a strict power ordering: common < uncommon < "
        "rare < mythical < legendary, each with a weighted stat budget enforced by "
        "tests/items_test.gd. `lifesteal` is a fractional heal-per-damage-dealt and "
        "appears ONLY on rare-or-better items, and only as a chance affix rolled at "
        "drop time. Stats are read directly by GameState.equipment_bonus()."
    )
    items = collections.OrderedDict()
    for iid, name, itype, slot, rarity, stats, desc in ITEMS:
        entry = collections.OrderedDict()
        entry["name"] = name
        entry["rarity"] = rarity
        entry["type"] = itype
        if slot:
            entry["slot"] = slot
        if itype == "consumable":
            heal, mana = _consumable_effect(iid)
            if heal:
                entry["heal"] = heal
            if mana:
                entry["restore_mp"] = mana
            # Effects that are not a one-shot heal: a timed buff the player
            # applies through GameState.use_item(), or a save-the-player-once
            # trigger. Written verbatim so the data always matches the code.
            for k, v in _consumable_buff(iid).items():
                entry[k] = v
            entry["stack"] = 10
        else:
            for k in ("atk", "def", "hp", "mp", "speed", "mp_regen", "crit", "lifesteal"):
                if k in stats:
                    entry[k] = stats[k]
            entry["stack"] = 1
        entry["value"] = _price(rarity, itype, stats)
        entry["desc"] = desc
        items[iid] = entry
    out["items"] = items
    out["rarity_order"] = ["common", "uncommon", "rare", "mythical", "legendary"]
    out["rarity_budget"] = BUDGET

    path = os.path.join(ROOT, "data", "items.json")
    with open(path, "w") as f:
        json.dump(out, f, indent=2)
        f.write("\n")

    # --- self-check: budgets and a strict power ordering ---------------------
    tier_totals = {r: [] for r in BUDGET}
    gear_totals = {r: [] for r in BUDGET}
    offenders = []
    for iid, entry in items.items():
        r = entry["rarity"]
        gear = entry["type"] in ("weapon", "armor", "accessory")
        # Consumables and materials carry no power ladder: their worth is the
        # effect they trigger once, not a stat line. Counting a timed buff
        # (mp_regen, speed) against a gear budget is meaningless.
        used = weighted({k: entry[k] for k in WEIGHT if k in entry}) if gear else 0.0
        tier_totals[r].append(used)
        if gear:
            gear_totals[r].append(used)
        if used > BUDGET[r] + 0.001:
            offenders.append((iid, r, round(used, 1), BUDGET[r]))
        if "lifesteal" in entry and r in ("common", "uncommon"):
            offenders.append((iid, "lifesteal on " + r, entry["lifesteal"], 0))
    if offenders:
        raise SystemExit("BUDGET VIOLATIONS: %s" % offenders)

    order = ["common", "uncommon", "rare", "mythical", "legendary"]
    # The real power ordering is over EQUIPMENT: materials/consumables carry no
    # stats, so including them would dilute a tier's average and hide a genuine
    # inversion between two gear tiers.
    avgs = {r: (sum(v) / len(v) if v else 0.0) for r, v in gear_totals.items()}
    for a, b in zip(order, order[1:]):
        if avgs[a] >= avgs[b]:
            raise SystemExit("ORDERING BROKEN: %s (%.1f) >= %s (%.1f)" % (a, avgs[a], b, avgs[b]))

    by_rarity = {r: len(v) for r, v in tier_totals.items()}
    print("wrote %s with %d items" % (path, len(items)))
    print("  per rarity:", by_rarity)
    print("  avg equipment power:", {r: round(avgs[r], 1) for r in order})
    print("  lifesteal items:", sum(1 for e in items.values() if "lifesteal" in e))


def _consumable_buff(iid: str) -> dict:
    """Timed/triggered effects, keyed by item id.

    `speed_mult` / `shield` / `mp_regen` are multipliers or rates applied for
    `duration` seconds; `revive` arms a one-shot revive in the player. Kept in
    the generator so an item's text and its mechanics are written together.
    """
    table = {
        "elixir_of_haste": {"speed_mult": 1.3, "duration": 10.0},
        "ironskin_tonic": {"shield": 0.35, "duration": 12.0},
        "focus_draught": {"mp_regen": 8.0, "duration": 12.0},
        "ward_of_ash": {"shield": 0.5, "duration": 10.0},
        "phoenix_elixir": {"revive": True},
    }
    return dict(table.get(iid, {}))


def _consumable_effect(iid: str):
    table = {
        "health_potion": (40, 0), "bread": (15, 0), "bandage": (25, 0),
        "greater_health_potion": (90, 0), "chilled_greater_potion": (180, 0),
        "mana_potion": (0, 30), "greater_mana_potion": (0, 70),
        "elixir_of_haste": (0, 0), "dried_meat": (20, 0),
        "ironskin_tonic": (0, 0), "focus_draught": (0, 0), "ward_of_ash": (0, 0),
        "elixir_of_iron": (40, 40), "greater_elixir": (150, 90),
        "phoenix_elixir": (320, 0),
    }
    return table.get(iid, (0, 0))


## Phase F7: prices are derived, not hand-picked. A tier's median price is a
## fraction of one level's kill income at the level that tier unlocks (see
## tools/player_model.py), so the shelf always keeps up with what the player
## earns; the stat term keeps the best-in-tier item more expensive than the
## median, which is what makes the last few points of budget feel expensive.
CONSUMABLE_TIER = {"common": 1, "uncommon": 2, "rare": 4, "mythical": 6,
                   "legendary": 6}
## Materials are trophies, not power: they price off the consumable curve of
## their band, so hauling twenty of them is pocket money rather than a fortune,
## and the quests that ask for them stay worth running.
MATERIAL_MULT = {"common": 3, "uncommon": 3, "rare": 3, "mythical": 3, "legendary": 6}


def _price(rarity: str, itype: str, stats: dict) -> int:
    if itype == "consumable":
        return player_model.consumable_price(CONSUMABLE_TIER.get(rarity, 1))
    if itype == "material":
        return player_model.consumable_price(CONSUMABLE_TIER.get(rarity, 1)) \
            * MATERIAL_MULT.get(rarity, 3)
    base = player_model.median_price(rarity)
    return base + int(weighted(stats) * 1.4)


if __name__ == "__main__":
    main()
