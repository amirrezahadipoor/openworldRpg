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
	return root


func _circle_polygon(radius: float, sides: int = 8) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in sides:
		var a := TAU * float(i) / float(sides)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts
