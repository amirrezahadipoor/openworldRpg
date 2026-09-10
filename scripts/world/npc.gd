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

var _player_in_range := false

@onready var _prompt: Label = $Prompt
@onready var _marker: Label = $Marker
@onready var _name_label: Label = $NameTag


func _ready() -> void:
	add_to_group("npc")
	_name_label.text = display_name
	_prompt.visible = false
	_marker.visible = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


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
