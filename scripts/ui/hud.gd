class_name HUD
extends CanvasLayer
## In-game HUD.
##
## Everything here is anchored, safe-area aware and (as of H1) wrapped in the
## game's own panel theme, so the HUD matches the menus instead of floating raw
## labels over the world. The touch layer is a two-tier thumb layout with a
## context-sensitive Talk/Use button.

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
var toast_label: Label
var _whirl_btn: ActionButton
var _bolt_btn: ActionButton
var _dodge_btn: ActionButton
var _attack_btn: ActionButton
var _interact_btn: ActionButton

var _toast_time := 0.0
var _toast_active := false
var _toast_queue: Array = []
var _buff_label: Label
var _panel_margin := 0.0

const TOAST_SECONDS := 4.5
const TOAST_QUEUE_MAX := 6
const THEME_PATH := "res://ui/theme.tres"

## Boss bar (H3.2).
var _boss_box: Control
var _boss_name: Label
var _boss_bar: ProgressBar
var _boss_phase_label: Label
var _boss: Node = null

## The root Control everything hangs off. Exists so the HUD can own a Theme.
var _ui: Control


func _ready() -> void:
	## The HUD keeps processing while the tree is paused. Dialogue and the shop
	## pause the game, and with the old default (INHERIT) the whole touch layer
	## went dead at exactly the moment the player needed its "Continue" button.
	process_mode = Node.PROCESS_MODE_ALWAYS


func setup(p: Player, s: ChunkStreamer = null) -> void:
	player = p
	streamer = s
	if _ui == null:
		_ui = Control.new()
		_ui.name = "HUIRoot"
		_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
		_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if ResourceLoader.exists(THEME_PATH):
			_ui.theme = load(THEME_PATH)
		add_child(_ui)
	_build_top_left()
	_build_top_right()
	_build_toast()
	_build_boss_bar()
	_build_touch_controls()
	if player != null:
		player.external_input = Vector2.ZERO
	if not EventBus.milestone_reached.is_connected(_on_milestone):
		EventBus.milestone_reached.connect(_on_milestone)
	if not EventBus.secret_found.is_connected(_on_secret_found):
		EventBus.secret_found.connect(_on_secret_found)


func _process(delta: float) -> void:
	_update_buffs(delta)
	_tick_boss()
	_tick_interact_button()
	_advance_toast(delta)
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
		# Dodge is on the same contract as the abilities: a sweep while it cools.
		_dodge_btn.set_cooldown(clampf(float(cds.get("dodge", 0.0)) * Player.DODGE_COOLDOWN
				/ maxf(Player.DODGE_COOLDOWN, 0.01), 0.0, 1.0) * float(cds.get("dodge", 0.0)))
		_attack_btn.set_cooldown(float(cds.get("attack", 0.0)))


func _update_cd(btn: ActionButton, frac: float, total_cd: float, mp_cost: float) -> void:
	if btn == null:
		return
	var label: Label = btn.get_node_or_null("CdLabel") as Label
	btn.set_cooldown(frac)
	if frac > 0.0:
		if label != null:
			label.text = "%.1f" % (frac * total_cd)
		btn.modulate.a = 0.85
	elif GameState.mp < mp_cost:
		if label != null:
			label.text = "MP"
		btn.set_dimmed(true)
	else:
		if label != null:
			label.text = ""
		btn.set_dimmed(false)


# --- Safe area (H1.2) ---------------------------------------------------------

func _insets() -> Vector4:
	## Real insets on all four sides: left, top, right, bottom.
	##
	## The old version returned one Vector2 built from the safe area's *position*
	## and clamped the top-left corner only, so the joystick and the five action
	## buttons — all anchored to the bottom — got no protection at all and could
	## sit under a gesture bar or be clipped by a notch. `win` was computed and
	## thrown away.
	var win := Vector2(DisplayServer.window_get_size())
	if win.x <= 1.0 or win.y <= 1.0:
		return Vector4(0, 0, 0, 0)
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var left := clampf(safe.position.x, 0.0, 64.0)
	var top := clampf(safe.position.y, 0.0, 64.0)
	var right := clampf(win.x - (safe.position.x + safe.size.x), 0.0, 64.0)
	var bottom := clampf(win.y - (safe.position.y + safe.size.y), 0.0, 64.0)
	return Vector4(left, top, right, bottom)


