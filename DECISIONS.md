# 🧭 DECISIONS.md — Autonomous Decision Log

Every non-trivial decision made during development is recorded here, per the master prompt.
Format: `#id — title · date · rationale`.

---

**#1 — Engine & version pin** · 2026-09-10
Godot **4.4.1-stable** (Linux x86_64 editor binary + matching export templates), pinned with
SHA256 verification (fetched from the release's `SHA256-SUMS.txt`) in `tools/bootstrap_toolchain.sh`.
Renderer: **GL Compatibility** (best coverage on low-end Android GPUs). Everything engine-related
lives in `/tmp/rpg-toolchain/`, never in the repo.

**#2 — Base design resolution & scaling** · 2026-09-10
Base viewport **1280×720** (16:9), stretch mode **`canvas_items`**, aspect **`expand`**,
landscape locked. UI uses anchors/margins only (no fixed pixel positions) plus
`DisplayServer.get_display_safe_area()` offsets, so it scales from ~5" 720p phones up to
10"+ tablets and taller 19.5:9 / 20:9 screens with notch-safe margins.

**#3 — Repo size strategy (< 120 MB)** · 2026-09-10
Only final compressed art is committed (indexed PNG / WebP, atlases). No engine binaries, export
templates, generator tools, or raw intermediate output ever enter the repo. `tools/check_repo_size.sh`
runs locally and in CI as a hard gate. Placeholder art is SVG (bytes-sized) until real LPC/CC0 art lands.

**#4 — Language** · 2026-09-10
All in-game text, quests, dialogue, and UI are **English** (per spec). Code/comments also English.
A language-toggle stub will exist in settings (Phase 10) but ships English-only.

**#5 — Save format** · 2026-09-10
JSON at `user://save.json`, versioned (`"version": 1`) for forward migration. Covers GameState
(stats/xp/gold/inventory/equipment/quests/talents) + player position. JSON over binary Resources
for debuggability on Android.

**#6 — World streaming parameters** · 2026-09-10
Chunk size **1024 px**, stream radius **1** (3×3 loaded), update interval 0.25 s. Chunks are
`res://world/chunks/chunk_X_Y.tscn` when authored; otherwise a deterministic placeholder chunk
(3 biome palettes, seeded by chunk coords) is generated so streaming logic is testable before
Tiled content exists.

**#7 — Progression math (initial)** · 2026-09-10
XP to next level: `100 × 1.35^(level-1)`. +1 talent point per level across 3 branches
(Combat / Magic / Utility). Stats scale per level: +12 HP, +6 MP, +1.5 ATK, +1 DEF.
Difficulty curve: biomes are tiered (Meadows L1–4 → Barrens L5–9 → Frosthollow L10+);
tuning happens during the Phase 13 playthrough.

**#8 — Combat model** · 2026-09-10
Real-time action combat: directional melee via Area2D hit/hurtboxes, dodge roll with i-frames
(0.28 s, 0.6 s cooldown), attack cooldown 0.35 s with a 0.12 s active hit window. Cooldown-based
abilities come in Phase 4 part 2.

**#9 — Versioning & package identity** · 2026-09-10
Package `com.amirrezahadipoor.openworldrpg`, semver starting `0.1.0`, version code incremented
per release. Conventional-commit style messages; small atomic commits pushed after each subsystem.

**#10 — Security: credentials** · 2026-09-10
No tokens/keys are ever committed. CI uses GitHub Actions ephemeral `GITHUB_TOKEN` for artifacts.
Signing uses a CI-generated **debug keystore** for now; a release keystore can be added later as a
repository secret without code changes. *(Note: the PAT shared in chat should be rotated by the
owner once this pipeline is running.)*

**#11 — CI strategy** · 2026-09-10
Every push: repo-size gate → bootstrap (editor only) → headless import → 300-frame headless smoke
run of the main scene. On `main`: additionally full Android export (debug-signed APK) uploaded as
an artifact. GUT unit tests will be added alongside gameplay systems.

**#13 — Android export without Gradle** · 2026-09-10
CI first failed on two preset mistakes, both fixed the same session: (a) empty
`patches` must be `PackedStringArray()` (ConfigFile rejects `array[]`), and
(b) `gradle_build/min_sdk`/`target_sdk` are only legal when Gradle build is on.
Decision: ship the **non-Gradle template export** (faster CI, no Gradle wrapper
in the repo) and let Godot's engine defaults set min/target SDK. Gradle build can
be enabled later if plugins require it.

**#29 — Release builds & signing** · 2026-09-10
`v*` tags trigger `release.yml`: Gradle-based `--export-release` produces both the signed
APK and the Play-Store AAB from one run; a release keystore is generated per-run with
`keytool` (alias `openworldrpg`) so CI never stores secrets, and both binaries are attached to
an auto-created GitHub Release plus a 90-day artifact. Tradeoff documented: per-run keys are
fine for sideload/testing builds; a Play Store launch would rotate to a persistent upload key
(Play App Signing makes that safe). Version 1.0.0 / code 1 shipped with the tag.
Wiring notes: the committed preset carries empty `keystore/release*` lines that CI seds
to the per-run keystore (Godot 4.4 has no editor-settings fallback for release keys,
only `debug_*`); Gradle exports need the in-project build template, installed by riding
`--install-android-build-template` on the APK export command (a standalone invocation
never quits the editor loop); a side-loadable signed **debug** APK is attached too.

**#28 — Performance strategy & validation** · 2026-09-10
Low-end Android target: GL Compatibility renderer, one shared texture atlas for all world
terrain (single bind, batched `draw_texture_rect_region` per chunk; chunk `_draw` is cached by
the canvas server so it costs only on load), pooled projectiles (`ObjectPool` prewarm 16) and
respawning enemy slots, `CPUParticles2D` one-shots that self-free, chunk streaming radius 1
(3×3 = ≤9 chunks, ~1 draw list each), UI rebuilt only on open, minimap redraws at 3 Hz off the
render loop. Validation: CombatTest asserts pool reuse/zero-allocation reacquire and a headless
frame-budget smoke (60 physics frames on the live world must average < 33 ms; measured ~16.5 ms
on CI-class hardware). Real-device profiling remains the signed-build soak step (DECISIONS #13).

**#27 — Procedural music score** · 2026-09-10
Five seamless-loop tracks synthesized by `tools/gen_music.py` (pure stdlib, deterministic):
title, meadow, barrens, frost (ambience) + combat. ~22 kHz mono 16-bit, ~5.2 MB total, CC0 by
construction. Voices: detuned pads, plucks, inharmonic bells, bass, swept kick, noise hats, all
through a one-pole low-pass + tanh soft-clip; loop points made seamless with a tail→head
crossfade, and `AudioManager._loopify` marks streams LOOP_FORWARD at runtime. `AudioManager`
upgraded to dual-deck crossfade (1.4 s) so biome/arena switches never cut. In-game music follows
the player's chunk biome (frost / barrens / meadow) with a combat override inside 1250 px of the
Ember Warden arena; the title screen plays the title theme. Settings music volume drives the
active deck.

**#26 — Minimap + juice layer + transitions** · 2026-09-10
Minimap is a real terrain map, not a placeholder: a `Minimap` Control redraws at 3 Hz by
sampling the live `ChunkStreamer` tile grids (72×72 cells over ~2300 px), coloring by tile
column (path/hazard/obstacle/wall/ground per biome) with a deterministic palette fallback for
placeholder chunks, then overlays lit waypoints and a player facing arrow. It reads the same
authored data as the renderer — zero duplicated map info. Juice: a `Juice` node listens to
`EventBus` and emits self-freeing `CPUParticles2D` bursts (hit sparks, death puff, level-up
fountain, dodge dust, pickup sparkle); kill and boss-phase trigger a guarded `_hit_stop`
time-scale dip; player dodge/hurt squash-and-stretch the sprite. Scene changes route through a
`Transition` autoload (CanvasLayer 100) doing fade-out → `change_scene_to_file` → fade-in, so
every menu/game swap is tweened.

**#25 — Authored world: Tiled pipeline + interactables + fast travel** · 2026-09-10
The world is a hand-authored 7×5 chunk grid (35 chunks, 1024 px, 32 px tiles) shipped as
canonical **Tiled JSON maps** (`world/chunks/chunk_X_Y.json`, openable in Tiled 1.11) compiled
to `.tscn` by `tools/tiled_to_godot.py` — the compiler emits a `ChunkRenderer` (packed GID grid
drawn from one 256×96 procedural atlas, `tools/worldgen/make_tileset.py`, 21 KB), greedy-merged
`StaticBody2D` collision (hazard/obstacle/wall tiles), and typed object nodes (chest/sign/lever/
waypoint/gate/spawner). `build_world.py` regenerates all maps deterministically. Biomes: Verdant
Meadows (village + pond), Ashen Barrens (lava, rocks), Frosthollow Peaks (pines, ice lake); a
mountain wall with two gates separates north/south. All world state (opened chests, pulled levers,
lit waypoints) persists in `GameState.quest_flags` → zero save-format changes. Camp campfire is
the always-lit starting waypoint; 4 more unlock in the world; travel UI lists lit fires and
teleports + camera-snaps. Secret: a lever in the Barrens opens a stone gate sealing a Hidden
Grove chest (traveler_ring). `DayNight` (CanvasModulate, 480 s cycle) provides the tint cycle.
`ChunkStreamer` loads authored scenes when present, placeholders otherwise (fallback retained).

**#24 — Cooldown abilities + procedural SFX pipeline** · 2026-09-10
Two active skills complete Phase 4: **Whirlwind** (Q, 10 MP, 4 s CD — 1.4× ATK to all
enemies within 95 px, spin tween) and **Firebolt** (F, 12 MP, 2.2 s CD — friendly pooled
projectile, 1.2× ATK, 430 px/s). `Projectile` gained a `friendly` flag: friendly bolts use
collision mask 2 and `area_entered` → hurtbox routing; hostile bolts keep the legacy timer
path. **Hit routing fix shipped here**: hurtboxes are bare `Area2D`s, so melee and friendly
projectiles resolve damage on `area.get_parent()` (`take_hit` lives on the owner) — headless
tests now cover melee-via-hurtbox as a regression guard. HUD shows per-ability cooldown
readouts + MP-gating on the two new ActionButtons. SFX: 13 deterministic procedural WAVs
(22050 Hz mono 16-bit, seed 7) generated by `tools/gen_sfx.py` — pure code, CC0 by
construction, 281 KB total; filename == AudioManager SFX id, auto-registered via
`_register_builtin_sfx()`. Real recorded/released CC0 music + SFX can drop-in later by file
name without code changes.

**#23 — Game flow architecture** · 2026-09-10
Entry point is now `scenes/menus/main_menu.tscn` (title → Continue/New Game
slot picker → game). Scene transitions carry intent through GameState:
`current_slot` + `pending_load` (Continue & "quit to last save" reload the
slot; New Game resets state first). Death shows a screen with three exits
(respawn at camp / load last save / quit to title) instead of silent respawn.
Settings live in their own autoload (`SettingsManager`) applied on boot, and
screens that open from an already-paused context restore the prior pause
state on close (no accidental unpauses).

**#22 — Save slots** · 2026-09-10
3 slots (`user://save_N.json`), same versioned JSON schema as before; the
legacy single `save.json` migrates to slot 1 on first boot so no progress is
lost. Slot picker shows level/gold previews; New Game over an occupied slot
requires explicit confirmation.

**#21 — Story arc & content authoring** · 2026-09-10
Main arc in 4 quests: **First Light** (clear slimes, earn trust) → **The Ember
Omen** (midpoint twist: the "monster" is a corrupted guardian created by the
Elder's own hubris) → **Fall of the Warden** (boss climax) → **A New Dawn**
(ending). The q2 choice — *vow vengeance* vs *vow mercy* — is the meaningful
branch: it sets a flag that changes the epilogue text AND the final reward
(iron_sword vs traveler_ring). Side content: Hunter Kael offers a one-shot
hunt plus a **repeatable** cull (repeatable quests erase their state on
completion so dialogue can re-offer). Objective completion auto-raises
`<quest>_<objective>` flags so dialogue `requires` blocks gate on progress
without extra scripting.

**#20 — Dialogue architecture** · 2026-09-10
Dialogue = JSON files per NPC, each file an ordered list of conversations;
`DialogueDB.pick(npc)` returns the first whose `requires` (quest_active /
quest_done / flag / flag_not, all AND-ed, lists are all-must) matches —
**specific-before-general ordering is the author's contract**. Choice-level
and `on_complete` actions run through one executor (start_quest / set_flag /
complete_objective / give_item / give_gold / give_xp), so content never needs
code. Talk-objective completion is always explicit via dialogue actions
(never auto on talk) to keep choice moments inside active quests. Camp hub
(elder + vendor + hunter) is a fixed world location near spawn, built in code.

**#19 — Talent tree mechanics** · 2026-09-10
Kept the save-compatible model (`talents = {branch: points}`) but read it as a
**tiered node tree**: node N of a branch is active at ≥ N points, so points are
allocated per branch and nodes unlock in order. Display data lives in
`data/talents.json`; mechanical effects are real gameplay hooks in GameState
(`attack_cooldown_mult`, `mp_regen_per_sec`, `potion_mult`, `gold_mult`,
`dodge_duration_bonus`) consumed by Player/use_item/add_gold. 9 nodes total
(3 per branch), each with a distinct, testable effect — verified by tests.

**#18 — Boss design: The Ember Warden** · 2026-09-10
Single-author boss reusing the Enemy base via `Boss extends Enemy` and an
extracted `_finish_attack()` hook — no FSM duplication. Phases at 60%/25% HP:
P1 melee slam + every-3rd triple shot → P2 speed-up + 8-way radial bursts
(shorter telegraph) → P3 enraged 10-way radials + charge dashes (1.5× contact
dmg). Transformations give 1.2 s i-frames so DPS can't skip phases. Arena is a
fixed world position (BOSS_POS), summons on aggro proximity, defeat persists
via `quest_flags["boss_defeated"]` (survives save/load). Boss never flees
(`behavior=="boss"` guard in the flee check). Guaranteed drops: iron_sword +
health_potion (+50% traveler_ring), 60–90 gold, 250 XP.

**#17 — Gameplay test harness** · 2026-09-10
`tests/CombatTest.tscn` is a normal scene (autoloads active) that asserts real
behavior headlessly: enemy death → XP + loot pickups, gold pickup collection,
and potion stacking/removal. It quits with exit 1 on any failure, and CI runs
it after the smoke test. Test code is excluded from shipped APKs via
`exclude_filter="tests/*"`. New systems get a matching test before merge.

**#16 — Local headless gate before every push** · 2026-09-10
Started running `godot --headless --import` + a 400-frame smoke run locally
before pushing, because the first CI smoke gate exited 0 despite script
errors (process exit code is not a reliable health signal). CI now also
greps the smoke log and fails on any `SCRIPT ERROR`/`Parse Error`. This
caught a real `min()`-vs-`minf()` type-inference bug and a `get_name()`
clash with `Node.get_name()` before they shipped.

**#15 — Data-driven enemies + pooled loot** · 2026-09-10
Enemy archetypes live in `data/enemies.json` (melee grunt/scout/emberling,
ranged shaman) and are applied via `Enemy.setup_archetype()`, so adding an
enemy is data-edit, not code. Ranged attacks reuse a prewarmed projectile
pool (`PoolManager`, 16 nodes); spawner deaths recycle enemy nodes into an
`ObjectPool` and respawn each slot after 40s. Loot is rolled from per-archetype
drop tables into gold/item `Pickup` nodes with player magnet. Difficulty tiers
by biome: power_scale 1.0 / 1.6 / 2.4 (Meadows / Barrens / Frosthollow).
Spawn chunk (0,0) deliberately has no spawners — safe starting area.

**#14 — Enemy design baseline** · 2026-09-10
Single `Enemy` base class with FSM (idle/patrol/chase/attack/flee), exported
stat knobs (hp/speed/damage/radii/xp/color) so archetypes are configured, not
forked. Attacks are **telegraphed** (0.45 s wind-up, sprite pulses gold) before
the hit lands — dodge i-frames are the counter. Flee triggers below 25% HP.
Death grants XP immediately + tween-out; loot drops attach in Phase 6.
Temporary combat sandbox: 3 enemies near spawn until chunk-based spawning ships.

**#12 — Placeholder art policy** · 2026-09-10
Tiny inline SVG placeholders (player, icons) keep the repo near-zero size while systems are built.
They are replaced by LPC-generated character sheets and CC0 tilesets (0x72 DungeonTileset II, LPC
collection — per-asset license verified before commit) in later phases; placeholders are then deleted.

**#30 — LPC compositing pipeline (Phase 3)** · 2026-09-10
The upstream Universal LPC generator is a Vite/TypeScript web app with no
headless CLI, so `tools/lpc_compose.py` (PIL, toolchain-side) bakes the layer
stack (body → pants → shirt/leather armour → boots → hair → steel arming
sword) into four 832×1280 RGBA sheets: `assets/lpc/player_{none,leather}_{none,sword}.png`
(idle/walk/slash/spellcast/hurt × n/w/s/e, 64 px frames). Weapons have no
attack-row layers upstream, so attack/cast rows hold the combat-idle pose.
At runtime `player.gd` builds `SpriteFrames` from the active variant and
rebuilds within 0.5 s of an equipment change — equipment slots visibly drive
the sprite (paper-doll). Sheets are ~90 KB each (repo stays far under the
120 MB budget). All LPC layers are CC-BY-SA-3.0/GPL; attribution in CREDITS.md.

**#31 — Automated full playthrough validation** · 2026-09-10
`tests/PlaythroughTest.tscn` replays the entire authored main arc headless on
the live world: dialogue-driven quest start, kill objectives through real
enemy deaths, auto-flags, quest chaining with rewards, traveling to the
scorched ring (arena sighting flag), Ember Warden summon + 3-phase kill via
the real `BossArena`, and the closing elder conversation (q1→q4, 23 checks).
Runs in CI after the combat suite. The test player steps out of melee range
before the lethal blow so a death screen can never pause the tree mid-tween.

**#32 — Level curve re-tapered to 1-100 + milestone rewards (Phase E §6)** · 2026-09-10
The shipped curve (`100 × 1.35^(L-1)`) was a launch-scale formula that cannot
support 100 levels: `xp_to_next(100)` came out at **7.999×10^14 XP**, roughly
6.7×10^12 typical kills for the final level alone. It is replaced by the content
bible's three tapering segments — 1-20 `80 × L^1.8`, 21-60 growth ×1.3,
61-100 growth ×1.15 — for a total climb of **~5.71M XP** (was ~3.09×10^15,
a 540-million-fold reduction).

The bible's mid/late formulas restart from a small constant, which makes the
curve *decrease* at the seams (L20 costs 17,576 XP, but the authored L21 formula
wants 1,500 — leveling up would make the next level 12× cheaper, and the same
again at 60/61). Each segment is therefore **anchored to the previous segment's
terminal cost** while keeping the authored exponents and segment boundaries, so
`xp_to_next` is continuous and strictly non-decreasing. Both seams are asserted
in `tests/combat_test.gd`, as is a sanity ceiling on the level-99 cost.

`XP_MAX_LEVEL = 100` is now enforced (`add_xp` discards overflow instead of
looping forever on a 0-cost level). `data/milestones.json` adds 10 milestone
rewards (every 10 levels: gold, bonus talent points, a title, and permanent stat
effects summed by `GameState.milestone_bonus()`); claimed milestones are stored
in the save and shown as a HUD banner. `data/enemies.json` gains
`floor_multiplier` and `EnemyDB.floor_scale()`, so dungeon floor N scales
hp/damage/xp by `1 + floor_multiplier × (N-1)` — `Enemy.setup_archetype()`
takes an optional floor, and `EnemySpawner.floor_index` exposes it per scene.

**#33 — 60-node talent tree, data-driven effects (Phase E §7)** · 2026-09-10
The bible asks for 60 nodes (3 branches x 4 tiers x 5 nodes) while `DECISIONS
#19` shipped talents as **one integer per branch** (`talents[branch]`) with
9 hardcoded nodes. Rather than replace the model, the counter is kept — it is
what the three-column UI and every existing save are built on — and each node
in `data/talents.json` now declares `req_points` (points invested in its branch)
and `req_level` (character level).

- **Tier gates** open at levels 5 / 25 / 50 / 75. The nine originally shipped
  nodes (`Power Strikes`, `Iron Skin`, `Swift Strikes`, `Arcane Focus`,
  `Clarity`, `Potent Brews`, `Fleet Foot`, `Fortune`, `Shadow Step`) are marked
  `core: true` with `req_level: 1`, so a level-1 character keeps exactly the
  effects it had before — the expansion is purely additive, and the existing
  talent assertions still pass unchanged.
- **Effects are data**: additive keys (`atk/def/hp/mp/speed/mp_regen/dodge/
  lifesteal`) are summed by `talent_sum()`, multiplier keys (`atk_cd/potion/
  gold/xp/dmg_taken/whirl/bolt/mp_cost`) are multiplied by `talent_mult()`,
  floored at 0.4 so stacked "take less damage" nodes can never reach zero.
- **New nodes got real hooks**, not just numbers: lifesteal heals on melee and
  whirlwind hits, `whirl_mult()`/`bolt_mult()` scale ability damage,
  `mp_cost_mult()` discounts whirlwind/firebolt costs (the HUD shows the
  discounted number), `damage_taken_mult()` reduces incoming damage, and
  `xp_mult()` scales all XP gains. Each is exercised in `combat_test.gd`.
- `MAX_BRANCH_POINTS = 20` — a mastered branch refuses further points. Since
  100 levels plus milestone points exceed 60 nodes, a max-level character
  masters all three branches; an overflow/paragon sink is deliberately left
  for a later phase instead of being invented here.
- `node_active(branch, tier)` is retained (points >= tier) for the original
  call sites and the "next point" hint in the UI.


**#34 — NPC schedules, state machine and idle barks (Phase E §3)** · 2026-09-10
`NPCController` (`scripts/world/npc_controller.gd`) adds the four states the
bible names — `IDLE_SCHEDULE / WALK_TO_POINT / TALK / FLEE_COMBAT` — using the
same shape as the enemy FSM. `NPC` now extends it, so the existing interaction
surface (prompt, marker, `interacted` signal, vendor routing) is untouched and
every placed NPC inherits a schedule for free.

- **Clock:** schedules read the existing `DayNight` node through the
  `day_night` group (no second time system). `DayNight` joins that group in
  `_ready()`. `time_of_day_name()` gives the four slots (Dawn/Day/Dusk/Night).
- **Schedule data** lives in `data/npcs.json`: display name, settlement, role,
  story/shop function, and four offsets from wherever the NPC is placed — so one
  roster works in any settlement layout instead of hardcoding world positions.
  11 named NPCs ship, including the bible's whole main cast.
- **Barks** live with the dialogue they belong to: `data/dialogue/<npc>.json`
  gains a `barks` array (`{text, when[]}`) that `DialogueDB` loads alongside
  `dialogues`. `pick_bark()` filters by time of day and rotates so a line never
  repeats twice in a row. Ambient barks fire only while idle, only near the
  player, and are rate-limited; they surface through the same HUD banner the
  milestone rewards use.
- **No NPC is scenery:** interacting with an NPC who has no quest line for the
  current world state now answers with a bark instead of doing nothing.
- `TALK` holds the NPC in place and is released by `EventBus.dialogue_closed`,
  so conversations never walk away mid-sentence.
- `tests/npc_test.gd` (24 checks, wired into CI) covers roster coverage
  (every NPC: 4 slots, >=3 barks, a role + function), bark rotation and time
  filtering, schedule offsets, all four states, arrival at a schedule point,
  and fleeing from a nearby enemy.


**#35 — Settlements and multi-floor dungeons as real built scenes (Phase E §1)** · 2026-09-10
Biomes were one palette per chunk; §1 asks for actual places. `data/settlements.json`
defines 9 settlements — 3 villages (Millhaven, Oakstead, Frosthaven), 3 towns
(Ashport, Cinderhold, Kilnrest) and 3 cities (Sunreach, Ashvow, Skyreach Citadel) —
and `scripts/world/settlement.gd` builds each one as a scene: a paved plaza, a ring
of houses sized by tier (village 6 / town 10 / city 16 buildings), its own waypoint
and name sign, lantern rings, and the NPCs the data assigns to it. Layout is
deterministic per settlement id (`hash(id)` seeds the RNG), so a settlement looks
identical every session on every machine.

- **Two settlement names were invented**: *Ashvow* (the Ashen Choir's burnt seat,
  the Barrens city) and *Kilnrest* (the Frosthollow trade town), because the bible
  names 7 settlements but the acceptance criteria call for 9. Both are flagged
  here so they are easy to rename in one data file.
- **Safe ground**: `Settlement.safe_zone_at()` is consulted by the chunk streamer,
  which re-rolls (and if needed drops) enemy spawners inside a settlement's
  `safe_radius` — towns are not ambush corridors.
- **Plaza tinting**: the trodden-ground disc tints toward the biome palette, so a
  frost village doesn't get a meadow-brown mud patch on its snow (found by
  rendering, like every other visual defect in this project).

`data/dungeons.json` defines 9 dungeons totalling **26 floors** (2–4 each), and
`scripts/world/dungeon.gd` builds a floor as a walled interior: `floor_root` is
rebuilt on every descend/ascend, spawners are ringed around the room and carry the
floor's `floor_index`, which is what Phase E §6's `floor_multiplier` scaling reads,
so depth drives difficulty instead of hand-tuned `power_scale` per floor. Stairs are
physical: the "Down" stair descends, "Up" climbs, and on floor 1 the same stair reads
"Exit" and returns the player to where they entered. Interiors are built at
`DUNGEON_ORIGIN` — `GlobalPosition (200000, 200000)` — **after** `setup()` places the
dungeon, since `setup()` overwrites `position`; getting that order wrong left the room
on the overworld while the player stood in an empty chunk (also caught by rendering).

The **boss floor of `ember_warden_keep` instantiates the existing `BossArena`
unchanged** — §3 of the bible says the final fight is mechanically untouched, so
nothing about the three-phase fight was reimplemented.

`tools/art/capture_settlements.gd` renders all nine settlements plus two dungeon
floors from the real game. It teleports the player and calls `FollowCamera.snap()`,
because the follow rig lerps at `follow_speed = 8` and waiting only two frames
photographs empty space between chunks — the first run of this harness produced nine
grey voids for that reason.

**#36 — Rarity is a stat budget, lifesteal is a chance find (Phase F1)** · 2026-09-10
The ask was "100+ items that are rare in order of power" and "a chance that an item
gives a bit of lifesteal". Two consequences shaped the implementation:

- **Rarity is enforced, not decorated.** `tools/gen_items.py` gives each tier a
  weighted stat budget (common 12 / uncommon 26 / rare 48 / mythical 78 /
  legendary 120, weights atk 3.0, def 2.5, hp 0.35, mp 0.25, speed 1.2,
  mp_regen 25, crit 60, lifesteal 220) and refuses to emit an item that exceeds
  it. The shipped averages of weighted equipment power per tier are
  **8.5 / 18.5 / 33.3 / 60.2 / 99.6** — a strict ordering a player can feel, and
  one `Tests/ItemsTest` re-derives from the JSON rather than trusting the author.
- **Lifesteal only enters from rare up**, on 8 items (`leechthorn_dagger` .04 through
  `ashen_choir_heart` .15). Common/uncommon rolls can never produce it — asserted by
  800 rolls — so it stays a find worth chasing rather than a starter stat.
- The catalogue is 120 items: 35 weapons, 27 armour, 23 accessories, 12 consumables,
  23 materials. Consumables are lootable because every monster also rolls its tier's
  consumable pool; the four story materials (`first_flame`, `grain_sack`,
  `goblin_fang`, `warden_core`) are turn-ins/boss trophies by design.
- The inventory shows the ordering: rarity colour on the name, `★` at mythical and
  above, and a stat line like `+4 ATK · +12 HP · 4% LEECH`.

**#37 — Monsters are placed by data, dungeons by level band (Phase F2/F3)** · 2026-09-10
`tools/gen_enemies.py` authors 14 monsters in 6 tiers and 6 bosses, and derives each
biome's spawn table from the monsters' own `biome` + `level_band` fields instead of
the streamer holding a list. `ChunkStreamer._populate_enemies()` now reads
`EnemyDB.spawn_table(biome)` and `EnemyDB.band_power_scale(band)`, so "where does this
monster live" is answered in the roster, and a monster cannot appear outside its band.

- **Dungeons gained an authored `level_band`** (`data/dungeons.json`). Floors may mix
  biomes — an old crypt can hold things from anywhere — but every monster on every
  floor must have a level band overlapping the dungeon's, asserted per floor. This is
  what caught a tier-5 revenant sitting on the first floor of the low-level
  `hollow_crypts` alongside a husk.
- **A boss gate means a boss.** Six dungeons end on a named boss; `scorched_monastery`
  and `wardens_ascent` end on elite waves and are honestly flagged `boss: false` rather
  than pretending. `ember_warden_keep` still runs the shipped `BossArena`.
- **`DataBoss` needed a scene.** `Enemy` expects a `$Sprite` child, so a bare
  `DataBoss.new()` was a headless crash waiting to happen — `scenes/enemies/data_boss.tscn`
  now mirrors `enemy.tscn` with a slightly larger body/hurtbox, and `Dungeon` instantiates
  it on boss floors. The test spawns a real one, hits it through two hp thresholds and
  asserts the phases fire exactly once each, in order (a phase change grants 0.6s of
  transformation invulnerability, so the test waits physics frames between blows).
- `Scorched_monastery`'s final floor and `wardens_ascent`'s are harder than the floor
  above them (`power_scale`), and the deep-floor/boss-floor `power_scale` must rise with
  depth — also asserted, so "the last floor is the hard one" is a property of the data.


**#38 — The 100-step chain runs *inside* the four-beat spine (Phase F4)** · 2026-09-10
The ask was a 100-step main chain "with the story progressing to the end", while
the four-beat story (First Light → Ember Omen → Fall of the Warden → A New Dawn)
and its quest ids are frozen content. The chain therefore threads *between* the
first and second beats rather than replacing or renumbering anything:

- `q1_first_light.next` now points at **MQ001**; `MQ100.next` points at
  **q2_ember_omen**. q1–q4 keep their ids, names, objectives, rewards and
  dialogue — `tests/PlaythroughTest.tscn` still walks them in the live world.
- The 100 steps are **Act 2: the ash road** — Meadows (20), Barrens (32), Peaks
  (48) — taking the player from Millhaven's farm roads to the scorched ring, and
  ending on the line that hands over to the Ember Omen. The bible's Mireille
  expose/protect fork lands exactly on **MQ065**, implemented with the existing
  dialogue choice system: two branches, two branch flags, one shared resolution
  flag that the step's objective waits on.
- **Rewards are a slice of a level, not a level.** Each step pays 35% of
  `GameState.xp_to_next()` at its level anchor (1 → 92 across the chain); walking
  all 100 steps lands the character at ~level 60 with combat supplying the rest.
  The old hand-written formula (`80*L^1.8` per step) would have paid millions.
- **The chain is validated by walking it.** `tests/QuestTest.tscn` completes every
  step through the real APIs; the author (`tools/gen_quests.py`) additionally
  refuses to emit a step whose monster does not live in that region or whose
  level band is not open by the step's anchor (+8 levels of tolerance for players
  who wander off the road).
- **Two engine fixes the chain forced.** (1) Interacting with an NPC now calls
  `QuestManager.talk_to()`, so the 100 briefings' hand-ins do not each need
  bespoke dialogue wiring. (2) `QuestManager.active_snapshot()`: a single world
  event advances only the quests that were already active, because the chain's
  steps routinely ask you to talk to the NPC who just handed them over — without
  it, every hand-in auto-completed the next step in the same interaction.
- **The world now raises place flags**: `visited_<settlement>` on walking into a
  settlement, `entered_<dungeon>` on taking a stair, `cleared_<dungeon>` on
  killing its floor boss, `cleared_ember_warden_keep` when the Warden falls.

**#39 — `remove_item(id, 99)` is not "empty the bag"** · 2026-09-10
Two CombatTest checks failed one run in three: `GameState.remove_item()` returns
false and removes nothing when the bag holds fewer than the requested amount, so
the test idiom "clear the bag with `remove_item(x, 99)`" silently left whatever
the player happened to be carrying — including loot from an earlier section —
in the bag. The API is right (over-removal should fail), the idiom was wrong; the
tests now `GameState.inventory.erase(id)` to empty a slot. Found only because the
suite was run repeatedly while chasing a different flake: a single green run is
not evidence.

**#40 — Two flaky tests, two real races, both fixed at the source** · 2026-09-10
- *Melee hurtbox routing* called `player._resolve_attack_hits()` without awaiting
  it: the method is a coroutine that waits a frame for the overlap set, so the
  assertion raced its own attack, and the attack shape is only enabled during a
  swing's active frames. The test now waits for `attack_area.get_overlapping_areas()`
  to be non-empty (bounded retries) and awaits the coroutine.
- *collect/deliver* flakiness was `#39` above.
Both tests now pass 6 runs out of 6, which is the standard the suite is held to.

**#41 — 100 side quests: eight models in full, one twist each (Phase F5)** · 2026-09-10
"100 side quests, easy → hard" plus the standing instruction that bulk content
uses the template system. The implementation is eight **category models** written
out in full — objective shape, reward shape, voice — and 100 authored entries that
supply targets, counts, giver and one `twist` clause carrying that quest's own
story. `tools/gen_side_quests.py` refuses to emit a quest whose kill target does
not live in the quest's region, whose item nobody in that region drops, whose
place flag has no producer, or whose target is not open by the quest's level
anchor — so "easy → hard" and "in the right place" are properties of the data,
not of the prose.

- **Region comes from the work, not the giver.** `region_of_quest()` reads the
  monster's biome, the dungeon's biome, or where the item actually drops. People
  hire you for work that is not on their doorstep, and deriving region from the
  giver's settlement made a meadow bounty "belong" to a barrens NPC.
- **The board is a runtime board.** The first attempt wrote a level-gated offer
  entry into each NPC's dialogue file, which *silently shadowed hand-written
  lines*: DialogueDB picks the first matching entry, and several NPCs' files end
  with catch-alls that have no conditions at all. Ten of the eleven files would
  have lost their fallback dialogue. Instead `QuestManager.next_offer(npc_id)`
  serves the easiest untaken job the NPC holds, `offer_dialogue()` wraps it in the
  shape the dialogue box already understands, and `main.gd` shows it when nothing
  in the data wants the NPC — no second UI, no data duplication.
- **Goods quests hand goods over.** Fetch, Collection and Mystery use `deliver`,
  which consumes on completion. Used `collect` (non-consuming) instead, a player
  could accept "bring 4 slime gel" while carrying four, get paid, and keep them.
- **`_sync_flags()`.** A quest that asks you to reach somewhere you have already
  been is already satisfied — the rule `collect` has used since Phase E. Without
  it, escorts and mysteries could be impossible to finish for a player who had
  explored first, which is exactly the player these quests are for.

**#42 — Secrets are places, not a list: streamed, idempotent, never on the map (Phase F6)** · 2026-09-11
"Lots of secrets" is a promise about the *world*, so the implementation is 40
physical sites streamed in by `ChunkStreamer`, not 40 entries in a table the game
reads out. `tools/gen_secrets.py` authors them into `data/secrets.json` and refuses
to emit one that would be unreachable: wrong biome for its region, inside a
settlement's safe ring, or crowding another secret. Four kinds, deliberately
different verbs — walk over a cache, read a carving, stand at a landmark, pick a
vault's lock — so exploring is not 40 instances of the same interaction.

- **The live world had zero secrets.** The first version spawned them inside
  `_build_placeholder_chunk()`, which only runs when an authored chunk is missing —
  and the real map *is* authored (`res://world/chunks/*.tscn`). Streaming them from
  `_load_chunk()` instead covers both paths. The integration assertion that caught
  it (`streaming a chunk builds the secrets that live in it`) is in CI now; a unit
  test over the JSON alone would have reported everything fine forever.
- **Found is a flag, and finding is idempotent.** Discovery writes
  `secret_<id>` into `GameState.quest_flags`, which already rides the save blob, so
  reloading a chunk or a save cannot re-pay a find. `discover()` returns
  `{ok, already}` rather than throwing, and the test asserts the second call is
  refused *and* the purse did not grow.
- **Illegal-to-spawn during a physics flush.** Caches are found from
  `body_entered`, and instantiating an `Area2D` (the loot `Pickup`) inside a physics
  callback produces `Can't change this state while flushing queries`. The loot drop
  is deferred.
- **Secrets pay exploration, not the wallet.** Total secret xp stays below the main
  chain's total (asserted), and a vault's key is a material that genuinely drops in
  that region — so a vault is a lock you can actually open, not a decoration.
- **The playthrough test was running a paused tree.** Act 3 leaves the player in the
  warden's arena and the death screen pauses the game; Act 5 now takes the game's
  own respawn path (hide screen + emit `respawn_requested`) before walking to a
  secret, which is also why the streamer had silently frozen around the old
  position.

**#43 — Validate the workflow with actionlint before pushing (Phase F6 hotfix)** · 2026-09-11
Twice now a CI file has broken in a way `yaml.safe_load` cannot see: an unquoted
colon in a step name (Phase E §1) and, here, a `name:`-only replacement that
orphaned the following step's `run:` key into the previous step. Both parse as
valid YAML and both are **silently fatal on GitHub** — a duplicate key or an
unquoted colon makes the workflow invalid, so the push produces a run with **zero
jobs** and no error anywhere a normal log check would look.

`actionlint` catches both (`key "run" is duplicated in element of "steps"`). Any
edit to `.github/workflows/*.yml` now gets:

    actionlint .github/workflows/ci.yml && python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"

before the push, and a run reporting `name = .github/workflows/ci.yml` with
`jobs: 0` means *the file did not parse* — not "the tests failed".

**#44 — The balance pass: derived monster stats, one scaling law, prices that follow income (Phase F7)** · 2026-09-11
The pass was run against the whole shipped game with `tools/balance_report.py`,
which reads every number out of the data and the .gd sources rather than taking
anyone's word for it. It found the game far outside its own intent, and the fixes
went into the generators, so the curves rebuild themselves.

**Before → after** (measured at band midpoints, reference player = one talent point
per level spent evenly, median item of the tier their level has unlocked):

| measured | before | after | target |
|---|---|---|---|
| swings to kill a field monster | 0.4 – 6.2 | 1.9 – 5.6 | 2 – 8 |
| monster hits the player survives | 27 – 633 | 8.5 – 25 | 5 – 30 |
| kills per level (L5→L60) | 76 – 581 | 18 – 30 | 12 – 45 |
| boss fight length | 2.8 – 10.8 s | 28 – 100 s | 25 – 120 s |
| boss HP, weakest→strongest | 260 → 5,200 | 2,995 → 144,308 | escalating |
| field monster HP / damage | 14–600 / 4–46 | 47–1,318 / 11–280 | tier ladder |
| monster xp per kill | 14–300 | 38–4,544 | 12–45 kills/level |
| legendary gear price | 1,637 | 27,701 | ≈1 level of income |
| gear price step per rarity | 3.7x, 3.2x, 3.0x, 2.7x | any ≥1.5x | ≥1.25x |

- **Monster stats are derived, not typed.** `tools/gen_enemies.py` still owns each
  monster's *identity* — tier, biome, band, speed, behaviour, drops, sprite — and
  keeps the authored table's *relative* roles inside a tier (shaman 0.7 of the
  tier median, raider brute 2.0), but the absolute hp/damage/xp/gold now come from
  `tools/player_model.py` evaluated at the archetype's band midpoint: hp so the
  fight is a stated number of swings, damage so the player survives a stated
  number of hits, xp so a level costs a stated number of kills. The old numbers
  were authored once against a level-1 player and never revisited, which is how a
  level-30 character ended up killing tier-3 monsters in 0.4 of a swing.
