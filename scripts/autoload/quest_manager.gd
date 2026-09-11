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


## Recompute every active quest's collect/deliver objective from the bag. The
## item_picked_up hook covers normal looting, but items granted through other
## paths (a load, a dialogue give_item whose signal was already consumed, a test
## harness adding items directly) still have to count — this is that entry point.
func sync_collect_objectives() -> void:
	for qid in active_snapshot():
		_sync_collect(qid)


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
	## Only the quest's *next* objective can be satisfied by talking. Hitting every
	## talk objective at once meant a single conversation could complete a step that
	## was gated behind a kill, ending two quests with one greeting (audit G2).
	for qid in active_snapshot():
		var next := next_objective(qid)
		if next.is_empty():
			continue
		if String(next.get("type", "")) != "talk":
			continue
		if String(next.get("target", "")) != npc_id:
			continue
		var oid := String(next.get("id", ""))
		var need := int(next.get("count", 1))
		if objective_count(qid, oid) < need:
			_set_done_obj(qid, oid, need)


func next_objective(qid: String) -> Dictionary:
	## The first objective of `qid` that is not finished yet — the only one that can
	## be advanced right now. Empty when the quest has no objectives or is finished.
	for obj in _objectives(qid):
		var oid := String(obj.get("id", ""))
		if objective_count(qid, oid) < int(obj.get("count", 1)):
			return obj
	return {}


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
	var reward: Dictionary = reward_of(qid)
	if int(reward.get("xp", 0)) > 0:
		GameState.add_xp(int(reward["xp"]))
	if int(reward.get("gold", 0)) > 0:
		GameState.add_gold(int(reward["gold"]))
	for it in reward.get("items", []):
		GameState.add_item(String(it), 1)
		EventBus.item_picked_up.emit(String(it), 1)
	# The ledger is the answer to "what did that job actually pay me?" — quests,
	# trades and level-ups all write to it, and the quest log reads it back.
	GameState.ledger_add("quest", "%s — %s" % [
		String(quest.get("title", qid)), _reward_text(reward)])
	if bool(quest.get("repeatable", false)):
		# Repeatable quests reset fully so their dialogue can re-offer them — and
		# that has to include the flag that recorded taking the job, or
		# next_offer() skips it forever and the job is one-shot after all (G1).
		GameState.quests.erase(qid)
		GameState.quest_progress.erase(qid)
		GameState.quest_flags.erase("took_%s" % qid)
	else:
		GameState.quests[qid] = "done"
	EventBus.quest_completed.emit(qid)
	var nxt := String(quest.get("next", ""))
	if nxt != "":
		start_quest(nxt)


func reward_of(qid: String) -> Dictionary:
	return (data.get(qid, {}) as Dictionary).get("reward", {})


func _reward_text(reward: Dictionary) -> String:
	var parts: Array = []
	if int(reward.get("gold", 0)) > 0:
		parts.append("%d g" % int(reward["gold"]))
	if int(reward.get("xp", 0)) > 0:
		parts.append("%d xp" % int(reward["xp"]))
	for it in reward.get("items", []):
		parts.append(ItemsDB.item_name(String(it)))
	return ", ".join(parts) if not parts.is_empty() else "no reward"


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
	## The player's own order: GameState.quests keeps insertion order, so this is
	## the quest they took first — the data dictionary's key order used to decide,
	## which had nothing to do with the run (audit G4).
	for qid in GameState.quests.keys():
		if is_active(String(qid)):
			return String(qid)
	return ""


func active_quest_ids() -> Array:
	var out: Array = []
	for qid in GameState.quests.keys():
		if is_active(String(qid)):
			out.append(String(qid))
	return out


func pinned_quest_id() -> String:
	var qid := GameState.pinned_quest
	return qid if qid != "" and is_active(qid) else ""


func set_pinned(qid: String) -> void:
	GameState.pinned_quest = qid if qid != GameState.pinned_quest else ""
	EventBus.quest_updated.emit(GameState.pinned_quest)


func tracker_text() -> String:
	## Several jobs can be in flight at once (the side-quest board is built on
	## exactly that), and the HUD used to show whichever one the data dictionary
	## happened to yield first, silently dropping the rest (audit G4). Show the
	## pinned quest in full, then one line per other active quest.
	var order := active_quest_ids()
	if order.is_empty():
		return "No active quests"
	var pinned := pinned_quest_id()
	var qid := pinned if pinned != "" else String(order[0])
	var text := _quest_tracker_block(qid, pinned != "")
	var others: Array = []
	for other in order:
		if String(other) == qid:
			continue
		others.append(String(other))
	if not others.is_empty():
		text += "\n"
		var shown: Array = []
		for i in mini(others.size(), MAX_TRACKER_QUESTS):
			shown.append("• " + _quest_headline(String(others[i])))
		if others.size() > MAX_TRACKER_QUESTS:
			shown.append("  (+%d more)" % (others.size() - MAX_TRACKER_QUESTS))
		text += "\n".join(shown)
	return text


const MAX_TRACKER_QUESTS := 3


func _quest_headline(qid: String) -> String:
	var quest: Dictionary = data.get(qid, {})
	var nxt := next_objective(qid)
	if nxt.is_empty():
		return String(quest.get("name", qid))
	var oid := String(nxt.get("id", ""))
	return "%s — %s (%d/%d)" % [
		String(quest.get("name", qid)), String(nxt.get("desc", oid)),
		objective_count(qid, oid), int(nxt.get("count", 1))]


func _quest_tracker_block(qid: String, pinned: bool) -> String:
	var entry: Dictionary = data.get(qid, {})
	var lines := []
	lines.append(("★ " if pinned else "") + String(entry.get("name", qid)))
	for obj in _objectives(qid):
		var oid := String(obj.get("id", ""))
		var need := int(obj.get("count", 1))
		var cur := objective_count(qid, oid)
		var mark := "✓" if cur >= need else "·"
		lines.append("%s %s (%d/%d)" % [mark, String(obj.get("desc", oid)), cur, need])
	return "\n".join(lines)
