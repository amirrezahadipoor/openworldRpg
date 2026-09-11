class_name HUD
extends CanvasLayer
## In-game HUD: HP/MP bars, XP/gold readout, quest tracker, minimap
## placeholder, virtual joystick + action buttons.
## Fully anchor-based with safe-area offsets (DECISIONS.md #2) — scales from
## 720p phones to 1440p+ tablets and 16:9 → 20:9 aspects.

signal bag_pressed
signal talents_pressed

var player: Player
var streamer: ChunkStreamer

var hp_bar: ProgressBar
var mp_bar: ProgressBar
var info_label: Label
var quest_label: Label
var joystick: VirtualJoystick
var minimap: Minimap
var _whirl_btn: ActionButton
var _bolt_btn: ActionButton
var toast_label: Label
var _toast_time := 0.0

# --- boss bar (H3.2) ---------------------------------------------------------
var _boss_box: Control
var _boss_name: Label
var _boss_bar: ProgressBar
var _boss_phase_label: Label
var _boss_pips: Control
var _boss: Node = null

const TOAST_SECONDS := 4.5


func setup(p: Player, s: ChunkStreamer = null) -> void:
	player = p
	streamer = s
	_build_top_left()
	_build_top_right()
	_build_touch_controls()
	if player != null:
		player.external_input = Vector2.ZERO
	_build_toast()
	_build_boss_bar()
	if not EventBus.milestone_reached.is_connected(_on_milestone):
		EventBus.milestone_reached.connect(_on_milestone)
	if not EventBus.secret_found.is_connected(_on_secret_found):
		EventBus.secret_found.connect(_on_secret_found)


func _process(delta: float) -> void:
	_update_buffs(delta)
	_tick_boss()
	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time <= 0.0 and toast_label != null:
			toast_label.visible = false
	if hp_bar != null:
		hp_bar.max_value = GameState.max_hp()
		hp_bar.value = GameState.hp
		mp_bar.max_value = GameState.max_mp()
		mp_bar.value = GameState.mp
		info_label.text = "Lv %d · XP %d/%d · %d gold" % [
			GameState.level, GameState.xp, GameState.xp_to_next(), GameState.gold
		]
	if player != null and _whirl_btn != null:
		var cds := player.cooldowns()
		_update_cd(_whirl_btn, float(cds["whirl"]), Player.WHIRL_COOLDOWN, player.whirl_mp_cost())
		_update_cd(_bolt_btn, float(cds["bolt"]), Player.BOLT_COOLDOWN, player.bolt_mp_cost())


func _update_cd(btn: ActionButton, frac: float, total_cd: float, mp_cost: float) -> void:
	var label: Label = btn.get_child(btn.get_child_count() - 1) if btn.get_child_count() > 0 else null
	if label == null:
		return
	if frac > 0.0:
		label.text = "%.1f" % (frac * total_cd)
		btn.modulate = Color(0.5, 0.5, 0.55, 0.85)
	elif GameState.mp < mp_cost:
		label.text = "MP"
		btn.modulate = Color(0.45, 0.5, 0.9, 0.85)
	else:
		label.text = ""
		btn.modulate = Color(1, 1, 1, 0.85)


# --- Builders -----------------------------------------------------------------

var _buff_label: Label


func _update_buffs(_delta: float) -> void:
	## Timed consumable effects belong on screen: a Haste you cannot see running
	## is a potion the player will not trust.
	if _buff_label == null:
		return
	var text := GameState.active_buff_text()
	_buff_label.text = text
	_buff_label.visible = text != ""


func _safe_margins() -> Vector2:
	var safe := DisplayServer.get_display_safe_area()
	var win := Vector2(DisplayServer.window_get_size())
	return Vector2(maxi(safe.position.x, 0), maxi(safe.position.y, 0)).limit_length(64.0)


func _make_bar(fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(230, 15)
	bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.08, 0.10, 0.8)
	bg.set_corner_radius_all(4)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill_color
	fg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	return bar