func _fit_scale() -> float:
	## Everything on the touch layer scales to the smaller screen axis (and to the
	## player's joystick setting), so a 640x360 phone fits the same layout a tablet
	## does.
	var vp := Vector2(DisplayServer.window_get_size())
	if vp.x <= 1.0 or vp.y <= 1.0:
		return 1.0
	return clampf(minf(vp.x / 1280.0, vp.y / 720.0), 0.62, 1.15)


# --- the HUD's own little panel helper (H1.1) --------------------------------

func _panel(tint: Color, type_name := "PanelContainer") -> PanelContainer:
	## A PanelContainer wearing the game's own ui/theme.tres panel style, so the
	## in-combat HUD stops looking like a different game from the menus. The
	## "BannerPanel" type is the illustrated plaque used for toasts and titles.
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb: StyleBox = null
	if _ui.theme != null:
		sb = _ui.theme.get_stylebox("panel", type_name)
	if sb != null:
		pc.add_theme_stylebox_override("panel", sb)
	else:
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color(0.07, 0.08, 0.11, 0.72)
		flat.set_corner_radius_all(8)
		flat.set_content_margin_all(8.0)
		pc.add_theme_stylebox_override("panel", flat)
	if tint.a < 1.0:
		pc.modulate = tint
	return pc


# --- Builders -----------------------------------------------------------------

func _update_buffs(_delta: float) -> void:
	## Timed consumable effects belong on screen: a Haste you cannot see running
	## is a potion the player will not trust.
	if _buff_label == null:
		return
	var text := GameState.active_buff_text()
	_buff_label.text = text
	_buff_label.visible = text != ""


func _make_bar(fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(230, 15)
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.08, 0.10, 0.85)
	bg.set_corner_radius_all(4)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill_color
	fg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	return bar


