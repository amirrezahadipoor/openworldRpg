extends Node
## DialogueDB — loads every res://data/dialogue/*.json at startup.
## pick(npc_key) returns the FIRST dialogue for that NPC whose `requires`
## block matches current world state (quests/flags). Fully data-driven.

var dialogues: Dictionary = {}  # npc_key -> Array of dialogue dicts


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
	return true


func get_dialogue(npc_key: String, id: String) -> Dictionary:
	for d in dialogues.get(npc_key, []):
		if String(d.get("id", "")) == id:
			return d
	return {}
