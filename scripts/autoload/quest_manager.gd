extends Node
## QuestManager — data-driven quest engine (data/quests.json).
## Objective types:
##   kill    — increments on EventBus.enemy_died when archetype matches target
##   talk    — completed via talk_to(npc_id)
##   flag    — completed via register_flag(flag) (quest_flags key)
##   collect — counts items held of `target` (Phase E §5: Fetch/Collection
##             quests). Recomputed from the inventory, so handing items over
##             (or dropping them) is reflected immediately.
##   deliver — like collect, but consumes the items when the objective lands,
##             which is what a trade quest needs.
## Rewards (xp/gold/items) granted on completion; "next" auto-starts.
## State lives in GameState (quests / quest_progress / quest_flags) so it
## save/loads automatically.

var data: Dictionary = {}


func _ready() -> void:
	var f := FileAccess.open("res://data/quests.json", FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(parsed) == TYPE_DICTIONARY:
			data = (parsed as Dictionary).get("quests", {})
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.item_picked_up.connect(_on_item_picked_up)


func quests() -> Dictionary:
	return data


func is_active(qid: String) -> bool:
	return GameState.quests.get(qid, "") == "active"


func is_done(qid: String) -> bool:
	return GameState.quests.get(qid, "") == "done"


## Progress for a collect/deliver objective that is already satisfied by the
## player's bag (picking the items up before accepting the quest must count).
func _sync_collect(qid: String) -> void:
	for obj in _objectives(qid):
		var t := String(obj.get("type", ""))
		if t != "collect" and t != "deliver":
			continue
		var oid := String(obj.get("id", ""))
		var need := int(obj.get("count", 1))
		var have := GameState.item_count(String(obj.get("target", "")))
		if have >= need and objective_count(qid, oid) < need:
			_set_done_obj(qid, oid, need)


func _sync_flags(qid: String) -> void:
	## A quest that asks you to reach somewhere you have already been is already
	## satisfied — the same rule collect objectives use for items in the bag.
	for obj in _objectives(qid):
		if String(obj.get("type", "")) != "flag":
			continue
		var flag := String(obj.get("target", ""))
		if bool(GameState.quest_flags.get(flag, false)):
			var need := int(obj.get("count", 1))
			if objective_count(qid, String(obj.get("id", ""))) < need:
				_set_done_obj(qid, String(obj.get("id", "")), need)


func _on_item_picked_up(_item_id: String, _qty: int) -> void:
	for qid in active_snapshot():
		_sync_collect(qid)


func start_quest(qid: String) -> void:
	if not data.has(qid) or is_active(qid) or is_done(qid):
		return
	GameState.quests[qid] = "active"
	var prog := {}
	for obj in _objectives(qid):
		prog[String(obj.get("id", ""))] = 0
	GameState.quest_progress[qid] = prog
	EventBus.quest_started.emit(qid)
	_sync_collect(qid)
	_sync_flags(qid)
	EventBus.quest_updated.emit(qid)


func _objectives(qid: String) -> Array:
	return (data.get(qid, {}) as Dictionary).get("objectives", [])


func _progress(qid: String) -> Dictionary:
	if not GameState.quest_progress.has(qid):
		GameState.quest_progress[qid] = {}
	return GameState.quest_progress[qid]


func objective_count(qid: String, oid: String) -> int:
	return int(_progress(qid).get(oid, 0))


func _bump(qid: String, oid: String, needed: int, amount: int = 1) -> void:
	var prog := _progress(qid)
	var was := int(prog.get(oid, 0))
	prog[oid] = mini(was + amount, needed)
	if was < needed and int(prog[oid]) >= needed:
		_auto_flag(qid, oid)
	EventBus.quest_updated.emit(qid)
	_check_complete(qid)


func _set_done_obj(qid: String, oid: String, needed: int) -> void:
	var was := objective_count(qid, oid)
	_progress(qid)[oid] = needed
	if was < needed:
		_auto_flag(qid, oid)
	EventBus.quest_updated.emit(qid)
	_check_complete(qid)


## Completing an objective also raises a flag named "<quest>_<objective>",
## so dialogue `requires` can gate on it (e.g. q1_first_light_kill_grunts).
func _auto_flag(qid: String, oid: String) -> void:
	GameState.quest_flags["%s_%s" % [qid, oid]] = true


# --- Triggers -----------------------------------------------------------------

func active_snapshot() -> Array:
	## The quests that are in flight right now, frozen — so a cascade of
	## auto-started follow-ups cannot be advanced by the event that triggered it.
	var out := []
	for qid in data.keys():
		if is_active(qid):
			out.append(qid)
	return out


func _on_enemy_died(enemy: Node) -> void:
	var arch := ""
	if "archetype" in enemy:
		arch = String(enemy.archetype)
	for qid in active_snapshot():
		if not is_active(qid):
			continue
		for obj in _objectives(qid):
			if String(obj.get("type", "")) == "kill" and String(obj.get("target", "")) == arch:
				var oid := String(obj.get("id", ""))
				var need := int(obj.get("count", 1))
				if objective_count(qid, oid) < need:
					_bump(qid, oid, need)


func talk_to(npc_id: String) -> void:
	for qid in active_snapshot():
		for obj in _objectives(qid):
			if String(obj.get("type", "")) == "talk" and String(obj.get("target", "")) == npc_id:
				var oid := String(obj.get("id", ""))
				var need := int(obj.get("count", 1))
				if objective_count(qid, oid) < need:
					_set_done_obj(qid, oid, need)


func register_flag(flag: String) -> void:
	if bool(GameState.quest_flags.get(flag, false)):
		return
	GameState.quest_flags[flag] = true
	for qid in active_snapshot():
		for obj in _objectives(qid):
			if String(obj.get("type", "")) == "flag" and String(obj.get("target", "")) == flag:
				var oid := String(obj.get("id", ""))
				var need := int(obj.get("count", 1))
				_set_done_obj(qid, oid, need)


func complete_objective(qid: String, oid: String) -> void:
	if not is_active(qid):
		return
	for obj in _objectives(qid):
		if String(obj.get("id", "")) == oid:
			_set_done_obj(qid, oid, int(obj.get("count", 1)))
			return


# --- Completion ----------------------------------------------------------------

func _check_complete(qid: String) -> void:
	if not is_active(qid):
		return
	for obj in _objectives(qid):
		var oid := String(obj.get("id", ""))
		if objective_count(qid, oid) < int(obj.get("count", 1)):
			return
	_complete(qid)


func _complete(qid: String) -> void:
	var quest: Dictionary = data.get(qid, {})
	# Deliver objectives hand the goods over as the quest closes.
	for obj in _objectives(qid):
		if String(obj.get("type", "")) == "deliver":
			GameState.remove_item(String(obj.get("target", "")), int(obj.get("count", 1)))
	var reward: Dictionary = quest.get("reward", {})
	if int(reward.get("xp", 0)) > 0:
		GameState.add_xp(int(reward["xp"]))
	if int(reward.get("gold", 0)) > 0:
		GameState.add_gold(int(reward["gold"]))
	for it in reward.get("items", []):
		GameState.add_item(String(it), 1)
		EventBus.item_picked_up.emit(String(it), 1)
	if bool(quest.get("repeatable", false)):
		# Repeatable quests reset fully so their dialogue can re-offer them.
		GameState.quests.erase(qid)
		GameState.quest_progress.erase(qid)
	else:
		GameState.quests[qid] = "done"
	EventBus.quest_completed.emit(qid)
	var nxt := String(quest.get("next", ""))
	if nxt != "":
		start_quest(nxt)


# --- side-quest board (Phase F5) ---------------------------------------------------

func side_quests() -> Array:
	## Every authored side quest id, in board order.
	var out := []
	for qid in data.keys():
		if String(qid).begins_with("SQ"):
			out.append(String(qid))
	return out


func next_offer(npc_id: String) -> String:
	## The next job this NPC has for the player: authored for them, not taken,
	## not already done, and at or below the player's level. Easiest first, so the
	## board grows with the player instead of dumping 100 jobs in Millhaven.
	var best := ""
	var best_level := 9999
	for qid in data.keys():
		var quest: Dictionary = data[qid]
		if String(qid).begins_with("SQ") == false:
			continue
		if String(quest.get("giver", "")) != npc_id:
			continue
		if is_active(String(qid)) or is_done(String(qid)):
			continue
		if bool(GameState.quest_flags.get("took_%s" % qid, false)):
			continue
		var lvl := int(quest.get("level_anchor", 1))
		if lvl > GameState.level:
			continue
		if lvl < best_level:
			best_level = lvl
			best = String(qid)
	return best


func reminder_for(npc_id: String) -> String:
	## What this NPC would say about the job you are already carrying. Barks were
	## completely deaf to quest state (0 of 37 were flag-gated), so an NPC you
	## were mid-mission for greeted you like a stranger.
	for row in active_snapshot():
		var qid := String(row)
		var data_q: Dictionary = data.get(qid, {})
		if data_q.is_empty():
			continue
		var giver := String(data_q.get("giver", ""))
		var targets: Array = []
		for o in (data_q.get("objectives", []) as Array):
			var od := o as Dictionary
			if String(od.get("type", "")) == "talk":
				targets.append(String(od.get("target", "")))
		if giver != npc_id and not targets.has(npc_id):
			continue
		var next_obj := ""
		for o in (data_q.get("objectives", []) as Array):
			var od := o as Dictionary
			if objective_count(qid, String(od.get("id", ""))) < int(od.get("count", 1)):
				next_obj = String(od.get("desc", ""))
				break
		if giver == npc_id:
			return "\"%s\" is not finished. %s" % [String(data_q.get("name", qid)), next_obj]
		return "You are still on \"%s\". %s" % [String(data_q.get("name", qid)), next_obj]
	return ""


func offer_dialogue(npc_id: String, display_name: String) -> Dictionary:
	## Wrap an offer in the same shape the dialogue box already understands, so
	## the board uses the existing choice UI rather than a second one.
	var qid := next_offer(npc_id)
	if qid == "":
		return {}
	var quest: Dictionary = data.get(qid, {})
	var first_obj: Dictionary = (quest.get("objectives", []) as Array)[0] if \
		not (quest.get("objectives", []) as Array).is_empty() else {}
	return {
		"start": "root",
		"nodes": {
			"root": {
				"speaker": display_name,
				"text": "%s — %s" % [String(quest.get("name", qid)),
					String(quest.get("desc", ""))],
				"next": "accept",
			},
			"accept": {
				"speaker": display_name,
				"text": String(first_obj.get("desc", "Come back when it is done.")),
				"choices": [
					{
						"text": "I will take it.",
						"next": "",
						"actions": [
							{"action": "start_quest", "quest": qid},
							{"action": "set_flag", "flag": "took_%s" % qid},
						],
					},
					{
						"text": "Not today.",
						"next": "",
						"actions": [],
					},
				],
			},
		},
	}


# --- NPC markers ------------------------------------------------------------------

func marker_for(npc_id: String) -> bool:
	## "!" when this NPC can advance an active quest, or can start one.
	for qid in data.keys():
		if not is_active(qid):
			continue
		for obj in _objectives(qid):
			if String(obj.get("type", "")) == "talk" \
					and String(obj.get("target", "")) == npc_id \
					and objective_count(qid, String(obj.get("id", ""))) < int(obj.get("count", 1)):
				return true
	var d := DialogueDB.pick(npc_id)
	for a in d.get("on_complete", []):
		if String(a.get("action", "")) == "start_quest":
			return true
	if next_offer(npc_id) != "":
		return true
	return false


# --- HUD / log ------------------------------------------------------------------

func active_quest_id() -> String:
	for qid in data.keys():
		if is_active(qid):
			return qid
	return ""


func tracker_text() -> String:
	var qid := active_quest_id()
	if qid == "":
		return "No active quests"
	var quest: Dictionary = data.get(qid, {})
	var lines := [String(quest.get("name", qid))]
	for obj in _objectives(qid):
		var oid := String(obj.get("id", ""))
		var need := int(obj.get("count", 1))
		var cur := objective_count(qid, oid)
		var mark := "✓" if cur >= need else "·"
		lines.append("%s %s (%d/%d)" % [mark, String(obj.get("desc", oid)), cur, need])
	return "\n".join(lines)
