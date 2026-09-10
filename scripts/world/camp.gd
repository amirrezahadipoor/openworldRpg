class_name Camp
extends Node2D
## The starting camp: firelight, tents, Elder Rowan (quest-giver) and
## Merchant Bram (vendor). Built in code to keep the repo art-light.

signal npc_interacted(npc: NPC)

const NPC_SCENE := "res://scenes/world/npc.tscn"
const MERCHANT_STOCK := ["health_potion", "mana_potion", "leather_armor", "iron_sword"]

var _fire_light: PointLight2D
var _t := 0.0


func _ready() -> void:
	_build_scenery()
	_spawn_npcs()


func _process(delta: float) -> void:
	_t += delta
	if _fire_light:
		_fire_light.energy = 0.9 + 0.15 * sin(_t * 9.0) + 0.08 * sin(_t * 23.0)


func _build_scenery() -> void:
	# Ground patch
	var ground := Polygon2D.new()
	ground.polygon = _circle_poly(170.0, 24)
	ground.color = Color(0.30, 0.26, 0.20, 0.9)
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
	_fire_light.energy = 1.0
	_fire_light.texture_scale = 4.2
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


func _spawn_npcs() -> void:
	var scene: PackedScene = load(NPC_SCENE)

	var elder: NPC = scene.instantiate()
	elder.npc_id = "elder_rowan"
	elder.display_name = "Elder Rowan"
	elder.position = Vector2(-55, 55)
	elder.interacted.connect(func(n: NPC) -> void: npc_interacted.emit(n))
	add_child(elder)

	var vendor: NPC = scene.instantiate()
	vendor.npc_id = "merchant_bram"
	vendor.display_name = "Merchant Bram"
	vendor.is_vendor = true
	vendor.show_quest_marker = false
	(vendor.get_node("Sprite") as Sprite2D).texture = load("res://assets/placeholder/vendor.svg")
	vendor.position = Vector2(120, 65)
	vendor.interacted.connect(func(n: NPC) -> void: npc_interacted.emit(n))
	add_child(vendor)

	var kael: NPC = scene.instantiate()
	kael.npc_id = "hunter_kael"
	kael.display_name = "Hunter Kael"
	kael.modulate = Color(0.85, 0.95, 0.85)
	kael.position = Vector2(215, 150)
	kael.interacted.connect(func(n: NPC) -> void: npc_interacted.emit(n))
	add_child(kael)


func get_vendor_stock() -> Array:
	return MERCHANT_STOCK


func _circle_poly(radius: float, sides: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in sides:
		var a := TAU * float(i) / float(sides)
		pts.append(Vector2.from_angle(a) * radius)
	return pts
