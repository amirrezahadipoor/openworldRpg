extends Node
## Main gameplay scene: builds world (chunk streamer), player, camera, HUD and
## pause menu; loads an existing save on boot (DECISIONS.md #5).

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const BOSS_ARENA_SCENE := "res://scenes/enemies/boss_arena.tscn"
const CAMP_SCENE := "res://scenes/world/camp.tscn"
const SPAWN_POINT := Vector2(700, 330)
const CAMP_POS := Vector2(900, 300)
const BOSS_POS := Vector2(2700, -1500)

var player: Player
var camera: FollowCamera
var streamer: ChunkStreamer
var inventory_ui: InventoryScreen
var talent_ui: TalentScreen
var dialogue_box: DialogueBox
var shop_ui: ShopScreen
var travel_ui: TravelScreen
var camp: Camp
var day_night: DayNight


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
	EventBus.world_interacted.connect(_on_world_interacted)
	EventBus.quest_started.connect(func(_q: String) -> void: _refresh_quest_ui())
	EventBus.quest_updated.connect(func(_q: String) -> void: _refresh_quest_ui())
	EventBus.quest_completed.connect(_on_quest_completed)
	EventBus.dialogue_closed.connect(_refresh_markers)

	if GameState.pending_load:
		SaveSystem.load_game(player, GameState.current_slot)
		GameState.pending_load = false
	_refresh_quest_ui()
	_refresh_markers()


func _build_world() -> void:
	var world := Node2D.new()
	world.name = "World"
	add_child(world)
	streamer = ChunkStreamer.new()
	streamer.name = "ChunkStreamer"
	world.add_child(streamer)

	day_night = DayNight.new()
	day_night.name = "DayNight"
	add_child(day_night)

	var arena: BossArena = (load(BOSS_ARENA_SCENE) as PackedScene).instantiate()
	arena.name = "BossArena"
	world.add_child(arena)
	arena.global_position = BOSS_POS

	camp = (load(CAMP_SCENE) as PackedScene).instantiate()
	camp.name = "Camp"
	world.add_child(camp)
	camp.global_position = CAMP_POS
	camp.npc_interacted.connect(_on_npc_interacted)


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
	hud_ref = hud
	hud.bag_pressed.connect(func() -> void: inventory_ui.toggle())
	hud.talents_pressed.connect(func() -> void: talent_ui.toggle())

	inventory_ui = InventoryScreen.new()
	inventory_ui.name = "InventoryScreen"
	add_child(inventory_ui)
	inventory_ui.drop_requested.connect(_on_drop_requested)

	talent_ui = TalentScreen.new()
	talent_ui.name = "TalentScreen"
	add_child(talent_ui)

	dialogue_box = DialogueBox.new()
	dialogue_box.name = "DialogueBox"
	add_child(dialogue_box)

	shop_ui = ShopScreen.new()
	shop_ui.name = "ShopScreen"
	add_child(shop_ui)

	travel_ui = TravelScreen.new()
	travel_ui.name = "TravelScreen"
	add_child(travel_ui)
	travel_ui.travel_to.connect(_on_travel_to)

	var pause := PauseMenu.new()
	pause.name = "PauseMenu"
	pause.player = player
	add_child(pause)

	var quest_log := QuestLogScreen.new()
	quest_log.name = "QuestLogScreen"
	add_child(quest_log)
	pause.quest_log_requested.connect(quest_log.open)

	var settings_ui := SettingsScreen.new()
	settings_ui.name = "SettingsScreen"
	add_child(settings_ui)
	pause.settings_requested.connect(settings_ui.open)
	pause.quit_title_requested.connect(func() -> void: pass)  # handled inside PauseMenu

	var death_ui := DeathScreen.new()
	death_ui.name = "DeathScreen"
	add_child(death_ui)
	death_ui.respawn_requested.connect(_on_respawn)
	death_ui.load_last_requested.connect(_on_load_last)
	death_ui.quit_title_requested.connect(_on_quit_title)


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


func _on_npc_interacted(npc: NPC) -> void:
	if npc.is_vendor:
		shop_ui.open(npc.display_name, camp.get_vendor_stock())
		return
	var d := DialogueDB.pick(npc.npc_id)
	if d.is_empty():
		return
	dialogue_box.start(d)


func _on_world_interacted(node: Node) -> void:
	if node is Sign:
		var sign := node as Sign
		dialogue_box.start({
			"start": "root",
			"nodes": {
				"root": {"speaker": sign.title, "text": sign.text, "choices": []},
			},
		})
	elif node is Waypoint:
		travel_ui.open((node as Waypoint).wp_id)


func _on_travel_to(wp_id: String) -> void:
	if not Waypoint.registry.has(wp_id):
		return
	player.global_position = (Waypoint.registry[wp_id] as Vector2) + Vector2(0, 42)
	player.velocity = Vector2.ZERO
	camera.snap()
	streamer.set_target(player)
	AudioManager.play_sfx("dodge")


func _refresh_quest_ui() -> void:
	if hud_ref:
		hud_ref.set_quest_text(QuestManager.tracker_text())
	_refresh_markers()


var hud_ref: HUD


func _refresh_markers() -> void:
	for npc in get_tree().get_nodes_in_group("npc"):
		(npc as NPC).set_marker(QuestManager.marker_for(npc.npc_id))


func _on_quest_completed(qid: String) -> void:
	if qid == "q4_new_dawn":
		_show_ending()


func _show_ending() -> void:
	var ending := CanvasLayer.new()
	ending.layer = 80
	ending.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ending)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ending.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)
	var title := Label.new()
	title.text = "T H E   E N D"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(1.0, 0.87, 0.5))
	box.add_child(title)
	var epilogue := Label.new()
	epilogue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	epilogue.custom_minimum_size = Vector2(620, 0)
	epilogue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if bool(GameState.quest_flags.get("vow_mercy", false)):
		epilogue.text = "You chose mercy, and the valley remembers you as the one who set its guardian free. The campfire burns bright again."
	else:
		epilogue.text = "You chose vengeance, and the corruption burned away with the Warden. The campfire burns bright again."
	box.add_child(epilogue)
	var stats := Label.new()
	stats.text = "Level %d · %d gold · %d quests completed" % [GameState.level, GameState.gold, _quests_done()]
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))
	box.add_child(stats)
	var btn := Button.new()
	btn.text = "Keep exploring"
	btn.custom_minimum_size = Vector2(260, 46)
	btn.pressed.connect(func() -> void:
		ending.queue_free()
		get_tree().paused = false
	)
	box.add_child(btn)
	get_tree().paused = true


func _quests_done() -> int:
	var n := 0
	for q in GameState.quests.values():
		if q == "done":
			n += 1
	return n


func _on_boss_defeated() -> void:
	camera.shake(0.9)


func _on_boss_phase(_phase: int) -> void:
	camera.shake(0.5)


func _on_player_died() -> void:
	var death_ui: DeathScreen = get_node_or_null("DeathScreen")
	if death_ui:
		death_ui.show_death()
	camera.shake(0.6)


func _on_respawn() -> void:
	GameState.hp = GameState.max_hp()
	GameState.mp = GameState.max_mp()
	player.global_position = SPAWN_POINT
	camera.global_position = SPAWN_POINT
	player.velocity = Vector2.ZERO


func _on_load_last() -> void:
	GameState.pending_load = true
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_quit_title() -> void:
	GameState.pending_load = false
	get_tree().change_scene_to_file("res://scenes/menus/main_menu.tscn")
