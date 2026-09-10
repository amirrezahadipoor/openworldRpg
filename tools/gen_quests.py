#!/usr/bin/env python3
"""Phase F4 - author the 100-step main quest chain into data/quests.json.

The chain is *Act 2* of the story: it starts the moment `q1_first_light` is
handed in and runs, step by step, all the way to the scorched ring, where it
hands over to `q2_ember_omen` -> `q3_warden_fall` -> `q4_new_dawn`. Nothing in
that four-beat spine is replaced: the canonical quests keep their ids, their
text, their objectives and their rewards, and `q1_first_light`'s `next` now
points at MQ001 instead of straight at `q2_ember_omen`.

Rules the author holds itself to (and `tests/QuestTest.tscn` re-checks from the
shipped JSON, so a bad edit cannot slip through):

  * ids are MQ001..MQ100, strictly sequential, one continuous path
  * every kill target exists in the monster roster and is reachable in the
    step's region (its level band must be open by the step's level anchor)
  * every collect target is a material dropped by that region's monsters
  * every flag target is produced by the game: `visited_<settlement>` (walking
    into a settlement), `entered_<dungeon>` (taking the stair), `cleared_<dungeon>`
    (killing its boss), or a choice flag raised by dialogue
  * every giver is a real NPC with a briefing dialogue that is actually written
    into data/dialogue/<npc>.json
  * rewards rise with the step's level anchor; the chain totals a full climb

Usage:  python3 tools/gen_quests.py
"""

import collections
import json
import os

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))

