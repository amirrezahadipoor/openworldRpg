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


func _on_item_picked_up(_item_id: String, _qty: int) -> void:
	for qid in data.keys():
		if is_active(qid):
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
	EventBus.quest_updated.emit(qid)
	_sync_collect(qid)


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

func _on_enemy_died(enemy: Node) -> void:
	var arch := ""
	if "archetype" in enemy:
		arch = String(enemy.archetype)
	for qid in data.keys():
		if not is_active(qid):
			continue
		for obj in _objectives(qid):
			if String(obj.get("type", "")) == "kill" and String(obj.get("target", "")) == arch:
				var oid := String(obj.get("id", ""))
				var need := int(obj.get("count", 1))
				if objective_count(qid, oid) < need:
					_bump(qid, oid, need)


func talk_to(npc_id: String) -> void:
	for qid in data.keys():
		if not is_active(qid):
			continue
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
	for qid in data.keys():
		if not is_active(qid):
			continue
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
