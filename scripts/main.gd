extends Node
## Main gameplay scene: builds world (chunk streamer), player, camera, HUD and
## pause menu; loads an existing save on boot (DECISIONS.md #5).

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const BOSS_ARENA_SCENE := "res://scenes/enemies/boss_arena.tscn"
const CAMP_SCENE := "res://scenes/world/camp.tscn"
const SPAWN_POINT := Vector2(700, 330)
const CAMP_POS := Vector2(900, 300)
const BOSS_POS := Vector2(2700, -1500)
## Phase E §1: dungeon interiors are built far off-map and the player is moved
## to them, so a floor never overlaps the overworld.
const DUNGEON_ORIGIN := Vector2(200000, 200000)
const BOSS_LINES_PATH := "res://data/boss_lines.json"

var player: Player
var camera: FollowCamera
var streamer: ChunkStreamer
var inventory_ui: InventoryScreen
var talent_ui: TalentScreen
var dialogue_box: DialogueBox
var shop_ui: ShopScreen
var travel_ui: TravelScreen
var camp: Camp
var world: Node2D
var settlements: Array[Settlement] = []
var _dungeon: Dungeon
var _dungeon_return := Vector2.ZERO
var day_night: DayNight
## Boss id -> {intro, defeat}. The antagonists were silent before this.
var _boss_lines: Dictionary = {}
var _boss_id: String = ""


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
	EventBus.boss_encounter_started.connect(_on_boss_encounter)
	_boss_lines = _load_boss_lines()
	EventBus.boss_phase_changed.connect(_on_boss_phase)
	EventBus.world_interacted.connect(_on_world_interacted)
	EventBus.quest_started.connect(func(_q: String) -> void: _refresh_quest_ui())
	EventBus.quest_updated.connect(func(_q: String) -> void: _refresh_quest_ui())
	EventBus.quest_completed.connect(_on_quest_completed)
	EventBus.dialogue_closed.connect(_refresh_markers)
	EventBus.dialogue_closed.connect(_release_npc_talk)
	EventBus.npc_barked.connect(_on_npc_barked)
	# Systems that used to be silent: money, equipping, a quest landing, a secret.
	EventBus.gold_changed.connect(func(_amount: int) -> void: AudioManager.play_sfx("coin"))
	EventBus.quest_started.connect(func(_q: String) -> void: AudioManager.play_sfx("quest_accept"))
	EventBus.quest_completed.connect(func(_q: String) -> void: AudioManager.play_sfx("quest_complete"))
	EventBus.secret_found.connect(func(_id: String, _n: String, _i: int, _t: int) -> void:
		AudioManager.play_sfx("secret_found"))

	if GameState.pending_load:
		SaveSystem.load_game(player, GameState.current_slot)
		GameState.pending_load = false
	_refresh_quest_ui()
	_refresh_markers()
	_update_music()
	SettingsManager.apply_text_scale(get_tree().root)


var _music_timer := 0.0


var _place_timer := 0.0


func _process(delta: float) -> void:
	_victory_timer = maxf(0.0, _victory_timer - delta)
	_music_timer += delta
	_place_timer += delta
	if _place_timer >= 0.5:
		_place_timer = 0.0
		_check_place_flags()
	if _music_timer < 0.75:
		return
	_music_timer = 0.0
	_update_music()


func _check_place_flags() -> void:
	## Phase F4: quest steps ask the player to *reach* places, so the world has
	## to raise flags for arriving somewhere. Dungeon entry and boss kills raise
	## their own (see enter_dungeon / _on_boss_defeated / Dungeon).
	if player == null or _dungeon != null:
		return
	var p: Vector2 = player.global_position
	for id in Settlement.all():
		var d: Dictionary = Settlement.get_data(id)
		var pos: Array = d.get("position", [0, 0])
		var radius := float(d.get("radius", 300.0))
		var flag := "visited_%s" % id
		if bool(GameState.quest_flags.get(flag, false)):
			continue
		if p.distance_to(Vector2(float(pos[0]), float(pos[1]))) <= radius:
			QuestManager.register_flag(flag)


