extends Node
## Headless full main-story playthrough: q1 -> the 100-step chain -> q2 -> q4,
## then a secret found the way a player finds one: by walking onto it.
## Exercises the real flow: dialogue-driven quest starts, kill objectives via
## enemy deaths, auto-flags, boss-arena summon + multi-phase kill, quest
## chaining, rewards (xp/gold/items). Exits 0 on PASS, 1 on FAIL. Run:
##   godot --headless --path . res://tests/PlaythroughTest.tscn

var failures := 0
var checks := 0

var main_node: Node = null
var player: Node2D = null
var arena: BossArena = null


func check(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("  PASS: ", label)
	else:
		failures += 1
		print("  FAIL: ", label)


func _ready() -> void:
	print("[playthrough] starting full main-story validation...")
	await get_tree().process_frame

	main_node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main_node)
	await get_tree().physics_frame
	player = main_node.get_node("Player")
	arena = main_node.get_node_or_null("World/BossArena")
	if arena == null:
		arena = main_node.get_node_or_null("BossArena")
	check(arena != null, "boss arena present in world")

	await _act1_thin_the_slimes()
	await _act1b_the_ash_road()
	await _act2_scorched_ring()
	await _act3_warden_fall()
	await _act4_new_dawn()
	await _act5_secrets()

	print("PLAYTHROUGH RESULT: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(1 if failures > 0 else 0)


## q1: elder starts the quest (dialogue action), 3 grunt kills, report back.
func _act1_thin_the_slimes() -> void:
	print("[playthrough] Act 1 — First Light")
	# First meeting with the elder runs dialogue action start_quest q1.
	QuestManager.start_quest("q1_first_light")
	check(QuestManager.is_active("q1_first_light"), "q1 active after elder dialogue")

	var gold_before := GameState.gold
	var host := Node2D.new()
	add_child(host)
	for i in 3:
		var e: Enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
		host.add_child(e)
		e.global_position = player.global_position + Vector2(60 + i * 30, 0)
		e.setup_archetype("grunt")
		e.take_hit(9999.0, Vector2.RIGHT)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(QuestManager.objective_count("q1_first_light", "kill_grunts") == 3,
		"kill objective counted 3 grunts")
	check(bool(GameState.quest_flags.get("q1_first_light_kill_grunts", false)),
		"auto-flag set when kill objective completed")

	QuestManager.talk_to("elder_rowan")  # dialogue action complete_objective(report_elder)
	await get_tree().physics_frame
	check(QuestManager.is_done("q1_first_light"), "q1 complete after reporting")
	check(QuestManager.is_active("MQ001"), "the 100-step chain starts (MQ001)")
	check(GameState.gold >= gold_before + 40, "gold reward granted (+40)")
	check(int(GameState.inventory.get("short_sword", 0)) >= 1, "short_sword reward in inventory")
	host.queue_free()


## Act 1b: the 100-step chain, walked the way world events would drive it.
func _act1b_the_ash_road() -> void:
	print("[playthrough] Act 1b — the ash road (MQ001-MQ100)")
	var gold_before := GameState.gold
	var xp_level_before := GameState.level
	var host := Node2D.new()
	add_child(host)

	var walker := _ChainWalker.new()
	walker.host = host
	walker.player_pos_callable = func() -> Vector2: return player.global_position
	var walked: int = await walker.walk_all()
	host.queue_free()

	check(walked == 100, "all 100 chain steps completed in order (%d)" % walked)
	check(QuestManager.is_active("q2_ember_omen"), "the Ember Omen starts after the chain")
	check(GameState.level > xp_level_before, "the chain granted levels (L%d -> L%d)" %
		[xp_level_before, GameState.level])
	check(GameState.gold > gold_before, "the chain paid gold (+%d)" %
		int(GameState.gold - gold_before))


class _ChainWalker:
	## Drives the chain through the real quest API — real enemy nodes for kills,
	## the pickup signal for collects, register_flag for travel, talk_to for
	## hand-ins — so the test exercises the same paths the game does.
	var host: Node2D
	var player_pos_callable: Callable

	func _wait(tree: SceneTree) -> void:
		await tree.physics_frame

	func walk_all() -> int:
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		var walked := 0
		for i in range(1, 101):
			var qid := "MQ%03d" % i
			if not QuestManager.is_active(qid):
				return walked
			var quest: Dictionary = QuestManager.data[qid]
			for obj in (quest.get("objectives", []) as Array):
				var o: Dictionary = obj
				var kind := String(o.get("type", ""))
				var target := String(o.get("target", ""))
				var need := int(o.get("count", 1))
				match kind:
					"kill":
						for n in need:
							var e: Enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
							host.add_child(e)
							var pos: Vector2 = player_pos_callable.call()
							e.global_position = pos + Vector2(40 + n * 12, 0)
							e.setup_archetype(target)
							e.take_hit(999999.0, Vector2.RIGHT)
							await tree.physics_frame
					"collect", "deliver":
						GameState.add_item(target, need)
						EventBus.item_picked_up.emit(target, need)
						await tree.physics_frame
					"flag":
						QuestManager.register_flag(target)
						await tree.physics_frame
					"talk":
						QuestManager.talk_to(target)
						await tree.physics_frame
			if i == 65:
				# The fork: pick the protect branch.
				QuestManager.register_flag("protect_mireille")
				QuestManager.register_flag("mireille_decision")
				await tree.physics_frame
			if not QuestManager.is_done(qid):
				print("  [chain] stuck at %s" % qid)
				return walked
			walked += 1
		return walked


## q2: travel to the scorched ring (flag via arena sighting), confront elder.
func _act2_scorched_ring() -> void:
	print("[playthrough] Act 2 — The Ember Omen")
	player.global_position = Vector2(2700, -1500) + Vector2(0, 500)
	var sighted := await _await_until(
		func() -> bool: return bool(GameState.quest_flags.get("saw_warden_ring", false)), 4.0)
	check(sighted, "scorched ring sighted (auto-flag on approach)")

	QuestManager.talk_to("elder_rowan")
	await get_tree().physics_frame
	check(QuestManager.is_done("q2_ember_omen"), "q2 complete")
	check(QuestManager.is_active("q3_warden_fall"), "q3 auto-started")


## q3: enter the arena, warden summons, three phases, lethal blow.
func _act3_warden_fall() -> void:
	print("[playthrough] Act 3 — Fall of the Warden")
	player.global_position = Vector2(2700, -1500)
	await _await_until(func() -> bool: return arena != null and arena.boss != null, 5.0)
	check(arena != null and arena.boss != null, "Ember Warden summoned on arena entry")
	if arena == null or arena.boss == null:
		return
	var boss: Boss = arena.boss
	check(boss.phase == 1, "warden starts in phase 1")

	boss.take_hit(boss.max_hp * 0.45, Vector2.RIGHT)
	check(boss.phase == 2, "phase 2 triggered")
	boss._transform_invuln = 0.0
	boss.take_hit(boss.max_hp * 0.4, Vector2.RIGHT)
	check(boss.phase == 3, "phase 3 triggered")
	boss._transform_invuln = 0.0
	# Step out of melee range so the warden cannot kill the test player
	# (a death screen would pause the tree and stall the death tween).
	player.global_position = Vector2(2700, -2600)
	boss.take_hit(boss.max_hp * 2.0, Vector2.RIGHT)  # percent, not a magic number

	# Death tween recycles the boss; poll up to ~3 s.
	for i in 90:
		await get_tree().physics_frame
		if bool(GameState.quest_flags.get("boss_defeated", false)):
			break
	check(bool(GameState.quest_flags.get("boss_defeated", false)), "boss_defeated flag set")
	await get_tree().physics_frame
	check(QuestManager.is_done("q3_warden_fall"), "q3 complete")
	check(QuestManager.is_active("q4_new_dawn"), "q4 auto-started")


## Act 5 (Phase F6): a secret, found by walking over it in the real world.
func _act5_secrets() -> void:
	print("[playthrough] Act 5 — What the World Hides")
	# Acts 3-4 leave the player standing in the warden's arena, so the tree can be
	# paused on the death screen. Take the game's own respawn path rather than
	# writing around it: same code the button runs.
	var death: DeathScreen = main_node.get_node_or_null("DeathScreen")
	if get_tree().paused:
		if death != null:
			death._hide_screen()
			death.respawn_requested.emit()
		else:
			get_tree().paused = false
		check(not get_tree().paused, "the world is running again (respawned at camp)")
	await get_tree().physics_frame

	var streamer: ChunkStreamer = main_node.get_node_or_null("World/ChunkStreamer")
	if streamer == null:
		streamer = main_node.get_node_or_null("ChunkStreamer")
	check(streamer != null, "chunk streamer present")
	if streamer == null:
		return

	# Stand where the first secret is, and let the world stream in around us.
	var sid := String(SecretsDB.all()[0])
	var target := SecretsDB.position_of(sid)
	var gold_before := GameState.gold
	var found_before := SecretsDB.found_count()
	GameState.quest_flags.erase(SecretsDB.flag_of(sid))
	player.global_position = target + Vector2(0, 220)
	await _await_until(func() -> bool: return _count_secret_sites(streamer) > 0, 4.0)
	var sites := _count_secret_sites(streamer)
	check(sites > 0, "secrets exist in the live world (%d sites near %s)" % [sites, sid])

	# Walk onto it: the player's own body overlap is what finds a cache. Wait for
	# the *find*, not merely for the site node: a site that streams in underneath a
	# player who is already standing there is found a physics step later, and the
	# node-only wait made this suite flake on CI's timing (run 34597447299).
	player.global_position = target
	await _await_until(func() -> bool: return _find_site(streamer, sid) != null, 3.0)
	await _await_until(func() -> bool: return SecretsDB.is_found(sid), 3.0)
	await _await_until(func() -> bool: return SecretsDB.found_count() == found_before + 1, 2.0)
	var probe := _find_site(streamer, sid)
	check(probe != null, "the secret's own site is streamed in where it sits (%s)" % sid)
	if probe != null:
		check(probe.global_position.distance_to(target) < 1.0,
			"the site stands at the secret's authored position")
	check(SecretsDB.is_found(sid), "walking over the secret found it (%s)" % sid)
	check(SecretsDB.found_count() == found_before + 1, "the world's found counter rose")
	check(GameState.gold >= gold_before, "the find did not cost anything")

	# Leave and come back: the chunk reloads, and the secret stays found.
	await get_tree().physics_frame   # let any reward land before it is measured
	await get_tree().physics_frame
	player.global_position = target + Vector2(4000, 0)
	await _await_until(func() -> bool: return _find_site(streamer, sid) == null, 4.0)
	var gold_after := GameState.gold
	player.global_position = target
	await _await_until(func() -> bool: return _find_site(streamer, sid) != null, 4.0)
	check(SecretsDB.is_found(sid), "the secret is still found after a chunk reload")
	check(GameState.gold == gold_after, "re-streaming the chunk did not pay twice")


## Poll a condition at physics rate until it holds or the budget runs out.
## Fixed sleeps made this suite flaky under load (chunk streaming lags CPU
## contention); every world-state wait now retries instead of guessing a delay.
func _await_until(cond: Callable, seconds: float) -> bool:
	var frames := int(seconds * 60.0)
	for i in frames:
		if bool(cond.call()):
			return true
		await get_tree().physics_frame
	return bool(cond.call())


func _find_site(node: Node, sid: String) -> SecretSite:
	for child in node.get_children():
		if child is SecretSite and String(child.secret_id) == sid:
			return child
		var deeper := _find_site(child, sid)
		if deeper != null:
			return deeper
	return null


func _count_secret_sites(node: Node) -> int:
	var n := 0
	for child in node.get_children():
		if child is SecretSite:
			n += 1
		else:
			n += _count_secret_sites(child)
	return n


## q4: final words with the elder close the arc.
func _act4_new_dawn() -> void:
	print("[playthrough] Act 4 — A New Dawn")
	QuestManager.talk_to("elder_rowan")
	await get_tree().physics_frame
	check(QuestManager.is_done("q4_new_dawn"), "main story complete (q4 done)")
	for q in ["q1_first_light", "q2_ember_omen", "q3_warden_fall", "q4_new_dawn"]:
		check(QuestManager.is_done(q), "%s done" % q)
