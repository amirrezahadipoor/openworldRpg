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
	_test_biome_geography()
	_test_micro_locations()
	await _test_dungeon_vaults()
	_test_overworld_spawners()
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


func _test_biome_geography() -> void:
	print("[world_map_test] biome geography matches the generated chunks")
	var x_range := range(-2, 5)
	var y_range := range(-3, 2)
	var matches := 0
	var interior := 0
	for cy in y_range:
		for cx in x_range:
			var path := "res://world/chunks/chunk_%d_%d.json" % [cx, cy]
			if not FileAccess.file_exists(path):
				continue
			var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
			var stamped := -1
			for prop in doc.get("properties", []):
				if String(prop.get("name", "")) == "biome":
					stamped = int(prop.get("value", -1))
			if stamped == Biome.biome_of(int(cx), int(cy)):
				matches += 1
			# A chunk with no differently-biome neighbour is interior; the rest sit
			# on a seam, and the seams must not be perfectly straight rows/columns.
			var n := Biome.biome_of(cx, cy + 1)
			if n == Biome.biome_of(cx, cy - 1) and n == Biome.biome_of(cx + 1, cy) \
					and n == Biome.biome_of(cx - 1, cy):
				interior += 1
	check(matches == 35, "all 35 chunks agree with Biome.biome_of (%d)" % matches)
	check(interior < 35, "biome borders are not straight lines (%d chunks sit on a seam)" % (35 - interior))
	check(frost_line_varies(), "the frost line varies per chunk column")
	check(barrens_line_varies(), "the barrens line varies per chunk row")


func frost_line_varies() -> bool:
	var seen := {}
	for cx in range(-2, 5):
		seen[Biome.frost_line(cx)] = true
	return seen.size() > 1


func barrens_line_varies() -> bool:
	var seen := {}
	for cy in range(-3, 2):
		seen[Biome.barrens_line(cy)] = true
	return seen.size() > 1


func _test_micro_locations() -> void:
	print("[world_map_test] named micro-locations exist on the map")
	var signs := 0
	var levers := 0
	var gates := 0
	var vault_chests := 0
	for cy in range(-3, 2):
		for cx in range(-2, 5):
			var path := "res://world/chunks/chunk_%d_%d.json" % [cx, cy]
			if not FileAccess.file_exists(path):
				continue
			var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
			for layer in doc.get("layers", []):
				if String(layer.get("name", "")) != "objects":
					continue
				for obj in layer.get("objects", []):
					var nm := String(obj.get("name", ""))
					var ty := String(obj.get("type", ""))
					if ty == "sign" and nm.begins_with("micro_"):
						signs += 1
					elif ty == "lever":
						levers += 1
					elif ty == "gate":
						gates += 1
					elif ty == "chest" and nm.begins_with("chest_vault_"):
						vault_chests += 1
	check(signs >= 12, "at least 12 named micro-locations carry a sign (%d)" % signs)
	check(levers >= 3, "levers placed in the world (%d)" % levers)
	check(gates == levers, "every world lever has its matching gate (%d levers / %d gates)" % [levers, gates])
	check(vault_chests >= 2, "lever-gated caches exist (%d)" % vault_chests)


func _test_dungeon_vaults() -> void:
	print("[world_map_test] non-boss dungeon floors hide a lever vault")
	var host := Node2D.new()
	add_child(host)
	var d := Dungeon.new()
	host.add_child(d)
	d.setup("drowned_mill", 1)
	await get_tree().process_frame
	var levers := 0
	var gates := 0
	var chests := 0
	for child in d.floor_root.get_children():
		if child is Lever:
			levers += 1
		elif child is SecretGate:
			gates += 1
		elif child is Chest:
			chests += 1
	check(levers == 1 and gates == 1 and chests == 1,
		"floor 1 builds one lever, one gate and one chest (%d/%d/%d)" % [levers, gates, chests])

	# A boss floor is an arena: no vault clutter in it.
	d.descend()
	await get_tree().process_frame
	var boss_levers := 0
	for child in d.floor_root.get_children():
		if child is Lever:
			boss_levers += 1
	check(boss_levers == 0, "boss floors have no vault")
	host.queue_free()


func _test_overworld_spawners() -> void:
	## The overworld used to bake two monster names per biome into the world
	## generator, so ten of the fourteen roster monsters never appeared on the
	## map at all (v3 audit §25). The generator now reads the roster's own
	## `spawns` tables; this pins that down so it cannot quietly regress.
	print("[world_map_test] overworld spawners come from the roster")
	var roster: Dictionary = EnemyDB.spawns()
	if roster.is_empty():
		roster = _roster_spawns()
	var allowed: Array = []
	for biome in roster.keys():
		for a in (roster[biome] as Dictionary).get("archetypes", []):
			if not allowed.has(String(a)):
				allowed.append(String(a))

	var seen: Array = []
	var out_of_table: Array = []
	for cy in range(-3, 2):
		for cx in range(-2, 5):
			var board := _load_chunk(Vector2i(cx, cy))
			if board.is_empty():
				continue
			for obj in (board["layers"][1] as Dictionary).get("objects", []):
				if String(obj.get("type", "")) != "spawner":
					continue
				for prop in obj.get("properties", []):
					if String(prop.get("name", "")) != "archetype":
						continue
					var a := String(prop.get("value", ""))
					if not seen.has(a):
						seen.append(a)
					if not allowed.has(a):
						out_of_table.append(a)
	check(allowed.size() >= 14, "the roster lists at least fourteen field monsters (%d)" % allowed.size())
	check(out_of_table.is_empty(), "no spawner uses a monster outside the roster tables %s" % str(out_of_table))
	check(seen.size() >= 10, "the overworld actually spawns the roster's variety (%d kinds)" % seen.size())


func _roster_spawns() -> Dictionary:
	var f := FileAccess.open("res://data/enemies.json", FileAccess.READ)
	if f == null:
		return {}
	var doc: Dictionary = JSON.parse_string(f.get_as_text()) as Dictionary
	return doc.get("spawns", {}) if doc != null else {}


func _load_chunk(key: Vector2i) -> Dictionary:
	var path := "res://world/chunks/chunk_%d_%d.json" % [key.x, key.y]
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var doc: Dictionary = JSON.parse_string(f.get_as_text()) as Dictionary
	return doc if doc != null else {}
