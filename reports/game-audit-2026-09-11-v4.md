# Game audit v4 — crash, HUD/fight feedback, and persistence pass

Date: 2026-09-11 · method: headless Godot 4.4.1, every suite plus runtime probes of
the live HUD/NPC graph. This pass chased the bugs CI cannot see: script errors
that print while a suite still reports PASS, art that is committed but never
referenced, and feedback the fight was supposed to give but did not.

## What was actually wrong

| # | Area | Symptom a player would hit | Root cause |
|---|------|----------------------------|------------|
| 1 | HUD / interaction | Thousands of `SCRIPT ERROR` lines per run (2,156 in CombatTest); a freed player kept being targeted every frame | `WorldInteractable.nearest_in_range(tree, player: Node2D)` failed its typed-argument check on a *freed* player before its own null guard ran. The HUD processes while paused and outlives teardown frames (test field swaps, scene changes). |
| 2 | Quests | A `SCRIPT ERROR: Nonexistent function 'sync_collect_objectives'` while the suite still printed PASS | The audit test called a public sync that only existed as the private per-quest `_sync_collect`; the invalid call aborted the rest of that test function, silently dropping checks. |
| 3 | HUD art | Every touch button and the Bag button showed rough placeholder SVGs — Bag read as a **padlock** | `_load_icon("icon_bag", …)` only searched `assets/placeholder`; the polished PNGs committed in `assets/ui/icons` use bare stems (`bag.png`, `dodge.png`, …) and were never found. |
| 4 | Fight feedback | The Attack and Dodge touch buttons never showed a cooldown sweep | `Player.cooldowns()` returned only whirl/bolt, so the HUD read `dodge`/`attack` as 0 every frame. |
| 5 | Accessibility | Normal text was rendered **4px smaller than authored**, and the Large-text toggle did nothing | The font walk computed `current_size - 4` on every pass, shrinking normal UI, then added the same 4 back when large was on — a no-op. |
| 6 | Saves | A consumed Phoenix Draught was lost on reload (paid item, no protection) | `revive_armed` was excluded from the save dictionary (momentary buffs are intentionally unsaved, but this is a consumed item for a future death). |
| 7 | Bag / shop | Materials showed an Equip button that only ever buzzed "denied"; buying into a full stack took gold and handed back nothing | Equip was offered for items with no slot; the shop did not check `stack_size` before charging (`add_item` silently caps). |
| 8 | Combat | The combo finisher had **identical reach to a jab** despite its 1.5× damage / long recovery | The widening branch only handled a `CircleShape2D`, but the player scene ships a `RectangleShape2D`, so it never ran. |
| 9 | Boss HUD | The title Ember Warden fight (overworld BossArena) showed **no boss name / health bar / phase pips** | `boss_encounter_started` was emitted only by dungeon data-boss floors, never by the overworld arena. Data-boss radial volleys also played the player's Whirlwind cue. |
| 10 | Robustness | Enemy could cache and chase a freed player body; minimap palette could index out of range on a future atlas | `is_queued_for_deletion` did not cover a `free()`d body; biome index was unbounded. |

## Fixes (one commit each)

1. `nearest_in_range` takes an untyped, validity-checked player; HUD and minimap
   guard on `is_instance_valid`. CombatTest script errors: **2,156 → 0**.
2. Added `QuestManager.sync_collect_objectives()` (syncs every active quest from
   the bag). QuestTest checks rose 61 → **69** (the previously aborted steps now
   run).
3. `HUD._load_icon` resolves bare stems to `assets/ui/icons` first, then falls
   back to placeholders. Verified at runtime: attack/dodge/whirl/bolt/interact
   all load the shipped PNGs.
4. `Player.cooldowns()` now reports `dodge` and `attack` fractions (attack scaled
   to the real jab-or-finisher recovery); the HUD drives both dials and shows the
   Attack recovery in seconds.
5. Settings: authored font sizes are captured once in metadata and every pass
   writes `authored (+4 large)` — idempotent, normal text is no longer shrunk,
   large text genuinely enlarges, content screens re-apply on open, and Settings
   Cancel restores a live-toggled value. Verified 14 → 18 → 14 and 26 → 30.
6. `revive_armed` round-trips through saves (defaults false for legacy saves).
7. Equip is hidden for non-gear items; the shop disables/guards purchases when
   the destination stack is full.
8. The finisher now sizes the shipped rectangle hitbox (56×46 vs 38×32 jab);
   CombatTest asserts it is wider.
9. BossArena emits `boss_encounter_started` on summon (HUD plate appears); data
   bosses use the `enemy_cast` cue; minimap clamps biome index.
10. Enemy validates cached player with `is_instance_valid`.

## Verification

Headless, Godot 4.4.1, zero `SCRIPT ERROR` / parse / compile errors everywhere:

| Suite | Result | Suite | Result |
|---|---|---|---|
| Combat | PASS 231 | Quest | PASS 69 |
| Playthrough | PASS 52 | Items | PASS 65 |
| NPC | PASS 43 | Secret | PASS 45 |
| WorldMap | PASS 72 | Audio | PASS 56 |
| UI | PASS 36 | **total** | **669 checks** |

Main scene 300-frame smoke and main-menu smoke are both clean;
`balance_report.py --check` PASSED; all 70 JSON data files validate; tracked
repository size is 26 MB (the local `.godot/` import cache is gitignored and
absent from CI).

## Still open (unchanged from v3, deliberately not code-touched here)

- World decoration density, behaviour-changing talent nodes, and a late-game
  gold sink remain design/content tasks, not bugs.
- Real-device FPS/thermal playtest (`PLAYTEST.md`) still needs a human with a
  phone; headless CI cannot replace it.

---

## خلاصهٔ فارسی

این پاس باگ‌هایی را گرفت که CI سبز آن‌ها را پنهان می‌کرد: کرش هزارتکرارهٔ HUD
هنگام آزاد شدن کاراکتر، آیکن‌های صیقل‌یافده‌ای که هیچ‌وقت نمایش داده نمی‌شدند
(دکمهٔ کیف مثل قفل بود)، نوار cooldown حمله/داج که کار نمی‌کرد، متن بزرگ بی‌اثر و
کوچک‌شدن متن عادی، از بین رفتن دراگت فینیکس با لود، بُرد یکسان فینیشر با ضربهٔ
ساده، و غایب بودن نوار جان باس نهایی. همه با ۶۶۹ تست سبز و بدون هیچ خطای اسکریپت
تأیید شدند.
