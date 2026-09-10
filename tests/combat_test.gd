extends Node
## Headless combat/loot integration test.
## Runs the full project (autoloads active), forces an enemy kill, and asserts
## XP, loot pickups, and gold collection all work end-to-end.
## Exits 0 on PASS, 1 on FAIL. Run:
##   godot --headless --path . res://tests/CombatTest.tscn

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
	print("[combat_test] starting...")
	await get_tree().process_frame

	_test_enemy_death_and_loot()
	await get_tree().physics_frame
	await get_tree().physics_frame

	_test_pickup_gold_collection()
	await get_tree().physics_frame

	_test_consumable_inventory()

	_test_equipment_stats()

	_test_consumable_use()

	_test_talents()

	_test_quests_and_dialogue()

	_test_save_slots()

	await _test_abilities()

	await _test_world()

	_test_boss_phases_and_death()
	await get_tree().physics_frame

	_report()


func _test_enemy_death_and_loot() -> void:
	print("[combat_test] enemy death + loot")
	var host := Node2D.new()
	add_child(host)

	# Player present so the world is realistic (group "player").
	var player: Player = load("res://scenes/player/player.tscn").instantiate()
	add_child(player)
	player.global_position = Vector2(0, 0)

	var enemy: Enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	host.add_child(enemy)
	enemy.global_position = Vector2(120, 0)
	enemy.setup_archetype("grunt")

	check(enemy.max_hp > 0.0, "grunt has positive max_hp")
	check(enemy.archetype == "grunt", "archetype applied")

	var level_before := GameState.level
	var xp_before := GameState.xp

	# Lethal hit -> should die, award XP, drop loot pickups.
	enemy.take_hit(9999.0, Vector2.RIGHT)

	# Loot is dropped synchronously at the start of _die().
	var pickups := 0
	for child in host.get_children():
		if child is Pickup:
			pickups += 1
	check(pickups >= 1, "death produced >=1 loot pickup (got %d)" % pickups)

	var gained := (GameState.level > level_before) or (GameState.xp > xp_before)
	check(gained, "XP/level increased after kill")


func _test_pickup_gold_collection() -> void:
	print("[combat_test] gold pickup collection")
	var host := Node2D.new()
	add_child(host)
	var player: Player = get_tree().get_first_node_in_group("player") as Player
	if player == null:
		player = load("res://scenes/player/player.tscn").instantiate()
		add_child(player)
		player.global_position = Vector2.ZERO

	var gold_before := GameState.gold
	var pickup: Pickup = load("res://scenes/world/pickup.tscn").instantiate()
	host.add_child(pickup)
	pickup.global_position = player.global_position
	pickup.setup_gold(25)

	# Drive collection deterministically (physics-overlap path is covered by
	# the same _on_body_entered handler).
	pickup._on_body_entered(player)
	await get_tree().process_frame

	check(GameState.gold == gold_before + 25, "gold increased by 25 (was %d, now %d)" % [gold_before, GameState.gold])
	check(not is_instance_valid(pickup) or pickup.is_queued_for_deletion(), "gold pickup freed after collection")


func _test_consumable_inventory() -> void:
	print("[combat_test] consumable inventory")
	var before: int = int(GameState.inventory.get("health_potion", 0))
	GameState.add_item("health_potion", 1)
	check(int(GameState.inventory.get("health_potion", 0)) == before + 1, "potion stacked in inventory")
	check(GameState.remove_item("health_potion", 1), "potion removable")
	check(int(GameState.inventory.get("health_potion", 0)) == before, "stack restored after removal")


func _test_equipment_stats() -> void:
	print("[combat_test] equipment affects stats")
	var atk_before := GameState.attack()
	var def_before := GameState.defense()

	GameState.add_item("short_sword", 1)
	check(GameState.equip("short_sword"), "equipping short_sword succeeds")
	check(GameState.equipment["weapon"] == "short_sword", "weapon slot filled")
	check(GameState.attack() == atk_before + 4.0, "attack +4 from short_sword (was %.1f, now %.1f)" % [atk_before, GameState.attack()])

	check(GameState.unequip("weapon"), "unequipping weapon succeeds")
	check(GameState.attack() == atk_before, "attack restored after unequip")
	check(int(GameState.inventory.get("short_sword", 0)) >= 1, "sword returned to inventory")

	GameState.add_item("leather_armor", 1)
	check(GameState.equip("leather_armor"), "equipping leather_armor succeeds")
	check(GameState.defense() == def_before + 3.0, "defense +3 from leather_armor")
	GameState.unequip("armor")  # restore baseline for later tests


