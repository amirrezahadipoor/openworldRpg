class_name DataBoss
extends Enemy
## Phase F3 — a data-driven multi-phase boss.
##
## The Ember Warden keeps its own hand-written script (`scripts/enemies/boss.gd`)
## because its fight is frozen. This class exists so the OTHER five bosses are
## authored entirely in `data/enemies.json` under `phases`, without copying the
## Warden's logic or special-casing each one:
##
##   "phases": [
##     {"hp_above": 0.60, "speed_mult": 1.0,  "radial": 0,  "telegraph": 0.45, "charge": false},
##     {"hp_above": 0.25, "speed_mult": 1.25, "radial": 6,  "telegraph": 0.36, "charge": false},
##     {"hp_above": 0.0,  "speed_mult": 1.45, "radial": 8,  "telegraph": 0.28, "charge": true}
##   ]
##
## `radial` fires that many projectiles in a ring every `RADIAL_EVERY` attacks;
## `charge` unlocks the telegraphed dash. Transitions grant brief invulnerability
## plus a screen shake, so a phase change always reads.

signal phase_changed(phase: int)

const RADIAL_EVERY := 3
const CHARGE_DURATION := 0.5
const CHARGE_SPEED_MULT := 4.6
const CHARGE_COOLDOWN := 3.2

var phase := 1
var phases: Array = []
var base_move_speed := 0.0
var base_telegraph := 0.0

var _attack_index := 0
var _transform_invuln := 0.0
var _charge_timer := 0.0
var _charge_cd := 0.0
var _charge_dir := Vector2.ZERO


func setup_archetype(id: String, power_scale: float = 1.0, floor: int = 1) -> void:
	super.setup_archetype(id, power_scale, floor)
	phases = EnemyDB.get_archetype(id).get("phases", [])
	phase = 1
	_attack_index = 0
	_charge_timer = 0.0
	_charge_cd = 0.0
	_apply_phase()


func phase_data() -> Dictionary:
	## Phases are authored strongest-last, so walk to the first entry whose
	## threshold the boss is still above.
	for i in phases.size():
		var p: Dictionary = phases[i]
		if hp > max_hp * float(p.get("hp_above", 0.0)):
			return p
	return phases[-1] if not phases.is_empty() else {}


func _apply_phase() -> void:
	var p := phase_data()
	if p.is_empty():
		return
	if base_move_speed <= 0.0:
		base_move_speed = move_speed
	if base_telegraph <= 0.0:
		base_telegraph = telegraph_time
	move_speed = base_move_speed * float(p.get("speed_mult", 1.0))
	telegraph_time = float(p.get("telegraph", base_telegraph))


func take_hit(amount: float, dir: Vector2) -> void:
	if _transform_invuln > 0.0:
		return
	super.take_hit(amount, dir)
	if state == State.DEAD:
		return
	var pct := hp / max_hp
	# GDScript has no for/else: default to the last phase, then break on
	# the highest threshold the boss is still above.
	var want := phases.size()
	for i in phases.size():
		if pct > float((phases[i] as Dictionary).get("hp_above", 0.0)):
			want = i + 1
			break
	if want > phase:
		phase = want
		_enter_phase(phase)


func _enter_phase(n: int) -> void:
	_transform_invuln = 0.6
	_apply_phase()
	sprite.modulate = Color(1, 1, 1)
	var tw := create_tween()
	tw.tween_property(sprite, "modulate", _tinted(), 0.6)
	phase_changed.emit(n)
	EventBus.boss_phase_changed.emit(n)
	var cam := get_tree().get_first_node_in_group("camera")
	if cam != null and cam.has_method("shake"):
		cam.call("shake", 0.5)


func _physics_process(delta: float) -> void:
	_transform_invuln = maxf(_transform_invuln - delta, 0.0)
	_charge_cd = maxf(_charge_cd - delta, 0.0)
	if _charge_timer > 0.0:
		_charge_timer = maxf(_charge_timer - delta, 0.0)
		global_position += _charge_dir * charge_speed() * delta
		return
	# A charge phase starts a dash instead of a normal swing, on a cooldown.
	var p := phase_data()
	if bool(p.get("charge", false)) and _charge_cd <= 0.0 and _player != null \
			and global_position.distance_to(_player.global_position) < 420.0:
		_start_charge()
		return
	super._physics_process(delta)
	if behavior != "ranged":
		# Melee bosses still throw a radial volley every few swings.
		var radial := int(phase_data().get("radial", 0))
		if radial > 0 and _state_time <= 0.02:
			_attack_index += 1
			if _attack_index % RADIAL_EVERY == 0:
				_fire_radial(radial)


func charge_speed() -> float:
	return move_speed * CHARGE_SPEED_MULT


func _start_charge() -> void:
	_charge_timer = CHARGE_DURATION
	_charge_cd = CHARGE_COOLDOWN
	if _player != null:
		_charge_dir = (_player.global_position - global_position).normalized()
	velocity = Vector2.ZERO


func _fire_radial(count: int) -> void:
	if _player == null:
		return
	var offset := (_player.global_position - global_position).angle()
	for i in count:
		var a := offset + TAU * float(i) / float(count)
		PoolManager.spawn_projectile(
			global_position, Vector2(cos(a), sin(a)),
			projectile_damage, projectile_speed, body_color.lightened(0.25)
		)
	AudioManager.play_sfx("ability_whirl")
