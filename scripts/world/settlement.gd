class_name Settlement
extends Node2D
## Phase E §1 — a settlement built as a real scene from data/settlements.json.
##
## Replaces "one recoloured chunk per biome": each settlement lays down a paved
## plaza, a distinct ring of buildings sized by tier (village 6 / town 10 /
## city 16), its own waypoint + name sign, and the NPCs the data assigns to it.
## Buildings and props are deterministic per settlement id, so a settlement
## looks the same every session and every machine.
##
## The settlement also declares a `safe_radius`: the chunk streamer skips enemy
## spawners inside it (see ChunkStreamer._populate_enemies).

signal npc_interacted(npc: NPC)

const NPC_SCENE := "res://scenes/world/npc.tscn"
const PROPS_PATH := "res://assets/tiles/props/"
const DATA_PATH := "res://data/settlements.json"

static var _cache: Dictionary = {}

var settlement_id := ""
var data: Dictionary = {}
var safe_radius := 300.0
var _t := 0.0
var _lanterns: Array[PointLight2D] = []


static func all() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("Settlement: data/settlements.json missing")
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Settlement: data/settlements.json is not a JSON object")
		return {}
	_cache = (parsed as Dictionary).get("settlements", {})
	return _cache


static func get_data(id: String) -> Dictionary:
	return (all() as Dictionary).get(id, {})


static func safe_zone_at(pos: Vector2) -> bool:
	## True when a world position sits inside any settlement's safe radius.
	for id in all():
		var s: Dictionary = (all() as Dictionary)[id]
		var p: Array = s.get("position", [0, 0])
		var r := float(s.get("safe_radius", 300.0))
		if pos.distance_to(Vector2(float(p[0]), float(p[1]))) <= r:
			return true
	return false


func setup(id: String) -> void:
	settlement_id = id
	data = get_data(id)
	if data.is_empty():
		push_error("Settlement: unknown id '%s'" % id)
		return
	var p: Array = data.get("position", [0, 0])
	position = Vector2(float(p[0]), float(p[1]))
	safe_radius = float(data.get("safe_radius", 300.0))
	_build()


func _process(delta: float) -> void:
	_t += delta
	# Lanterns flicker with the same cheap two-sine trick the camp fire uses.
	for i in _lanterns.size():
		var l := _lanterns[i]
		l.energy = 0.72 + 0.1 * sin(_t * 7.0 + float(i)) + 0.05 * sin(_t * 19.0 + float(i))


func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(settlement_id) & 0x7FFFFFFF
	var radius := float(data.get("radius", 210.0))
	var ground := _color("ground_color", Color(0.28, 0.46, 0.28))
	var roof := _color("roof_color", Color(0.52, 0.30, 0.22))

	_build_plaza(radius, ground)
	var count := int(data.get("buildings", 6))
	for i in count:
		var a := TAU * float(i) / float(count) + rng.randf_range(-0.12, 0.12)
		var r := radius * rng.randf_range(0.72, 1.0)
		_build_house(Vector2(cos(a), sin(a)) * r, roof, rng, i)
	_build_sign(radius)
	if (data.get("services", []) as Array).has("waypoint"):
		_build_waypoint(radius)
	_build_lanterns(radius, count)
	_spawn_npcs(radius, rng)


func _color(key: String, fallback: Color) -> Color:
	var a: Array = data.get(key, [])
	if a.size() != 3:
		return fallback
	return Color(float(a[0]), float(a[1]), float(a[2]))


func _build_plaza(radius: float, ground: Color) -> void:
	## Paved plaza: a trodden disc of the biome's ground tile (same technique as
	## the camp — real tiles, not a flat colour disc), then a paved inner ring.
	var patch := Polygon2D.new()
	patch.polygon = _circle_poly(radius * 0.78, 44, radius * 0.05)
	patch.texture = load(PROPS_PATH + "camp_ground.png")
	patch.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	patch.uv = patch.polygon
	# Tint the trodden ground toward the biome palette, otherwise a Meadow dirt
	# patch reads as a mud blob dropped on the Frosthollow snow.
	patch.color = Color(1, 1, 1).lerp(ground, 0.55)
	patch.z_index = -8
	add_child(patch)

	var pave := Polygon2D.new()
	pave.polygon = _circle_poly(radius * 0.42, 32)
	pave.color = ground.lightened(0.12)
	pave.z_index = -7
	add_child(pave)


