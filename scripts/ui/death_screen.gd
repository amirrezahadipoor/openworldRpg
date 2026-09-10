class_name DeathScreen
extends CanvasLayer
## Death / game-over overlay: respawn, load last save, or quit to title.

signal respawn_requested
signal load_last_requested
signal quit_title_requested

var _root: Control


func _ready() -> void:
	layer = 65
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func show_death() -> void:
	visible = true
	get_tree().paused = true


func _hide_screen() -> void:
	visible = false
	get_tree().paused = false


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.10, 0.02, 0.02, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)

	var title := Label.new()
	title.text = "YOU DIED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(0.95, 0.25, 0.2))
	box.add_child(title)

	var hint := Label.new()
	hint.text = "The road is long, but it does not end here."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	box.add_child(hint)

	box.add_child(_btn("Respawn at Camp", func() -> void:
		_hide_screen()
		respawn_requested.emit()
	))
	box.add_child(_btn("Load Last Save", func() -> void:
		_hide_screen()
		load_last_requested.emit()
	))
	box.add_child(_btn("Quit to Title", func() -> void:
		_hide_screen()
		quit_title_requested.emit()
	))


func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 48)
	b.pressed.connect(func() -> void: AudioManager.play_sfx("ui_click"))
	b.pressed.connect(cb)
	return b
