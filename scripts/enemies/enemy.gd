class_name Enemy
extends CharacterBody2D
## Enemy — data-driven from data/enemies.json archetypes (EnemyDB).
## FSM: idle / patrol / chase / attack / flee. Telegraphed attacks (gold
## pulse wind-up). melee = contact lunge; ranged = pooled projectile.
## On death: XP + loot drops (gold/items), then recycled into the spawner's
## ObjectPool (no queue_free) for respawn reuse.

enum State { IDLE, PATROL, CHASE, ATTACK, FLEE, DEAD }

signal recycled(enemy: Enemy)

const DEFAULT_TELEGRAPH := 0.45
const FLEE_TIME := 1.6
const FLEE_THRESHOLD := 0.25

# Composed LPC sheet layout (tools/lpc_compose.py): 13 cols x 20 rows of 64 px
# frames. Rows come in blocks of 4 directions, ordered n, w, s, e.
#   anim block 0 idle · 1 walk · 2 slash (attack) · 3 spellcast · 4 hurt
const SHEET_COLS := 13
const SHEET_ROWS := 20
const DIR_ROW := {"n": 0, "w": 1, "s": 2, "e": 3}
const ANIM_FRAMES := {"idle": 2, "walk": 9, "slash": 6, "spellcast": 7, "hurt": 6}
const ANIM_FPS := {"idle": 4.0, "walk": 12.0, "slash": 14.0, "spellcast": 12.0, "hurt": 10.0}
const ANIM_BLOCK := {"idle": 0, "walk": 1, "slash": 2, "spellcast": 3, "hurt": 4}

var telegraph_time := DEFAULT_TELEGRAPH
var base_scale := Vector2.ONE

var archetype := "grunt"

var hp := 30.0
var max_hp := 30.0
var move_speed := 95.0
var contact_damage := 8.0
var chase_radius := 300.0
var attack_radius := 56.0
var attack_cooldown := 1.2
var xp_reward := 18
var behavior := "melee"
var projectile_damage := 0.0
var projectile_speed := 240.0
var body_color := Color(0.78, 0.28, 0.28)

var state: State = State.IDLE

var _player: Player
var _anim_name := "idle"
var _anim_dir := "s"
var _anim_frame := 0.0
var _sheet_ready := false
var _state_time := 0.0
var _attack_cd := 0.0
var _patrol_target := Vector2.ZERO
var _origin := Vector2.ZERO

@onready var sprite: Sprite2D = $Sprite


func _tinted() -> Color:
	## Archetype identity colour, softened toward white.
	##
	## Sprite2D.modulate MULTIPLIES, so tinting the (already dark) LPC sheets with
	## the raw body_color crushed them to near-black silhouettes on a real render.
	## Blending halfway to white keeps each archetype's hue readable while letting
	## the sprite art show through.
	return body_color.lerp(Color(1, 1, 1), 0.5)


func _ready() -> void:
	add_to_group("enemies")


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_state_time += delta
	_attack_cd = maxf(_attack_cd - delta, 0.0)
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
			elif dist < attack_radius and _attack_cd <= 0.0:
				_change_state(State.ATTACK)
			elif dist > chase_radius * 1.6:
				_change_state(State.IDLE)
			else:
				var desired := move_speed
				if behavior == "ranged" and dist < attack_radius * 0.5:
					desired = -move_speed * 0.7  # keep distance while casting
				velocity = velocity.move_toward(to_player.normalized() * desired, 700.0 * delta)

		State.ATTACK:
			velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
			var pulse := 0.5 + 0.5 * sin(_state_time * 24.0)
			sprite.modulate = _tinted().lerp(Color(1.0, 0.85, 0.2), pulse)
			if _state_time >= telegraph_time:
				sprite.modulate = _tinted()
				_attack_cd = attack_cooldown
				_finish_attack(to_player, dist)
				_change_state(State.CHASE)

		State.FLEE:
			if _player:
				velocity = velocity.move_toward(-to_player.normalized() * move_speed * 1.2, 700.0 * delta)
			if _state_time > FLEE_TIME:
				_change_state(State.CHASE if _player else State.IDLE)

	move_and_slide()
	_update_anim(delta)


func _update_anim(delta: float) -> void:
	## Drive the composed LPC sheet directly (Sprite2D hframes/vframes), so an
	## enemy needs no AnimatedSprite2D node and no per-enemy scene.
	if not _sheet_ready:
		return
	var next := "idle"
	if state == State.ATTACK:
		next = "slash"
	elif behavior == "ranged" and state == State.CHASE and _state_time < 0.35:
		next = "spellcast"
	elif velocity.length() > 6.0:
		next = "walk"
	if next != _anim_name:
		_anim_name = next
		_anim_frame = 0.0

	# face the direction of travel; ranged enemies face the player while casting
	var face := velocity
	if next == "slash" or next == "spellcast":
		if _player:
			face = _player.global_position - global_position
	if absf(face.x) > absf(face.y):
		if absf(face.x) > 1.0:
			_anim_dir = "e" if face.x > 0.0 else "w"
	elif absf(face.y) > 1.0:
		_anim_dir = "s" if face.y > 0.0 else "n"

	var count: int = ANIM_FRAMES[_anim_name]
	_anim_frame += delta * float(ANIM_FPS[_anim_name])
	while _anim_frame >= float(count):
		_anim_frame -= float(count)
	var row: int = int(ANIM_BLOCK[_anim_name]) * 4 + int(DIR_ROW[_anim_dir])
	sprite.frame = row * SHEET_COLS + int(_anim_frame)