func _build_top_left() -> void:
	var ins := _insets()
	var panel := _panel(Color(1, 1, 1, 1))
	panel.name = "VitalsPanel"
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(14 + ins.x, 10 + ins.y)
	_ui.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	hp_bar = _make_bar(Color(0.78, 0.2, 0.22))
	mp_bar = _make_bar(Color(0.22, 0.42, 0.8))
	info_label = Label.new()
	info_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	info_label.add_theme_font_size_override("font_size", 14)
	_buff_label = Label.new()
	_buff_label.add_theme_font_size_override("font_size", 14)
	_buff_label.add_theme_color_override("font_color", Color(0.75, 0.95, 1.0))
	_buff_label.visible = false

	box.add_child(hp_bar)
	box.add_child(mp_bar)
	box.add_child(info_label)
	box.add_child(_buff_label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	for spec in [["icon_bag", "bag"], ["icon_talent", "talent"]]:
		var b := TextureButton.new()
		b.texture_normal = _load_icon(String(spec[0]))
		b.custom_minimum_size = Vector2(46, 46)
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		b.modulate = Color(1, 1, 1, 0.9)
		b.tooltip_text = "Bag" if String(spec[1]) == "bag" else "Talents"
		if String(spec[1]) == "bag":
			b.pressed.connect(func() -> void: bag_pressed.emit())
		else:
			b.pressed.connect(func() -> void: talents_pressed.emit())
		btn_row.add_child(b)
	box.add_child(btn_row)


func _build_top_right() -> void:
	var ins := _insets()

	var tracker := _panel(Color(1, 1, 1, 1))
	tracker.name = "QuestPanel"
	tracker.anchor_left = 1.0
	tracker.anchor_right = 1.0
	tracker.offset_left = -348.0 - ins.z
	tracker.offset_top = 10.0 + ins.y
	tracker.offset_right = -14.0 - ins.z
	tracker.offset_bottom = 10.0 + ins.y
	tracker.grow_vertical = Control.GROW_DIRECTION_END
	_ui.add_child(tracker)

	quest_label = Label.new()
	quest_label.text = "No active quests"
	quest_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quest_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quest_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	quest_label.add_theme_font_size_override("font_size", 14)
	tracker.add_child(quest_label)

	var map_panel := _panel(Color(1, 1, 1, 1))
	map_panel.name = "MinimapPanel"
	map_panel.anchor_left = 1.0
	map_panel.anchor_right = 1.0
	map_panel.offset_left = -158.0 - ins.z
	map_panel.offset_top = 0.0
	map_panel.offset_right = -14.0 - ins.z
	map_panel.offset_bottom = 140.0
	map_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	map_panel.grow_vertical = Control.GROW_DIRECTION_END
	_ui.add_child(map_panel)
	# The quest panel sits above the map panel: one column, not two overlapping
	# floating blocks. (Fixed order keeps the minimap's own legend readable.)
	map_panel.offset_top = 0.0
	map_panel.position.y = 0.0
	tracker.offset_bottom = tracker.offset_top

	minimap = Minimap.new()
	minimap.custom_minimum_size = Vector2(132, 132)
	minimap.setup(player, streamer)
	map_panel.add_child(minimap)

	# Stack them: minimap bottom-right, quest tracker directly above it.
	map_panel.offset_top = -(140.0 + 8.0) - ins.w
	map_panel.offset_bottom = -ins.w
	tracker.offset_bottom = map_panel.offset_top - 8.0
	tracker.grow_vertical = Control.GROW_DIRECTION_BEGIN


# --- Touch controls (H2) ------------------------------------------------------

func _build_touch_controls() -> void:
	var ins := _insets()
	var fit := _fit_scale()
	var pad := 18.0 * fit

	joystick = VirtualJoystick.new()
	var js := 210.0 * clampf(SettingsManager.joystick_scale, 0.8, 1.5) * fit
	joystick.size = Vector2(js, js)
	joystick.anchor_top = 1.0
	joystick.anchor_bottom = 1.0
	joystick.offset_left = 16.0 + ins.x
	joystick.offset_top = -(js + 16.0) - ins.w
	joystick.offset_right = (js + 16.0) + ins.x
	joystick.offset_bottom = -16.0 - ins.w
	if player != null:
		joystick.vector_changed.connect(func(v: Vector2) -> void: player.external_input = v)
	_ui.add_child(joystick)

	# Two tiers instead of one five-wide row (H2.1): the thumb lives on Attack and
	# Dodge, and the abilities sit one step further away so a swing cannot turn
	# into a Firebolt. Talk/Use is context-sensitive and sits above them.
	var primary := HBoxContainer.new()
	primary.anchor_left = 1.0
	primary.anchor_right = 1.0
	primary.anchor_top = 1.0
	primary.anchor_bottom = 1.0
	primary.alignment = BoxContainer.ALIGNMENT_END
	primary.add_theme_constant_override("separation", pad)
	var dodge_size := 84.0 * fit
	var attack_size := 118.0 * fit
	primary.offset_left = -(dodge_size + attack_size + pad + 16.0) - ins.z
	primary.offset_right = -16.0 - ins.z
	primary.offset_top = -(attack_size + 16.0) - ins.w
	primary.offset_bottom = -16.0 - ins.w
	_ui.add_child(primary)

	_dodge_btn = ActionButton.new()
	_dodge_btn.setup("dodge", _load_icon("icon_dodge"), dodge_size)
	_dodge_btn.press_sfx = "ui_click"
	_attack_btn = ActionButton.new()
	_attack_btn.setup("attack", _load_icon("icon_attack"), attack_size, "", true)
	var attack_cd := _cd_label()
	attack_cd.name = "CdLabel"
	_attack_btn.add_child(attack_cd)
	primary.add_child(_dodge_btn)
	primary.add_child(_attack_btn)

	var secondary := HBoxContainer.new()
	secondary.anchor_left = 1.0
	secondary.anchor_right = 1.0
	secondary.anchor_top = 1.0
	secondary.anchor_bottom = 1.0
	secondary.alignment = BoxContainer.ALIGNMENT_END
	secondary.add_theme_constant_override("separation", pad)
	var ability_size := 76.0 * fit
	secondary.offset_left = -(ability_size * 2.0 + pad + 16.0) - ins.z
	secondary.offset_right = -16.0 - ins.z
	secondary.offset_top = primary.offset_top - ability_size - pad
	secondary.offset_bottom = primary.offset_top - pad
	_ui.add_child(secondary)

	_whirl_btn = ActionButton.new()
	_whirl_btn.setup("ability_whirl", _load_icon("icon_whirl"), ability_size, "Whirl")
	_whirl_btn.press_sfx = "ui_click"
	var whirl_cd := _cd_label()
	whirl_cd.name = "CdLabel"
	_whirl_btn.add_child(whirl_cd)
	_bolt_btn = ActionButton.new()
	_bolt_btn.setup("ability_bolt", _load_icon("icon_bolt"), ability_size, "Bolt")
	_bolt_btn.press_sfx = "ui_click"
	var bolt_cd := _cd_label()
	bolt_cd.name = "CdLabel"
	_bolt_btn.add_child(bolt_cd)
	secondary.add_child(_whirl_btn)
	secondary.add_child(_bolt_btn)

	# The verbal button. It pushes no input event of its own: the HUD decides
	# whether this press means "talk to that NPC" (closest target wins) or "advance
	# / close the screen that is open", which is what makes it reliable.
	_interact_btn = ActionButton.new()
	_interact_btn.setup("interact", _load_icon("icon_interact"), 88.0 * fit, "Talk", false)
	_interact_btn.push_events = false
	_interact_btn.anchor_left = 1.0
	_interact_btn.anchor_right = 1.0
	_interact_btn.anchor_top = 1.0
	_interact_btn.anchor_bottom = 1.0
	_interact_btn.offset_left = -(88.0 * fit + 16.0) - ins.z
	_interact_btn.offset_right = -16.0 - ins.z
	_interact_btn.offset_top = secondary.offset_top - 88.0 * fit - pad
	_interact_btn.offset_bottom = secondary.offset_top - pad
	_interact_btn.pressed_once.connect(_on_interact_pressed)
	_ui.add_child(_interact_btn)


func _cd_label() -> Label:
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _load_icon(n: String) -> Texture2D:
	for dir in ["res://assets/ui/icons/", "res://assets/placeholder/"]:
		for ext in [".png", ".svg"]:
			var path := "%s%s%s" % [dir, n, ext]
			if ResourceLoader.exists(path):
				return load(path)
	return null


# --- the contextual interact button ------------------------------------------

func _tick_interact_button() -> void:
	if _interact_btn == null:
		return
	if PauseManager.is_paused():
		# A screen is open: this button is "continue" (audit C6 - ask the owner).
		_interact_btn.set_caption("Continue")
		_interact_btn.set_dimmed(false)
		_interact_btn.set_glow(false)
		return
	var target := nearest_interactable()
	if target == null:
		_interact_btn.set_caption("")
		_interact_btn.set_dimmed(true)
		_interact_btn.set_glow(false)
		return
	var verb := "Use"
	if target.has_method("interact_label"):
		verb = String(target.call("interact_label"))
	_interact_btn.set_caption(verb)
	_interact_btn.set_dimmed(false)
	_interact_btn.set_glow(true)


func nearest_interactable() -> Node2D:
	## Closest thing in reach wins, so standing between a chest and an NPC cannot
	## fire both. NPCs and world interactables join the group themselves. The rule
	## lives in WorldInteractable so the keyboard path cannot drift from this one
	## (audit M1).
	if not is_instance_valid(player):
		# The screen can outlive the body it was built around (scene change, a
		# death + respawn): fall back to the live player rather than handing a
		# freed object to the shared rule.
		player = get_tree().get_first_node_in_group("player") as Player
	return WorldInteractable.nearest_in_range(get_tree(), player) as Node2D


func _on_interact_pressed() -> void:
	AudioManager.play_sfx("ui_click")
	if PauseManager.is_paused():
		# Let the open screen hear a normal interact tap.
		_interact_btn.tap_action()
		return
	var target := nearest_interactable()
	if target == null:
		AudioManager.play_sfx("denied")
		return
	target.call("interact_from_ui")


func set_quest_text(text: String) -> void:
	if quest_label != null:
		quest_label.text = text


# --- Toasts (H1.3) ------------------------------------------------------------

func _build_toast() -> void:
	var ins := _insets()
	var panel := _panel(Color(1, 1, 1, 1), "BannerPanel")
	panel.name = "ToastPanel"
	panel.visible = false
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.0
	panel.offset_left = -300.0
	panel.offset_right = 300.0
	panel.offset_top = 122.0 + ins.y
	panel.offset_bottom = 122.0 + ins.y
	panel.grow_vertical = Control.GROW_DIRECTION_END
	_ui.add_child(panel)
	toast_label = Label.new()
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label.add_theme_font_size_override("font_size", 16)
	toast_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.55))
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(toast_label)
	_toast_panel = panel


