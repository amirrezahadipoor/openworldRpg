class_name TalentScreen
extends CanvasLayer
## Talent tree UI — 3 branches, tiered nodes (data/talents.json).
## A node becomes active once the player has allocated `tier` points to its
## branch; "Learn" buttons allocate one point to the next locked node.
## Pauses the game while open.

signal closed

var _root: Control
var _points_label: Label
var _branches_box: HBoxContainer
var _data: Dictionary = {}


func _ready() -> void:
	layer = 41
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_load_data()
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("talents") or event.is_action_pressed("pause")):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	_refresh()
	visible = true
	get_tree().paused = true


func close() -> void:
	visible = false
	get_tree().paused = false
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _load_data() -> void:
	var f := FileAccess.open("res://data/talents.json", FileAccess.READ)
	if f == null:
		push_error("TalentScreen: cannot open data/talents.json")
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		_data = parsed


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(960, 540)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.10, 0.09, 0.15, 0.97)
	bg.set_corner_radius_all(12)
	bg.content_margin_left = 26.0
	bg.content_margin_right = 26.0
	bg.content_margin_top = 20.0
	bg.content_margin_bottom = 20.0
	panel.add_theme_stylebox_override("panel", bg)
	center.add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	panel.add_child(outer)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "TALENTS"
	title.add_theme_font_size_override("font_size", 26)
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_points_label = Label.new()
	_points_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	_points_label.add_theme_font_size_override("font_size", 18)
	header.add_child(_points_label)
	outer.add_child(header)

	_branches_box = HBoxContainer.new()
	_branches_box.add_theme_constant_override("separation", 18)
	_branches_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_branches_box)

	var close_btn := Button.new()
	close_btn.text = "Close (T)"
	close_btn.custom_minimum_size = Vector2(200, 42)
	close_btn.pressed.connect(close)
	outer.add_child(close_btn)


func _refresh() -> void:
	_points_label.text = "Points: %d" % GameState.talent_points
	for child in _branches_box.get_children():
		child.queue_free()
	for branch in _data.get("branches", []):
		_branches_box.add_child(_branch_column(branch))


func _branch_column(branch: Dictionary) -> Control:
	var bid := String(branch.get("id", ""))
	var col := PanelContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cbg := StyleBoxFlat.new()
	cbg.bg_color = Color(1, 1, 1, 0.04)
	cbg.set_corner_radius_all(8)
	cbg.content_margin_left = 14.0
	cbg.content_margin_right = 14.0
	cbg.content_margin_top = 12.0
	cbg.content_margin_bottom = 12.0
	col.add_theme_stylebox_override("panel", cbg)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	col.add_child(vbox)

	var name_label := Label.new()
	name_label.text = String(branch.get("name", bid))
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)

	var desc := Label.new()
	desc.text = String(branch.get("desc", ""))
	desc.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	desc.add_theme_font_size_override("font_size", 13)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc)

	var pts := int(GameState.talents.get(bid, 0))
	for node in branch.get("nodes", []):
		vbox.add_child(_node_row(bid, node, pts))
	return col


func _node_row(bid: String, node: Dictionary, branch_points: int) -> Control:
	var tier := int(node.get("tier", 1))
	var active := branch_points >= tier
	var is_next := branch_points == tier - 1

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var nbg := StyleBoxFlat.new()
	nbg.bg_color = Color(0.35, 0.55, 0.35, 0.25) if active else Color(1, 1, 1, 0.03)
	nbg.set_corner_radius_all(6)
	nbg.content_margin_left = 10.0
	nbg.content_margin_right = 10.0
	nbg.content_margin_top = 8.0
	nbg.content_margin_bottom = 8.0
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", nbg)
	box.add_child(panel)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 3)
	panel.add_child(inner)

	var head := HBoxContainer.new()
	var nm := Label.new()
	nm.text = "%s" % String(node.get("name", ""))
	nm.add_theme_font_size_override("font_size", 15)
	nm.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8) if active else Color(1, 1, 1, 0.8))
	head.add_child(nm)
	inner.add_child(head)

	var dsc := Label.new()
	dsc.text = String(node.get("desc", ""))
	dsc.add_theme_font_size_override("font_size", 12)
	dsc.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	dsc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(dsc)

	if active:
		var status := Label.new()
		status.text = "✓ Active"
		status.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
		status.add_theme_font_size_override("font_size", 12)
		inner.add_child(status)
	elif is_next and GameState.talent_points > 0:
		var learn := Button.new()
		learn.text = "Learn (1 point)"
		learn.pressed.connect(func() -> void:
			GameState.spend_talent(bid)
			_refresh()
		)
		inner.add_child(learn)
	else:
		var lock := Label.new()
		lock.text = "Locked" if not is_next else "Need a point"
		lock.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
		lock.add_theme_font_size_override("font_size", 12)
		inner.add_child(lock)
	return box
