class_name DialogueBox
extends CanvasLayer
## Branching dialogue UI (typewriter). Fully data-driven from DialogueDB.
## Pauses the world while open. Executes on_complete/choice actions
## (start_quest / set_flag / complete_objective / give_item / give_gold / give_xp).

signal dialogue_finished

const CHARS_PER_SEC := 45.0

var _dialogue: Dictionary = {}
var _node_id := ""
var _shown := 0
var _full_text := ""
var _waiting_choice := false

var _root: Control
var _panel: Panel
var _portrait: TextureRect
var _name_label: Label
var _text_label: RichTextLabel
var _hint_label: Label
var _choice_box: VBoxContainer


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_panel = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.11, 0.95)
	sb.border_color = Color(0.85, 0.75, 0.5, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 14.0
	sb.content_margin_bottom = 14.0
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.gui_input.connect(func(ev: InputEvent) -> void:
		if (ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed) \
				or (ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed):
			_advance()
	)
	_root.add_child(_panel)

	# Portrait on the left, text on the right: eleven characters used to be a
	# name and a paragraph with nothing to look at.
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 14)
	_panel.add_child(row)

	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(104, 104)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_portrait)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	row.add_child(vbox)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 18)
	_name_label.add_theme_color_override("font_color", Color(0.95, 0.8, 0.4))
	vbox.add_child(_name_label)

	_text_label = RichTextLabel.new()
	_text_label.bbcode_enabled = false
	_text_label.fit_content = true
	_text_label.scroll_active = false
	_text_label.add_theme_font_size_override("normal_font_size", 16)
	_text_label.add_theme_color_override("default_color", Color(0.93, 0.93, 0.95))
	vbox.add_child(_text_label)

	_choice_box = VBoxContainer.new()
	_choice_box.add_theme_constant_override("separation", 6)
	vbox.add_child(_choice_box)

	_hint_label = Label.new()
	_hint_label.text = "▼ E / tap to continue"
	_hint_label.add_theme_font_size_override("font_size", 14)
	_hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(_hint_label)


func _process(delta: float) -> void:
	if not visible or _waiting_choice:
		return
	if _shown < _full_text.length():
		_shown = mini(_full_text.length(), _shown + int(CHARS_PER_SEC * delta) + 1)
		_text_label.visible_characters = _shown


func layout(size: Vector2) -> void:
	## Sized from the viewport, so the box lands correctly on a phone in
	## landscape as well as on desktop.
	var w := minf(size.x * 0.72, 860.0)
	var h := 216.0 if _portrait != null and _portrait.visible else 200.0
	_panel.size = Vector2(w, h)
	_panel.position = Vector2((size.x - w) * 0.5, size.y - h - 24.0)


func start(dialogue: Dictionary) -> void:
	if dialogue.is_empty():
		return
	_dialogue = dialogue
	get_tree().paused = true
	visible = true
	if not get_tree().root.size_changed.is_connected(_relayout):
		get_tree().root.size_changed.connect(_relayout)
	_relayout()
	EventBus.dialogue_open = true
	EventBus.dialogue_opened.emit()
	_show_node(String(dialogue.get("start", "")))


func _relayout() -> void:
	layout(get_viewport().get_visible_rect().size)


func _show_node(id: String) -> void:
	var nodes: Dictionary = _dialogue.get("nodes", {})
	if id == "" or not nodes.has(id):
		_finish()
		return
	_node_id = id
	var node: Dictionary = nodes[id]
	var speaker := String(node.get("speaker", ""))
	_name_label.text = speaker
	var portrait_path := DialogueDB.portrait_for(speaker)
	_portrait.texture = load(portrait_path) if portrait_path != "" else null
	_portrait.visible = portrait_path != ""
	_full_text = String(node.get("text", ""))
	# Every line goes into the history as it is spoken, so a conversation can be
	# re-read later instead of existing only in the moment.
	GameState.record_line(speaker, _full_text)
	_shown = 0
	_text_label.text = _full_text
	_text_label.visible_characters = 0
	_waiting_choice = false
	_populate_choices(node)
	_hint_label.visible = not _waiting_choice


func _populate_choices(node: Dictionary) -> void:
	for child in _choice_box.get_children():
		child.queue_free()
	var choices: Array = node.get("choices", [])
	if choices.is_empty():
		return
	_waiting_choice = true
	for c in choices:
		var btn := Button.new()
		btn.text = "• " + String(c.get("text", "..."))
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(func() -> void: AudioManager.play_sfx("ui_click"))
		btn.pressed.connect(func() -> void: GameState.record_line("You", String(c.get("text", "..."))))
		btn.pressed.connect(_on_choice.bind(c))
		_choice_box.add_child(btn)


func _on_choice(choice: Dictionary) -> void:
	for a in choice.get("actions", []):
		_execute_action(a)
	_show_node(String(choice.get("next", "")))


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _waiting_choice:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("attack"):
		_advance()
		get_viewport().set_input_as_handled()


func _advance() -> void:
	# Finish typewriter first, then advance.
	if _shown < _full_text.length():
		_shown = _full_text.length()
		_text_label.visible_characters = _shown
		return
	var nodes: Dictionary = _dialogue.get("nodes", {})
	var node: Dictionary = nodes.get(_node_id, {})
	_show_node(String(node.get("next", "")))


func _finish() -> void:
	for a in _dialogue.get("on_complete", []):
		_execute_action(a)
	visible = false
	get_tree().paused = false
	EventBus.dialogue_open = false
	EventBus.dialogue_closed.emit()
	dialogue_finished.emit()
	_dialogue = {}


func _execute_action(a: Dictionary) -> void:
	var act := String(a.get("action", ""))
	match act:
		"start_quest":
			QuestManager.start_quest(String(a.get("quest", "")))
		"set_flag":
			QuestManager.register_flag(String(a.get("flag", "")))
		"complete_objective":
			QuestManager.complete_objective(String(a.get("quest", "")), String(a.get("objective", "")))
		"give_item":
			GameState.add_item(String(a.get("item", "")), int(a.get("qty", 1)))
			EventBus.item_picked_up.emit(String(a.get("item", "")), 1)
		"give_gold":
			GameState.add_gold(int(a.get("amount", 0)))
		"give_xp":
			GameState.add_xp(int(a.get("amount", 0)))
