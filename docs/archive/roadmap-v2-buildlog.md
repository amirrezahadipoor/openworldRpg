# 🗺️ OpenWorld RPG — Roadmap v3 (Content Bible + Loot/Monster/Quest build-out)

> **Goal:** a shippable 2D open-world action RPG for Android.
>
> This roadmap replaces the previous one at the user's instruction. The build record of
> everything already shipped is preserved in
> is archived here, and the single plan of record is now the consolidated
> [ROADMAP.md](../../ROADMAP.md) at the repo root.

Legend: `[x]` done & pushed · `[~]` in progress · `[ ]` todo

---

## Already shipped (do not regress — it is the foundation this builds on)

| Area | What exists |
|---|---|
| Systems | Autoloads: `GameState`, `EventBus`, `QuestManager`, `ItemsDB`, `EnemyDB`, `DialogueDB`, `AudioManager`, `SaveSystem`, `SettingsManager`, `PoolManager`, `Transition` |
| Combat | Melee + whirlwind + firebolt, dodge i-frames, telegraphed attacks, 3-phase `BossArena`, damage numbers, hit-stop |
| World | 35 authored chunks (32 px LPC tiles), 3 biomes, chunk streaming, day/night `CanvasModulate` clock |
| Art/audio | 12 composed LPC character sheets, CC0/CC-BY score, 13 SFX, visual-capture harness, attribution in `CREDITS.md` |
| **E§6** | Re-tapered 1–100 XP curve (5,711,771 XP total), 10 milestone rewards, `floor_multiplier` dungeon scaling |
| **E§7** | 60 talent nodes (3 branches × 4 tiers × 5), level-gated 5/25/50/75, real effect hooks |
| **E§3** | `NPCController` (idle_schedule / walk_to_point / talk / flee_combat), 11 named NPCs, 37 idle barks, schedules off the `DayNight` clock |
| **E§1** | 9 settlements as real scenes (3 villages / 3 towns / 3 cities), 9 dungeons / 26 floors, settlement safe zones, the Ember Warden fight unchanged |
| CI | `smoke-test` (13 steps) · `visual-capture` · `android-export`; suites: CombatTest 178, PlaythroughTest 23, AudioTest 35, NpcTest 24, WorldMapTest 34 |

---

## Phase F — the loot / monster / quest build-out

### F1. Item economy: 100+ items across five rarity tiers `[ ]`
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

### F2. Monster roster: 10+ types, placed by region `[ ]`
- **≥10 monster archetypes** from weak to strong, each with a tier, biome and
  level band.
- Placement is data-driven: each biome's spawn table references only monsters
  whose band matches that biome, and each dungeon's floors reference monsters
  appropriate to their depth. A test asserts no monster spawns outside its band.
- Existing five archetypes (`grunt`, `scout`, `shaman`, `emberling`) stay valid —
  ids are frozen, they are re-tiered rather than replaced.

### F3. Six bosses, escalating `[ ]`
- **6 bosses** from "first real fight" to "endgame", each with a phase count,
  arena, and a guaranteed loot table.
- The shipped **Ember Warden stays the final fight and keeps its mechanics**
  (its framing is already done in Act 4).
- Bosses are placed at the end of dungeons / at authored landmarks, and each one
  guards the next power tier — you cannot reasonably reach boss N+1 without
  loot from boss N.

### F4. Main quest chain: 100 steps `[ ]`
- `MQ001`–`MQ100` with the story progressing to the end: Act 1 (Millhaven burns,
  Rowan dies, Wren taken) → Act 2 (Mireille, the expose/protect fork) → Act 3
  (Isolde, the binding) → Act 4 (free Wren).
- Act 2's fork reuses the existing choice system and changes which NPCs are
  available in Act 3.
- Each act is playable end-to-end before the next is written.

### F5. Side quests: 100, easy → hard `[ ]`
- `SQ001`–`SQ100` across the bible's categories (Bounty, Fetch, Escort, Mystery,
  Faction, Collection, Companion, Repeatable), split ~30 Meadows / ~40 Barrens /
  ~30 Peaks.
- Difficulty ramps with the region and the level band; rewards scale with
  difficulty, not with quest order.

### F6. Secrets `[ ]`
- Hidden caches, locked vaults, lever/gate puzzles, lore fragments, secret
  bosses, and off-map stashes — discoverable but never required.
- Secrets are tracked as flags so they survive save/load and can be counted.

### F7. Economy & power balance pass `[ ]`
- Run only once F1–F6 are complete, against everything in the game at once.
- Levers: item stat budgets vs level curve, gold income vs shop prices and
  upgrade costs, XP income vs the 1–100 curve, monster/boss HP & damage vs
  expected player power at each band, lifesteal proc rate vs sustain, potion
  economy, and time-to-kill for each boss.
- Output: a documented before/after table in `DECISIONS.md`, plus a
  `tools/balance_report.py` that prints the numbers so the balance is
  reproducible rather than asserted.

---

## Phase G — Ship (unchanged targets)

- Playtest on a real device (the one thing that cannot be done here).
- Performance profile on Android hardware.
- Signed release: the `release` workflow already builds signed APK/AAB on a `v*`
  tag; `v0.2.0` is published as a prerelease.

---

## What's left, in one line

Phase F is the whole remaining content build: 100+ rarity-tiered items that
drop from ≥10 monsters and 6 escalating bosses, a 100-step main chain, 100 side
quests, secrets, and a full balance pass — all on top of the shipped systems,
never replacing them.