- **One scaling law, not two.** `EnemyDB.band_power_scale()` is retired to a
  documented no-op. It scaled every spawn in a biome by `1 + 0.022 * (biome_lo - 1)`,
  i.e. barrens ×1.15 and frost ×1.81, *on top of* stats that are already band-scaled
  — double-counting two entire regions and making "frost is harder" a data
  accident rather than a band choice. `EnemySpawner.power_scale` still exists for
  one-off tougher spawns.
- **Prices follow income.** `tools/gen_items.py` priced gear off hand-picked
  constants (12/45/160/520/1500) that were set when the xp curve was a tenth of its
  size: by level 20 a player could afford the best item in the game, and gold
  stopped mattering entirely. Now a tier's median price is a fraction (0.8) of one
  level's kill income at the level that rarity unlocks, consumables cost about one
  kill of their band, and materials cost a few kills — trophies, not treasure.
  Common stays cheap on purpose (three kills at level 4): the first hour should be
  able to buy a better club.
- **The instrument is now a guard.** `tools/balance_report.py --check` exits
  non-zero when any measured target leaves its band, and CI runs it. The numbers in
  the report above were not written by hand; re-running the tool reproduces them.

**#45 — Do not write `"…" % [list]` in Python (Phase F7 tooling)** · 2026-09-11
The report crashed with `%d format: a real number is required, not list` on an
expression whose arguments were all numbers. Cause: `"%d" % [7]` does **not**
unpack — only a *tuple* does, so the list itself was handed to `%d`. Every
`% [ … ]` in a format expression is a latent bug of this kind: one conversion
silently takes the whole list, two or more raise. `tools/` is clean of the pattern
now (checked with a grep pass), and the fix pass is recorded here because the same
shape appeared in three different formatting sites in one file.

