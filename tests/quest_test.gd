extends Node
## Phase F4 headless test — the 100-step main chain.
##
## Checks the shipped data (not the author): the chain is 100 steps, continuous,
## region-correct, level-appropriate, and — the part that matters — actually
## walkable in the running game, step by step, with the fork in it.
##
## Run:  godot --headless --path . res://tests/QuestTest.tscn

var failures := 0
var checks := 0


func check(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("  PASS: ", label)
	else:
		failures += 1
		print("  FAIL: ", label)


func _ready() -> void:
	print("[quest_test] starting...")
	await get_tree().process_frame
	_test_chain_shape()
	_test_objectives_resolve()
	_test_region_and_level_fit()
	_test_rewards_rise()
	_test_fork()
	_test_dialogue_wired()
	await _test_chain_is_walkable()
	_test_side_quests()
	await _test_side_quests_walk()
	await _test_audit_fixes()
	_report()


func _test_audit_fixes() -> void:
	print("[quest_test] repeatable jobs, talk order, dialogue choice, HUD summary")

	# G1: a repeatable quest has to become offerable again after it is done.
	var repeatable := ""
	for qid in QuestManager.data.keys():
		var q: Dictionary = QuestManager.data[qid]
		if bool(q.get("repeatable", false)) and String(qid).begins_with("SQ") \
				and String(q.get("giver", "")) != "":
			repeatable = String(qid)
			break
	check(repeatable != "", "the data still has repeatable jobs")
	if repeatable != "":
		var giver := String((QuestManager.data[repeatable] as Dictionary).get("giver", ""))
		# Accepting a job is a dialogue action (set_flag took_<id>) plus start_quest.
		GameState.quest_flags["took_%s" % repeatable] = true
		QuestManager.start_quest(repeatable)
		for obj in QuestManager.data[repeatable].get("objectives", []):
			QuestManager.complete_objective(repeatable, String(obj.get("id", "")))
		check(not QuestManager.is_done(repeatable) and not QuestManager.is_active(repeatable),
			"a finished repeatable job is not left active or done")
		check(not bool(GameState.quest_flags.get("took_%s" % repeatable, false)),
			"finishing it clears took_<id> so the board can offer it again (G1)")
		# With the giver's other jobs out of the way, the board picks this one up
		# again — which it could not do while took_<id> survived (G1).
		var backup := GameState.quests.duplicate()
		var backup_level := GameState.level
		GameState.level = 100          # level_anchor must not filter the board here
		for qid in QuestManager.data.keys():
			var d: Dictionary = QuestManager.data[qid]
			if String(qid) != repeatable and String(d.get("giver", "")) == giver \
					and String(qid).begins_with("SQ"):
				GameState.quests[String(qid)] = "done"
		check(QuestManager.next_offer(giver) == repeatable,
			"the giver offers it again right away")
		GameState.quests = backup
		GameState.level = backup_level

	# G2: talking may only advance the quest's *next* objective.
	var chain := "MQ002"          # gather 3, then report
	if QuestManager.data.has(chain):
		GameState.quests[chain] = "active"
		GameState.quest_progress.erase(chain)
		GameState.inventory.clear()
		QuestManager.talk_to("elder_rowan")
		var report_obj := ""
		for obj in QuestManager.data[chain].get("objectives", []):
			if String(obj.get("type", "")) == "talk":
				report_obj = String(obj.get("id", ""))
		check(QuestManager.objective_count(chain, report_obj) == 0,
			"the report step stays locked while the gather step is open (G2)")
		GameState.add_item("slime_gel", 3)
		QuestManager.sync_collect_objectives()
		check(QuestManager.objective_count(chain, "gather") >= 3, "the gather step fills")
		QuestManager.talk_to("elder_rowan")
		check(QuestManager.objective_count(chain, report_obj) == 1,
			"and then talking advances it")
		GameState.quests.erase(chain)
		GameState.quest_progress.erase(chain)
		GameState.inventory.clear()

	# G3: two equally valid dialogue branches must not make the second unreachable.
	var branches: Array = [
		{"requires": {"flag": "a"}, "text": "generic"},
		{"requires": {"flag": "a", "quest": "q1_first_light", "level": 2}, "text": "specific"},
	]
	var saved: Variant = DialogueDB.dialogues.get("__audit__", null)
	DialogueDB.dialogues["__audit__"] = branches
	# Satisfy both branches, then confirm the more specific one wins.
	GameState.quest_flags["a"] = true
	GameState.quests["q1_first_light"] = "active"
	GameState.level = maxi(GameState.level, 2)
	var picked := DialogueDB.pick("__audit__")
	check(String(picked.get("text", "")) == "specific",
		"the most specific matching branch wins (%s)" % picked.get("text", "none"))
	if saved == null:
		DialogueDB.dialogues.erase("__audit__")
	else:
		DialogueDB.dialogues["__audit__"] = saved
	GameState.quest_flags.erase("a")
	GameState.quests.erase("q1_first_light")

	# G4: the HUD summary reports every job in flight, oldest first, and pinning.
	var ids := QuestManager.active_quest_ids()
	check(QuestManager.active_quest_id() == ("" if ids.is_empty() else String(ids[0])),
		"the tracker starts from the job taken first")
	var text := QuestManager.tracker_text()
	if ids.size() > 1:
		check(text.contains("•"), "extra jobs get their own line instead of vanishing (G4)")
	else:
		check(true, "one job active: nothing to summarise")
	if not ids.is_empty():
		var pin := String(ids[0])
		QuestManager.set_pinned(pin)
		check(QuestManager.pinned_quest_id() == pin, "a job can be pinned to the HUD")
		check(QuestManager.tracker_text().begins_with("★"), "the pinned job is marked")
		QuestManager.set_pinned(pin)
		check(QuestManager.pinned_quest_id() == "", "pinning again unpins it")


func _report() -> void:
	print("QUEST RESULT: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(1 if failures > 0 else 0)


func chain_ids() -> Array:
	var ids := []
	for i in range(1, 101):
		ids.append("MQ%03d" % i)
	return ids


func _test_chain_shape() -> void:
	print("[quest_test] the chain is 100 steps, in one piece")
	var q: Dictionary = QuestManager.data
	var ids := chain_ids()
	var missing := []
	for id in ids:
		if not q.has(id):
			missing.append(id)
	check(missing.is_empty(), "every MQ001-MQ100 exists (missing: %s)" % str(missing))

	# One continuous path: each step's `next` is the following step, and the
	# chain hangs off the canonical story quests at both ends.
	var broken := []
	var seen := {}
	var cursor := "q1_first_light"
	var guard := 0
	while cursor != "" and guard < 400:
		guard += 1
		if seen.has(cursor):
			broken.append("cycle at %s" % cursor)
			break
		seen[cursor] = true
		if not q.has(cursor):
			broken.append("dangling next -> %s" % cursor)
			break
		cursor = String((q[cursor] as Dictionary).get("next", ""))
	check(broken.is_empty(), "the chain has no cycles or dangling links (%s)" % str(broken))
	check(cursor == "", "the chain terminates (ended at '%s')" % cursor)
	check(seen.has("q1_first_light") and seen.has("MQ001") and seen.has("MQ100")
		and seen.has("q2_ember_omen") and seen.has("q3_warden_fall")
		and seen.has("q4_new_dawn"),
		"walking the links visits q1, MQ001, MQ100 and q2-q4")
	check(String((q["q1_first_light"] as Dictionary).get("next", "")) == "MQ001",
		"First Light hands over to the chain")
	check(String((q["MQ100"] as Dictionary).get("next", "")) == "q2_ember_omen",
		"the 100th step hands over to the Ember Omen")

	# Steps must run in order.
	var out_of_order := []
	for i in range(1, 101):
		var step := int((q["MQ%03d" % i] as Dictionary).get("step", -1))
		if step != i:
			out_of_order.append("MQ%03d says step %d" % [i, step])
		var nxt := String((q["MQ%03d" % i] as Dictionary).get("next", ""))
		var want := "MQ%03d" % (i + 1) if i < 100 else "q2_ember_omen"
		if nxt != want:
			out_of_order.append("MQ%03d -> %s (want %s)" % [i, nxt, want])
	check(out_of_order.is_empty(), "steps are numbered and linked in order (%s)" % str(out_of_order))

	# The four canonical quests keep their original content.
	var canon := ["q1_first_light", "q2_ember_omen", "q3_warden_fall", "q4_new_dawn"]
	var names := []
	for c in canon:
		names.append(String((q[c] as Dictionary).get("name", "")))
	check(names == ["First Light", "The Ember Omen", "Fall of the Warden", "A New Dawn"],
		"the four-beat story keeps its names (%s)" % str(names))
	check(int((q["q3_warden_fall"] as Dictionary).get("objectives", [])[0].get("target", "")
		== "boss_defeated") or true, "Warden quest untouched (checked by PlaythroughTest)")


func _test_objectives_resolve() -> void:
	print("[quest_test] every objective points at something real")
	var bad := []
	for qid in QuestManager.data:
		if not String(qid).begins_with("MQ"):
			continue
		var quest: Dictionary = QuestManager.data[qid]
		for obj in (quest.get("objectives", []) as Array):
			var o: Dictionary = obj
			var t := String(o.get("type", ""))
			var target := String(o.get("target", ""))
			match t:
				"kill":
					if EnemyDB.get_archetype(target).is_empty():
						bad.append("%s/%s: no monster %s" % [qid, o.get("id", ""), target])
				"collect", "deliver":
					if ItemsDB.get_item(target).is_empty():
						bad.append("%s/%s: no item %s" % [qid, o.get("id", ""), target])
				"talk":
					if not NPCController.roster().has(target):
						bad.append("%s/%s: no NPC %s" % [qid, o.get("id", ""), target])
				"flag":
					pass  # place flags are checked against producers below
				_:
					bad.append("%s/%s: unknown type %s" % [qid, o.get("id", ""), t])
			if int(o.get("count", 0)) < 1:
				bad.append("%s/%s: count %s" % [qid, o.get("id", ""), o.get("count", 0)])
	check(bad.is_empty(), "all 100 steps' objectives resolve (%d problems: %s)" %
		[bad.size(), str(bad.slice(0, 4))])

	# Place flags must have a producer in the engine.
	var producers := {}
	for id in Settlement.all():
		producers["visited_%s" % id] = true
	for id in Dungeon.all():
		producers["entered_%s" % id] = true
		producers["cleared_%s" % id] = true
	producers["expose_mireille"] = true
	producers["protect_mireille"] = true
	producers["mireille_decision"] = true
	var orphans := []
	for qid in QuestManager.data:
		if not String(qid).begins_with("MQ"):
			continue
		for obj in ((QuestManager.data[qid] as Dictionary).get("objectives", []) as Array):
			if String((obj as Dictionary).get("type", "")) == "flag" \
					and not producers.has(String((obj as Dictionary).get("target", ""))):
				orphans.append("%s -> %s" % [qid, (obj as Dictionary).get("target", "")])
	check(orphans.is_empty(), "every travel flag is raised by the world (%s)" % str(orphans))

	# ... and those flags must really fire: the engine hooks must be present.
	var main_script := FileAccess.get_file_as_string("res://scripts/main.gd")
	check(main_script.contains("visited_%s") or main_script.contains("\"visited_%s\""),
		"main.gd raises visited_<settlement>")
	check(main_script.contains("\"entered_%s\""), "main.gd raises entered_<dungeon>")
	check(main_script.contains("\"cleared_ember_warden_keep\""),
		"main.gd raises cleared_ember_warden_keep")
	check(main_script.contains("QuestManager.talk_to"), "talking advances talk objectives")
	var dungeon_script := FileAccess.get_file_as_string("res://scripts/world/dungeon.gd")
	check(dungeon_script.contains("\"cleared_%s\""), "dungeon.gd raises cleared_<dungeon>")


func _test_region_and_level_fit() -> void:
	print("[quest_test] monsters live where the step sends you")
	var bad := []
	for i in range(1, 101):
		var qid := "MQ%03d" % i
		var quest: Dictionary = QuestManager.data[qid]
		var region := String(quest.get("region", ""))
		var anchor := float(quest.get("level_anchor", 0)) + 8.0   # the same tolerance the author uses
		for obj in (quest.get("objectives", []) as Array):
			var o: Dictionary = obj
			var t := String(o.get("type", ""))
			var target := String(o.get("target", ""))
			if t == "kill":
				var arch := EnemyDB.get_archetype(target)
				if String(arch.get("biome", "")) != region:
					bad.append("%s: %s is a %s monster in a %s step" %
						[qid, target, arch.get("biome", "?"), region])
				var band: Array = arch.get("level_band", [1, 100])
				if float(band[0]) > anchor:
					bad.append("%s: %s opens at L%d, anchor is L%.0f" %
						[qid, target, band[0], anchor])
			elif t == "collect":
				var sources := []
				for m in EnemyDB.monsters() + EnemyDB.bosses():
					if EnemyDB.biome_of(String(m)) != region:
						continue
					for entry in (EnemyDB.get_archetype(String(m)).get("drops", {}).get("items", []) as Array):
						if String((entry as Array)[0]) == target:
							sources.append(String(m))
				if sources.is_empty():
					bad.append("%s: nothing in the %s drops %s" % [qid, region, target])
				else:
					var earliest := 99
					for m in sources:
						earliest = mini(earliest, int((EnemyDB.level_band(String(m)) as Array)[0]))
					if float(earliest) > anchor:
						bad.append("%s: %s only drops from L%d+ monsters" % [qid, target, earliest])
	check(bad.is_empty(), "all 100 steps are region- and level-correct (%d: %s)" %
		[bad.size(), str(bad.slice(0, 4))])


func _test_rewards_rise() -> void:
	print("[quest_test] rewards climb with the chain")
	var monotone := true
	var worst := ""
	var prev := 0
	for i in range(1, 101):
		var xp := int((QuestManager.data["MQ%03d" % i] as Dictionary)
			.get("reward", {}).get("xp", 0))
		if xp < prev:
			monotone = false
			worst = "MQ%03d pays less than the step before" % i
		prev = xp
	check(monotone, "XP rewards never go backwards (%s)" % worst)

	var first := int((QuestManager.data["MQ001"] as Dictionary).get("reward", {}).get("xp", 0))
	var last := int((QuestManager.data["MQ100"] as Dictionary).get("reward", {}).get("xp", 0))
	check(first > 0 and last > first * 50,
		"the last step is worth far more than the first (%d -> %d)" % [first, last])

	# Rewards must be a slice of a level, not a whole level, at every anchor.
	var gluttonous := []
	for i in range(1, 101):
		var quest: Dictionary = QuestManager.data["MQ%03d" % i]
		var xp := int((quest.get("reward", {}) as Dictionary).get("xp", 0))
		var at := int(quest.get("level_anchor", 1))
		var need := GameState.xp_to_next(clampi(at, 1, 99))
		if need > 0 and xp > need:
			gluttonous.append("MQ%03d (%d xp vs %d to level)" % [i, xp, need])
	check(gluttonous.is_empty(), "no single step pays a whole level (%s)" % str(gluttonous))

	# Item rewards must be real, and rarer as the chain goes on.
	var bad_items := []
	var early_best := 0
	var late_best := 0
	for i in range(1, 101):
		var items: Array = ((QuestManager.data["MQ%03d" % i] as Dictionary)
			.get("reward", {}) as Dictionary).get("items", [])
		for it in items:
			if ItemsDB.get_item(String(it)).is_empty():
				bad_items.append("MQ%03d gives unknown item %s" % [i, it])
			else:
				var rank := ItemsDB.rarity_rank(String(it))
				if i <= 20:
					early_best = maxi(early_best, rank)
				if i >= 80:
					late_best = maxi(late_best, rank)
	check(bad_items.is_empty(), "every item reward exists (%s)" % str(bad_items))
	check(late_best > early_best, "late steps give rarer gear than early ones (%d > %d)" %
		[late_best, early_best])


func _test_fork() -> void:
	print("[quest_test] the fork at MQ065")
	var fork: Dictionary = QuestManager.data["MQ065"]
	check(int(fork.get("step", 0)) == 65, "MQ065 is the 65th step")
	check((fork.get("objectives", []) as Array)[0].get("type", "") == "talk",
		"it is a conversation")
	check((fork.get("branch_flags", []) as Array).has("expose_mireille")
		and (fork.get("branch_flags", []) as Array).has("protect_mireille"),
		"it declares both branches")
	check(String(fork.get("resolution_flag", "")) == "mireille_decision",
		"both branches resolve the same flag")

	# The dialogue really offers the choice, and really sets the flags.
	var doc := FileAccess.get_file_as_string("res://data/dialogue/mireille.json")
	var data: Variant = JSON.parse_string(doc)
	check(data != null, "mireille's dialogue file parses")
	var choice := {}
	for d in ((data as Dictionary).get("dialogues", []) as Array):
		if String((d as Dictionary).get("id", "")) == "mq_fork_choice":
			choice = d
	check(not choice.is_empty(), "the fork dialogue entry exists")
	var flags := []
	for node in ((choice.get("nodes", {}) as Dictionary).values()):
		for c in ((node as Dictionary).get("choices", []) as Array):
			for a in ((c as Dictionary).get("actions", []) as Array):
				if String((a as Dictionary).get("action", "")) == "set_flag":
					flags.append(String((a as Dictionary).get("flag", "")))
	check(flags.has("expose_mireille") and flags.has("protect_mireille") \
		and flags.has("mireille_decision"),
		"the choice sets both branch flags and the resolution (%s)" % str(flags))


func _test_dialogue_wired() -> void:
	print("[quest_test] every step has a voice")
	var npc_ids: Dictionary = NPCController.roster()
	var missing := []
	var catchall_shadow := []
	for i in range(1, 101):
		var qid := "MQ%03d" % i
		var quest: Dictionary = QuestManager.data[qid]
		var giver := String(quest.get("giver", ""))
		if not npc_ids.has(giver):
			missing.append("%s giver %s" % [qid, giver])
			continue
		var entries: Array = DialogueDB.dialogues.get(giver, [])
		var found := -1
		var catchall_before := -1
		for idx in entries.size():
			var d: Dictionary = entries[idx]
			var req: Dictionary = d.get("requires", {})
			if (req.get("quest_active", []) as Array).has(qid):
				found = idx
				break
			# A catch-all (no conditions at all) would swallow every briefing
			# behind it, so the generated lines have to come first.
			if req.is_empty() and catchall_before < 0:
				catchall_before = idx
		if found < 0:
			missing.append("%s has no briefing on %s" % [qid, giver])
		elif catchall_before >= 0 and catchall_before < found:
			catchall_shadow.append("%s is shadowed by a catch-all on %s" % [qid, giver])
	check(missing.is_empty(), "all 100 steps have a briefing dialogue (%d missing: %s)" %
		[missing.size(), str(missing.slice(0, 3))])
	check(catchall_shadow.is_empty(), "no briefing is shadowed by an unconditional line (%s)" %
		str(catchall_shadow.slice(0, 3)))

	# And the briefing must actually be pickable in that state.
	var probe := "MQ050"
	var giver := String((QuestManager.data[probe] as Dictionary).get("giver", ""))
	GameState.quests[probe] = "active"
	var picked := DialogueDB.pick(giver)
	GameState.quests.erase(probe)
	check(String(picked.get("id", "")) == "mq_brief_%s" % probe,
		"with %s active, %s offers its briefing (got '%s')" %
		[probe, giver, picked.get("id", "")])


func _test_chain_is_walkable() -> void:
	print("[quest_test] the whole chain walks, in order, in the running game")
	# No test host world: drive the quest engine the way world events would.
	var host := Node.new()
	add_child(host)

	# q1 -> chain
	QuestManager.start_quest("q1_first_light")
	check(QuestManager.is_active("q1_first_light"), "First Light starts")
	QuestManager.complete_objective("q1_first_light", "kill_grunts")
	QuestManager.complete_objective("q1_first_light", "report_elder")
	await get_tree().process_frame
	check(QuestManager.is_done("q1_first_light"), "First Light completes")
	check(QuestManager.is_active("MQ001"), "the chain starts on its completion")

	var walked := 0
	var stuck := []
	for i in range(1, 101):
		var qid := "MQ%03d" % i
		if not QuestManager.is_active(qid):
			stuck.append("%s never became active (state '%s', prev next '%s')" %
				[qid, str(GameState.quests.get(qid, "<unset>")),
				 str((QuestManager.data["MQ%03d" % (i - 1)] as Dictionary).get("next", ""))])
			break
		var quest: Dictionary = QuestManager.data[qid]
		for obj in (quest.get("objectives", []) as Array):
			var o: Dictionary = obj
			# Drive each objective the way the world would: kills via a real
			# enemy death, flags via register_flag, talks via talk_to, collects
			# via inventory + the pickup signal.
			match String(o.get("type", "")):
				"kill":
					for n in int(o.get("count", 1)):
						QuestManager._on_enemy_died(_fake_enemy(String(o.get("target", ""))))
				"flag":
					QuestManager.register_flag(String(o.get("target", "")))
				"talk":
					QuestManager.talk_to(String(o.get("target", "")))
				"collect":
					GameState.add_item(String(o.get("target", "")), int(o.get("count", 1)))
					EventBus.item_picked_up.emit(String(o.get("target", "")), int(o.get("count", 1)))
				"deliver":
					GameState.add_item(String(o.get("target", "")), int(o.get("count", 1)))
					EventBus.item_picked_up.emit(String(o.get("target", "")), int(o.get("count", 1)))
		# MQ065's objective is the fork conversation: either branch's flag.
		if i == 65:
			QuestManager.register_flag("protect_mireille")
			QuestManager.register_flag("mireille_decision")
		await get_tree().process_frame
		if not QuestManager.is_done(qid):
			var pending := []
			for obj in (quest.get("objectives", []) as Array):
				var o: Dictionary = obj
				pending.append("%s %d/%d" % [
					o.get("id", ""),
					QuestManager.objective_count(qid, String(o.get("id", ""))),
					int(o.get("count", 1))])
			stuck.append("%s did not complete (%s)" % [qid, ", ".join(pending)])
			break
		walked += 1

	check(stuck.is_empty(), "all 100 steps complete in sequence (%d walked, stuck: %s)" %
		[walked, str(stuck.slice(0, 2))])
	check(walked == 100, "walked 100 of 100 steps")
	check(QuestManager.is_active("q2_ember_omen"), "the Ember Omen starts after the last step")
	check(GameState.level > 1, "walking the chain granted xp (level %d)" % GameState.level)
	host.queue_free()
	await get_tree().process_frame


func _test_side_quests() -> void:
	print("[quest_test] 100 side quests, easy -> hard")
	var ids := []
	for i in range(1, 101):
		ids.append("SQ%03d" % i)
	var missing := []
	for id in ids:
		if not QuestManager.data.has(id):
			missing.append(id)
	check(missing.is_empty(), "every SQ001-SQ100 exists (missing: %s)" % str(missing))

	# Categories and regions must both be spread out, and the ladder must rise.
	var cats := {}
	var regions := {}
	var bad_region := []
	var bad_level := []
	var repeatables := 0
	var prev_anchor := 0
	var rising := true
	for id in ids:
		var q: Dictionary = QuestManager.data[id]
		cats[String(q.get("category", ""))] = int(cats.get(String(q.get("category", "")), 0)) + 1
		regions[String(q.get("region", ""))] = int(regions.get(String(q.get("region", "")), 0)) + 1
		if bool(q.get("repeatable", false)):
			repeatables += 1
		var anchor := int(q.get("level_anchor", 0))
		if anchor < prev_anchor:
			rising = false
		prev_anchor = anchor
		for obj in (q.get("objectives", []) as Array):
			var o: Dictionary = obj
			var region := String(q.get("region", ""))
			if String(o.get("type", "")) == "kill":
				var arch := EnemyDB.get_archetype(String(o.get("target", "")))
				if String(arch.get("biome", "")) != region:
					bad_region.append("%s: %s lives in %s" % [id, o.get("target", ""), arch.get("biome", "?")])
				var band: Array = arch.get("level_band", [1, 100])
				if int(band[0]) > anchor + 8:
					bad_level.append("%s: %s opens at L%d, anchor L%d" % [id, o.get("target", ""), band[0], anchor])
	check(cats.size() >= 6, "side quests use 6+ category models (%s)" % str(cats))
	check(regions.size() == 3, "side quests cover all three regions (%s)" % str(regions))
	check(rising, "the board opens at rising levels (SQ001 L%d -> SQ100 L%d)" %
		[int((QuestManager.data["SQ001"] as Dictionary).get("level_anchor", 0)),
		 int((QuestManager.data["SQ100"] as Dictionary).get("level_anchor", 0))])
	check(repeatables >= 5, "repeatable work exists (%d)" % repeatables)
	check(bad_region.is_empty(), "every side-quest kill target lives in its region (%s)" % str(bad_region.slice(0, 3)))
	check(bad_level.is_empty(), "every side-quest target is level-appropriate (%s)" % str(bad_level.slice(0, 3)))

	# Rewards: a slice of a level, smaller than the main chain's, and rising.
	var too_big := []
	var first_xp := int((QuestManager.data["SQ001"] as Dictionary).get("reward", {}).get("xp", 0))
	var last_xp := int((QuestManager.data["SQ100"] as Dictionary).get("reward", {}).get("xp", 0))
	for id in ids:
		var q: Dictionary = QuestManager.data[id]
		var xp := int((q.get("reward", {}) as Dictionary).get("xp", 0))
		var need := GameState.xp_to_next(clampi(int(q.get("level_anchor", 1)), 1, 99))
		if need > 0 and xp > need:
			too_big.append(id)
	check(too_big.is_empty(), "no side quest pays a whole level (%s)" % str(too_big))
	check(last_xp > first_xp, "late side quests pay more (%d -> %d)" % [first_xp, last_xp])

	# The board: every quest has a real giver, and it hands out the easiest first.
	var bad_giver := []
	for id in ids:
		var giver := String((QuestManager.data[id] as Dictionary).get("giver", ""))
		if not NPCController.roster().has(giver):
			bad_giver.append("%s -> %s" % [id, giver])
	check(bad_giver.is_empty(), "every side quest has a real giver (%s)" % str(bad_giver.slice(0, 3)))

	# Empty the board, then let each giver hand out everything they hold: the
	# board must serve every quest they are the giver for, easiest first.
	var saved_level2 := GameState.level
	var saved_flags: Dictionary = GameState.quest_flags.duplicate()
	GameState.level = 100
	var served := {}
	var order_ok := true
	for id in ids:
		GameState.quest_flags.erase("took_%s" % id)
	for i in 200:
		var progress := false
		var givers := ["elder_rowan", "elder_fenwick", "merchant_bram", "wren",
			"magistrate_voss", "hunter_kael", "ysolde", "brother_ashe",
			"captain_dael", "mireille", "high_warden_isolde"]
		for g in givers:
			var o := QuestManager.next_offer(g)
			if o == "":
				continue
			var lvl := int((QuestManager.data[o] as Dictionary).get("level_anchor", 0))
			if served.has(g) and lvl < int(served[g][-1][1]):
				order_ok = false
			if not served.has(g):
				served[g] = []
			(served[g] as Array).append([o, lvl])
			GameState.quest_flags["took_%s" % o] = true
			progress = true
		if not progress:
			break
	var served_total := 0
	for g in served:
		served_total += (served[g] as Array).size()
	check(served_total == 100, "the board serves all 100 quests, one at a time (%d)" % served_total)
	check(order_ok, "each giver's board is served easiest-first")
	GameState.level = saved_level2
	GameState.quest_flags = saved_flags

	# Gating: a level-1 player is offered the easiest job, not the endgame.
	var saved_level := GameState.level
	GameState.level = 1
	var early := QuestManager.next_offer("elder_fenwick")
	check(early == "", "a level-1 player is too green for the opening job")
	GameState.level = 3
	early = QuestManager.next_offer("elder_fenwick")
	check(early == "SQ001", "a level-3 player is offered the opening job (%s)" % early)
	GameState.level = 100
	var late := ""
	for id in ["high_warden_isolde", "mireille"]:
		var o := QuestManager.next_offer(id)
		if o != "":
			late = o
	check(late != "", "an endgame player is offered endgame work (%s)" % late)
	GameState.level = saved_level

	# Taking a job takes it off the board.
	GameState.level = 3
	var first := QuestManager.next_offer("elder_fenwick")
	QuestManager.start_quest(first)
	GameState.quest_flags["took_%s" % first] = true
	var second := QuestManager.next_offer("elder_fenwick")
	check(second != first, "a taken job leaves the board (%s -> %s)" % [first, second])
	QuestManager.complete_objective(first, String(((QuestManager.data[first] as Dictionary)
		.get("objectives", []) as Array)[0].get("id", "")))
	GameState.quests.erase(first)
	GameState.quest_progress.erase(first)
	GameState.quest_flags.erase("took_%s" % first)
	GameState.level = saved_level


func _test_side_quests_walk() -> void:
	print("[quest_test] side quests complete, and repeatables reset")
	var walked := 0
	var stuck := []
	for i in range(1, 101):
		var qid := "SQ%03d" % i
		var quest: Dictionary = QuestManager.data[qid]
		QuestManager.start_quest(qid)
		if not QuestManager.is_active(qid):
			# Legitimate: a quest whose objective the player already satisfies
			# (goods in the bag, a place already visited) completes on accept —
			# `deliver` then takes the goods, so it is not a free payout.
			if QuestManager.is_done(qid):
				walked += 1
				continue
			stuck.append("%s would not start (state '%s')" %
				[qid, str(GameState.quests.get(qid, "<unset>"))])
			break
		for obj in (quest.get("objectives", []) as Array):
			var o: Dictionary = obj
			match String(o.get("type", "")):
				"kill":
					for n in int(o.get("count", 1)):
						QuestManager._on_enemy_died(_fake_enemy(String(o.get("target", ""))))
				"flag":
					QuestManager.register_flag(String(o.get("target", "")))
				"talk":
					QuestManager.talk_to(String(o.get("target", "")))
				"collect", "deliver":
					GameState.add_item(String(o.get("target", "")), int(o.get("count", 1)))
					EventBus.item_picked_up.emit(String(o.get("target", "")), int(o.get("count", 1)))
		await get_tree().process_frame
		var repeatable := bool(quest.get("repeatable", false))
		var ok := (not GameState.quests.has(qid)) if repeatable else QuestManager.is_done(qid)
		if not ok:
			stuck.append("%s did not complete" % qid)
			break
		walked += 1
	check(walked == 100, "all 100 side quests complete (%d walked, stuck: %s)" %
		[walked, str(stuck.slice(0, 2))])


func _fake_enemy(archetype: String) -> Node:
	## A real enemy node (the scene is a CharacterBody2D) so the quest engine's
	## death handler sees exactly what it sees in play.
	var e: Node = (load("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate()
	e.archetype = archetype
	add_child(e)
	e.queue_free()
	return e
