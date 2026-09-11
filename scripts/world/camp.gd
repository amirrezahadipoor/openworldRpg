class_name Camp
extends Node2D
## The starting camp: firelight, tents, Elder Rowan (quest-giver) and
## Merchant Bram (vendor). Built in code to keep the repo art-light.

signal npc_interacted(npc: NPC)

const NPC_SCENE := "res://scenes/world/npc.tscn"
const MERCHANT_STOCK := ["health_potion", "mana_potion", "leather_armor", "iron_sword"]

var _fire_light: PointLight2D
var _t := 0.0


## Set once Millhaven has burned (MQ020): the camp loses its elder for good and
## the fire is rebuilt as a memorial. Checked on load too, so a save taken after
## the burn does not resurrect him.
var _burned := false


func _ready() -> void:
	_build_scenery()
	_burned = bool(GameState.quest_flags.get("millhaven_burned", false))
	_build_safe_ring()
	_spawn_npcs()
	if _burned:
		_build_memorial()
	# The camp fire is the starting fast-travel waypoint (auto-unlocked at
	# spawn via GameState defaults for new games).
	var wp := Waypoint.new()
	wp.wp_id = "camp"
	wp.wp_name = "Hazelwood Camp"
	wp.position = Vector2(-10, 34)
	add_child(wp)


func _process(delta: float) -> void:
	_t += delta
	if _fire_light:
		_fire_light.energy = 0.9 + 0.15 * sin(_t * 9.0) + 0.08 * sin(_t * 23.0)


func _build_scenery() -> void:
	# Ground patch — real dirt TILES from the atlas rather than a flat brown
	# disc. A 24-gon of solid colour read as a hard-edged mud circle on screen;
	# tiling the dirt tile gives a trodden clearing that matches the world art.
	var ground := Polygon2D.new()
	ground.polygon = _circle_poly(168.0, 48, 15.0)
	ground.texture = load("res://assets/tiles/props/camp_ground.png")
	ground.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	ground.uv = ground.polygon                   # world-pixel UVs -> tiles every 32 px
	ground.color = Color(1, 1, 1, 1)
	ground.z_index = -8
	add_child(ground)

	# Tents
	add_child(_tent(Vector2(-110, -70), Color(0.45, 0.30, 0.22)))
	add_child(_tent(Vector2(95, -95), Color(0.30, 0.38, 0.30)))

	# Campfire
	var stones := Polygon2D.new()
	stones.polygon = _circle_poly(16.0, 10)
	stones.color = Color(0.35, 0.33, 0.32)
	add_child(stones)
	var fire := Polygon2D.new()
	fire.polygon = _circle_poly(9.0, 8)
	fire.color = Color(0.98, 0.55, 0.15)
	add_child(fire)

	_fire_light = PointLight2D.new()
	_fire_light.texture = load("res://assets/placeholder/light.svg")
	_fire_light.color = Color(1.0, 0.72, 0.38)
	_fire_light.energy = 0.85
	_fire_light.texture_scale = 2.6   # was 4.2: a ~270 px glow swallowed the camp
	add_child(_fire_light)


func _tent(pos: Vector2, color: Color) -> Node2D:
	var tent := Node2D.new()
	tent.position = pos
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-42, 26), Vector2(0, -38), Vector2(42, 26),
	])
	body.color = color
	tent.add_child(body)
	var door := Polygon2D.new()
	door.polygon = PackedVector2Array([
		Vector2(-10, 26), Vector2(0, 2), Vector2(10, 26),
	])
	door.color = color.darkened(0.55)
	tent.add_child(door)
	return tent


func burn() -> void:
	## Millhaven burns. data/npcs.json always said Rowan "dies when Millhaven
	## burns", but nothing in the game ever removed him — the player could come
	## back from the ash road and find the mentor standing at a fire that was
	## supposed to have taken him. This is that beat, finally played out.
	if _burned:
		return
	_burned = true
	var elder := get_node_or_null("ElderRowan")
	if elder != null:
		(elder as Node).queue_free()
	_build_memorial()
	for child in get_children():
		if child is PointLight2D:
			(child as PointLight2D).color = Color(0.95, 0.45, 0.25)
	EventBus.camp_burned.emit()