func _test_consumable_use() -> void:
	print("[combat_test] consumable use")
	GameState.hp = 10.0
	GameState.add_item("health_potion", 1)
	var before: int = int(GameState.inventory.get("health_potion", 0))
	check(GameState.use_item("health_potion"), "using health_potion succeeds")
	check(GameState.hp == 50.0, "healed 10 -> 50 (now %.0f)" % GameState.hp)
	check(int(GameState.inventory.get("health_potion", 0)) == before - 1, "potion consumed")


func _test_talents() -> void:
	print("[combat_test] talent allocation + effects")
	# Guarantee points to spend regardless of earlier XP levels.
	GameState.talent_points += 3

	var atk0 := GameState.attack()
	check(GameState.spend_talent("combat"), "allocating a combat point succeeds")
	check(GameState.node_active("combat", 1), "Power Strikes active at 1 combat point")
	check(GameState.attack() == atk0 + 4.0, "+4 attack from Power Strikes")

	check(GameState.attack_cooldown_mult() == 1.0, "no cooldown bonus before tier 3")
	GameState.spend_talent("combat")
	GameState.spend_talent("combat")
	check(GameState.node_active("combat", 3), "Swift Strikes active at 3 points")
	check(GameState.attack_cooldown_mult() == 0.8, "attack cooldown -20% at tier 3")

	check(GameState.mp_regen_per_sec() == 0.0, "no MP regen without Clarity")
	GameState.talent_points += 2
	GameState.spend_talent("magic")
	GameState.spend_talent("magic")
	check(GameState.mp_regen_per_sec() == 0.6, "Clarity grants 0.6 MP/s")
	check(GameState.potion_mult() == 1.0, "no potion bonus before Potent Brews")


