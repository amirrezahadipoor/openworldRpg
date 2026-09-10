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