# --- the story, in 100 steps --------------------------------------------------
# (region, giver, kind, target, count, name, desc)
# region: the biome the step is played in. Kill/collect targets must belong to
#         that region's roster, and a target's level band must be open by the
#         step's level anchor (plus the tolerance below) - both asserted here and
#         re-asserted by tests/QuestTest.tscn from the shipped JSON.
# kind:   K = kill an archetype    C = collect a material
#         F = reach a place flag   T = talk (story beat, hand-off)
# Every step also gets a "report back to <giver>" talk objective unless its main
# objective is already that conversation.
STEPS = [
    # --- Part I: the ash on the wind (Meadows, steps 1-20) --------------------
    ("meadow", "elder_rowan", "K", "grunt", 4, "Ash on the Wind",
     "Grey flecks on the washing-line. Rowan says it is not woodsmoke, and he "
     "wants the slimes thinned before the village starts asking questions."),
    ("meadow", "elder_rowan", "C", "slime_gel", 3, "Rendered Down",
     "The tanner pays in coin for slime gel, and Rowan wants the stores full "
     "before the frost turns."),
    ("meadow", "wren", "K", "emberling", 5, "What Wren Saw",
     "Your sibling swears the emberlings were walking in a line -- not "
     "scattering, walking -- and asks you to break the column."),
    ("meadow", "wren", "C", "emberling_ember", 4, "Embers in a Jar",
     "Wren wants four emberling embers sealed in a jar, to show Rowan the colour "
     "is wrong."),
    ("meadow", "elder_fenwick", "F", "visited_oakstead", 1, "The Road to Oakstead",
     "Fenwick of Oakstead sent word: the mill road is no longer safe, and the "
     "village wants a sword arm to walk it."),
    ("meadow", "elder_fenwick", "K", "meadow_wolf", 5, "Wolves at the Fold",
     "The wolves have stopped hunting deer and started hunting pens."),
    ("meadow", "elder_fenwick", "C", "cave_moss", 4, "Moss for the Fever",
     "Oakstead's fever wants cave moss, and the caves are full of things that "
     "want it too."),
    ("meadow", "merchant_bram", "C", "bone_fragment", 5, "Bram's Bone Trade",
     "Bram buys bone by the handful and sells it by the finger. He needs a "
     "consignment before the caravan leaves."),
    ("meadow", "elder_rowan", "K", "husk", 6, "The Walking Tired",
     "Something is raising Millhaven's dead badly -- as if it had learned how "
     "from a book, not a rite. Put them down."),
    ("meadow", "elder_rowan", "C", "fetid_gland", 4, "Something Rotten",
     "The glands in the husks are wrong for corpses this fresh. Rowan wants them "
     "on his table before the smell decides anything."),
    ("meadow", "wren", "F", "entered_drowned_mill", 1, "Down the Mill Stair",
     "The mill's lower floor has been open since the sluice broke. Wren will not "
     "go down; you will."),
    ("meadow", "wren", "K", "goblin_king", 1, "Skarn's Crown",
     "A crowned goblin has been sitting in the mill's wheel-room, holding court "
     "over a drowned village."),
    ("meadow", "elder_rowan", "F", "visited_sunreach", 1, "Summons to Sunreach",
     "A sealed writ arrives from Sunreach City. Rowan does not open it; he says "
     "the seal is on the inside."),
    ("meadow", "magistrate_voss", "C", "torn_cloth", 6, "Voss's Inventory",
     "The magistrate will talk about the ash road once the ledger balances, and "
     "the ledger needs six bolts' worth of cloth."),
    ("meadow", "magistrate_voss", "F", "entered_emberling_warrens", 1, "The Warrens Under the Road",
     "Voss admits the warrens under the ash road are not a vermin problem. He "
     "wants to know what they actually are."),
    ("meadow", "elder_rowan", "K", "emberling", 8, "Burn Them Out",
     "The warrens are breathing. Every emberling you leave is a lungful of the "
     "thing coming up the road."),
    ("meadow", "elder_rowan", "C", "emberling_ember", 6, "The Ember Tithe",
     "Six embers, sealed and boxed, for the road wardens' braziers."),
    ("meadow", "merchant_bram", "K", "grunt", 10, "Bram's Standing Order",
     "Bram has a standing order with the tanners and no patience for suppliers "
     "who stop supplying."),
    ("meadow", "elder_fenwick", "K", "meadow_wolf", 8, "The Fold Rebuilt",
     "Oakstead rebuilt the fold where the wolves came through. Fenwick wants the "
     "pack that did it thinned to nothing."),
    ("meadow", "elder_rowan", "T", "elder_rowan", 1, "The Ash Road",
     "Rowan finally opens the writ. Sunreach is sending someone east, and the "
     "road east does not stay in the Meadows."),

    # --- Part II: the Barrens (steps 21-46) ----------------------------------
    ("barrens", "hunter_kael", "F", "visited_ashport", 1, "East to Ashport",
     "Ashport is the last town before the salt flats, and the first one the ash "
     "reached. Kael is waiting at the gate."),
    ("barrens", "hunter_kael", "K", "scout", 6, "Scouts on the Salt",
     "The scouts are ranging further west than raiders ever did, and they are not "
     "carrying loot -- they are carrying orders."),
    ("barrens", "hunter_kael", "C", "raider_insignia", 4, "Insignia of Meat and Iron",
     "Kael wants four insignia off four different brutes. He says two matching "
     "ones will tell him which captain is moving."),
    ("barrens", "ysolde", "C", "scrap_iron", 5, "Ysolde's Stock Pot",
     "Ysolde will trade with anyone who brings iron she can actually melt, and "
     "the slag fields are full of it."),
    ("barrens", "hunter_kael", "F", "entered_slagworks", 1, "The Smokestack",
     "The old smelting works has been lit for three weeks. It has no coal."),
    ("barrens", "hunter_kael", "K", "slag_wraith", 1, "The Wraith in the Slag",
     "Whatever has been feeding the furnace has a shape, and the shape has a "
     "grudge."),
    ("barrens", "captain_dael", "F", "visited_cinderhold", 1, "Cinderhold's Captain",
     "Cinderhold's captain wants the ash road walked by someone who is not one "
     "of her own soldiers -- and she wants a witness."),
    ("barrens", "captain_dael", "K", "shaman", 7, "Silence the Chant",
     "The chanting starts at dusk and the walls answer it. Dael wants it stopped, "
     "not studied."),
    ("barrens", "captain_dael", "C", "shaman_charm", 4, "Charms for the Wall",
     "The charms Dael's smiths copy keep the mortar from singing, but the copies "
     "need originals."),
    ("barrens", "captain_dael", "K", "lizard", 8, "Scale and Sinew",
     "Cinderhold's shields are laced with lizard hide. The lacing is wearing out."),
    ("barrens", "captain_dael", "C", "ash_shard", 6, "Ash Shards",
     "Six ash shards from the glass fields, for Dael's armourer to test a theory."),
    ("barrens", "hunter_kael", "F", "entered_scorched_monastery", 1, "The Monastery Gate",
     "Brother Ashe's order held the Scorched Monastery for eighty years. The gate "
     "is open, which is the first thing wrong with it."),
    ("barrens", "hunter_kael", "K", "raider_brute", 9, "Brutes at the Altar",
     "The brutes have billeted themselves in the nave. Kael finds that obscene on "
     "grounds he refuses to explain."),
    ("barrens", "captain_dael", "C", "scorched_relic", 4, "Relics of the Order",
     "Four relics out of the rubble, before the Choir gets a use out of them."),
    ("barrens", "captain_dael", "K", "shaman", 10, "The Chant Grows",
     "The chant is louder than it was and it is coming from further away. Dael "
     "wants the mouth of it stopped."),
    ("barrens", "captain_dael", "C", "warden_steel_ingot", 3, "Warden Steel",
     "Three ingots of warden steel, still warm, still in Choir hands. Dael wants "
     "to know how they are making it."),
    ("barrens", "hunter_kael", "K", "lizard", 12, "The Salt Beds",
     "Something in the salt beds is drilling. Kael wants the drilling stopped "
     "before it reaches the water."),
    ("barrens", "hunter_kael", "C", "emberglass_shard", 5, "Glass From the Burn",
     "Kael has a buyer for emberglass and, more tellingly, a buyer who is in a "
     "hurry."),
    ("barrens", "ysolde", "C", "raider_insignia", 8, "Brass by Weight",
     "Ysolde buys raider insignia by weight -- brass is brass -- and the Choir's "
     "raiders are carrying more of it than they used to."),
    ("barrens", "ysolde", "K", "lizard", 6, "Hide for the Stalls",
     "Ysolde's awning is lizard hide and the season has eaten through it. She "
     "would rather buy it off a hunter than a tanner."),
    ("barrens", "captain_dael", "K", "minotaur", 6, "Horns on the Road",
     "Cinderhold's road to Ashvow is shut by something with horns and a "
     "reasonable grasp of tactics."),
    ("barrens", "captain_dael", "C", "choir_sigil", 4, "Sigils in the Road Dust",
     "Four Choir sigils off four different beasts. Dael says a sigil on a beast "
     "is a signature."),
    ("barrens", "captain_dael", "F", "visited_ashvow", 1, "Ashvow",
     "Ashvow is where the ash started and where the money still is. Walk in with "
     "your hand off your sword."),
    ("barrens", "hunter_kael", "K", "legion", 8, "The Legion of Ash",
     "The Choir has formed a legion out of people who used to be Cinderhold's. "
     "Kael asks you not to think about their faces."),
    ("barrens", "hunter_kael", "K", "legion", 6, "Grey Coats, Ash Coats",
     "The legion has started wearing Ashvow's colours under the Choir's grey. "
     "Kael wants the grey ones put down where the city can see it."),
    ("barrens", "captain_dael", "K", "raider_brute", 12, "Salt, Ash and Iron",
     "Dael's last sweep of the salt flats before she calls the road lost. She "
     "does not want company and she does not want witnesses left alive."),
    ("barrens", "hunter_kael", "T", "hunter_kael", 1, "What the Insignia Said",
     "The insignia match. Two captains, one order, and the order came from "
     "Ashvow."),

    # --- Part III: the sanctum, and the vessel (steps 47-64) ------------------
    ("barrens", "captain_dael", "F", "entered_choir_sanctum", 1, "Beneath Ashvow",
     "There is a sanctum under the city, and the singing in it keeps time with "
     "the chant you have been killing."),
    ("barrens", "captain_dael", "K", "legion", 10, "Ashvow Burns Twice",
     "Word from the south: Ashvow's own garrison turned. Dael asks for the ones "
     "in Choir grey to be dealt with first."),
    ("barrens", "hunter_kael", "C", "scrap_iron", 8, "Scrap for the Last Forge",
     "Eight loads of scrap for the last forge still working west of Ashvow."),
    ("barrens", "ysolde", "K", "minotaur", 8, "The Ram's Head Road",
     "Ysolde's caravans have stopped coming. She can price a minotaur horn to the "
     "coin and would rather not have to."),
    ("barrens", "hunter_kael", "T", "hunter_kael", 1, "What Kael Kept",
     "Kael finally says the thing he has been walking around: the Choir takes "
     "people to make vessels, and the vessels are why the ash moves."),
    # --- Part III: north, into the cold (steps 53-64) -------------------------
    # Frost monsters wake up late (bone_titan at L58, revenant at L65, archon at
    # L85), so the first northern steps are travel and collecting, and the fights
    # come up the ladder from there.
    ("frost", "wren", "F", "entered_hollow_crypts", 1, "The Hollow Crypts",
     "The crypts predate the Wardens. Wren wants to read what is on the door, and "
     "you would rather be standing next to Wren when it opens."),
    ("frost", "wren", "K", "bone_titan", 1, "Whatever Keeps Accounts",
     "Something in the crypts has been keeping a ledger of the dead for four "
     "hundred years, and it has Wren's name in it."),
    ("frost", "wren", "T", "wren", 1, "Wren's Name",
     "The ledger has Wren's name and a date that has not happened yet. Wren "
     "laughs. You notice Wren's hands are shaking."),
    ("frost", "wren", "C", "hollow_relic", 4, "Hollow Relics",
     "Four hollow relics off the cold ones -- Wren says they are the same metal "
     "as the shards, and Wren is right too often lately."),
    ("frost", "high_warden_isolde", "F", "visited_skyreach", 1, "Skyreach Citadel",
     "The Warden-kin hold Skyreach. They have been expecting someone carrying "
     "warm shards for a long time, and they are not happy about it."),
    ("frost", "high_warden_isolde", "T", "high_warden_isolde", 1, "The Binding",
     "Isolde tells you what a Warden is: a promise made into a person, and a "
     "promise can be broken."),
    ("frost", "high_warden_isolde", "C", "rime_core", 3, "Cores of Old Ice",
     "Three rime cores, so the Citadel's forge can burn cold enough to unmake "
     "warden steel."),
    ("frost", "high_warden_isolde", "F", "entered_rimevault", 1, "The Rimevault",
     "A vault sealed with ice that was once a door. Isolde's grandmother helped "
     "seal it; Isolde wants to know why."),
    ("frost", "high_warden_isolde", "K", "frost_giant", 1, "Jorunn the Frost Giant",
     "A giant has been standing at the vault door since the ash came north. It "
     "has not eaten, and it has not moved."),
    ("frost", "high_warden_isolde", "C", "hollow_relic", 6, "Trophies of the Vault",
     "Six hollow relics out of the vault, all of them older than the door they "
     "were sealed behind."),
    ("frost", "mireille", "F", "visited_kilnrest", 1, "Kilnrest",
     "Mireille asked to meet at Kilnrest rather than at Frosthaven, and chose a "
     "night with no moon for it."),
    ("frost", "mireille", "K", "revenant", 10, "The Kiln Road",
     "Ten revenants on the Kiln road. Mireille walks it every week and has never "
     "once been attacked, which she has stopped mentioning."),

    # --- Part IV: the fork, and the peaks (steps 65-86) -----------------------
    # MQ065 - the expose/protect fork. The choice itself lives in dialogue
    # (data/dialogue/mireille.json); whichever branch is taken raises the same
    # resolution flag, which is what this step's objective waits on.
    ("frost", "mireille", "T", "mireille", 1, "The Defector's Ledger",
     "Mireille was Choir before she was anything else, and the ledger in her "
     "sleeve is the reason she left. What you do with it is up to you."),
    ("frost", "mireille", "C", "frost_crystal", 5, "Five Crystals for the Road",
     "Five frost crystals to re-light the Kilnrest road markers, so the next "
     "caravan can find the town."),
    ("frost", "high_warden_isolde", "K", "troll", 10, "Trolls at the Switchback",
     "The switchback up to Warden's Ascent is held by trolls. Isolde's scouts "
     "counted ten before they stopped counting."),
    ("frost", "high_warden_isolde", "C", "rime_core", 5, "Cold Iron",
     "Five rime cores, for the one forge in the peaks that can still work them."),
    ("frost", "high_warden_isolde", "K", "revenant", 8, "The Old Road North",
     "Isolde is reopening the old road to Warden's Ascent and the revenants have "
     "opinions about it."),
    ("frost", "high_warden_isolde", "K", "troll", 12, "Oaths in the Snow",
     "Skyreach's scouts have not reported in for nine days. Clear whatever is "
     "sitting on their route."),
    ("frost", "high_warden_isolde", "K", "revenant", 10, "The Grey Procession",
     "Ten revenants walking in file, none of them armed, all of them in Citadel "
     "grey. Isolde wants to know what they think they are marching to."),
    ("frost", "high_warden_isolde", "K", "revenant", 12, "The Silent Mile",
     "The mile of road under the Citadel is walked by revenants in Citadel grey. "
     "Isolde wants to know which of her people they were."),
    ("frost", "high_warden_isolde", "C", "frost_crystal", 6, "Ward Stones",
     "Six ward stones for the Citadel gate -- the last six, if the Choir's "
     "archons are counting the same way Isolde is."),
    ("frost", "mireille", "K", "troll", 12, "What Mireille Chose",
     "Mireille is still standing where you left her. Whatever the ledger cost "
     "her, she is paying it now, one troll at a time."),
    ("frost", "mireille", "C", "frost_crystal", 5, "Crystal Debt",
     "Five frost crystals are owed to a woman in Kilnrest who staked Mireille "
     "for a winter and never once asked why she left the Choir."),
    ("frost", "mireille", "C", "rime_core", 6, "Cold Work",
     "Six rime cores, for the cold work of undoing a promise."),
    ("frost", "high_warden_isolde", "F", "entered_wardens_ascent", 1, "Warden's Ascent",
     "The switchback climb to the Citadel's undercroft. Isolde will not walk it; "
     "she says Wardens do not enter each other's graves."),
    ("frost", "high_warden_isolde", "K", "troll", 14, "The Switchback Broken",
     "The switchback has to be broken behind you, and the trolls are in the way "
     "of the picks."),
    ("frost", "mireille", "K", "revenant", 14, "The Long Quiet",
     "Fourteen revenants between the Citadel and the ring. Mireille calls it a "
     "procession, not a patrol."),
    ("frost", "mireille", "K", "revenant", 16, "The Quietest Mile",
     "Sixteen revenants on the last mile. Isolde will want their names, and you "
     "will want to have them."),
    ("frost", "mireille", "C", "hollow_relic", 8, "Hollow Work",
     "Eight hollow relics, to make the door of the ring openable by something "
     "other than the thing inside it."),
    ("frost", "high_warden_isolde", "C", "frost_crystal", 8, "The Citadel's Wards",
     "Eight frost crystals to light the Citadel's gate wards one more time, for "
     "the people who will come back down this road without you."),
    ("frost", "high_warden_isolde", "K", "troll", 16, "The Last Procession",
     "Sixteen trolls on the last of the switchback, with the ring warm underneath "
     "them and the snow steaming off the stone."),
    ("frost", "mireille", "K", "troll", 18, "The Ring Wakes",
     "Eighteen trolls walking a ring they did not draw. Mireille says the Choir "
     "pays them in something she does not want named."),

    # --- Part V: the archons, and the ring (steps 87-100) ---------------------
    ("frost", "mireille", "K", "archon", 8, "The Choir's Best",
     "Archons answer to the sanctum and to nothing else. Mireille says that means "
     "someone in the sanctum is still giving orders."),
    ("frost", "mireille", "K", "archon", 6, "The Sanctum's Orders",
     "Six archons carrying sealed orders in the sanctum's own hand. Mireille "
     "wants one of those seals intact, and wants it more than she wants sleep."),
    ("frost", "mireille", "C", "choir_ledger", 5, "Names into Light",
     "Five more ledgers, so the names of the taken survive the people who took "
     "them."),
    ("frost", "high_warden_isolde", "C", "warden_steel_ingot", 5, "Replacing What Was Lost",
     "Five ingots of warden steel, drawn from the Choir's own store, to reforge "
     "the Citadel's broken gate."),
    ("frost", "high_warden_isolde", "C", "choir_ledger", 4, "Ledgers for the Archive",
     "Four more of the Choir's ledgers, for the archive wing that is only opened "
     "for endings."),
    ("frost", "mireille", "C", "vessel_shard", 8, "Eight Shards, One Vessel",
     "Eight shards of the vessel the Choir has been building since the ash "
     "started falling. Mireille will not hold them."),
    ("frost", "high_warden_isolde", "K", "ashen_herald", 5, "Five Heralds Left",
     "Five heralds left, and every one of them is carrying the Warden's seal."),
    ("frost", "mireille", "K", "archon", 10, "Archons at the Door",
     "Ten archons standing in a ring around the scorched ground. They are not "
     "guarding it. They are waiting for it."),
    ("frost", "high_warden_isolde", "K", "ashen_herald", 3, "Three Heralds",
     "Three Ashen Heralds, all carrying the same sealed order, all addressed to "
     "you by name."),
    ("frost", "high_warden_isolde", "F", "entered_ember_warden_keep", 1, "Warden's Keep",
     "The scorched ring, and under it the keep where the first promise is still "
     "being kept. Isolde's last order is one word: descend."),
    ("frost", "high_warden_isolde", "K", "archon", 14, "Ash, Snow and Silence",
     "Fourteen archons between you and the stair down. Nobody is singing now."),
    ("frost", "high_warden_isolde", "C", "choir_sigil", 6, "Seals and Sigils",
     "Six Choir sigils, unbroken, for the Citadel's archive. The archive has a "
     "wing that is only opened for endings."),
    ("frost", "mireille", "K", "ashen_herald", 6, "Heralds of the End",
     "Six heralds, and the last one has stopped moving its lips, because the "
     "message has been delivered."),
    ("frost", "mireille", "C", "rime_core", 8, "The Cold That Remembers",
     "Eight rime cores to hold open a door that was sealed warm and has hated it "
     "ever since."),
    ("frost", "high_warden_isolde", "C", "warden_steel_ingot", 6, "Ingots for the Return Road",
     "Six ingots left at the citadel, so the road back is a road and not a walk "
     "into nothing."),
    ("frost", "elder_rowan", "T", "elder_rowan", 1, "The Warden's Answer",
     "You climb back into the snow at the scorched ring with the ledger, the "
     "shards and the word 'vessel' in your mouth. Rowan is waiting at the edge of "
     "the burn, and he already knows what you are going to say."),
]

