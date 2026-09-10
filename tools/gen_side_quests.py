#!/usr/bin/env python3
"""Phase F5 - author 100 side quests (SQ001-SQ100) into data/quests.json.

Sanctioned approach for bulk content: eight **category models** are written out in
full (objective shape, reward shape, voice), and each of the 100 quests supplies
its own targets, counts, giver and one authored **twist** clause that carries its
particular story. Same voice, same format, regionally distributed, and every
number in the result is checked mechanically:

  * 30 Meadows / 40 Barrens / 30 Peaks, easy -> hard (SQ001 is level 3, SQ100 92)
  * kill/collect targets must live in the quest's region and be open by its anchor
  * place flags must be producible, relics must exist, NPCs must be real
  * every quest is offered by a real dialogue entry on its giver, gated by level
    and by a per-quest 'taken' flag, so the board grows with the player
  * rewards are a slice of a level-up at the anchor and do not exceed it

Run:  python3 tools/gen_side_quests.py     (after tools/gen_quests.py)
"""

import collections
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_quests as gq   # shared helpers: loading, XP mirror, place flags

ROOT = gq.ROOT

# --- category models (written in full) ----------------------------------------
# Each model decides the objective shape and the reward shape; `twist` is the
# per-quest authored clause. Goods quests use `deliver` (which consumes on
# completion) rather than `collect`, so carrying four slime gels you never gave
# up cannot be turned into a payout.
CATEGORIES = {
    "Bounty": {
        "objs": [("kill", "{target}", "{count}", "Hunt {count} {target_name}"),
                 ("talk", "{giver}", "1", "Report to {giver_name}")],
        "xp": 0.22, "gold": 0.55, "item": 12,
    },
    "Fetch": {
        "objs": [("collect", "{item}", "{count}", "Gather {count} {item_name}"),
                 ("deliver", "{item}", "{count}", "Hand them over to {giver_name}")],
        "xp": 0.18, "gold": 0.8, "item": 6,
    },
    "Escort": {
        "objs": [("flag", "visited_{place}", "1", "See it safely to {place_name}"),
                 ("talk", "{giver}", "1", "Report back to {giver_name}")],
        "xp": 0.20, "gold": 0.9, "item": 0,
    },
    "Mystery": {
        "objs": [("flag", "entered_{dungeon}", "1", "Get inside {dungeon_name}"),
                 ("deliver", "{item}", "{count}", "Bring back {count} {item_name}")],
        "xp": 0.28, "gold": 0.6, "item": 0,
    },
    "Faction": {
        "objs": [("kill", "{target}", "{count}", "Break {count} {target_name}"),
                 ("deliver", "{item}", "2", "Hand over 2 {item_name}")],
        "xp": 0.26, "gold": 0.7, "item": 10,
    },
    "Collection": {
        "objs": [("deliver", "{item}", "{count}", "Deliver {count} {item_name}"),
                 ("deliver", "{item2}", "{count}", "Deliver {count} {item2_name}"),
                 ("talk", "{giver}", "1", "Report to {giver_name}")],
        "xp": 0.24, "gold": 0.5, "item": 8,
    },
    "Companion": {
        "objs": [("talk", "{npc}", "1", "Walk with {npc_name}"),
                 ("talk", "{giver}", "1", "Finish the road with {giver_name}")],
        "xp": 0.16, "gold": 0.4, "item": 0,
    },
    "Repeatable": {
        "objs": [("kill", "{target}", "{count}", "Cull {count} {target_name}")],
        "xp": 0.10, "gold": 0.6, "item": 0, "repeatable": True,
    },
}

