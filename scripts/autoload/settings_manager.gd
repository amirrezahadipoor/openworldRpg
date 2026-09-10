extends Node
## SettingsManager — persisted user settings (user://settings.json).
## Language is a stub (English-only build per DECISIONS #4).

const SETTINGS_PATH := "user://settings.json"

var music_volume := 1.0
var sfx_volume := 1.0
var joystick_scale := 1.0
var language := "en"


func _ready() -> void:
	load_settings()
	apply()


func apply() -> void:
	AudioManager.set_music_volume(music_volume)
	AudioManager.set_sfx_volume(sfx_volume)


func save_settings() -> void:
	var data := {
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"joystick_scale": joystick_scale,
		"language": language,
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