# --- reward curve -------------------------------------------------------------
# A step's level anchor walks L1 -> L92 across the chain. Its XP reward is a
# fraction of the level-up cost AT that anchor -- the same curve GameState uses
# (80*L^1.8 early, then the anchored mid/late segments), so a chain step is worth
# a fixed slice of a level wherever you are and never blows the curve open.
XP_BASE, XP_E1, XP_E2, XP_E3 = 80.0, 1.8, 1.3, 1.15
XP_SEG1_END, XP_SEG2_END, XP_CAP = 20, 60, 100
STEP_XP_FRACTION = 0.35
GOLD_PER_XP = 0.55

LEVEL_FIRST = 1.0
LEVEL_LAST = 92.0

# Which rarities a step may hand out as its bonus item, by step range.
ITEM_POOL = [
    (1, 20, ["common", "uncommon"]),
    (21, 49, ["uncommon", "rare"]),
    (50, 79, ["rare", "mythical"]),
    (80, 100, ["mythical", "legendary"]),
]

# A player who wanders off the road arrives over-levelled; this is how far above
# a step's anchor a target may be and still be considered fair to ask for.
LEVEL_TOLERANCE = 8

# The four canonical story quests keep everything they have; only the opening
# quest's `next` changes so the chain runs through the 100 steps first.
SPINE_AFTER = "q2_ember_omen"      # MQ100 hands over to the Ember Omen
SPINE_BEFORE = "q1_first_light"    # ... and q1 hands over to MQ001

