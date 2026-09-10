class_name SettingsScreen
extends CanvasLayer
## Settings menu: music/SFX volume, joystick size, large-text accessibility.
## Everything on this screen does something: the language dropdown that always
## saved "en" and the control-scale slider that changed nothing are gone.
## Persists via SettingsManager and applies live.

signal closed

var _root: Control
var _music_slider: HSlider
var _sfx_slider: HSlider
var _scale_slider: HSlider
var _lang_option: OptionButton
var _large_text_check: CheckButton


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()


var _was_paused := false


func open() -> void:
	_load_into_ui()
	_was_paused = get_tree().paused
	visible = true
	get_tree().paused = true


func close() -> void:
	visible = false
	get_tree().paused = _was_paused  # keep pause menu paused if opened from it
	closed.emit()


func _load_into_ui() -> void:
	_music_slider.value = SettingsManager.music_volume
	_sfx_slider.value = SettingsManager.sfx_volume
	_scale_slider.value = SettingsManager.joystick_scale
	if _large_text_check != null:
		_large_text_check.button_pressed = SettingsManager.large_text


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
	panel.custom_minimum_size = Vector2(520, 420)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.09, 0.11, 0.15, 0.97)
	bg.set_corner_radius_all(12)
	bg.content_margin_left = 30.0
	bg.content_margin_right = 30.0
	bg.content_margin_top = 24.0
	bg.content_margin_bottom = 24.0
	panel.add_theme_stylebox_override("panel", bg)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)

	box.add_child(_slider_row("Music Volume", func(s: HSlider) -> void: _music_slider = s))
	box.add_child(_slider_row("SFX Volume", func(s: HSlider) -> void: _sfx_slider = s))
	box.add_child(_slider_row("Joystick Size", func(s: HSlider) -> void: _scale_slider = s))
	_scale_slider.tooltip_text = "Scales the on-screen stick. Applied live."

	# This used to be a live dropdown that silently saved "en" whatever you
	# picked, next to a "Control Size" slider that changed nothing. A setting that
	# lies is worse than no setting, so what is shipped is stated plainly.
	var lang_row := HBoxContainer.new()
	var lang_label := Label.new()
	lang_label.text = "Language"
	lang_label.custom_minimum_size = Vector2(180, 0)
	lang_row.add_child(lang_label)
	var lang_value := Label.new()
	lang_value.text = "English (the only language in this build)"
	lang_value.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	lang_row.add_child(lang_value)
	box.add_child(lang_row)

	# Accessibility: works, and is applied immediately.
	var big_row := HBoxContainer.new()
	var big_label := Label.new()
	big_label.text = "Large text"
	big_label.custom_minimum_size = Vector2(180, 0)
	big_row.add_child(big_label)
	_large_text_check = CheckButton.new()
	_large_text_check.button_pressed = SettingsManager.large_text
	_large_text_check.toggled.connect(func(on: bool) -> void:
		SettingsManager.large_text = on
		SettingsManager.apply_text_scale(get_tree().root)
	)
	big_row.add_child(_large_text_check)
	box.add_child(big_row)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	var apply_btn := Button.new()
	apply_btn.text = "Apply & Close"
	apply_btn.custom_minimum_size = Vector2(200, 44)
	apply_btn.pressed.connect(func() -> void: AudioManager.play_sfx("ui_click"))
	apply_btn.pressed.connect(_apply_and_close)
	btns.add_child(apply_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(140, 44)
	cancel_btn.pressed.connect(func() -> void: AudioManager.play_sfx("ui_click"))
	cancel_btn.pressed.connect(close)
	btns.add_child(cancel_btn)
	box.add_child(btns)


func _slider_row(label_text: String, store: Callable) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(180, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = 1.0
	slider.custom_minimum_size = Vector2(220, 0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	store.call(slider)
	return row


func _apply_and_close() -> void:
	SettingsManager.music_volume = _music_slider.value
	SettingsManager.sfx_volume = _sfx_slider.value
	SettingsManager.joystick_scale = _scale_slider.value
	SettingsManager.apply()
	SettingsManager.save_settings()
	close()
