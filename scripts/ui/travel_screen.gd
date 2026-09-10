class_name TravelScreen
extends CanvasLayer
## Fast-travel UI: lists lit campfires (Waypoint.registry ∩ quest_flags).
## Opened by interacting with any waypoint; choosing one emits travel_to.

signal travel_to(wp_id: String)

var _root: Control
var _list: VBoxContainer
var _title: Label
var _empty: Label
var _current_id := ""
var _was_paused := false


func _ready() -> void:
	layer = 42
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	_root.add_child(dim)

	var panel := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.11, 0.97)
	sb.border_color = Color(0.85, 0.62, 0.3, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 22.0
	sb.content_margin_right = 22.0
	sb.content_margin_top = 16.0
	sb.content_margin_bottom = 16.0
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(420, 0)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	_title = Label.new()
	_title.text = "Fast Travel — Lit Campfires"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", Color(1, 0.86, 0.6))
	vbox.add_child(_title)

	_empty = Label.new()
	_empty.text = "No other campfires are lit yet.\nExplore the world and light them."
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	_empty.visible = false
	vbox.add_child(_empty)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	vbox.add_child(_list)

	var cancel := Button.new()
	cancel.text = "Stay here"
	cancel.custom_minimum_size = Vector2(200, 42)
	cancel.pressed.connect(func() -> void:
		AudioManager.play_sfx("ui_click")
		close()
	)
	vbox.add_child(cancel)


func open(current_wp_id: String) -> void:
	_current_id = current_wp_id
	_was_paused = get_tree().paused
	get_tree().paused = true
	_rebuild()
	visible = true


func _rebuild() -> void:
	for child in _list.get_children():
		child.queue_free()
	var options := 0
	for wp_id in Waypoint.registry.keys():
		if not bool(GameState.quest_flags.get("wp_%s" % wp_id, false)):
			continue
		if String(wp_id) == _current_id:
			continue
		options += 1
		var b := Button.new()
		b.text = _name_of(wp_id)
		b.custom_minimum_size = Vector2(380, 44)
		b.pressed.connect(func() -> void:
			AudioManager.play_sfx("ui_click")
			var chosen := String(wp_id)
			close()
			travel_to.emit(chosen)
		)
		_list.add_child(b)
	_empty.visible = options == 0


func _name_of(wp_id: String) -> String:
	# Waypoint instances keep their display name in a static table.
	return Waypoint.names.get(wp_id, String(wp_id))


func close() -> void:
	visible = false
	get_tree().paused = _was_paused