CHOICE_AT = 65                     # the Mireille expose/protect fork
CHOICE_FLAGS = ["expose_mireille", "protect_mireille"]
CHOICE_RESOLUTION = "mireille_decision"


def level_at(index: int, total: int) -> float:
    if total <= 1:
        return LEVEL_FIRST
    t = float(index) / float(total - 1)
    return LEVEL_FIRST + (LEVEL_LAST - LEVEL_FIRST) * t


def _seg1_end() -> int:
    return int(round(XP_BASE * (XP_SEG1_END ** XP_E1)))


def _seg2_end() -> int:
    return int(round(float(_seg1_end()) *
                     (((XP_SEG2_END - 1) / float(XP_SEG1_END)) ** XP_E2)))


def xp_to_next(at_level: int) -> int:
    """Mirror of GameState.xp_to_next(), so the chain and the curve agree."""
    lv = max(1, at_level)
    if lv >= XP_CAP:
        return 0
    if lv <= XP_SEG1_END:
        return int(round(XP_BASE * (float(lv) ** XP_E1)))
    if lv <= XP_SEG2_END:
        return int(round(float(_seg1_end()) *
                         (((lv - 1) / float(XP_SEG1_END)) ** XP_E2)))
    return int(round(float(_seg2_end()) *
                     (((lv - 1) / float(XP_SEG2_END)) ** XP_E3)))