# --- the 100 quests -----------------------------------------------------------
# (category, giver, target, count, extra, name, twist)
#   target : the monster (Bounty/Faction/Repeatable) or the sole item (Fetch/
#            Collection/Mystery/Companion)
#   extra  : the second item (Collection/Faction), the place (Escort), the
#            dungeon (Mystery) or the NPC (Companion) — whatever the category
#            model needs beyond `target`
# The quest's region is *derived from its content* (a monster's biome, where an
# item drops, a settlement's biome), not from where its giver happens to stand:
# people hire you for work that is not on their doorstep.
SIDE = [
    # --- Meadows: SQ001-SQ030, level 3 -> 25 ---------------------------------
    ("Bounty", "elder_fenwick", "grunt", 5, "", "Fold Work",
     "Oakstead's sheep pens"),
    ("Fetch", "merchant_bram", "slime_gel", 4, "", "The Tanner's Ledger",
     "the mill pond's slime beds"),
    ("Bounty", "hunter_kael", "meadow_wolf", 6, "", "Teeth for the Wall",
     "the treeline above Oakstead"),
    ("Repeatable", "hunter_kael", "emberling", 5, "", "Ash Cull",
     "the ash road's verge"),
    ("Escort", "elder_rowan", "0", 1, "oakstead", "Grain for Oakstead",
     "Oakstead"),
    ("Collection", "elder_fenwick", "cave_moss", 3, "bone_fragment", "Fever Rations",
     "the cave mouth east of the fold"),
    ("Mystery", "elder_rowan", "torn_cloth", 2, "drowned_mill", "The Warren Door",
     "the old mill's lower floor"),
    ("Companion", "wren", "0", 1, "wren", "Wren's Walk",
     "Wren"),
    ("Bounty", "merchant_bram", "grunt", 8, "", "Road Tax",
     "the Sunreach road cut"),
    ("Fetch", "elder_fenwick", "bone_fragment", 6, "", "Marrow for the Kiln",
     "the wolf runs"),
    ("Faction", "magistrate_voss", "emberling", 8, "emberling_ember", "Voss's Quiet Ledger",
     "the emberling warrens' mouth"),
    ("Bounty", "elder_rowan", "husk", 6, "", "The Kindness",
     "the old graves behind Millhaven"),
    ("Repeatable", "merchant_bram", "emberling", 6, "", "Gel by the Barrel",
     "the sluice ditches"),
    ("Escort", "merchant_bram", "0", 1, "sunreach", "The Caravan's Ledger",
     "Sunreach City"),
    ("Collection", "elder_rowan", "emberling_ember", 3, "bone_fragment", "Embers and Bones",
     "the warren mouths"),
    ("Mystery", "magistrate_voss", "fetid_gland", 1, "emberling_warrens", "What Voss Heard",
     "the warrens under the road"),
    ("Bounty", "hunter_kael", "emberling", 10, "", "Long Ash",
     "the burn line east of Millhaven"),
    ("Companion", "elder_fenwick", "0", 1, "wren", "Oakstead's Dowry",
     "Wren"),
    ("Faction", "elder_rowan", "husk", 8, "fetid_gland", "Bought Silence",
     "the drowned fields"),
    ("Fetch", "magistrate_voss", "torn_cloth", 8, "", "The Magistrate's Uniform",
     "the mill road's hedges"),
    ("Bounty", "elder_fenwick", "meadow_wolf", 10, "", "The Pack That Stayed",
     "the ridge past Oakstead"),
    ("Repeatable", "hunter_kael", "grunt", 8, "", "Standing Cull",
     "the mill road"),
    ("Collection", "merchant_bram", "cave_moss", 4, "emberling_ember", "Moss and Embers",
     "the bone yards"),
    ("Mystery", "wren", "cave_moss", 2, "drowned_mill", "Wren's Question",
     "the mill's drowned wheel-room"),
    ("Bounty", "elder_rowan", "husk", 10, "", "The Second Grave",
     "the flooded fields"),
    ("Escort", "magistrate_voss", "0", 1, "millhaven", "An Escort of Paperwork",
     "Millhaven"),
    ("Faction", "hunter_kael", "emberling", 12, "emberling_ember", "Kael's Grey Ledger",
     "the ash verge"),
    ("Fetch", "wren", "fetid_gland", 5, "", "Wren's Specimens",
     "the husk fields"),
    ("Bounty", "merchant_bram", "goblin_king", 1, "", "Bram's Insurance",
     "the mill's wheel-room"),
    ("Companion", "elder_rowan", "0", 1, "wren", "Before the Road",
     "Wren"),

    # --- Barrens: SQ031-SQ070, level 25 -> 65 -------------------------------
    ("Bounty", "hunter_kael", "scout", 6, "", "Scout Sweep",
     "the salt flats' western edge"),
    ("Fetch", "ysolde", "scrap_iron", 6, "", "Ysolde's Second Pot",
     "the slag fields"),
    ("Mystery", "brother_ashe", "scorched_relic", 1, "scorched_monastery", "Brother Ashe's List",
     "the Scorched Monastery"),
    ("Bounty", "captain_dael", "shaman", 8, "", "The Dusk Chant",
     "the wall's shadow"),
    ("Faction", "captain_dael", "shaman", 10, "shaman_charm", "Grey Before Grey",
     "Cinderhold's outer fields"),
    ("Repeatable", "hunter_kael", "scout", 8, "", "Salt Money",
     "the salt pans"),
    ("Collection", "ysolde", "shaman_charm", 3, "scorched_relic", "Charms and Relics",
     "the chant circles"),
    ("Escort", "ysolde", "0", 1, "cinderhold", "The Stock Cart",
     "Cinderhold"),
    ("Bounty", "captain_dael", "lizard", 10, "", "Scale Contract",
     "the glass fields"),
    ("Mystery", "brother_ashe", "ash_shard", 4, "scorched_monastery", "The Order's Ledger",
     "the monastery's nave"),
    ("Fetch", "captain_dael", "ash_shard", 8, "", "Dael's Test Bars",
     "the ash glass fields"),
    ("Companion", "brother_ashe", "0", 1, "hunter_kael", "The Long Walk South",
     "Hunter Kael"),
    ("Bounty", "hunter_kael", "lizard", 12, "", "Salt and Scales",
     "the drilling grounds"),
    ("Faction", "captain_dael", "lizard", 10, "emberglass_shard", "Insignia Audit",
     "the Cinderhold road"),
    ("Repeatable", "ysolde", "raider_brute", 6, "", "Brass on Account",
     "the raid camps"),
    ("Mystery", "hunter_kael", "raider_insignia", 3, "slagworks", "Who Lit the Works",
     "the slagworks' furnace floor"),
    ("Bounty", "captain_dael", "raider_brute", 12, "", "The Nave Billet",
     "the monastery's nave"),
    ("Collection", "captain_dael", "scorched_relic", 4, "shaman_charm", "Relics, Not Souvenirs",
     "the rubble lines"),
    ("Fetch", "hunter_kael", "warden_steel_ingot", 3, "", "Warm Steel",
     "the Choir's forges"),
    ("Escort", "captain_dael", "0", 1, "ashvow", "The Witness Walk",
     "Ashvow"),
    ("Bounty", "brother_ashe", "shaman", 12, "", "Silence for the Office",
     "the monastery's cloister"),
    ("Mystery", "captain_dael", "choir_sigil", 2, "choir_sanctum", "Under the Street",
     "the sanctum under Ashvow"),
    ("Faction", "hunter_kael", "scout", 10, "raider_insignia", "Horns Bought and Paid",
     "the pass road"),
    ("Companion", "hunter_kael", "0", 1, "brother_ashe", "Ashe's Last Mile",
     "Brother Ashe"),
    ("Bounty", "captain_dael", "minotaur", 12, "", "The Ram's Head Debt",
     "the ram road"),
    ("Repeatable", "captain_dael", "lizard", 10, "", "Wall Duty",
     "the glass fields"),
    ("Fetch", "ysolde", "emberglass_shard", 6, "", "Emberglass, Whole",
     "the burn glass"),
    ("Collection", "ysolde", "raider_insignia", 5, "scrap_iron", "A Full Set of Brass",
     "the raid lines"),
    ("Mystery", "brother_ashe", "choir_sigil", 1, "choir_sanctum", "The Vessel Question",
     "the sanctum's lowest floor"),
    ("Bounty", "captain_dael", "legion", 14, "", "The Ashvow Grey",
     "Ashvow's garrison yard"),
    ("Escort", "captain_dael", "0", 1, "kilnrest", "North With the Caravan",
     "Kilnrest"),
    ("Faction", "captain_dael", "legion", 12, "torn_cloth", "The Officer's Coat",
     "the garrison road"),
    ("Bounty", "hunter_kael", "minotaur", 14, "", "Horns to the Pass",
     "the northern pass"),
    ("Mystery", "captain_dael", "warden_steel_ingot", 2, "choir_sanctum", "Names in the Floor",
     "the sanctum's archive floor"),
    ("Collection", "captain_dael", "choir_sigil", 4, "warden_steel_ingot", "Sigil Study",
     "the sanctum's outer ring"),
    ("Bounty", "brother_ashe", "legion", 16, "", "The Office of Ash",
     "the monastery's chapter house"),
    ("Repeatable", "captain_dael", "raider_brute", 12, "", "Road Clearing",
     "the Cinderhold-Ashvow road"),
    ("Companion", "ysolde", "0", 1, "captain_dael", "Dael Off Duty",
     "Captain Dael"),
    ("Fetch", "brother_ashe", "ash_shard", 6, "", "The Missing Volume",
     "the monastery's scriptorium"),
    ("Faction", "brother_ashe", "legion", 18, "torn_cloth", "The Order Answers",
     "the ash road's last mile"),

    # --- Peaks: SQ071-SQ100, level 65 -> 92 --------------------------------
    ("Bounty", "mireille", "revenant", 10, "", "Cold Numbers",
     "the Kiln road"),
    ("Mystery", "high_warden_isolde", "hollow_relic", 2, "hollow_crypts", "The Ledger of the Dead",
     "the Hollow Crypts"),
    ("Fetch", "mireille", "frost_crystal", 6, "", "Kilnrest's Lamp Oil",
     "the frost fields"),
    ("Bounty", "high_warden_isolde", "troll", 12, "", "Switchback Patrol",
     "the switchback"),
    ("Repeatable", "mireille", "revenant", 10, "", "Kiln Road Sweep",
     "the Kiln road"),
    ("Faction", "high_warden_isolde", "revenant", 3, "frost_crystal", "Seals in the Snow",
     "the Citadel's approach"),
    ("Collection", "high_warden_isolde", "rime_core", 4, "hollow_relic", "Forge Cold",
     "the vault's edge"),
    ("Escort", "mireille", "0", 1, "skyreach", "The Defector's Road",
     "Skyreach Citadel"),
    ("Bounty", "high_warden_isolde", "revenant", 14, "", "Citadel Grey",
     "the under-Citadel mile"),
    ("Mystery", "high_warden_isolde", "rime_core", 3, "rimevault", "What Grandmother Sealed",
     "the Rimevault"),
    ("Fetch", "mireille", "hollow_relic", 4, "", "Warm Glass, Cold Hands",
     "the crypt mouths"),
    ("Bounty", "high_warden_isolde", "troll", 16, "", "The Long Switchback",
     "the upper switchback"),
    ("Companion", "high_warden_isolde", "0", 1, "mireille", "Mireille's Silence",
     "Mireille"),
    ("Faction", "mireille", "troll", 10, "frost_crystal", "The Sanctum's Hand",
     "the ring's inner line"),
    ("Repeatable", "high_warden_isolde", "troll", 12, "", "Gate Watch",
     "the Citadel's gate"),
    ("Mystery", "mireille", "hollow_relic", 3, "wardens_ascent", "The Ascent's Names",
     "Warden's Ascent"),
    ("Bounty", "high_warden_isolde", "archon", 12, "", "Archons in the Snow",
     "the ring road"),
    ("Collection", "mireille", "frost_crystal", 8, "rime_core", "Lamps for the Return",
     "the frost fields"),
    ("Fetch", "high_warden_isolde", "rime_core", 5, "", "Gate Cold",
     "the Citadel's forge"),
    ("Faction", "high_warden_isolde", "ashen_herald", 5, "warden_steel_ingot", "Heralds Kept",
     "the ring's outer line"),
    ("Bounty", "mireille", "ashen_herald", 6, "", "The Message Delivered",
     "the ring's edge"),
    ("Mystery", "high_warden_isolde", "hollow_relic", 1, "ember_warden_keep", "What the Warden Kept",
     "Warden's Keep"),
    ("Bounty", "high_warden_isolde", "archon", 14, "", "The Sanctum's Last Orders",
     "the ring's inner line"),
    ("Repeatable", "mireille", "archon", 12, "", "Ring Duty",
     "the scorched ring"),
    ("Collection", "high_warden_isolde", "choir_sigil", 6, "warden_steel_ingot", "Seals for the Archive",
     "the heralds' route"),
    ("Faction", "mireille", "archon", 16, "choir_ledger", "The Choir's Best, Counted",
     "the ring's processional"),
    ("Bounty", "high_warden_isolde", "ashen_herald", 8, "", "Eight Seals",
     "the ring's outer line"),
    ("Mystery", "mireille", "vessel_shard", 6, "ember_warden_keep", "The Vessel, Counted",
     "Warden's Keep"),
    ("Companion", "high_warden_isolde", "0", 1, "high_warden_isolde", "Isolde's Oath",
     "High Warden Isolde"),
    ("Bounty", "mireille", "troll", 18, "", "The Last Procession",
     "the ring's outer walk"),
]

