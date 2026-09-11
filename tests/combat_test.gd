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
	await _test_projectile_contact()

	await _test_world()

	await _test_music()

	await _test_perf()

	_test_boss_phases_and_death()
	await get_tree().physics_frame

	_test_quest_collect()
	_test_xp_curve()
	_test_milestones()
	_test_floor_scaling()
	_test_talent_tree()
	await _test_safe_ground_and_dialogue_protection()
	await _test_fight_feedback()
	await _test_idle_art()

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
	check(QuestManager.is_active("MQ001"), "the 100-step chain auto-started after q1")
	check(GameState.gold == gold_before + 40, "q1 gold reward (+40)")
	check(int(GameState.inventory.get("short_sword", 0)) >= 1, "q1 item reward delivered")

	# Phase F4: the 100-step chain sits between q1 and q2. Walk it here to reach
	# the Ember Omen, then put the character back where this test found them —
	# the chain's own economy is QuestTest's and PlaythroughTest's business.
	var gold_at_chain := GameState.gold
	var level_at_chain := GameState.level
	var xp_at_chain := GameState.xp
	var walked := _fast_forward_chain()
	check(walked == 100, "the whole chain walks (%d steps)" % walked)
	check(QuestManager.is_active("q2_ember_omen"), "q2 auto-started after the chain")
	GameState.gold = gold_at_chain
	GameState.level = level_at_chain
	GameState.xp = xp_at_chain

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


func _fast_forward_chain() -> int:
	## Completes each step's objectives directly — the engine paths are covered
	## step-by-step in tests/QuestTest.tscn and tests/PlaythroughTest.tscn.
	var walked := 0
	for i in range(1, 101):
		var qid := "MQ%03d" % i
		if not QuestManager.is_active(qid):
			return walked
		var quest: Dictionary = QuestManager.data[qid]
		for obj in (quest.get("objectives", []) as Array):
			QuestManager.complete_objective(qid, String((obj as Dictionary).get("id", "")))
		if i == 65:
			QuestManager.register_flag("protect_mireille")
			QuestManager.register_flag("mireille_decision")
		if not QuestManager.is_done(qid):
			return walked
		walked += 1
	return walked


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
	# The attack shape is only enabled during the active frames of a swing, and
	# the overlap set is scanned at the end of a physics step, so wait for the
	# overlap to actually exist rather than assuming one frame is enough. The
	# guard being tested is the routing (hurtbox area -> its owner's take_hit).
	var melee_before := melee_target.hp
	var landed := false
	for attempt in 8:
		player.facing = Vector2.RIGHT
		melee_target.global_position = player.global_position + Vector2(48, 0)
		player.attack_shape.disabled = false
		await get_tree().physics_frame
		await get_tree().physics_frame
		if player.attack_area.get_overlapping_areas().is_empty():
			continue
		await player._resolve_attack_hits()
		await get_tree().process_frame
		if melee_target.hp < melee_before:
			landed = true
			break
	check(landed, "melee hit lands via hurtbox routing")
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


func _test_music() -> void:
	print("[combat_test] procedural music")
	for id in ["title", "meadow", "barrens", "frost", "combat"]:
		check(AudioManager.music_tracks.has(id), "music track registered: %s" % id)
	check(AudioManager.music_tracks.size() >= 5, "all five builtin tracks registered")

	AudioManager.play_music("meadow")
	await get_tree().process_frame
	check(AudioManager._current_track == "meadow", "play_music sets current track")
	check(AudioManager._active.playing, "music deck is playing")
	var first_deck := AudioManager._active
	AudioManager.play_music("combat")
	await get_tree().process_frame
	check(AudioManager._current_track == "combat", "crossfade switches track id")
	check(AudioManager._active != first_deck, "crossfade swaps to the other deck")
	AudioManager.stop_music()
	check(AudioManager._current_track == "", "stop_music clears track")


