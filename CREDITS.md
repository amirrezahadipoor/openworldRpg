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
| Placeholder SVG sprites (enemy/gold pickups; player placeholder replaced by LPC) | This project | MIT / CC0 | ✅ in repo (`assets/placeholder/`) |
| Authored world maps (Tiled JSON, `tools/worldgen/build_world.py`) | This project | CC0 (content) | ✅ in repo (`world/chunks/*.json` + compiled `.tscn`) |
| LPC character layers composited into `assets/lpc/player_*.png` (body male, hair bedhead, pants, shortsleeve shirt, boots basic, leather armour, arming sword steel — idle/walk/slash/spellcast/hurt) | Liberated Pixel Cup contributors | CC-BY-SA-3.0 + GPL dual | ✅ shipped Phase 3 (composited by `tools/lpc_compose.py`) |
| 0x72 DungeonTileset II | 0x72 (itch.io) | CC0 | not used — see tile-set decision below |

### World tileset (Phase B art pass) — `assets/tiles/atlas.png`

The world atlas is **built** by `tools/art/build_atlas.py` from the upstream sheets in
`assets/source/` (vendored by `tools/art/vendor_sources.sh`, so the build is reproducible
and every upstream author stays identifiable in-repo). Recolours and composites performed
by that script are derivative works and remain under the source licence.

| Source sheet | Authors | Licence | Status |
|---|---|---|---|
| `lpc_terrain/*` — "LPC terrain extension" (grass, dirt, water, snow, ice, lava, lavarock, redsand, sand) | Lanea Zimmerman (Sharm), Daniel Eddeland, Connor Sherson, Johann Charlot, Jonas Klinger, Mark Weyer, Cem Kalyoncu, Juan Rodriguez, Skyler Robert Colladay | CC-BY-SA 3.0 / GPL | ✅ used — grass/dirt/water/snow/ice/lava/lavarock/sand |
| `lpc_conifers.png` — "[LPC] Conifers" | bluecarrot16, b_o, Lanea Zimmerman (Sharm), Johann Charlot, Yar, Jetrel, Zabin, Hyptosis, Surt, KnoblePersona | CC-BY-SA 3.0 / GPL 2.0 / GPL 3.0 | ✅ used — green + snow-laden forest canopy, saplings |
| `lpc_forest_tiles.png` — "[LPC] Forest tiles" | Reemax, Sharm, Hyptosis, Johann C, Beast, William.Thompsonj, Tuomo Untinen | CC-BY-SA 3.0 / GPL | ✅ used — rock/cliff faces, flowered grass, boulders |
| `lpc_trees_dead.png` — "[LPC] Trees" | bluecarrot16, Jetrel, Zabin, Hyptosis, Surt, Buch, Johann Charlot, Stephen Challener, Gaurav Munjal, Ivan Voirol, Guido Bos, Yar, Paulina Riva (PauR), William.Thompsonj, Casper Nilsson, ansimuz, qubodup, Bart K., Blarumyrran, Lanea Zimmerman (Sharm), Leonard Pabin, Chris Phillips, Barbara Rivera, Talosaurus | CC-BY-SA 3.0 | ✅ used — bare/dead canopy for the Ashen Barrens |
| "[LPC] Plant Repack", "[LPC] Flowers / Plants / Fungi / Wood" | pennomi, laetissima, C.Nilsson, Sharm, Johann C, Reemax, bluecarrot16 | CC-BY-SA 3.0 | downloaded, **not** composited into the atlas |
| Kenney "Roguelike/RPG pack", "Roguelike Caves & Dungeons", "Tiny Town", "Tiny Dungeon", "Tiny Battle" | Kenney Vleugels (kenney.nl), with Lynn Evers | CC0 | **not used** — see below |

