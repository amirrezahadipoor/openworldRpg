class_name Enemy
extends CharacterBody2D
## Base enemy: full FSM (idle / patrol / chase / attack / flee), telegraphed
## attacks, hurtbox in group "hurtbox" (hit by the player's attack area),
## XP reward + EventBus notifications on hurt/death.

enum State { IDLE, PATROL, CHASE, ATTACK, FLEE, DEAD }

@export var max_hp := 30.0
@export var move_speed := 95.0
@export var contact_damage := 8.0
@export var chase_radius := 300.0
@export var attack_radius := 56.0
@export var xp_reward := 18
@export var body_color := Color(0.78, 0.28, 0.28)

const TELEGRAPH_TIME := 0.45
const FLEE_TIME := 1.6
const FLEE_THRESHOLD := 0.25

var hp: float
var state: State = State.IDLE

var _player: Player
var _state_time := 0.0
var _patrol_target := Vector2.ZERO
var _origin := Vector2.ZERO

@onready var sprite: Sprite2D = $Sprite


func _ready() -> void:
	hp = max_hp
	_origin = global_position
	sprite.modulate = body_color
	add_to_group("enemies")


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_state_time += delta
	_player = _find_player()

	var to_player := (_player.global_position - global_position) if _player else Vector2.ZERO
	var dist := to_player.length()

	match state:
		State.IDLE:
			velocity = velocity.move_toward(Vector2.ZERO, 400.0 * delta)
			if _player and dist < chase_radius:
				_change_state(State.CHASE)
			elif _state_time > 1.5:
				_pick_patrol_point()
				_change_state(State.PATROL)

		State.PATROL:
			var to_target := _patrol_target - global_position
			if to_target.length() < 12.0 or _state_time > 5.0:
				_change_state(State.IDLE)
			else:
				velocity = velocity.move_toward(to_target.normalized() * move_speed * 0.6, 600.0 * delta)
			if _player and dist < chase_radius:
				_change_state(State.CHASE)

		State.CHASE:
			if _player == null:
				_change_state(State.IDLE)
			elif dist < attack_radius:
				_change_state(State.ATTACK)
			elif dist > chase_radius * 1.6:
				_change_state(State.IDLE)
			else:
				velocity = velocity.move_toward(to_player.normalized() * move_speed, 700.0 * delta)

		State.ATTACK:
			velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
			# Telegraph: pulse red while winding up so the player can dodge.
			var pulse := 0.5 + 0.5 * sin(_state_time * 24.0)
			sprite.modulate = body_color.lerp(Color(1.0, 0.85, 0.2), pulse)
			if _state_time >= TELEGRAPH_TIME:
				sprite.modulate = body_color
				if _player and dist < attack_radius + 18.0:
					_player.take_hit(contact_damage, to_player.normalized())
				_change_state(State.IDLE)

		State.FLEE:
			if _player:
				velocity = velocity.move_toward(-to_player.normalized() * move_speed * 1.2, 700.0 * delta)
			if _state_time > FLEE_TIME:
				_change_state(State.CHASE if _player else State.IDLE)

	move_and_slide()


func _change_state(s: State) -> void:
	state = s
	_state_time = 0.0


func _pick_patrol_point() -> void:
	_patrol_target = _origin + Vector2(randf_range(-160.0, 160.0), randf_range(-160.0, 160.0))


func _find_player() -> Player:
	if _player != null and not _player.is_queued_for_deletion():
		return _player
	return get_tree().get_first_node_in_group("player") as Player


## Hit entry point — called by the player's attack area (group "hurtbox").
func take_hit(amount: float, dir: Vector2) -> void:
	if state == State.DEAD:
		return
	hp -= amount
	velocity += dir * 160.0  # knockback
	sprite.modulate = Color(1.5, 1.5, 1.5)
	var tw := create_tween()
	tw.tween_property(sprite, "modulate", body_color, 0.18)
	EventBus.enemy_hurt.emit(self, amount, dir)
	if hp <= 0.0:
		_die()
	elif hp < max_hp * FLEE_THRESHOLD and state != State.FLEE:
		_change_state(State.FLEE)


func _die() -> void:
	_change_state(State.DEAD)
	EventBus.enemy_died.emit(self)
	GameState.add_xp(xp_reward)
	set_physics_process(false)
	for child in get_children():
		if child is CollisionShape2D:
			child.set_deferred("disabled", true)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(0.1, 0.1), 0.3)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.3)
	tw.tween_callback(queue_free)
