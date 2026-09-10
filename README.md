# ⚔️ OpenWorld RPG

A complete, polished **2D open-world action RPG for Android**, built with **Godot 4** — real-time
combat with dodge i-frames, a chunk-streamed seamless world with 3 biomes, talent trees, quests
with branching dialogue, loot, shops, and full save/load. Built to ship: signed APK/AAB from CI.

> 📍 Status: **active development** — see [ROADMAP.md](ROADMAP.md) for the live checklist
> (ticked after every pushed subsystem), [DECISIONS.md](DECISIONS.md) for design decisions,
> and [CREDITS.md](CREDITS.md) for third-party licenses.

## Quick facts

| | |
|---|---|
| Engine | Godot 4.4.1-stable (GL Compatibility, mobile) |
| Target | Android (ARM64 + ARMv7), 60 FPS on mid-range hardware |
| Design resolution | 1280×720, `canvas_items` stretch, `expand` aspect, landscape |
| Repo budget | < 120 MB total (enforced in CI); toolchain lives in `/tmp/rpg-toolchain/` |
| Language | English |

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
