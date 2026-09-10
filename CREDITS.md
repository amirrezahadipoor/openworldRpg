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
| World tile atlas (procedural, `tools/worldgen/make_tileset.py`) | This project | CC0 | ✅ in repo (`assets/tiles/atlas.png`) |
| Authored world maps (Tiled JSON, `tools/worldgen/build_world.py`) | This project | CC0 (content) | ✅ in repo (`world/chunks/*.json` + compiled `.tscn`) |
| LPC character sheets (walk/attack/cast/hurt/death + equipment layers) | Liberated Pixel Cup contributors | CC-BY-SA-3.0 + GPL dual (verify per file) | ⬜ pending Phase 3/6 |
| 0x72 DungeonTileset II | 0x72 (itch.io) | CC0 | ⬜ pending Phase 2 |
| LPC tileset collection | LPC contributors | CC-BY-SA-3.0 / GPL (verify per file) | ⬜ pending Phase 2 |
| Music (title + 3 biome ambiences + combat; procedural `tools/gen_music.py`) | This project (synthesized) | CC0 | ✅ in repo (`assets/audio/music/`) |
| SFX pack (13 procedural WAVs, `tools/gen_sfx.py`) | This project (procedurally generated, seed 7) | CC0 | ✅ in repo (`assets/audio/sfx/`) |

> ⚠️ Anything CC-BY-SA additionally requires attribution in-game (credits screen) — handled
> when the assets are integrated, and noted here per asset.

## Fonts
| Font | Author | License | Status |
|---|---|---|---|
| Press Start 2P (UI default theme) | CodeMan38 | OFL-1.1 | ✅ in repo (`assets/fonts/PressStart2P.ttf`, via google/fonts) |
| UI 9-patch frames (panel9/button9, `tools/gen_ui_assets.py`) | This project | CC0 | ✅ in repo (`assets/ui/`) |
