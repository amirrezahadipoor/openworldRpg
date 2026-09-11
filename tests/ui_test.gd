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
	_report()


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
