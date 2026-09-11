# 🗺️ OpenWorld RPG — Consolidated Roadmap

> **One file, two lists.** Everything in **Part 1** is shipped, verified and pushed.
> **Part 2** is what is not done yet: the audit that was handed over on 2026-09-11
> plus the weaknesses the v3 evaluation still lists. Nothing moves from Part 2 to
> Part 1 until it is *made, covered by a test, and committed* — the same rule every
> earlier roadmap ran on. No entry in Part 1 is aspirational.
>
> **Goal (unchanged):** a shippable 2D open-world action RPG for Android.
>
> This file replaces Roadmap v1 (build), v2 (reality-checked + content bible), v3
> (loot/monsters/quests) and v4 (UI/fight). Their item-level records are kept as
> [ROADMAP-v1-buildlog.md](ROADMAP-v1-buildlog.md),
> [ROADMAP-v2-buildlog.md](ROADMAP-v2-buildlog.md) and
> [ROADMAP-v4-ui-fight.md](ROADMAP-v4-ui-fight.md); everything they delivered is
> summarised here.

Legend: `[x]` done & pushed · `[~]` in progress · `[ ]` todo

---

# Part 1 — Done

## 1.1 The build (Roadmap v1, Phases 0–13)

| Phase | Delivered |
|---|---|
| 0 Infrastructure | Repo + `/tmp` toolchain bootstrap (Godot 4.4.1, checksum-pinned), repo-size gate (<120 MB), CI on every push (headless smoke, visual capture, Android export) |
| 1 Scaffold | 1280×720 `canvas_items` + expand, touch emulation, folder layout (DECISIONS #2) |
| 2 World | 35 authored chunks of real 32 px LPC tiles, 3 biomes, chunk streaming (3×3 radius), day/night `CanvasModulate` clock |
| 3 Player | 8-way movement, camera with look-ahead + shake, dodge with i-frames |
| 4 Combat | Melee, whirlwind, firebolt, telegraphed enemy attacks, hit-stop, damage numbers, particles |
| 5 Enemy AI + boss | Patrol/chase/attack state machine, 3-phase `BossArena`, the Ember Warden |
| 6 Items & economy | `ItemsDB`, inventory, equipment slots, vendor, gold |
| 7 Progression | 1–100 XP curve, milestone rewards, 60 talent nodes in 3 branches |
| 8 Quests & narrative | `QuestManager`, dialogue JSON + choice system, 4-act main story |
| 9 Save/load | 3 slots, autosave, settings persistence |
| 10 UI/UX | HUD, pause menu, minimap, inventory/talent/quest-log screens, main menu, death screen, notch-safe insets |
| 11 Audio | `AudioManager`, 5 procedural CC0 tracks (crossfade, looping), 13 SFX, transitions, juice pass |
| 12 Performance | 256×96 terrain atlas, object pooling, frame-budget guard, streamer stress test |
| 13 Ship | Automated full-playthrough test, signed release workflow on `v*`, README/CREDITS/DECISIONS |

## 1.2 Content bible (Roadmap v2, Phases A–E)

- **A — Systems** frozen as the regression baseline: autoloads (`GameState`,
  `EventBus`, `QuestManager`, `ItemsDB`, `EnemyDB`, `DialogueDB`, `AudioManager`,
  `SaveSystem`, `SettingsManager`, `PoolManager`, `Transition`).
- **B — Real content**: real 32 px LPC tileset and clustered terrain, pixel-art
  rendering (nearest-neighbour), character breadth (12 composed LPC sheets), real
  audio, a visual-capture harness so art can be verified without a display. B6
  (asset pipeline hardening) was declined with reasoning, not skipped.
- **C — Playtest & balance**: automated playthrough, balance instrumentation.
- **D — Ship**: pre-release `v0.2.0` published as a prerelease; APK/AAB jobs.
- **E — Content bible**: re-tapered 1–100 curve (5,711,771 XP) with 10 milestone
  rewards; 60 talent nodes (3×4×5, level-gated 5/25/50/75) with real effect hooks;
  `NPCController` with the `DayNight`-driven schedule state machine, walk-to-point,
  flee-combat and 37 idle barks; 9 settlements as real scenes (3 villages / 3 towns
  / 3 cities) with safe zones; 9 dungeons / 26 floors; reputation hooks; weather;
  secrets.

## 1.3 Loot / monsters / quests (Roadmap v3, Phase F)

| Item | Shipped |
|---|---|
| F1 Item economy | 120 items in 5 rarity tiers with test-enforced stat budgets (avg power 8.5 / 18.5 / 33.3 / 60.2 / 99.6); lifesteal only as a rare-or-better chance affix; every item reachable from loot |
| F2 Monster roster | 14 field archetypes tiered and biome/level-banded; placement is data-driven and asserted |
| F3 Six bosses | `goblin_king` 260 → `slag_wraith` 620 → `bone_titan` 1400 → `frost_giant` 2600 → `choir_priest` 3600 → **Ember Warden 144,308** (mechanics frozen); `DataBoss` drives five of them from data |
| F4 Main chain | MQ001–MQ100 (Act 2, the ash road) threaded between the untouched `q1_first_light`/`q2_ember_omen`; MQ065 is the Mireille expose/protect fork; every step walked by `QuestTest` |
| F5 Side quests | SQ001–SQ100 on eight category models + one authored twist each, spread 30/39/31 by region, offered at runtime through `QuestManager.next_offer()` |
| F6 Secrets | 40 secrets (caches, vaults, lever gates, lore, secret bosses), flag-tracked, never required |
| F7 Balance | `tools/player_model.py` + `tools/balance_report.py --check` as a CI gate; swings-to-kill 1.9–5.6, boss fights 28–100 s, prices follow income |

## 1.4 Ship (Phase G)

- [x] Signed release workflow: `release` builds signed APK/AAB on a `v*` tag and
  publishes 0.x tags as prereleases (`v0.2.0`, `v0.3.0`).
- [x] Docs tell the truth: README, release notes, DECISIONS and the roadmaps all
  rewritten to match the shipped build.
- [ ] Device playtest — see Part 2.

## 1.5 UI / fight / world feel (Roadmap v4, H1–H7)

- **H1 HUD visual system** — one themed panel per cluster (HP/MP, quest tracker,
  buffs, minimap, toasts) on `ui/theme.tres`.
- **H2 Touch layout** — fight ergonomics; attack/talk and every touch button
  rebuilt from scratch (`c3c8b68`, UiTest).
- **H3 Fight feedback** — damage numbers, hit-stop, shake, telegraph clarity.
- **H4 Safe zones** — 9.69 % of the world; enemies never attack or approach inside
  a safe zone or during a conversation, enforced on both sides with a test.
- **H5 Movement** — true rest after three patrol cycles, off-screen enemies skip
  the loop, `cycle_seconds` 480 → 1200, 46 px separation so nothing overlaps
  (measured min NPC pair 136 px), **H5.5/H5.6 idle art: all 49 posed sheets carry
  generated idle frames** (24/24 villagers).
- **H6 Art polish** — banners, panels, portraits where art was the fix.
- **H7 Fight animations** — 21 attack sheets + 3 cast sheets; enemy, boss, caster
  and bare-hand sets; the hero's 4-pose attack; weapons swing the composited
  6-frame LPC film.

Art parity is machine-checked: **POSE ART PASS = 49 sheets / 49 idle / 21 attack /
3 cast**, ANIM CHECK = 2 weapons + 16 armed 4-direction characters.
Size: sheets ship as exact-palette indexed PNGs (5.64 MB → 2.05 MB, pixel-identical).

---

# Part 2 — Not done

## 2.1 The handover audit (2026-09-11) — all repaired

Every item below was fixed, covered by a regression test, swept through the full
suite and pushed. The commit that landed it is named on each line.

### Critical

- [x] **C1 — the Warden attacked anyone who walked past, and the keep's third
  floor died with it.** `BossArena` now wakes the Ember Warden only once the story
  has reached the Ember Omen (`q3_warden_fall` active/done, or `saw_warden_ring`
  plus `q2_ember_omen` active); `may_summon()` is the single gate and it says why
  once instead of leaving a silent ring. The keep's floor-3 arena builds its own
  Warden with `cleared_<dungeon>_floor<N>`, so killing the overworld Warden can no
  longer leave that floor permanently empty. — `d9479b6`
- [x] **C2 — a level-85 frost chunk sat next to the starting camp.** Biomes come
  from radial distance (`BIOME_BANDS`, ±0.55 chunk-hash wobble) instead of a free
  roll, and the spawn chunk's 2-chunk neighbourhood carries no spawners at all
  (`SPAWN_SAFE_RADIUS`). Measured nearest frost ≥ 4 chunks from origin. — `d9479b6`
- [x] **C3 — saving underground lost the dungeon.** `GameState` stores
  `dungeon_id`/`dungeon_floor`; `main._restore_dungeon_from_state()` rebuilds the
  interior on load instead of dropping the player into an empty chunk
  ~200,000 px from anywhere. — `d9479b6`
- [x] **C4 — dying in a dungeon leaked it, and broke settlement flags for the rest
  of the run.** `_leave_dungeon()` is the one teardown (exit stair, death, load);
  `_check_place_flags()` stops bailing out. — `d9479b6`
- [x] **C5 — dungeon walls were not walls, and the overworld kept streaming
  underneath.** Four `StaticBody2D` bands on layer 1; `ChunkStreamer.suspend()` /
  `resume()` while underground. — `d9479b6`
- [x] **C6 — six screens each wrote `get_tree().paused`.** New `PauseManager`
  autoload owns the flag as a *set of holds*: a screen holds it while it is up and
  releases it when done, so the second screen closing cannot unpause under the
  first, and a holder freed without releasing (quit to title, scene change) is
  pruned instead of stranding the world paused. All nine call sites rewired; the
  two private `_was_paused` copies are gone; the HUD and virtual joystick ask the
  manager; a source scan in `UiTest` fails if anything else writes the flag again. — `11d5b31`

### Serious

- [x] **G1 — repeatable quests were one-shot.** `_complete()` clears the
  `took_<qid>` flag the offer dialogue sets, so `next_offer()` can hand the job
  out again. — `811b8b7`
- [x] **G2 — one greeting could complete a step that was gated behind a kill.**
  `talk_to()` advances only the quest's *next* unfinished objective
  (`next_objective()`). — `811b8b7`
- [x] **G3 — an unreachable dialogue branch.** `DialogueDB.pick()` returned the
  first match, so when two authored branches were true the second could never be
  read (and it can gate content). Most specific wins: explicit `priority` beats
  condition count, ties keep file order. — `811b8b7`
- [x] **G4 — the HUD showed one quest and silently dropped the rest.** The tracker
  follows the player's own acceptance order, lists extra jobs one line each, and a
  job can be pinned (★) from the quest log (`GameState.pinned_quest`, saved). — `811b8b7`
- [x] **G5 — walking away from a chest destroyed its contents.** A chest marks
  itself opened forever but dropped ordinary (unsaved) pickups. It banks the loot
  at open time; the coins/item fly is only that animation. — `811b8b7`
- [x] **G6 — nothing enforced `stack` sizes** (and enforcing it exposed materials
  authored `stack: 1`, which made "gather 3 Slime Gel" unfillable). `add_item()`
  caps at `ItemsDB.stack_size`; materials stack 99 (generator + data). — `811b8b7`
- [x] **G7 — the gold-find talent also multiplied vendor sales.** `add_gold(amount,
  source)` applies the multiplier only to money that was *found*; the shop's sell
  path passes `"trade"`. — `811b8b7`

### Medium

- [x] **M1 — keyboard/gamepad interact and the touch button disagreed on the
  target.** One rule now: `WorldInteractable.nearest_in_range()`, used by the HUD
  and both `_unhandled_input` paths. — `1522335`
- [x] **M2 — the ending's Credits button did nothing.** It sets
  `GameState.pending_credits`; the main menu opens its credits layer on arrival. — `1522335`
- [x] **M3 — the menu background was drawn for a fixed 1280×720.** Hills, fire and
  flame are now fractions of the live viewport. — `1522335`
- [x] **M4 — one typo'd music id killed the soundtrack for the run.**
  `play_music()` records the track only after it checks the id exists. — `1522335`
- [x] **M5 — entering a dungeon changed physics state during the physics flush.**
  The descent is deferred by a frame (same pattern `SecretGate` uses). — `1522335`
- [x] **M6 — a double release could hand one node to two callers.**
  `ObjectPool.release()` ignores a repeat release. — `d9479b6`
- [x] **M7 — death left the hero dead-looking.** `player.revive()` clears the death
  state and the 90° sprite tilt on respawn. — `d9479b6`

### Low

- [x] **L1 — the epilogue printed a hardcoded "/206 quests".** It reports
  `QuestManager.data.size()`. — `1522335`
- [x] **L2 — settlement music radius was a global constant**, not the
  settlement's own radius. — `d9479b6`
- [x] **L3 — the minimap sampled 72×72 = 5,184 points every 0.3 s** for cells drawn
  at ~1.4 px. 48 cells still resolve the authored 32 px tiles. — `1522335`
- [x] **L4 — New Game inherited the previous run's campfire registry**
  (`Waypoint.registry`/`names` are statics and statics survive a scene change).
  `GameState.reset()` clears it. — `1522335`
- [x] **L5 — the opening vendor sold a 2,965 g sword to a hero with 50 g.**
  Bram's shelf and Factor Orlan's both start at `wooden_club` / `short_sword`
  prices. — `1522335`

**Audit pass totals.** Commits `d9479b6` (C1–C5), `811b8b7` (G1–G7), `1522335`
(M1–M5, L1, L3–L5), `11d5b31` (C6), each pushed to `main` with green CI on
`d9479b6`, `811b8b7`, `1fc3052` and `1522335`.

## 2.2 Still open

- [ ] **The device playtest** (Phase G / `PLAYTEST.md`). The one thing that cannot
  be done here: it needs a human, a phone, and an opinion about how the game
  *feels* — performance, heat, touch reach, readability in daylight, and whether
  the balanced numbers are the right experience. Everything it feeds back lands
  here as new items.
- [ ] **Android performance numbers.** Folded into `PLAYTEST.md` §1; no trustworthy
  FPS/thermals figure exists until the device pass runs.
- [ ] **World decor density** (v3 §2: 0.17 % decor tiles, biomes read flat). Fix
  path: 2–3 decor columns in the atlas + scatter in the generator.
- [ ] **Three engine-key talent nodes** (v3 §3: 60 nodes, all numeric). Candidates
  from the report: a chain finisher that ignites, a dodge that leaves dust/breath,
  a whirlwind that knocks back.
- [~] **Second-half gold sink** (v3 §4). Partly answered — fast travel is priced by
  distance and gear is priced against level income — but an item upgrade or a
  simple craft using the 23 materials is still the stronger answer and is not
  built.
- [ ] **Cut the release tag** for this pass (the workflow publishes 0.x as a
  prerelease with signed APK/AAB; `project.godot` is at **0.5.0**).

---

# Part 3 — How to verify any of this

| Gate | Command |
|---|---|
| Full gameplay suites (9) | `godot --headless --path . tests/<Suite>.tscn` → Combat 229 · Items 63 · WorldMap 72 · Ui 36 · Npc 43 · Quest 61 · Secret 45 · Audio 56 · Playthrough 52 |
| Balance band | `python3 tools/balance_report.py --check` |
| Art parity | `python3 tools/make_idle_frames.py --check` (49 sheets / 49 idle / 21 attack / 3 cast) |
| Repo budget | `tools/check_repo_size.sh` (< 120 MB repo) |
| CI | `smoke-test` · `visual-capture` · `android-export` on every push |

Standing rules that keep Part 1 honest:

1. An item is ticked only after it is **made, tested and committed** — never when
   it is planned or partly done.
2. Every fix ships with the regression test that would have caught it.
3. Nothing already shipped is replaced to fix something else: biomes, the Ember
   Warden and the four-beat story survive every pass (DECISIONS carries the reasoning).
4. Sizes are checked before every commit; art sources are parked out of the
   workspace with `tools/pose_sources.sh park` rather than deleted.
