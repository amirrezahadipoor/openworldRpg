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


## Lines for the state of the world *after* the chain is over. The game used to
## go silent once the boss was down: no NPC acknowledged that it had changed.
const POST_GAME_LINES := {
	"elder_rowan": "The fire is still going. That is the whole of my report.",
	"hunter_kael": "Nothing on the salt since. I keep walking it anyway.",
	"merchant_bram": "Prices are down. Nobody needs warding anymore, apparently.",
	"ysolde": "I melted my last Choir ingot down into a cooking pot. Feels right.",
	"elder_fenwick": "Oakstead's fold has lambs in it again. Come and see them.",
	"brother_ashe": "I have started writing it down. Someone should have the order of it.",
	"captain_dael": "The wall is quiet. I do not trust quiet, but I will take it.",
	"magistrate_voss": "The ledger balances. Do not ask me to say it twice.",
	"mireille": "Whatever you decided, I am still here. That is not nothing.",
	"high_warden_isolde": "The Warden is still. You can put the sword down now.",
	"wren": "You came back. I stopped expecting that a while ago.",
}


func post_game_line(npc_key: String) -> String:
	return String(POST_GAME_LINES.get(npc_key, ""))


func pick(npc_key: String) -> Dictionary:
	## The most specific matching branch wins. The old version returned the first
	## match in file order, so when two authored branches were true at the same time
	## (two quests in flight, say) the second one could never be reached — and with
	## no way to drop a quest, that dialogue was locked out for the whole run
	## (audit G3). An explicit `priority` beats condition count; equal ranks keep
	## file order.
	var best := {}
	var best_rank := -1
	for d in dialogues.get(npc_key, []):
		var req: Dictionary = d.get("requires", {})
		if not _conditions_met(req):
			continue
		var rank := int(d.get("priority", 0)) * 1000 + req.size()
		if rank > best_rank:
			best_rank = rank
			best = d
	return best


const PORTRAIT_DIR := "res://assets/portraits/"
# Display-name variants used in the dialogue data. "Old Rowan" is the roster
# name and "Elder Rowan" is what the camp scene calls him; both are the same man.
const SPEAKER_ALIASES := {"Elder Rowan": "elder_rowan", "Old Rowan": "elder_rowan"}


func portrait_for(speaker: String) -> String:
	## Portrait texture for whoever is talking, or "" when there is no art.
	## Resolved from data/npcs.json display names, so a new NPC ships with a face
	## as soon as the roster entry and the sheet exist.
	var id := String(SPEAKER_ALIASES.get(speaker, ""))
	if id == "":
		for npc_id in _roster_names().keys():
			if String(_roster_names()[npc_id]) == speaker:
				id = String(npc_id)
				break
	if id == "":
		id = speaker.to_lower()
	var path := "%s%s.png" % [PORTRAIT_DIR, id]
	return path if ResourceLoader.exists(path) else ""


## display_name -> npc id, read straight from data/npcs.json. DialogueDB reads the
## file rather than asking NPCController, because NPCController is a scene class
## that must not be a dependency of an autoload.
static var _roster_name_cache: Dictionary = {}


func _roster_names() -> Dictionary:
	if not _roster_name_cache.is_empty():
		return _roster_name_cache
	var f := FileAccess.open("res://data/npcs.json", FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			for npc_id in ((parsed as Dictionary).get("npcs", {}) as Dictionary).keys():
				var entry: Dictionary = ((parsed as Dictionary)["npcs"] as Dictionary).get(npc_id, {})
				_roster_name_cache[String(npc_id)] = String(entry.get("display_name", ""))
	return _roster_name_cache


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
