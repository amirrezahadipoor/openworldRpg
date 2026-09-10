class_name HUD
extends CanvasLayer
## In-game HUD: HP/MP bars, XP/gold readout, quest tracker, minimap
## placeholder, virtual joystick + action buttons.
## Fully anchor-based with safe-area offsets (DECISIONS.md #2) — scales from
## 720p phones to 1440p+ tablets and 16:9 → 20:9 aspects.

signal bag_pressed
signal talents_pressed

var player: Player

var hp_bar: ProgressBar
var mp_bar: ProgressBar
var info_label: Label
var quest_label: Label
var joystick: VirtualJoystick


func setup(p: Player) -> void:
	player = p
	_build_top_left()
	_build_top_right()
	_build_touch_controls()
	if player != null:
		player.external_input = Vector2.ZERO


func _process(_delta: float) -> void:
	if hp_bar != null:
		hp_bar.max_value = GameState.max_hp()
		hp_bar.value = GameState.hp
		mp_bar.max_value = GameState.max_mp()
		mp_bar.value = GameState.mp
		info_label.text = "Lv %d · XP %d/%d · %d gold" % [
			GameState.level, GameState.xp, GameState.xp_to_next(), GameState.gold
		]


# --- Builders -----------------------------------------------------------------

func _safe_margins() -> Vector2:
	var safe := DisplayServer.get_display_safe_area()
	var win := Vector2(DisplayServer.window_get_size())
	return Vector2(maxi(safe.position.x, 0), maxi(safe.position.y, 0)).limit_length(64.0)


func _make_bar(fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(230, 15)
	bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.08, 0.10, 0.8)
	bg.set_corner_radius_all(4)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill_color
	fg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	return bar


func _build_top_left() -> void:
	var m := _safe_margins()
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	box.position = Vector2(16, 12) + m
	box.add_theme_constant_override("separation", 4)

	hp_bar = _make_bar(Color(0.78, 0.2, 0.22))
	mp_bar = _make_bar(Color(0.22, 0.42, 0.8))
	info_label = Label.new()
	info_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	info_label.add_theme_font_size_override("font_size", 14)

	box.add_child(hp_bar)
	box.add_child(mp_bar)
	box.add_child(info_label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	var bag := TextureButton.new()
	bag.texture_normal = _load_icon("icon_bag")
	bag.custom_minimum_size = Vector2(46, 46)
	bag.ignore_texture_size = true
	bag.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	bag.modulate = Color(1, 1, 1, 0.85)
	bag.pressed.connect(func() -> void: bag_pressed.emit())
	var star := TextureButton.new()
	star.texture_normal = _load_icon("icon_talent")
	star.custom_minimum_size = Vector2(46, 46)
	star.ignore_texture_size = true
	star.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	star.modulate = Color(1, 1, 1, 0.85)
	star.pressed.connect(func() -> void: talents_pressed.emit())
	btn_row.add_child(bag)
	btn_row.add_child(star)
	box.add_child(btn_row)

	add_child(box)


func _build_top_right() -> void:
	var m := _safe_margins()
	quest_label = Label.new()
	quest_label.text = "No active quests"
	quest_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quest_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quest_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	quest_label.add_theme_font_size_override("font_size", 14)
	quest_label.anchor_left = 1.0
	quest_label.anchor_right = 1.0
	quest_label.offset_left = -340.0 - m.x
	quest_label.offset_top = 12.0 + m.y
	quest_label.offset_right = -16.0 - m.x
	quest_label.offset_bottom = 130.0
	add_child(quest_label)

	var minimap := Panel.new()
	var mm_bg := StyleBoxFlat.new()
	mm_bg.bg_color = Color(0.05, 0.06, 0.08, 0.6)
	mm_bg.set_corner_radius_all(6)
	minimap.add_theme_stylebox_override("panel", mm_bg)
	minimap.custom_minimum_size = Vector2(130, 130)
	minimap.anchor_left = 1.0
	minimap.anchor_right = 1.0
	minimap.offset_left = -146.0 - m.x
	minimap.offset_top = 64.0 + m.y
	minimap.offset_right = -16.0 - m.x
	minimap.offset_bottom = 194.0 + m.y
	add_child(minimap)

	var mm_label := Label.new()
	mm_label.text = "minimap\n(phase 10)"
	mm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mm_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
	mm_label.add_theme_font_size_override("font_size", 12)
	mm_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	mm_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	minimap.add_child(mm_label)


func _build_touch_controls() -> void:
	var m := _safe_margins()

	joystick = VirtualJoystick.new()
	joystick.size = Vector2(210, 210)
	joystick.anchor_top = 1.0
	joystick.anchor_bottom = 1.0
	joystick.offset_left = 20.0 + m.x
	joystick.offset_top = -230.0 - m.y
	joystick.offset_right = 230.0 + m.x
	joystick.offset_bottom = -20.0 - m.y
	if player != null:
		joystick.vector_changed.connect(func(v: Vector2) -> void: player.external_input = v)
	add_child(joystick)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 18)
	buttons.anchor_left = 1.0
	buttons.anchor_right = 1.0
	buttons.anchor_top = 1.0
	buttons.anchor_bottom = 1.0
	buttons.offset_left = -320.0 - m.x
	buttons.offset_top = -130.0 - m.y
	buttons.offset_right = -20.0 - m.x
	buttons.offset_bottom = -20.0 - m.y
	buttons.alignment = BoxContainer.ALIGNMENT_END

	var dodge := ActionButton.new()
	dodge.setup("dodge", _load_icon("icon_dodge"), 74.0)
	var interact_btn := ActionButton.new()
	interact_btn.setup("interact", _load_icon("icon_interact"), 74.0)
	var attack := ActionButton.new()
	attack.setup("attack", _load_icon("icon_attack"), 104.0)

	buttons.add_child(dodge)
	buttons.add_child(interact_btn)
	buttons.add_child(attack)
	add_child(buttons)


func _load_icon(n: String) -> Texture2D:
	var path := "res://assets/placeholder/%s.svg" % n
	if ResourceLoader.exists(path):
		return load(path)
	return null


func set_quest_text(text: String) -> void:
	if quest_label != null:
		quest_label.text = text