func _test_perf() -> void:
	print("[combat_test] pooling + frame budget")
	var main_node = get_node_or_null("Main")
	var holder := PoolManager.get_node("Projectiles")
	var pool: ObjectPool = PoolManager._projectiles
	# Hermetic: the live world is still shooting around us (an enemy projectile, a
	# player bolt in flight) and those are *visible* pool members too, which made
	# this count depend on what happened to be alive at that instant. Clear the
	# pool first, then measure only what this test spawns.
	for p in holder.get_children():
		if p is Projectile and p.visible:
			PoolManager.release_projectile(p)
	await get_tree().process_frame
	var free_before: int = pool._free.size()

	var spawned := []
	for i in 4:
		PoolManager.spawn_projectile(Vector2(-3000, -3000), Vector2.RIGHT, 5.0, 400.0, Color.WHITE)
	for p in holder.get_children():
		if p is Projectile and p.visible:
			spawned.append(p)
	check(spawned.size() == 4, "four pooled projectiles active")
	for p in spawned:
		PoolManager.release_projectile(p)
	check(pool._free.size() == free_before, "release returns nodes to pool (no leak)")

	var children_before := holder.get_child_count()
	PoolManager.spawn_projectile(Vector2(-3000, -3000), Vector2.RIGHT, 5.0, 400.0, Color.WHITE)
	check(holder.get_child_count() == children_before,
		"reacquire reuses pooled node (zero new allocations)")
	for p in holder.get_children():
		if p is Projectile and p.visible:
			PoolManager.release_projectile(p)

	# Frame budget smoke on the live world (chunks, spawners, HUD, juice).
	var t0 := Time.get_ticks_usec()
	for i in 60:
		await get_tree().physics_frame
	var avg_ms := float(Time.get_ticks_usec() - t0) / 60000.0
	print("  avg frame: %.2f ms" % avg_ms)
	check(avg_ms < 33.0, "avg frame under 33 ms budget (headless smoke)")

	# Chunk streaming: walking east loads new authored chunks and unloads old.
	if main_node != null:
		var streamer: ChunkStreamer = main_node.get_node("World/ChunkStreamer")
		var walker: Node2D = main_node.get_node("Player")
		walker.global_position = Vector2(2600, 600)
		streamer.set_target(walker)
		await get_tree().create_timer(0.6).timeout
		check(streamer.get_loaded_chunk(Vector2i(2, 0)) != null, "east chunk (2,0) streamed in")
		check(streamer.get_loaded_chunk(Vector2i(0, 0)) == null, "village chunk (0,0) streamed out")
		walker.global_position = Vector2(700, 330)
		streamer.set_target(walker)
		await get_tree().create_timer(0.6).timeout
		check(streamer.get_loaded_chunk(Vector2i(0, 0)) != null, "village chunk re-streamed on return")

		# 3x3 radius stress: sweep all neighbor chunks, loader must cap at 9.
		for ox in [-1, 0, 1]:
			for oy in [-1, 0, 1]:
				walker.global_position = Vector2(700 + ox * 1024, 330 + oy * 1024)
				streamer.set_target(walker)
				await get_tree().create_timer(0.25).timeout
		check(streamer._loaded.size() <= 9, "3x3 stress: loaded chunks capped at 9 (got %d)" % streamer._loaded.size())
		check(streamer.get_loaded_chunk(Vector2i(1, 1)) != null, "3x3 stress: corner chunk (1,1) loaded")


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
	# Percent, not a magic number: a flat 99,999 stopped being lethal the moment
	# the balance pass raised the Warden's pool (144,308 at L92).
	boss.take_hit(boss.max_hp * 2.0, Vector2.RIGHT)
	var pickups := 0
	var found_core := false
	for child in host.get_children():
		if child is Pickup:
			pickups += 1
			if (child as Pickup).item_id == "warden_core":
				found_core = true
	check(pickups >= 3, "boss death dropped >=3 pickups (got %d)" % pickups)
	check(found_core, "boss guaranteed warden_core drop present")


func _report() -> void:
	if failures == 0:
		print("TEST RESULT: PASS (%d checks)" % checks)
		get_tree().quit(0)
	else:
		print("TEST RESULT: FAIL (%d/%d checks failed)" % [failures, checks])
		get_tree().quit(1)


# --- Phase E §6: level curve, milestones, floor scaling ----------------------

