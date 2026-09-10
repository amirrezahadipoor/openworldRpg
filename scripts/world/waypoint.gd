class_name Waypoint
extends WorldInteractable
## Fast-travel campfire. Lighting it registers it as unlocked (persistent via
## GameState.quest_flags "wp_<id>"). Positions register in a static registry
## so the travel UI can list them even when their chunk is unloaded.

@export var wp_id := "wp"
@export var wp_name := "Campfire"

static var registry: Dictionary = {}
static var names: Dictionary = {}

var _fire: Polygon2D
var _light: PointLight2D


func _flag_key() -> String:
	return "wp_%s" % wp_id


func is_unlocked() -> bool:
	return bool(GameState.quest_flags.get(_flag_key(), false))


func _ready() -> void:
	prompt_text = "Rest & Travel" if is_unlocked() else "Light campfire"
	super._ready()
	registry[wp_id] = global_position
	names[wp_id] = wp_name


func _build_visual() -> void:
	var stones := PackedVector2Array()
	for k in 8:
		var a := TAU * float(k) / 8.0
		stones.append(Vector2(cos(a), sin(a)) * 15.0)
	_poly(stones, Color(0.35, 0.33, 0.32, 0.9))
	_fire = Polygon2D.new()
	var flame := PackedVector2Array()
	for k in 6:
		var a := TAU * float(k) / 6.0
		flame.append(Vector2(cos(a), sin(a)) * 8.0)
	_fire.polygon = flame
	add_child(_fire)
	_light = PointLight2D.new()
	_light.texture = load("res://assets/placeholder/light.svg")
	_light.color = Color(1.0, 0.72, 0.38)
	_light.texture_scale = 3.4
	add_child(_light)
	_refresh_visual()


func _refresh_visual() -> void:
	if _fire == null or _light == null:
		return
	if is_unlocked():
		_fire.color = Color(0.98, 0.55, 0.15)
		_light.energy = 0.9
	else:
		_fire.color = Color(0.25, 0.23, 0.22)
		_light.energy = 0.0


func _on_interact() -> void:
	if not is_unlocked():
		GameState.quest_flags[_flag_key()] = true
		AudioManager.play_sfx("level_up")
		EventBus.interactable_used.emit(self)
		_refresh_visual()
		set_prompt("Rest & Travel")
	EventBus.world_interacted.emit(self)
