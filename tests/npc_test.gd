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
	await _test_idle_art()
	await _test_flee()
	_test_conversation_depth()
	_test_placement_and_vendors()
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


func _test_idle_art() -> void:
	print("[npc_test] generated idle loops")
	# Five villagers wear generated idle art this pass; the rest of the roster
	# still shows the two frames the LPC layers ship.
	var dressed := _spawn_npc("hunter_kael", Vector2(300, 100),
		"res://assets/lpc/npc_hunter.png")
	dressed.schedule_enabled = false
	await _phys_frames(2)
	check(dressed.anim_frame_count() == 4,
		"a villager on generated idle art loops four frames (%s -> %d)" %
		[dressed.sheet_path.get_file(), dressed.anim_frame_count()])
	var cols := PoseArt.idle_columns(dressed.sheet_path, 2)
	check(cols == PoseArt.IDLE_LOOP,
		"the loop interleaves base/shift/breath/look-around (%s)" % str(cols))
	var sprite: Sprite2D = dressed.get_node("Sprite")
	dressed.advance_sprite_anim(0.016, sprite, 2)
	var column: int = sprite.frame - dressed.anim_block_base() - 2 * dressed.ROW_WIDTH
	check(column in PoseArt.IDLE_LOOP,
		"the standing sprite shows a generated idle column (%d)" % column)
	dressed.queue_free()

	var plain := _spawn_npc("elder_rowan", Vector2(300, 200),
		"res://assets/lpc/npc_elder.png")
	plain.schedule_enabled = false
	await _phys_frames(2)
	check(plain.anim_frame_count() == 2 and PoseArt.idle_columns(plain.sheet_path, 2).size() == 2,
		"a villager without generated art keeps the two LPC frames (%s -> %d)" %
		[plain.sheet_path.get_file(), plain.anim_frame_count()])
	plain.queue_free()


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


func _spawn_npc(id: String, at: Vector2, sheet: String = "") -> NPC:
	var npc: NPC = load("res://scenes/world/npc.tscn").instantiate()
	npc.npc_id = id
	if sheet != "":
		npc.sprite_sheet = sheet   # the world hands this in (settlement.gd does the same)
	add_child(npc)
	npc.global_position = at
	npc.home = at
	npc.load_schedule()
	return npc


func _phys_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _test_conversation_depth() -> void:
	print("[npc_test] conversation depth: choices, and every NPC has something to say")
	var dialogue_dir := DirAccess.open("res://data/dialogue")
	if dialogue_dir == null:
		check(false, "data/dialogue is readable")
		return

	# Every NPC file must end in a fallback the player can always reach, or talking
	# to someone between quests is a dead end (that was the audit's complaint).
	var npc_ids := []
	for id in NPCController.roster().keys():
		npc_ids.append(String(id))
	var with_fallback := 0
	var choices := 0
	var empty_files := []
	var flag_actions := 0
	for id in npc_ids:
		var path := "res://data/dialogue/%s.json" % id
		if not FileAccess.file_exists(path):
			empty_files.append(id)
			continue
		var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var entries: Array = doc.get("dialogues", [])
		if entries.is_empty():
			empty_files.append(id)
			continue
		var last: Dictionary = entries[entries.size() - 1]
		var req: Dictionary = last.get("requires", {})
		if req.is_empty():
			with_fallback += 1
		for e in entries:
			for node in (e.get("nodes", {}) as Dictionary).values():
				for c in (node.get("choices", []) as Array):
					choices += 1
					for a in (c.get("actions", []) as Array):
						if String(a.get("action", "")) == "set_flag":
							flag_actions += 1
	check(empty_files.is_empty(), "every NPC has a dialogue tree (missing: %s)" % str(empty_files))
	check(with_fallback == npc_ids.size(),
		"every NPC has an unconditional fallback entry (%d/%d)" % [with_fallback, npc_ids.size()])
	check(choices >= 30, "conversation offers real choices (%d)" % choices)
	check(flag_actions >= 20, "choices record what the player said (%d set_flag actions)" % flag_actions)

	# Bosses: an introduction, a defeat line and a taunt per phase change.
	var bosses: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/boss_lines.json")).get("bosses", {})
	var enemies: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/enemies.json")).get("archetypes", {})
	var boss_ids := []
	for id in enemies:
		if String((enemies[id] as Dictionary).get("behavior", "")) == "boss":
			boss_ids.append(String(id))
	check(boss_ids.size() >= 6, "the roster names six bosses (%d)" % boss_ids.size())
	var voiced := 0
	for id in boss_ids:
		var b: Dictionary = bosses.get(id, {})
		if String(b.get("intro", "")) != "" and String(b.get("defeat", "")) != "" \
				and (b.get("phases", []) as Array).size() >= 2:
			voiced += 1
	check(voiced == boss_ids.size(),
		"every boss speaks (intro + taunt per phase + defeat): %d/%d" % [voiced, boss_ids.size()])

	# The game's last conversation must actually branch, and the epilogue reads it.
	var rowan: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/dialogue/elder_rowan.json"))
	var ending_choices := 0
	for e in rowan.get("dialogues", []):
		if String(e.get("id", "")).begins_with("elder_q4_end"):
			for node in (e.get("nodes", {}) as Dictionary).values():
				for c in (node.get("choices", []) as Array):
					for a in (c.get("actions", []) as Array):
						if String(a.get("flag", "")) in ["answer_buried", "answer_carried"]:
							ending_choices += 1
	check(ending_choices >= 2, "the final conversation in the game branches (%d endings-flagged choices)" % ending_choices)
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	check(main_src.contains("answer_buried") and main_src.contains("answer_carried"),
		"the epilogue reads the player's last decision")