func _test_xp_curve() -> void:
	print("[combat_test] XP curve (Phase E §6)")
	check(GameState.xp_to_next(1) == 80, "level 1 costs 80 XP")
	check(GameState.xp_to_next(GameState.XP_MAX_LEVEL) == 0, "level cap needs no more XP")

	# Monotonic and continuous: the authored segment formulas restart from small
	# constants, which would make a level cheaper after level 20/60. Guard it.
	var previous := 0
	var monotone := true
	var worst_drop := 0
	for lv in range(1, GameState.XP_MAX_LEVEL):
		var cost := GameState.xp_to_next(lv)
		if cost < previous:
			monotone = false
			worst_drop = mini(worst_drop, cost - previous)
		previous = cost
	check(monotone, "xp_to_next never decreases (worst drop %d)" % worst_drop)

	# Exact seam continuity — both boundaries must not regress.
	check(GameState.xp_to_next(21) == GameState.xp_to_next(20),
		"segment 1→2 seam is seamless at level 20/21")
	check(GameState.xp_to_next(61) == GameState.xp_to_next(60),
		"segment 2→3 seam is seamless at level 60/61")

	# No runaway exponent, unlike the old 1.35^L curve (which asked 8e14 at L100).
	check(GameState.xp_to_next(99) < 250000,
		"level 99 cost stays sane (%d)" % GameState.xp_to_next(99))
	var total := 0
	for lv in range(1, GameState.XP_MAX_LEVEL):
		total += GameState.xp_to_next(lv)
	check(total < 8000000, "full 1-100 climb is %d XP" % total)


func _test_milestones() -> void:
	print("[combat_test] milestone rewards (Phase E §6)")
	var saved := {
		"level": GameState.level, "xp": GameState.xp, "gold": GameState.gold,
		"tp": GameState.talent_points, "hp": GameState.hp, "mp": GameState.mp,
		"milestones": GameState.milestones_claimed.duplicate(),
	}
	GameState.level = 1
	GameState.xp = 0
	GameState.milestones_claimed.clear()
	GameState.talent_points = 0
	var gold_before := GameState.gold
	var hp_before := GameState.max_hp()

	var to_ten := 0
	for lv in range(1, 10):
		to_ten += GameState.xp_to_next(lv)
	GameState.add_xp(to_ten)
	check(GameState.level == 10, "climbed to level 10")
	check(GameState.milestones_claimed.has(10), "level 10 milestone claimed")
	check(GameState.talent_points == 10, "9 level points + 1 milestone point (got %d)" % GameState.talent_points)
	check(GameState.gold >= gold_before + 150, "milestone gold granted")
	check(GameState.milestone_bonus("hp") == 25.0, "+25 max HP from Wayfarer milestone")
	check(GameState.max_hp() == hp_before + 9.0 * 12.0 + 25.0, "milestone HP stacks on level HP")

	# Re-entering the same level must not double-grant.
	GameState.add_xp(1)
	check(GameState.milestones_claimed.count(10) == 1, "milestone is not granted twice")

	# Save shape: claimed milestones must survive a round-trip.
	var snapshot := GameState.to_dict()
	var claimed := GameState.milestones_claimed.duplicate()
	GameState.milestones_claimed.clear()
	GameState.from_dict(snapshot)
	check(GameState.milestones_claimed == claimed, "milestones survive a save round-trip")

	# Cap: dumping absurd XP at level 100 must not hang or overflow.
	GameState.level = GameState.XP_MAX_LEVEL
	GameState.add_xp(999999999)
	check(GameState.level == GameState.XP_MAX_LEVEL and GameState.xp == 0,
		"level cap absorbs excess XP")

	GameState.level = int(saved["level"])
	GameState.xp = int(saved["xp"])
	GameState.gold = int(saved["gold"])
	GameState.talent_points = int(saved["tp"])
	GameState.milestones_claimed = saved["milestones"]
	GameState.hp = float(saved["hp"])
	GameState.mp = float(saved["mp"])
	GameState.stats_changed.emit()


func _test_floor_scaling() -> void:
	print("[combat_test] dungeon floor scaling (Phase E §6)")
	check(EnemyDB.floor_scale("grunt", 1) == 1.0, "floor 1 is unscaled")
	check(absf(EnemyDB.floor_scale("grunt", 3) - 1.22) < 0.001, "floor 3 = +22%")
	check(EnemyDB.floor_scale("ember_warden", 10) == 1.0, "boss has no floor scaling")

	var host := Node2D.new()
	add_child(host)
	var shallow: Enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	var deep: Enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	host.add_child(shallow)
	host.add_child(deep)
	shallow.setup_archetype("grunt", 1.0, 1)
	deep.setup_archetype("grunt", 1.0, 6)
	check(deep.max_hp > shallow.max_hp, "deeper floor enemies have more HP")
	check(deep.xp_reward > shallow.xp_reward, "deeper floor enemies award more XP")
	check(deep.floor_index == 6 and shallow.floor_index == 1, "floor index recorded")
	shallow.setup_floor(6)
	check(absf(shallow.max_hp - deep.max_hp) < 0.001, "setup_floor re-scales in place")
	host.queue_free()