func _build_memorial() -> void:
	## A scorched ring and a stone where the elder stood.
	var stone := Sign.new()
	stone.name = "RowanStone"
	stone.title = "Rowan's Stone"
	stone.text = ("The camp at Millhaven burned while you were on the ash road. "
		+ "Nobody has told the story the same way twice. Someone has scratched a "
		+ "name into the stone and someone else has kept the fire going anyway.")
	stone.position = Vector2(-55, 55)
	add_child(stone)


func _build_safe_ring() -> void:
	## The camp is safe ground (data/settlements.json -> safe_zones) and now says
	## so on the floor, the same way the settlements do.
	var r := 340.0
	for z in Settlement.safe_zones():
		if String((z as Dictionary).get("id", "")) == "camp":
			r = float((z as Dictionary)["radius"])
	var pts := PackedVector2Array()
	for i in 65:
		pts.append(Vector2.from_angle(TAU * float(i) / 64.0) * r)
	var edge := Line2D.new()
	edge.points = pts
	edge.width = 3.0
	edge.default_color = Color(0.95, 0.86, 0.60, 0.30)
	edge.z_index = -6
	add_child(edge)


func _spawn_npcs() -> void:
	var scene: PackedScene = load(NPC_SCENE)
	if _burned:
		return _spawn_npcs_survivors()

	var elder: NPC = scene.instantiate()
	elder.name = "ElderRowan"
	elder.npc_id = "elder_rowan"
	elder.display_name = "Elder Rowan"
	elder.sprite_sheet = "res://assets/lpc/npc_elder.png"
	elder.position = Vector2(-55, 55)
	elder.interacted.connect(func(n: NPC) -> void: npc_interacted.emit(n))
	add_child(elder)

	var vendor: NPC = scene.instantiate()
	vendor.npc_id = "merchant_bram"
	vendor.display_name = "Merchant Bram"
	vendor.is_vendor = true
	vendor.show_quest_marker = false
	vendor.sprite_sheet = "res://assets/lpc/npc_vendor.png"
	vendor.position = Vector2(120, 65)
	vendor.interacted.connect(func(n: NPC) -> void: npc_interacted.emit(n))
	add_child(vendor)

	var kael: NPC = scene.instantiate()
	kael.npc_id = "hunter_kael"
	kael.display_name = "Hunter Kael"
	kael.sprite_sheet = "res://assets/lpc/npc_hunter.png"
	kael.modulate = Color(0.85, 0.95, 0.85)
	kael.position = Vector2(215, 150)
	kael.interacted.connect(func(n: NPC) -> void: npc_interacted.emit(n))
	add_child(kael)


func _spawn_npcs_survivors() -> void:
	## After the burn the camp is a smaller, harder place: the vendor stays
	## because someone has to sell rope, and Kael stays because he never left.
	var scene: PackedScene = load(NPC_SCENE)
	var vendor: NPC = scene.instantiate()
	vendor.npc_id = "merchant_bram"
	vendor.display_name = "Merchant Bram"
	vendor.is_vendor = true
	vendor.show_quest_marker = false
	vendor.sprite_sheet = "res://assets/lpc/npc_vendor.png"
	vendor.position = Vector2(120, 65)
	vendor.interacted.connect(func(n: NPC) -> void: npc_interacted.emit(n))
	add_child(vendor)

	var kael: NPC = scene.instantiate()
	kael.npc_id = "hunter_kael"
	kael.display_name = "Hunter Kael"
	kael.sprite_sheet = "res://assets/lpc/npc_hunter.png"
	kael.modulate = Color(0.85, 0.95, 0.85)
	kael.position = Vector2(215, 150)
	kael.interacted.connect(func(n: NPC) -> void: npc_interacted.emit(n))
	add_child(kael)


func get_vendor_stock() -> Array:
	## data/npcs.json owns the shelf; MERCHANT_STOCK is only the fallback for a
	## build with the data file missing.
	var from_data: Array = NPCController.stock_for("merchant_bram")
	return from_data if not from_data.is_empty() else MERCHANT_STOCK


func _circle_poly(radius: float, sides: int, wobble: float = 0.0) -> PackedVector2Array:
	## `wobble` perturbs each vertex so a clearing reads as an organic trodden
	## patch rather than a perfect disc with a hard-edged rim.
	var pts := PackedVector2Array()
	for i in sides:
		var a := TAU * float(i) / float(sides)
		var r := radius
		if wobble > 0.0:
			r += sin(a * 3.0 + 1.7) * wobble * 0.62 + sin(a * 7.0 + 4.1) * wobble * 0.38
		pts.append(Vector2.from_angle(a) * r)
	return pts
