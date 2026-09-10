# Playtest checklist — the one thing CI cannot do

Everything in this repository is measured by a machine: 8 headless suites, a
balance report, a smoke run of the real scene. What none of those can tell us is
whether the game is *good in the hand*. That is this document.

Build: `release` workflow on a `v*` tag → signed APK/AAB, or
`godot --path . --export-debug "Android" build/playtest.apk`.

## 0. Before you touch it

- [ ] Install the APK on a real Android device (not just an emulator — emulators
      have no touch latency and no thermal throttling, which is half of what we
      are here to find out).
- [ ] Note the device: model, Android version, RAM.

## 1. Performance (the top risk)

- [ ] 60 FPS in the meadows standing still, and while walking.
- [ ] 60 FPS in the barrens, and in the frost peaks.
- [ ] Framerate while **chunk-streaming**: run east for 30 seconds straight.
- [ ] Framerate in the Ember Warden fight (the heaviest scene: boss, particles,
      hit-stop, radial attacks).
- [ ] Framerate in the deepest dungeon floor you can reach.
- [ ] Device temperature after 10 minutes — does it throttle, and does the
      framerate recover?
- [ ] Battery drain over 10 minutes of play.

What "fine" means: **no sustained dips below 45 FPS**, no audio crackle, no
input lag on attack or dodge. If it drops, note *where* — the fix differs
wildly between chunk streaming, particle counts and enemy count.

## 2. Touch controls (this is an Android game; nobody has tested the touch UI)

- [ ] The virtual joystick feels right — no dead zone weirdness, no drift.
- [ ] Attack / dodge / interact / Whirlwind / Firebolt buttons: reachable with a
      thumb, correctly sized, cooldown readouts legible.
- [ ] Can you dodge-cancel out of an attack animation without fighting the UI?
- [ ] The whole loop played with touch only: kill 10 monsters, loot them, open the
      inventory, equip something, drink a potion, talk to an NPC, take a quest.

## 3. Readability on a small screen

- [ ] Dialogue text, quest log and inventory text legible at arm's length.
- [ ] Item rarity colours distinguishable (and not only by colour — check the ★
      on rare-or-better).
- [ ] The minimap readable, and the quest tracker not covering the action.
- [ ] Damage numbers readable over a fight with three enemies.

## 4. The balance pass, felt rather than measured

`tools/balance_report.py` targets: a field monster takes 2–8 swings, a boss fight
lasts 25–120 seconds, a level costs 12–45 kills, and each rarity's median item
costs about 0.8 of a level's income. Check whether those *numbers* are the right
*experience*:

- [ ] Levels 1–10: is the Slime Grunt / Emberling fight fun, or tedious?
- [ ] Levels 10–30: does the meadow feel safe and the barrens dangerous?
- [ ] The **Goblin King** (gate L8): 28 seconds, 14 hits survived. Too easy?
- [ ] Levels 40–60: is the Minotaur/Legion band a wall, or a fair fight?
- [ ] The **Frost Giant** (L60) and **Choir Priest** (L76): 62 and 76 seconds —
      long enough to feel like a boss, short enough not to be a slog?
- [ ] The **Ember Warden** (L92): 100 seconds, 570 swings. Does it *feel* like the
      end of the game?
- [ ] Are potions worth their new price (a kill or two)? Do you run out?
- [ ] Do you ever feel short of gold, or does it pile up?
- [ ] Is a legendary item (≈27,700 gold, about a level of income at L80)
      something you *want* badly enough to earn?

## 5. Content sanity (spot-check the generated content)

The 100-step chain and 100 side quests come from the sanctioned template system
(see DECISIONS.md #41) — models authored in full, one authored twist per quest.
Sample a handful by hand and check the voice and the geography:

- [ ] MQ001 → MQ010: does the main line read as a story?
- [ ] MQ065: the Mireille expose/protect fork — does the consequence land?
- [ ] The last chain step before the Ember Warden: does the escalation feel earned?
- [ ] 5 side quests picked at random across the three regions: right place, right
      level, sensible reward?
- [ ] A follow-up side-quest chain (SQ007→SQ008 is one) actually continues.
- [ ] The repeatable "Thin the Slimes"-style work: does it reset cleanly?

## 6. Secrets

- [ ] Walk over a buried cache: it should reveal itself with no prompt beforehand.
- [ ] Read a carving: the hint it gives should point somewhere real.
- [ ] Try a vault you are too low-level for: the refusal should say *why*.
- [ ] Found/not-found should survive: save, quit, reload, and revisit the same spot.

## 7. Save/load and the edges

- [ ] Save, force-close the app, reopen, load: same position, gold, quests, secrets.
- [ ] Die (let a boss kill you), respawn at camp, and keep playing.
- [ ] Fast-travel between all five campfires.
- [ ] Kill the app during a chunk stream and reload.
- [ ] Rotate the device (landscape lock should hold) and background/foreground it.

## 8. Report back

For anything that feels wrong, the useful report is: **what you were doing, what
you expected, what happened**, plus the device and — if you can get it — a
logcat capture (`adb logcat | grep -i godot`). Performance findings are worth
more than anything else here; balance findings are worth a lot; typos are worth
a note.
