class_name Boss
extends Enemy
## The Ember Warden — multi-phase boss (Roadmap Phase 5).
##   Phase 1 (>60% HP): melee slams + every 3rd attack is a triple shot.
##   Phase 2 (60–25%):  faster, 8-way radial bursts, shorter telegraph.
##   Phase 3 (<25%):    enraged — faster still, 10-way radials and
##                      telegraphed charge dashes.
## Phase transitions grant brief invulnerability + a visible flash + shake.

signal phase_changed(phase: int)

const PHASE2_AT := 0.60
const PHASE3_AT := 0.25
const CHARGE_DURATION := 0.55
const CHARGE_SPEED_MULT := 4.6

var phase := 1

var _attack_index := 0
var _charge_timer := 0.0
var _charge_dir := Vector2.ZERO
var _transform_invuln := 0.0


func _physics_process(delta: float) -> void:
	_transform_invuln = maxf(_transform_invuln - delta, 0.0)
	if _charge_timer > 0.0:
		_process_charge(delta)
		return
	super._physics_process(delta)


func take_hit(amount: float, dir: Vector2) -> void:
	if _transform_invuln > 0.0:
		return  # immune mid-transformation
	super.take_hit(amount, dir)
	if state == State.DEAD:
		return
	var pct := hp / max_hp
	if phase == 1 and pct <= PHASE2_AT:
		_enter_phase(2)
	elif phase == 2 and pct <= PHASE3_AT:
		_enter_phase(3)


func setup_archetype(id: String, power_scale: float = 1.0, floor: int = 1) -> void:
	super.setup_archetype(id, power_scale, floor)
	base_scale = Vector2(2.2, 2.2)   # after super: it assigns base_scale itself
	scale = base_scale
	phase = 1
	_attack_index = 0
	_charge_timer = 0.0
	telegraph_time = DEFAULT_TELEGRAPH


func _phase_tint(c: Color) -> Color:
	## Sprite2D.modulate multiplies; soften so the boss stays legible.
	return c.lerp(Color(1, 1, 1), 0.45)


func _enter_phase(p: int) -> void:
	phase = p
	_transform_invuln = 1.2
	_attack_cd = 1.6
	_charge_timer = 0.0
	_change_state(State.IDLE)
	velocity = Vector2.ZERO

	match p:
		2:
			move_speed *= 1.25
			attack_cooldown = maxf(attack_cooldown * 0.8, 0.6)
			telegraph_time = 0.35
			body_color = Color(0.95, 0.55, 0.12)
		3:
			move_speed *= 1.2
			attack_cooldown = maxf(attack_cooldown * 0.75, 0.5)
			telegraph_time = 0.28
			body_color = Color(0.85, 0.15, 0.12)

	# Transformation flash + shockwave ring feel.
	sprite.modulate = Color(2.0, 2.0, 2.0)
	var tw := create_tween()
	tw.tween_property(sprite, "modulate", _phase_tint(body_color), 0.6)
	tw.parallel().tween_property(self, "scale", base_scale * 1.25, 0.15)
	tw.tween_property(self, "scale", base_scale, 0.3)

	phase_changed.emit(phase)
	EventBus.boss_phase_changed.emit(phase)
	AudioManager.play_sfx("boss_roar")


func _finish_attack(to_player: Vector2, dist: float) -> void:
	if _player == null:
		return
	_attack_index += 1
	var dir := to_player.normalized()
	match phase:
		1:
			if _attack_index % 3 == 0:
				_spread_shot(dir, 3, 0.22)
			elif dist < attack_radius + 26.0:
				_player.take_hit(contact_damage, dir)
		2:
			if _attack_index % 2 == 0:
				_radial_burst(8)
			elif dist < attack_radius + 26.0:
				_player.take_hit(contact_damage, dir)
			else:
				_spread_shot(dir, 3, 0.18)
		3:
			if _attack_index % 2 == 0:
				_radial_burst(10)
			else:
				_start_charge(dir)


func _spread_shot(dir: Vector2, count: int, spread: float) -> void:
	var base_angle := dir.angle()
	for i in count:
		var a := base_angle + (float(i) - float(count - 1) * 0.5) * spread
		PoolManager.spawn_projectile(
			global_position, Vector2.from_angle(a),
			projectile_damage, projectile_speed, body_color.lightened(0.25)
		)
	AudioManager.play_sfx("enemy_cast")


func _radial_burst(count: int) -> void:
	for i in count:
		var a := TAU * float(i) / float(count) + float(_attack_index) * 0.2
		PoolManager.spawn_projectile(
			global_position, Vector2.from_angle(a),
			projectile_damage, projectile_speed * 0.85, body_color.lightened(0.15)
		)
	AudioManager.play_sfx("enemy_cast")


func _start_charge(dir: Vector2) -> void:
	_charge_dir = dir
	_charge_timer = CHARGE_DURATION
	sprite.modulate = _phase_tint(Color(1.0, 0.3, 0.2))


func _process_charge(delta: float) -> void:
	_charge_timer -= delta
	velocity = _charge_dir * move_speed * CHARGE_SPEED_MULT
	if _player and global_position.distance_to(_player.global_position) < 46.0:
		_player.take_hit(contact_damage * 1.5, _charge_dir)
		_charge_timer = 0.0
	move_and_slide()
	if _charge_timer <= 0.0:
		sprite.modulate = _phase_tint(body_color)
		_change_state(State.IDLE)
