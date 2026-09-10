# 🗺️ OpenWorld RPG — Roadmap v2 (Reality-Checked)

> **Goal:** a shippable 2D open-world action RPG for Android.
> Reviewed against the actual repo contents, not against claims. The previous
> build log is preserved at [ROADMAP-v1-buildlog.md](ROADMAP-v1-buildlog.md).
>
> **Honest headline:** the systems are done and verified. What's missing is
> content quality (real art/audio) and hardening (playtesting, release signing).

Legend: `[x]` done & pushed · `[~]` partially done · `[ ]` todo

---

## Corrections to the original v2 draft

The draft circulating as "Roadmap v2" was directionally right but had specific errors. Corrected:

| Claim in the draft | Reality |
|---|---|
| "~5,500 lines of GDScript" | **6,183 lines** across `scripts/` — more than stated |
| "10 scenes, 35 chunk files" | 35 chunks = **35 `.json` + 35 compiled `.tscn`** (70 files) |
| "re-verify the 120 MB repo budget" as an open Phase B task | Repo is **~14 MB (12 %)** of that budget. It is **not** a constraint. Dropped as a gate. |
| "Run the real Universal LPC SpriteSheet Generator … replace `assets/lpc/*`" | The 4 shipped `player_*.png` sheets **were** composited from real LPC layers by `tools/lpc_compose.py` — but they were **HEADLESS**: `body/bodies/*` in the LPC generator omits the head, which is a separate layer under `head/heads/*`, and the original composer never added it. The player — the most visible sprite in the game — was rendering with hair floating above a headless torso, in the shipped v1.0.0 APK. Fixed in B4; `lpc_compose.py` now refuses to build an archetype with no head layer. |
| "Pull real 0x72 DungeonTileset II" | Evaluated and **deliberately not used** — it is authored at **16 px**, while this project's grid is 32 px and its LPC characters are 64 px. Mixing them puts two pixel densities and two palettes on screen. Replaced by a native-32 px LPC outdoor set. Reasoning recorded in [CREDITS.md](CREDITS.md). |
| "This is why it reads as garbage on a phone" | Largely true — but **two code defects contributed as much as the art**, and the draft missed both: pixel art was bilinear-blurred (no `default_texture_filter`), and terrain was generated with per-tile randomness (a literal checkerboard). |
| "NPC portraits for dialogue (currently deferred)" | Still deferred, and worth saying why: portraits are a different art surface (large, face-on, expressive), not a slice of the isometric sprite sheets. Treat it as new art, not an integration task. |

---

## Phase A — Systems (DONE — keep as regression baseline)

- [x] World/chunk streaming, biomes, fast travel, secrets, day/night
- [x] Player movement/camera, dodge i-frames, virtual joystick
- [x] Combat core, abilities, hit feedback, enemy telegraphs
- [x] Enemy AI states, object pooling, boss (3-phase)
- [x] Inventory/equipment/consumables/loot/shop/currency
- [x] XP/leveling/talent tree (3 branches)/stat formulas
- [x] Quest engine + branching dialogue + quest log/tracker
- [x] Save/load (3 slots), settings, full menu set, responsive UI
- [x] Audio hooks, particles/juice, CI smoke + gameplay tests

**Regression baseline (re-verified after every Phase B commit):**

```
repo size gate ...................... OK (~15 MB / 120 MB)
JSON data validation ................ 41 files OK
headless import ..................... OK, 0 script/parse/compile errors
smoke: main.tscn (300 frames) ....... clean
smoke: main_menu.tscn ............... clean
tests: CombatTest ................... PASS (120 checks)
tests: PlaythroughTest .............. PASS (23 checks)
tests: AudioTest .................... PASS (35 checks)   [added in B5]
visual: capture_screenshot .......... 2 PNGs rendered    [added in B7]
```

---

## Phase B — Real Content  ← **in progress**

### B1. World tileset ✅ DONE
- [x] Replaced the procedural placeholder atlas with real **native-32 px LPC** terrain and props
- [x] Vendored upstream sheets into `assets/source/` via `tools/art/vendor_sources.sh` (reproducible + auditable)
- [x] `tools/art/build_atlas.py` — deterministic atlas build preserving the `gid = biome*8 + col + 1` contract
- [x] Per-biome palette derivation (recolour) instead of hand-picking three duplicated sheets
- [x] `tools/art/preview_world.py` — renders real chunks with the GID math from `chunk_renderer.gd`, so art can be reviewed without a GPU
- [x] Full attribution recorded in CREDITS.md (CC-BY-SA 3.0 share-alike honoured)