## Boss music state. main.gd owns the music selection (it re-evaluates every
## 0.75 s), so BossArena requesting tracks itself would be overwritten — the
## boss theme has to be decided here.
var _boss_active := false
var _boss_defeated := false


## A victory sting plays over the boss theme for a few seconds, then the world
## track returns — the score reacts to what just happened instead of looping.
var _victory_timer := 0.0


func _update_music() -> void:
	if player == null:
		return
	var track := _biome_track(player.global_position)
	var here := player.global_position
	if _dungeon != null:
		track = "dungeon"
	elif _inside_settlement(here):
		track = "town"
	elif here.distance_to(CAMP_POS) < 320.0:
		track = "camp"
	elif day_night != null and day_night.time_of_day_name() == "Night":
		# The day/night cycle had no audio signature at all before this.
		track = "night" if ResourceLoader.exists("res://assets/audio/music/night.ogg") else track
	if _boss_active:
		track = "boss"
	elif not _boss_defeated and here.distance_to(BOSS_POS) < 1250.0:
		track = "combat"
	elif _victory_timer > 0.0:
		track = "victory"
	elif track in ["meadow", "barrens", "frost"] and GameState.max_hp() > 0.0 \
			and GameState.hp / GameState.max_hp() < 0.25:
		# Badly hurt and alone in the field: the score notices.
		track = "danger"
	AudioManager.play_music(track)
	AudioManager.play_ambient(_ambient_id())


func _inside_settlement(pos: Vector2) -> bool:
	for st in settlements:
		if st == null or not is_instance_valid(st):
			continue
		if pos.distance_to(st.global_position) <= 420.0:
			return true
	return false


func _ambient_id() -> String:
	## Place, in sound: cave for a dungeon, room-tone in a town, firelight at the
	## camp, weather for the biome. (Beds are generated — tools/gen_ambient.py.)
	if _dungeon != null:
		return "amb_water" if _dungeon.dungeon_id == "drowned_mill" else "amb_cave"
	if _inside_settlement(player.global_position):
		return "amb_town"
	if player.global_position.distance_to(CAMP_POS) < 420.0:
		return "amb_campfire"
	match _biome_track(player.global_position):
		"frost":
			return "amb_frost"
		"barrens":
			return "amb_lava"
		_:
			return "amb_meadow"


func _biome_track(pos: Vector2) -> String:
	## Delegates to the same function the generator uses (scripts/world/biome.gd),
	## so the music follows the map's wobbling borders instead of three straight
	## lines that no longer exist in the world data.
	return Biome.name_at_position(pos, ChunkStreamer.CHUNK_SIZE)


func _build_world() -> void:
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	streamer = ChunkStreamer.new()
	streamer.name = "ChunkStreamer"
	world.add_child(streamer)

	day_night = DayNight.new()
	day_night.name = "DayNight"
	add_child(day_night)

	var juice := Juice.new()
	juice.name = "Juice"
	world.add_child(juice)

	var arena: BossArena = (load(BOSS_ARENA_SCENE) as PackedScene).instantiate()
	arena.name = "BossArena"
	world.add_child(arena)
	arena.global_position = BOSS_POS

	camp = (load(CAMP_SCENE) as PackedScene).instantiate()
	camp.name = "Camp"
	world.add_child(camp)
	camp.global_position = CAMP_POS
	camp.npc_interacted.connect(_on_npc_interacted)
	_build_settlements()


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
	hud.setup(player, streamer)
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
	_hit_stop(0.05)