**#46 — The workflow is not valid until actionlint says so (Phase F7 CI)** · 2026-09-11
Applies #43 to every later workflow edit: the new balance step was inserted by
splitting a step's `name:` line, which YAML accepts and GitHub rejects (a run named
`.github/workflows/ci.yml` with zero jobs). `actionlint` caught it before the push,
as intended. The rule now holds for all three workflow files.

**#47 — A pool test is a test of the pool, not of the world (Phase F7 CI)** · 2026-09-11
CI failed F7 on `four pooled projectiles active` / `release returns nodes to pool`
while the same suite passed eight times locally. The cause was not the balance
change: the test counted *visible* members of the projectile pool, and the live
world had one of its own in flight at that instant (an enemy shot, a player bolt —
whichever the frame timing produced). The count is only meaningful if the pool is
quiet, so the test now releases whatever is already in flight, awaits a frame, and
baselines against that. It also asserts the boss kill with `max_hp * 2.0` instead
of a literal `99,999`, which stopped being lethal the moment the Warden's pool went
from 5,200 to 144,308 — a flat damage number in a test is a hidden coupling to the
data it is testing.

**#48 — The honest release: v0.3.0 pre-release, and the v1.0.0 ghost dealt with (Phase G)** · 2026-09-11
`release` run 34531514544 built and published **v0.3.0** — signed APK, AAB and a
side-loadable debug APK — as a pre-release, carrying the whole Phase F content
pass. Separately, the repository still had the accidental **v1.0.0** release from
the old hardcoded-version workflow bug: not a draft, not a pre-release, sitting
there as the project's "Latest release" and reading to any visitor as a shipped
game. It is now marked as a pre-release with a note explaining how it came to
exist, which is what it always should have been — the workflow fix stopped new
ones being fabricated, but nobody went back for that one.

