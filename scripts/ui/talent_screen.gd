class_name TalentScreen
extends CanvasLayer
## Talent tree UI — 3 branches, tiered nodes (data/talents.json).
## A node becomes active once the player has allocated `tier` points to its
## branch; "Learn" buttons allocate one point to the next locked node.
## Pauses the game while open.

signal closed

var _root: Control
var _points_label: Label
var _branches_box: HBoxContainer
var _data: Dictionary = {}
var _stat_line: Label
var _respec_btn: Button
var _note_label: Label


func _ready() -> void:
	layer = 41
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_load_data()
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("talents") or event.is_action_pressed("pause")):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	_refresh()
	visible = true
	PauseManager.hold(self, "talents")
	SettingsManager.apply_text_scale(self)


func close() -> void:
	visible = false
	PauseManager.release(self)
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _load_data() -> void:
	var f := FileAccess.open("res://data/talents.json", FileAccess.READ)
	if f == null:
		push_error("TalentScreen: cannot open data/talents.json")
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		_data = parsed


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(960, 540)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.10, 0.09, 0.15, 0.97)
	bg.set_corner_radius_all(12)
	bg.content_margin_left = 26.0
	bg.content_margin_right = 26.0
	bg.content_margin_top = 20.0
	bg.content_margin_bottom = 20.0
	panel.add_theme_stylebox_override("panel", bg)
	center.add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	panel.add_child(outer)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "TALENTS"
	title.add_theme_font_size_override("font_size", 26)
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_points_label = Label.new()
	_points_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	_points_label.add_theme_font_size_override("font_size", 18)
	header.add_child(_points_label)
	outer.add_child(header)

	_stat_line = Label.new()
	_stat_line.add_theme_font_size_override("font_size", 14)
	_stat_line.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	outer.add_child(_stat_line)

	_branches_box = HBoxContainer.new()
	_branches_box.add_theme_constant_override("separation", 18)
	_branches_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_branches_box)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	# A build is a 60-point blind commitment on a phone. Being able to take it
	# back is the difference between experimenting and reading a wiki.
	_respec_btn = Button.new()
	_respec_btn.text = "Respec (refund all points)"
	_respec_btn.custom_minimum_size = Vector2(280, 42)
	_respec_btn.pressed.connect(func() -> void:
		var n := GameState.respec_talents()
		if n > 0:
			AudioManager.play_sfx("ui_click")
			show_note("Refunded %d point(s) — spend them again." % n)
		_refresh()
	)
	footer.add_child(_respec_btn)
	var close_btn := Button.new()
	close_btn.text = "Close (T)"
	close_btn.custom_minimum_size = Vector2(200, 42)
	close_btn.pressed.connect(close)
	footer.add_child(close_btn)
	outer.add_child(footer)

	_note_label = Label.new()
	_note_label.add_theme_font_size_override("font_size", 14)
	_note_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
	outer.add_child(_note_label)


func show_note(text: String) -> void:
	_note_label.text = text


func _refresh() -> void:
	_points_label.text = "Points: %d" % GameState.talent_points
	# Live numbers, so a point is spent against a visible target rather than a
	# description. Every value below is the derived stat the game actually uses.
	_stat_line.text = "Level %d   ATK %d   DEF %d   HP %d/%d   MP %d/%d   SPD %d   Reg/s %.1f   Dodge +%.2fs" % [
		GameState.level,
		int(round(GameState.attack())), int(round(GameState.defense())),
		int(ceil(GameState.hp)), int(round(GameState.max_hp())),
		int(ceil(GameState.mp)), int(round(GameState.max_mp())),
		int(round(GameState.move_speed())),
		GameState.mp_regen_per_sec(),
		GameState.dodge_duration_bonus(),
	]
	for child in _branches_box.get_children():
		child.queue_free()
	for branch in _data.get("branches", []):
		_branches_box.add_child(_branch_column(branch))


func _branch_column(branch: Dictionary) -> Control:
	var bid := String(branch.get("id", ""))
	var col := PanelContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cbg := StyleBoxFlat.new()
	cbg.bg_color = Color(1, 1, 1, 0.04)
	cbg.set_corner_radius_all(8)
	cbg.content_margin_left = 14.0
	cbg.content_margin_right = 14.0
	cbg.content_margin_top = 12.0
	cbg.content_margin_bottom = 12.0
	col.add_theme_stylebox_override("panel", cbg)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	col.add_child(vbox)

	var name_label := Label.new()
	name_label.text = "%s  %d/%d" % [
		String(branch.get("name", bid)),
		int(GameState.talents.get(bid, 0)),
		int(branch.get("nodes", []).size()),
	]
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)

	var desc := Label.new()
	desc.text = String(branch.get("desc", ""))
	desc.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	desc.add_theme_font_size_override("font_size", 14)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc)

	var pts := int(GameState.talents.get(bid, 0))
	for node in branch.get("nodes", []):
		vbox.add_child(_node_row(bid, node, pts))
	return col


