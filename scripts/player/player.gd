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
const CRIT_MULT := 1.8

# Abilities (Phase 4): cooldown-based, MP-fueled.
const WHIRL_COOLDOWN := 4.0
const WHIRL_MP := 10.0
const WHIRL_RADIUS := 95.0
const WHIRL_MULT := 1.4
const BOLT_COOLDOWN := 2.2
const BOLT_MP := 12.0
const BOLT_SPEED := 430.0
const BOLT_MULT := 1.2

## Fed by the virtual joystick (touch). Zero → fall back to keyboard actions.
var external_input := Vector2.ZERO

var facing := Vector2.RIGHT
var invulnerable := false

var _dodge_timer := 0.0
var _dodge_cd := 0.0
var _dodge_dir := Vector2.RIGHT
var _attack_cd := 0.0
var _attack_active := 0.0
var _whirl_cd := 0.0
var _bolt_cd := 0.0

signal ability_cooldowns_changed(whirl: float, bolt: float)

@onready var attack_pivot: Node2D = $AttackPivot
@onready var attack_area: Area2D = $AttackPivot/AttackArea
@onready var attack_shape: CollisionShape2D = $AttackPivot/AttackArea/AttackShape

# --- LPC animation (Phase 3) -------------------------------------------------
# Composed sheets (tools/lpc_compose.py): 13 cols x 20 rows of 64 px frames.
const LPC_SHEET := "res://assets/lpc/player_%s_%s.png"
const LPC_ANIMS := ["idle", "walk", "slash", "spellcast", "hurt"]
const LPC_FRAMES := {"idle": 2, "walk": 9, "slash": 6, "spellcast": 7, "hurt": 6}
const LPC_FPS := {"idle": 4.0, "walk": 12.0, "slash": 14.0, "spellcast": 12.0, "hurt": 10.0}
const LPC_DIRS := ["n", "w", "s", "e"]

var sprite: AnimatedSprite2D
var _cast_anim := 0.0
var _hurt_anim := 0.0
var _dead := false
var _last_variant := ""
var _variant_timer := 0.0


func _ready() -> void:
	add_to_group("player")
	GameState.hp = GameState.max_hp()
	GameState.mp = GameState.max_mp()
	attack_shape.disabled = true
	sprite = AnimatedSprite2D.new()
	sprite.name = "LpcSprite"
	add_child(sprite)
	_rebuild_sprite_frames()
	EventBus.player_died.connect(_on_died)


func _physics_process(delta: float) -> void:
	_dodge_cd = maxf(_dodge_cd - delta, 0.0)
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	_whirl_cd = maxf(_whirl_cd - delta, 0.0)
	_bolt_cd = maxf(_bolt_cd - delta, 0.0)
	_cast_anim = maxf(_cast_anim - delta, 0.0)
	_hurt_anim = maxf(_hurt_anim - delta, 0.0)
	_variant_timer -= delta
	if _variant_timer <= 0.0:
		_variant_timer = 0.5
		if _variant_key() != _last_variant:
			_rebuild_sprite_frames()
	_update_anim()

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
			var top_speed := GameState.move_speed()
			velocity = velocity.move_toward(move * top_speed, ACCELERATION * delta)
		else:
			velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)
		if Input.is_action_just_pressed("attack") and _attack_cd <= 0.0:
			_start_attack()
		elif Input.is_action_just_pressed("dodge") and _dodge_cd <= 0.0:
			_start_dodge(move)
		if Input.is_action_just_pressed("ability_whirl") and _whirl_cd <= 0.0:
			cast_whirlwind()
		if Input.is_action_just_pressed("ability_bolt") and _bolt_cd <= 0.0:
			cast_firebolt()

	move_and_slide()


## Normalized remaining cooldowns for HUD display (1 = just cast, 0 = ready).
func cooldowns() -> Dictionary:
	return {
		"whirl": _whirl_cd / WHIRL_COOLDOWN,
		"bolt": _bolt_cd / BOLT_COOLDOWN,
	}


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
		if area.is_in_group("hurtbox"):
			var target: Node = area.get_parent()
			if target != null and target.has_method("take_hit"):
				var dmg := roll_damage(GameState.attack())
				target.take_hit(dmg, facing)
				_apply_lifesteal(dmg)


## Whirlwind — 360° melee spin hitting every hurtbox in WHIRL_RADIUS.
func cast_whirlwind() -> void:
	var cost := whirl_mp_cost()
	if GameState.mp < cost:
		return
	GameState.mp -= cost
	_whirl_cd = WHIRL_COOLDOWN
	_cast_anim = 0.32
	AudioManager.play_sfx("ability_whirl")
	# Spin flourish.
	var tw := create_tween()
	tw.tween_property(attack_pivot, "rotation", attack_pivot.rotation + TAU, 0.28)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is Node2D:
			var e := enemy as Node2D
			if global_position.distance_to(e.global_position) <= WHIRL_RADIUS:
				var dir := (e.global_position - global_position).normalized()
				if e.has_method("take_hit"):
					var wdmg := roll_damage(GameState.attack() * WHIRL_MULT * GameState.whirl_mult())
					e.take_hit(wdmg, dir)
					_apply_lifesteal(wdmg)


## Firebolt — ranged projectile that pierces toward the facing direction.
func cast_firebolt() -> void:
	var cost := bolt_mp_cost()
	if GameState.mp < cost:
		return
	GameState.mp -= cost
	_bolt_cd = BOLT_COOLDOWN
	_cast_anim = 0.35
	AudioManager.play_sfx("ability_bolt")
	PoolManager.spawn_projectile(
		global_position + facing * 22.0, facing,
		GameState.attack() * BOLT_MULT * GameState.bolt_mult(), BOLT_SPEED,
		Color(0.45, 0.75, 1.0), true
	)


func _start_dodge(move: Vector2) -> void:
	_dodge_dir = move if move.length_squared() > 0.01 else facing
	_dodge_timer = DODGE_DURATION + GameState.dodge_duration_bonus()
	_dodge_cd = DODGE_COOLDOWN
	EventBus.player_dodged.emit(self)
	AudioManager.play_sfx("dodge")
	_squash(Vector2(1.25, 0.72))


## Squash-and-stretch juice: snap the sprite to a scale then tween back.
func _squash(target: Vector2) -> void:
	if sprite == null:
		return
	sprite.scale = target
	var tw := create_tween()
	tw.tween_property(sprite, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Whirlwind / Firebolt MP costs after the Efficient Casting talent.
func whirl_mp_cost() -> float:
	return maxf(1.0, WHIRL_MP * GameState.mp_cost_mult())


func bolt_mp_cost() -> float:
	return maxf(1.0, BOLT_MP * GameState.mp_cost_mult())


func roll_damage(base: float) -> float:
	## Applies the crit chance from gear + talents (Phase F1). A crit lands 1.8x
	## and shows a bigger, brighter number so the loot that caused it reads.
	var dmg := base
	if randf() < GameState.crit_chance():
		dmg = base * CRIT_MULT
		if is_inside_tree():
			DamageNumber.spawn(get_parent(), global_position + Vector2(0, -34),
				"CRIT %d" % int(dmg), Color(1.0, 0.75, 0.25))
	return dmg


func _apply_lifesteal(dmg: float) -> void:
	## Bloodletter / Sanguine Edge: heal a fraction of the damage dealt.
	var frac := GameState.lifesteal()
	if frac <= 0.0:
		return
	GameState.hp = minf(GameState.hp + dmg * frac, GameState.max_hp())
	EventBus.player_healed.emit(dmg * frac)


## Called by enemy hitboxes / hazards.
func take_hit(amount: float, _dir: Vector2) -> void:
	if invulnerable:
		return
	var dmg := maxf(1.0, amount - GameState.defense() * 0.5) * GameState.damage_taken_mult()
	GameState.hp = clampf(GameState.hp - dmg, 0.0, GameState.max_hp())
	EventBus.player_damaged.emit(dmg)
	_hurt_anim = 0.3
	_squash(Vector2(0.8, 1.22))
	if GameState.hp <= 0.0:
		EventBus.player_died.emit()


# --- LPC animation (Phase 3) -------------------------------------------------

func _update_anim() -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	var anim := "idle"
	if _dead or _hurt_anim > 0.0:
		anim = "hurt"
	elif _attack_active > 0.0:
		anim = "slash"
	elif _cast_anim > 0.0:
		anim = "spellcast"
	elif velocity.length_squared() > 4.0:
		anim = "walk"
	var name := "%s_%s" % [anim, _dir_key()]
	if sprite.animation != name:
		sprite.play(name)


func _dir_key() -> String:
	if absf(facing.x) > absf(facing.y):
		return "e" if facing.x > 0.0 else "w"
	return "s" if facing.y > 0.0 else "n"


## Equipment -> composed sheet variant (rebuilds animation on change).
func _variant_key() -> String:
	var armor: String = GameState.equipment.get("armor", "")
	var weapon: String = GameState.equipment.get("weapon", "")
	var a := "leather" if armor == "leather_armor" else "none"
	var w := "sword" if weapon in ["short_sword", "iron_sword"] else "none"
	return "player_%s_%s" % [a, w]


func _rebuild_sprite_frames() -> void:
	_last_variant = _variant_key()
	var tex := load(LPC_SHEET % [_last_variant.split("_")[1], _last_variant.split("_")[2]])
	if tex == null:
		return
	var sf := SpriteFrames.new()
	for a_i in LPC_ANIMS.size():
		var anim: String = LPC_ANIMS[a_i]
		for d_i in LPC_DIRS.size():
			var name := "%s_%s" % [anim, LPC_DIRS[d_i]]
			sf.add_animation(name)
			sf.set_animation_speed(name, LPC_FPS[anim])
			sf.set_animation_loop(name, anim in ["idle", "walk"])
			for f in LPC_FRAMES[anim]:
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(f * 64.0, (a_i * 4 + d_i) * 64.0, 64.0, 64.0)
				sf.add_frame(name, at)
	sprite.sprite_frames = sf
	sprite.centered = true
	sprite.offset = Vector2(0, -10)  # LPC frames are taller than the body pivot


func _on_died() -> void:
	_dead = true
	if sprite != null:
		var tw := create_tween()
		tw.tween_property(sprite, "rotation", deg_to_rad(90.0), 0.35)