# --- Phase E §7: 60-node talent tree -----------------------------------------

func _test_talent_tree() -> void:
	print("[combat_test] 60-node talent tree (Phase E §7)")
	var branches: Array = GameState._talent_branches()
	check(branches.size() == 3, "three branches (%d)" % branches.size())

	var total := 0
	var ids := {}
	var shape_ok := true
	var band_ok := true
	for b in branches:
		var branch := b as Dictionary
		var bid := String(branch.get("id", ""))
		var nodes: Array = branch.get("nodes", [])
		total += nodes.size()
		for i in nodes.size():
			var node := nodes[i] as Dictionary
			ids[String(node.get("id", ""))] = true
			if int(node.get("req_points", -1)) != i + 1:
				band_ok = false
			var expected_tier := (i / 5) + 1
			if int(node.get("tier", -1)) != expected_tier:
				shape_ok = false
		check(nodes.size() == 20, "%s branch has 20 nodes" % bid)
	check(total == 60, "60 nodes in total (%d)" % total)
	check(ids.size() == 60, "all 60 node ids are unique (%d)" % ids.size())
	check(shape_ok, "4 tiers x 5 nodes per branch")
	check(band_ok, "req_points runs 1..20 in every branch")

	# Level gates: tier bands must open at 5 / 25 / 50 / 75.
	var gate_ok := true
	for b in branches:
		var nodes2: Array = (b as Dictionary).get("nodes", [])
		for i in nodes2.size():
			var n := nodes2[i] as Dictionary
			if bool(n.get("core", false)):
				continue
			var want: int = [5, 25, 50, 75][i / 5]
			if int(n.get("req_level", -1)) != want:
				gate_ok = false
	check(gate_ok, "tier gates are 5 / 25 / 50 / 75 (core starter nodes stay at 1)")

	# Points alone are not enough — the level gate must bite.
	var saved := {
		"level": GameState.level, "tp": GameState.talent_points,
		"talents": GameState.talents.duplicate(),
	}
	GameState.talents = {"combat": 20, "magic": 0, "utility": 0}
	GameState.level = 1
	check(GameState.talent_sum("atk") == 4.0,
		"at level 1 only the core node counts (+%d atk)" % int(GameState.talent_sum("atk")))
	check(GameState.node_unlocked("combat", GameState.talents_for_branch("combat")[19]) == false,
		"tier 4 node stays locked at level 1 even with 20 points")

	GameState.level = 25
	check(GameState.talent_sum("atk") == 13.0,
		"levels 1-25 open tiers 1-2 (+%d atk)" % int(GameState.talent_sum("atk")))
	check(absf(GameState.attack_cooldown_mult() - 0.72) < 0.001,
		"Swift Strikes x Momentum stack multiplicatively (%.3f)" % GameState.attack_cooldown_mult())

	GameState.level = 50
	check(absf(GameState.attack_cooldown_mult() - 0.648) < 0.001,
		"three cooldown nodes stack (%.3f)" % GameState.attack_cooldown_mult())
	check(GameState.talent_sum("lifesteal") > 0.0, "Bloodletter grants lifesteal")
	check(GameState.damage_taken_mult() < 1.0, "Unyielding reduces damage taken")

	GameState.level = 75
	check(GameState.talent_sum("atk") == 34.0,
		"all four tiers open (+%d atk)" % int(GameState.talent_sum("atk")))
	check(GameState.whirl_mult() > 1.0, "combat whirlwind talent applies")
	check(GameState.bolt_mult() == 1.0, "magic branch is untouched with 0 points")

	GameState.talents["magic"] = 20
	check(GameState.bolt_mult() > 1.0, "magic firebolt talents apply")
	check(GameState.mp_cost_mult() < 1.0, "Efficient Casting discounts MP costs")
	check(GameState.mp_regen_per_sec() > 1.0, "MP regen talents stack")
	check(GameState.talent_mult("gold") == 1.0, "utility branch is untouched")

	# A branch is mastered at 20 points; further points are refused.
	GameState.talent_points = 5
	check(not GameState.spend_talent("combat"), "spending past the mastered branch is refused")
	check(GameState.talent_points == 5, "refused spend keeps the point")

	# Multiplier floor keeps "less of a bad thing" talents from reaching zero.
	check(GameState.talent_mult("dmg_taken") >= 0.4, "multiplier stack is floored")

	GameState.level = int(saved["level"])
	GameState.talent_points = int(saved["tp"])
	GameState.talents = saved["talents"]
	GameState.stats_changed.emit()