func _build_house(pos: Vector2, roof: Color, rng: RandomNumberGenerator, index: int) -> void:
	var house := Node2D.new()
	house.position = pos
	var w := rng.randf_range(34.0, 48.0)
	var h := rng.randf_range(26.0, 36.0)

	# Wall block.
	var wall := Polygon2D.new()
	wall.polygon = PackedVector2Array([
		Vector2(-w, h * 0.25), Vector2(0, -h * 0.15),
		Vector2(w, h * 0.25), Vector2(0, h * 0.7),
	])
	wall.color = Color(0.42, 0.34, 0.28).lightened(rng.randf_range(-0.04, 0.06))
	house.add_child(wall)

	# Roof: two slopes, tinted per biome so a frost town doesn't look meadow-ish.
	for side in [-1.0, 1.0]:
		var slope := Polygon2D.new()
		slope.polygon = PackedVector2Array([
			Vector2(0, -h * 0.15), Vector2(side * w, h * 0.25),
			Vector2(side * w * 0.82, h * 0.05), Vector2(0, -h * 0.5),
		])
		slope.color = roof.lightened(rng.randf_range(-0.05, 0.05))
		house.add_child(slope)

	# Door + lit window.
	var door := Polygon2D.new()
	door.polygon = PackedVector2Array([
		Vector2(-7, h * 0.68), Vector2(-7, h * 0.34),
		Vector2(7, h * 0.34), Vector2(7, h * 0.68),
	])
	door.color = Color(0.24, 0.17, 0.12)
	house.add_child(door)

	var window := Polygon2D.new()
	window.polygon = PackedVector2Array([
		Vector2(w * 0.42, h * 0.18), Vector2(w * 0.62, h * 0.2),
		Vector2(w * 0.62, h * 0.34), Vector2(w * 0.42, h * 0.32),
	])
	window.color = Color(0.98, 0.82, 0.45, 0.9)
	house.add_child(window)

	if index % 3 == 0:
		var lamp := _make_light(Color(1.0, 0.78, 0.44), 0.9, 1.5)
		lamp.position = Vector2(0, h * 0.1)
		house.add_child(lamp)
		_lanterns.append(lamp)

	house.z_index = -5
	add_child(house)


func _build_sign(radius: float) -> void:
	var post := Polygon2D.new()
	post.polygon = PackedVector2Array([
		Vector2(-3, 0), Vector2(-3, -34), Vector2(3, -34), Vector2(3, 0),
	])
	post.color = Color(0.35, 0.26, 0.18)
	add_child(post)
	var board := Polygon2D.new()
	board.polygon = PackedVector2Array([
		Vector2(-62, -34), Vector2(62, -34), Vector2(62, -62), Vector2(-62, -62),
	])
	board.color = Color(0.50, 0.36, 0.22)
	add_child(board)

	var label := Label.new()
	label.text = String(data.get("name", settlement_id))
	label.position = Vector2(-58, -60)
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
	add_child(label)

	var sign := Sign.new()
	sign.title = String(data.get("name", settlement_id))
	sign.text = String(data.get("desc", ""))
	sign.position = Vector2(0, -8)
	add_child(sign)


func _build_waypoint(radius: float) -> void:
	var wp := Waypoint.new()
	wp.wp_id = settlement_id
	wp.wp_name = String(data.get("name", settlement_id))
	wp.position = Vector2(radius * 0.22, radius * 0.16)
	add_child(wp)


func _build_lanterns(radius: float, count: int) -> void:
	for i in maxi(2, count / 3):
		var a := TAU * float(i) / float(maxi(2, count / 3))
		var lamp := _make_light(Color(1.0, 0.80, 0.48), 0.8, 2.0)
		lamp.position = Vector2(cos(a), sin(a)) * radius * 0.55
		add_child(lamp)
		_lanterns.append(lamp)


func _make_light(color: Color, energy: float, scale: float) -> PointLight2D:
	var light := PointLight2D.new()
	light.texture = load("res://assets/placeholder/light.svg")
	light.color = color
	light.energy = energy
	light.texture_scale = scale
	return light


func _spawn_npcs(radius: float, rng: RandomNumberGenerator) -> void:
	var scene: PackedScene = load(NPC_SCENE)
	var ids: Array = data.get("npcs", [])
	if ids.is_empty():
		return
	var services: Array = data.get("services", [])
	for i in ids.size():
		var npc_id := String(ids[i])
		var npc: NPC = scene.instantiate()
		npc.npc_id = npc_id
		npc.display_name = ""
		npc.is_vendor = (npc_id == "merchant_bram" or npc_id == "ysolde") and services.has("shop")
		npc.show_quest_marker = true
		npc.sprite_sheet = _sheet_for(npc_id)
		var a := TAU * float(i) / float(ids.size()) + 0.7
		npc.position = Vector2(cos(a), sin(a)) * radius * rng.randf_range(0.30, 0.55)
		npc.interacted.connect(func(n: NPC) -> void: npc_interacted.emit(n))
		add_child(npc)


func _sheet_for(npc_id: String) -> String:
	## Reuse the composed sheets already shipped; unknown NPCs keep placeholder
	## art rather than breaking the scene.
	var known := {
		"elder_rowan": "res://assets/lpc/npc_elder.png",
		"merchant_bram": "res://assets/lpc/npc_vendor.png",
		"hunter_kael": "res://assets/lpc/npc_hunter.png",
	}
	var sheet := String(known.get(npc_id, ""))
	if sheet != "" and not ResourceLoader.exists(sheet):
		return ""
	return sheet


func _circle_poly(radius: float, sides: int, jitter: float = 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(settlement_id) & 0x7FFFFFFF
	for i in sides:
		var a := TAU * float(i) / float(sides)
		var r := radius + (rng.randf_range(-jitter, jitter) if jitter > 0.0 else 0.0)
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts
