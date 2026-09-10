extends Node
## SettingsManager — persisted user settings (user://settings.json).
## Language is a stub (English-only build per DECISIONS #4).

const SETTINGS_PATH := "user://settings.json"
const THEME_PATH := "res://ui/theme.tres"

var music_volume := 1.0
var sfx_volume := 1.0
var joystick_scale := 1.0
var language := "en"
## Accessibility: +4px on every UI text size, for phones and for anyone who does
## not want to read a quest log at 12px. Applied to the whole tree at runtime.
var large_text := false
const LARGE_TEXT_BONUS := 4
const BASE_FONT_SIZE := 14          # nothing in the UI ships below this now

signal ui_scale_changed


func _ready() -> void:
	# Project-wide themed look (Phase 10 polish). Applied from code so the
	# theme resource never blocks the very first import pass.
	var t := load(THEME_PATH)
	if t is Theme:
		get_tree().root.theme = t
	load_settings()
	apply()


func apply() -> void:
	AudioManager.set_music_volume(music_volume)
	AudioManager.set_sfx_volume(sfx_volume)
	ui_scale_changed.emit()


func apply_text_scale(root: Node) -> void:
	## Walk the UI and re-size every text node. Theme overrides beat the theme,
	## so this edits the overrides the screens set — and covers nodes built later
	## if it is called again (main.gd calls it after building the HUD).
	var bonus := LARGE_TEXT_BONUS if large_text else 0
	_bump(root, bonus)


func _bump(node: Node, bonus: int) -> void:
	if node is Label or node is Button or node is RichTextLabel or node is OptionButton or node is LineEdit:
		var c := node as Control
		var key := "normal_font_size" if node is RichTextLabel else "font_size"
		var base := int(c.get_theme_font_size(key))
		var eff := int(c.get_theme_font_size(key)) - LARGE_TEXT_BONUS
		if eff <= 0:
			eff = BASE_FONT_SIZE
		c.add_theme_font_size_override(key, eff + bonus)
	for child in node.get_children():
		_bump(child, bonus)


func save_settings() -> void:
	var data := {
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"joystick_scale": joystick_scale,
		"language": language,
		"large_text": large_text,
	}
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data))
	f.close()


func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	music_volume = clampf(float(d.get("music_volume", 1.0)), 0.0, 1.0)
	sfx_volume = clampf(float(d.get("sfx_volume", 1.0)), 0.0, 1.0)
	joystick_scale = clampf(float(d.get("joystick_scale", 1.0)), 0.8, 1.5)
	language = String(d.get("language", "en"))
	large_text = bool(d.get("large_text", false))
