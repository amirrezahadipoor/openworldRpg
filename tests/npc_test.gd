extends Node
## Phase E §3 headless test — NPC schedules, the controller FSM, and barks.
## Exits 0 on PASS, 1 on FAIL. Run:
##   godot --headless --path . res://tests/NpcTest.tscn

var failures := 0
var checks := 0


func check(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("  PASS: ", label)
	else:
		failures += 1
		print("  FAIL: ", label)


func _ready() -> void:
	print("[npc_test] starting...")
	await get_tree().process_frame
	_test_roster()
	_test_barks()
	_test_schedule()
	await _test_states()
	await _test_flee()
	_report()


func _report() -> void:
	print("NPC RESULT: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(1 if failures > 0 else 0)


func _test_roster() -> void:
	print("[npc_test] roster coverage (every named NPC has schedule + barks + a function)")
	var roster := NPCController.roster()
	check(roster.size() >= 10, "roster has %d named NPCs" % roster.size())
	var all_scheduled := true
	var all_functioned := true
	var all_barked := true
	for id in roster:
		var n: Dictionary = roster[id]
		var sched: Dictionary = n.get("schedule", {})
		for slot_name in ["Dawn", "Day", "Dusk", "Night"]:
			if not sched.has(slot_name):
				all_scheduled = false
		if String(n.get("function", "")) == "" or String(n.get("role", "")) == "":
			all_functioned = false
		if DialogueDB.bark_count(id) < 3:
			all_barked = false
	check(all_scheduled, "every NPC has all four schedule slots")
	check(all_functioned, "every NPC has a role and a story/shop function")
	check(all_barked, "every NPC has at least 3 idle barks")

	# The names the content bible fixes for the main cast must exist.
	var cast := ["wren", "elder_rowan", "hunter_kael", "mireille", "magistrate_voss",
		"brother_ashe", "captain_dael", "ysolde", "elder_fenwick", "high_warden_isolde"]
	var missing := []
	for id in cast:
		if not roster.has(id):
			missing.append(id)
	check(missing.is_empty(), "bible cast present (missing: %s)" % str(missing))


func _test_barks() -> void:
	print("[npc_test] bark selection")
	var first := DialogueDB.pick_bark("elder_rowan", "Day")
	var second := DialogueDB.pick_bark("elder_rowan", "Day")
	check(first != "", "elder has a bark for Day")
	check(first != second, "barks rotate instead of repeating")
	check(DialogueDB.pick_bark("nobody_here", "Day") == "", "unknown NPC yields no bark")
	var night_only := DialogueDB.pick_bark("mireille", "Night")
	var day := DialogueDB.pick_bark("mireille", "Day")
	check(night_only != "" and day != "", "time-filtered barks still resolve")
	var seen := {}
	for i in 8:
		seen[DialogueDB.pick_bark("hunter_kael", "Day")] = true
	check(seen.size() >= 3, "rotation exposes the whole bark set (%d distinct)" % seen.size())


func _test_schedule() -> void:
	print("[npc_test] schedule data -> points")
	var npc := _spawn_npc("hunter_kael", Vector2(200, 100))
	check(npc.home == Vector2(200, 100), "home is the placed position")
	check(npc.schedule_point("Night") == Vector2(200, 100), "night point = home offset")
	check(npc.schedule_point("Day") != npc.schedule_point("Night"), "day differs from night")
	check(npc.schedule_point("Nonsense") == npc.schedule_point("Day"),
		"unknown slot falls back to the Day point")
	npc.queue_free()


func _test_states() -> void:
	print("[npc_test] controller FSM")
	var npc := _spawn_npc("hunter_kael", Vector2(200, 100))
	npc.time_override = "Night"
	npc.schedule_enabled = false
	await _phys_frames(2)
	check(npc.state == NPCController.State.IDLE_SCHEDULE,
		"schedule off -> stands still in IDLE_SCHEDULE")

	npc.schedule_enabled = true
	npc.time_override = "Day"          # day point is (-120,-60) away from home
	var before := npc.global_position
	await _phys_frames(6)
	check(npc.state == NPCController.State.WALK_TO_POINT, "walks toward the day point")
	check(npc.global_position != before, "position actually changed while walking")
	var d0 := npc.global_position.distance_to(npc.schedule_point("Day"))

	npc.talk()
	await _phys_frames(10)
	check(npc.state == NPCController.State.TALK, "talk() holds the talk state")
	check(npc.global_position.distance_to(npc.schedule_point("Day")) >= d0 - 0.01,
		"a talking NPC does not walk away")

	npc.end_talk()
	await _phys_frames(300)
	var arrived := npc.global_position.distance_to(npc.schedule_point("Day")) <= npc.arrive_radius
	check(arrived, "reaches the day point (%d px away)" %
		int(npc.global_position.distance_to(npc.schedule_point("Day"))))
	check(npc.state == NPCController.State.IDLE_SCHEDULE, "settles into IDLE_SCHEDULE on arrival")

	# Moving from day to night must send them home again.
	npc.time_override = "Night"
	await _phys_frames(6)
	check(npc.state == NPCController.State.WALK_TO_POINT, "slot change sends the NPC walking")
	npc.queue_free()


func _test_flee() -> void:
	print("[npc_test] flee_combat")
	var npc := _spawn_npc("merchant_bram", Vector2(0, 0))
	npc.time_override = "Day"
	npc.schedule_enabled = false
	var enemy: Enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	add_child(enemy)
	enemy.global_position = Vector2(40, 0)
	enemy.setup_archetype("grunt")
	await _phys_frames(3)
	check(npc.state == NPCController.State.FLEE_COMBAT, "nearby enemy triggers FLEE_COMBAT")
	var away := npc.global_position.x < 0.0
	check(away, "NPC runs away from the threat (x=%d)" % int(npc.global_position.x))
	enemy.queue_free()
	npc.queue_free()


func _spawn_npc(id: String, at: Vector2) -> NPC:
	var npc: NPC = load("res://scenes/world/npc.tscn").instantiate()
	npc.npc_id = id
	add_child(npc)
	npc.global_position = at
	npc.home = at
	npc.load_schedule()
	return npc


func _phys_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
