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
var _stats_label: Label
var _gold_label: Label


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
	get_tree().paused = true


func close() -> void:
	visible = false
	get_tree().paused = false
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
		row.add_child(lbl)
		row.add_child(unequip)
		box.add_child(row)

	_stats_label = Label.new()
	_stats_label.add_theme_color_override("font_color", Color(0.75, 0.9, 0.75))
	_stats_label.add_theme_font_size_override("font_size", 15)
	box.add_child(_stats_label)

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

	for item_id in GameState.inventory.keys():
		_item_list.add_child(_item_row(String(item_id), int(GameState.inventory[item_id])))


func _item_row(item_id: String, qty: int) -> Control:
	var it: Dictionary = ItemsDB.get_item(item_id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var name_label := Label.new()
	name_label.text = "%s ×%d" % [ItemsDB.item_name(item_id), qty]
	name_label.custom_minimum_size = Vector2(190, 0)
	name_label.tooltip_text = ItemsDB.get_desc(item_id)
	row.add_child(name_label)

	var type_label := Label.new()
	type_label.text = "[%s]" % String(it.get("type", "?"))
	type_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	type_label.add_theme_font_size_override("font_size", 13)
	type_label.custom_minimum_size = Vector2(110, 0)
	row.add_child(type_label)

	var primary := Button.new()
	if String(it.get("type", "")) == "consumable":
		primary.text = "Use"
		primary.pressed.connect(func() -> void:
			GameState.use_item(item_id)
			_refresh()
		)
	else:
		primary.text = "Equip"
		primary.pressed.connect(func() -> void:
			GameState.equip(item_id)
			_refresh()
		)
	row.add_child(primary)

	var drop := Button.new()
	drop.text = "Drop"
	drop.pressed.connect(func() -> void:
		drop_requested.emit(item_id)
		_refresh()
	)
	row.add_child(drop)
	return row