def xp_at(step: int, total: int) -> int:
    lvl = int(round(level_at(step - 1, total)))
    return int(round(STEP_XP_FRACTION * xp_to_next(lvl) / 5.0) * 5)


def rarity_allowed(step: int) -> list:
    for lo, hi, pool in ITEM_POOL:
        if lo <= step <= hi:
            return pool
    return ["legendary"]


def load(name: str) -> dict:
    with open(os.path.join(ROOT, "data", name)) as f:
        return json.load(f)


def npc_name(npcs: dict, npc_id: str) -> str:
    return String_display(npcs.get(npc_id, {}).get("display_name", npc_id))


def String_display(value: str) -> str:
    return str(value)


def objectives_for(giver: str, kind: str, target: str, count: int,
                   target_desc: str, npcs: dict) -> list:
    objs = []
    main_id = {"K": "hunt", "C": "gather", "F": "reach", "T": "speak"}[kind]
    objs.append(collections.OrderedDict([
        ("id", main_id),
        ("type", {"K": "kill", "C": "collect", "F": "flag", "T": "talk"}[kind]),
        ("target", target),
        ("count", count),
        ("desc", target_desc),
    ]))
    # Hand-in: every step is reported to its giver, so the chain has a face.
    if not (kind == "T" and target == giver):
        objs.append(collections.OrderedDict([
            ("id", "report"),
            ("type", "talk"),
            ("target", giver),
            ("count", 1),
            ("desc", "Report to %s" % npc_name(npcs, giver)),
        ]))
    return objs


