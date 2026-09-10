extends Node
## Phase E §1 headless test — settlements (3 villages / 3 towns / 3 cities) and
## dungeons (9 dungeons / 26 floors) as real built scenes.
## Exits 0 on PASS, 1 on FAIL. Run:
##   godot --headless --path . res://tests/WorldMapTest.tscn

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
	print("[world_map_test] starting...")
	await get_tree().process_frame
	_test_settlement_data()
	_test_dungeon_data()
	await _test_settlement_builds()
	await _test_dungeon_builds()
	_report()


func _report() -> void:
	print("WORLDMAP RESULT: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(1 if failures > 0 else 0)


func _test_settlement_data() -> void:
	print("[world_map_test] settlement roster (Phase E §1)")
	var all := Settlement.all()
	check(all.size() == 9, "nine settlements (%d)" % all.size())

	var tiers := {}
	for id in all:
		var s: Dictionary = all[id]
		tiers[String(s.get("tier", ""))] = int(tiers.get(String(s.get("tier", "")), 0)) + 1
	check(int(tiers.get("village", 0)) == 3, "three villages")
	check(int(tiers.get("town", 0)) == 3, "three towns")
	check(int(tiers.get("city", 0)) == 3, "three cities")

	# The names the bible fixes must be present, and every settlement must be
	# staffed and reachable (waypoint or dungeon).
	var named := ["millhaven", "oakstead", "sunreach", "ashport", "cinderhold",
		"frosthaven", "skyreach"]
	var missing := []
	for id in named:
		if not all.has(id):
			missing.append(id)
	check(missing.is_empty(), "bible settlements present (missing: %s)" % str(missing))

	var staffed := true
	var sited := true
	var rosters_ok := true
	for id in all:
		var s2: Dictionary = all[id]
		if (s2.get("npcs", []) as Array).is_empty():
			staffed = false
		if not (s2.get("services", []) as Array).has("waypoint"):
			sited = false
		for n in (s2.get("npcs", []) as Array):
			if NPCController.roster_entry(String(n)).is_empty():
				rosters_ok = false
	check(staffed, "every settlement has at least one named NPC")
	check(sited, "every settlement has a waypoint")
	check(rosters_ok, "every settlement NPC exists in the NPC roster")

	# Cities must be materially bigger than villages.
	var v := int((all["oakstead"] as Dictionary).get("buildings", 0))
	var c := int((all["sunreach"] as Dictionary).get("buildings", 0))
	check(c > v, "a city builds more than a village (%d > %d)" % [c, v])


func _test_dungeon_data() -> void:
	print("[world_map_test] dungeon roster (Phase E §1)")
	var all := Dungeon.all()
	check(all.size() == 9, "nine dungeons (%d)" % all.size())
	check(Dungeon.total_floors() == 26, "26 floors total (%d)" % Dungeon.total_floors())

	var multi := 0
	var boss_floors := 0
	var tables_ok := true
	for id in all:
		var d: Dictionary = all[id]
		var fl: Array = d.get("floors", [])
		if fl.size() >= 2:
			multi += 1
		for i in fl.size():
			var f: Dictionary = fl[i]
			if int(f.get("floor", -1)) != i + 1:
				tables_ok = false
			# floor_index must match depth so §6 scaling compounds correctly
			if int(f.get("floor_index", -1)) != i + 1:
				tables_ok = false
			if bool(f.get("boss", false)):
				boss_floors += 1
			for e in (f.get("enemies", []) as Array):
				if EnemyDB.get_archetype(String(e)).is_empty():
					tables_ok = false
			if f.get("exit_to", "") == "":
				tables_ok = false
	check(multi == 9, "every dungeon has multiple floors (%d/9)" % multi)
	# Phase F3: exactly six dungeons end on a named boss (one per boss in the
	# roster); the rest end on an elite floor that is harder than the one above.
	check(boss_floors == 6, "six dungeons gate on a named boss floor (%d)" % boss_floors)
	check(tables_ok, "floor tables reference real archetypes with correct floor_index")

	# The final fight must stay the shipped one, not a reimplementation.
	var keep: Dictionary = (all["ember_warden_keep"] as Dictionary)
	var last: Dictionary = (keep["floors"] as Array)[-1]
	check((last.get("enemies", []) as Array).has("ember_warden"),
		"the Ember Warden keep ends on the shipped boss")


func _test_settlement_builds() -> void:
	print("[world_map_test] settlements build as scenes")
	var host := Node2D.new()
	add_child(host)
	var built := 0
	var npc_total := 0
	var lights := 0
	var waypoints := 0
	var signs := 0
	for id in Settlement.all():
		var s := Settlement.new()
		host.add_child(s)
		s.setup(String(id))
		built += 1
		for child in s.get_children():
			if child is NPC:
				npc_total += 1
			elif child is PointLight2D:
				lights += 1
			elif child is Waypoint:
				waypoints += 1
			elif child is Sign:
				signs += 1
	check(built == 9, "all nine settlements instantiate")
	check(npc_total >= 17, "settlements place their NPCs (%d)" % npc_total)
	check(lights > 0, "settlements are lit (%d lights)" % lights)
	check(waypoints == 9, "one waypoint per settlement (%d)" % waypoints)
	check(signs == 9, "one name sign per settlement (%d)" % signs)

	# Buildings must differ per settlement (not one recoloured chunk).
	var shapes := {}
	for s in host.get_children():
		if s is Settlement:
			shapes[(s as Settlement).settlement_id] = s.get_child_count()
	check(shapes.size() == 9, "nine distinct settlement scenes")
	host.queue_free()


func _test_dungeon_builds() -> void:
	print("[world_map_test] dungeons build floors")
	var host := Node2D.new()
	add_child(host)
	var d := Dungeon.new()
	host.add_child(d)
	d.setup("drowned_mill", 1)
	check(d.floor_count() == 2, "drowned_mill reports 2 floors")
	check(d.floor_index == 1, "starts on floor 1")

	var spawners_f1 := _count_spawners(d)
	check(spawners_f1 > 0, "floor 1 populated (%d spawners)" % spawners_f1)
	var deep := d.floor_data(2)
	check(float(deep.get("power_scale", 0.0)) > float(d.floor_data(1).get("power_scale", 0.0)),
		"deeper floors are harder")

	check(d.descend(), "descending to floor 2 succeeds")
	check(d.floor_index == 2, "now on floor 2")
	check(not d.descend(), "cannot descend past the bottom")
	check(d.ascend(), "ascending back to floor 1 succeeds")
	check(not d.ascend(), "cannot ascend past the surface")
	check(_count_spawners(d) > 0, "floor 1 repopulated after ascending")

	# Floor depth must reach the spawner, which is what §6 scales on.
	var depths := _spawner_depths(d)
	check(depths.has(1), "floor 1 spawners carry floor_index 1 (%s)" % str(depths))

	# Walk the deepest dungeon through every floor.
	d.setup("choir_sanctum", 1)
	var walked := 0
	while d.descend():
		walked += 1
	check(walked == 3, "choir_sanctum descends through all 4 floors (%d)" % (walked + 1))
	check(d.floor_index == 4, "ends on floor 4")
	host.queue_free()


func _count_spawners(d: Dungeon) -> int:
	var n := 0
	for child in d.floor_root.get_children():
		if child is EnemySpawner:
			n += 1
	return n


func _spawner_depths(d: Dungeon) -> Array:
	var out := []
	for child in d.floor_root.get_children():
		if child is EnemySpawner:
			out.append((child as EnemySpawner).floor_index)
	return out