README, `PLAYTEST.md` and the release body were rewritten in the same pass: the
old text still sold the game short by two phases ("audio placeholders", "credits
screen does not exist yet", "difficulty untuned"), which is a different failure
than overclaiming but a failure of the same document.

**#49 — The audit turned into a fix list: 13 categories, every deduction answered (fix pass 1)** · 2026-09-11
`reports/game-audit-2026-09-11.md` scored the build 5.8/10 and named a reason for
every deduction. That report is now the checklist, and the work is closed out in
this batch: side-quest description leaks, the "road to Wren" dead end, the MQ100
name clash, missing armour art for the ember warden, item effects that the budget
check rejected, invisible armour upgrades, portraits, the removed NPC, an ending
that stopped one beat early, no respec, bosses with no lines, the camp that could
not burn, barks that ignored the quest you were on, three settings that lied
(language, text scale, joystick size), 12–13 px fonts, no joypad map, a flat
unsorted inventory, and — the audio half — no buses, missing cues and a silent
world. Two items are deliberately *not* rewritten: the story and the 100/100
quest text stay as authored (the template system is the sanctioned method), and
the Warden's mechanics stay frozen.

**#50 — The borders had to move before the seams could be built (worldgen)** · 2026-09-11
The geographic complaint in the audit — "graphics 5.0", which the rigid biome
edges fed — was really two problems. First, the world was three rectangles:
`cy <= -1` winter, `cx >= 2` barrens, meadow elsewhere, borders you could walk
along in a perfectly straight line. They now breathe on a slow sinusoid
(`tools/worldgen/build_world.py`, mirrored in `scripts/world/biome.gd`), which is
also how 8 chunks changed biome — frost pushed as far south as y = 0 and the
barrens wedged in from the south-east — so no old save spoils by finding snow
where it used to farm. Second, a straight edge was invisible from three tiles
away. Along a seam the generator now scatters the neighbour's ground tile, which
costs nothing at runtime and reads as a transition instead of a cut. Music and
ambience read the *same* function (`Biome.name_at_position`), so the score can no
longer disagree with the map about where the player is — it used to, because
`main.gd` hardcoded the old straight lines. `WorldMapTest` re-derives every
chunk's stamped biome from the GDScript and fails if the two ever drift.

**#51 — Named places, and reasons to open a door (level design)** · 2026-09-11
"Level 7.5" came down to density of *place*: fourteen settlements, dungeons and
boss gates, and then a lot of ground with nothing to arrive at. The map now
carries **14 named micro-locations** — the Hollow Well, the Gallows Oak, the
Ferryman's Rest, the Standing Stones, the Slag Chapel, Cinder Well, Rime Orchard,
the Long Ladder, Hermit's Chimney, the Quiet Mile and the rest — each stamping
its own tile feature (ring, ruin, orchard, walls, pit, well) and each carrying a
sign with its own text. Two of them hide a **lever-gated cache**, using the lever
and gate scripts that already existed and had nowhere to be used. Dungeon floors
get the same treatment from the other end: every non-boss floor now builds a
sealed side-vault (lever, rock gate, chest, two torches), so a floor is a room to
search rather than a room to cross. Doors with nothing behind them were the
complaint; now every lever in the game opens something.

**#52 — The projectile that kept hitting: a pooled Area2D disarmed from inside its own signal** · 2026-09-11
CI caught this one, and it is the kind of bug that only shows up in a render. The
visual-capture job hung until its 25-minute timeout and printed exactly one
suspicious line: `ERROR: Function blocked during in/out signal. Use
set_deferred("monitoring", true/false)`.

The cause was in `scripts/combat/projectile.gd`. A projectile is pooled, so when it
connects it is *released* from inside its own `body_entered` / `area_entered`
handler — and release ran `monitoring = false` directly. Godot refuses that
assignment during the physics flush, the error aborts the assignment, and the
Area2D stays **live while parked on top of whatever it just hit**. The player walks
off and back, or jitters inside it, and takes damage again from a projectile that
does not exist any more. Headless suites never saw it (no enemy ever landed a shot
inside the window they ran); the rendered run did, and the hits it produced were
enough to kill the character, which opened the death screen — which pauses the tree
— which froze the capture node too, which hung the job.

Two fixes, because there were two faults:
* **The bug:** `_spent` is set the instant a projectile connects and both handlers
  bail out if it is set; `on_pool_release()` now uses
  `set_deferred("monitoring", false)`, and `on_pool_acquire()` re-arms both flags.
  Deferred calls run FIFO, so a re-acquire in the same frame still ends armed.
  `CombatTest` gained a section that fires a hostile projectile at the player,
  asserts the hit lands **exactly once**, asserts the pool's copy is genuinely
  disarmed, then walks out of its radius and back in and asserts zero phantom
  damage — three checks that would have caught the original defect.
* **The job:** the capture node is now `PROCESS_MODE_ALWAYS`, prints a diagnostic
  when it finds the tree paused (so a paused game produces a screenshot and a log
  line instead of silence), and carries a 90-second watchdog that fails fast with
  a clear message rather than burning the job timeout.

Lesson recorded: this is the same class of failure as `SecretSite._drop_loot`
instantiated inside `body_entered` (see the secrets pass) — **anything that
touches the scene tree or an Area2D from inside a physics signal has to defer**.

**#53 — Coasts, not staircases: biome ownership is per chunk, biome paint is per tile** · 2026-09-11
Decision #50 wobbled the borders, and the first render proved it only half-worked:
because biome was decided per *chunk*, every seam became a 32-tile staircase — three
rectangles replaced by a staircase is not obviously better. The fix separates two
questions that had been one. **Ownership** stays per chunk: `Biome.biome_of()`, the
`biome` property stamped in each `chunk_*.json`, music, ambience and the spawn tables
all keep reading a single value per 1024-pixel chunk, so nothing about gameplay or
streaming changes. **Paint** is now per tile: `tile_biome()` evaluates the same
sinusoidal border with a smooth noise offset of up to ~0.4 chunk in both axes, and
`neighbour_tile_biome()` finds the adjacent biome so the ground can blend across the
seam. Roads, clearings and micro-location features paint on the tile's own biome for
the same reason — a meadow-green road through snow was the alternative.

Two guarantees were held while doing it: the chunk grid is byte-identical to the
previous commit (same 8 chunks changed biome from the audit baseline), and the
generator's RNG stream is untouched, so every spawner, chest and tree sits where it
did and no balance number moves. The rendered capture from CI is the evidence —
`reports/rpg_shot_1.png` / `rpg_shot_2.png` now show a wavy coast where the earlier
capture showed steps.

**#54 — Fights are read, not mashed: enemy patterns and a three-hit chain** · 2026-09-11
The v2 audit's harshest gameplay number was combat variety (5.5): fifteen of twenty
archetypes shared one brain — walk straight at the player, swing on cooldown — and
every player click was the same click. Two changes, both small in code and large in
feel. Enemies now declare a `pattern` in `enemies.json`: **skirmish** (wolves,
scouts, emberlings and lizards circle instead of charging down the middle, so a
straight swing misses), **charger** (brutes, minotaurs, trolls and the Ashen Herald
back off to a 260 px standoff, telegraph for at least 0.55 s, then commit to a
locked 0.42 s dash at 2.9× speed — and stand **winded** for 0.9 s afterwards, taking
1.3× damage: the reward for reading the tell), **caster** (shamans, revenants and
archons hold a casting band and strafe inside it), and plain **melee** for grunts,
husks and legionaries. Bosses keep their own frozen mechanics and simply report
`pattern: "boss"`. The player side is a three-hit chain: two quick jabs, then a
finisher at 1.5× damage, a wider arc and a shove — paid for with 1.8× recovery, so
the chain trades sustained DPS for burst and does not move the balance bands.
`balance_report.py --check` still passes.

**#55 — The ledger and the words: nothing you were paid, or told, disappears** · 2026-09-11
Two audit deductions (quest log 5.5, economy 6.5) were really the same complaint:
the game paid you and spoke to you, and then had no memory of either. `GameState`
now keeps a **ledger** (`ledger_add` / `ledger_entries`, capped at 120, saved with
the slot) that quests write to on completion with a formatted reward line, purchases
and sales write to as they happen, level-ups write to, and travel tolls write to —
and a **dialogue history** (`record_line`, capped at 60) that records every spoken
line and every player choice, both surfaced as their own tabs in the quest log
(*Received*, *Heard*). The quest log itself stopped being one 306-row wall: it is
sectioned into *In hand*, *On the board*, *Finished*, *Received*, *Heard* and
*Everything*, with the untouched remainder of the story behind a single count
instead of two hundred `[Hidden]` rows that spoiled the size of the game.

**#56 — Gold has somewhere to go: local markets and a travel toll** · 2026-09-11
Economy was deducted for having exactly one sink and identical prices everywhere.
Every settlement now declares a `market` multiplier (Ashport 0.88 — a trading port
with cheap wares and poor prices; Ashvow 1.18 — a burnt city at the end of a bad
road), applied by the shop screen to both directions: buy `value × market`, sell
`value × 0.5 × (2 − market)`, so carrying goods between towns is a genuine trade
route rather than decoration, and the shop says which kind of town you are standing
in. Fast travel is no longer free: `Waypoint.travel_cost()` charges 6 gold per
1000 px beyond a 900 px walking range, the travel screen prints the fare on every
destination and greys out what you cannot afford, and `main.gd` re-checks before it
moves anyone.

**#57 — Secrets you have heard of are rumoured; secrets you have not are not drawn** · 2026-09-11
`secrets.json` had a `hint` field that no code ever read, and all forty hints were
byte-identical to the lore text. Hints are now authored per secret (a frame that
matches the kind of find, an eight-way bearing, a distance rounded to the nearest
100 paces, and a line about the terrain), `SecretsDB.hint_from()` speaks them with
`_bearing()`, and finding anything — or reading a carving — marks the secret it
points at as **rumoured**. The minimap draws rumoured secrets only, with a legend
that finally says what its colours mean (fire, hazard, wall, rumour). Walking into
a cache now leaves you with somewhere to go instead of just loot.

**#58 — Land ends at water: the shore column is used at last** · 2026-09-11
The tileset has carried a shore column since it was first authored and the world
generator never used it, so every pond and lake ended in a hard 32-px edge. The
generator now paints the shore tile on the ground directly above any water body
(the tile art has its water band along its bottom edge, so the two line up) and
clears the collision stamp there. Eleven tiles in the shipped world change;
nothing else does.

**#59 — Safe ground: measured, visible, and actually safe** · 2026-09-11
The safe zone was three separate half-measures. It was invisible
(`Settlement.safe_zone_at()` had no counterpart in the world), it was too wide —
every bubble was 90–130 px larger than the town it belonged to, which is what
"there are too many safe zones" actually meant — and it only stopped spawners
from *appearing* inside it: a wolf that had already seen you walked into town
behind you, and the starting camp, which hosts Elder Rowan, Hunter Kael and the
first merchant, was not safe ground at all. Now: `safe_radius` is the town radius
plus a 70 px walk-out margin (union 8.9% of the map, under the 15% ceiling, down
from 10.6%); settlements and the camp draw a ring on the ground at that edge;
`data/settlements.json` gains a `safe_zones` list (`Settlement.safe_zones()`), so
standalone safe ground exists as a concept and the camp is one of them;
`ChunkStreamer` pushes a spawn point radially outward instead of skipping the
spawner, so a chunk straddling a town is no longer an empty dead patch; and
enemies now hard-refuse: `Enemy._may_press_attack()` gates `_finish_attack` and
the charger's dash, `Player._protected_ground()` is the last gate before damage,
and a monster caught inside a bubble enters the new `WITHDRAW` state and walks
out — its `_origin` is pushed to legal ground (`_legal_origin`) so it can never
call the middle of town home. `tools/safe_zone_report.py` prints the same
numbers the test asserts.

**#60 — The world stops pacing: rest, sleep off-screen, and a day you can read** · 2026-09-11
Every enemy ran an infinite `IDLE 1.5 s → PATROL ≤5 s → IDLE` loop for as long as
its chunk was loaded, off-screen included, which is what "excessive circling"
looked like. Enemies now count their patrols (`PATROLS_BEFORE_REST`) and then take
a real 18–32 s rest; `_awake()` keeps anything beyond 900 px from animating a
patrol at all; `_separation_vector()` pushes clustered enemies apart instead of
letting them jitter through each other; and `DayNight.cycle_seconds` goes from 480
to 1200 s so an NPC's schedule point is somewhere they hold for three to six
minutes rather than something they are always walking toward.

**#61 — Nobody stands inside anybody** · 2026-09-11
Residents were placed by picking a random angle and a random radius of 0.30–0.55×
the town radius from the same RNG stream, and their schedules are offsets measured
*from wherever they landed* — so two neighbours could share a few pixels and stay
there all day. Seats are now deterministic (`Settlement._npc_seat()`: even angles,
two alternating rows, a `_seat_is_clear()` check in global space against every NPC
already in the tree, including the camp trio), and `NPCController._separate_from_neighbours()`
keeps a soft 46 px gap while walking and standing. Measured on the built
settlements: the closest pair of residents in the whole valley is 136 px apart.

**#62 — A conversation is not a combat zone, and neither is a town** · 2026-09-11
`EventBus.dialogue_open` is now plain shared state (not just a signal), set by the
dialogue box, and it is one of the two conditions that make the player
untouchable — the other being safe ground. Three layers enforce it: the enemy
never enters or continues an attack state, `_finish_attack` re-checks before
dealing damage, and `Player.take_hit` refuses at the bottom, which also covers a
projectile already in flight. Signed off in `combat_test` by four assertions that
run the real damage path both ways — protected takes nothing, unprotected takes
hits, so the suite cannot pass by accident.

**#63 — The fight reads: enemy bars, a boss plate, ground telegraphs** · 2026-09-11
Combat feedback was one sprite colour flash and a hit sound. Enemy now overrides
`_draw()` for two things that are only drawn when they matter: a floating 44 px
health bar above the sprite, raised by any hit and fading out over 3 s (and
redrawn only while it is visible — this runs per enemy on a loaded map, so it is
not a per-frame cost), and a ground telegraph — a filled disc at exactly
`attack_radius` for melee, a firing line for ranged — that fills in as the wind-up
runs, so "it is about to hit me" is readable from the floor rather than from a
64 px sprite's tint. Bosses join a `boss` group on setup and leave it on death,
which is how the HUD finds them: `_build_boss_bar()` (name, bar, one pip per
phase, polled each frame because a dungeon floor's boss does not exist when the
encounter signal fires) closes the worst hole in the game's most important fight.
Finally the swing window: hits used to be resolved by a single `await
process_frame` sample inside a 0.12 s window, which at 30 fps on a phone is one
sample per third of the window. The window is now 0.16 s and sampled on *every*
physics frame, with a per-swing hit set so a target cannot be hit twice; the
regression sweep runs the real swing at `Engine.physics_ticks_per_second = 30`.

**#64 — The touch layer actually works, and the HUD wears the game's clothes** · 2026-09-11
`ActionButton` called `Input.action_press()` and nothing else. That sets the
action's *polled* state, but every interactable in this game — NPCs, chests,
signs, levers, dialogue advance — listens in `_unhandled_input()` for an
InputEvent, and polled state never produces one. So Attack worked (the player
polls it) and the Talk button silently did nothing. Three fixes: the button now
injects a real `InputEventAction` through `Input.parse_input_event`, it holds the
action down for at least one physics frame so a same-frame tap cannot be
swallowed, and dragging a thumb off the button releases it. The Talk button is a
different kind of control now: it finds the single closest node in the
`interactable_in_range` group (every NPC and world interactable registers itself
on body overlap), shows the verb it would perform ("Talk", "Trade", "Open",
"Read", "Pull"), glows when something is in reach, dims and refuses when nothing
is, and becomes **Continue** while any screen is open — the HUD runs in
`PROCESS_MODE_ALWAYS` so the touch layer is not dead exactly when the player needs
it. Layout is two tiers (Attack + Dodge under the thumb, Whirl + Bolt one step
in, Talk above) instead of a five-wide row; the cooldown is a radial sweep as well
as a number; presses are acknowledged with a sound; the joystick has a dark
backing disc and doubled alpha so it reads on snow and sand; and all four safe-area
insets are computed (the old code found a top-left corner, threw away the window
size it had just read, and left the bottom-anchored controls unprotected). The
HUD itself is now wrapped in the game's `ui/theme.tres` panels and the placeholder
SVG icons are replaced by generated 32 px LPC-style art
(`tools/make_ui_icons.py` keys the magenta screen, despills the edges and
downsamples to the grid). New suite `tests/ui_test.gd`: 22 checks covering event
delivery, same-frame taps, target selection, the real NPC conversation firing,
cooldown sweeps, the toast queue and the insets.

**#65 — Idle-only frames are generated art, pasted by a measured pipeline (H5.5)** · 2026-09-11
The `IDLE` state can now last 18-32 s (H5.1), and the LPC layer library this project
vendors only ships **two** idle frames per direction — a monster resting for half a
minute was a statue with a twitch. The extra frames are therefore generated art, not
code: one image-gen sheet per character, laid out as four direction columns (LPC's
own n/w/s/e order) by two rows (weight shift, look-around), keyed off the same magenta
screen the UI icons use. `tools/make_idle_frames.py` does the pasting **measurably**
rather than by eye — it cuts the poses apart by empty-projection runs (so uneven
generator spacing cannot merge two poses), mirrors a side profile back when the
silhouette IoU against that direction's existing frame says the generator drew it
facing the wrong way, scales each pose uniformly to the reference frame's height and
re-pastes it on that frame's baseline and horizontal centre (no floating or sinking
between frames), and snaps every pixel to the reference frame's own palette. Output
goes into idle columns 2-3, so the idle loop became `[base, shift, breath,
look-around]` (`IDLE_LOOP`), slower by `REST_IDLE_SLOWDOWN` while resting, and a
resting monster also turns to a new facing every few seconds, because four idle frames
playing into a fixed facing still reads as a statue. `lpc_compose.py` calls the
patcher itself, so recomposing a sheet cannot throw the art away (verified: recompose
+ re-patch is byte-identical). `assets/lpc/idle_frames.json` is the manifest the
runtime reads; sheets that are not in it keep their two-frame idle, so this is
additive. `assets/lpc/_idle_src/` holds the generated sources at 40% scale — the full
resolution sheets (~1.5 MB each) would not fit the 120 MB repo budget, and the tool
only needs ~2x the 64 px target. Payload so far: 10 of 21 character sheets (the
image generator is capped at 10 sheets per pass); the remaining 11 are the same
pipeline, no new code. Verified by `items_test` (frames exist, differ from frame 0,
do not overflow their column) and `combat_test` (each archetype reports its sheet's
frame count, the idle loop really plays four distinct columns, resting slows the loop
and looks around).