func _test_placement_and_vendors() -> void:
	## Placement rules the audit asked for: nobody stands in two towns at once,
	## every settlement has someone to talk to, and vendors do not all sell the
	## same four things.
	print("[npc_test] placement: one home each, and a shelf per vendor")
	var st: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/settlements.json")).get("settlements", {})
	var seen := {}
	var duplicates := []
	var thin := []
	for sid in st:
		var roster: Array = (st[sid] as Dictionary).get("npcs", [])
		if roster.size() < 2:
			thin.append("%s(%d)" % [sid, roster.size()])
		for npc_id in roster:
			var key := String(npc_id)
			if seen.has(key):
				duplicates.append("%s in %s+%s" % [key, seen[key], sid])
			seen[key] = sid
	check(duplicates.is_empty(), "no NPC lives in two settlements (%s)" % str(duplicates))
	check(thin.is_empty(), "every settlement has at least two residents (%s)" % str(thin))

	# The camp trio are placed by camp.gd, so they must be excluded from the
	# settlement spawner or the player meets Rowan twice.
	var camp_flagged := 0
	var roster: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/npcs.json")).get("npcs", {})
	for npc_id in roster:
		if bool((roster[npc_id] as Dictionary).get("at_camp", false)):
			camp_flagged += 1
	check(camp_flagged == 3, "the camp's three residents are flagged at_camp (%d)" % camp_flagged)

	var shelves := {}
	var vendors := 0
	var dead_shelves := []
	for npc_id in roster:
		var stock: Array = (roster[npc_id] as Dictionary).get("stock", [])
		if stock.is_empty():
			continue
		vendors += 1
		shelves[str(stock)] = true
		for iid in stock:
			if ItemsDB.get_item(String(iid)).is_empty():
				dead_shelves.append("%s:%s" % [npc_id, iid])
	check(vendors >= 6, "at least six vendors trade in the valley (%d)" % vendors)
	check(shelves.size() == vendors, "every vendor has a shelf of its own (%d/%d)" % [shelves.size(), vendors])
	check(dead_shelves.is_empty(), "every shelf item exists in the catalogue (%s)" % str(dead_shelves))

	# The shop screen must be handed the vendor's own stock, not the camp's list.
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	check(main_src.contains("NPCController.stock_for"), "the shop opens with the vendor's own stock")