func _test_quests_and_dialogue() -> void:
	print("[combat_test] quest flow + dialogue picking")
	check(not QuestManager.is_active("q1_first_light"), "q1 inactive before start")
	QuestManager.start_quest("q1_first_light")
	check(QuestManager.is_active("q1_first_light"), "q1 started")
	check(String(DialogueDB.pick("elder_rowan").get("id", "")) == "elder_q1_progress",
		"elder reminds while kills pending")

	var host := Node2D.new()
	add_child(host)
	for i in 3:
		var e: Enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
		host.add_child(e)
		e.global_position = Vector2(-2000, -2000)
		e.setup_archetype("grunt")
		e.take_hit(9999.0, Vector2.RIGHT)
	check(QuestManager.objective_count("q1_first_light", "kill_grunts") == 3, "kill objective tracked 3/3")
	check(bool(GameState.quest_flags.get("q1_first_light_kill_grunts", false)), "auto-flag on objective done")
	check(String(DialogueDB.pick("elder_rowan").get("id", "")) == "elder_q1_report",
		"report dialogue unlocked after kills")

	var gold_before := GameState.gold
	QuestManager.complete_objective("q1_first_light", "report_elder")
	check(QuestManager.is_done("q1_first_light"), "q1 completed")
	check(QuestManager.is_active("q2_ember_omen"), "q2 auto-started")
	check(GameState.gold == gold_before + 40, "q1 gold reward (+40)")
	check(int(GameState.inventory.get("short_sword", 0)) >= 1, "q1 item reward delivered")

	check(String(DialogueDB.pick("elder_rowan").get("id", "")) == "elder_q2_brief", "q2 briefing dialogue")
	QuestManager.register_flag("saw_warden_ring")
	check(QuestManager.objective_count("q2_ember_omen", "reach_ring") == 1, "ring flag completes objective")
	check(String(DialogueDB.pick("elder_rowan").get("id", "")) == "elder_q2_choice",
		"branching choice dialogue unlocked")

	QuestManager.register_flag("vow_mercy")  # simulate the player's choice
	QuestManager.complete_objective("q2_ember_omen", "confront_truth")
	check(QuestManager.is_active("q3_warden_fall"), "q3 started after the truth")

	QuestManager.register_flag("boss_defeated")
	check(QuestManager.is_active("q4_new_dawn"), "q4 started after boss falls")
	check(String(DialogueDB.pick("elder_rowan").get("id", "")) == "elder_q4_end_mercy",
		"mercy ending picked via choice flag")
	QuestManager.complete_objective("q4_new_dawn", "final_words")
	check(QuestManager.is_done("q4_new_dawn"), "main questline complete")
	check(String(DialogueDB.pick("elder_rowan").get("id", "")) == "elder_after_end", "post-game dialogue")
	check(bool(GameState.quest_flags.get("vow_mercy", false)), "meaningful choice flag persisted")

	# Side + repeatable quests
	QuestManager.start_quest("s_emberling_run")
	check(QuestManager.is_active("s_emberling_run"), "repeatable side quest started")
	var host2 := Node2D.new()
	add_child(host2)
	for i in 4:
		var e: Enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
		host2.add_child(e)
		e.global_position = Vector2(-2400, -2400)
		e.setup_archetype("emberling")
		e.take_hit(9999.0, Vector2.RIGHT)
	check(QuestManager.objective_count("s_emberling_run", "kill_emberlings") == 4, "repeatable kill objective 4/4")
	QuestManager.complete_objective("s_emberling_run", "report_kael_run")
	check(not GameState.quests.has("s_emberling_run"), "repeatable quest fully reset after completion")
	QuestManager.start_quest("s_emberling_run")
	check(QuestManager.is_active("s_emberling_run"), "repeatable quest can be re-accepted")
	check(QuestManager.marker_for("hunter_kael"), "marker shown for pending talk objective")


func _test_save_slots() -> void:
	print("[combat_test] save slots + reset")
	var player: Player = get_tree().get_first_node_in_group("player")
	check(player != null, "player exists for save test")
	GameState.gold = 777
	check(SaveSystem.save_game(player, 2), "save to slot 2")
	check(SaveSystem.has_save(2), "slot 2 file exists")
	var sum := SaveSystem.slot_summary(2)
	check(bool(sum.get("exists", false)) and int(sum.get("gold", 0)) == 777, "slot summary round-trip")
	GameState.gold = 5
	check(SaveSystem.load_game(player, 2), "load slot 2")
	check(GameState.gold == 777, "gold restored from slot 2")
	GameState.reset()
	check(GameState.gold == 50 and GameState.level == 1, "reset yields fresh state")
	check(GameState.quests.is_empty() and GameState.quest_flags.size() == 1 \
		and bool(GameState.quest_flags.get("wp_camp", false)), "reset clears story state (keeps camp waypoint)")