func _on_npc_interacted(npc: NPC) -> void:
	# Phase F4: interacting is what counts as talking, so any active `talk`
	# objective for this NPC advances even when the reply is only a bark.
	QuestManager.talk_to(npc.npc_id)
	if npc.is_vendor:
		shop_ui.open(npc.display_name, camp.get_vendor_stock())
		return
	var d := DialogueDB.pick(npc.npc_id)
	if not d.is_empty():
		dialogue_box.start(d)
		return
	# Phase F5: nothing in the dialogue data wants this NPC right now, so check
	# the side-quest board before falling back to a bark.
	var offer := QuestManager.offer_dialogue(npc.npc_id, npc.display_name)
	if not offer.is_empty():
		dialogue_box.start(offer)
		return
	# Mid-mission: an NPC you are working for (or reporting to) talks about the
	# job in hand. Before this, barks were completely deaf to quest state.
	# After the Warden falls the valley should notice. One line per NPC.
	if QuestManager.is_done("MQ100") or QuestManager.is_done("q4_new_dawn"):
		var done_line := DialogueDB.post_game_line(npc.npc_id)
		if done_line != "":
			dialogue_box.start({
				"start": "root",
				"nodes": {"root": {"speaker": npc.display_name, "text": done_line, "choices": []}},
			})
			return
	var reminder := QuestManager.reminder_for(npc.npc_id)
	if reminder != "" and randf() < 0.6:
		dialogue_box.start({
			"start": "root",
			"nodes": {"root": {"speaker": npc.display_name, "text": reminder, "choices": []}},
		})
		return
	# No quest line right now -> answer with an idle bark instead of silence
	# (Phase E §3: every named NPC has something to say, always).
	var line := DialogueDB.pick_bark(npc.npc_id, npc.time_of_day())
	if line == "":
		return
	dialogue_box.start({
		"start": "root",
		"nodes": {"root": {"speaker": npc.display_name, "text": line, "choices": []}},
	})


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


func _release_npc_talk() -> void:
	## Conversations freeze the NPC in place (NPCController.TALK); release them
	## once the dialogue box closes.
	for npc in get_tree().get_nodes_in_group("npc"):
		(npc as NPCController).end_talk()


func _on_npc_barked(_npc_id: String, display_name: String, text: String) -> void:
	## Ambient schedule barks surface through the HUD banner (same toast the
	## milestone rewards use).
	if hud_ref != null:
		hud_ref.show_toast("%s: %s" % [display_name, text])


func _refresh_markers() -> void:
	for npc in get_tree().get_nodes_in_group("npc"):
		(npc as NPC).set_marker(QuestManager.marker_for(npc.npc_id))


const BURN_QUEST := "MQ020"   # "The Ash Road" — the player leaves the valley


func _load_boss_lines() -> Dictionary:
	var f := FileAccess.open(BOSS_LINES_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return (parsed as Dictionary).get("bosses", {})


func _on_boss_encounter(boss_id: String, display_name: String) -> void:
	## The boss speaks before it tries to kill you. A banner, not a modal box:
	## the fight must never open behind a wall of paused text.
	_boss_id = boss_id
	var line: Dictionary = _boss_lines.get(boss_id, {})
	var intro := String(line.get("intro", ""))
	AudioManager.play_sfx("boss_roar")
	if hud_ref != null and intro != "":
		hud_ref.show_toast("%s — \"%s\"" % [display_name, intro])


func _burn_millhaven() -> void:
	## MQ020 ends the first act: the player is sent east on the ash road, and the
	## camp they started in burns while they are gone. The roster always said
	## Rowan dies here; until now nothing in the game removed him.
	if bool(GameState.quest_flags.get("millhaven_burned", false)):
		return
	QuestManager.register_flag("millhaven_burned")
	AudioManager.play_sfx("boss_roar")
	if camp != null and is_instance_valid(camp):
		camp.burn()
	if hud_ref != null:
		hud_ref.show_toast("Smoke on the western road: Millhaven is burning.")


func _on_quest_completed(qid: String) -> void:
	if qid == BURN_QUEST:
		_burn_millhaven()
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
	epilogue.custom_minimum_size = Vector2(680, 0)
	epilogue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	epilogue.add_theme_font_size_override("font_size", 16)
	epilogue.text = _epilogue_text()
	box.add_child(epilogue)
	var stats := Label.new()
	stats.text = _epilogue_stats()
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))
	box.add_child(stats)

	# The credits are built by MainMenu (there is no separate credits scene), so
	# the ending rolls them by showing the title screen's credits layer.
	var credits := Button.new()
	credits.text = "Credits"
	credits.custom_minimum_size = Vector2(200, 40)
	credits.pressed.connect(func() -> void:
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/menus/main_menu.tscn")
	)
	box.add_child(credits)
	var btn := Button.new()
	btn.text = "Keep exploring"
	btn.custom_minimum_size = Vector2(260, 46)
	btn.pressed.connect(func() -> void:
		ending.queue_free()
		get_tree().paused = false
	)
	box.add_child(btn)
	get_tree().paused = true