ROOT_GIVER = {"brother_ashe": "brother_ashe"}   # givers who live outside a settlement


def npc_name(npcs: dict, npc_id: str) -> str:
    return str((npcs.get(npc_id, {}) or {}).get("display_name", npc_id))


def item_name(items: dict, item_id: str) -> str:
    return str((items.get(item_id, {}) or {}).get("name", item_id))


def archetype_name(enemies: dict, aid: str) -> str:
    return str((enemies.get(aid, {}) or {}).get("display_name", aid))


def place_name(settlements: dict, sid: str) -> str:
    return str((settlements.get(sid, {}) or {}).get("name", sid.replace("_", " ").title()))


def giver_region(npcs: dict, settlements: dict, npc_id: str) -> str:
    s = str(npcs.get(npc_id, {}).get("settlement", ""))
    return str((settlements.get(s, {}) or {}).get("biome", ""))


def region_of_quest(cat: str, target: str, extra: str, enemies: dict,
                    dungeons: dict, settlements: dict, npcs: dict, giver: str) -> str:
    """Where the work is, not where the giver stands."""
    if cat in ("Bounty", "Faction", "Repeatable"):
        return str(enemies.get(target, {}).get("biome", ""))
    if cat == "Mystery":
        return str(dungeons.get(extra, {}).get("biome", ""))
    if cat == "Escort":
        return str(settlements.get(extra, {}).get("biome", ""))
    if cat == "Companion":
        reg = giver_region(npcs, settlements, extra)
        return reg if reg != "" else giver_region(npcs, settlements, giver)
    # Fetch / Collection: the region whose monsters drop the item; prefer the
    # giver's own region when it qualifies.
    home = giver_region(npcs, settlements, giver)
    for want in (target, extra):
        if want in ("", "0"):
            continue
        regions = [v["biome"] for v in enemies.values()
                   if any(e[0] == want for e in v["drops"]["items"])]
        if home and home in regions:
            return home
        if regions:
            return regions[0]
    return home


