# 🗺️ OpenWorld RPG — Roadmap v3 (Loot / Monsters / Quests)

> **Goal:** a shippable 2D open-world action RPG for Android.
>
> This roadmap replaces the previous one at the user's instruction. The build record of
> everything already shipped is preserved in
> [ROADMAP-v2-buildlog.md](ROADMAP-v2-buildlog.md) and
> [ROADMAP-v1-buildlog.md](ROADMAP-v1-buildlog.md); this file is the plan of record.

Legend: `[x]` done & pushed · `[~]` in progress · `[ ]` todo

---

## Already shipped (do not regress — it is the foundation this builds on)

| Area | What exists |
|---|---|
| Systems | Autoloads: `GameState`, `EventBus`, `QuestManager`, `ItemsDB`, `EnemyDB`, `DialogueDB`, `AudioManager`, `SaveSystem`, `SettingsManager`, `PoolManager`, `Transition` |
| Combat | Melee + whirlwind + firebolt, dodge i-frames, telegraphed attacks, 3-phase `BossArena`, damage numbers, hit-stop |
| World | 35 authored chunks (32 px LPC tiles), 3 biomes, chunk streaming, day/night `CanvasModulate` clock |
| Art/audio | 12 composed LPC character sheets, CC0/CC-BY score, 13 SFX, visual-capture harness, attribution in `CREDITS.md` |
| XP curve | Re-tapered 1–100 curve (5,711,771 XP total), 10 milestone rewards, `floor_multiplier` dungeon scaling |
| Talents | 60 nodes (3 branches × 4 tiers × 5), level-gated 5/25/50/75, real effect hooks |
| NPCs | `NPCController` (idle_schedule / walk_to_point / talk / flee_combat), 11 named NPCs, 37 idle barks, schedules off the `DayNight` clock |
| World map | 9 settlements as real scenes (3 villages / 3 towns / 3 cities), 9 dungeons / 26 floors, settlement safe zones |
| CI | `smoke-test` · `visual-capture` · `android-export`; suites: CombatTest 178, PlaythroughTest 23, AudioTest 35, NpcTest 24, WorldMapTest 34 |

---

## Phase F — the loot / monster / quest build-out

### F1. Item economy: 100+ items across five rarity tiers `[x]`
- **≥100 items** in `data/items.json` with a `rarity` field:
  `common → uncommon → rare → mythical → legendary`.
- Rarity is a **power ordering**, not a label: each tier has a stat budget that
  the item's stats must fit inside, enforced by test.
- Lifesteal exists **only as a rare-or-better affix** and only as a *chance*
  find — it never rolls on common/uncommon gear.
- Every item is **visible in the inventory** with its rarity colour, stats and
  value; no hidden or unusable entries.
- Every item is **obtainable from monster loot** (or a shop/quest), verified by a
  drop-table coverage test — no orphan items.
- Rarity-weighted drop tables per monster tier, so better monsters drop better loot.

**Done.** `tools/gen_items.py` → 120 items (31/29/24/21/15). Average weighted
equipment power per tier: **8.5 / 18.5 / 33.3 / 60.2 / 99.6** — strictly rising, and
every item fits its tier's budget. 8 lifesteal items, rare and up only. Every monster
also rolls its tier's consumable pool, and `tools/gen_items.py`'s tables are the single
source of truth — `tests/ItemsTest.tscn` re-derives all of the above from the shipped
JSON (48 checks), including 400 loot rolls per archetype to prove nothing is orphaned.

### F2. Monster roster: 10+ types, placed by region `[x]`
- **≥10 monster archetypes** from weak to strong, each with a tier, biome and
  level band.
- Placement is data-driven: each biome's spawn table references only monsters
  whose band matches that biome, and each dungeon's floors reference monsters
  appropriate to their depth. A test asserts no monster spawns outside its band.
- Existing archetypes (`grunt`, `scout`, `shaman`, `emberling`) stay valid —
  ids are frozen, they are re-tiered rather than replaced.