**#66 — Buildings become whole sprites on the 32 px grid (H6.1, art pending)** · 2026-09-11
A settlement's houses were a wall quad, two `Polygon2D` roof slopes and a door
rectangle, tinted per biome — cardboard next to LPC terrain and 64 px characters.
`tools/make_facade_sheets.py` turns one generated sheet per biome family (three:
meadow, barrens, frost — the biomes the nine settlements actually use) into an
atlas of **whole buildings**, and `Settlement._build_facade_house()` draws them as
region sprites. Buildings are baked whole rather than assembled from wall/roof
tiles on purpose: a generated tileset cannot be trusted to seam (corners, slopes
and ridge lines must line up exactly), while a whole building only has to be cut
out and scaled. What the tool guarantees is the part that matters: sizes are
decided *relative to the family* (the typical building becomes 3 tiles wide, the
rest keep their ratio) and then rounded to whole 32 px tiles, so a hall is not
flattened into a cottage and everything lands on the world grid; the family's
buildings are quantised together to one 48-colour palette, because twelve slightly
different generator browns read as noise at 32 px; and each sprite is placed so
the art's bottom row lands on the house's ground line rather than hovering.
`house_scale` shrinks houses when a ring is crowded (96 buildings across nine
settlements), which is also how a city reads differently from a village. The
procedural houses stay as the fallback for any biome with no family, so a
settlement never blanks out — `world_map_test` measures both paths (0 facade + 96
polygon today; the same check flips to 96 facade houses as the art lands, and the
probe run that exercised the new path measured 28 facade + 68 polygon with every
house inside its size band and sitting on the ground).