func _test_abilities() -> void:
	print("[combat_test] abilities (whirlwind + firebolt)")
	var player: Player = get_tree().get_first_node_in_group("player")
	GameState.mp = GameState.max_mp()

	var host := Node2D.new()
	add_child(host)
	var e: Enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	host.add_child(e)
	e.global_position = player.global_position + Vector2(50, 0)
	e.setup_archetype("grunt")

	var mp_before := GameState.mp
	player.cast_whirlwind()
	check(e.hp < e.max_hp, "whirlwind damaged nearby enemy")
	check(GameState.mp == mp_before - Player.WHIRL_MP, "whirlwind MP cost applied")
	check(float(player.cooldowns()["whirl"]) > 0.9, "whirlwind on cooldown after cast")

	mp_before = GameState.mp
	player.facing = Vector2.RIGHT
	player.cast_firebolt()
	check(GameState.mp == mp_before - Player.BOLT_MP, "firebolt MP cost applied")
	check(float(player.cooldowns()["bolt"]) > 0.9, "firebolt on cooldown after cast")

	# Friendly projectile damages an enemy hurtbox.
	var e2: Enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	host.add_child(e2)
	e2.global_position = player.global_position + Vector2(200, 0)
	e2.setup_archetype("grunt")
	# Melee: hurtbox routes take_hit to its owner (regression guard).
	var melee_target: Enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	host.add_child(melee_target)
	melee_target.setup_archetype("grunt")
	player.facing = Vector2.RIGHT
	melee_target.global_position = player.global_position + Vector2(48, 0)
	player.attack_shape.disabled = false
	await get_tree().physics_frame
	var melee_before := melee_target.hp
	player._resolve_attack_hits()
	await get_tree().process_frame
	check(melee_target.hp < melee_before, "melee hit lands via hurtbox routing")
	player.attack_shape.disabled = true

	PoolManager.spawn_projectile(e2.global_position, Vector2.RIGHT, 12.0, 400.0, Color.WHITE, true)
	await get_tree().physics_frame
	var proj: Projectile = null
	for child in get_tree().root.get_node("PoolManager").get_node("Projectiles").get_children():
		if child is Projectile and child.visible and (child as Projectile).friendly:
			proj = child
			break
	if proj != null:
		proj._armed = true
		proj._on_area_entered(e2.get_node("Hurtbox"))
	check(e2.hp < e2.max_hp, "friendly projectile damages enemy hurtbox")

	# No MP -> no cast.
	GameState.mp = 0.0
	player._whirl_cd = 0.0
	player.cast_whirlwind()
	check(GameState.mp == 0.0, "cannot cast whirlwind without MP")
	GameState.mp = GameState.max_mp()


func _test_world() -> void:
	print("[combat_test] authored world + interactables")
	# Clear stale standalone players from earlier sections, then boot the real
	# game scene (streamer, camp, day/night, dialogue, travel) as the harness.
	for p in get_tree().get_nodes_in_group("player"):
		p.queue_free()
	await get_tree().physics_frame
	var main_node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main_node)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var player = main_node.get_node("Player")

	# Authored chunk pipeline active (Tiled JSON -> .tscn).
	check(ResourceLoader.exists("res://world/chunks/chunk_0_0.tscn"),
		"authored chunk scene exists (Tiled pipeline)")
	var chunk: Node = null
	for child in main_node.get_node("World/ChunkStreamer").get_children():
		if String(child.name) == "chunk_0_0":
			chunk = child
	check(chunk != null, "chunk (0,0) streamed from authored scene")
	if chunk != null:
		var renderer := chunk.get_node("Renderer") as ChunkRenderer
		check(renderer.tiles.size() == 1024, "chunk tile grid populated (32x32)")
		check(chunk.get_node("Solids").get_child_count() > 0, "chunk has collision rects")
		var found_sign := false
		for o in chunk.get_node("Objects").get_children():
			if o is Sign:
				found_sign = true
		check(found_sign, "authored sign present in village chunk")

	# Chest lifecycle: closed -> loot + flag -> idempotent.
	var chest := Chest.new()
	chest.chest_id = "test_chest"
	chest.gold = 25
	chest.item_id = "health_potion"
	add_child(chest)
	chest.global_position = player.global_position + Vector2(-400, -400)
	check(not chest.is_opened(), "chest starts closed")
	chest._on_interact()
	check(chest.is_opened(), "chest opened after interact")
	check(bool(GameState.quest_flags.get("chest_test_chest_opened", false)), "chest flag persisted")
	chest._on_interact()
	check(chest.is_opened(), "second interact idempotent")

	# Lever opens matching gate.
	var lever := Lever.new()
	lever.lever_id = "t"
	lever.gate_id = "tg"
	add_child(lever)
	lever.position = Vector2(-600, -600)
	var gate := SecretGate.new()
	gate.gate_id = "tg"
	add_child(gate)
	gate.position = Vector2(-620, -600)
	await get_tree().physics_frame
	lever._on_interact()
	await get_tree().process_frame
	check(bool(GameState.quest_flags.get("gate_tg_open", false)), "lever sets gate flag")
	await get_tree().create_timer(0.9).timeout  # fade-out tween then queue_free
	check(not is_instance_valid(gate) or gate.is_queued_for_deletion(), "gate removed after lever")

	# Waypoint unlock + registry + names.
	var wp := Waypoint.new()
	wp.wp_id = "t_wp"
	wp.wp_name = "Test Fire"
	add_child(wp)
	wp.position = Vector2(-700, -700)
	await get_tree().physics_frame
	check(Waypoint.registry.has("t_wp"), "waypoint registered position")
	check(not wp.is_unlocked(), "waypoint locked before lighting")
	wp._on_interact()
	check(wp.is_unlocked(), "waypoint unlocked after lighting")
	check(String(Waypoint.names.get("t_wp", "")) == "Test Fire", "waypoint name registered")
	if main_node.travel_ui.visible:
		main_node.travel_ui.close()

	# Fast travel teleports the player (camp waypoint is lit by default).
	var before: Vector2 = player.global_position
	main_node._on_travel_to("camp")
	check(player.global_position.distance_to(before) > 100.0, "fast travel teleports player")

	# Sign routes into the dialogue box.
	var sign := Sign.new()
	sign.title = "Test"
	sign.text = "hello"
	add_child(sign)
	main_node._on_world_interacted(sign)
	check(main_node.dialogue_box.visible, "sign opens dialogue box")
	main_node.dialogue_box._finish()

	# Day/night cycle running.
	check(main_node.day_night != null and main_node.day_night.canvas != null,
		"day/night CanvasModulate active")

	# Real minimap samples authored terrain.
	var mm = main_node.get_node("HUD").minimap
	check(mm != null, "HUD has real minimap")
	var sample: Color = mm._sample(Vector2(700, 330))
	check(sample.a > 0.01, "minimap samples terrain color at spawn")

	# World flags (chests/levers/waypoints) survive save/load.
	var had_flag := bool(GameState.quest_flags.get("chest_test_chest_opened", false))
	check(had_flag, "chest flag set before save")
	check(SaveSystem.save_game(player), "save with world flags")
	GameState.reset()
	check(not GameState.quest_flags.has("chest_test_chest_opened"), "reset clears world flags")
	check(SaveSystem.load_game(player), "load restores save")
	check(bool(GameState.quest_flags.get("chest_test_chest_opened", false)),
		"chest flag restored from save")