**Done.** 14 monsters across 6 tiers in `data/enemies.json` (authored by
`tools/gen_enemies.py`): meadow L1-22 (grunt, emberling, meadow_wolf, husk), barrens
L8-68 (scout, shaman, lizard, raider_brute, minotaur, legion), frost L38-100 (revenant,
troll, archon, ashen_herald). `ChunkStreamer._populate_enemies()` now reads the biome
table + `EnemyDB.band_power_scale()` instead of a hardcoded list, so a monster is placed
by declaring its biome and band. Dungeons carry an authored `level_band`, and the test
proves every floor's monsters fit it.

### F3. Six bosses, escalating `[x]`
- **6 bosses** from "first real fight" to "endgame", each with a phase count,
  arena, and a guaranteed loot table.
- The shipped **Ember Warden stays the final fight and keeps its mechanics**
  (its framing is Act 4 of the main chain).
- Bosses are placed at the end of dungeons / at authored landmarks, and each one
  guards the next power tier — boss N+1 should not be comfortably reachable
  without loot from boss N.

**Done.** HP ladder: `goblin_king` 260 → `slag_wraith` 620 → `bone_titan` 1400 →
`frost_giant` 2600 → `choir_priest` 3600 → **`ember_warden` 5200** (each step ≥25%
tougher, asserted). Five bosses carry their phase table in data and spawn through
`DataBoss` (`scripts/enemies/data_boss.gd` + `scenes/enemies/data_boss.tscn`); the
Ember Warden keeps its own phase script in `boss.gd` untouched. Six floors gate six
dungeons; `scorched_monastery` and `wardens_ascent` end on elite waves instead of
pretending to have a boss.

### F4. Main quest chain: 100 steps `[x]`
- `MQ001`–`MQ100` with the story progressing to the end: Act 1 (Millhaven burns,
  Rowan dies, Wren taken) → Act 2 (Mireille, the expose/protect fork) → Act 3
  (Isolde, the binding) → Act 4 (free Wren).
- Act 2's fork reuses the existing choice system and changes which NPCs are
  available in Act 3.
- Each act is playable end-to-end before the next is written.

### F5. Side quests: 100, easy → hard `[x]`

**F4 done.** `tools/gen_quests.py` authors MQ001–MQ100 — Act 2, the ash road — and
threads them between the unchanged `q1_first_light` and `q2_ember_omen`
(`q1.next = MQ001`, `MQ100.next = q2_ember_omen`). 20 Meadow / 32 Barrens / 48
Peaks steps, 43 kill / 34 collect / 16 travel / 7 story objectives, each with a
spoken briefing in its giver's dialogue file. **MQ065 is the Mireille
expose/protect fork**: the choice lives in `data/dialogue/mireille.json`, both
branches raise the same resolution flag, and both keep their own branch flag for
later lines. Rewards are a fixed slice (35%) of the level-up cost at the step's
level anchor, so the chain pays levels ~1→60 and leaves combat to close the rest.

The world had to learn to notice the player: `main.gd` now raises
`visited_<settlement>` on entering a settlement, `entered_<dungeon>` on taking a
stair, `cleared_<dungeon>` when a floor boss dies, `cleared_ember_warden_keep`
when the shipped Warden fight ends, and talking to an NPC advances any active
`talk` objective for them. One world event now advances only the quests that were
active when it fired (`QuestManager.active_snapshot()`), because otherwise handing
in step N would start step N+1 and instantly complete it.

`tests/QuestTest.tscn` (39 checks) walks all 100 steps through the real quest
API — real enemy nodes, real pickup signal, real flags — and fails if any step
cannot be reached or completed. `PlaythroughTest` now runs q1 → the chain → q2 →
the Warden → A New Dawn in the live world (27 checks).
- `SQ001`–`SQ100` across the bible's categories (Bounty, Fetch, Escort, Mystery,
  Faction, Collection, Companion, Repeatable), split ~30 Meadows / ~40 Barrens /
  ~30 Peaks.
- Difficulty ramps with the region and the level band; rewards scale with
  difficulty, not with quest order.

**F5 done.** `tools/gen_side_quests.py` authors SQ001–SQ100 on the sanctioned
template model: **eight category models written out in full** (Bounty, Fetch,
Escort, Mystery, Faction, Collection, Companion, Repeatable) plus one authored
`twist` clause per quest. 30 Meadow / 39 Barrens / 31 Peaks, opening at level 3
and closing at 92: Bounty 27, Mystery 14, Faction 12, Fetch 12, Collection 10,
Repeatable 10, Companion 8, Escort 7. Every kill target lives in the quest's
region and is open by its level anchor, which the author asserts before writing
and `tests/QuestTest.tscn` re-asserts from the shipped JSON.

