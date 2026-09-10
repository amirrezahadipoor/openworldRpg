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

var _loaded: Dictionary = {}
var _timer := 0.0


func _physics_process(delta: float) -> void:
	if follow_target == null:
		return
	_timer += delta
	if _timer < UPDATE_INTERVAL:
		return
	_timer = 0.0
	_update()


func set_target(t: Node2D) -> void:
	follow_target = t
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


func _build_placeholder_chunk(key: Vector2i) -> Node2D:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) & 0x7FFFFFFF
	var biome := rng.randi_range(0, 2)  # 0 meadow · 1 barrens · 2 frosthollow
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

	# Enemy spawners (skip the spawn chunk so the starting area is safe).
	if key != Vector2i.ZERO:
		_populate_enemies(root, rng, biome)
	return root


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
	var band: Array = EnemyDB.spawnable_band(biome_name)
	for i in rng.randi_range(1, 2):
		var local := Vector2(
			rng.randf_range(128.0, CHUNK_SIZE - 128.0),
			rng.randf_range(128.0, CHUNK_SIZE - 128.0)
		)
		# Phase E §1: settlements are safe ground — no spawner may land inside a
		# settlement's safe radius (roll the position again, bounded attempts).
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
			continue
		var spawner := EnemySpawner.new()
		spawner.archetype = String(table[rng.randi_range(0, table.size() - 1)])
		spawner.count = rng.randi_range(1, 2)
		spawner.power_scale = EnemyDB.band_power_scale(band)
		spawner.position = local
		root.add_child(spawner)


func _circle_polygon(radius: float, sides: int = 8) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in sides:
		var a := TAU * float(i) / float(sides)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts
