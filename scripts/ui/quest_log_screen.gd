class_name QuestLogScreen
extends CanvasLayer
## Quest log: full list of main + side quests with state and objective
## progress. Opened from the pause menu (game already paused).

var _root: Control
var _list: VBoxContainer


func _ready() -> void:
	layer = 55
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("pause") or event.is_action_pressed("interact")):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	_refresh()
	visible = true


func close() -> void:
	visible = false


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 500)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.09, 0.10, 0.14, 0.97)
	bg.set_corner_radius_all(12)
	bg.content_margin_left = 24.0
	bg.content_margin_right = 24.0
	bg.content_margin_top = 18.0
	bg.content_margin_bottom = 18.0
	panel.add_theme_stylebox_override("panel", bg)
	center.add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	panel.add_child(outer)

	var title := Label.new()
	title.text = "QUEST LOG"
	title.add_theme_font_size_override("font_size", 24)
	outer.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 360)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)
	outer.add_child(scroll)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(200, 42)
	close_btn.pressed.connect(close)
	outer.add_child(close_btn)


func _refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	for qid in QuestManager.data.keys():
		_list.add_child(_quest_block(String(qid)))
	_list.add_child(_secrets_block())


func _secrets_block() -> Control:
	## Phase F6: the world's secrets, as a count you can watch climb. Found ones
	## are named; unfound ones stay a dash, in region order, so the list says how
	## much is out there without saying where.
	var v := VBoxContainer.new()
	var head := Label.new()
	head.text = "%s   (%d kinds: %s)" % [SecretsDB.summary(),
		SecretsDB.by_kind().size(), _kind_summary()]
	v.add_child(head)
	for sid in SecretsDB.all():
		var secret: Dictionary = SecretsDB.get_secret(String(sid))
		var row := Label.new()
		if SecretsDB.is_found(String(sid)):
			row.text = "  * %s  [%s]" % [String(secret.get("name", sid)),
				String(secret.get("region", "?"))]
		else:
			row.text = "  - ? ? ?  [%s]" % String(secret.get("region", "?"))
			row.modulate = Color(1, 1, 1, 0.45)
		v.add_child(row)
	return v


func _kind_summary() -> String:
	var parts := []
	for k in SecretsDB.by_kind().keys():
		parts.append("%s %d" % [k, int(SecretsDB.by_kind()[k])])
	parts.sort()
	return ", ".join(parts)


func _quest_block(qid: String) -> Control:
	var quest: Dictionary = QuestManager.data.get(qid, {})
	var state := String(GameState.quests.get(qid, ""))
	var repeatable := bool(quest.get("repeatable", false))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)

	var head := Label.new()
	var tag := "[Hidden]"
	var color := Color(1, 1, 1, 0.35)
	if state == "active":
		tag = "[Active]"
		color = Color(0.6, 1.0, 0.65)
	elif state == "done":
		tag = "[Done]"
		color = Color(0.75, 0.8, 1.0)
	elif repeatable:
		tag = "[Repeatable]"
		color = Color(1.0, 0.9, 0.6)
	head.text = "%s %s" % [tag, String(quest.get("name", qid))]
	head.add_theme_color_override("font_color", color)
	head.add_theme_font_size_override("font_size", 17)
	box.add_child(head)

	var desc := Label.new()
	desc.text = String(quest.get("desc", ""))
	desc.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	desc.add_theme_font_size_override("font_size", 14)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(desc)

	if state == "active":
		for obj in quest.get("objectives", []):
			var oid := String(obj.get("id", ""))
			var need := int(obj.get("count", 1))
			var cur := QuestManager.objective_count(qid, oid)
			var line := Label.new()
			line.text = "    %s %s (%d/%d)" % ["✓" if cur >= need else "·", String(obj.get("desc", oid)), cur, need]
			line.add_theme_color_override("font_color", Color(0.85, 0.9, 0.8))
			line.add_theme_font_size_override("font_size", 14)
			box.add_child(line)
	return box
