# ⚔️ OpenWorld RPG

A complete, polished **2D open-world action RPG for Android**, built with **Godot 4** — real-time
combat with dodge i-frames, a chunk-streamed seamless world with 3 biomes, talent trees, quests
with branching dialogue, loot, shops, and full save/load. Built to ship: signed APK/AAB from CI.

> 📍 Status: **v1.0 feature-complete** — see [ROADMAP.md](ROADMAP.md) for the live checklist
> (ticked after every pushed subsystem), [DECISIONS.md](DECISIONS.md) for design decisions,
> and [CREDITS.md](CREDITS.md) for third-party licenses. Signed APK/AAB are produced by the
> `release` workflow on `v*` tags and attached to the GitHub Release.

## Quick facts

| | |
|---|---|
| Engine | Godot 4.4.1-stable (GL Compatibility, mobile) |
| Target | Android (ARM64 + ARMv7), 60 FPS on mid-range hardware |
| Design resolution | 1280×720, `canvas_items` stretch, `expand` aspect, landscape |
| Repo budget | < 120 MB total (enforced in CI); toolchain lives in `/tmp/rpg-toolchain/` |
| Language | English |

## What's in the game

- **World** — 35 authored chunks (Tiled JSON → compiled scenes) across Verdant Meadows,
  Ashen Barrens and Frosthollow Peaks; gated mountain passes, a hidden grove secret,
  5 fast-travel campfires, day/night tint cycle, real terrain minimap.
- **Combat** — directional melee, dodge with i-frames, Whirlwind + Firebolt cooldown
  abilities, telegraphed enemy AI (idle/patrol/chase/attack/flee), the three-phase
  Ember Warden boss, damage numbers, hit-stop, particles and squash-and-stretch.
- **Progression** — XP/levels, 3-branch talent tree, stats (HP/MP/stamina/ATK/DEF/SPD),
  loot chests, stacking inventory, equipment affecting stats, consumables, shop economy.
- **Story** — 4-part main questline with branching, consequential dialogue, side and
  repeatable quests, tracked objectives, data-driven JSON dialogue.
- **Meta** — 3 save slots, settings (volume/joystick/language stub), main menu with slot
  picker, pause, death and fast-travel screens; procedural CC0 music + SFX.
- **Controls** — keyboard or touch: left virtual joystick; right buttons for attack,
  dodge, interact and the two abilities (with live cooldown readouts).

## Repository layout

```
scenes/    Godot scenes (main, player, later: enemies, ui screens)
scripts/   GDScript: autoloads/, player/, world/, ui/
assets/    final compressed art only (placeholder SVGs for now)
data/      JSON game data (items, dialogue, quests)
world/     authored chunk scenes (chunk_X_Y.tscn)
tools/     bootstrap_toolchain.sh, check_repo_size.sh
.github/   CI workflows (smoke test + Android export)
```

## Development setup

```bash
# 1. Fetch/verify the whole toolchain into /tmp/rpg-toolchain (idempotent, self-healing)
bash tools/bootstrap_toolchain.sh --editor            # editor only (smoke tests)
bash tools/bootstrap_toolchain.sh --editor --templates # + Android export templates
bash tools/bootstrap_toolchain.sh --authoring          # + Tiled/Pixelorama/LPC/crunch

# 2. Run the game (PC with touch emulation enabled in project settings)
/tmp/rpg-toolchain/bin/godot --path .

# 3. Headless smoke test (what CI runs)
/tmp/rpg-toolchain/bin/godot --path . --headless --import
/tmp/rpg-toolchain/bin/godot --path . --headless --quit-after 300 res://scenes/main.tscn

# 4. Repo size gate (must stay under 120 MB)
bash tools/check_repo_size.sh
```

## CI

Every push runs: repo-size gate → toolchain bootstrap → headless import → 300-frame headless
smoke run. Pushes to `main` additionally produce a debug-signed **APK artifact**.

## License

Code: MIT (see [LICENSE](LICENSE)). Assets: see [CREDITS.md](CREDITS.md) per asset.
