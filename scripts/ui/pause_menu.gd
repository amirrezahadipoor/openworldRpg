class_name PauseMenu
extends CanvasLayer
## Pause overlay: resume / save / restart-from-save.
## Stays interactive while the tree is paused (PROCESS_MODE_ALWAYS).

var player: Node2D

var _root: Control
var _status: Label


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	visible = not visible
	get_tree().paused = visible
	_status.text = ""


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.12, 0.16, 0.95)
	bg.set_corner_radius_all(12)
	bg.content_margin_left = 40.0
	bg.content_margin_right = 40.0
	bg.content_margin_top = 24.0
	bg.content_margin_bottom = 24.0
	panel.add_theme_stylebox_override("panel", bg)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)

	box.add_child(_button("Resume", func() -> void: toggle()))
	box.add_child(_button("Save Game", func() -> void: _save()))
	box.add_child(_button("Quit to Last Save", func() -> void: _quit_to_save()))

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	box.add_child(_status)


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(260, 44)
	b.pressed.connect(cb)
	return b


func _save() -> void:
	if player != null and SaveSystem.save_game(player):
		_status.text = "Saved ✓"
	else:
		_status.text = "Save failed!"


func _quit_to_save() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")
