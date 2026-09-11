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
const FACADES_PATH := "res://data/facades.json"
## How much of the ring each house may take up before it is shrunk to fit, and
## how far below its anchor a house's ground line sits (the art is drawn from its
## footprint up, so the baseline hangs below the placement point, as the old
## polygon houses did).
const HOUSE_ARC_FILL := 1.5
const HOUSE_BASELINE := 24.0

static var _cache: Dictionary = {}
static var _facades: Dictionary = {}

var settlement_id := ""
var data: Dictionary = {}
var safe_radius := 300.0
var _t := 0.0
var _lanterns: Array[PointLight2D] = []


static var _doc_cache: Dictionary = {}


static func _document() -> Dictionary:
	if not _doc_cache.is_empty():
		return _doc_cache
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	_doc_cache = parsed as Dictionary
	return _doc_cache


static func all() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	var doc := _document()
	if doc.is_empty():
		push_error("Settlement: data/settlements.json missing or malformed")
		return {}
	_cache = doc.get("settlements", {})
	return _cache


static func facades() -> Dictionary:
	## H6.1: biome -> {sheet, houses[]} from data/facades.json, written by
	## tools/make_facade_sheets.py. Empty until a family has art; a biome with no
	## entry keeps the procedural houses, so this is additive.
	if not _facades.is_empty():
		return _facades
	var f := FileAccess.open(FACADES_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	_facades = (parsed as Dictionary).get("families", {})
	return _facades


static func facade_for(biome: String) -> Dictionary:
	var entry: Variant = facades().get(biome, {})
	return entry as Dictionary if typeof(entry) == TYPE_DICTIONARY else {}


static func get_data(id: String) -> Dictionary:
	return (all() as Dictionary).get(id, {})


static func safe_zones() -> Array:
	## Every bubble of no-combat ground: the nine settlements plus any standalone
	## zone declared in data/settlements.json (`safe_zones`). The starting camp is
	## one — it hosts an elder, a hunter and the first merchant, and until now it
	## was not safe ground at all.
	var out: Array = []
	for id in all():
		var s: Dictionary = (all() as Dictionary)[id]
		var p: Array = s.get("position", [0, 0])
		out.append({
			"id": String(id),
			"name": String(s.get("name", id)),
			"position": Vector2(float(p[0]), float(p[1])),
			"radius": float(s.get("safe_radius", 300.0)),
		})
	for z in ((_document() as Dictionary).get("safe_zones", []) as Array):
		var d: Dictionary = z
		var zp: Array = d.get("position", [0, 0])
		out.append({
			"id": String(d.get("id", "zone")),
			"name": String(d.get("name", d.get("id", "zone"))),
			"position": Vector2(float(zp[0]), float(zp[1])),
			"radius": float(d.get("radius", 300.0)),
		})
	return out


static func safe_zone_at(pos: Vector2) -> bool:
	## True when a world position sits inside any safe bubble.
	for z in safe_zones():
		if pos.distance_to((z as Dictionary)["position"]) <= float((z as Dictionary)["radius"]):
			return true
	return false


static func safe_zone_containing(pos: Vector2) -> Dictionary:
	## Which bubble a position is in (used by the HUD's zone readout and tests).
	for z in safe_zones():
		if pos.distance_to((z as Dictionary)["position"]) <= float((z as Dictionary)["radius"]):
			return z
	return {}


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
	# Facade art is a fixed size, so a crowded ring would overlap: shrink the
	# houses until the ring can hold them (a city has smaller houses than a
	# village, which is also how real towns look from above).
	var spacing := TAU * radius * 0.86 / float(maxi(count, 1))
	var house_scale := 1.0
	var family := facade_for(String(data.get("biome", "")))
	if not (family.get("houses", []) as Array).is_empty():
		var widest := 0.0
		for h in (family.get("houses", []) as Array):
			widest = maxf(widest, float((h.get("region", [0, 0, 0, 0]) as Array)[2]))
		house_scale = clampf(spacing * HOUSE_ARC_FILL / maxf(widest * 1.6, 1.0), 0.55, 1.0)
	for i in count:
		var a := TAU * float(i) / float(count) + rng.randf_range(-0.12, 0.12)
		var r := radius * rng.randf_range(0.72, 1.0)
		if family.is_empty():
			_build_house(Vector2(cos(a), sin(a)) * r, roof, rng, i)
		else:
			_build_facade_house(Vector2(cos(a), sin(a)) * r, family, rng, i, house_scale)
	_build_sign(radius)
	if (data.get("services", []) as Array).has("waypoint"):
		_build_waypoint(radius)
	_build_lanterns(radius, count)
	_build_safe_ring(radius)
	_spawn_npcs(radius, rng)


func _build_safe_ring(radius: float) -> void:
	## The no-combat boundary, drawn on the ground. `safe_zone_at()` has always
	## been invisible: enemies simply stopped existing at some radius the player
	## could only discover by walking out and counting. Two rings — a hard edge at
	## `safe_radius` and a soft fade 40 px inside it — say "this is town" without a
	## UI element. Same technique as BossArena's aggro ring.
	var edge := Line2D.new()
	edge.points = _circle_poly(safe_radius, 64)
	edge.width = 3.0
	edge.default_color = Color(0.95, 0.86, 0.60, 0.30)
	edge.z_index = -6
	add_child(edge)

	var soft := Line2D.new()
	soft.points = _circle_poly(maxf(safe_radius - 42.0, radius), 64)
	soft.width = 10.0
	soft.default_color = Color(0.95, 0.86, 0.60, 0.07)
	soft.z_index = -6
	add_child(soft)


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


func _build_facade_house(pos: Vector2, family: Dictionary, rng: RandomNumberGenerator,
		index: int, house_scale: float) -> void:
	## H6.1: a whole building drawn on the 32 px grid, instead of a wall quad and
	## two roof slopes. The atlas holds several designs per biome family and the
	## sprite is mirrored per house, so a village of six does not repeat itself.
	var houses: Array = family.get("houses", [])
	if houses.is_empty():
		return
	var tex_path := String(family.get("sheet", ""))
	var tex: Texture2D = load(tex_path) if ResourceLoader.exists(tex_path) else null
	if tex == null:
		return
	var pick: Dictionary = houses[rng.randi_range(0, houses.size() - 1)]
	var region: Array = pick.get("region", [0, 0, 0, 0])
	var house := Node2D.new()
	house.position = pos
	var body := Sprite2D.new()
	body.texture = tex
	body.region_enabled = true
	body.region_rect = Rect2(float(region[0]), float(region[1]), float(region[2]), float(region[3]))
	body.flip_h = rng.randf() < 0.5
	body.scale = Vector2.ONE * house_scale
	# Sprites are centred on their own centre, so lifting the sprite by half its
	# height lands the art's bottom row (its ground line) on HOUSE_BASELINE.
	body.position = Vector2(0, HOUSE_BASELINE - float(region[3]) * 0.5 * house_scale)
	house.add_child(body)
	var shadow := Polygon2D.new()
	shadow.polygon = PackedVector2Array([
		Vector2(-float(region[2]) * 0.45 * house_scale, HOUSE_BASELINE - 6.0),
		Vector2(float(region[2]) * 0.45 * house_scale, HOUSE_BASELINE - 6.0),
		Vector2(float(region[2]) * 0.36 * house_scale, HOUSE_BASELINE + 12.0),
		Vector2(-float(region[2]) * 0.36 * house_scale, HOUSE_BASELINE + 12.0),
	])
	shadow.color = Color(0.0, 0.0, 0.0, 0.22)
	shadow.z_index = -1
	house.add_child(shadow)
	if index % 3 == 0:
		var lamp := _make_light(Color(1.0, 0.78, 0.44), 0.9, 1.5)
		lamp.position = Vector2(0, HOUSE_BASELINE - float(region[3]) * 0.4 * house_scale)
		house.add_child(lamp)
		_lanterns.append(lamp)
	house.z_index = -5
	add_child(house)


func _build_house(pos: Vector2, roof: Color, rng: RandomNumberGenerator, index: int) -> void:
	## The original procedural house. Kept as the fallback for any biome without
	## facade art (a camp, a new settlement, a build before the art lands) — the
	## menu of a game in progress should not blank a town out.
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
		var entry: Dictionary = NPCController.roster_entry(npc_id)
		if bool(entry.get("at_camp", false)):
			continue   # Elder Rowan, Bram and Kael live at the camp, once
		var npc: NPC = scene.instantiate()
		npc.npc_id = npc_id
		npc.display_name = ""
		# A vendor is whoever data/npcs.json gives a stock list to. The old pair
		# (bram/ysolde) were the only two, and every shop carried one inventory.
		npc.is_vendor = NPCController.is_vendor_id(npc_id) and services.has("shop")
		npc.show_quest_marker = true
		npc.sprite_sheet = _sheet_for(npc_id)
		# Placement: a fixed seat per resident, not a random point on a ring.
		#
		# The old rule picked an angle and a radius of 0.30-0.55x the town radius
		# from the same RNG stream, so two neighbours could land within a few pixels
		# of each other and their schedules (offsets measured from wherever they
		# were dropped) kept them that way — the "everyone is standing inside
		# everyone" report. Each NPC now gets a seat from the table below, with the
		# ring split evenly and the radius alternating between an inner and an outer
		# row, and `_seat_is_clear()` refuses a seat that is closer than
		# NPC_MIN_GAP to anyone already placed (including the camp's fixed trio).
		var seat := _npc_seat(i, ids.size(), radius)
		npc.position = seat
		npc.interacted.connect(func(n: NPC) -> void: npc_interacted.emit(n))
		add_child(npc)


## Two rows of seats so three residents never line up, and a hard floor on the
## distance between any two of them.
const NPC_INNER_ROW := 0.34
const NPC_OUTER_ROW := 0.56
const NPC_MIN_GAP := 118.0


func _npc_seat(index: int, total: int, radius: float) -> Vector2:
	## Even angles, alternating rows, deterministic per index — no RNG involved,
	## so the same town lays out the same way on every machine and a seat can be
	## space-checked before it is used.
	var row := float(index % 2)
	var ring := index / 2
	var rings := maxi(1, int(ceilf(float(total) / 2.0)))
	var a := TAU * (float(ring) / float(rings)) + (0.35 if row > 0.5 else 0.0) + 0.7
	var dist := radius * lerpf(NPC_INNER_ROW, NPC_OUTER_ROW, row)
	var seat := Vector2(cos(a), sin(a)) * dist
	var guard := 0
	while not _seat_is_clear(seat) and guard < 24:
		# Rotate outward in small steps until the seat clears everyone.
		a += 0.42
		dist = minf(dist + 14.0, radius * 0.72)
		seat = Vector2(cos(a), sin(a)) * dist
		guard += 1
	return seat


func _seat_is_clear(seat: Vector2) -> bool:
	## Global space: comparing local positions would make two towns that sit at
	## different world coordinates look like they overlap.
	var world_seat := to_global(seat)
	for other in get_tree().get_nodes_in_group("npc"):
		if not (other is Node2D):
			continue
		if (other as Node2D).global_position.distance_to(world_seat) < NPC_MIN_GAP:
			return false
	return true


func _sheet_for(npc_id: String) -> String:
	## The sheet lives in data/npcs.json next to the schedule, so all eleven named
	## NPCs have their own body instead of three of them having one and the rest
	## falling through to a placeholder sprite.
	var sheet := String(NPCController.roster_entry(npc_id).get("sheet", ""))
	if sheet != "" and not ResourceLoader.exists(sheet):
		push_warning("settlement: missing sheet %s for %s" % [sheet, npc_id])
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
