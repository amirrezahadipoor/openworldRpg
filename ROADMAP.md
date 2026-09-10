# 🗺️ OpenWorld RPG — Build Roadmap

> **Goal:** 0 → shippable, complete 2D open-world RPG for Android (signed `.apk` + `.aab`).
> Derived from the master prompt. Every checkbox is a real deliverable — nothing decorative.
> **Rule:** push after every completed item; tick it here in the same or next commit.

Legend: `[x]` done & pushed · `[ ]` todo · commits referenced inline where useful.

---

## Phase 0 — Infrastructure & Rules
- [x] Repository initialized, `main` branch, push access verified
- [x] `ROADMAP.md`, `DECISIONS.md`, `CREDITS.md`, `README.md` created
- [x] `.gitignore` tuned for the **120 MB repo budget** (no binaries, no toolchain in repo)
- [x] `tools/bootstrap_toolchain.sh` — idempotent, self-healing, everything into `/tmp/rpg-toolchain/`
- [x] `tools/check_repo_size.sh` — hard gate against the 120 MB ceiling
- [x] GitHub Actions CI: headless Godot smoke test on **every push**
- [x] GitHub Actions CI: Android export job (APK artifact) on push to `main`
- [x] Godot version pinned (**4.4.1-stable**) + SHA512 checksum verification in bootstrap
- [x] Automated gameplay test suite (`tests/CombatTest.tscn`) run in CI — combat/loot/economy, exits non-zero on failure

## Phase 1 — Project Scaffold
- [x] `project.godot` — Godot 4.x, GL Compatibility renderer, touch emulation
- [x] Base design resolution chosen & documented (**1280×720, `canvas_items` + `expand`**) → DECISIONS.md #2
- [x] Folder structure: `scenes/` `scripts/` `assets/` `data/` `ui/` `world/` `tools/`
- [x] Autoloads: `EventBus`, `GameState`, `SaveSystem`, `AudioManager`
- [x] Input map (keyboard + touch actions: move/attack/dodge/interact/pause)
- [x] Android `export_presets.cfg` (package name, ARM64 + ARMv7, minimal permissions)
- [x] Adaptive icon + full icon set (mdpi → xxxhdpi; `tools/gen_icons.py`)

