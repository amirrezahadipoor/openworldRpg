extends Node
## Main gameplay scene: builds world (chunk streamer), player, camera, HUD and
## pause menu; loads an existing save on boot (DECISIONS.md #5).

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const BOSS_ARENA_SCENE := "res://scenes/enemies/boss_arena.tscn"
const SPAWN_POINT := Vector2(512, 512)
const BOSS_POS := Vector2(2700, -1500)

var player: Player
var camera: FollowCamera
var streamer: ChunkStreamer
var inventory_ui: InventoryScreen
var talent_ui: TalentScreen


func _ready() -> void:
	_build_world()
	_build_player()
	_build_camera()
	_build_ui()

	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.player_died.connect(_on_player_died)
	EventBus.enemy_hurt.connect(_on_enemy_hurt)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.boss_defeated.connect(_on_boss_defeated)
	EventBus.boss_phase_changed.connect(_on_boss_phase)

	if SaveSystem.has_save():
		SaveSystem.load_game(player)


func _build_world() -> void:
	var world := Node2D.new()
	world.name = "World"
	add_child(world)
	streamer = ChunkStreamer.new()
	streamer.name = "ChunkStreamer"
	world.add_child(streamer)

	var arena: BossArena = (load(BOSS_ARENA_SCENE) as PackedScene).instantiate()
	arena.name = "BossArena"
	world.add_child(arena)
	arena.global_position = BOSS_POS


func _build_player() -> void:
	var scene: PackedScene = load(PLAYER_SCENE)
	player = scene.instantiate()
	player.name = "Player"
	add_child(player)
	player.global_position = SPAWN_POINT
	streamer.set_target(player)


func _build_camera() -> void:
	camera = FollowCamera.new()
	camera.name = "Camera"
	add_child(camera)
	camera.target = player
	camera.zoom = Vector2(1.1, 1.1)


func _build_ui() -> void:
	var hud := HUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(player)
	hud.bag_pressed.connect(func() -> void: inventory_ui.toggle())
	hud.talents_pressed.connect(func() -> void: talent_ui.toggle())

	inventory_ui = InventoryScreen.new()
	inventory_ui.name = "InventoryScreen"
	add_child(inventory_ui)
	inventory_ui.drop_requested.connect(_on_drop_requested)

	talent_ui = TalentScreen.new()
	talent_ui.name = "TalentScreen"
	add_child(talent_ui)

	var pause := PauseMenu.new()
	pause.name = "PauseMenu"
	pause.player = player
	add_child(pause)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		inventory_ui.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("talents"):
		talent_ui.toggle()
		get_viewport().set_input_as_handled()


func _on_drop_requested(item_id: String) -> void:
	if not GameState.remove_item(item_id, 1):
		return
	var p: Pickup = (load("res://scenes/world/pickup.tscn") as PackedScene).instantiate()
	$World.add_child(p)
	p.global_position = player.global_position + Vector2(36, 0)
	p.setup_item(item_id)


func _on_player_damaged(_amount: float) -> void:
	camera.shake(0.35)
	AudioManager.play_sfx("player_hurt")


func _on_enemy_hurt(enemy: Node, amount: float, _dir: Vector2) -> void:
	if enemy is Node2D:
		DamageNumber.spawn(self, (enemy as Node2D).global_position + Vector2(0, -30), str(int(amount)), Color(1.0, 0.9, 0.35))


func _on_enemy_died(enemy: Node) -> void:
	if enemy is Node2D:
		DamageNumber.spawn(self, (enemy as Node2D).global_position + Vector2(0, -34), "+%d XP" % (enemy as Enemy).xp_reward, Color(0.55, 0.95, 0.55))
	camera.shake(0.2)


func _on_boss_defeated() -> void:
	camera.shake(0.9)


func _on_boss_phase(_phase: int) -> void:
	camera.shake(0.5)


func _on_player_died() -> void:
	# Death screen is Phase 10; for now respawn at spawn with full HP.
	GameState.hp = GameState.max_hp()
	player.global_position = SPAWN_POINT
	camera.shake(0.6)
