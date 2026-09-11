class_name InventoryScreen
extends CanvasLayer
## Inventory & equipment screen. Pauses the game while open.
## Left: equipment slots + live stat sheet. Right: item rows with
## Use / Equip / Unequip / Drop actions. Fully anchor-based layout.

signal closed
signal drop_requested(item_id: String)

const SLOTS := ["weapon", "armor", "accessory"]

var _root: Control
var _item_list: VBoxContainer
var _equip_labels: Dictionary = {}
var _unequip_btns: Dictionary = {}
var _stats_label: Label
var _gold_label: Label
## Sorting / filtering / selection: 123 items with no way to order them meant
## scrolling blind on a phone.
var _sort_mode := "rarity"          # rarity | power | name | type
var _filter_mode := "all"           # all | gear | consumable | material
var _selected := ""
var _detail_label: Label
var _count_label: Label


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("inventory") or event.is_action_pressed("pause")):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	_refresh()
	visible = true
	PauseManager.hold(self, "inventory")
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


# --- Construction -------------------------------------------------------------

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
	panel.custom_minimum_size = Vector2(920, 520)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.09, 0.11, 0.15, 0.97)
	bg.set_corner_radius_all(12)
	bg.content_margin_left = 24.0
	bg.content_margin_right = 24.0
	bg.content_margin_top = 18.0
	bg.content_margin_bottom = 18.0
	panel.add_theme_stylebox_override("panel", bg)
	center.add_child(panel)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 28)
	panel.add_child(columns)

	columns.add_child(_build_left_column())
	columns.add_child(_build_right_column())


func _build_left_column() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(320, 0)
	box.add_theme_constant_override("separation", 10)

	var title := Label.new()
	title.text = "INVENTORY"
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)

	_gold_label = Label.new()
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	box.add_child(_gold_label)

	_count_label = Label.new()
	_count_label.add_theme_font_size_override("font_size", 14)
	_count_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	box.add_child(_count_label)

	var sort_row := HBoxContainer.new()
	sort_row.add_theme_constant_override("separation", 6)
	var sort_label := Label.new()
	sort_label.text = "Sort"
	sort_label.add_theme_font_size_override("font_size", 14)
	sort_row.add_child(sort_label)
	for mode in ["rarity", "power", "name", "type"]:
		var sb := Button.new()
		sb.text = String(mode).capitalize()
		sb.add_theme_font_size_override("font_size", 14)
		sb.pressed.connect(func() -> void:
			_sort_mode = String(mode)
			_refresh()
		)
		sort_row.add_child(sb)
	box.add_child(sort_row)

	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 6)
	var filter_label := Label.new()
	filter_label.text = "Show"
	filter_label.add_theme_font_size_override("font_size", 14)
	filter_row.add_child(filter_label)
	for mode in ["all", "gear", "consumable", "material"]:
		var fb := Button.new()
		fb.text = String(mode).capitalize()
		fb.add_theme_font_size_override("font_size", 14)
		fb.pressed.connect(func() -> void:
			_filter_mode = String(mode)
			_refresh()
		)
		filter_row.add_child(fb)
	box.add_child(filter_row)

	var eq_title := Label.new()
	eq_title.text = "— Equipment —"
	eq_title.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	box.add_child(eq_title)

	for slot in SLOTS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lbl := Label.new()
		lbl.custom_minimum_size = Vector2(210, 0)
		_equip_labels[slot] = lbl
		var unequip := Button.new()
		unequip.text = "Unequip"
		unequip.pressed.connect(func() -> void:
			GameState.unequip(slot)
			_refresh()
		)
		_unequip_btns[slot] = unequip
		row.add_child(lbl)
		row.add_child(unequip)
		box.add_child(row)

	_stats_label = Label.new()
	_stats_label.add_theme_color_override("font_color", Color(0.75, 0.9, 0.75))
	_stats_label.add_theme_font_size_override("font_size", 15)
	box.add_child(_stats_label)

	# Details for the tapped item. On a phone there is no hover, so the tooltip
	# that explained every item was unreachable: this panel is what it becomes.
	_detail_label = Label.new()
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_label.custom_minimum_size = Vector2(300, 96)
	_detail_label.add_theme_font_size_override("font_size", 14)
	_detail_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0, 0.95))
	box.add_child(_detail_label)

	var close_btn := Button.new()
	close_btn.text = "Close (I)"
	close_btn.custom_minimum_size = Vector2(0, 42)
	close_btn.pressed.connect(close)
	box.add_child(close_btn)
	return box


func _build_right_column() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(480, 0)
	# The item rows are built to fit the column; a horizontal bar only ever let
	# their "[type]" tag scroll off the right edge instead of wrapping.
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	_item_list = VBoxContainer.new()
	_item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_item_list)
	return scroll


# --- Refresh ------------------------------------------------------------------