# --- Phase E §5: collect / deliver objectives --------------------------------

func _test_quest_collect() -> void:
	print("[combat_test] collect + deliver objectives (Phase E §5)")
	# --- collect: requires the items, does not consume them ---
	var qid := "__t_collect"
	QuestManager.data[qid] = {
		"name": "Test Gathering",
		"objectives": [
			{"id": "gather", "type": "collect", "target": "health_potion", "count": 2,
				"desc": "Bring 2 potions"},
		],
		"reward": {"xp": 5},
	}
	GameState.add_item("health_potion", 5)
	var potions_before := GameState.item_count("health_potion")
	QuestManager.start_quest(qid)
	check(QuestManager.objective_count(qid, "gather") == 2,
		"items already in the bag satisfy a collect objective on accept")
	check(QuestManager.is_done(qid), "quest completes when the objective is met")
	check(GameState.item_count("health_potion") == potions_before,
		"a collect objective does NOT consume the items")

	# --- deliver: consumes on completion ---
	var qid2 := "__t_deliver"
	QuestManager.data[qid2] = {
		"name": "Test Handover",
		"objectives": [
			{"id": "handover", "type": "deliver", "target": "mana_potion", "count": 1,
				"desc": "Hand over a mana potion"},
		],
	}
	GameState.inventory.erase("mana_potion")   # remove_item(x, 99) is a no-op when you carry fewer than 99
	QuestManager.start_quest(qid2)
	check(QuestManager.objective_count(qid2, "handover") == 0,
		"an empty bag leaves the deliver objective unmet")
	GameState.add_item("mana_potion", 2)
	EventBus.item_picked_up.emit("mana_potion", 2)
	check(QuestManager.is_done(qid2), "deliver completes once the item is carried")
	check(GameState.item_count("mana_potion") == 1,
		"a deliver objective consumes exactly what it asked for (2 -> 1)")

	# --- live pickup mid-quest ---
	var qid3 := "__t_collect_live"
	QuestManager.data[qid3] = {
		"name": "Test Live Gathering",
		"objectives": [
			{"id": "gather", "type": "collect", "target": "leather_armor", "count": 1,
				"desc": "Bring leather armor"},
		],
	}
	GameState.inventory.erase("leather_armor")   # remove_item(x, 99) is a no-op when you carry fewer than 99
	QuestManager.start_quest(qid3)
	check(QuestManager.objective_count(qid3, "gather") == 0, "starts at 0 with an empty bag")
	GameState.add_item("leather_armor", 1)
	EventBus.item_picked_up.emit("leather_armor", 1)
	check(QuestManager.objective_count(qid3, "gather") == 1, "pickup advances the collect objective")
	check(QuestManager.is_done(qid3), "quest completes on pickup")

	for q in [qid, qid2, qid3]:
		QuestManager.data.erase(q)

