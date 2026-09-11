# 🗺️ OpenWorld RPG — Consolidated Roadmap

> **One roadmap, two halves.** The first half is everything that is **done** — every
> previous roadmap (v1 build, v2 reality-check + content bible, v3 loot/monsters/
> quests, v4 UI/fight) folded into a single record. The second half is the
> **not-done** list: the audit handed over on 2026-09-11, item by item, plus what
> still genuinely remains.
>
> The item-level history stays in
> [docs/archive/roadmap-v1-buildlog.md](docs/archive/roadmap-v1-buildlog.md) and
> [docs/archive/roadmap-v2-buildlog.md](docs/archive/roadmap-v2-buildlog.md); the
> v4 UI/fight pass is in
> [docs/archive/roadmap-v4-ui-fight.md](docs/archive/roadmap-v4-ui-fight.md).
>
> **Rule:** an item moves from the second half to the first only when it is
> *made, tested and committed*. A checkbox is never ahead of the code.
>
> **Goal (unchanged):** a shippable 2D open-world action RPG for Android.

Legend: `[x]` done & pushed · `[~]` in progress · `[ ]` todo

---

# PART 1 — DONE

## 1.1 Build (Roadmap v1, Phases 0–13)

| Phase | Delivered |
|---|---|
| 0 — Infrastructure | Repo + branch + push access, `/tmp` toolchain bootstrap (Godot 4.4.1, checksum-pinned), 120 MB repo-size gate, CI on every push: headless smoke test + Android export, first automated gameplay suite |
| 1 — Scaffold | `project.godot` on GL Compatibility with touch emulation, 1280×720 `canvas_items` + `expand` (DECISIONS #2), the `scenes/ scripts/ assets/ data/ ui/ world/ tools/` layout |
| 2 — World & streaming | 35 authored chunks of 32 px tiles, 3×3 chunk streaming, biome ground palette, `CanvasModulate` day/night clock |
| 3 — Player & camera | 8-way movement, dodge with i-frames, camera look-ahead + screenshake, sprite facing |
| 4 — Combat core | 3-hit melee chain with a heavy finisher, whirlwind, firebolt, telegraphed enemy attacks, hit-stop, damage numbers |
| 5 — Enemy AI & boss | Patrol/chase/attack/flee state machine, `BossArena` with a 3-phase Warden and a summon ring |
| 6 — Items & economy | `ItemsDB`, inventory with stacks, equipment slots, vendor buy/sell, gold, loot drops |
| 7 — Progression | 1–100 XP curve, level-up rewards, talent tree with per-branch points |
| 8 — Quests & narrative | `QuestManager` (objectives, flags, rewards), dialogue JSON with a choice system, the 4-act main story (`q1_first_light` → `q4_new_dawn`) |
| 9 — Save/load & meta | 3 save slots + autosave, settings persistence, `SaveSystem` summaries for the slot picker |
| 10 — UI/UX | HUD (pools, XP/gold, quest tracker, buff row, minimap, toasts), pause menu, inventory / talent / quest-log screens, main menu with slot picker, death screen, notch-safe insets |
| 11 — Audio & polish | `AudioManager` with crossfading looping music (5 tracks), 13 SFX, fade transitions, a juice pass (hit-stop, shake, squash) |
| 12 — Performance | Terrain in one atlas, object pooling for enemies/projectiles/damage numbers, frame-budget guard, streamer stress test |
| 13 — Ship | Automated full-playthrough test in CI, signed release workflow on `v*` tags, README / CREDITS / DECISIONS written |

## 1.2 Content bible (Roadmap v2, Phases A–E)

- **A — Systems**: autoloads frozen as the regression baseline (`GameState`,
  `EventBus`, `QuestManager`, `ItemsDB`, `EnemyDB`, `DialogueDB`, `AudioManager`,
  `SaveSystem`, `SettingsManager`, `PoolManager`, `Transition`, `PauseManager`).
- **B — Real content**: real 32 px LPC tileset (in `assets/source/`, vendored with
  attribution), terrain quality pass, nearest-neighbour pixel rendering, character
  breadth (composed LPC sheets), real audio, and a visual-capture harness so art
  can be checked from CI. B6 (asset pipeline hardening) was **declined with
  reasoning**, not skipped.
- **C — Playtest & balance**: automated playthrough, balance instrumentation,
  the safe-zone report.
- **D — Ship**: signed debug APK in CI; `v0.2.0` published as a prerelease.
- **E — Content bible**: E§1 nine settlements as real scenes (3 villages / 3 towns
  / 3 cities) with safe zones + 9 dungeons / 26 floors; E§3 `NPCController`
  (schedule, walk-to-point, talk, flee) with named NPCs and idle barks; E§6
  re-tapered 1–100 curve with milestones; E§7 60 talent nodes gated 5/25/50/75;
  E§8/E§9 reputation, weather and secrets.

## 1.3 Loot / monsters / quests (Roadmap v3, Phase F)

- **F1 — Item economy** `[x]`: 120 items across five rarity tiers with a stat
  budget per tier enforced by tests; lifesteal only as a rare-or-better chance
  affix; every item reachable from loot or a shop.
- **F2 — Monster roster** `[x]`: 14 field archetypes, tiered and level-banded,
  placed by biome from the roster's own tables (the generator used to hardcode two
  names per biome — audit §25, fixed in the v3 appendix).
