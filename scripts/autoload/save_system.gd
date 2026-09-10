extends Node
## SaveSystem — JSON save at user://save.json (DECISIONS.md #5).

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game(player: Node2D) -> bool:
	var data := {
		"version": SAVE_VERSION,
		"state": GameState.to_dict(),
		"player": {
			"x": player.global_position.x,
			"y": player.global_position.y,
		},
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("SaveSystem: cannot open %s (err=%d)" % [SAVE_PATH, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	EventBus.game_saved.emit()
	return true


func load_game(player: Node2D) -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SaveSystem: corrupt save file ignored")
		return false
	var d: Dictionary = parsed
	# Forward-compatible: future versions migrate here based on d["version"].
	GameState.from_dict(d.get("state", {}))
	var p: Dictionary = d.get("player", {})
	player.global_position = Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))
	EventBus.game_loaded.emit()
	return true