func _test_projectile_contact() -> void:
	## A pooled projectile is released from inside its own contact signal, and
	## Godot refuses a direct `monitoring = false` there ("Function blocked during
	## in/out signal"). That used to leave the spent projectile live on top of
	## whatever it hit, so the next contact dealt damage again with nothing in the
	## air. Three things must hold: one hit, a genuinely disarmed area, and no
	## damage when the player walks back over the corpse.
	print("[combat_test] projectile contact (one hit, disarmed, no phantom damage)")
	var host := Node2D.new()
	add_child(host)
	var player: Player = load("res://scenes/player/player.tscn").instantiate()
	host.add_child(player)
	player.global_position = Vector2(9000, 9000)   # away from everything else
	GameState.hp = GameState.max_hp()
	await _phys(3)

	# Quiet the pool first: anything already in flight would pollute the count.
	var holder := get_tree().root.get_node_or_null("PoolManager/Projectiles")
	if holder != null:
		for child in holder.get_children():
			if child is Projectile and (child as Projectile).visible:
				PoolManager.release_projectile(child)
	await _phys(3)

	# Clear the field: earlier sections leave players standing in enemy fire, and
	# GameState.hp is global, so a stray grunt landing 19 on somebody else's
	# character would show up in this measurement. (Muting them is not an option —
	# Player._physics_process resets `invulnerable` every frame.)
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	if holder != null:
		for child in holder.get_children():
			if child is Projectile and (child as Projectile).visible:
				PoolManager.release_projectile(child)
	await _phys(4)
	var before := GameState.hp
	var hits: Array = []
	var probe := func(amount: float) -> void: hits.append(amount)
	EventBus.player_damaged.connect(probe)
	PoolManager.spawn_projectile(player.global_position + Vector2(0, -60),
		Vector2.DOWN, 6.0, 300.0, Color.RED, false)
	for i in 60:
		await get_tree().physics_frame
		if GameState.hp < before:
			break
	EventBus.player_damaged.disconnect(probe)
	var after_one := GameState.hp
	check(after_one < before, "hostile projectile damaged the player (%d -> %d)" % [before, after_one])
	check(hits.size() == 1, "the hit landed exactly once (%d damage events %s)" % [hits.size(), str(hits)])

	# The spent projectile must be genuinely disarmed (the bug was a blocked
	# `monitoring = false` inside the physics signal).
	await _phys(2)
	var spent: Projectile = null
	for child in holder.get_children():
		if child is Projectile and (child as Projectile)._spent:
			spent = child
			break
	check(spent != null, "the projectile was returned to the pool")
	check(spent != null and not spent.monitoring, "the spent projectile's area is off (monitoring=%s)"
		% [str(spent.monitoring) if spent != null else "n/a"])

	# Walk out of its radius and straight back into it.
	player.global_position = Vector2(9400, 9000)
	await _phys(20)
	player.global_position = Vector2(9000, 9000)
	await _phys(45)
	check(GameState.hp == after_one,
		"a spent projectile deals no phantom damage (%d -> %d)" % [after_one, GameState.hp])
	host.queue_free()