- **F3 — Six bosses** `[x]`: `goblin_king` → `slag_wraith` → `bone_titan` →
  `frost_giant` → `choir_priest` → **Ember Warden** (mechanics frozen), each with a
  data-driven phase table and a guaranteed loot table.
- **F4 — Main chain** `[x]`: MQ001–MQ100 (Act 2, the ash road) threaded between
  the shipped `q1`/`q2`, with the Mireille expose/protect fork at MQ065 and a
  spoken briefing per step.
- **F5 — Side quests** `[x]`: SQ001–SQ100 over eight category models plus an
  authored twist each, offered at runtime by `QuestManager.next_offer()`.
- **F6 — Secrets** `[x]`: 40 secrets (caches, vaults, levers, lore, secret bosses),
  flag-tracked and never required.
- **F7 — Balance pass** `[x]`: `tools/player_model.py` + `tools/balance_report.py
  --check` as a CI gate; swings-to-kill 1.9–5.6, boss fights 28–100 s, prices
  follow income, every rarity step ≥ 1.5×.

## 1.4 Ship (Phase G)

- [x] Signed release workflow: `release` builds signed APK/AAB on a `v*` tag and
  publishes 0.x tags as prereleases (`v0.2.0`, `v0.3.0`).
- [x] Docs tell the truth: README, release notes, DECISIONS and the roadmaps.
- [ ] Device playtest — see Part 2.

## 1.5 UI / fight / world feel (Roadmap v4, H1–H7)

- **H1 HUD visual system** `[x]` — one themed panel per cluster on `ui/theme.tres`.
- **H2 Touch controls** `[x]` — attack/talk and every touch button rebuilt from
  scratch; UiTest covers the tap path (`c3c8b68`).
- **H3 Fight feedback** `[x]` — damage numbers, hit-stop, shake, telegraphs.
- **H4 Safe zones** `[x]` — 9.69 % of the world; nothing attacks or approaches
  inside a safe zone or during a conversation, enforced on both sides.
- **H5 Movement** `[x]` — true rest after three patrol cycles, off-screen enemies
  skip the loop, `cycle_seconds` 480 → 1200, 46 px separation (measured min NPC
  pair 136 px).
- **H5.5 / H5.6 Idle art** `[x]` — every posed sheet carries generated idle frames:
  **24/24 villagers**, all monsters and bosses.
- **H6 Art polish** `[x]` — banners, panels, portraits where art was the fix.
- **H7 Fight animations** `[x]` — 21 attack sheets + 3 cast sheets; enemy, boss,
  caster and bare-hand sets; the hero's 4-pose attack; 16 armed characters swing
  the composited 6-frame LPC film.

## 1.6 Post-audit follow-ups (v3 report, remaining weaknesses)

- [x] **World decor density** — atlas 8 → 11 columns (three decor variants per
  biome), scattered by the generator: **0.17 % → 4.73 %** of the map, with object
  placement provably untouched (no RNG consumed; all 35 chunks diff byte-identical
  on object layers). `ec07c3e`
- [x] **Three engine-key talents** — tier-4 nodes that change behaviour, not
  numbers: the chain finisher ignites, a talented whirlwind hurls enemies away, a
  dodge leaves a 1.2 s speed surge. The tree keeps its 60 nodes/ids/gates; a test
  fails if an authored `behaviour` key has no handler in code. `824a317`
