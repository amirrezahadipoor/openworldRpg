class_name Dungeon
extends Node2D
## Phase E §1 — a multi-floor dungeon driven by data/dungeons.json.
##
## An entrance is a world object (a stair mouth). Interacting with it descends:
## `descend()` builds the current floor from the floor's data — a walled room
## sized by spawner count, the floor's enemy table, and a stair back up (or
## down). Floors reuse the existing `EnemySpawner`, which now carries a
## `floor_index` so depth drives hp/damage/xp scaling (Phase E §6) instead of
## each dungeon hand-tuning power_scale.
##
## The boss floor of `ember_warden_keep` deliberately uses the existing
## `BossArena` three-phase fight untouched (Phase E: the final fight is
## mechanically unchanged; only its framing changed).

signal floor_changed(dungeon_id: String, floor: int, total: int)
signal exited(dungeon_id: String)

const DATA_PATH := "res://data/dungeons.json"
const ROOM := 900.0          # interior size of one floor
const WALL := 48.0
const STAIR_UP := Vector2(96, 96)
const STAIR_DOWN := Vector2(900 - 96, 900 - 96)
const BOSS_SCENE := preload("res://scenes/enemies/data_boss.tscn")

static var _cache: Dictionary = {}

var dungeon_id := ""
var data: Dictionary = {}
var floor_index := 1
var floor_root: Node2D
var _rng := RandomNumberGenerator.new()
var _floor_boss: Node = null


static func all() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("Dungeon: data/dungeons.json missing")
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Dungeon: data/dungeons.json is not a JSON object")
		return {}
	_cache = (parsed as Dictionary).get("dungeons", {})
	return _cache


static func get_data(id: String) -> Dictionary:
	return (all() as Dictionary).get(id, {})


static func floors_of(id: String) -> int:
	## Static accessor used by the entrance plate. The instance method
	## `floor_count()` below reports the depth of the dungeon in play.
	return (get_data(id).get("floors", []) as Array).size()


static func total_floors() -> int:
	var n := 0
	for id in all():
		n += ((all() as Dictionary)[id].get("floors", []) as Array).size()
	return n


func setup(id: String, at_floor: int = 1) -> void:
	dungeon_id = id
	data = get_data(id)
	if data.is_empty():
		push_error("Dungeon: unknown id '%s'" % id)
		return
	var p: Array = data.get("position", [0, 0])
	position = Vector2(float(p[0]), float(p[1]))
	_rng.seed = (hash(dungeon_id) & 0x7FFFFFFF) + at_floor
	floor_index = maxi(1, at_floor)
	_build_floor()


func floor_count() -> int:
	return (data.get("floors", []) as Array).size()


func floor_data(idx: int = -1) -> Dictionary:
	var f: Array = data.get("floors", [])
	var i := (floor_index if idx < 0 else idx) - 1
	if i < 0 or i >= f.size():
		return {}
	return f[i]


func descend() -> bool:
	## Move one floor deeper. Returns false at the bottom.
	if floor_index >= floor_count():
		return false
	floor_index += 1
	_rng.seed = (hash(dungeon_id) & 0x7FFFFFFF) + floor_index
	_build_floor()
	floor_changed.emit(dungeon_id, floor_index, floor_count())
	return true


func ascend() -> bool:
	## Move one floor back up. Returns false on the surface floor.
	if floor_index <= 1:
		return false
	floor_index -= 1
	_rng.seed = (hash(dungeon_id) & 0x7FFFFFFF) + floor_index
	_build_floor()
	floor_changed.emit(dungeon_id, floor_index, floor_count())
	return true


func _build_floor() -> void:
	if floor_root != null and is_instance_valid(floor_root):
		floor_root.queue_free()
	floor_root = Node2D.new()
	floor_root.name = "Floor_%d" % floor_index
	add_child(floor_root)
	var fd := floor_data()
	if fd.is_empty():
		return
	_build_room()
	_build_stairs()
	_populate(fd)
	_build_torches()