var _toast_panel: PanelContainer


func _show_toast_now(text: String) -> void:
	if toast_label == null:
		return
	toast_label.text = text
	toast_label.visible = true
	_toast_panel.visible = true
	_toast_active = true
	_toast_time = TOAST_SECONDS


func show_toast(text: String) -> void:
	## Queued, not overwritten. A milestone and a secret landing in the same second
	## used to mean one of the two messages simply never appeared.
	if toast_label == null:
		return
	if _toast_active:
		if _toast_queue.size() >= TOAST_QUEUE_MAX:
			_toast_queue.pop_front()
		_toast_queue.append(text)
		return
	_show_toast_now(text)


func _advance_toast(delta: float) -> void:
	if not _toast_active:
		return
	_toast_time -= delta
	if _toast_time > 0.0:
		return
	if _toast_queue.is_empty():
		_toast_active = false
		if _toast_panel != null:
			_toast_panel.visible = false
			toast_label.visible = false
		return
	_show_toast_now(String(_toast_queue.pop_front()))


func _on_secret_found(_secret_id: String, secret_name: String, index: int, total: int) -> void:
	show_toast("Secret found - %s  (%d/%d)" % [secret_name, index, total])


func _on_milestone(lv: int, title: String, text: String) -> void:
	## "Level 20 — Ember-Touched: Ash still clings to your cloak."
	show_toast("Level %d · %s — %s" % [lv, title, text])