- [x] **Second-half gold sink** — the shop's smith's bench: gold + the item's
  regional material push an equipped item to +10 (+8 % of its own stats per step),
  priced at a fraction of the item's value so the sink scales with the gear the
  money pooled around. `0c3b8d5`
- [x] **The side-loadable APK was 175 MB** — 157 MB of that was two ABIs of
  *uncompressed* engine binary (`libgodot_android.so`, 69 MB + 76 MB) next to
  ~25 MB of actual game. Compressed, the same build is **67 MB** (published as
  `v0.6.2`), and a new release gate refuses to publish an artefact whose libraries
  are stored raw or whose merged manifest cannot extract them. `da6bb9e`


---

# PART 2 — NOT DONE

## 2.1 The handed-over audit (2026-09-11) — every item repaired

Each line names the fix and the commit that landed it. All of these are covered by
a regression test and were run through the full suite.

### 🔴 Critical

- [x] **C1 — the Ember Warden attacked anyone who walked past, and the dungeon's own
  boss floor died with it.** The arena now waits for the story (`q3_warden_fall`
  active/done, or the ring seen plus `q2_ember_omen`), `may_summon()` is the single
  gate, and the keep's floor-3 arena carries its own flag
  (`cleared_<dungeon>_floor<N>`) so killing the overworld Warden cannot empty it. `d9479b6`
- [x] **C2 — level-85 monsters could spawn next to the starting camp.** Biomes are
  radial bands (`BIOME_BANDS`) instead of a free roll, and the spawn chunk's
  2-chunk neighbourhood carries no spawners (`SPAWN_SAFE_RADIUS`); measured nearest
  frost ≥ 4 chunks from origin. `d9479b6`
- [x] **C3 — saving inside a dungeon dropped the player into the void.**
  `GameState.dungeon_id`/`dungeon_floor` are saved and `_restore_dungeon_from_state()`
  rebuilds the interior on load. `d9479b6`
- [x] **C4 — dying in a dungeon leaked it and disabled every `visited_<settlement>`
  flag for the rest of the session.** `_leave_dungeon()` is the single teardown for
  exit, death and load. `d9479b6`
- [x] **C5 — dungeon walls had no collision, and the overworld kept streaming
  underneath.** Walls are four `StaticBody2D` bands; `ChunkStreamer.suspend()/resume()`
  stops overworld streaming while underground. `d9479b6`
- [x] **C6 — six screens each owned `get_tree().paused`.** New `PauseManager`
  autoload: the pause is a **set of holds**, the world is paused while at least one
  is outstanding, holders are pruned when freed, and a source scan in `UiTest`
  fails if anything outside the manager writes the flag. `11d5b31`

### 🟠 Serious

- [x] **G1 — repeatable quests were one-shot.** `_complete()` clears `took_<qid>`,
  so `next_offer()` can hand the job out again. `811b8b7`
- [x] **G2 — one greeting could finish a step gated behind a kill.** `talk_to()`
  advances only the quest's next unfinished objective (`next_objective()`). `811b8b7`
- [x] **G3 — a dialogue branch that could never be read.**
  `DialogueDB.pick()` ranks by `priority * 1000 + requires.size()`; the most
  specific branch wins. `811b8b7`
- [x] **G4 — the HUD silently dropped all but one active quest.** The tracker
  follows the player's own acceptance order, lists extra jobs one line each, and
  supports pinning from the quest log (`GameState.pinned_quest`, saved). `811b8b7`
- [x] **G5 — chest loot could be lost forever.** A chest banks its contents at open
  time and the falling coins/items are visual pickups, so leaving the chunk can no
  longer destroy a payout from a chest that is permanently opened. `811b8b7`
- [x] **G6 — stack sizes were decorative.** `add_item()` caps at
  `ItemsDB.stack_size`; materials stack 99 (they were authored at 1, which made a
  "gather 3" quest impossible the moment the field was enforced). `811b8b7`
- [x] **G7 — the gold-find talent also boosted selling.** `add_gold(amount, source)`
  applies the multiplier only to found money; the shop's sell path passes
  `"trade"`. `811b8b7`

### 🟡 Medium

- [x] **M1 — keyboard/gamepad interact used scene order, not distance.** One rule
  (`WorldInteractable.nearest_in_range()`) now serves the HUD and both input paths,
  and it survives a stale player reference. `1522335`, `01c1a77`
