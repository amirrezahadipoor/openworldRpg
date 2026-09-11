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


func interact_from_ui() -> void:
	## Touch entry point. The on-screen Talk/Use button calls this on the single
	## closest interactable instead of broadcasting an input event, so standing
	## between a chest and a sign cannot trigger both.
	if not player_in_range:
		return
	_on_interact()
	interacted.emit(self)


func interact_label() -> String:
	## The verb the touch button shows for this thing ("Open", "Read", "Pull"...).
	return prompt_text if prompt_text != "" else "Use"


func set_prompt(text: String) -> void:
	prompt_text = text
	if _prompt != null:
		_prompt.text = text


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_range = true
		add_to_group("interactable_in_range")
		if _prompt != null:
			_prompt.visible = true


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_range = false
		remove_from_group("interactable_in_range")
		if _prompt != null:
			_prompt.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if player_in_range and event.is_action_pressed("interact"):
		# Keyboard/gamepad used to act on whichever node happened to be earliest in
		# the scene tree when several were in range, while the touch button picked
		# the closest. Both paths go through the same rule now (audit M1): the
		# closer thing wins, and the loser leaves the event alone.
		if nearest_in_range(get_tree(), _player()) != self:
			return
		_on_interact()
		get_viewport().set_input_as_handled()


func _player() -> Node2D:
	return get_tree().get_first_node_in_group("player") as Node2D


static func nearest_in_range(tree: SceneTree, player) -> Node:
	## The single interactable an interact press should act on, or null.
	##
	## The player parameter is deliberately untyped and validity-checked: screens
	## hold a reference across a scene change, and even an `Object` parameter
	## rejects a *freed* instance at the call boundary ("previously freed" - CI
	## caught it on the commit that introduced this rule).
	if tree == null or not is_instance_valid(player) or not (player is Node2D):
		return null
	var here := (player as Node2D).global_position
	var best: Node = null
	var best_d := INF
	# Membership of the group is the in-range test: NPCs and world interactables add
	# and remove themselves as the player enters and leaves their radius.
	for n in tree.get_nodes_in_group("interactable_in_range"):
		if not (n is Node2D) or not is_instance_valid(n):
			continue
		var d := (n as Node2D).global_position.distance_to(here)
		if d < best_d:
			best_d = d
			best = n
	return best


func _poly(points: PackedVector2Array, color: Color, pos: Vector2 = Vector2.ZERO, z: int = 0) -> Polygon2D:
	var p := Polygon2D.new()
	p.polygon = points
	p.color = color
	p.position = pos
	p.z_index = z
	add_child(p)
	return p