func _apply_sheet(path: String) -> void:
	## Attach the archetype's composed LPC sheet, or clear back to the single
	## placeholder sprite when an archetype has no art.
	if path == "" or not ResourceLoader.exists(path):
		_sheet_ready = false
		sprite.hframes = 1
		sprite.vframes = 1
		sprite.frame = 0
		return
	var tex: Texture2D = load(path)
	if tex == null:
		_sheet_ready = false
		return
	sprite.texture = tex
	sprite.hframes = SHEET_COLS
	sprite.vframes = SHEET_ROWS
	sprite.offset = Vector2(0, -10)   # LPC frames sit above the body pivot
	_sheet_ready = true
	_anim_name = "idle"
	_anim_dir = "s"
	_anim_frame = 0.0
	sprite.frame = int(DIR_ROW["s"]) * SHEET_COLS


func setup_archetype(id: String, power_scale: float = 1.0) -> void:
	## (Re)configure from EnemyDB — used on spawn AND on pool reuse.
	archetype = id
	var cfg := EnemyDB.get_archetype(id)
	if cfg.is_empty():
		push_error("Enemy: unknown archetype '%s'" % id)
	max_hp = float(cfg.get("max_hp", 30.0)) * power_scale
	move_speed = float(cfg.get("move_speed", 95.0))
	contact_damage = float(cfg.get("contact_damage", 8.0)) * power_scale
	chase_radius = float(cfg.get("chase_radius", 300.0))
	attack_radius = float(cfg.get("attack_radius", 56.0))
	attack_cooldown = float(cfg.get("attack_cooldown", 1.2))
	xp_reward = int(int(cfg.get("xp_reward", 18)) * power_scale)
	behavior = String(cfg.get("behavior", "melee"))
	projectile_damage = float(cfg.get("projectile_damage", 0.0)) * power_scale
	projectile_speed = float(cfg.get("projectile_speed", 240.0))
	var c: Array = cfg.get("body_color", [0.78, 0.28, 0.28])
	body_color = Color(float(c[0]), float(c[1]), float(c[2]))
	_apply_sheet(String(cfg.get("sheet", "")))
	base_scale = Vector2.ONE * float(cfg.get("sprite_scale", 1.0))

	hp = max_hp
	state = State.IDLE
	_state_time = 0.0
	_attack_cd = 0.0
	velocity = Vector2.ZERO
	_origin = global_position
	sprite.modulate = _tinted()
	modulate.a = 1.0
	scale = base_scale
	show()
	set_physics_process(true)
	for child in get_children():
		if child is CollisionShape2D:
			child.set_deferred("disabled", false)


## Attack resolution hook — Boss overrides this for phase patterns.
func _finish_attack(to_player: Vector2, dist: float) -> void:
	if _player == null:
		return
	if behavior == "ranged":
		PoolManager.spawn_projectile(
			global_position, to_player.normalized(),
			projectile_damage, projectile_speed, body_color.lightened(0.2)
		)
		AudioManager.play_sfx("enemy_cast")
	elif dist < attack_radius + 18.0:
		_player.take_hit(contact_damage, to_player.normalized())


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
	velocity += dir * 160.0
	AudioManager.play_sfx("hit")
	sprite.modulate = Color(1.5, 1.5, 1.5)
	var tw := create_tween()
	tw.tween_property(sprite, "modulate", _tinted(), 0.18)
	EventBus.enemy_hurt.emit(self, amount, dir)
	if hp <= 0.0:
		_die()
	elif hp < max_hp * FLEE_THRESHOLD and state != State.FLEE and behavior != "boss":
		_change_state(State.FLEE)


func _die() -> void:
	_change_state(State.DEAD)
	set_physics_process(false)
	for child in get_children():
		if child is CollisionShape2D:
			child.set_deferred("disabled", true)
	_drop_loot()
	EventBus.enemy_died.emit(self)
	GameState.add_xp(xp_reward)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(0.1, 0.1), 0.3)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func() -> void: recycled.emit(self))


func _drop_loot() -> void:
	var drops := EnemyDB.roll_drops(archetype)
	var host := get_parent()
	if host == null:
		return
	var scene: PackedScene = load("res://scenes/world/pickup.tscn")
	var gold: int = drops["gold"]
	if gold > 0:
		var g: Pickup = scene.instantiate()
		host.add_child(g)
		g.global_position = global_position + Vector2(randf_range(-12.0, 12.0), randf_range(-12.0, 12.0))
		g.setup_gold(gold)
	for item_id in drops["items"]:
		var p: Pickup = scene.instantiate()
		host.add_child(p)
		p.global_position = global_position + Vector2(randf_range(-16.0, 16.0), randf_range(-16.0, 16.0))
		p.setup_item(String(item_id))


func on_pool_release() -> void:
	state = State.DEAD
	set_physics_process(false)
	hide()