## Phase 2 — World & Chunk Streaming
- [x] `ChunkStreamer` — loads/unloads chunks around player (radius 1, 1024 px chunks)
- [x] Deterministic placeholder chunks (3 biome palettes) so streaming is testable now
- [x] Tiled pipeline: `.tmx`/JSON → Godot scene importer (`tools/tiled_to_godot.py`)
- [x] Authored chunks for **Biome 1: Verdant Meadows** (starting area + village)
- [x] Authored chunks for **Biome 2: Ashen Barrens** (midpoint area)
- [x] Authored chunks for **Biome 3: Frosthollow Peaks** (climax area)
- [x] Collision layers for world geometry (greedy-merged StaticBody2D rects)
- [x] Day/night tint cycle (CanvasModulate, 8-min day)
- [x] Interactable objects (chests, levers, signs, waypoints)
- [x] ≥1 hidden/secret area (Hidden Grove: ashen lever → stone gate → treasure
- [x] Fast-travel unlock points + fast-travel UI (5 campfires + Travel screen)

## Phase 3 — Player & Camera
- [x] Player `CharacterBody2D` with acceleration/friction movement
- [x] Facing, sprite flip, 8-directional support
- [x] **Dodge roll with i-frames** + cooldown
- [x] Camera follow with smoothing + `shake(power)` API
- [x] Virtual joystick (touch) feeding player input
- [x] Tap/hold action buttons wired through Godot's `Input` actions
- [ ] Player animation states (idle/walk/attack/hurt/death via LPC sheets)

## Phase 4 — Combat Core
- [x] Directional melee attack with hit/hurtbox areas
- [x] Attack cooldown + active hit window
- [x] `EventBus` combat signals (swung/damaged/dodged/died) + camera shake on hit
- [x] Hurtbox/damage component for enemies (`Hurtbox` Area2D, group `hurtbox`, `take_hit`)
- [x] Cooldown-based abilities (≥2 active skills: Whirlwind Q, Firebolt F)
- [x] Floating damage numbers (`DamageNumber` — hits + XP gains)
- [x] Hit feedback: flash, knockback, hit-stop *(all shipped)*
- [x] Enemy telegraph system (0.45 s wind-up, gold pulse before attack lands)

## Phase 5 — Enemy AI & Boss
- [x] Enemy base controller + state machine: `idle / patrol / chase / attack / flee`
- [x] ≥3 enemy archetypes (melee grunt/scout/emberling, ranged shaman) — data-driven via `data/enemies.json`
- [x] Object pooling for enemies & projectiles (`ObjectPool` + spawner pool + `PoolManager`)
- [x] Death → loot drop → respawn handling (drop tables, gold/item pickups, 40s respawn)
- [x] **Boss fight with multi-phase pattern** — The Ember Warden: 3 phases (slam/triple-shot → radial bursts → enraged charges), arena summon, persistent defeat

## Phase 6 — Items & Economy
- [x] `data/items.json` item database seeded (weapons/armor/consumables)
- [x] Inventory model in `GameState` (stacking, add/remove)
- [x] `ItemsDB` autoload (single source of truth for item lookups)
- [x] Inventory UI screen (item rows, tooltips, Use/Equip/Drop, stat sheet, pauses game)
- [x] Equipment slots (weapon/armor/accessory) affecting stats (atk/def/hp/mp/speed)
- [ ] Equipment drives LPC sprite layers (paper-doll) *(waits for LPC art)*
- [x] Consumables (potions etc.) with effects (heal/mana, consumed on use)
- [x] Loot drop system (drop tables in `data/enemies.json`)
- [x] Currency (gold) — earned from kills, shown in HUD/inventory · vendor NPC with Phase 8

## Phase 7 — Progression
- [x] XP curve + leveling (`GameState.add_xp`, growth 1.35)
- [x] Talent points awarded per level
- [x] Stat formulas (HP/MP/ATK/DEF/SPD) driven by level + talents
- [x] Talent tree UI — **3 branches** (Combat / Magic / Utility), allocatable points, T key / HUD star
- [x] ≥2 talents per branch with real gameplay effects (9 nodes: atk/def/hp, cooldown -20%, MP+regen, potion +35%, speed, gold +20%, dodge i-frames +0.08s)
- [x] Gear contributes to final stats (equipment_bonus in every stat formula)

## Phase 8 — Quests & Narrative
- [x] Dialogue system — data-driven (`data/dialogue/*.json`), typewriter UI, condition-based picking *(portraits deferred to art phase)*
- [x] Branching dialogue with **≥1 meaningful player choice** — mercy/vengeance vow changes ending text + final reward
- [x] Quest engine: objectives (kill/talk/flag), counters, flags, completion + rewards + auto-chains *(fail states: supported, none authored yet)*
- [x] Quest log UI (pause menu) + HUD multi-line quest tracker
- [x] Side/repeatable quests (≥2) — Hunter Kael: "Scouts in the Barrens" + repeatable "Emberling Run"
- [x] Main story arc authored (First Light → Ember Omen twist → Fall of the Warden → A New Dawn), English

## Phase 9 — Save/Load & Meta
- [x] `SaveSystem` — versioned JSON (state + position) at `user://save_N.json`
- [x] Save on demand from pause menu (shows slot); legacy save migrates to slot 1
- [x] Save slots (3) + overwrite confirm dialog; slot picker with level/gold previews
- [x] Settings menu: music/SFX volume, control size, language stub (English)
- [x] Settings persistence (`user://settings.json`, applied on boot)

## Phase 10 — UI/UX & Responsive Layout
- [x] HUD scaffold: HP/MP bars, XP/gold readout, quest tracker, minimap placeholder
- [x] Pause menu (resume/save/quest log/settings/quit) with correct `process_mode`
- [x] Anchors/margins + `DisplayServer` safe-area handling (notch/cutout)
- [x] Minimap (real: chunk terrain map + player facing arrow + lit waypoints)
- [x] Main menu (Continue / New Game + slot picker / Settings / Credits) — new game entry point
- [x] Inventory screen (Phase 6)
- [x] Talent tree screen (Phase 7)
- [x] Death / game-over screen (respawn / load last save / quit to title)
- [ ] UI polish pass: fonts, 9-patch panels, consistent theme across 720p→1440p+ & 16:9→20:9

## Phase 11 — Audio & Polish
- [x] `AudioManager` registries wired to real CC0 assets (5 procedural tracks: title/3 biomes/combat, crossfade + loop)
- [x] SFX: attack, hit, pickup, UI click, dodge + more (13 procedural CC0 WAVs via `tools/gen_sfx.py`)
- [x] Particles: hits, deaths, pickups, level-up, dodge dust (`Juice`)
- [x] Tweened scene transitions (fade via `Transition` autoload)
- [x] Juice pass (hit-stop, screenshake, squash-and-stretch)

## Phase 12 — Performance
- [ ] Atlas all sprites (crunch or Godot import) — single atlas per biome
- [ ] Object pooling verified for projectiles/enemies
- [ ] 60 FPS profiling pass (low-end target assumptions documented)
- [ ] Chunk streamer memory/CPU budget verified with 3×3 radius stress test

## Phase 13 — Ship It 🚀
- [ ] Full playthrough validation (main quest start → finish)
- [ ] Signed debug `.apk` produced in CI and attached as **GitHub Release** artifact
- [ ] `.aab` build verified (ARM64 + ARMv7)
- [ ] `DECISIONS.md` + `CREDITS.md` final review
- [ ] Tag `v1.0.0` + GitHub Release notes

---

### Repo budget status
| Check | Limit | Status |
|---|---|---|
| Repo size (incl. `.git`) | < 120 MB | ✅ enforced by `tools/check_repo_size.sh` + CI |
| Heavy tools | `/tmp/rpg-toolchain/` only | ✅ enforced by bootstrap design |