func _build_top_left() -> void:
	var m := _safe_margins()
	_buff_label = Label.new()
	_buff_label.add_theme_font_size_override("font_size", 14)
	_buff_label.add_theme_color_override("font_color", Color(0.75, 0.95, 1.0))
	_buff_label.visible = false

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	box.position = Vector2(16, 12) + m
	box.add_theme_constant_override("separation", 4)

	hp_bar = _make_bar(Color(0.78, 0.2, 0.22))
	mp_bar = _make_bar(Color(0.22, 0.42, 0.8))
	info_label = Label.new()
	info_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	info_label.add_theme_font_size_override("font_size", 14)

	box.add_child(hp_bar)
	box.add_child(mp_bar)
	box.add_child(info_label)
	box.add_child(_buff_label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	var bag := TextureButton.new()
	bag.texture_normal = _load_icon("icon_bag")
	bag.custom_minimum_size = Vector2(46, 46)
	bag.ignore_texture_size = true
	bag.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	bag.modulate = Color(1, 1, 1, 0.85)
	bag.pressed.connect(func() -> void: bag_pressed.emit())
	var star := TextureButton.new()
	star.texture_normal = _load_icon("icon_talent")
	star.custom_minimum_size = Vector2(46, 46)
	star.ignore_texture_size = true
	star.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	star.modulate = Color(1, 1, 1, 0.85)
	star.pressed.connect(func() -> void: talents_pressed.emit())
	btn_row.add_child(bag)
	btn_row.add_child(star)
	box.add_child(btn_row)

	add_child(box)


func _build_top_right() -> void:
	var m := _safe_margins()
	quest_label = Label.new()
	quest_label.text = "No active quests"
	quest_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quest_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quest_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	quest_label.add_theme_font_size_override("font_size", 14)
	quest_label.anchor_left = 1.0
	quest_label.anchor_right = 1.0
	quest_label.offset_left = -340.0 - m.x
	quest_label.offset_top = 12.0 + m.y
	quest_label.offset_right = -16.0 - m.x
	quest_label.offset_bottom = 130.0
	add_child(quest_label)

	minimap = Minimap.new()
	minimap.custom_minimum_size = Vector2(140, 140)
	minimap.anchor_left = 1.0
	minimap.anchor_right = 1.0
	minimap.offset_left = -156.0 - m.x
	minimap.offset_top = 64.0 + m.y
	minimap.offset_right = -16.0 - m.x
	minimap.offset_bottom = 204.0 + m.y
	minimap.setup(player, streamer)
	add_child(minimap)


func _build_touch_controls() -> void:
	var m := _safe_margins()
	# Everything on the touch layer scales to the smaller screen axis (and to the
	# player's joystick setting). A 640x360 phone fits a 210px stick plus five
	# 74-104px buttons with 18px gaps only if those numbers shrink; before this the
	# row simply ran off the left edge of small screens.
	var vp := Vector2(DisplayServer.window_get_size())
	var fit: float = clampf(minf(vp.x / 1280.0, vp.y / 720.0), 0.62, 1.15)

	joystick = VirtualJoystick.new()
	# The joystick size is a real setting now: "Joystick Size" in Settings moves
	# this number, instead of a slider that changed nothing.
	var js := 210.0 * clampf(SettingsManager.joystick_scale, 0.8, 1.5) * fit
	joystick.size = Vector2(js, js)
	joystick.anchor_top = 1.0
	joystick.anchor_bottom = 1.0
	joystick.offset_left = 20.0 + m.x
	joystick.offset_top = -(js + 20.0) - m.y
	joystick.offset_right = (js + 20.0) + m.x
	joystick.offset_bottom = -20.0 - m.y
	if player != null:
		joystick.vector_changed.connect(func(v: Vector2) -> void: player.external_input = v)
	add_child(joystick)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 18.0 * fit)
	buttons.anchor_left = 1.0
	buttons.anchor_right = 1.0
	buttons.anchor_top = 1.0
	buttons.anchor_bottom = 1.0
	# Hug the row's real width (74*4 + 104 + gaps), so it scales as one unit.
	buttons.offset_left = -((74.0 * 4.0 + 104.0 + 18.0 * 4.0) * fit) - 20.0 - m.x
	buttons.offset_top = -130.0 - m.y
	buttons.offset_right = -20.0 - m.x
	buttons.offset_bottom = -20.0 - m.y
	buttons.alignment = BoxContainer.ALIGNMENT_END

	var whirl := ActionButton.new()
	whirl.setup("ability_whirl", _load_icon("icon_whirl"), 74.0 * fit)
	_whirl_btn = whirl
	whirl.add_child(_cd_label())
	var bolt := ActionButton.new()
	bolt.setup("ability_bolt", _load_icon("icon_bolt"), 74.0 * fit)
	_bolt_btn = bolt
	bolt.add_child(_cd_label())
	var dodge := ActionButton.new()
	dodge.setup("dodge", _load_icon("icon_dodge"), 74.0 * fit)
	var interact_btn := ActionButton.new()
	interact_btn.setup("interact", _load_icon("icon_interact"), 74.0 * fit)
	var attack := ActionButton.new()
	attack.setup("attack", _load_icon("icon_attack"), 104.0 * fit)

	buttons.add_child(whirl)
	buttons.add_child(bolt)
	buttons.add_child(dodge)
	buttons.add_child(interact_btn)
	buttons.add_child(attack)
	add_child(buttons)


func _cd_label() -> Label:
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	return l


func _load_icon(n: String) -> Texture2D:
	var path := "res://assets/placeholder/%s.svg" % n
	if ResourceLoader.exists(path):
		return load(path)
	return null


