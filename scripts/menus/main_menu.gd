extends Node
## Main menu: Continue / New Game (3 save slots), Settings, Credits.
## Entry point of the game (project.godot main scene).

const GAME_SCENE := "res://scenes/main.tscn"

var _slot_picker: Control
var _slot_mode := "continue"
var _settings_ui: SettingsScreen
var _credits_layer: CanvasLayer
var _continue_btn: Button
var _confirm_box: VBoxContainer
var _confirm_layer: CanvasLayer


func _ready() -> void:
	randomize()
	_build_background()
	_build_buttons()
	_build_slot_picker()
	_build_confirm()
	_settings_ui = SettingsScreen.new()
	add_child(_settings_ui)
	_build_credits()


# --- Background -----------------------------------------------------------------

func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Decorative hills
	var hills := Polygon2D.new()
	hills.polygon = PackedVector2Array([
		Vector2(0, 500), Vector2(220, 380), Vector2(480, 520), Vector2(760, 400),
		Vector2(1040, 540), Vector2(1280, 430), Vector2(1280, 720), Vector2(0, 720),
	])
	hills.color = Color(0.10, 0.14, 0.13)
	add_child(hills)

	var hills2 := Polygon2D.new()
	hills2.polygon = PackedVector2Array([
		Vector2(0, 590), Vector2(300, 500), Vector2(640, 610), Vector2(980, 520),
		Vector2(1280, 600), Vector2(1280, 720), Vector2(0, 720),
	])
	hills2.color = Color(0.07, 0.10, 0.09)
	add_child(hills2)

	# Campfire glow
	var light := PointLight2D.new()
	light.texture = load("res://assets/placeholder/light.svg")
	light.color = Color(1.0, 0.7, 0.35)
	light.energy = 1.4
	light.texture_scale = 3.0
	light.position = Vector2(1080, 560)
	add_child(light)
	var fire := Polygon2D.new()
	fire.polygon = PackedVector2Array([Vector2(-8, 6), Vector2(0, -12), Vector2(8, 6)])
	fire.color = Color(0.98, 0.55, 0.15)
	fire.position = Vector2(1080, 560)
	add_child(fire)


# --- Buttons --------------------------------------------------------------------

func _build_buttons() -> void:
	var title := Label.new()
	title.text = "OPENWORLD RPG"
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(0.98, 0.87, 0.55))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	title.add_theme_constant_override("outline_size", 8)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0
	title.anchor_right = 1.0
	title.offset_top = 60.0
	title.offset_bottom = 140.0
	add_child(title)

	var subtitle := Label.new()
	subtitle.text = "A tale of embers, mercy and the open road"
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.anchor_left = 0.0
	subtitle.anchor_right = 1.0
	subtitle.offset_top = 138.0
	subtitle.offset_bottom = 168.0
	add_child(subtitle)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.42
	box.anchor_bottom = 0.42
	box.offset_left = -160.0
	box.offset_right = 160.0
	add_child(box)

	_continue_btn = _menu_button("Continue", _on_continue)
	box.add_child(_continue_btn)
	box.add_child(_menu_button("New Game", _on_new_game))
	box.add_child(_menu_button("Settings", func() -> void: _settings_ui.open()))
	box.add_child(_menu_button("Credits", _on_credits))

	var version := Label.new()
	version.text = "v0.1.0 — Godot 4.4 · %d slots" % SaveSystem.SLOT_COUNT
	version.add_theme_font_size_override("font_size", 13)
	version.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
	version.anchor_left = 0.0
	version.anchor_right = 1.0
	version.anchor_top = 1.0
	version.anchor_bottom = 1.0
	version.offset_top = -28.0
	version.offset_bottom = -8.0
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(version)

	_refresh_continue()


func _refresh_continue() -> void:
	var any_save := false
	for s in SaveSystem.SLOT_COUNT:
		if SaveSystem.has_save(s + 1):
			any_save = true
			break
	_continue_btn.disabled = not any_save


func _menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 50)
	b.pressed.connect(cb)
	return b


# --- Slot picker ------------------------------------------------------------------

func _on_continue() -> void:
	_slot_mode = "continue"
	_refresh_slot_picker()
	_slot_picker.visible = true


func _on_new_game() -> void:
	_slot_mode = "new"
	_refresh_slot_picker()
	_slot_picker.visible = true


func _build_slot_picker() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	_slot_picker = Control.new()
	_slot_picker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_slot_picker.visible = false
	layer.add_child(_slot_picker)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_slot_picker.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_slot_picker.add_child(center)

	var panel := PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.10, 0.12, 0.16, 0.97)
	bg.set_corner_radius_all(12)
	bg.content_margin_left = 30.0
	bg.content_margin_right = 30.0
	bg.content_margin_top = 20.0
	bg.content_margin_bottom = 20.0
	panel.add_theme_stylebox_override("panel", bg)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.name = "SlotBox"
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)