func _epilogue_text() -> String:
	## A closing that reflects what the player actually did, instead of one
	## sentence that only knew about a flag. Three towns, a decision or two, a
	## secret count and the state of the camp.
	var mercy := bool(GameState.quest_flags.get("vow_mercy", false))
	var rows: Array = []
	rows.append("The Warden is still. The ash that came up out of the valley stops coming.")
	rows.append("You chose mercy, and the valley remembers you as the one who set its guardian free."
		if mercy else
		" You chose vengeance, and the corruption burned away with the Warden, and something that had been keeping watch stopped watching.")
	var burned := bool(GameState.quest_flags.get("millhaven_burned", false))
	var dead := _towns_visited() - 1
	rows.append("Millhaven burned behind you before you were half the fighter you are now, and the road has been a road to somewhere ever since."
		if burned else
		"Hazelwood Camp still keeps its fire, and Rowan still asks what you saw out there.")
	if bool(GameState.quest_flags.get("answer_buried", false)):
		rows.append("You buried what the Warden said in the burn, and the valley has one less thing to argue about.")
	elif bool(GameState.quest_flags.get("answer_carried", false)):
		rows.append("You carried what the Warden said back down the road, and told it to anyone who would listen.")
	if bool(GameState.quest_flags.get("protect_mireille", false)):
		rows.append("Mireille is alive, and still refuses to be thanked. The Choir's ledgers name her as missing.")
	elif bool(GameState.quest_flags.get("expose_mireille", false)):
		rows.append("Mireille answers for what she did, in a room she cannot leave, and asks for nothing.")
	rows.append("You have walked into %d of the valley's towns and come back out of %d of its dungeons."
		% [_towns_visited(), _dungeons_entered()])
	rows.append("The road east is open. If the Choir comes back it will find the valley already awake.")
	return "\n\n".join(rows)


func _epilogue_stats() -> String:
	var secrets := 0
	for flag in GameState.quest_flags.keys():
		if String(flag).begins_with("secret_"):
			secrets += 1
	return "Level %d · %d gold · %d/%d quests · %d dungeons · %d/%d secrets found" % [
		GameState.level, GameState.gold, _quests_done(), 106 + 100,
		_dungeons_entered(), secrets, int(SecretsDB.total())]


func _towns_visited() -> int:
	var n := 0
	for id in ["millhaven", "oakstead", "sunreach", "ashport", "cinderhold",
			"ashvow", "frosthaven", "kilnrest", "skyreach"]:
		if bool(GameState.quest_flags.get("visited_%s" % id, false)):
			n += 1
	return maxi(n, 1)


func _dungeons_entered() -> int:
	var n := 0
	for flag in GameState.quest_flags.keys():
		if String(flag).begins_with("entered_"):
			n += 1
	return n


func _quests_done() -> int:
	var n := 0
	for q in GameState.quests.values():
		if q == "done":
			n += 1
	return n


func _on_boss_defeated() -> void:
	_victory_timer = 6.0
	var line: Dictionary = _boss_lines.get(_boss_id, {})
	var defeat_line := String(line.get("defeat", ""))
	AudioManager.play_sfx("quest_complete")
	if hud_ref != null and defeat_line != "":
		hud_ref.show_toast(defeat_line)
	_boss_active = false
	_boss_defeated = true
	QuestManager.register_flag("cleared_ember_warden_keep")
	_music_timer = 0.75      # let the biome theme return promptly
	camera.shake(0.9)


