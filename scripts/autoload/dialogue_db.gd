extends Node
## DialogueDB — loads every res://data/dialogue/*.json at startup.
## pick(npc_key) returns the FIRST dialogue for that NPC whose `requires`
## block matches current world state (quests/flags). Fully data-driven.

var dialogues: Dictionary = {}  # npc_key -> Array of dialogue dicts
var barks: Dictionary = {}      # npc_key -> Array of idle barks (Phase E §3)
var _bark_cursor: Dictionary = {}  # npc_key -> rotation index (no repeats)


func _ready() -> void:
	var dir := DirAccess.open("res://data/dialogue")
	if dir == null:
		push_error("DialogueDB: res://data/dialogue missing")
		return
	for file_name in dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		var f := FileAccess.open("res://data/dialogue/" + file_name, FileAccess.READ)
		if f == null:
			continue
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("DialogueDB: bad JSON in " + file_name)
			continue
		var npc_key := file_name.get_basename()
		dialogues[npc_key] = (parsed as Dictionary).get("dialogues", [])
		barks[npc_key] = (parsed as Dictionary).get("barks", [])


func pick_bark(npc_key: String, time_name: String = "") -> String:
	## One idle bark for this NPC, filtered by time of day when a bark declares
	## `when`. Rotates so the same line never plays twice in a row.
	var all: Array = barks.get(npc_key, [])
	if all.is_empty():
		return ""
	var eligible: Array = []
	for b in all:
		var bark := b as Dictionary
		var when: Array = bark.get("when", [])
		if when.is_empty() or time_name == "" or when.has(time_name):
			eligible.append(String(bark.get("text", "")))
	if eligible.is_empty():
		return ""
	var i := int(_bark_cursor.get(npc_key, 0)) % eligible.size()
	_bark_cursor[npc_key] = i + 1
	return eligible[i]


func bark_count(npc_key: String) -> int:
	return (barks.get(npc_key, []) as Array).size()


func pick(npc_key: String) -> Dictionary:
	for d in dialogues.get(npc_key, []):
		if _conditions_met(d.get("requires", {})):
			return d
	return {}


func _conditions_met(req: Dictionary) -> bool:
	for qid in req.get("quest_active", []):
		if GameState.quests.get(qid, "") != "active":
			return false
	for qid in req.get("quest_done", []):
		if GameState.quests.get(qid, "") != "done":
			return false
	for flag in req.get("flag", []):
		if not bool(GameState.quest_flags.get(flag, false)):
			return false
	for flag in req.get("flag_not", []):
		if bool(GameState.quest_flags.get(flag, false)):
			return false
	# Phase F5: side-quest offers are gated by level, so the board grows with the
	# player instead of dumping 100 jobs on them in Millhaven.
	if req.has("min_level") and GameState.level < int(req.get("min_level", 1)):
		return false
	if req.has("max_level") and GameState.level > int(req.get("max_level", 100)):
		return false
	return true


func get_dialogue(npc_key: String, id: String) -> Dictionary:
	for d in dialogues.get(npc_key, []):
		if String(d.get("id", "")) == id:
			return d
	return {}
