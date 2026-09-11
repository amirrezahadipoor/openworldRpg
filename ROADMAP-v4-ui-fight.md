# ROADMAP v4 — UI/UX, HUD, Fight Feedback, Safe Zones, NPC/Monster Movement

> **Status (2026-09-11):** H1–H4 complete, H5 complete except the optional
> idle-frame art, H6 open (art polish). Everything below was verified on the
> commit named in each item and is covered by a suite where a suite can cover it.
> Legend: `[x]` done & committed · `[~]` in progress · `[ ]` todo

Commits: `6d08974` (H4 + H5 + the three field reports) · `8bd3ab0` (H3) ·
`c3c8b68` (H1 + H2).

---

## H1. HUD visual system — readability & consistency

- [x] **H1.1** Wrap each HUD cluster (HP/MP/info, quest tracker, buff readout,
      minimap, toasts) in its own `PanelContainer` wearing `ui/theme.tres`'s
      panel style. *Done: `hud.gd` builds everything under a single `_ui` Control
      that owns the theme; `_panel()` falls back to a flat StyleBox if the theme
      is missing.*
- [x] **H1.2** Real safe-area insets on all four sides. *Done: `_insets()`
      returns a `Vector4(left, top, right, bottom)` and every anchored cluster
      (including the joystick and the bottom tier) applies the right one. The old
      helper built a top-left corner, computed `win` and never used it, and left
      the bottom-anchored controls unprotected.*
- [x] **H1.3** Toast queue. *Done: `show_toast()` queues (max 6) instead of
      overwriting; `_advance_toast()` plays them in order with a 4.5 s dwell.
      Covered by `UiTest`.*
- [x] **H1.4** Radial cooldown sweep. *Done: `ActionButton.set_cooldown()` draws
      a filled dial over the icon; the countdown number stays as well.*
- [x] **H1.5 [image-gen]** Real icon art instead of placeholder SVGs. *Done:
      seven icons generated, keyed off their magenta screen, despilled and
      downsampled to the 32 px grid by `tools/make_ui_icons.py`; sources kept in
      `assets/ui/icons/_src/`, output in `assets/ui/icons/`.*

## H2. Touch control layout — fight ergonomics

- [x] **H2.1** Two visual tiers: Attack + Dodge under the thumb, Whirl + Bolt one
      step in, Talk/Use above them (context-sensitive).
- [x] **H2.2** Joystick contrast: dark backing disc plus roughly doubled ring and
      knob alpha, so it reads on the sand and snow palettes.
- [x] **H2.3** Press sound on ability press (not only on cast), plus a scale
      press animation and a dimmed/glowing state that says whether it will work.

## H3. Fight feedback

- [x] **H3.1** Per-enemy floating health bar, raised by any hit, fading after 3 s,
      redrawn only while it is up.
- [x] **H3.2** Boss bar: name, HP, one pip per phase, fed by
      `boss_encounter_started` / `boss_defeated`. Bosses maintain a `boss` group.
- [x] **H3.3** Ground telegraph: a disc at exactly `attack_radius` for melee, a
      firing line for ranged, filling as the wind-up runs.
- [x] **H3.4** Frame-rate independence: window 0.12 → 0.16 s, sampled every
      physics frame with a per-swing hit set; regression test runs the real swing
      at `Engine.physics_ticks_per_second = 30`.

## H4. Safe zones

- [x] **H4.1** `safe_radius` retuned to town radius + 70 px (was +90…+130).
      Union: 8.93 % of the map, down from 10.58 %, under the 15 % ceiling.
- [x] **H4.2** Visible ground boundary — a 3 px edge ring at `safe_radius` and a
      soft 10 px fade 42 px inside it, for settlements *and* the starting camp.
- [x] **H4.3** `tools/safe_zone_report.py` (with `--check`) prints the union area
      and per-bubble share; `WorldMapTest._test_safe_zones()` asserts the same
      numbers.
- [x] **H4.4** `ChunkStreamer` nudges a spawn point radially out of the bubble
      (`_push_out_of_safe_zones`) instead of skipping the spawner, so a chunk
      straddling a town is no longer dead ground.

## H5. NPC / monster movement

- [x] **H5.1** True rest: after three patrol cycles an enemy holds `IDLE` for
      18–32 s instead of the old fixed 1.5 s pause.
- [x] **H5.2** Off-screen enemies (beyond 900 px) skip the patrol loop entirely.
- [x] **H5.3** `DayNight.cycle_seconds` 480 → 1200, so a schedule point is held
      for three-to-six minutes and reads as a routine.
- [x] **H5.4** Separation: `Enemy._separation_vector()` (46 px) and
      `NPCController._separate_from_neighbours()` (soft 46 px). Measured on the
      built settlements, the closest pair of residents is 136 px apart.
- [ ] **H5.5 [image-gen]** Extra idle-only frames (look-around / shift-weight).
      *Deferred: the standing enemies now stand still for real stretches, which
      was the actual complaint; the extra frames are polish on top of that.*

## H6. General polish where art is the fix

- [ ] **H6.1 [image-gen]** Building-facade art sized to the 32 px grid, instead of
      procedural `Polygon2D` walls.
- [x] **H6.2 [image-gen]** Illustrated banner background behind toast and boss-intro
      text — *generated, keyed/despilled and sliced to 192x64 by
      `tools/make_ui_icons.py`, wired as a 9-slice `StyleBoxTexture` under the
      custom theme type `BannerPanel` in `ui/theme.tres`; used by the toast
      panel and the boss name plate.*

---

## Field reports folded into this pass

- [x] **NPCs standing inside each other** — deterministic seats
      (`Settlement._npc_seat()`, two alternating rows, `_seat_is_clear()` in
      global space) plus runtime separation. `WorldMapTest._test_npc_seats()`.
- [x] **Monsters attacking inside safe zones and while talking** —
      `Enemy._may_press_attack()` (gates `_finish_attack` and the charger dash),
      `Player._protected_ground()` (last gate before damage, also covers
      projectiles in flight), the new `State.WITHDRAW`, and
      `EventBus.dialogue_open`. `CombatTest` asserts both directions.
- [x] **Attack / Talk / the rest of the buttons must be designed properly and
      actually work** — see H1/H2 above and `tests/ui_test.gd` (22 checks).