func _build_room() -> void:
	var floor_poly := Polygon2D.new()
	floor_poly.polygon = PackedVector2Array([
		Vector2.ZERO, Vector2(ROOM, 0), Vector2(ROOM, ROOM), Vector2(0, ROOM),
	])
	floor_poly.color = Color(0.16, 0.15, 0.17).lightened(float(floor_index - 1) * 0.02)
	# Above the streamer's ground band (-10): the interior must occlude any
	# overworld chunk that happens to exist in this corner of the map.
	floor_poly.z_index = -6
	floor_root.add_child(floor_poly)

	# Wall ring (four bands) so the floor reads as an interior.
	for band in [
		Rect2(-WALL, -WALL, ROOM + WALL * 2, WALL),
		Rect2(-WALL, ROOM, ROOM + WALL * 2, WALL),
		Rect2(-WALL, 0, WALL, ROOM),
		Rect2(ROOM, 0, WALL, ROOM),
	]:
		var wall := Polygon2D.new()
		wall.polygon = PackedVector2Array([
			band.position,
			band.position + Vector2(band.size.x, 0),
			band.position + band.size,
			band.position + Vector2(0, band.size.y),
		])
		wall.color = Color(0.11, 0.10, 0.12)
		wall.z_index = -5
		floor_root.add_child(wall)

	var label := Label.new()
	label.text = String(floor_data().get("name", dungeon_id))
	label.position = Vector2(28, 24)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(1, 0.86, 0.6, 0.8))
	floor_root.add_child(label)


func _build_stairs() -> void:
	# Up: on floor 1 this leaves the dungeon entirely, otherwise it climbs.
	var up_label := "Exit" if floor_index <= 1 else "Up"
	var up_color := Color(0.62, 0.78, 0.6) if floor_index <= 1 else Color(0.55, 0.65, 0.85)
	floor_root.add_child(_stair_marker(STAIR_UP, up_color, up_label, true))
	# Down: only when another floor exists.
	if floor_index < floor_count():
		floor_root.add_child(_stair_marker(STAIR_DOWN, Color(0.95, 0.62, 0.3), "Down", false))


func _stair_marker(at: Vector2, color: Color, label_text: String, up: bool) -> Node2D:
	var node := Node2D.new()
	node.position = at
	var pit := Polygon2D.new()
	pit.polygon = PackedVector2Array([
		Vector2(-26, -18), Vector2(26, -18), Vector2(20, 18), Vector2(-20, 18),
	])
	pit.color = color.darkened(0.55)
	node.add_child(pit)
	for i in 3:
		var step := Polygon2D.new()
		var y := -12.0 + float(i) * 10.0
		step.polygon = PackedVector2Array([
			Vector2(-18, y), Vector2(18, y), Vector2(16, y + 6), Vector2(-16, y + 6),
		])
		step.color = color.lightened(float(i) * 0.08)
		node.add_child(step)
	var tag := Label.new()
	tag.text = label_text
	tag.position = Vector2(-16, 22)
	tag.add_theme_font_size_override("font_size", 12)
	tag.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	node.add_child(tag)

	# The stair is a physical exit: stepping on it moves a floor.
	var area := Area2D.new()
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 34.0
	shape.shape = circle
	area.add_child(shape)
	area.body_entered.connect(func(body: Node) -> void:
		if not body.is_in_group("player"):
			return
		if up and floor_index <= 1:
			exited.emit(dungeon_id)   # surface
		elif up:
			ascend()
		else:
			descend()
	)
	node.add_child(area)
	return node


func _build_vault() -> void:
	## Every non-boss floor hides one sealed side-vault: a lever, a rock gate and
	## a chest behind it. Dungeon floors were a room, a stair and a spawn ring —
	## no puzzle, no reason to look at the walls. The vault is the reason.
	var floor_id := "%s_%d" % [dungeon_id, floor_index]
	if bool(GameState.quest_flags.get("lever_%s" % floor_id, false)):
		pass  # already opened on a previous run: the gate builds itself open
	var gate := SecretGate.new()
	gate.gate_id = "vault_%s" % floor_id
	gate.position = Vector2(ROOM - 150.0, 180.0)
	floor_root.add_child(gate)

	var lever := Lever.new()
	lever.lever_id = floor_id
	lever.gate_id = gate.gate_id
	lever.prompt_text = "Pull the lever"
	lever.position = Vector2(96.0, ROOM - 150.0)
	floor_root.add_child(lever)

	# Chest is built the way the chunk pipeline builds one: an Area2D with the
	# chest script on it (there is no chest.tscn in this project).
	var chest := Area2D.new()
	chest.name = "VaultChest_" + floor_id
	chest.set_script(load("res://scripts/world/chest.gd"))
	chest.set("chest_id", "vault_%s" % floor_id)
	chest.set("gold", 120 + 40 * floor_index)
	chest.set("item_id", "health_potion" if floor_index % 2 == 1 else "mana_potion")
	floor_root.add_child(chest)
	(chest as Node2D).position = Vector2(ROOM - 60.0, 180.0)

	# Two torches so the vault corner is legible in the dark. The light texture is
	# a radial gradient made in code — no extra art file to ship.
	for at in [Vector2(ROOM - 240.0, 120.0), Vector2(ROOM - 240.0, 300.0)]:
		var light := PointLight2D.new()
		light.color = Color(1.0, 0.72, 0.35)
		light.energy = 0.85
		light.texture = _radial_light_texture()
		light.texture_scale = 2.4
		light.position = at
		floor_root.add_child(light)


