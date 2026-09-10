extends Node
## Main gameplay scene: builds world (chunk streamer), player, camera, HUD and
## pause menu; loads an existing save on boot (DECISIONS.md #5).

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const SPAWN_POINT := Vector2(512, 512)

var player: Player
var camera: FollowCamera
var streamer: ChunkStreamer


func _ready() -> void:
	_build_world()
	_build_player()
	_build_camera()
	_build_ui()

	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.player_died.connect(_on_player_died)

	if SaveSystem.has_save():
		SaveSystem.load_game(player)


func _build_world() -> void:
	var world := Node2D.new()
	world.name = "World"
	add_child(world)
	streamer = ChunkStreamer.new()
	streamer.name = "ChunkStreamer"
	world.add_child(streamer)


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

	var pause := PauseMenu.new()
	pause.name = "PauseMenu"
	pause.player = player
	add_child(pause)


func _on_player_damaged(_amount: float) -> void:
	camera.shake(0.35)
	AudioManager.play_sfx("player_hurt")


func _on_player_died() -> void:
	# Death screen is Phase 10; for now respawn at spawn with full HP.
	GameState.hp = GameState.max_hp()
	player.global_position = SPAWN_POINT
	camera.shake(0.6)