def validate(steps: list, enemies: dict, items: dict, npcs: dict) -> list:
    """Self-check the authored table before it is allowed into data/.

    Everything here is re-checked from the shipped JSON by tests/QuestTest.tscn;
    failing in the author is simply the earliest place to catch it.
    """
    problems = []
    total = len(steps)
    if total != 100:
        problems.append("the chain must be exactly 100 steps, found %d" % total)

    region_roster = {}
    for aid, a in enemies.items():
        region_roster.setdefault(a["biome"], []).append(aid)
    drops = {}
    for aid, a in enemies.items():
        for iid, _chance in a["drops"]["items"]:
            drops.setdefault(iid, set()).add(aid)

    bands = {aid: a["level_band"] for aid, a in enemies.items()}
    flags = place_flags()

    for i, (region, giver, kind, target, count, name, _desc) in enumerate(steps, start=1):
        anchor = level_at(i - 1, total) + LEVEL_TOLERANCE
        if giver not in npcs:
            problems.append("MQ%03d: unknown giver %s" % (i, giver))
        if kind == "K":
            if target not in enemies:
                problems.append("MQ%03d: unknown monster %s" % (i, target))
            else:
                if enemies[target]["biome"] != region:
                    problems.append("MQ%03d: %s lives in %s, not %s" %
                                    (i, target, enemies[target]["biome"], region))
                if bands[target][0] > anchor + 0.5:
                    problems.append("MQ%03d: %s opens at L%d, step anchor is L%.0f" %
                                    (i, target, bands[target][0], anchor))
        elif kind == "C":
            if target not in items:
                problems.append("MQ%03d: unknown item %s" % (i, target))
            else:
                if items[target]["type"] != "material":
                    problems.append("MQ%03d: %s is not a material" % (i, target))
                sources = drops.get(target, set())
                regional = [a for a in sources if a in region_roster.get(region, [])]
                if not regional:
                    problems.append("MQ%03d: nothing in %s drops %s" % (i, region, target))
                elif min(bands[a][0] for a in regional) > anchor + 0.5:
                    problems.append("MQ%03d: %s only drops from L%d+ monsters" %
                                    (i, target, min(bands[a][0] for a in regional)))
        elif kind == "F":
            if target not in flags:
                problems.append("MQ%03d: flag '%s' has no producer" % (i, target))
        elif kind == "T":
            if target not in npcs:
                problems.append("MQ%03d: unknown speaker %s" % (i, target))
        else:
            problems.append("MQ%03d: unknown kind %s" % (i, kind))
        if count < 1:
            problems.append("MQ%03d: count must be >= 1" % i)

    if steps[CHOICE_AT - 1][2] != "T":
        problems.append("MQ%03d must be the fork conversation" % CHOICE_AT)
    return problems


def place_flags() -> set:
    """Every place flag the engine can raise (see main.gd / Dungeon / BossArena)."""
    flags = set()
    for sid in load("settlements.json")["settlements"]:
        flags.add("visited_%s" % sid)
    for did in load("dungeons.json")["dungeons"]:
        flags.add("entered_%s" % did)
        flags.add("cleared_%s" % did)
    flags.update(CHOICE_FLAGS)
    flags.add(CHOICE_RESOLUTION)
    return flags