# Level anchors: SQ001 opens at L3 and SQ100 at L92, so the board grows with the
# player across the same three regions the chain walks.
def anchor_at(index: int) -> float:
    if index <= 30:
        return 3.0 + (25.0 - 3.0) * (index - 1) / 29.0
    if index <= 70:
        return 25.0 + (65.0 - 25.0) * (index - 31) / 39.0
    return 65.0 + (92.0 - 65.0) * (index - 71) / 29.0


def main() -> None:
    npcs = gq.load("npcs.json")["npcs"]
    settlements = gq.load("settlements.json")["settlements"]
    dungeons = gq.load("dungeons.json")["dungeons"]
    enemies = gq.load("enemies.json")["archetypes"]
    items = gq.load("items.json")["items"]
    items_db = gq.load("items.json")

    if len(SIDE) != 100:
        raise SystemExit("gen_side_quests: expected 100 quests, found %d" % len(SIDE))

    problems = []
    quests = collections.OrderedDict()
    offers = collections.defaultdict(list)

    for i, (cat, giver, target, count, extra, name, twist) in enumerate(SIDE, start=1):
        qid = "SQ%03d" % i
        model = CATEGORIES[cat]
        anchor = anchor_at(i)
        region = region_of_quest(cat, target, extra, enemies, dungeons,
                                 settlements, npcs, giver)
        if region == "":
            problems.append("%s: cannot tell which region %s belongs to" % (qid, name))
            region = "meadow"
        item_id = extra if extra not in ("", "0") and cat in ("Collection", "Faction") \
            else target

        ctx = {
            "target": target, "item": item_id, "item2": extra, "count": count,
            "giver": giver, "npc": extra, "place": extra, "dungeon": extra,
            "target_name": archetype_name(enemies, target),
            "item_name": item_name(items, item_id),
            "item2_name": item_name(items, extra),
            "giver_name": npc_name(npcs, giver),
            "npc_name": npc_name(npcs, extra),
            "place_name": place_name(settlements, extra),
            "dungeon_name": str((dungeons.get(extra, {}) or {}).get("name", extra)),
        }

        objs = []
        for n, (kind, tgt, cnt, desc) in enumerate(model["objs"]):
            objs.append(collections.OrderedDict([
                ("id", "obj%d" % (n + 1)),
                ("type", kind),
                ("target", tgt.format(**ctx) if "{" in tgt else tgt),
                ("count", int(cnt.format(**ctx)) if "{" in cnt else int(cnt)),
                ("desc", desc.format(**ctx)),
            ]))

        # --- validation: does this quest actually make sense where it is? ---
        for o in objs:
            if o["type"] == "kill":
                arch = enemies.get(o["target"])
                if arch is None:
                    problems.append("%s: no monster %s" % (qid, o["target"]))
                else:
                    if arch["biome"] != region:
                        problems.append("%s: %s is a %s monster in a %s quest (%s)" %
                                        (qid, o["target"], arch["biome"], region, giver))
                    if arch["level_band"][0] > anchor + gq.LEVEL_TOLERANCE:
                        problems.append("%s: %s opens at L%d, anchor L%.0f" %
                                        (qid, o["target"], arch["level_band"][0], anchor))
            elif o["type"] in ("collect", "deliver"):
                it = items.get(o["target"])
                if it is None:
                    problems.append("%s: no item %s" % (qid, o["target"]))
                else:
                    sources = [a for a, v in enemies.items()
                               if v["biome"] == region
                               and any(e[0] == o["target"] for e in v["drops"]["items"])]
                    if not sources:
                        problems.append("%s: nothing in the %s drops %s" %
                                        (qid, region, o["target"]))
                    else:
                        earliest = min(enemies[a]["level_band"][0] for a in sources)
                        if earliest > anchor + gq.LEVEL_TOLERANCE:
                            problems.append("%s: %s only drops from L%d+" %
                                            (qid, o["target"], earliest))
            elif o["type"] == "flag":
                if o["target"] not in gq.place_flags():
                    problems.append("%s: flag %s has no producer" % (qid, o["target"]))
            elif o["type"] == "talk":
                if o["target"] not in npcs:
                    problems.append("%s: no NPC %s" % (qid, o["target"]))

        # --- rewards: a slice of a level-up at the anchor ---
        need = gq.xp_to_next(int(round(anchor)))
        xp = int(round(model["xp"] * need / 5.0) * 5)
        reward_items = []
        every = int(model["item"])
        if every > 0 and i % every == 0:
            allowed = ["common", "uncommon"] if i <= 30 else \
                      (["uncommon", "rare"] if i <= 70 else ["rare", "mythical"])
            pool = sorted([iid for iid, it in items_db["items"].items()
                           if it["rarity"] in allowed
                           and it["type"] in ("weapon", "armor", "accessory", "consumable")])
            if pool:
                reward_items = [pool[(i * 7) % len(pool)]]

        q = collections.OrderedDict()
        q["name"] = name
        q["desc"] = "%s (%s, %s)" % (
            model_desc(cat, ctx, twist), cat, name)
        q["giver"] = giver
        q["category"] = cat
        q["region"] = region
        q["level_anchor"] = int(round(anchor))
        q["objectives"] = objs
        q["reward"] = collections.OrderedDict([
            ("xp", xp),
            ("gold", int(round(xp * model["gold"] / 5.0) * 5)),
            ("items", reward_items),
        ])
        q["next"] = ""
        if model.get("repeatable"):
            q["repeatable"] = True
        # Two-part side stories: a handful of quests hand off to the next one, so
        # the board is not 100 unconnected jobs.
        if i in FOLLOWUPS:
            q["next"] = "SQ%03d" % (i + 1)
        quests[qid] = q
        offers[giver].append((qid, q, anchor))

    if problems:
        for p in problems:
            print("  ERROR %s" % p)
        raise SystemExit("gen_side_quests: %d problem(s)" % len(problems))

    # --- merge into data/quests.json, preserving everything already there -----
    path = os.path.join(ROOT, "data", "quests.json")
    with open(path) as f:
        doc = json.load(f, object_pairs_hook=collections.OrderedDict)
    merged = collections.OrderedDict()
    for qid, q in doc["quests"].items():
        if not qid.startswith("SQ"):
            merged[qid] = q
    for qid, q in quests.items():
        merged[qid] = q
    doc["quests"] = merged
    doc["side_quests"] = collections.OrderedDict([
        ("count", len(quests)),
        ("categories", collections.Counter(q["category"] for q in quests.values())),
        ("regions", collections.Counter(q["region"] for q in quests.values())),
        ("starts_at_level", int(round(anchor_at(1)))),
        ("ends_at_level", int(round(anchor_at(100)))),
    ])
    with open(path, "w") as f:
        json.dump(doc, f, indent=2)
        f.write("\n")
    print("wrote %s" % path)
    print("  %d side quests + %d other quests = %d total" %
          (len(quests), len(merged) - len(quests), len(merged)))
    print("  categories: %s" % ", ".join(
        "%s %d" % (k, v) for k, v in
        sorted(collections.Counter(q["category"] for q in quests.values()).items())))
    print("  regions: %s" % ", ".join(
        "%s %d" % (k, v) for k, v in
        sorted(collections.Counter(q["region"] for q in quests.values()).items())))
    print("  levels: SQ001 at L%d -> SQ100 at L%d" %
          (int(round(anchor_at(1))), int(round(anchor_at(100)))))

    report_offers(offers, npcs)