The board is served at **runtime**, not baked into dialogue files:
`QuestManager.next_offer(npc_id)` hands out the easiest job that NPC holds which
the player has not taken and is high enough level for, and `main.gd` shows it
through the existing dialogue/choice UI. Baking 100 offer entries into
`data/dialogue/*.json` would have shadowed the hand-written lines those files end
with (several NPCs' catch-alls have no conditions at all). Goods quests use
`deliver` (consumes) rather than `collect`, so goods you never gave up cannot be
turned into a payout. `QuestManager._sync_flags()` also means a "reach X" step is
already satisfied if you have been there — the same rule collect already used.

### F6. Secrets `[x]`
- Hidden caches, locked vaults, lever/gate puzzles, lore fragments, secret
  bosses, and off-map stashes — discoverable but never required.
- Secrets are tracked as flags so they survive save/load and can be counted.

### F7. Economy & power balance pass `[x]`
- Run only once F1–F6 are complete, against everything in the game at once.
- Levers: item stat budgets vs the level curve, gold income vs shop prices and
  upgrade costs, XP income vs the 1–100 curve, monster/boss HP & damage vs
  expected player power at each band, lifesteal proc rate vs sustain, potion
  economy, and time-to-kill for each boss.
- Output: a documented before/after table in `DECISIONS.md`, plus a
  `tools/balance_report.py` that prints the numbers, so the balance is
  reproducible rather than asserted.

**F7 done.** `tools/player_model.py` is the single source of the player power
curve (read out of the .gd constants at import time, so it cannot drift), and
`tools/balance_report.py` measures the shipped game against it. The pass found
the game in bad shape and fixed it at the source rather than by taste:

| measured | before | after | target |
|---|---|---|---|
| swings to kill (band midpoint) | 0.4 – 6.2 | **1.9 – 5.6** | 2 – 8 |
| monster hits the player survives | 27 – 633 | **8.5 – 25** | 5 – 30 |
| kills per level | 76 – 581 | **18 – 30** | 12 – 45 |
| boss fight length | 2.8 – 10.8 s | **28 – 100 s** | 25 – 120 s |
| boss HP (weakest → strongest) | 260 → 5,200 | **2,995 → 144,308** | escalating |
| field monster HP / damage | 14–600 / 4–46 | **47–1,318 / 11–280** | ladder |
| legendary item price | 1,637 | **27,701** | ≈1 level of income |
| price jump per rarity | mixed | **every rarity ≥ 1.5x** | ≥ 1.25x |

Three changes made this hold:

1. **Monster stats are derived, not typed.** `tools/gen_enemies.py` keeps the
   authored *relative* roles (a shaman is squishier than a brute) and takes the
   absolute numbers from the power curve at each archetype's band midpoint, so
   "how long is a fight" and "how many kills is a level" are design inputs.
2. **One scaling law.** `EnemyDB.band_power_scale()` is retired (a documented
   no-op): the old biome-wide multiplier ran barrens ×1.15 and frost ×1.81 on top
   of stats that were already band-authored, double-counting whole regions.
3. **Prices follow income.** `_price()` in `tools/gen_items.py` prices gear at a
   fraction of one level's kill income at the tier's unlock level, consumables at
   about one kill, and materials at a few — the old constants left the entire
   catalogue affordable by level 20.

`python3 tools/balance_report.py --check` now fails CI if any measured target
leaves its band (DECISIONS #44/#45).

---

## Phase G — Ship (unchanged targets)

- Playtest on a real device (the one thing that cannot be done here).
- Performance profile on Android hardware.
- Signed release: the `release` workflow already builds signed APK/AAB on a `v*`
  tag; `v0.2.0` is published as a prerelease.

---

## What's left, in one line

Phase F is the remaining content build: 100+ rarity-tiered items that drop from
≥10 monsters and 6 escalating bosses, a 100-step main chain, 100 side quests,
secrets, and a full balance pass — layered on top of the shipped systems, never
replacing them.