**#67 — Armed characters actually swing their weapon (4-direction attack anims)** · 2026-09-11
The player carried a sword and every enemy carried nothing: fifteen archetypes
punched, and the two attempts before this were invented shortcuts. What upstream
actually ships is a weapon **split across films**: per-animation *hold* sheets on
the 64 px canvas, and a `slash_128` / `slash_oversize` **attack** film on a 128 px
canvas — six frames per direction, drawn at 2x so the arc can leave the body's own
box — split into a behind half (zPos 9) and a front half (zPos 150), because a
swing crosses the body and cannot be flattened onto one side of it. That is exactly
what `tools/lpc_compose.py` now consumes: the attack film is halved onto the 64 px
grid (verified pixel-aligned against the body: the blade lands in the hand),
composited *under* the character and then again *over* it, and mapped to the slash
block so each archetype's attack is a real six-frame swing per direction rather
than a wind-up. The longsword's frames are not even in the LPC 4-row-per-animation
layout, which is why the old attempt pasted them misaligned — the arming sword's
`attack_slash/fg.png` is a plain 6x4 grid of 128 px cells and is correct.
Sixteen characters are armed: the player's four sword variants, raider, raider
brute (mace), goblin, skeleton, legion, minotaur (mace), troll (mace), the Ember
Warden (blade), and the goblin king, bone titan, frost giant, ashen herald. The
beasts (wolf, husk, lizard, rime stalker) and the casters (shaman, revenant,
archon, slag wraith, choir priest) are deliberately unarmed — they claw and cast,
which is what their spellcast block draws. Guarded by `lpc_compose.py --check`
(films exist, attack films are the oversize canvas with six frames, and no
composed sheet's attack block is just its walk) plus two checks in `items_test`
driven from the data: every physical archetype animates an attack in all four
directions, and it differs from the walk cycle.

**#68 — H6.1 landed: the settlements are drawn from generated facades** · 2026-09-11
The three families the nine settlements need (meadow, barrens, frost) are
generated, four buildings each, and every house in the game is now one of them:
**96 facade houses, 0 polygon houses**, measured by `world_map_test`. The
pipeline built for #66 did the work without changes — poses cut out by
empty-projection runs, sizes set relative to the family and snapped to whole
32 px tiles, one 48-colour palette per family — which is what "the art pass is
the only thing left" was supposed to mean. `_facade_src/` holds the raw sheets
(5.9 MB, `.gdignore`d so they are never imported or shipped).
Also of note: the image generator failed one request with `MAX_TOKENS` (it
returned text instead of an image); re-issuing the same prompt worked, so a
generation failure is worth one retry before it is treated as a dead end.
Also: the new art step failed its first CI run with `ModuleNotFoundError: No module
named 'PIL'` — the GitHub runner's Python ships no imaging library, so the workflow
now installs Pillow + numpy before the art checks (with a `--break-system-packages`
fallback). Any future check that reads a PNG from the runner needs the same step.

**#69 — The hero is a character too: generated swing + idle poses (H7.2)** · 2026-09-11
The enemies got real swings (H7.1) and the hero did not: his attack was whatever
the shared LPC slash block shows at 6 fps, which reads as a slideshow rather than
"this is my sword". It is not fixed in the hero's code but in the same pose-art
pipeline the monsters use, because the hero's sprite is built exactly the way a
monster's is (equipment -> composed sheet -> frames). `PoseArt`
(`scripts/data/pose_art.gd`) now owns the manifest the whole game reads
(`assets/lpc/pose_frames.json`, written by `tools/make_idle_frames.py`):
`{"sheet": {"idle": 4, "slash": 4}}`, so a sheet without generated art keeps the
LPC frames and nothing has to guess. Generated art is pasted per animation —
idle into columns 2-3, attack into columns 0-3 of the slash block, **clearing the
rest of that row**, so a block only ever contains frames that will be played.
Four hero sheets (all four armour looks) got a four-pose swing: wind-up, begun
swing, impact, recovery, drawn in all four directions with the sword in hand, and
the loop/variant is picked per worn equipment like everything else. The generator
returned the poses *already matching LPC's own geometry* (frame-for-frame
comparable to the preset slash), which is why the alignment pass could scale them
to the reference frame without a custom offset. Two rules fell out of it:
  * a block made of generated art must not also composite the LPC weapon film, or
    the sword would be drawn twice — `lpc_compose.weapon_skips()` decides that
    from the same source folders the patcher reads, so the two cannot drift;
  * frame rate compensates only when the generated block is *shorter* than the LPC
    one (attack 4 vs 6) so the swing still lands inside `ATTACK_ACTIVE_TIME`; the
    idle loop, which is longer (4 vs 2), plays at the block's own rate rather than
    dragging.