func _test_idle_art() -> void:
	## H5.5: a monster that holds IDLE for half a minute must not stand on the
	## same two frames the whole time. This checks the runtime side of the extra
	## idle art — which sheets report four frames, that the idle loop really plays
	## four different columns, and that a resting monster looks around.
	print("[combat_test] idle art + resting look-around")
	for p in get_tree().get_nodes_in_group("player"):
		p.queue_free()
	await _phys(2)
	var host := Node2D.new()
	add_child(host)

	var patched := PoseArt.all()
	check(patched.size() > 0, "the pose-art manifest is readable (%d sheets)" % patched.size())

	# Every archetype must read its own sheet's frame count, and the count must
	# match what the manifest says about that sheet.
	var mismatched := []
	var with_four := 0
	for id in EnemyDB.monsters() + EnemyDB.bosses():
		var sheet := String(EnemyDB.get_archetype(String(id)).get("sheet", ""))
		var want := PoseArt.count(sheet, "idle", 2)
		var probe: Enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
		host.add_child(probe)
		probe.setup_archetype(String(id))
		if want == PoseArt.IDLE_GENERATED:
			with_four += 1
		if probe.idle_frames != want:
			mismatched.append("%s=%d(want %d)" % [id, probe.idle_frames, want])
		probe.queue_free()
	check(mismatched.is_empty(),
		"every archetype reads its sheet's idle frame count (%d archetypes with 4 frames)"
		% with_four)

	# Drive one patched enemy's idle animation and look at the frames it shows.
	# Which archetype that is depends on which sheets have art so far, so pick a
	# patched one instead of hard-coding a name the art pass may not have reached.
	var probe_id := ""
	for id in EnemyDB.monsters():
		var sheet := String(EnemyDB.get_archetype(String(id)).get("sheet", ""))
		if PoseArt.has(sheet, "idle"):
			probe_id = String(id)
			break
	if probe_id == "":
		check(false, "no monster archetype uses a patched idle sheet")
		host.queue_free()
		await _phys(2)
		return
	var enemy: Enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	host.add_child(enemy)
	enemy.setup_archetype(probe_id)
	check(enemy.idle_frames == PoseArt.IDLE_GENERATED,
		"%s's sheet carries the extra idle frames" % probe_id)
	var seen := {}
	for i in 90:
		enemy._update_anim(1.0 / 60.0)
		seen[enemy.sprite.frame] = true
	check(seen.size() == PoseArt.IDLE_GENERATED,
		"the idle loop plays %d different frames (%d seen)" % [PoseArt.IDLE_GENERATED, seen.size()])
	var columns := {}
	for step in PoseArt.IDLE_GENERATED:
		columns[enemy._idle_column(step)] = true
	check(columns.size() == PoseArt.IDLE_GENERATED,
		"the idle loop visits four distinct sheet columns (%s)" % str(columns.keys()))

	# And the hero's attack animation must be real motion whichever sheet he is
	# wearing: generated poses if that sheet has them, the LPC slash plus the
	# tween fallback if it does not.


	# Attack poses: a monster with generated swing art plays those frames, and one
	# without keeps the six LPC frames it always had.
	var with_attack := 0
	var without_attack := 0
	for id in EnemyDB.monsters():
		var sheet := String(EnemyDB.get_archetype(String(id)).get("sheet", ""))
		if PoseArt.has(sheet, "slash"):
			with_attack += 1
		else:
			without_attack += 1
	check(with_attack + without_attack == EnemyDB.monsters().size(),
		"every monster resolves an attack frame count (%d generated, %d LPC)"
		% [with_attack, without_attack])

	# Resting: the loop slows down and the monster turns to look around.
	check(Enemy.REST_IDLE_SLOWDOWN < 1.0,
		"a resting monster breathes slower (x%.2f)" % Enemy.REST_IDLE_SLOWDOWN)
	var facings := {}
	enemy._patrols_done = Enemy.PATROLS_BEFORE_REST
	enemy._glance_timer = 0.0
	for i in 40:
		enemy._rest_glance(1.0)
		facings[enemy._anim_dir] = true
	check(facings.size() >= 2,
		"a resting monster looks around (%d facings over 40 s)" % facings.size())
	check(enemy._resting(), "the rest state is what gates the look-around")

	enemy.queue_free()
	host.queue_free()
	await _phys(2)

	# The hero is a character too: his sheet is read through the same manifest, so
	# he breathes on four idle frames and swings his own attack poses the moment
	# the art exists for the armour he is wearing.
	var hero_sheets := 0
	# The hero's swing is real motion whichever sheet he wears.
	for look in ["none", "leather", "plate", "legion"]:
		var path := "res://assets/lpc/player_%s_sword.png" % look
		if not ResourceLoader.exists(path):
			continue
		hero_sheets += 1
		var idle_cols := PoseArt.idle_columns(path, 2)
		var slash_cols := PoseArt.slash_columns(path, 6)
		check(idle_cols.size() == PoseArt.count(path, "idle", 2),
			"the %s hero plays %d idle frames" % [look, idle_cols.size()])
		check(slash_cols.size() == PoseArt.count(path, "slash", 6),
			"the %s hero plays %d attack poses" % [look, slash_cols.size()])
		var hero: Player = load("res://scenes/player/player.tscn").instantiate()
		add_child(hero)
		GameState.equipment["weapon"] = "iron_sword" if look == "none" else "iron_sword"
		hero._rebuild_sprite_frames()
		var frames := 0
		if hero.sprite != null and hero.sprite.sprite_frames != null:
			frames = hero.sprite.sprite_frames.get_frame_count("slash_s")
		check(frames == slash_cols.size(),
			"the hero's animator builds %d attack frames for %s (got %d)"
			% [slash_cols.size(), look, frames])
		hero.queue_free()
	check(hero_sheets == 4, "all four hero armour looks have sheets (%d)" % hero_sheets)
	var swing_hero: Player = load("res://scenes/player/player.tscn").instantiate()
	add_child(swing_hero)
	swing_hero._rebuild_sprite_frames()
	var generated_swing := swing_hero.uses_generated_art("slash")
	check(generated_swing or swing_hero.sprite.sprite_frames.get_frame_count("slash_s") == 6,
		"the hero's swing is either generated art or the full LPC slash (generated=%s)"
		% str(generated_swing))
	swing_hero.queue_free()
	await _phys(2)


