extends Node
## Headless full main-story playthrough: q1 -> q4.
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
	await _act2_scorched_ring()
	await _act3_warden_fall()
	await _act4_new_dawn()

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
	check(QuestManager.is_active("q2_ember_omen"), "q2 auto-started (quest chain)")
	check(GameState.gold >= gold_before + 40, "gold reward granted (+40)")
	check(int(GameState.inventory.get("short_sword", 0)) >= 1, "short_sword reward in inventory")
	host.queue_free()


## q2: travel to the scorched ring (flag via arena sighting), confront elder.
func _act2_scorched_ring() -> void:
	print("[playthrough] Act 2 — The Ember Omen")
	player.global_position = Vector2(2700, -1500) + Vector2(0, 500)
	await get_tree().create_timer(1.2).timeout
	check(bool(GameState.quest_flags.get("saw_warden_ring", false)),
		"scorched ring sighted (auto-flag on approach)")

	QuestManager.talk_to("elder_rowan")
	await get_tree().physics_frame
	check(QuestManager.is_done("q2_ember_omen"), "q2 complete")
	check(QuestManager.is_active("q3_warden_fall"), "q3 auto-started")


## q3: enter the arena, warden summons, three phases, lethal blow.
func _act3_warden_fall() -> void:
	print("[playthrough] Act 3 — Fall of the Warden")
	player.global_position = Vector2(2700, -1500)
	await get_tree().create_timer(1.2).timeout
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
	boss.take_hit(99999.0, Vector2.RIGHT)

	# Death tween recycles the boss; poll up to ~3 s.
	for i in 90:
		await get_tree().physics_frame
		if bool(GameState.quest_flags.get("boss_defeated", false)):
			break
	check(bool(GameState.quest_flags.get("boss_defeated", false)), "boss_defeated flag set")
	await get_tree().physics_frame
	check(QuestManager.is_done("q3_warden_fall"), "q3 complete")
	check(QuestManager.is_active("q4_new_dawn"), "q4 auto-started")


## q4: final words with the elder close the arc.
func _act4_new_dawn() -> void:
	print("[playthrough] Act 4 — A New Dawn")
	QuestManager.talk_to("elder_rowan")
	await get_tree().physics_frame
	check(QuestManager.is_done("q4_new_dawn"), "main story complete (q4 done)")
	for q in ["q1_first_light", "q2_ember_omen", "q3_warden_fall", "q4_new_dawn"]:
		check(QuestManager.is_done(q), "%s done" % q)
