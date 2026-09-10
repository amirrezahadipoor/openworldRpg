extends Node
## SaveSystem — 3 save slots at user://save_N.json (DECISIONS #22).
## JSON, versioned. Migrates the legacy single user://save.json to slot 1.

const SAVE_VERSION := 1
const SLOT_COUNT := 3
const LEGACY_PATH := "user://save.json"


func _ready() -> void:
	_migrate_legacy()


func path_for(slot: int) -> String:
	return "user://save_%d.json" % clampi(slot, 1, SLOT_COUNT)


func _migrate_legacy() -> void:
	if FileAccess.file_exists(LEGACY_PATH) and not FileAccess.file_exists(path_for(1)):
		var f := FileAccess.open(LEGACY_PATH, FileAccess.READ)
		if f != null:
			var content := f.get_as_text()
			f.close()
			var out := FileAccess.open(path_for(1), FileAccess.WRITE)
			if out != null:
				out.store_string(content)
				out.close()


func has_save(slot: int = 1) -> bool:
	return FileAccess.file_exists(path_for(slot))


func save_game(player: Node2D, slot: int = -1) -> bool:
	var s := GameState.current_slot if slot == -1 else slot
	var data := {
		"version": SAVE_VERSION,
		"state": GameState.to_dict(),
		"player": {
			"x": player.global_position.x,
			"y": player.global_position.y,
		},
	}
	var f := FileAccess.open(path_for(s), FileAccess.WRITE)
	if f == null:
		push_error("SaveSystem: cannot open %s (err=%d)" % [path_for(s), FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	EventBus.game_saved.emit()
	return true


func load_game(player: Node2D, slot: int = -1) -> bool:
	var s := GameState.current_slot if slot == -1 else slot
	if not has_save(s):
		return false
	var f := FileAccess.open(path_for(s), FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SaveSystem: corrupt save ignored")
		return false
	var d: Dictionary = parsed
	# Forward-compatible: future versions migrate on d["version"].
	GameState.from_dict(d.get("state", {}))
	var p: Dictionary = d.get("player", {})
	player.global_position = Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))
	EventBus.game_loaded.emit()
	return true


func slot_summary(slot: int) -> Dictionary:
	## {"exists": bool, "level": int, "gold": int} for slot pickers.
	if not has_save(slot):
		return {"exists": false}
	var f := FileAccess.open(path_for(slot), FileAccess.READ)
	if f == null:
		return {"exists": false}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"exists": false}
	var state: Dictionary = (parsed as Dictionary).get("state", {})
	return {
		"exists": true,
		"level": int(state.get("level", 1)),
		"gold": int(state.get("gold", 0)),
	}