func _build_confirm() -> void:
	_confirm_layer = CanvasLayer.new()
	_confirm_layer.layer = 30
	add_child(_confirm_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.10, 0.10, 0.97)
	bg.set_corner_radius_all(12)
	bg.content_margin_left = 30.0
	bg.content_margin_right = 30.0
	bg.content_margin_top = 22.0
	bg.content_margin_bottom = 22.0
	panel.add_theme_stylebox_override("panel", bg)
	center.add_child(panel)

	_confirm_box = VBoxContainer.new()
	_confirm_box.add_theme_constant_override("separation", 16)
	panel.add_child(_confirm_box)

	_confirm_layer.visible = false


func _refresh_slot_picker() -> void:
	var box: VBoxContainer = _slot_picker.find_child("SlotBox", true, false)
	for child in box.get_children():
		child.queue_free()

	var title := Label.new()
	title.text = "Choose a save slot" if _slot_mode == "continue" else "Start a new adventure"
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)

	for s in SaveSystem.SLOT_COUNT:
		var slot := s + 1
		var summary := SaveSystem.slot_summary(slot)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(360, 46)
		if bool(summary.get("exists", false)):
			btn.text = "Slot %d — Lv %d · %d gold" % [slot, int(summary["level"]), int(summary["gold"])]
		else:
			btn.text = "Slot %d — empty" % slot
		btn.pressed.connect(_on_slot_chosen.bind(slot))
		row.add_child(btn)
		box.add_child(row)

	var cancel := Button.new()
	cancel.text = "Back"
	cancel.custom_minimum_size = Vector2(200, 42)
	cancel.pressed.connect(func() -> void: _slot_picker.visible = false)
	box.add_child(cancel)


func _on_slot_chosen(slot: int) -> void:
	if _slot_mode == "continue":
		if not SaveSystem.has_save(slot):
			return
		GameState.current_slot = slot
		GameState.pending_load = true
		get_tree().change_scene_to_file(GAME_SCENE)
	else:
		if SaveSystem.has_save(slot):
			_show_overwrite_confirm(slot)
		else:
			_start_new_game(slot)


func _start_new_game(slot: int) -> void:
	GameState.current_slot = slot
	GameState.reset()
	GameState.pending_load = false
	get_tree().change_scene_to_file(GAME_SCENE)


func _show_overwrite_confirm(slot: int) -> void:
	_slot_picker.visible = false
	for child in _confirm_box.get_children():
		child.queue_free()
	var msg := Label.new()
	msg.text = "Slot %d already has a hero (Lv %d).\nOverwrite it? This cannot be undone." % [
		slot, int(SaveSystem.slot_summary(slot).get("level", 1))
	]
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_theme_font_size_override("font_size", 17)
	_confirm_box.add_child(msg)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var yes := Button.new()
	yes.text = "Overwrite"
	yes.custom_minimum_size = Vector2(180, 44)
	yes.pressed.connect(func() -> void:
		_confirm_layer.visible = false
		_start_new_game(slot)
	)
	var no := Button.new()
	no.text = "Cancel"
	no.custom_minimum_size = Vector2(180, 44)
	no.pressed.connect(func() -> void:
		_confirm_layer.visible = false
		_slot_picker.visible = true
	)
	row.add_child(yes)
	row.add_child(no)
	_confirm_box.add_child(row)
	_confirm_layer.visible = true


# --- Credits ---------------------------------------------------------------------

func _build_credits() -> void:
	_credits_layer = CanvasLayer.new()
	_credits_layer.layer = 25
	add_child(_credits_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	_credits_layer.add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.09, 0.10, 0.14, 0.97)
	bg.set_corner_radius_all(12)
	bg.content_margin_left = 30.0
	bg.content_margin_right = 30.0
	bg.content_margin_top = 22.0
	bg.content_margin_bottom = 22.0
	panel.add_theme_stylebox_override("panel", bg)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var text := Label.new()
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(640, 0)
	text.add_theme_font_size_override("font_size", 15)
	text.text = """Engine: Godot 4.4 (MIT)
Placeholder art: this project (MIT/CC0) — LPC & 0x72 CC0 art integrate later
Tooling: Tiled (GPL, authoring), Pixelorama (MIT, authoring),
Universal LPC Generator (GPL), crunch (zlib)
Audio: CC0 sources, logged in CREDITS.md
Made with ❤ and GitHub Actions — see CREDITS.md for the full license list."""
	box.add_child(text)

	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(200, 42)
	close.pressed.connect(func() -> void: root.visible = false)
	box.add_child(close)


func _on_credits() -> void:
	_credits_layer.get_child(0).visible = true
