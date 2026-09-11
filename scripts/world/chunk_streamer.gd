class_name ChunkStreamer
extends Node2D
## Streams world chunks around a target node (DECISIONS.md #6).
## Authored chunks live at res://world/chunks/chunk_X_Y.tscn (Tiled pipeline,
## Phase 2). Until they exist, a deterministic placeholder chunk is generated
## (3 biome palettes + scenery) so streaming is fully testable.

const CHUNK_SIZE := 1024
const VIEW_RADIUS := 1
const CHUNK_SCENE_DIR := "res://world/chunks"
const UPDATE_INTERVAL := 0.25

var follow_target: Node2D
## Dungeon interiors are built far off-map and the player is moved to them, so the
## streamer used to keep generating ordinary overworld chunks - monster spawners
## and all - underneath the dungeon room (audit C5). Inside a dungeon it is
## suspended instead.
var suspended := false

var _loaded: Dictionary = {}
var _timer := 0.0


func _physics_process(delta: float) -> void:
	if follow_target == null or suspended:
		return
	_timer += delta
	if _timer < UPDATE_INTERVAL:
		return
	_timer = 0.0
	_update()


func set_target(t: Node2D) -> void:
	follow_target = t
	_update()


func suspend() -> void:
	suspended = true


func resume() -> void:
	suspended = false
	_update()


func get_loaded_chunk(key: Vector2i) -> Node:
	return _loaded.get(key, null)


func _update() -> void:
	var cx := int(floorf(follow_target.global_position.x / float(CHUNK_SIZE)))
	var cy := int(floorf(follow_target.global_position.y / float(CHUNK_SIZE)))
	var needed := {}
	for y in range(cy - VIEW_RADIUS, cy + VIEW_RADIUS + 1):
		for x in range(cx - VIEW_RADIUS, cx + VIEW_RADIUS + 1):
			var key := Vector2i(x, y)
			needed[key] = true
			if not _loaded.has(key):
				_load_chunk(key)
	for key in _loaded.keys():
		if not needed.has(key):
			(_loaded[key] as Node).queue_free()
			_loaded.erase(key)
			EventBus.chunk_unloaded.emit(key)


func _load_chunk(key: Vector2i) -> void:
	var path := "%s/chunk_%d_%d.tscn" % [CHUNK_SCENE_DIR, key.x, key.y]
	var chunk: Node2D
	if ResourceLoader.exists(path):
		chunk = (load(path) as PackedScene).instantiate()
	else:
		chunk = _build_placeholder_chunk(key)
	chunk.position = Vector2(key.x * CHUNK_SIZE, key.y * CHUNK_SIZE)
	add_child(chunk)
	_loaded[key] = chunk
	# Phase F6: secrets belong to the chunk they sit in, whether that chunk is an
	# authored scene (res://world/chunks) or a generated placeholder — spawning
	# them inside the placeholder builder alone would have meant the real map,
	# which *is* authored, had no secrets in it at all.
	_populate_secrets(chunk, key)
	EventBus.chunk_loaded.emit(key)


## Chunk-radius at which one biome gives way to the next. A chunk adjacent to the
## spawn used to be able to roll Frosthollow purely on its hash, and the frost
## table spawns level 85-100 archetypes next to the starting camp (audit C2).
const BIOME_BANDS := [2.6, 5.2]


func biome_of_chunk(key: Vector2i) -> int:
	## 0 meadow · 1 barrens · 2 frosthollow, by distance from the origin rather
	## than by a free roll. The band edge is wobbled by a chunk-stable hash so the
	## world does not read as three perfect rings.
	var d := Vector2(float(key.x), float(key.y)).length()
	var wobble := (float(hash(key) % 1000) / 1000.0 - 0.5) * 1.1
	if d + wobble < BIOME_BANDS[0]:
		return 0
	if d + wobble < BIOME_BANDS[1]:
		return 1
	return 2


func _build_placeholder_chunk(key: Vector2i) -> Node2D:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) & 0x7FFFFFFF
	var biome := biome_of_chunk(key)
	var palettes := [
		Color(0.24, 0.42, 0.25),
		Color(0.55, 0.47, 0.33),
		Color(0.33, 0.38, 0.47),
	]
	var root := Node2D.new()
	root.name = "Chunk_%d_%d" % [key.x, key.y]

	var ground := Polygon2D.new()
	ground.polygon = PackedVector2Array([
		Vector2.ZERO,
		Vector2(CHUNK_SIZE, 0),
		Vector2(CHUNK_SIZE, CHUNK_SIZE),
		Vector2(0, CHUNK_SIZE),
	])
	ground.color = palettes[biome].lightened(rng.randf_range(0.0, 0.06))
	ground.z_index = -10
	root.add_child(ground)

	for i in rng.randi_range(2, 5):
		var rock := Polygon2D.new()
		rock.polygon = _circle_polygon(rng.randf_range(10.0, 26.0))
		rock.position = Vector2(
			rng.randf_range(64.0, CHUNK_SIZE - 64.0),
			rng.randf_range(64.0, CHUNK_SIZE - 64.0)
		)
		rock.color = palettes[biome].darkened(0.45)
		root.add_child(rock)

	var tag := Label.new()
	tag.text = "(%d, %d)" % [key.x, key.y]
	tag.position = Vector2(12, 8)
	tag.add_theme_color_override("font_color", Color(1, 1, 1, 0.25))
	root.add_child(tag)

	# Enemy spawners. The spawn chunk keeps the starting area safe, and so do its
	# immediate neighbours: the first thing a new player does is walk out of the
	# camp, and that walk should not be into a level-30 spawn table (audit C2).
	if not _is_spawn_safe(key):
		_populate_enemies(root, rng, biome)
	return root