def main() -> None:
    quests_file = load("quests.json")
    quests = quests_file["quests"]
    npcs = load("npcs.json")["npcs"]
    enemies = load("enemies.json")["archetypes"]
    items = load("items.json")["items"]

    problems = validate(STEPS, enemies, items, npcs)
    if problems:
        for p in problems:
            print("  ERROR %s" % p)
        raise SystemExit("gen_quests: %d problem(s) in the authored chain" % len(problems))

    # Re-runnable: previous chain entries are dropped so a shorter chain can
    # never leave orphans behind, while side quests and the canonical four stay.
    kept = {qid: quests[qid] for qid in quests
            if not qid.startswith("MQ")}
    total = len(STEPS)

    # --- author the 100 steps -------------------------------------------------
    ordered = collections.OrderedDict()
    for i, (region, giver, kind, target, count, name, desc) in enumerate(STEPS, start=1):
        qid = "MQ%03d" % i
        nxt = "MQ%03d" % (i + 1) if i < total else SPINE_AFTER
        if kind == "K":
            target_desc = "Slay %d %s" % (count, enemies[target]["display_name"])
        elif kind == "C":
            target_desc = "Gather %d %s" % (count, items[target]["name"])
        elif kind == "F":
            target_desc = "Reach %s" % target.replace("_", " ").title()
        else:
            target_desc = "Speak with %s" % npcs[target]["display_name"]
        objs = objectives_for(giver, kind, target, count, target_desc, npcs)
        reward_items = []
        if i % 5 == 0:
            allowed = rarity_allowed(i)
            pool = sorted([iid for iid, it in items.items()
                           if it["rarity"] in allowed and it["type"] in
                           ("weapon", "armor", "accessory", "consumable")])
            if pool:
                reward_items = [pool[(i // 5) % len(pool)]]
        q = collections.OrderedDict()
        q["name"] = name
        q["desc"] = desc
        q["giver"] = giver
        q["step"] = i
        q["region"] = region
        q["level_anchor"] = int(round(level_at(i - 1, total)))
        q["objectives"] = objs
        q["reward"] = collections.OrderedDict([
            ("xp", xp_at(i, total)),
            ("gold", int(xp_at(i, total) * GOLD_PER_XP / 5) * 5),
            ("items", reward_items),
        ])
        q["next"] = nxt
        if i == CHOICE_AT:
            # The fork reuses the dialogue choice system (Phase E): whichever
            # branch the player takes raises the same resolution flag, and the
            # two branch flags stay set for every later line that cares.
            q["branch_flags"] = CHOICE_FLAGS
            q["resolution_flag"] = CHOICE_RESOLUTION
        ordered[qid] = q

    out = collections.OrderedDict()
    out["_comment"] = (
        "Quest definitions. Objective types: kill (archetype), talk (npc_id), "
        "flag (quest_flags key), collect (items held), deliver (consumes on "
        "completion). 'next' auto-starts the follow-up quest. MQ001-MQ100 are the "
        "main chain (Act 2: the ash road, the Choir, and the vessel), authored by "
        "tools/gen_quests.py; they run between q1_first_light and q2_ember_omen, "
        "which keep their original content unchanged. MQ065 is the Mireille "
        "expose/protect fork."
    )
    # canonical quests first (their ids are frozen), then the chain
    merged = collections.OrderedDict()
    for qid in ["q1_first_light", "q2_ember_omen", "q3_warden_fall", "q4_new_dawn"]:
        if qid in kept:
            merged[qid] = kept[qid]
    for qid in kept:
        if qid not in merged:
            merged[qid] = kept[qid]
    for qid, q in ordered.items():
        merged[qid] = q
    # q1 hands off to the chain instead of straight to the Ember Omen.
    merged[SPINE_BEFORE]["next"] = "MQ001"
    out["quests"] = merged
    out["chain"] = collections.OrderedDict([
        ("length", total),
        ("starts_after", SPINE_BEFORE),
        ("ends_with", SPINE_AFTER),
        ("fork_step", "MQ%03d" % CHOICE_AT),
        ("fork_flags", CHOICE_FLAGS),
        ("step_xp_fraction", STEP_XP_FRACTION),
        ("level_anchor_first", int(round(LEVEL_FIRST))),
        ("level_anchor_last", int(round(LEVEL_LAST))),
    ])

    path = os.path.join(ROOT, "data", "quests.json")
    with open(path, "w") as f:
        json.dump(out, f, indent=2)
        f.write("\n")
    print("wrote %s" % path)
    print("  %d main-chain steps + %d canonical/legacy quests = %d total" %
          (total, len(merged) - total, len(merged)))
    print("  chain: %s -> MQ001 .. MQ100 -> %s" % (SPINE_BEFORE, SPINE_AFTER))
    print("  fork at MQ%03d (%s / %s)" % (CHOICE_AT, CHOICE_FLAGS[0], CHOICE_FLAGS[1]))
    regions = collections.Counter(st[0] for st in STEPS)
    print("  regions: %s" % ", ".join("%s %d" % (k, regions[k]) for k in
                                      ("meadow", "barrens", "frost")))
    print("  rewards: MQ001 = %d xp / %d gold, MQ100 = %d xp / %d gold" %
          (ordered["MQ001"]["reward"]["xp"], ordered["MQ001"]["reward"]["gold"],
           ordered["MQ100"]["reward"]["xp"], ordered["MQ100"]["reward"]["gold"]))
    kinds = collections.Counter(st[2] for st in STEPS)
    print("  objective mix: %d kill, %d collect, %d travel, %d story" %
          (kinds["K"], kinds["C"], kinds["F"], kinds["T"]))

    write_briefings(ordered, npcs)


# --- dialogue -----------------------------------------------------------------

def briefing_entry(qid: str, q: dict, npc: dict) -> dict:
    """One spoken briefing per step, in the giver's mouth."""
    speaker = npc.get("display_name", q["giver"])
    objs = q["objectives"]
    task = objs[0]["desc"]
    return collections.OrderedDict([
        ("id", "mq_brief_%s" % qid),
        ("requires", {"quest_active": [qid]}),
        ("nodes", collections.OrderedDict([
            ("1", collections.OrderedDict([
                ("speaker", speaker),
                ("text", q["desc"]),
                ("next", "2"),
                ("choices", []),
            ])),
            ("2", collections.OrderedDict([
                ("speaker", speaker),
                ("text", "%s. %s" % (task, "Come back to me when it is done.")),
                ("next", ""),
                ("choices", []),
            ])),
        ])),
        ("start", "1"),
        ("on_complete", []),
    ])


def fork_entries(q: dict, npcs: dict) -> list:
    """The MQ065 fork: the player decides what happens to Mireille."""
    npc = npcs["mireille"]
    speaker = npc.get("display_name", "Mireille")
    common = collections.OrderedDict([
        ("speaker", speaker),
        ("text", "The ledger in my sleeve is every name the Choir paid for, "
                 "mine included. Ashvow hangs people for less. Frosthaven burns "
                 "them. Kill me, hand me over, or put me behind you -- I only "
                 "want it decided out loud."),
        ("next", ""),
        ("choices", [
            collections.OrderedDict([
                ("text", "I will take it to the magistrate. Let Ashvow decide."),
                ("next", "expose"),
                ("actions", [
                    {"action": "set_flag", "flag": "expose_mireille"},
                    {"action": "set_flag", "flag": "mireille_decision"},
                    {"action": "complete_objective", "quest": "MQ065",
                     "objective": "speak"},
                ]),
            ]),
            collections.OrderedDict([
                ("text", "Nobody else needs to know. Keep your ledger."),
                ("next", "protect"),
                ("actions", [
                    {"action": "set_flag", "flag": "protect_mireille"},
                    {"action": "set_flag", "flag": "mireille_decision"},
                    {"action": "complete_objective", "quest": "MQ065",
                     "objective": "speak"},
                ]),
            ]),
        ]),
    ])
    exposed = collections.OrderedDict([
        ("speaker", speaker),
        ("text", "Then it is a trial and not a grave. Walk ahead of me -- I would "
                 "rather the magistrate saw me with you than without you."),
        ("next", ""),
        ("choices", []),
    ])
    protected = collections.OrderedDict([
        ("speaker", speaker),
        ("text", "You have just made yourself responsible for every name in this "
                 "book. I hope you understand that I will hold you to it."),
        ("next", ""),
        ("choices", []),
    ])
    return [
        collections.OrderedDict([
            ("id", "mq_fork_choice"),
            ("requires", {"quest_active": ["MQ065"], "flag_not": ["mireille_decision"]}),
            ("nodes", collections.OrderedDict([("1", common), ("expose", exposed),
                                               ("protect", protected)])),
            ("start", "1"),
            ("on_complete", []),
        ]),
        collections.OrderedDict([
            ("id", "mq_fork_exposed"),
            ("requires", {"flag": ["expose_mireille"]}),
            ("nodes", collections.OrderedDict([("1", collections.OrderedDict([
                ("speaker", speaker),
                ("text", "Ashvow has my ledger and I have a date. Whatever you "
                         "meet at the ring, remember which of us chose this."),
                ("next", ""), ("choices", []),
            ]))])),
            ("start", "1"),
            ("on_complete", []),
        ]),
        collections.OrderedDict([
            ("id", "mq_fork_protected"),
            ("requires", {"flag": ["protect_mireille"]}),
            ("nodes", collections.OrderedDict([("1", collections.OrderedDict([
                ("speaker", speaker),
                ("text", "The Choir still thinks I am theirs. That is worth "
                         "something at the ring, and you have bought it."),
                ("next", ""), ("choices", []),
            ]))])),
            ("start", "1"),
            ("on_complete", []),
        ]),
    ]


def write_briefings(ordered: dict, npcs: dict) -> None:
    """Insert one briefing per step into its giver's dialogue file.

    Idempotent: any previously generated entry (id starting `mq_`) is replaced,
    the hand-authored entries are preserved byte-for-byte in order, and the
    generically specific briefings are placed *first* because DialogueDB picks
    the first entry whose `requires` match, and several NPCs have catch-all
    entries at the bottom of their file.
    """
    by_npc = collections.OrderedDict()
    for qid, q in ordered.items():
        by_npc.setdefault(q["giver"], []).append((qid, q))

    written = 0
    for npc_id, group in by_npc.items():
        path = os.path.join(ROOT, "data", "dialogue", "%s.json" % npc_id)
        if not os.path.exists(path):
            raise SystemExit("gen_quests: no dialogue file for giver %s" % npc_id)
        with open(path) as f:
            doc = json.load(f)
        kept = [d for d in doc.get("dialogues", [])
                if not String_display(d.get("id", "")).startswith("mq_")]
        generated = [briefing_entry(qid, q, npcs[npc_id]) for qid, q in group]
        # The fork entries belong to Mireille and must match before briefings.
        if npc_id == "mireille":
            fork = fork_entries(ordered["MQ065"], npcs)
            generated = fork + generated
        doc["dialogues"] = generated + kept
        if "barks" not in doc:
            doc["barks"] = []
        with open(path, "w") as f:
            json.dump(doc, f, indent=2, ensure_ascii=False)
            f.write("\n")
        written += len(generated)
        print("  %-22s %3d quest lines (%d hand-written kept)" %
              (npc_id, len(generated), len(kept)))
    print("  %d generated dialogue entries across %d NPCs" % (written, len(by_npc)))

    # A generated file for the fork's other actor, so the fork is never a dead
    # end for a player who never meets Mireille again.
    print("  fork: expose/protect both resolve MQ065 via its resolution flag")


if __name__ == "__main__":
    main()
