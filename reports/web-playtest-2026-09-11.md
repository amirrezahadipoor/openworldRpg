# Web-build playtest — 2026-09-11

The game was exported to **HTML5 (Godot 4.4.1, threads template)** and actually
*played* in a real browser (headless Chromium 153 with software WebGL2), driving
the menu, movement, combat, abilities and every UI screen with mouse +
keyboard + emulated touch, while recording the browser console and a
screenshot of every step. This catches the class of bug the headless suites
cannot: how the game looks and where the controls land on a non-phone.

## Harness (all ephemeral, nothing added to the repo)

- Export templates installed under a scratch `XDG_DATA_HOME`; game exported to
  `build/web/` (git-ignored) and served with the COOP/COEP headers the threads
  build requires (`Cross-Origin-Opener-Policy: same-origin`,
  `Cross-Origin-Embedder-Policy: require-corp`).
- Puppeteer + `puppeteer-core`, run at 1280×720 (desktop web) and emulated at a
  720×360 Android viewport with `hasTouch` (mobile). Each run dumps every
  `console`/`pageerror` line and full-screen captures.
- Result: the export boots, loads the title, starts a new game, streams chunks,
  plays abilities, and opens inventory/talents/pause with **no script errors**
  (the single console line is an emscripten "blocking on the main thread"
  advisory from software WebGL, not a game error).

## Bugs found by playing, then fixed

1. **Touch controls painted over a desktop web game.** The virtual joystick
   and the Whirl/Bolt/Attack/Dodge/Talk thumb buttons were built unconditionally,
   so on a desktop web build they sat permanently over the world and NPC name
   labels even though the player has WASD/J/K/E. They are now wrapped in a
   single `TouchLayer` that is shown only when the device really has touch:
   `DisplayServer.is_touchscreen_available()` on native, and
   `navigator.maxTouchPoints > 0` on web (the web display server reports touch
   on desktop Chrome via emulated touch events, which was the trap). Verified
   hidden at 1280×720 desktop and present on the emulated Android viewport.
2. **"Unequip" was enabled on an empty equipment slot.** All three rows offered
   a button that could only ever no-op. The Unequip buttons are now disabled
   whenever their slot holds nothing, and arm as soon as gear is worn
   (`InventoryScreen._refresh`). Covered by six new `UiTest` checks.
3. **Item type tag clipped off the right edge.** The inventory's right column
   produced a horizontal scrollbar and the row's `[consumable]` tag read as
   `[consum…`/`[cons:` because the column's fixed minimum widths summed past
   the panel. Horizontal scrolling is disabled, the columns size/clip
   responsibly, and the tag is a compact `[gear]/[cons]/[mat]`.

## Investigated and cleared (not bugs)

- *"Clicking New Game opens Settings."* A first, eye-balled click landed ~70 px
  below the actual button; measuring each button's live `get_global_rect()` and
  clicking its centre opens the correct panel every time. The menu hit-rects
  match the drawn labels.
- The flat grey block in the middle of Millhaven is the biome-tinted **paved
  plaza** the settlement code lays down (`_build_plaza`); in the ash/cinder
  biome the tint is grey by design, not a missing texture.

## Gate

All nine suites green after the fixes — **737 checks, 0 script errors** — both
smoke scenes clean, `balance_report --check` passed. (One Combat gold-pickup
check failed once on a loaded machine and passed 3/3 in isolation plus the
full rerun; it is a pre-existing headless frame-timing flake in the test,
untouched by these UI changes.)