func _refresh() -> void:
	_gold_label.text = "Gold: %d" % GameState.gold

	for slot in SLOTS:
		var id: String = GameState.equipment[slot]
		var lbl: Label = _equip_labels[slot]
		lbl.text = "%s: %s" % [slot.capitalize(), ItemsDB.item_name(id) if id != "" else "—"]
		# An empty slot has nothing to take off: an enabled "Unequip" was a
		# control that could only ever no-op.
		var unequip_btn: Button = _unequip_btns.get(slot)
		if unequip_btn != null:
			unequip_btn.disabled = id == ""

	_stats_label.text = "Lv %d  ·  HP %.0f/%.0f  ·  MP %.0f/%.0f\nATK %.1f  ·  DEF %.1f  ·  SPD %.0f" % [
		GameState.level,
		GameState.hp, GameState.max_hp(),
		GameState.mp, GameState.max_mp(),
		GameState.attack(), GameState.defense(), GameState.move_speed(),
	]

	for child in _item_list.get_children():
		child.queue_free()

	if GameState.inventory.is_empty():
		var empty := Label.new()
		empty.text = "Your bag is empty."
		empty.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
		_item_list.add_child(empty)
		return

	var ids: Array = []
	for item_id in GameState.inventory.keys():
		if _passes_filter(String(item_id)):
			ids.append(String(item_id))
	ids.sort_custom(func(a: String, b: String) -> bool: return _before(a, b))
	_count_label.text = "%d shown / %d carried" % [ids.size(), GameState.inventory.size()]
	if ids.is_empty():
		var none := Label.new()
		none.text = "Nothing here for that filter."
		none.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
		_item_list.add_child(none)
	_update_detail()
	for item_id in ids:
		_item_list.add_child(_item_row(item_id, int(GameState.inventory[item_id])))


func _passes_filter(item_id: String) -> bool:
	if _filter_mode == "all":
		return true
	return ItemsDB.get_type(item_id) == _filter_mode


func _before(a: String, b: String) -> bool:
	## Ordering the player asked for. "power" is the weighted stat budget the
	## rarity ladder is built on, so the list can be read as a strength ranking.
	match _sort_mode:
		"power":
			return ItemsDB.stat_budget_used(a) > ItemsDB.stat_budget_used(b)
		"name":
			return ItemsDB.item_name(a).to_lower() < ItemsDB.item_name(b).to_lower()
		"type":
			if ItemsDB.get_type(a) != ItemsDB.get_type(b):
				return ItemsDB.get_type(a) < ItemsDB.get_type(b)
			return ItemsDB.item_name(a) < ItemsDB.item_name(b)
		_:
			if ItemsDB.rarity_rank(a) != ItemsDB.rarity_rank(b):
				return ItemsDB.rarity_rank(a) > ItemsDB.rarity_rank(b)
			return ItemsDB.item_name(a) < ItemsDB.item_name(b)


func _update_detail() -> void:
	if _selected == "" or int(GameState.inventory.get(_selected, 0)) < 1:
		_detail_label.text = "Tap an item to see what it does."
		return
	var it: Dictionary = ItemsDB.get_item(_selected)
	var lines: Array = [ItemsDB.item_name(_selected)]
	lines.append(String(it.get("desc", "")))
	var stat := _stat_line(it)
	if stat != "":
		lines.append(stat)
	lines.append("Value %d g · %s" % [ItemsDB.get_value(_selected),
		ItemsDB.get_rarity(_selected).capitalize()])
	var delta := _compare_text(_selected)
	if delta != "":
		lines.append(delta)
	_detail_label.text = "\n".join(lines)


func _compare_text(item_id: String) -> String:
	## "Equipped: Leather Armor — ATK 0 · DEF +6 · HP +18" / what you lose.
	var slot := ItemsDB.get_slot(item_id)
	if slot == "":
		return ""
	var worn: String = String(GameState.equipment.get(slot, ""))
	if worn == "":
		return "Equipped slot is empty — every point is a gain."
	var what: Dictionary = ItemsDB.get_item(item_id)
	var have: Dictionary = ItemsDB.get_item(worn)
	var keys := ["atk", "def", "hp", "mp", "speed", "crit", "lifesteal"]
	var parts: Array = []
	for k in keys:
		var d := float(what.get(k, 0)) - float(have.get(k, 0))
		if absf(d) < 0.0001:
			continue
		if k in ["crit", "lifesteal"]:
			parts.append("%s %+.1f%%" % [k.to_upper(), d * 100.0])
		else:
			parts.append("%s %+d" % [k.to_upper(), int(round(d))])
	if parts.is_empty():
		return "Equipped (%s) is numerically identical." % ItemsDB.item_name(worn)
	return "vs equipped %s: %s" % [ItemsDB.item_name(worn), " · ".join(parts)]


