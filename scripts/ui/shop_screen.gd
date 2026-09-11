class_name ShopScreen
extends CanvasLayer
## Vendor shop: buy stock at list price, sell anything from the bag at half
## value. Pauses the game while open.

signal closed

var _root: Control
var _title: Label
var _gold_label: Label
var _market_label: Label
var _market := 1.0
var _buy_list: VBoxContainer
var _sell_list: VBoxContainer
var _stock: Array = []


func _ready() -> void:
	layer = 45
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("pause") or event.is_action_pressed("interact")):
		close()
		get_viewport().set_input_as_handled()


func open(vendor_name: String, stock: Array, market: float = 1.0) -> void:
	_stock = stock
	_market = clampf(market, 0.6, 1.6)
	_title.text = "%s's Wares" % vendor_name
	_market_label.text = _market_blurb()
	_refresh()
	visible = true
	get_tree().paused = true


func close() -> void:
	visible = false
	get_tree().paused = false
	closed.emit()


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
	panel.custom_minimum_size = Vector2(860, 500)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.11, 0.10, 0.08, 0.97)
	bg.set_corner_radius_all(12)
	bg.content_margin_left = 24.0
	bg.content_margin_right = 24.0
	bg.content_margin_top = 18.0
	bg.content_margin_bottom = 18.0
	panel.add_theme_stylebox_override("panel", bg)
	center.add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	panel.add_child(outer)

	var header := HBoxContainer.new()
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	header.add_child(_title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_gold_label = Label.new()
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	_gold_label.add_theme_font_size_override("font_size", 18)
	header.add_child(_gold_label)

	# Prices are local, and the player can see that they are: the same sword is
	# not the same sword in Ashvow and in Ashport.
	_market_label = Label.new()
	_market_label.add_theme_font_size_override("font_size", 14)
	_market_label.modulate = Color(1, 1, 1, 0.7)
	outer.add_child(header)
	outer.add_child(_market_label)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(columns)

	var buy_scroll := ScrollContainer.new()
	buy_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy_scroll.custom_minimum_size = Vector2(400, 0)
	_buy_list = VBoxContainer.new()
	_buy_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_buy_list.add_theme_constant_override("separation", 6)
	buy_scroll.add_child(_buy_list)
	columns.add_child(buy_scroll)

	var sell_scroll := ScrollContainer.new()
	sell_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell_scroll.custom_minimum_size = Vector2(380, 0)
	_sell_list = VBoxContainer.new()
	_sell_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sell_list.add_theme_constant_override("separation", 6)
	sell_scroll.add_child(_sell_list)
	columns.add_child(sell_scroll)

	var close_btn := Button.new()
	close_btn.text = "Leave Shop (Esc)"
	close_btn.custom_minimum_size = Vector2(220, 42)
	close_btn.pressed.connect(close)
	outer.add_child(close_btn)


func _refresh() -> void:
	_gold_label.text = "Gold: %d" % GameState.gold
	if _market_label != null:
		_market_label.text = _market_blurb()

	for child in _buy_list.get_children():
		child.queue_free()
	var buy_header := Label.new()
	buy_header.text = "— Buy —"
	buy_header.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	_buy_list.add_child(buy_header)
	for item_id in _stock:
		_buy_list.add_child(_buy_row(String(item_id)))

	for child in _sell_list.get_children():
		child.queue_free()
	var sell_header := Label.new()
	sell_header.text = "— Sell (local rate) —"
	sell_header.add_theme_color_override("font_color", Color(1.0, 0.8, 0.6))
	_sell_list.add_child(sell_header)
	if GameState.inventory.is_empty():
		var empty := Label.new()
		empty.text = "Nothing to sell."
		empty.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
		_sell_list.add_child(empty)
	else:
		for item_id in GameState.inventory.keys():
			_sell_list.add_child(_sell_row(String(item_id), int(GameState.inventory[item_id])))


func _buy_row(item_id: String) -> Control:
	var price := buy_price(item_id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = "%s" % ItemsDB.item_name(item_id)
	label.custom_minimum_size = Vector2(190, 0)
	label.tooltip_text = ItemsDB.get_desc(item_id)
	row.add_child(label)
	var price_label := Label.new()
	price_label.text = "%d g" % price
	price_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	price_label.custom_minimum_size = Vector2(70, 0)
	row.add_child(price_label)
	var btn := Button.new()
	btn.text = "Buy"
	btn.disabled = GameState.gold < price
	btn.pressed.connect(func() -> void: _buy(item_id, price))
	row.add_child(btn)
	return row


func _sell_row(item_id: String, qty: int) -> Control:
	var price := sell_price(item_id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = "%s ×%d" % [ItemsDB.item_name(item_id), qty]
	label.custom_minimum_size = Vector2(190, 0)
	row.add_child(label)
	var price_label := Label.new()
	price_label.text = "%d g" % price
	price_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	price_label.custom_minimum_size = Vector2(70, 0)
	row.add_child(price_label)
	var btn := Button.new()
	btn.text = "Sell"
	btn.pressed.connect(func() -> void: _sell(item_id, price))
	row.add_child(btn)
	return row


func buy_price(item_id: String) -> int:
	## What this town charges. Dear towns charge up to +18%, trading towns as
	## little as -12%.
	return maxi(1, int(round(float(ItemsDB.get_value(item_id)) * _market)))


func sell_price(item_id: String) -> int:
	## Buying low and selling high only works if the two ends move in opposite
	## directions, so the sell rate is the mirror of the buy rate around half.
	return maxi(1, int(round(float(ItemsDB.get_value(item_id)) * 0.5 * (2.0 - _market))))


func _market_blurb() -> String:
	if _market >= 1.12:
		return "Prices here are cruel — but the same goods fetch well."
	if _market <= 0.92:
		return "A trading town: cheap wares, poor prices for your own."
	return "Fair local prices."


func _buy(item_id: String, price: int) -> void:
	if GameState.gold < price:
		AudioManager.play_sfx("denied")
		return
	GameState.add_gold(-price)
	GameState.add_item(item_id, 1)
	AudioManager.play_sfx("coin")     # a coin, not the same blip as a menu click
	GameState.ledger_add("purchase", "%s ← %d g" % [ItemsDB.item_name(item_id), price])
	_refresh()


func _sell(item_id: String, price: int) -> void:
	# Never sell what's currently equipped.
	for slot in GameState.equipment:
		if GameState.equipment[slot] == item_id:
			AudioManager.play_sfx("denied")
			return
	if not GameState.remove_item(item_id, 1):
		return
	GameState.add_gold(price, "trade")   # selling is trade, not a find (audit G7)
	GameState.ledger_add("sale", "%s → %d g" % [ItemsDB.item_name(item_id), price])
	AudioManager.play_sfx("purchase")  # the till, not the coin
	_refresh()