### B2. World terrain quality ✅ DONE (this pass)
- [x] **Root cause fixed:** terrain was stamped with `rng.random()` per tile → checkerboard noise. Now deterministic **value noise sampled in world space**, so patches are clustered *and* seamless across the 1024 px chunk borders.
- [x] **Roads:** were a stamped rectangle covering the whole path bounding box. Now a noise-perturbed ~30 px track.
- [x] **Forests:** obstacle tiles were single tree sprites (read as an icon grid). Now seamless **canopy masses**, which read as forest at the same density.
- [x] **Clearings** re-floor blocked tiles so plazas no longer look torn up.
- [x] Verified non-destructive: solids, hazards and all objects/spawners are **byte-identical** to the previous generator (see "Cosmetic-only guarantee" below).

### B3. Pixel-art rendering ✅ DONE
- [x] `project.godot` never set `textures/canvas_textures/default_texture_filter`, so Godot 4's **Linear** default was **bilinear-blurring every pixel-art sprite**. Set to `0` (nearest). One line, visible on every screen, and it was invisible in headless CI.

### B4. Character breadth ✅ DONE
- [x] `tools/lpc_compose.py` rewritten: 12 sheets from vendored LPC layers (was 4)
- [x] NPCs: Elder Rowan (elderly head), Hunter Kael, Merchant Bram — each distinct, idle-animated
- [x] Enemies: 5 distinct creatures (goblin / skeleton / orc / raider / shaman) replacing the
      single `placeholder/enemy.svg` blob that every enemy and the boss used to render as
- [x] Enemies animated from the composed sheet via `Sprite2D.hframes/vframes` — no new node
      types, no per-enemy scenes; `slash` on attack, `spellcast` for casters, `walk`/`idle` by state
- [x] Boss (Ember Warden) uses the orc sheet at 2.2× with per-phase colour tints
- [x] **Fixed: the player sprite was headless in the shipped build.** The head is a
      separate LPC layer the original composer omitted. `lpc_compose.py` now asserts every
      archetype includes a head layer (verified to fail when the layer is removed)
- [ ] NPC dialogue portraits — **still deferred** (separate art surface, not a sprite-sheet slice)

### B7. Visual verification ✅ DONE (new capability)
- [x] `tools/art/capture_screenshot.gd` — renders the **real game** under a virtual display and
      saves PNGs; wired into CI as a job that uploads screenshots as build artifacts
- [x] This immediately caught five defects that headless CI could never see:
      bilinear blur, checkerboard terrain, canopy blocks reading as black rectangles, a
      hard-edged mud circle for the camp floor, and enemies crushed to silhouettes by
      `Sprite2D.modulate`

### B5. Audio ✅ DONE
- [x] Real score: 6 tracks by Avgvst ("Generic 8-bit JRPG Soundtrack", CC-BY) —
      title + 3 biomes + combat + a new boss theme
- [x] Real SFX: 13 clips from Kenney's RPG Audio / Interface Sounds / Impact Sounds (CC0)
- [x] `tools/audio/vendor_audio.sh` vendors and renames to the registered ids
- [x] `_loopify()` now handles `AudioStreamOggVorbis` (it only handled WAV, so an OGG score
      would have played once and stopped instead of looping)
- [x] **Fixed a silent bug:** `boss_arena.gd` asked for `combat_theme` / `biome_meadows`,
      neither of which was ever registered — so the boss fight had **no music at all**.
      `AudioManager` no-ops on unknown ids by design, so it failed with no error anywhere.
- [x] `tests/AudioTest.tscn` adds a regression test for exactly this: every literal id passed
      to `play_music`/`play_sfx` anywhere in `scripts/` must be registered

### B6. Asset pipeline hardening — `[x]` NOT NEEDED (with reasoning)
- [x] Atlas packing / `crunch` pass — **skipped deliberately.** The atlas is a single
      256×96 PNG at **11 KB**, and the whole `assets/` tree is a few MB. `crunch` exists
      to pack many loose sprite files into an atlas; this project already ships one atlas
      plus 12 character sheets. Running it would add a build step and a tool dependency
      for no measurable gain.