# --- Boss bar (H3.2) ----------------------------------------------------------

func _build_boss_bar() -> void:
	## The Ember Warden fight had no on-screen health indicator at all: the only
	## feedback was hit-stop and camera shake. This is a name plate, a bar, and one
	## pip per phase (lit pips are phases already entered).
	var ins := _insets()
	_boss_box = VBoxContainer.new()
	_boss_box.visible = false
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_box.anchor_left = 0.5
	_boss_box.anchor_right = 0.5
	_boss_box.offset_left = -230.0
	_boss_box.offset_right = 230.0
	_boss_box.offset_top = 26.0 + ins.y
	_boss_box.offset_bottom = 84.0 + ins.y
	_boss_box.add_theme_constant_override("separation", 3)
	if _ui == null:
		_ui = Control.new()
		_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_ui)
	_ui.add_child(_boss_box)

	_boss_name = Label.new()
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name.add_theme_font_size_override("font_size", 18)
	_boss_name.add_theme_color_override("font_color", Color(1.0, 0.82, 0.45))
	_boss_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# On the illustrated plaque (H6.2), so the boss's name reads as a title card.
	var plate := _panel(Color(1, 1, 1, 1), "BannerPanel")
	plate.name = "BossPlate"
	plate.add_child(_boss_name)
	_boss_box.add_child(plate)

	_boss_bar = _make_bar(Color(0.72, 0.14, 0.16))
	_boss_bar.custom_minimum_size = Vector2(460, 16)
	_boss_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_boss_box.add_child(_boss_bar)

	_boss_phase_label = Label.new()
	_boss_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_phase_label.add_theme_font_size_override("font_size", 14)
	_boss_phase_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	_boss_phase_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_boss_phase_label.add_theme_constant_override("outline_size", 4)
	_boss_box.add_child(_boss_phase_label)

	if not EventBus.boss_encounter_started.is_connected(_on_boss_encounter):
		EventBus.boss_encounter_started.connect(_on_boss_encounter)
	if not EventBus.boss_defeated.is_connected(_on_boss_defeated):
		EventBus.boss_defeated.connect(_on_boss_defeated)


func _on_boss_encounter(_boss_id: String, display_name: String) -> void:
	_boss_name.text = display_name
	_boss_box.visible = true
	_boss = get_tree().get_first_node_in_group("boss") if is_inside_tree() else null


func _on_boss_defeated() -> void:
	_boss = null
	if _boss_box != null:
		_boss_box.visible = false


func _tick_boss() -> void:
	## Polled, not signal-driven: the boss node is instantiated inside its dungeon
	## floor, so the HUD has to keep looking for it until it exists (and let go of
	## it when the floor is freed).
	if _boss_box == null or not _boss_box.visible or not is_inside_tree():
		return
	if _boss == null or not is_instance_valid(_boss) or not (_boss as Node).is_inside_tree():
		_boss = get_tree().get_first_node_in_group("boss")
		if _boss == null:
			_boss_box.visible = false
			return
	var hp := float(_boss.get("hp"))
	var mx := float(_boss.get("max_hp"))
	_boss_bar.max_value = maxf(mx, 1.0)
	_boss_bar.value = hp
	var phase := 1
	var pv: Variant = _boss.get("phase")
	if pv != null:
		phase = int(pv)
	var total := 1
	var ph: Variant = _boss.get("phases")
	if ph is Array and not (ph as Array).is_empty():
		total = (ph as Array).size()
	elif phase >= 3:
		total = 3          # the Ember Warden's phases live in boss.gd
	var pips := ""
	for i in total:
		pips += "●" if i < phase else "○"
	_boss_phase_label.text = "phase %d/%d  %s" % [phase, total, pips]