For a hero sheet still without attack art the swing does not disappear: the
attack animation falls back to idle and a short rotation tween (`_tween_swing_fallback`)
carries the wind-up instead of an 8-frame slideshow. `combat_test` now checks the
hero path directly — per armour look: idle frames, attack poses, and the frame
count the animator really built — and the suite is 219 checks.

**Workspace hygiene (user request).** The workspace was over 100 MB, so the
scratch/prototype directory (`art-work/`, incl. all reference sheets) and the
`before_after.png` were moved to `/tmp/ws-scratch/`, the generated `.godot`
import cache (29 MB, regenerate with `--import`) was deleted and the pack was
repacked (`git gc`); the workspace is now 104 MB with the repo at 118 MB total
including `.git`. Rule going forward: only things the build needs (art sources
that `lpc_compose.py` regenerates from, generators, tests, docs) live in the
repo; scratch and exploration live in `/tmp`. Two more sources of bulk went the
same way: the `.godot/` import cache (14 MB, untracked, regenerated by any
`--import`, so it is deleted rather than kept) and `assets/ui/icons/_src/`, which
held ~1024 px generated sheets that the icon tool only ever keys and shrinks to
32x32 — halved to 512 px (8.6 MB -> 2.0 MB); re-running the pipeline changed
37-170 pixels out of 1024 per icon, i.e. the same art within the magenta key's
own tolerance. Workspace: 88 MB with the repo at 116 MB including `.git`.