func _on_boss_phase(phase: int) -> void:
	## The antagonist speaks mid-fight, not only at the door: every boss carries a
	## taunt per phase change in data/boss_lines.json.
	_boss_active = true
	camera.shake(0.5)
	_hit_stop(0.09)
	var lines: Array = (_boss_lines.get(_boss_id, {}) as Dictionary).get("phases", [])
	var idx := phase - 2      # phase 2 is the first change
	if idx >= 0 and idx < lines.size():
		AudioManager.play_sfx("boss_roar")
		if hud_ref != null:
			hud_ref.show_toast(String(lines[idx]))


var _hit_stop_busy := false


func _hit_stop(duration: float) -> void:
	## Brief time-scale dip for impact feel. Guarded so overlapping hits don't
	## fight over Engine.time_scale.
	if _hit_stop_busy:
		return
	_hit_stop_busy = true
	Engine.time_scale = 0.35
	get_tree().create_timer(duration, true, false, true).timeout.connect(func() -> void:
		Engine.time_scale = 1.0
		_hit_stop_busy = false
	)


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
	get_tree().paused = false
	GameState.pending_load = true
	Transition.go_to("res://scenes/main.tscn")


func _on_quit_title() -> void:
	get_tree().paused = false
	GameState.pending_load = false
	Transition.go_to("res://scenes/menus/main_menu.tscn")


# --- Phase E §1: settlements + dungeons --------------------------------------

func _build_settlements() -> void:
	## One real scene per settlement (plaza, buildings, waypoint, sign, NPCs).
	for id in Settlement.all():
		var s := Settlement.new()
		s.name = "Settlement_%s" % id
		world.add_child(s)
		s.setup(String(id))
		s.npc_interacted.connect(_on_npc_interacted)
		settlements.append(s)
	_build_dungeon_entrances()


func _build_dungeon_entrances() -> void:
	for id in Dungeon.all():
		var d: Dictionary = (Dungeon.all() as Dictionary)[id]
		var p: Array = d.get("position", [0, 0])
		var entrance := DungeonEntrance.new()
		entrance.name = "Dungeon_%s" % id
		entrance.position = Vector2(float(p[0]), float(p[1]))
		entrance.configure(String(id))
		entrance.entered.connect(enter_dungeon)
		world.add_child(entrance)


func enter_dungeon(dungeon_id: String) -> void:
	## Build the dungeon off-map and move the player in. Ascending past floor 1
	## (the "Exit" stair) returns them to where they stood.
	if player == null:
		return
	_dungeon_return = player.global_position
	if _dungeon != null and is_instance_valid(_dungeon):
		_dungeon.queue_free()
	_dungeon = Dungeon.new()
	_dungeon.name = "Dungeon_%s" % dungeon_id
	add_child(_dungeon)
	_dungeon.exited.connect(_on_dungeon_exited)
	QuestManager.register_flag("entered_%s" % dungeon_id)
	_dungeon.setup(dungeon_id, 1)
	# Important: setup() places the dungeon at its world position, so the
	# off-map relocation has to happen AFTER it, or the room is left sitting on
	# the overworld while the player stands in an empty chunk.
	_dungeon.global_position = DUNGEON_ORIGIN
	if hud_ref != null:
		hud_ref.show_toast("Entered %s — floor 1 of %d" % [
			String(_dungeon.data.get("name", dungeon_id)), _dungeon.floor_count()])
	player.global_position = DUNGEON_ORIGIN + Dungeon.STAIR_DOWN - Vector2(0, 40)


func _on_dungeon_exited(_id: String) -> void:
	if _dungeon != null and is_instance_valid(_dungeon):
		_dungeon.queue_free()
		_dungeon = null
	if player != null:
		player.global_position = _dungeon_return
	if hud_ref != null:
		hud_ref.show_toast("Back on the surface")


func current_dungeon() -> Dungeon:
	return _dungeon
