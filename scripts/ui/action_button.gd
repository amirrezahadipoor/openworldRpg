class_name ActionButton
extends TextureButton
## Touch button that drives a named Godot Input action (press on touch-down,
## release on touch-up), so gameplay code uses one unified input path for
## keyboard and touch.

var action_name := ""


func setup(p_action: String, icon: Texture2D, btn_size: float = 88.0) -> void:
	action_name = p_action
	texture_normal = icon
	custom_minimum_size = Vector2(btn_size, btn_size)
	ignore_texture_size = true
	stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	modulate = Color(1, 1, 1, 0.85)
	focus_mode = Control.FOCUS_NONE


func _ready() -> void:
	button_down.connect(_on_down)
	button_up.connect(_on_up)


func _on_down() -> void:
	if action_name != "":
		Input.action_press(action_name)


func _on_up() -> void:
	if action_name != "":
		Input.action_release(action_name)
