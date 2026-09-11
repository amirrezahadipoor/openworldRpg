extends Node
## UI / touch-layer test suite.
##
## Why this exists: the on-screen buttons were the least-tested part of the game
## and the most broken. `ActionButton` used to call `Input.action_press()` only,
## which sets polled state but never produces an InputEvent — so every
## `_unhandled_input` handler in the game (NPC talk, chests, signs, levers,
## dialogue advance) was unreachable from touch. Attack worked and Talk silently
## did nothing, which is precisely what a player reported.
##
## Exits 0 on PASS, 1 on FAIL. Run:
##   godot --headless --path . res://tests/UiTest.tscn

var failures := 0
var checks := 0

## Set by the probe below when a real event reaches an `_unhandled_input` handler.
var _seen_events: Array = []


func check(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("  PASS: ", label)
	else:
		failures += 1
		print("  FAIL: ", label)


func _ready() -> void:
	print("[ui_test] starting...")
	await get_tree().process_frame
	await _test_button_delivers_events()
	await _test_same_frame_tap()
	await _test_interact_target_and_verb()
	await _test_interact_reaches_the_npc()
	_test_cooldown_sweep()
	_test_toast_queue()
	_test_safe_insets()
	await _test_audit_fixes()
	await _test_pause_owner()
	await _test_upgrade_bench()
	_report()


func _test_audit_fixes() -> void:
	print("[ui_test] nearest-wins interaction, ending credits handoff")

	# M1: the keyboard path and the touch path must agree on the target.
	var tree := get_tree()
	var player := Node2D.new()
	player.add_to_group("player")
	var near := _bare_interactable(Vector2(30, 0))
	var far := _bare_interactable(Vector2(100, 0))
	add_child(player)
	add_child(far)
	add_child(near)          # added last: plain tree order would pick the far one
	near.add_to_group("interactable_in_range")
	far.add_to_group("interactable_in_range")
	var target := WorldInteractable.nearest_in_range(tree, player)
	check(target == near, "the closest of two in range is the one that acts (M1)")

	# A screen can outlive the body it was built around. Passing a freed player used
	# to be a hard script error ("previously freed", CI caught it on the commit that
	# introduced the shared rule), so the rule takes it and says "nothing".
	var doomed := Node2D.new()
	doomed.add_to_group("player")
	add_child(doomed)
	var stale: Node2D = doomed
	remove_child(doomed)
	doomed.free()
	check(WorldInteractable.nearest_in_range(tree, stale) == null,
		"a freed player reference answers 'nothing in reach' instead of erroring")
	far.remove_from_group("interactable_in_range")   # stepped out of its radius
	check(WorldInteractable.nearest_in_range(tree, player) == near,
		"an out-of-range neighbour is ignored")
	near.remove_from_group("interactable_in_range")
	check(WorldInteractable.nearest_in_range(tree, player) == null,
		"nothing in range means no target")
	remove_child(near)
	remove_child(far)
	remove_child(player)
	player.free()
	near.free()
	far.free()

	# M2: the ending's Credits button asks the menu to open its credits layer.
	GameState.pending_credits = false
	var main_script: GDScript = load("res://scripts/main.gd")
	check(main_script != null, "main.gd loads")
	var menu_script: GDScript = load("res://scripts/menus/main_menu.gd")
	check(menu_script != null, "main menu loads")
	var menu_src := menu_script.source_code
	check(menu_src.contains("pending_credits"),
		"the menu consumes the pending-credits request (M2)")
	check(main_script.source_code.contains("pending_credits"),
		"and the ending raises it")


func _bare_interactable(pos: Vector2) -> WorldInteractable:
	var n := WorldInteractable.new()
	n.position = pos
	return n


func _test_pause_owner() -> void:
	print("[ui_test] one owner for the paused flag")

	# C6: the state is a set of holds, so a second screen closing cannot unpause a
	# world the first screen is still holding still.
	var a := Node.new()
	var b := Node.new()
	add_child(a)
	add_child(b)
	PauseManager.release_all()
	check(not PauseManager.is_paused(), "nothing holding means the world runs")
	PauseManager.hold(a, "screen a")
	check(PauseManager.is_paused() and get_tree().paused, "one hold pauses the world")
	PauseManager.hold(b, "screen b")
	PauseManager.release(a)
	check(PauseManager.is_paused(),
		"the second screen closing does not unpause under the first (C6)")
	PauseManager.release(b)
	check(not PauseManager.is_paused() and not get_tree().paused,
		"and the world runs again when the last hold lets go")

	# A screen freed while it is holding (scene change, quit to title) must not be
	# able to strand the pause.
	PauseManager.hold(b, "screen b")
	check(PauseManager.is_paused(), "the doomed screen holds")
	remove_child(b)
	b.free()
	check(not PauseManager.is_paused(), "a freed holder drops its hold (C6)")

	# And the flag itself must have exactly one writer left in the code base.
	var offenders := _pause_flag_writers("res://scripts")
	check(offenders.is_empty(),
		"only PauseManager writes get_tree().paused (%s)" % ", ".join(offenders))
	remove_child(a)
	a.free()
	PauseManager.release_all()


func _pause_flag_writers(root: String) -> Array:
	## Every script that assigns the tree's paused flag directly.
	var out: Array = []
	var dir := DirAccess.open(root)
	if dir == null:
		return ["<unreadable: %s>" % root]
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var path := "%s/%s" % [root, name]
		if dir.current_is_dir():
			if name != "." and name != "..":
				out.append_array(_pause_flag_writers(path))
		elif name.ends_with(".gd") and not path.ends_with("pause_manager.gd"):
			var f := FileAccess.open(path, FileAccess.READ)
			if f != null:
				var n := 1
				while not f.eof_reached():
					var line := f.get_line().strip_edges()
					if not line.begins_with("#") and line.contains("paused ="):
						out.append("%s:%d" % [path.get_file(), n])
					n += 1
		name = dir.get_next()
	dir.list_dir_end()
	return out


func _test_upgrade_bench() -> void:
	print("[ui_test] the shop's smith bench renders and respects affordability")

	# v3 audit §4 wanted a second-half gold sink; the shop is where it lives, so
	# the screen itself is what has to show it.
	var bench: CanvasLayer = load("res://scripts/ui/shop_screen.gd").new()
	add_child(bench)
	bench.open("Bram", ["health_potion"], 1.0)
	await get_tree().process_frame

	GameState.inventory.clear()
	GameState.upgrades.clear()
	GameState.equipment = {"weapon": "", "armor": "", "accessory": ""}
	GameState.gold = 0

	var rows := 0
	for slot in ["weapon", "armor", "accessory"]:
		if bench.find_child("Upgrade_%s" % slot, true, false) != null:
			rows += 1
	check(rows == 3, "a bench row for each equipment slot (%d)" % rows)

	var empty_row := bench.find_child("Upgrade_weapon", true, false)
	check(empty_row != null and (empty_row.get_child(2) as Button).disabled,
		"an empty slot cannot be upgraded")

	GameState.add_item("iron_sword", 1)
	GameState.equip("iron_sword")
	GameState.gold = 0
	bench.open("Bram", ["health_potion"], 1.0)
	await get_tree().process_frame
	var row := bench.find_child("Upgrade_weapon", true, false)
	check(row != null and (row.get_child(2) as Button) != null, "the bench rebuilds on open")
	check((row.get_child(2) as Button).disabled, "no gold, no anvil")
	var cost := GameState.upgrade_cost("weapon")
	GameState.gold = int(cost["gold"])
	GameState.add_item(String(cost["material"]), int(cost["qty"]))
	bench.open("Bram", ["health_potion"], 1.0)
	await get_tree().process_frame
	row = bench.find_child("Upgrade_weapon", true, false)
	check(not (row.get_child(2) as Button).disabled, "gold + material arms the button")
	check((row.get_child(1) as Label).text.contains(String(cost["material"])) == false,
		"the price line names the material by its display name")

	GameState.inventory.clear()
	GameState.upgrades.clear()
	GameState.equipment = {"weapon": "", "armor": "", "accessory": ""}
	GameState.gold = 0
	bench.close()
	bench.queue_free()


func _report() -> void:
	print("UI RESULT: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(1 if failures > 0 else 0)


func _unhandled_input(event: InputEvent) -> void:
	## Stands in for every NPC / chest / sign in the game.
	if event is InputEventAction:
		_seen_events.append((event as InputEventAction).action)


func _phys(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _make_player() -> Player:
	var p: Player = load("res://scenes/player/player.tscn").instantiate()
	add_child(p)
	p.global_position = Vector2(0, 0)
	return p


func _make_hud(player: Player) -> HUD:
	var hud: HUD = HUD.new()
	add_child(hud)
	hud.setup(player, null)
	return hud


func _test_button_delivers_events() -> void:
	print("[ui_test] a touch press delivers a real input event")
	var player := _make_player()
	var hud := _make_hud(player)
	await _phys(2)

	_seen_events.clear()
	Input.action_release("interact")
	hud._interact_btn.push_events = true      # the plain path, as the abilities use
	hud._whirl_btn._on_down()
	await _phys(2)
	hud._whirl_btn._on_up()
	await _phys(3)
	check(_seen_events.has("ability_whirl"),
		"the press reaches an _unhandled_input handler (%s)" % str(_seen_events))
	check(not Input.is_action_pressed("ability_whirl"),
		"the action is released again after the press")

	hud.queue_free()
	player.queue_free()
	await _phys(2)


func _test_same_frame_tap() -> void:
	## The touch case that used to be lost: press and release inside one frame.
	print("[ui_test] a tap shorter than a frame still registers")
	var player := _make_player()
	var hud := _make_hud(player)
	await _phys(2)
	Input.action_release("ability_whirl")
	_seen_events.clear()
	hud._whirl_btn._on_down()
	hud._whirl_btn._on_up()          # no frame in between, exactly as a fast tap
	# Synchronous check: the press is still live at this instant, which is what
	# makes `is_action_just_pressed()` able to see it on the next poll.
	check(Input.is_action_pressed("ability_whirl"),
		"a same-frame tap is still held when the finger lifts")
	await _phys(4)
	check(_seen_events.has("ability_whirl"), "and its event was delivered too (%s)" % str(_seen_events))
	check(not Input.is_action_pressed("ability_whirl"), "and it is released afterwards")
	hud.queue_free()
	player.queue_free()
	await _phys(2)


func _place_npc(id: String, at: Vector2) -> NPC:
	var npc: NPC = load("res://scenes/world/npc.tscn").instantiate()
	add_child(npc)
	npc.npc_id = id
	npc.monitoring = true
	npc.global_position = at
	return npc


func _test_interact_target_and_verb() -> void:
	## Two things in reach must not both fire, and the button must say what it will
	## do before it is pressed.
	print("[ui_test] the Talk button picks one target and names the verb")
	var player := _make_player()
	var hud := _make_hud(player)
	var near: NPC = _place_npc("marget", Vector2(40, 0))
	var far: NPC = _place_npc("smith_corvin", Vector2(110, 0))
	await _phys(3)
	var target := hud.nearest_interactable()
	check(target == near, "the closest interactable wins (got %s)" %
		("none" if target == null else target.name))

	hud._tick_interact_button()
	check(hud._interact_btn.caption == "Talk", "the button reads Talk for an NPC ('%s')" %
		hud._interact_btn.caption)
	check(not hud._interact_btn._dimmed, "and it is lit while something is in reach")

	# Out of reach: the button goes quiet and dims.
	player.global_position = Vector2(9000, 9000)
	await _phys(3)
	hud._tick_interact_button()
	check(hud._interact_btn._dimmed, "the button dims when nothing is in reach")

	hud.queue_free()
	player.queue_free()
	near.queue_free()
	far.queue_free()
	await _phys(2)


func _test_interact_reaches_the_npc() -> void:
	print("[ui_test] pressing Talk actually starts the conversation")
	var player := _make_player()
	var hud := _make_hud(player)
	var npc: NPC = _place_npc("marget", Vector2(40, 0))
	var talked := [0]
	npc.interacted.connect(func(_n: NPC) -> void: talked[0] += 1)
	await _phys(3)
	check(hud.nearest_interactable() != null, "the NPC registered itself as in range")
	hud._on_interact_pressed()
	await _phys(2)
	check(talked[0] == 1, "the Talk button emitted the NPC's interacted signal once (%d)" % talked[0])
	check(npc.state == NPCController.State.TALK, "and the NPC held position for the conversation")
	npc.end_talk()

	# Nothing in reach: pressing must be a refusal, not a silent no-op.
	player.global_position = Vector2(9000, 9000)
	await _phys(3)
	hud._on_interact_pressed()
	await _phys(2)
	check(talked[0] == 1, "pressing Talk with nothing in reach does nothing (%d)" % talked[0])

	hud.queue_free()
	player.queue_free()
	npc.queue_free()
	await _phys(2)


func _test_cooldown_sweep() -> void:
	## H1.4: a radial sweep as well as a number.
	print("[ui_test] ability buttons sweep while they cool")
	var player := _make_player()
	var hud := _make_hud(player)
	await _phys(2)
	hud._whirl_btn.set_cooldown(0.0)
	check(absf(hud._whirl_btn._cd_frac) < 0.001, "a ready ability has no sweep")
	hud._whirl_btn.set_cooldown(0.5)
	check(absf(hud._whirl_btn._cd_frac - 0.5) < 0.001, "half-cooled sweeps half the dial")
	hud._whirl_btn.set_cooldown(3.4)
	check(absf(hud._whirl_btn._cd_frac - 1.0) < 0.001, "an over-long value is clamped")
	hud.queue_free()
	player.queue_free()
	await _phys(2)


func _test_toast_queue() -> void:
	## H1.3: two messages in the same second must both be seen.
	print("[ui_test] toasts queue instead of overwriting each other")
	var hud: HUD = HUD.new()
	add_child(hud)
	hud.setup(null, null)
	hud.show_toast("first")
	hud.show_toast("second")
	hud.show_toast("third")
	check(hud.toast_label.text == "first", "the first message is shown first ('%s')" % hud.toast_label.text)
	check(hud._toast_queue.size() == 2, "the rest are queued (%d)" % hud._toast_queue.size())
	hud._toast_time = 0.0
	hud._advance_toast(0.016)
	check(hud.toast_label.text == "second", "the next message follows ('%s')" % hud.toast_label.text)
	hud._toast_time = 0.0
	hud._advance_toast(0.016)
	hud._toast_time = 0.0
	hud._advance_toast(0.016)
	check(not hud._toast_panel.visible, "the queue empties and the banner hides again")
	hud.queue_free()
	await _phys(2)


func _test_safe_insets() -> void:
	## H1.2: real insets on all four sides (a notched device can report any of them).
	print("[ui_test] safe-area insets are computed on all four sides")
	var hud: HUD = HUD.new()
	add_child(hud)
	hud.setup(null, null)
	var ins := hud._insets()
	check(ins is Vector4, "the inset is a four-sided value, not a top-left corner")
	check(ins.x >= 0.0 and ins.y >= 0.0 and ins.z >= 0.0 and ins.w >= 0.0,
		"no inset is negative (%s)" % str(ins))
	check(ins.x <= 64.0 and ins.w <= 64.0, "insets are clamped to something sane")
	check(hud.joystick.anchor_bottom == 1.0 and hud.joystick.offset_bottom <= -16.0,
		"the joystick keeps its inset from the bottom edge")
	var fit := hud._fit_scale()
	check(fit > 0.5 and fit <= 1.2, "the touch layer scales to the window (%.2f)" % fit)
	hud.queue_free()
	await _phys(2)