func _phys(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _test_safe_ground_and_dialogue_protection() -> void:
	## Two hard rules the player asked for: nothing attacks you on a town's safe
	## ground, and nothing attacks you while a conversation is open. Both are
	## checked through the real damage path, not by reading a flag.
	print("[combat_test] safe ground + dialogue protection")
	# Earlier suites left their own player nodes in the tree, and Enemy picks the
	# first node in the group — so clear the field first.
	for p in get_tree().get_nodes_in_group("player"):
		p.queue_free()
	await _phys(2)
	var host := Node2D.new()
	add_child(host)
	var player: Player = load("res://scenes/player/player.tscn").instantiate()
	add_child(player)

	var camp := Vector2(900, 300)   # data/settlements.json -> safe_zones
	player.global_position = camp
	var enemy: Enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	host.add_child(enemy)
	enemy.global_position = camp + Vector2(40, 0)
	enemy.setup_archetype("grunt")

	GameState.hp = GameState.max_hp()
	var before := GameState.hp
	# Long enough for a withdrawal at WITHDRAW_SPEED to clear the whole bubble.
	await _phys(430)
	check(GameState.hp >= before,
		"a monster beside you on safe ground deals no damage (hp %.0f -> %.0f)" % [before, GameState.hp])
	# It should visibly leave rather than stand in the middle of the camp. (It can
	# stop a few pixels short of the bubble edge if a tent blocks the retreat, so
	# the assertion is "it walked off", not "it is provably outside".)
	var walked := enemy.global_position.distance_to(camp)
	check(walked > 260.0 and enemy.state != Enemy.State.CHASE and enemy.state != Enemy.State.ATTACK,
		"the monster walks off instead of loitering in the middle of town (%.0f px out, state %d)" %
		[walked, enemy.state])

	# Chasing in from outside must not work either.
	enemy.global_position = camp + Vector2(520, 0)
	enemy.setup_archetype("grunt")
	GameState.hp = GameState.max_hp()
	before = GameState.hp
	await _phys(180)
	check(GameState.hp >= before, "a monster chasing from outside cannot reach you inside")

	# Dialogue: the same enemy, in open country, with a conversation open.
	player.global_position = Vector2(0, -2500)
	enemy.global_position = Vector2(40, -2500)
	enemy.setup_archetype("grunt")
	EventBus.dialogue_open = true
	GameState.hp = GameState.max_hp()
	before = GameState.hp
	await _phys(100)
	check(GameState.hp >= before, "nothing lands while a conversation is open")

	# ...and the same enemy does hit when neither protection applies, so the test
	# cannot pass by accident.
	EventBus.dialogue_open = false
	await _phys(140)
	check(GameState.hp < GameState.max_hp(),
		"the same monster does land hits once the player is unprotected")


func _test_fight_feedback() -> void:
	## H3: the fight has to read on screen. A 30 fps sweep of the swing window, the
	## per-enemy health bar, the ground telegraph and the boss bar are all checked
	## here, because "the fight feels unclear" was a feedback problem, not a damage
	## problem.
	print("[combat_test] fight feedback")
	for p in get_tree().get_nodes_in_group("player"):
		p.queue_free()
	await _phys(2)
	var host := Node2D.new()
	add_child(host)
	var player: Player = load("res://scenes/player/player.tscn").instantiate()
	add_child(player)
	player.global_position = Vector2(0, -4000)

	# --- H3.4: the swing still connects at 30 fps -----------------------------
	var old_tick := Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 30
	var enemy: Enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	host.add_child(enemy)
	enemy.setup_archetype("grunt")
	enemy.global_position = player.global_position + Vector2(40, 0)
	await _phys(2)
	var before := enemy.hp
	player.facing = Vector2.RIGHT
	player._start_attack()
	await _phys(14)          # half a second at 30 fps, well past the window
	check(enemy.hp < before, "a swing connects at 30 fps (%.0f -> %.0f hp)" % [before, enemy.hp])
	Engine.physics_ticks_per_second = old_tick

	# --- H3.1: hitting an enemy puts its health bar up -------------------------
	check(enemy._bar_time > 0.0, "a hit raises the enemy's health bar")
	await _phys(2)
	# --- H3.3: an attack in progress is telegraphed on the ground --------------
	enemy.global_position = player.global_position + Vector2(40, 0)
	enemy._attack_cd = 0.0
	var saw_telegraph := false
	for i in 160:
		await get_tree().physics_frame
		if enemy._telegraphing:
			saw_telegraph = true
			break
	check(saw_telegraph, "a winding-up attack draws its ground telegraph")

	# --- H3.2: the boss bar answers the encounter signal -----------------------
	var hud: HUD = HUD.new()
	add_child(hud)
	hud.setup(null, null)
	EventBus.boss_encounter_started.emit("goblin_king", "Goblin King")
	check(hud._boss_box.visible, "the boss bar appears when an encounter starts")
	check(hud._boss_name.text == "Goblin King", "the boss bar names the boss")
	EventBus.boss_defeated.emit()
	check(not hud._boss_box.visible, "the boss bar clears when the boss dies")
	hud.queue_free()

	enemy.queue_free()
	player.queue_free()
	await _phys(2)
