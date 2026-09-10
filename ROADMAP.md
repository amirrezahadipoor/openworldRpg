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
- [x] Godot version pinned (**4.4.1-stable**) + SHA256 verification in bootstrap

## Phase 1 — Project Scaffold
- [x] `project.godot` — Godot 4.x, GL Compatibility renderer, touch emulation
- [x] Base design resolution chosen & documented (**1280×720, `canvas_items` + `expand`**) → DECISIONS.md #2
- [x] Folder structure: `scenes/` `scripts/` `assets/` `data/` `ui/` `world/` `tools/`
- [x] Autoloads: `EventBus`, `GameState`, `SaveSystem`, `AudioManager`
- [x] Input map (keyboard + touch actions: move/attack/dodge/interact/pause)
- [x] Android `export_presets.cfg` (package name, ARM64 + ARMv7, minimal permissions)
- [ ] Adaptive icon + full icon set (mdpi → xxxhdpi)

## Phase 2 — World & Chunk Streaming
- [x] `ChunkStreamer` — loads/unloads chunks around player (radius 1, 1024 px chunks)
- [x] Deterministic placeholder chunks (3 biome palettes) so streaming is testable now
- [ ] Tiled pipeline: `.tmx`/JSON → Godot scene importer (`tools/` converter)
- [ ] Authored chunks for **Biome 1: Verdant Meadows** (starting area + village)
- [ ] Authored chunks for **Biome 2: Ashen Barrens** (midpoint area)
- [ ] Authored chunks for **Biome 3: Frosthollow Peaks** (climax area)
- [ ] Collision layers for world geometry
- [ ] Day/night tint cycle (or region-based lighting variation)
- [ ] Interactable objects (chests, levers, signs)
- [ ] ≥1 hidden/secret area
- [ ] Fast-travel unlock points + fast-travel UI

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
- [ ] Cooldown-based abilities (≥2 active skills)
- [x] Floating damage numbers (`DamageNumber` — hits + XP gains)
- [x] Hit feedback: flash, knockback, hit-stop *(flash + knockback + screenshake; hit-stop later)*
- [x] Enemy telegraph system (0.45 s wind-up, gold pulse before attack lands)

## Phase 5 — Enemy AI & Boss
- [x] Enemy base controller + state machine: `idle / patrol / chase / attack / flee`
- [ ] ≥3 enemy archetypes (melee, ranged, fast)
- [ ] Object pooling for enemies & projectiles
- [ ] Death → loot drop → respawn handling
- [ ] **Boss fight with multi-phase pattern** (≥2 distinct phases)

## Phase 6 — Items & Economy
- [x] `data/items.json` item database seeded (weapons/armor/consumables)
- [x] Inventory model in `GameState` (stacking, add/remove)
- [ ] Inventory UI screen (grid, tooltips, use/equip/drop)
- [ ] Equipment slots (weapon/armor/accessory) affecting stats
- [ ] Equipment drives LPC sprite layers (paper-doll)
- [ ] Consumables (potions etc.) with effects
- [ ] Loot drop system (drop tables)
- [ ] Currency (gold) + vendor/shop NPC

## Phase 7 — Progression
- [x] XP curve + leveling (`GameState.add_xp`, growth 1.35)
- [x] Talent points awarded per level
- [x] Stat formulas (HP/MP/ATK/DEF/SPD) driven by level + talents
- [ ] Talent tree UI — **3 branches** (Combat / Magic / Utility), allocatable points
- [ ] ≥2 talents per branch with real gameplay effects
- [ ] Gear contributes to final stats

## Phase 8 — Quests & Narrative
- [ ] Dialogue system — data-driven (`data/dialogue/*.json`), typewriter UI, portraits
- [ ] Branching dialogue with **≥1 meaningful player choice**
- [ ] Quest engine: objectives, counters, flags, complete/fail states
- [ ] Quest log UI + HUD quest tracker (tracker label scaffolded)
- [ ] Side/repeatable quests (≥2)
- [ ] Main story arc authored (beginning → midpoint twist → climax → ending), English

## Phase 9 — Save/Load & Meta
- [x] `SaveSystem` — JSON at `user://save.json` (state + position; versioned)
- [x] Save on demand from pause menu; auto-load on boot
- [ ] Save slots (≥2) + overwrite confirm
- [ ] Settings menu: music/SFX volume, control sensitivity, language toggle stub
- [ ] Settings persistence

## Phase 10 — UI/UX & Responsive Layout
- [x] HUD scaffold: HP/MP bars, XP/gold readout, quest tracker, minimap placeholder
- [x] Pause menu (resume/save/quit) with correct `process_mode`
- [x] Anchors/margins + `DisplayServer` safe-area handling (notch/cutout)
- [ ] Minimap (real: chunk map + player arrow + POIs)
- [ ] Main menu (New Game / Continue / Settings / Credits)
- [ ] Inventory screen (see Phase 6)
- [ ] Talent tree screen (see Phase 7)
- [ ] Death / game-over screen with respawn flow
- [ ] UI polish pass: fonts, 9-patch panels, consistent theme across 720p→1440p+ & 16:9→20:9

## Phase 11 — Audio & Polish
- [ ] `AudioManager` registries wired to real CC0 assets (music per biome + combat theme)
- [ ] SFX: attack, hit, pickup, UI click, dodge (CC0 only → CREDITS.md)
- [ ] Particles: hits, spells, pickups, level-up
- [ ] Tweened scene transitions (fade)
- [ ] Juice pass (hit-stop, screenshake tuning, squash)

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