func _radial_light_texture() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	return tex


func _populate(fd: Dictionary) -> void:
	if not bool(fd.get("boss", false)):
		_build_vault()
	var table: Array = fd.get("enemies", ["grunt"])
	var count := int(fd.get("spawner_count", 3))
	var power := float(fd.get("power_scale", 1.0))
	var is_boss := bool(fd.get("boss", false))

	if is_boss and table.has("ember_warden"):
		# The shipped three-phase fight, untouched (Phase E keeps it as-is).
		var arena_script: GDScript = load("res://scripts/enemies/boss_arena.gd")
		if arena_script != null:
			var arena: Node2D = Node2D.new()
			arena.set_script(arena_script)
			arena.position = Vector2(ROOM * 0.5, ROOM * 0.5)
			floor_root.add_child(arena)
			return

	# Phase F3: a named boss gates the floor. DataBoss reads its phase table from
	# the roster, so five of the six bosses are authored entirely in data.
	if is_boss and table.size() >= 1 and EnemyDB.is_boss(String(table[0])):
		var arena := Node2D.new()
		arena.name = "BossArena_%s" % String(table[0])
		arena.position = Vector2(ROOM * 0.5, ROOM * 0.5)
		floor_root.add_child(arena)
		var boss: DataBoss = BOSS_SCENE.instantiate() as DataBoss
		boss.position = Vector2.ZERO
		arena.add_child(boss)
		boss.setup_archetype(String(table[0]), power, int(fd.get("floor_index", floor_index)))
		# Phase F4: killing the boss is the world state other systems read.
		# Re-entering a boss floor must not stack connections, so the listener is
		# the plain method (idempotent) and the boss is remembered in a member.
		_floor_boss = boss
		if not EventBus.enemy_died.is_connected(_on_enemy_died):
			EventBus.enemy_died.connect(_on_enemy_died)
		# The roster boss gets a line before the fight: the antagonists used to
		# be silent, which left the lore coming only from two side NPCs.
		EventBus.boss_encounter_started.emit(String(table[0]), EnemyDB.display_name(String(table[0])))
		_spawn_boss_guards(table)
		return

	# Ring the floor with spawners, avoiding the stairs.
	for i in count:
		var a := TAU * float(i) / float(count) + 0.4
		var r := ROOM * 0.34
		var spawner := EnemySpawner.new()
		spawner.archetype = String(table[_rng.randi_range(0, table.size() - 1)])
		spawner.count = 1 + (1 if is_boss else 0)
		spawner.power_scale = power
		spawner.floor_index = int(fd.get("floor_index", floor_index))
		spawner.position = Vector2(ROOM * 0.5, ROOM * 0.5) + Vector2(cos(a), sin(a)) * r
		floor_root.add_child(spawner)


func _on_enemy_died(enemy: Node) -> void:
	if _floor_boss != null and enemy == _floor_boss:
		QuestManager.register_flag("cleared_%s" % dungeon_id)


func _spawn_boss_guards(table: Array) -> void:
	## A couple of the boss's kin so the arena is not a bare duel.
	var guards: Array = []
	for m in EnemyDB.monsters():
		if EnemyDB.biome_of(String(m)) == biome_name() and not table.has(m):
			guards.append(m)
	if guards.is_empty():
		return
	for i in 2:
		var spawner := EnemySpawner.new()
		spawner.archetype = String(guards[_rng.randi_range(0, guards.size() - 1)])
		spawner.count = 1
		spawner.floor_index = floor_index
		var a := TAU * float(i) / 2.0 + 0.6
		spawner.position = Vector2(ROOM * 0.5, ROOM * 0.5) + Vector2(cos(a), sin(a)) * ROOM * 0.3
		floor_root.add_child(spawner)


func biome_name() -> String:
	return String(data.get("biome", "meadow"))


func _build_torches() -> void:
	for i in 6:
		var a := TAU * float(i) / 6.0
		var light := PointLight2D.new()
		light.texture = load("res://assets/placeholder/light.svg")
		light.color = Color(1.0, 0.66, 0.34)
		light.energy = 0.55
		light.texture_scale = 1.6
		light.position = Vector2(ROOM * 0.5, ROOM * 0.5) + Vector2(cos(a), sin(a)) * ROOM * 0.44
		floor_root.add_child(light)
