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


func _report() -> void:
	if failures == 0:
		print("TEST RESULT: PASS (%d checks)" % checks)
		get_tree().quit(0)
	else:
		print("TEST RESULT: FAIL (%d/%d checks failed)" % [failures, checks])
		get_tree().quit(1)
