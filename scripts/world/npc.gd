class_name NPC
extends NPCController
## Interactable NPC. Emits `interacted` when the player presses interact in
## range; main.gd routes to dialogue (or the shop for vendors). Shows a
## prompt and an optional "!" quest marker.
##
## Movement, the schedule state machine and idle barks come from NPCController
## (Phase E §3); this class owns the player-facing interaction surface.

signal interacted(npc: NPC)

@export var display_name: String = "Elder Rowan"
@export var is_vendor: bool = false
@export var show_quest_marker: bool = true
## Composed LPC sheet (tools/lpc_compose.py). Empty = keep the placeholder art.
@export var sprite_sheet: String = ""

var _player_in_range := false
var _facing_row := 2  # south

@onready var _sprite: Sprite2D = $Sprite
@onready var _prompt: Label = $Prompt
@onready var _marker: Label = $Marker
@onready var _name_label: Label = $NameTag


func _ready() -> void:
	super._ready()  # NPCController: group, home, schedule
	if display_name == "" or display_name == "Elder Rowan":
		display_name = String(roster_entry(npc_id).get("display_name", display_name))
	_apply_sheet()
	_name_label.text = display_name
	_prompt.visible = false
	_marker.visible = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _apply_sheet() -> void:
	## Slice the composed LPC sheet; the controller picks the idle block while
	## standing at a schedule point and the walk block while moving to one.
	if sprite_sheet == "" or not ResourceLoader.exists(sprite_sheet):
		return
	var tex: Texture2D = load(sprite_sheet)
	if tex == null:
		return
	_sprite.texture = tex
	_sprite.hframes = 13
	_sprite.vframes = 20
	_sprite.offset = Vector2(0, -10)          # LPC frames sit above the pivot
	_sprite.frame = IDLE_FRAME_BASE           # idle block, south row, frame 0


func _process(delta: float) -> void:
	if sprite_sheet == "":
		return
	advance_sprite_anim(delta, _sprite, _facing_row)


func set_marker(on: bool) -> void:
	if _marker:
		_marker.visible = on and show_quest_marker


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		_prompt.visible = true
		add_to_group("interactable_in_range")


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		_prompt.visible = false
		remove_from_group("interactable_in_range")


func _unhandled_input(event: InputEvent) -> void:
	if _player_in_range and event.is_action_pressed("interact"):
		talk()  # NPCController: holds position while the conversation is open
		interacted.emit(self)
		get_viewport().set_input_as_handled()


func interact_from_ui() -> void:
	## Touch entry point, called by the HUD's Talk button for the closest target.
	if not _player_in_range:
		return
	talk()
	interacted.emit(self)


func interact_label() -> String:
	if is_vendor:
		return "Trade"
	return "Talk"


func _physics_process(delta: float) -> void:
	super._physics_process(delta)  # schedule / flee / bark
	if _sprite != null:
		# Face the direction of travel (composed sheet order: n, w, s, e).
		var want_row := 2
		if state == State.WALK_TO_POINT or state == State.FLEE_COMBAT:
			var d := target - global_position
			if absf(d.x) > absf(d.y):
				want_row = 3 if d.x > 0.0 else 1
			elif d.y < 0.0:
				want_row = 0
		_facing_row = want_row