func _test_boss_phases_and_death() -> void:
	print("[combat_test] boss phases + death")
	var host := Node2D.new()
	add_child(host)

	var boss: Boss = load("res://scenes/enemies/boss.tscn").instantiate()
	host.add_child(boss)
	boss.global_position = Vector2(3000, -3000)
	boss.setup_archetype("ember_warden")

	check(boss.behavior == "boss", "boss behavior configured")
	check(boss.max_hp >= 500.0, "boss has a boss-sized HP pool")

	# Phase 1 -> 2 (below 60%).
	boss.take_hit(boss.max_hp * 0.45, Vector2.RIGHT)
	check(boss.phase == 2, "phase 2 below 60%% HP (phase=%d)" % boss.phase)

	# Phase 2 -> 3 (below 25%). Clear transformation i-frames for the test.
	boss._transform_invuln = 0.0
	boss.take_hit(boss.max_hp * 0.4, Vector2.RIGHT)
	check(boss.phase == 3, "phase 3 below 25%% HP (phase=%d)" % boss.phase)

	# Lethal blow -> guaranteed loot (iron_sword + potion + gold).
	boss._transform_invuln = 0.0
	boss.take_hit(99999.0, Vector2.RIGHT)
	var pickups := 0
	var found_iron_sword := false
	for child in host.get_children():
		if child is Pickup:
			pickups += 1
			if (child as Pickup).item_id == "iron_sword":
				found_iron_sword = true
	check(pickups >= 3, "boss death dropped >=3 pickups (got %d)" % pickups)
	check(found_iron_sword, "boss guaranteed iron_sword drop present")


func _report() -> void:
	if failures == 0:
		print("TEST RESULT: PASS (%d checks)" % checks)
		get_tree().quit(0)
	else:
		print("TEST RESULT: FAIL (%d/%d checks failed)" % [failures, checks])
		get_tree().quit(1)