func _effect_numbers(node: Dictionary) -> String:
	## "ATK +6" / "Firebolt +25%" — the raw effect of one node.
	var parts: Array = []
	for k in ((node.get("effects", {}) as Dictionary).keys() as Array):
		var v := float(node["effects"][k])
		if k in ["atk", "def", "hp", "mp", "speed"]:
			parts.append("%s +%d" % [k.to_upper(), int(round(v))])
		elif k in ["atk_cd", "dmg_taken", "mp_cost", "potion", "whirl", "bolt"]:
			parts.append("%s %+d%%" % [k, int(round((v - 1.0) * 100.0))])
		elif k == "mp_regen":
			parts.append("MP/s +%.1f" % v)
		elif k == "dodge":
			parts.append("i-frames +%.2fs" % v)
		elif k == "lifesteal":
			parts.append("lifesteal +%d%%" % int(round(v * 100.0)))
		elif k in ["gold", "xp"]:
			parts.append("%s +%d%%" % [k, int(round((v - 1.0) * 100.0))])
		else:
			parts.append("%s %+g" % [k, v - 1.0 if k in ["gold",] else v])
	return " · ".join(parts)


func _node_row(bid: String, node: Dictionary, branch_points: int) -> Control:
	## Phase E §7: a node unlocks on points invested in its branch AND a character
	## level gate, so the row reports which of the two is missing.
	var req_points := int(node.get("req_points", int(node.get("tier", 1))))
	var req_level := int(node.get("req_level", 1))
	var active := GameState.node_unlocked(bid, node)
	var is_next := not active and branch_points == req_points - 1 and GameState.level >= req_level

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var nbg := StyleBoxFlat.new()
	nbg.bg_color = Color(0.35, 0.55, 0.35, 0.25) if active else Color(1, 1, 1, 0.03)
	nbg.set_corner_radius_all(6)
	nbg.content_margin_left = 10.0
	nbg.content_margin_right = 10.0
	nbg.content_margin_top = 8.0
	nbg.content_margin_bottom = 8.0
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", nbg)
	box.add_child(panel)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 3)
	panel.add_child(inner)

	var head := HBoxContainer.new()
	var nm := Label.new()
	nm.text = "%s" % String(node.get("name", ""))
	nm.add_theme_font_size_override("font_size", 15)
	nm.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8) if active else Color(1, 1, 1, 0.8))
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(nm)
	var tier_label := Label.new()
	tier_label.text = "T%d" % int(node.get("tier", 1))
	tier_label.add_theme_font_size_override("font_size", 14)
	tier_label.add_theme_color_override("font_color", Color(1, 0.85, 0.5, 0.7))
	head.add_child(tier_label)
	inner.add_child(head)

	var dsc := Label.new()
	dsc.text = String(node.get("desc", ""))
	if String(node.get("behaviour", "")) != "":
		# Engine-key nodes change behaviour rather than a number; mark them so the
		# choice reads as different in kind, not just different in size.
		dsc.text = "◆ " + dsc.text
	dsc.add_theme_font_size_override("font_size", 14)
	dsc.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	dsc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(dsc)

	# The exact numbers this node moves, so "Swift Strikes" is comparable to
	# "Power Strikes" at a glance instead of being two adjectives.
	var nums := _effect_numbers(node)
	if nums != "":
		var eff := Label.new()
		eff.text = nums
		eff.add_theme_font_size_override("font_size", 14)
		eff.add_theme_color_override("font_color", Color(1, 0.85, 0.5, 0.9))
		inner.add_child(eff)

	if active:
		var mark := Label.new()
		mark.text = "✓ Active"
		mark.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
		mark.add_theme_font_size_override("font_size", 14)
		inner.add_child(mark)
	elif is_next and GameState.talent_points > 0:
		var learn := Button.new()
		learn.text = "Learn (1 point)"
		learn.pressed.connect(func() -> void:
			GameState.spend_talent(bid)
			_refresh()
		)
		inner.add_child(learn)
	else:
		var lock := Label.new()
		var reason := GameState.node_locked_reason(bid, node)
		lock.text = ("Locked · %s" % reason) if reason != "" else "Locked"
		lock.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
		lock.add_theme_font_size_override("font_size", 14)
		inner.add_child(lock)
	return box