- [x] **M2 — the ending's Credits button did nothing.** It raises
  `GameState.pending_credits`; the main menu opens its credits layer on arrival. `1522335`
- [x] **M3 — the main menu's hills were hardcoded to 1280×720.** Every point is now
  a fraction of the live viewport. `1522335`
- [x] **M4 — one bad music id silenced the run.** `play_music()` validates the id
  before recording it as current. `1522335`
- [x] **M5 — entering a dungeon changed physics state during a physics flush.**
  The descent is deferred by a frame (the pattern `SecretGate` already used). `1522335`
- [x] **M6 — `ObjectPool.release()` could hand one node to two callers.**
  A repeat release is ignored. `d9479b6`
- [x] **M7 — death left the hero dead-looking.** `player.revive()` clears the death
  state and the sprite tilt on respawn. `d9479b6`

### 🟢 Low

- [x] **L1 — the epilogue printed a hardcoded `/206 quests`.** It reports
  `QuestManager.data.size()`. `1522335`
- [x] **L2 — `_inside_settlement()` used one radius for every town.** It reads the
  settlement's own data radius, the same value `_check_place_flags()` uses. `d9479b6`
- [x] **L3 — the minimap sampled 5,184 points every 0.3 s.** `CELLS` 72 → 48, which
  still resolves the authored 32 px tiles at full map size. `1522335`
- [x] **L4 — `Waypoint.registry` survived New Game.** `GameState.reset()` clears the
  static registry, so a new run only sees its own campfires. `1522335`
- [x] **L5 — the opening vendor sold a 2,965 g sword to a 50 g hero.** Bram's shelf
  and Factor Orlan's start at `wooden_club` / `short_sword` prices. `1522335`

## 2.2 What is genuinely still open

- [ ] **Playtest on a real Android device** — the one thing that cannot be done
  from here. `PLAYTEST.md` is the checklist: performance, heat, touch reach,
  readability in daylight, and whether the balanced numbers are the right
  *experience*. Everything it turns up becomes a new item in this list.
- [ ] **Android performance profile** — folded into `PLAYTEST.md` §1; there is no
  trustworthy FPS/thermals number until the device pass runs.
- [x] **Cut the release tag** for this pass — **`v0.6.0`** (run 34613095209) published
  signed APK/AAB as a prerelease. That build then failed a check the tag itself made
  visible: the installed app reported `versionName 0.4.2 / versionCode 6`, because
  `export_presets.cfg` carries its own version fields that nothing kept in step with
  the tag. **`v0.6.1`** derives both from the tag (`2f5b9a9`). **`v0.6.2`** is the
  build worth side-loading: 175 MB → ~90 MB, with the artefact gate above.

---

# PART 3 — How any of this is verified

| Gate | Command / result |
|---|---|
| Gameplay suites (9) | Combat **250** · Items **82** · WorldMap **84** · Ui **46** · Npc **43** · Quest **69** · Secret **45** · Audio **56** · Playthrough **52** — all PASS |
| Balance band | `python3 tools/balance_report.py --check` → PASSED |
| Art parity | `python3 tools/make_idle_frames.py --check` → 49 sheets / 49 idle / 21 attack / 3 cast |
| World decor | atlas 11 columns; the shipped map is 4.73 % decorated (asserted ≥ 3 % and < 15 %) |
| Repo budget | `tools/check_repo_size.sh` (< 120 MB) |
| Release builds | `v0.6.0` → `v0.6.2` — signed APK + debug APK + AAB, prereleases, `versionName`/`versionCode` derived from the tag, size 175 MB → 67 MB |
| Release gate | `python3 tools/check_apk.py <artefact>` on every published file, plus `tools/check_apk_test.py` (4 fixtures) in CI |
| CI | `smoke-test` · `visual-capture` · `android-export` on every push to `main` |

Standing rules that keep Part 1 honest:

1. An item is ticked only after it is **made, tested and committed** — never when
   it is planned or half-done.
2. Every fix ships with the regression test that would have caught it.
3. Nothing already shipped is replaced to fix something else: the biomes, the
   Ember Warden and the four-beat story survive every pass (DECISIONS carries the
   reasoning).
4. Sizes are checked before every commit; art sources are parked, not deleted
   (`tools/pose_sources.sh park`).
