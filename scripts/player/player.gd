class_name Player
extends CharacterBody2D
## Player controller: acceleration-based movement, 8-way facing, dodge roll
## with i-frames, directional melee attack (hit/hurtbox areas).
## Input sources: keyboard Input actions + touch (VirtualJoystick sets
## `external_input`; ActionButtons press the same Input actions).

const ACCELERATION := 1600.0
const FRICTION := 1500.0
const DODGE_SPEED := 540.0
const DODGE_DURATION := 0.28
const DODGE_COOLDOWN := 0.6
const ATTACK_COOLDOWN := 0.35
const ATTACK_ACTIVE_TIME := 0.12

## Fed by the virtual joystick (touch). Zero → fall back to keyboard actions.
var external_input := Vector2.ZERO

var facing := Vector2.RIGHT
var invulnerable := false

var _dodge_timer := 0.0
var _dodge_cd := 0.0
var _dodge_dir := Vector2.RIGHT
var _attack_cd := 0.0
var _attack_active := 0.0

@onready var sprite: Sprite2D = $Sprite
@onready var attack_pivot: Node2D = $AttackPivot
@onready var attack_area: Area2D = $AttackPivot/AttackArea
@onready var attack_shape: CollisionShape2D = $AttackPivot/AttackArea/AttackShape


func _ready() -> void:
	add_to_group("player")
	GameState.hp = GameState.max_hp()
	GameState.mp = GameState.max_mp()
	attack_shape.disabled = true


func _physics_process(delta: float) -> void:
	_dodge_cd = maxf(_dodge_cd - delta, 0.0)
	_attack_cd = maxf(_attack_cd - delta, 0.0)

	if _dodge_timer > 0.0:
		_dodge_timer -= delta
		invulnerable = true
		velocity = _dodge_dir * DODGE_SPEED
	elif _attack_active > 0.0:
		_attack_active -= delta
		invulnerable = false
		velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)
		if _attack_active <= 0.0:
			attack_shape.disabled = true
	else:
		invulnerable = false
		var move := _read_move_input()
		if move.length_squared() > 0.01:
			facing = move.normalized()
			attack_pivot.rotation = facing.angle()
			sprite.flip_h = facing.x < 0.0
			var top_speed := GameState.move_speed()
			velocity = velocity.move_toward(move * top_speed, ACCELERATION * delta)
		else:
			velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)
		if Input.is_action_just_pressed("attack") and _attack_cd <= 0.0:
			_start_attack()
		elif Input.is_action_just_pressed("dodge") and _dodge_cd <= 0.0:
			_start_dodge(move)

	move_and_slide()


func _read_move_input() -> Vector2:
	if external_input.length_squared() > 0.01:
		return external_input.limit_length(1.0)
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


func _start_attack() -> void:
	_attack_cd = ATTACK_COOLDOWN * GameState.attack_cooldown_mult()
	_attack_active = ATTACK_ACTIVE_TIME
	attack_shape.disabled = false
	EventBus.attack_swung.emit(self)
	AudioManager.play_sfx("attack_swing")
	_resolve_attack_hits()


func _resolve_attack_hits() -> void:
	await get_tree().process_frame  # let physics overlaps update first
	if attack_area == null:
		return
	for area in attack_area.get_overlapping_areas():
		if area.is_in_group("hurtbox") and area.has_method("take_hit"):
			area.take_hit(GameState.attack(), facing)


func _start_dodge(move: Vector2) -> void:
	_dodge_dir = move if move.length_squared() > 0.01 else facing
	_dodge_timer = DODGE_DURATION + GameState.dodge_duration_bonus()
	_dodge_cd = DODGE_COOLDOWN
	EventBus.player_dodged.emit(self)
	AudioManager.play_sfx("dodge")


## Called by enemy hitboxes / hazards.
func take_hit(amount: float, _dir: Vector2) -> void:
	if invulnerable:
		return
	var dmg := maxf(1.0, amount - GameState.defense() * 0.5)
	GameState.hp = clampf(GameState.hp - dmg, 0.0, GameState.max_hp())
	EventBus.player_damaged.emit(dmg)
	if GameState.hp <= 0.0:
		EventBus.player_died.emit()