**#70 — The weapon film is composited per column, not per block** · 2026-09-11
#69's rule ("a block made of generated art must not also composite the LPC weapon
film, or the sword is drawn twice") was right but stated one level too coarse: a
block is not necessarily all-generated. The idle patch fills only columns 2-3, and
when a sheet's old (unarmed) idle poses get pruned because the character picked up
a weapon, columns 0-1 are plain LPC frames — so a whole-block skip left the idle
loop popping between a bare hand and a sword (measured: column 0 bbox 30x48 with no
weapon, column 3 with one). `weapon_column_ok()` now answers per column, from the
same source folders and the same FIRST_COL/KEEP_COLS layout make_idle_frames.py
patches with, so the two cannot drift: armed sheets get the film in columns 0-1 and
none in 2-3, unarmed-idle sheets (skeleton) get it in all four, and walk/hurt/
spellcast always get it. Verified by bbox on the south idle row of goblin, raider
and minotaur.

**#70b — Deleting .godot/ costs a re-import before any test.** The workspace-size
pass deletes the generated import cache (14 MB, untracked). Without it, Godot
cannot resolve `class_name` globals and every suite dies instantly with
"Identifier X not declared in the current scope" — which looks like a code
regression and is not. Always run `godot --headless --import` after removing
`.godot/` (one import, ~10 s) before trusting a test result.

**#71 — The LPC weapon film is a slash arc, not a sword in the hand** · 2026-09-11
H7.1 claimed 16 armed characters "swing". Looking at the goblin's south slash
row, they do not: the LPC `attack_slash` film is a pale crescent that sweeps
past the body, so the melee read was an effect rather than a weapon. The film is
geometrically right — it is a clean 2x upscale (99.2% of 2x2 blocks uniform, so
halving lands it back on the 64 px grid) and compositing it over the matching
body row puts the arc exactly where the hand is — but LPC draws that animation
as a swing trail. The fix is not a better offset: it is the generated attack art
of H7.3, where the weapon is in the fist by construction. `weapon_column_ok()`
already suppresses the film per column once a sheet has real attack frames, so
generated art and the film never draw twice.

**#72 — Generated grids are only *usually* well-formed; cut what you can** · 2026-09-11
Two generator habits cost sheets today, and neither is worth failing over:
* More rotation columns than LPC has directions (the shaman returned six evenly
  spaced facings): sample four evenly across the run list — back, both profiles,
  front — and say so in the log.
* Poses that touch, so two of them read as a single pixel run (the minotaur's
  raised mace met the pose above it, and two of its four columns merged): split
  that column's ink evenly into the expected number of rows instead of raising.
  A column with *extra* runs keeps the topmost ones, which are the ones that
  start at the head.
Both are logged as `note:` lines, so a cut that needed help is visible in the
build output rather than silently guessed at.

**#74 — The art tests must know which block they are looking at** · 2026-09-11
`items_test` asserted that no generated block overflows its frames by checking
column `frames` of "the block", which it computed as `0 if idle else 2`. That was
true while only idle and slash art existed; the moment cast art landed it inspected
the *slash* block of the three casters, found the LPC swing frames that legitimately
live there, and failed. The art was right and the test was wrong — the lesson is
that the test now spells out all three block indices itself (0 idle, 2 slash,
3 spellcast) rather than deriving them from a two-case rule, so adding a fourth
kind has to be a deliberate edit on both sides.

**#75 — Composed sheets ship as exact-palette indexed PNGs** · 2026-09-11
The workspace ceiling (100 MB) started fighting the art pass: the repo's own bytes
are incompressible once written, and `.git` grows by roughly 2 MB per art commit
because PNG blobs do not delta. The reclaim came from the file format, not from
dropping art: a composed sheet is 33-200 distinct RGBA colours stored as 4 bytes
per pixel. Building a palette *from the image* (not fitting one to it) and writing
indexed PNG is exact — `tools/sheet_png.py` asserts nothing else, and the
conversion of all 53 sheets round-tripped with zero differing pixels — while
cutting them from 5.64 MB to 2.05 MB. Both writers (`lpc_compose.py`,
`make_idle_frames.py`) now save through the helper, so the next compose cannot undo
it. A sheet with more than 256 colours (none today) falls back to RGBA instead of
losing colour.


**#76 — Generated idle art must be the character it joins** · 2026-09-11
`tools/make_idle_frames.py` now refuses a source sheet whose corner pixels are not
the magenta chroma screen, and warns when a cut pose's silhouette overlap with the
frame it is joining falls below 0.70. Both guards come from real failures: the
husk's first attack sheet came back on a near-white background, keyed as *fully
opaque*, and cut as a single 576-px "pose" that the pipeline happily pasted; and
the elder's first idle sheet drew a bearded robed man rather than the grey-haired
villager, which the scale/palette-snap step made *look* plausible. A wrong
character is worse than no animation, so the elder sheet was reverted to its two
LPC frames and its source deleted; the warning names the sheet so the next batch
surfaces the same mistake in the run log.

**#77 — Villagers read the pose manifest for their idle loop (H5.6)** · 2026-09-11
`npc_controller.gd` no longer assumes two idle frames: `anim_frame_count()` asks
`PoseArt.count(sheet_path, "idle", IDLE_FRAMES)` and `advance_sprite_anim()` maps
its non-walk columns through `PoseArt.idle_columns(...)`, so a villager whose
sheet carries generated art wears the same `[base, shift, breath, look-around]`
loop the monsters breathe on, and every other villager keeps the two LPC frames.
`npc.gd` hands its `sheet_path` over when it applies the sheet (`settlement.gd`
sets `sprite_sheet`, exactly as the test harness now does). `NpcTest` asserts both
paths — frame count, loop order, the column the sprite actually shows, and the
two-frame fallback.


**#78 — The generation sources are parked outside the repo (workspace budget)** · 2026-09-11
The pose sources (`assets/lpc/_attack_src/`, `_idle_src/`, `_cast_src/`) are the
image generator's raw output: the inputs `tools/make_idle_frames.py` pastes from,
never read at runtime. At ~7 MB they were what pushed the workspace into its 100 MB
ceiling, while the sheets they produce are 2 MB. They are now parked in
`/tmp/ws-scratch/pose-sources/` (`tools/pose_sources.sh park|restore`) and no
longer tracked; every check CI runs — `lpc_compose.py --check`,
`make_idle_frames.py --check`, the facade check — reads only the composed sheets
and the manifest, and all three were verified green with the sources absent. So
the loss cannot be silent, `lpc_compose.py` now *refuses* to compose a sheet whose
manifest entry promises generated art when its source is not on disk: the old
behaviour would have written a source-less sheet and then dropped the manifest
entry, quietly deleting animation the game ships. Earlier batches' sources stay
recoverable from history (`git log --diff-filter=D -- assets/lpc/_attack_src`, which
`tools/pose_sources.sh restore` walks automatically), and sources that were never
committed can still be lifted out of the object store while they are unreferenced
(`git fsck --no-reflogs --unreachable | grep blob`) — how this batch's eight files
were recovered after a parking test cleared /tmp; re-patching from the recovered
sources reproduced the committed sheets byte for byte.


**#79 — The low-match warning was naming the wrong thing** · 2026-09-11
`normalise_pose()` grew a warning that names the sheet whose generated pose does
not look like the frame it is joining (DECISIONS #76), but the local loop that
picks between a pose and its mirror already used `tag` as its loop variable, so the
parameter was clobbered and every warning printed "flipped is only N% like the
frame it joins". Renamed the loop variable. The guard immediately earned its keep
in the batch that followed: five notes named `enemy_husk` and nothing else — the
husk's *attack* poses sit at 54-70% silhouette overlap with a standing frame, which
is exactly what a punch should do, while all nine villagers passed.