func set_quest_text(text: String) -> void:
	if quest_label != null:
		quest_label.text = text


# --- Milestone banner (Phase E §6) -------------------------------------------

func _build_boss_bar() -> void:
	## The Ember Warden fight had no on-screen health indicator at all: the only
	## feedback was hit-stop and camera shake. This is a name plate, a bar, and one
	## pip per phase (lit pips are phases already entered).
	_boss_box = VBoxContainer.new()
	_boss_box.visible = false
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_box.anchor_left = 0.5
	_boss_box.anchor_right = 0.5
	_boss_box.offset_left = -230.0
	_boss_box.offset_right = 230.0
	_boss_box.offset_top = 26.0
	_boss_box.offset_bottom = 84.0
	_boss_box.add_theme_constant_override("separation", 3)

	_boss_name = Label.new()
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name.add_theme_font_size_override("font_size", 18)
	_boss_name.add_theme_color_override("font_color", Color(1.0, 0.82, 0.45))
	_boss_name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_boss_name.add_theme_constant_override("outline_size", 5)
	_boss_box.add_child(_boss_name)

	_boss_bar = _make_bar(Color(0.72, 0.14, 0.16))
	_boss_bar.custom_minimum_size = Vector2(460, 16)
	_boss_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_boss_box.add_child(_boss_bar)

	_boss_phase_label = Label.new()
	_boss_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_phase_label.add_theme_font_size_override("font_size", 14)
	_boss_phase_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	_boss_box.add_child(_boss_phase_label)
	add_child(_boss_box)
	if not EventBus.boss_encounter_started.is_connected(_on_boss_encounter):
		EventBus.boss_encounter_started.connect(_on_boss_encounter)
	if not EventBus.boss_defeated.is_connected(_on_boss_defeated):
		EventBus.boss_defeated.connect(_on_boss_defeated)


func _on_boss_encounter(_boss_id: String, display_name: String) -> void:
	_boss_name.text = display_name
	_boss_box.visible = true
	_boss = get_tree().get_first_node_in_group("boss")


func _on_boss_defeated() -> void:
	_boss = null
	if _boss_box != null:
		_boss_box.visible = false


func _tick_boss() -> void:
	## Polled, not signal-driven: the boss node is instantiated inside its dungeon
	## floor, so the HUD has to keep looking for it until it exists (and let go of
	## it when the floor is freed).
	if _boss_box == null or not _boss_box.visible:
		return
	if _boss == null or not is_instance_valid(_boss) or not (_boss as Node).is_inside_tree():
		_boss = get_tree().get_first_node_in_group("boss")
		if _boss == null:
			_boss_box.visible = false
			return
	var e: Node = _boss
	var hp := float(e.get("hp"))
	var mx := float(e.get("max_hp"))
	_boss_bar.max_value = maxf(mx, 1.0)
	_boss_bar.value = hp
	var phase := int(e.get("phase")) if e.get("phase") != null else 1
	var total := 1
	var ph: Variant = e.get("phases")
	if ph is Array and not (ph as Array).is_empty():
		total = (ph as Array).size()
	elif phase >= 3:
		total = 3          # the Ember Warden's phases live in boss.gd
	var pips := ""
	for i in total:
		pips += "●" if i < phase else "○"
	_boss_phase_label.text = "phase %d/%d  %s" % [phase, total, pips]


func _build_toast() -> void:
	toast_label = Label.new()
	toast_label.visible = false
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.anchor_left = 0.0
	toast_label.anchor_right = 1.0
	var m := _safe_margins()
	# Anchored across the middle of the screen, not the full width: a full-width
	# toast printed straight across the HP/MP/XP block (see the merchant toast in
	# reports/rpg_shot_2.png). It also sits below the bars now.
	toast_label.offset_left = 220.0 + m.x
	toast_label.offset_right = -220.0 - m.x
	toast_label.offset_top = 118.0 + m.y
	toast_label.offset_bottom = 162.0 + m.y
	toast_label.add_theme_font_size_override("font_size", 19)
	toast_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.55))
	toast_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	toast_label.add_theme_constant_override("outline_size", 5)
	add_child(toast_label)


func _on_secret_found(_secret_id: String, secret_name: String, index: int, total: int) -> void:
	show_toast("Secret found - %s  (%d/%d)" % [secret_name, index, total])


func show_toast(text: String) -> void:
	if toast_label == null:
		return
	toast_label.text = text
	toast_label.visible = true
	_toast_time = TOAST_SECONDS


func _on_milestone(lv: int, title: String, text: String) -> void:
	## "Level 20 — Ember-Touched: Ash still clings to your cloak."
	show_toast("Level %d · %s — %s" % [lv, title, text])