- [x] Mobile texture memory — the 256×96 atlas and the 13×20×64 px character sheets are
      far below any mobile limit. `textures/vram_compression/import_etc2_astc=true` is
      already set in `project.godot`.
- Revisit only if the repo approaches the 120 MB budget (currently ~15 MB, 12%).

---

## Phase C — Playtest & Balance  `[ ]` TODO

- [ ] Full manual playthrough on a real or emulated Android device — **nothing in this repo has ever been played by a human on a phone**
- [ ] Difficulty tuning per biome tier (Meadows / Barrens / Frosthollow) by real combat feel
- [ ] Fix what the manual pass finds — it always surfaces bugs automated tests miss
- [ ] Performance profiling on actual low/mid-range hardware

> **Known caveat:** the automated suite runs **headless**, so it renders nothing. Every
> visual bug fixed in Phase B (the blur, the noise, the canopy readability) was invisible
> to it. CI proves the systems work; it cannot prove the game *looks* right.

---

## Phase D — Ship  `[~]` IN PROGRESS

- [x] **In-game credits screen** — done. It already existed, but its text claimed
      *"World tiles, UI art, audio: this project (CC0)"*, which became false (and a
      share-alike violation) once the real LPC atlas landed. Rewritten with complete
      attribution for the tile set, characters, score and SFX, in a scroll container.
- [x] Signed debug `.apk` produced by CI, attached to a GitHub Release
- [x] Fixed the release workflow **fabricating releases**: it hardcoded a `v1.0.0` fallback
      for non-tag dispatches, which silently published a "v1.0.0" release (with APK/AAB)
      from whatever was on `main`. That is why a v1.0.0 exists despite this roadmap listing
      it as future work. Now derives the version from `project.godot` and never hardcodes.
- [x] `.aab` **built** for ARM64 + ARMv7
- [ ] `.aab` **verified on device** — building for an ABI is not the same as running on it.
      Covered by Phase C.
- [x] `CREDITS.md` final pass — every asset license logged and attributed in-game
- [x] Tag `v0.2.0` (flagged **prerelease**) with release notes → installable Android builds
      published: `.apk` 160 MB, `.aab` 58 MB, `-debug.apk` 172 MB
- [ ] **APK size is too large** — a 160 MB debug/release APK for a 2D game is mostly
      export-template weight and both ABIs. The 58 MB AAB is acceptable for Play, but the
      APK should be trimmed (per-ABI splits, strip debug symbols, check whether the
      export template is being embedded) before any wider distribution.
- [ ] **Tag `v1.0.0`** — deliberately NOT done. `v1.0.0` claims a shippable game, and
      Phase C (a human playtest on a device) has not happened. Tagging it now would be
      exactly the overclaiming this roadmap exists to correct.

> **Why v0.2.0 matters:** Phase C requires a build on a real device. The release workflow
> only produces signed APK/AAB on a `v*` tag, so cutting a pre-release tag is what makes
> the playtest possible at all.

---

## Cosmetic-only guarantee (how Phase B2 was de-risked)

Terrain rewrites are dangerous because the same grid drives collision, chests, gates,
waypoints and enemy spawns. Method used:

1. Re-ran the **committed** generator and confirmed its output is byte-identical to the
   committed chunks — so "the generator + its seed" *is* the previous world, and any
   difference is genuinely mine.
2. Made the new ground pass consume the RNG stream exactly as the old one did, so no
   downstream random feature moved.
3. Diffed the new world against the old, per chunk:

```
solids          35/35 chunks identical
hazards         35/35 chunks identical
objects/spawns   0/35 chunks differ
```

The world is visually new and mechanically untouched. This was verified, not assumed.

---

## What's left, in one line

Phase B is done: the game now has a real 32 px LPC world, real characters and enemies,
a real CC0/CC-BY score, a visual-capture harness, and shipped attribution. Remaining work
is **Phase C (a human playtest on a device, difficulty tuning, perf profiling on real
hardware) and Phase D (signed APK/AAB release)** — grind and QA, not architectural risk.