func _item_row(item_id: String, qty: int) -> Control:
	var it: Dictionary = ItemsDB.get_item(item_id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var name_label := Label.new()
	name_label.text = "%s ×%d" % [ItemsDB.item_name(item_id), qty]
	name_label.custom_minimum_size = Vector2(140, 0)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	# Kept for desktops, but the details panel below is what phones use.
	name_label.tooltip_text = ItemsDB.get_desc(item_id)
	name_label.mouse_filter = Control.MOUSE_FILTER_STOP
	name_label.gui_input.connect(func(ev: InputEvent) -> void:
		if (ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed) \
				or (ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed):
			_selected = item_id
			_update_detail()
	)
	# Rarity is the power ordering, so it is the thing the player scans for.
	# Legendary/mythical gear also gets a marker so it reads at a glance.
	name_label.add_theme_color_override("font_color", ItemsDB.rarity_color(item_id))
	if ItemsDB.rarity_rank(item_id) >= 3:
		name_label.text = "★ " + name_label.text
	row.add_child(name_label)

	var rarity_label := Label.new()
	rarity_label.text = ItemsDB.get_rarity(item_id).capitalize()
	rarity_label.add_theme_color_override("font_color", ItemsDB.rarity_color(item_id))
	rarity_label.add_theme_font_size_override("font_size", 14)
	rarity_label.custom_minimum_size = Vector2(62, 0)
	rarity_label.clip_text = true
	row.add_child(rarity_label)

	var stat_text := _stat_line(it)
	var stat_label := Label.new()
	stat_label.text = stat_text
	stat_label.add_theme_font_size_override("font_size", 14)
	stat_label.add_theme_color_override("font_color", Color(0.85, 0.95, 0.85, 0.9))
	stat_label.custom_minimum_size = Vector2(0, 0)
	stat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stat_label.clip_text = true
	row.add_child(stat_label)

	var type_label := Label.new()
	# Short tags: the full word "consumable" was clipped to "[consum" in the
	# narrow type column, which read as a half-rendered label.
	type_label.text = _type_tag(String(it.get("type", "?")))
	type_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	type_label.add_theme_font_size_override("font_size", 14)
	type_label.custom_minimum_size = Vector2(52, 0)
	type_label.clip_text = true
	row.add_child(type_label)

	var primary := Button.new()
	primary.add_theme_font_size_override("font_size", 15)
	if String(it.get("type", "")) == "consumable":
		primary.text = "Use"
		primary.pressed.connect(func() -> void:
			if GameState.use_item(item_id):
				AudioManager.play_sfx("item_use")
			else:
				# A consumable that does nothing right now must say so out loud.
				AudioManager.play_sfx("denied")
			_refresh()
		)
	else:
		# Materials and quest items have no equipment slot: an "Equip" button that
		# only ever buzzed denied was a control that lied. Hide it for those.
		if ItemsDB.get_slot(item_id) == "":
			primary.visible = false
		else:
			primary.text = "Equip"
			primary.pressed.connect(func() -> void:
				if GameState.equip(item_id):
					AudioManager.play_sfx("equip")
				else:
					AudioManager.play_sfx("denied")
				_refresh()
			)
	row.add_child(primary)

	var drop := Button.new()
	drop.text = "Drop"
	drop.add_theme_font_size_override("font_size", 15)
	drop.pressed.connect(func() -> void:
		drop_requested.emit(item_id)
		_refresh()
	)
	row.add_child(drop)
	return row


func _type_tag(raw_type: String) -> String:
	## Compact column tag so "consumable" cannot clip to "[consum".
	match raw_type:
		"gear":
			return "[gear]"
		"consumable":
			return "[cons]"
		"material":
			return "[mat]"
		_:
			return "[%s]" % raw_type


func _stat_line(it: Dictionary) -> String:
	## Compact "+4 ATK · +12 HP · 4% lifesteal" summary shown in the row, so the
	## power ordering is visible without opening a tooltip.
	var parts := []
	var names := {
		"atk": "ATK", "def": "DEF", "hp": "HP", "mp": "MP",
		"speed": "SPD", "mp_regen": "MP/s", "crit": "CRIT",
	}
	for key in ["atk", "def", "hp", "mp", "speed", "mp_regen"]:
		if it.has(key):
			parts.append("%+d %s" % [int(it[key]), names[key]])
	if it.has("crit"):
		parts.append("%d%% CRIT" % int(round(float(it["crit"]) * 100.0)))
	if it.has("lifesteal"):
		parts.append("%d%% LEECH" % int(round(float(it["lifesteal"]) * 100.0)))
	if it.get("type", "") == "consumable":
		if it.has("heal"):
			parts.append("+%d HP" % int(it["heal"]))
		if it.has("restore_mp"):
			parts.append("+%d MP" % int(it["restore_mp"]))
	return " · ".join(parts)
