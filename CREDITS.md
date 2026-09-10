# 📜 CREDITS.md — Third-Party Tools & Assets

Every third-party tool and asset used by the game, with its license.
**Policy:** only CC0 / permissively licensed assets are committed. Each asset batch is
license-verified before commit and logged below.

## Engine & Tools (never committed to the repo — live in `/tmp/rpg-toolchain/`)

| Tool | Version | License | Source |
|---|---|---|---|
| Godot Engine | 4.4.1-stable | MIT | https://github.com/godotengine/godot |
| Godot Android export templates | 4.4.1-stable | MIT | https://github.com/godotengine/godot/releases |
| Tiled Map Editor | latest AppImage (authoring-only) | GPL-2.0 | https://github.com/mapeditor/tiled |
| Universal LPC Spritesheet Character Generator | git HEAD | GPL-3.0 (generator); assets: CC-BY-SA-3.0 / GPL (see below) | https://github.com/LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator |
| Pixelorama | latest (authoring-only) | MIT | https://github.com/Orama-Interactive/Pixelorama |
| crunch (atlas packer) | git HEAD | zlib/libpng | https://github.com/ChevyRay/crunch |

## In-Game Assets

| Asset | Author | License | Status |
|---|---|---|---|
| Placeholder SVG sprites (player, icons) | This project | MIT / CC0 | ✅ in repo (`assets/placeholder/`) |
| LPC character sheets (walk/attack/cast/hurt/death + equipment layers) | Liberated Pixel Cup contributors | CC-BY-SA-3.0 + GPL dual (verify per file) | ⬜ pending Phase 3/6 |
| 0x72 DungeonTileset II | 0x72 (itch.io) | CC0 | ⬜ pending Phase 2 |
| LPC tileset collection | LPC contributors | CC-BY-SA-3.0 / GPL (verify per file) | ⬜ pending Phase 2 |
| Music (per-biome ambient + combat theme) | TBD — CC0 sources only | CC0 | ⬜ pending Phase 11 |
| SFX pack (13 procedural WAVs, `tools/gen_sfx.py`) | This project (procedurally generated, seed 7) | CC0 | ✅ in repo (`assets/audio/sfx/`) |

> ⚠️ Anything CC-BY-SA additionally requires attribution in-game (credits screen) — handled
> when the assets are integrated, and noted here per asset.

## Fonts
| Font | Author | License | Status |
|---|---|---|---|
| UI font (TBD — e.g. a CC0/OFL pixel font) | — | OFL/CC0 | ⬜ pending Phase 10 |