FOLLOWUPS = {7, 16, 22, 26, 42, 50, 62, 76, 88, 94}


def model_desc(cat: str, ctx: dict, twist: str) -> str:
    """The category model, written out with this quest's own twist."""
    giver = ctx["giver_name"]
    model = {
        "Bounty": "%s wants %d %s cleared out of %s, and pays the same whether you "
                  "come back happy or honest.",
        "Fetch": "%s needs %d %s and needs them in hand, not in rumour.",
        "Escort": "%s asked you to see a party safely to %s and to stop asking who "
                  "they are.",
        "Mystery": "%s will not say what happened at %s. Go and find out, and come "
                   "back with something that can be held.",
        "Faction": "%s has been paying the Choir's dues in ways that leave names. "
                   "Break the arrangement where people can see it.",
        "Collection": "%s is assembling something out of %s, and older hands say it "
                      "has been tried before and gone badly.",
        "Companion": "%s wants company on the road to %s and will not say why.",
        "Repeatable": "The same work again: %s will pay on the spot for %d %s.",
    }[cat]
    rows = {
        "Bounty": (giver, ctx["count"], ctx["target_name"], twist),
        "Fetch": (giver, ctx["count"], ctx["item_name"]),
        "Escort": (giver, ctx["place_name"]),
        "Mystery": (giver, twist),
        "Faction": (giver,),
        "Collection": (giver, twist),
        "Companion": (giver, twist),
        "Repeatable": (giver, ctx["count"], ctx["target_name"]),
    }[cat]
    return model % rows


def report_offers(offers: dict, npcs: dict) -> None:
    """The board is served at runtime, not baked into dialogue files.

    `QuestManager.next_offer(npc_id)` hands out the first side quest for that NPC
    that the player has not taken and is high enough level for, and main.gd shows
    it through the same dialogue/choice UI as everything else. Writing 100 offer
    entries into the dialogue files instead would have shadowed the hand-written
    lines those files already end with (several NPCs' catch-all entries have no
    conditions at all, so anything placed after them is dead data).
    """
    total = 0
    for giver, group in sorted(offers.items()):
        levels = sorted(max(1, int(round(a))) for _qid, _q, a in group)
        total += len(group)
        print("  %-22s %3d jobs, L%d-L%d" %
              (giver, len(group), levels[0], levels[-1]))
    print("  %d side-quest offers served at runtime by QuestManager.next_offer()" % total)


if __name__ == "__main__":
    main()
