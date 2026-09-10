class_name NPC
extends Area2D
## Interactable NPC. Emits `interacted` when the player presses interact in
## range; main.gd routes to dialogue (or the shop for vendors). Shows a
## prompt and an optional "!" quest marker.

signal interacted(npc: NPC)

@export var npc_id: String = "elder_rowan"
@export var display_name: String = "Elder Rowan"
@export var is_vendor: bool = false
@export var show_quest_marker: bool = true
## Composed LPC sheet (tools/lpc_compose.py). Empty = keep the placeholder art.
@export var sprite_sheet: String = ""

var _player_in_range := false
var _anim_frame := 0.0
var _frame_count := 2

@onready var _sprite: Sprite2D = $Sprite
@onready var _prompt: Label = $Prompt
@onready var _marker: Label = $Marker
@onready var _name_label: Label = $NameTag


func _ready() -> void:
	add_to_group("npc")
	_apply_sheet()
	_name_label.text = display_name
	_prompt.visible = false
	_marker.visible = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _apply_sheet() -> void:
	## Idle animation only: NPCs are stationary, so we slice the composed sheet
	## and loop the 'idle' block's south-facing row.
	if sprite_sheet == "" or not ResourceLoader.exists(sprite_sheet):
		return
	var tex: Texture2D = load(sprite_sheet)
	if tex == null:
		return
	_sprite.texture = tex
	_sprite.hframes = 13
	_sprite.vframes = 20
	_sprite.offset = Vector2(0, -10)          # LPC frames sit above the pivot
	_sprite.frame = 2 * 13                    # idle block, south row, frame 0


func _process(delta: float) -> void:
	if sprite_sheet == "":
		return
	_anim_frame += delta * 4.0
	while _anim_frame >= float(_frame_count):
		_anim_frame -= float(_frame_count)
	_sprite.frame = 2 * 13 + int(_anim_frame)


func set_marker(on: bool) -> void:
	if _marker:
		_marker.visible = on and show_quest_marker


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		_prompt.visible = true


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		_prompt.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if _player_in_range and event.is_action_pressed("interact"):
		interacted.emit(self)
		get_viewport().set_input_as_handled()