**Tile-set decision (recorded so this isn't re-litigated):** the Kenney packs are CC0 and
excellent, but they are authored at **16 px**. The LPC character sprites already shipping in
`assets/lpc/` are **64 px** (32 px terrain-equivalent) and this project's tile grid is **32 px**.
`[LPC] Conifers` explicitly notes *"Tiles are all 32x32, but some trees are multiple tiles."*
Mixing 16 px Kenney terrain with 64 px LPC characters would put two different pixel densities
and two different palettes on screen at once. The LPC outdoor family was chosen instead so the
world, the props and the characters all share one style.

**Share-alike note:** the atlas contains CC-BY-SA 3.0 material. It must not be relicensed as
CC0, and the attribution above must ship with the game. Per-file provenance is preserved in
`assets/source/CREDITS-*.txt` and `assets/source/lpc_terrain/COPYRIGHT`.

**Attribution is now shipped:** the in-game credits screen (`scripts/menus/main_menu.gd`)
lists every author above, plus Avgvst for the score and Kenney for SFX, and labels the
CC-BY-SA content explicitly as such. An earlier revision of that screen claimed
*"World tiles, UI art, audio: this project (CC0)"* — which became false (and a share-alike
violation) as soon as the real LPC atlas landed. Corrected in the Phase B5 pass.

| Asset | Author | License | Status |
|---|---|---|---|
| 0x72 DungeonTileset II | 0x72 (itch.io) | CC0 | not used (LPC 32 px outdoors family chosen for style consistency — see above) |
| LPC tileset collection | LPC contributors | CC-BY-SA-3.0 / GPL (verify per file) | superseded by the specific sheets listed above |
| Music — **superseded, see below** (was procedural `tools/gen_music.py`) | This project (synthesized) | CC0 | ❌ removed in Phase B5 |
| SFX — **superseded, see below** (was procedural `tools/gen_sfx.py`) | This project (procedurally generated, seed 7) | CC0 | ❌ removed in Phase B5 |

### Characters (Phase B3, extended in B4) — `assets/lpc/*.png`

Composed from vendored LPC layer PNGs by `tools/lpc_compose.py`; the layers are
fetched into `assets/source/lpc_layers/` by `tools/art/vendor_lpc_layers.sh`.

| Sheets | Layers used | Licence |
|---|---|---|
| `player_*` (4 equipment variants) | body + head + eyes + hair + shirt + pants + boots + sword | CC-BY-SA 3.0 / GPL |
| `npc_elder`, `npc_hunter`, `npc_vendor` | as above; elderly / gaunt / female heads | CC-BY-SA 3.0 / GPL |
| `enemy_raider`, `enemy_shaman`, `enemy_goblin`, `enemy_skeleton`, `enemy_orc` | as above + goblin / skeleton / orc heads | CC-BY-SA 3.0 / GPL |

Authors: the Liberated Pixel Cup contributors, via the Universal LPC Spritesheet
Character Generator (generator GPL-3.0; art CC-BY-SA 3.0 / GPL). Credit list as
published on the generator repository.

> **Important:** `body/bodies/*` in that repository is **headless** — the head is a
> separate layer under `head/heads/*`, and a face-bearing head must be paired with an
> `eyes/*` layer. The original version of `tools/lpc_compose.py` omitted both, so the
> player sprite shipped with hair floating above a headless torso. The composer now
> refuses to build any archetype without a head layer, and the mistake is documented in
> both `tools/art/vendor_lpc_layers.sh` and `tools/lpc_compose.py`.

### Audio (Phase B5) — real score and SFX

Vendored by `tools/audio/vendor_audio.sh`. Six tracks are committed (renamed to the ids
`AudioManager` registers); the 26 MB upstream OST archive is **not** committed, only the
selected tracks, so attribution below is what satisfies the licence.

| Asset | Author | Licence | Status |
|---|---|---|---|
| Score: `title`, `meadow`, `barrens`, `frost`, `combat`, `boss` | **Avgvst** — "Generic 8-bit JRPG Soundtrack" ([OpenGameArt](https://opengameart.org/content/generic-8-bit-jrpg-soundtrack)) | **CC-BY 3.0 / 4.0** | ✅ in repo (`assets/audio/music/*.ogg`) |
| SFX (13): attack_swing, hit, player_hurt, dodge, pickup, ui_click, item_use, purchase, level_up, enemy_cast, boss_roar, ability_whirl, ability_bolt | **Kenney** — "RPG Audio", "Interface Sounds", "Impact Sounds" ([kenney.nl](https://kenney.nl/assets/rpg-audio)) | **CC0** | ✅ in repo (`assets/audio/sfx/*.ogg`) |

**CC-BY obligation:** the score requires attribution, which is shipped in the in-game
credits screen (`scripts/menus/main_menu.gd`) **and** in this file. Do not remove either.

> Note: Kenney's packs are generic sound libraries, not fantasy-specific. The mappings
> above are intentional substitutions (e.g. a heavy bell impact for the boss roar, a
> knife draw for an attack swing) — they read correctly in play but are not bespoke.

`tools/gen_music.py` and `tools/gen_sfx.py` are deprecated and now refuse to run without
`--force`, so they cannot silently regenerate placeholders over the real audio.

> ⚠️ Anything CC-BY-SA additionally requires attribution in-game (credits screen) — handled
> when the assets are integrated, and noted here per asset.

## Fonts
| Font | Author | License | Status |
|---|---|---|---|
| Press Start 2P (UI default theme) | CodeMan38 | OFL-1.1 | ✅ in repo (`assets/fonts/PressStart2P.ttf`, via google/fonts) |
| UI 9-patch frames (panel9/button9, `tools/gen_ui_assets.py`) | This project | CC0 | ✅ in repo (`assets/ui/`) |
