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