## Chunks within this many chunks of the origin carry no spawners at all.
const SPAWN_SAFE_RADIUS := 2


func _is_spawn_safe(key: Vector2i) -> bool:
	return absi(key.x) <= SPAWN_SAFE_RADIUS and absi(key.y) <= SPAWN_SAFE_RADIUS


func _populate_secrets(root: Node2D, key: Vector2i) -> void:
	## Phase F6: the world's secrets stream in with the chunk that holds them, so a
	## secret is a place in the world, not a list entry — walk to it or do not find
	## it. Found/not-found lives in GameState, so re-streaming a chunk after a save
	## never resurrects a secret or pays one twice.
	for sid in SecretsDB.secrets_in_chunk(key):
		var site := SecretSite.new()
		site.name = "Secret_%s" % sid
		site.secret_id = String(sid)
		site.position = SecretsDB.position_of(String(sid)) - root.position
		root.add_child(site)


func _populate_enemies(root: Node2D, rng: RandomNumberGenerator, biome: int) -> void:
	## Phase F2: which monsters live here, and how strong they are, comes from the
	## roster's own biome tables + level bands (data/enemies.json `spawns`), not
	## from a hardcoded list — so a new monster is placed by declaring its biome
	## and band, and can never appear outside them.
	var biome_name: String = ["meadow", "barrens", "frost"][clampi(biome, 0, 2)]
	var table: Array = EnemyDB.spawn_table(biome_name)
	if table.is_empty():
		return
	for i in rng.randi_range(1, 2):
		var local := Vector2(
			rng.randf_range(128.0, CHUNK_SIZE - 128.0),
			rng.randf_range(128.0, CHUNK_SIZE - 128.0)
		)
		# Phase E §1: settlements are safe ground — no spawner may land inside a
		# settlement's safe radius. Roll the position again, and if eight tries are
		# not enough, push the point radially outward until it clears the bubble:
		# skipping the spawner instead left chunks that straddle a town completely
		# empty, which reads as a dead patch of map rather than a safe one.
		var world_pos := root.position + local
		var tries := 0
		while Settlement.safe_zone_at(world_pos) and tries < 8:
			local = Vector2(
				rng.randf_range(128.0, CHUNK_SIZE - 128.0),
				rng.randf_range(128.0, CHUNK_SIZE - 128.0)
			)
			world_pos = root.position + local
			tries += 1
		if Settlement.safe_zone_at(world_pos):
			local = _push_out_of_safe_zones(local, root.position)
		var spawner := EnemySpawner.new()
		spawner.archetype = String(table[rng.randi_range(0, table.size() - 1)])
		spawner.count = rng.randi_range(1, 2)
		# Phase F7: no blanket biome multiplier. Each archetype's stats are authored
		# against the player curve at the middle of its own level band, so a second
		# scale on top of that (barrens x1.15, frost x1.81) was double-counting and
		# made whole regions harder than the ladder they were measured against.
		spawner.power_scale = 1.0
		spawner.position = local
		root.add_child(spawner)


func _push_out_of_safe_zones(local: Vector2, chunk_origin: Vector2) -> Vector2:
	## Walk the point outward from the nearest settlement centre until it is clear
	## of every safe bubble, then clamp it back inside the chunk.
	var guard := 0
	while Settlement.safe_zone_at(chunk_origin + local) and guard < 64:
		var nearest := Vector2.ZERO
		var best := INF
		for id in Settlement.all():
			var d: Dictionary = (Settlement.all() as Dictionary)[id]
			var pos: Array = d.get("position", [0, 0])
			var centre := Vector2(float(pos[0]), float(pos[1]))
			if centre.distance_to(chunk_origin + local) < best:
				best = centre.distance_to(chunk_origin + local)
				nearest = centre
		var away := (chunk_origin + local - nearest)
		if away.length() < 0.001:
			away = Vector2.RIGHT
		local += away.normalized() * 48.0
		local.x = clampf(local.x, 96.0, CHUNK_SIZE - 96.0)
		local.y = clampf(local.y, 96.0, CHUNK_SIZE - 96.0)
		guard += 1
	return local


func _circle_polygon(radius: float, sides: int = 8) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in sides:
		var a := TAU * float(i) / float(sides)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts
