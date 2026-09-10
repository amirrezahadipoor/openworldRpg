class_name WorldInteractable
extends Area2D
## Base class for world interactables (chests, signs, levers, waypoints).
## Detects the player via body overlap; consumes the "interact" action.

signal interacted(node: Node)

@export var prompt_text := "Interact"
@export var interact_radius := 64.0

var player_in_range := false
var _prompt: Label


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	var cs := CollisionShape2D.new()
	var circ := CircleShape2D.new()
	circ.radius = interact_radius
	cs.shape = circ
	add_child(cs)
	_build_visual()
	_prompt = Label.new()
	_prompt.text = prompt_text
	_prompt.custom_minimum_size = Vector2(160, 0)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.position = Vector2(-80, -84)
	_prompt.add_theme_font_size_override("font_size", 13)
	_prompt.add_theme_color_override("font_color", Color(1, 1, 0.85, 0.95))
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_prompt.add_theme_constant_override("outline_size", 4)
	_prompt.visible = false
	add_child(_prompt)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _build_visual() -> void:
	pass


func _on_interact() -> void:
	pass


func set_prompt(text: String) -> void:
	prompt_text = text
	if _prompt != null:
		_prompt.text = text


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_range = true
		if _prompt != null:
			_prompt.visible = true


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_range = false
		if _prompt != null:
			_prompt.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if player_in_range and event.is_action_pressed("interact"):
		_on_interact()
		get_viewport().set_input_as_handled()


func _poly(points: PackedVector2Array, color: Color, pos: Vector2 = Vector2.ZERO, z: int = 0) -> Polygon2D:
	var p := Polygon2D.new()
	p.polygon = points
	p.color = color
	p.position = pos
	p.z_index = z
	add_child(p)
	return p
