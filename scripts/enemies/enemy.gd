class_name Enemy
extends CharacterBody2D
## Enemy — data-driven from data/enemies.json archetypes (EnemyDB).
## FSM: idle / patrol / chase / attack / flee. Telegraphed attacks (gold
## pulse wind-up). melee = contact lunge; ranged = pooled projectile.
## On death: XP + loot drops (gold/items), then recycled into the spawner's
## ObjectPool (no queue_free) for respawn reuse.

enum State { IDLE, PATROL, CHASE, ATTACK, FLEE, WITHDRAW, DEAD }

signal recycled(enemy: Enemy)

const DEFAULT_TELEGRAPH := 0.45
const FLEE_TIME := 1.6
const FLEE_THRESHOLD := 0.25
## Once the player is out of reach (or somewhere it may not follow), an enemy
## walks home instead of standing where it stopped.
const WITHDRAW_SPEED := 0.75
## A wanderer settles down: after this many patrol cycles it rests instead of
## picking another point, because a world where every creature paces forever
## reads as a screensaver, not a place (H5.1).
const PATROLS_BEFORE_REST := 3
const REST_MIN := 18.0
const REST_MAX := 32.0
## Off-screen enemies do not need to animate a patrol (H5.2).
const PATROL_AWAKE_RANGE := 900.0

# Composed LPC sheet layout (tools/lpc_compose.py): 13 cols x 20 rows of 64 px
# frames. Rows come in blocks of 4 directions, ordered n, w, s, e.
#   anim block 0 idle · 1 walk · 2 slash (attack) · 3 spellcast · 4 hurt
const SHEET_COLS := 13
const SHEET_ROWS := 20
const DIR_ROW := {"n": 0, "w": 1, "s": 2, "e": 3}
const ANIM_FRAMES := {"idle": 2, "walk": 9, "slash": 6, "spellcast": 7, "hurt": 6}
const ANIM_FPS := {"idle": 4.0, "walk": 12.0, "slash": 14.0, "spellcast": 12.0, "hurt": 10.0}
const ANIM_BLOCK := {"idle": 0, "walk": 1, "slash": 2, "spellcast": 3, "hurt": 4}
## Generated pose art (H5.5 idle frames, H7.2 attack frames) pasted into the
## composed sheet by tools/make_idle_frames.py. Which sheets have it, and how
## many frames, lives in PoseArt's manifest — a sheet without the art falls back
## to the frames the LPC layers ship, so this is additive for the whole roster.
const REST_IDLE_SLOWDOWN := 0.62         # a resting monster breathes slower
const REST_GLANCE_MIN := 2.5             # and looks around every few seconds
const REST_GLANCE_MAX := 6.0
const GLANCE_DIRS := ["n", "w", "s", "e"]
static var _idle_sheets: Dictionary = {}


static func patched_idle_sheets() -> Dictionary:
	## Sheet stem -> {anim: frame count} (see PoseArt).
	return PoseArt.all()

var telegraph_time := DEFAULT_TELEGRAPH
## Frames this sheet actually has per animation: the LPC count, or the generated
## count once tools/make_idle_frames.py has patched art in (see PoseArt).
var idle_frames := 2
var attack_frames := 6
var cast_frames := 7
var _sheet_path := ""
var _glance_timer := 0.0
## Movement/attack style, read from the archetype ("melee", "skirmish",
## "charger", "caster"). Before this every non-ranged enemy in the game fought
## identically: walk straight at the player, swing on cooldown. Fifteen of the
## twenty archetypes shared one brain.
var pattern := "melee"
var _strafe := 1.0          # skirmish: which way it circles
var _strafe_timer := 0.0
var _dash_time := 0.0       # charger: seconds of committed dash left
var _dash_dir := Vector2.RIGHT
var _recovery := 0.0        # charger: winded after a dash — hits hurt more
const CHARGE_STANDOFF := 260.0
const CHARGE_DASH_SPEED := 2.9
const CHARGE_RECOVERY := 0.9
const DASH_DAMAGE_MULT := 1.35
const STAGGER_DAMAGE_MULT := 1.3
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
var floor_index := 1
var _base_power_scale := 1.0
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
var _patrols_done := 0
## Seconds the floating health bar stays up after the last hit. Combat feedback
## used to be "the sprite flashed": with two enemies on screen nobody could tell
## which one was nearly dead or whether their swing had connected at all.
var _bar_time := 0.0
# Burn (engine-key talent `finisher_ignites`): damage per second and the
# time left on it, ticked in BURN_TICK steps so a burn is not a per-frame
# redraw on every enemy in the loaded chunks.
const BURN_TICK := 0.25
var _burn_dps := 0.0
var _burn_time := 0.0
var _burn_tick := 0.0
## Set while an attack is being telegraphed, for the ground reticle.
var _telegraphing := false
var _separation := Vector2.ZERO
## Set while the player is somewhere an enemy may not press an attack: inside a
## settlement's safe bubble, or mid-conversation. See _player_protected().
var player_protected := false

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


func _sync_boss_group() -> void:
	## The HUD's boss bar looks the fight up by group, so membership has to follow
	## `behavior` even when a pooled enemy is re-used for a different archetype.
	if behavior == "boss":
		if not is_in_group("boss"):
			add_to_group("boss")
	elif is_in_group("boss"):
		remove_from_group("boss")


func apply_burn(dps: float, duration: float) -> void:
	## Fire that keeps working after the hit that started it (engine-key talent
	## `finisher_ignites`). Re-applying refreshes the timer and keeps the stronger
	## rate; it never stacks, so a fast chain cannot multiply itself.
	if state == State.DEAD:
		return
	_burn_dps = maxf(_burn_dps, dps)
	_burn_time = maxf(_burn_time, duration)


func is_burning() -> bool:
	return _burn_time > 0.0


func burn_dps() -> float:
	return _burn_dps if _burn_time > 0.0 else 0.0


func _tick_burn(delta: float) -> void:
	_burn_time = maxf(_burn_time - delta, 0.0)
	_burn_tick += delta
	if _burn_time <= 0.0:
		_burn_dps = 0.0
		_burn_tick = 0.0
		return
	if _burn_tick < BURN_TICK:
		return
	# Damage lands in ticks, not per frame: the hp bar redraws three or four times
	# over the whole burn instead of sixty.
	var dmg := _burn_dps * _burn_tick
	_burn_tick = 0.0
	if dmg <= 0.0:
		return
	hp -= dmg
	_bar_time = 3.0
	queue_redraw()
	EventBus.enemy_hurt.emit(self, dmg, Vector2.ZERO)
	if hp <= 0.0:
		_die()


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_state_time += delta
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	_recovery = maxf(_recovery - delta, 0.0)
	var bar_was := _bar_time
	_bar_time = maxf(_bar_time - delta, 0.0)
	# Redraw while the bar is fading, and only then: this runs for every enemy in
	# the loaded chunks, so it must not be a per-frame cost on a quiet map.
	if bar_was > 0.0 or _bar_time > 0.0 or state == State.ATTACK or _burn_time > 0.0:
		queue_redraw()
	if _burn_time > 0.0:
		_tick_burn(delta)
	if pattern == "charger" and _dash_time > 0.0:
		_charge_tick(delta)
		return
	_player = _find_player()
	player_protected = _player_protected()

	# While the player is protected, or while this enemy is standing on safe
	# ground, every aggressive state drops: no chase, no telegraph, no hit.
	if state == State.CHASE or state == State.ATTACK:
		if player_protected or Settlement.safe_zone_at(global_position):
			_change_state(State.WITHDRAW)
	if state == State.ATTACK and not _may_press_attack():
		_change_state(State.WITHDRAW)

	var to_player := (_player.global_position - global_position) if _player else Vector2.ZERO
	var dist := to_player.length()

	match state:
		State.IDLE:
			velocity = velocity.move_toward(Vector2.ZERO, 400.0 * delta)
			if _player and dist < chase_radius and not player_protected:
				_change_state(State.CHASE)
			elif _patrols_done >= PATROLS_BEFORE_REST:
				# A real rest, not the old fixed 1.5 s pause between loops. The
				# extra idle frames only read as "alive" if the monster also
				# turns to look at something now and then (H5.5).
				_rest_glance(delta)
				if _state_time > 1.5 + REST_MIN + randf() * (REST_MAX - REST_MIN):
					_patrols_done = 0
					_state_time = 0.0
			elif _state_time > 1.5 and _awake():
				_pick_patrol_point()
				_change_state(State.PATROL)

		State.PATROL:
			var to_target := _patrol_target - global_position
			if to_target.length() < 12.0 or _state_time > 5.0:
				_patrols_done += 1
				_change_state(State.IDLE)
			else:
				velocity = velocity.move_toward(to_target.normalized() * move_speed * 0.6, 600.0 * delta)
			if _player and dist < chase_radius and not player_protected:
				_change_state(State.CHASE)
			velocity += _separation * 40.0

		State.WITHDRAW:
			# Walking home: no aggro, no attacks. This is what keeps towns, and
			# conversations, monster-free. If it is standing inside a safe bubble
			# (dragged in by a chase), "home" is the nearest point *outside* the
			# bubble — otherwise it would walk home to the middle of town and stay.
			var away := _retreat_point() - global_position
			if _state_time > 8.0 or away.length() < 16.0:
				_change_state(State.IDLE)
			else:
				velocity = velocity.move_toward(
					away.normalized() * move_speed * WITHDRAW_SPEED, 500.0 * delta)

		State.CHASE:
			if _player == null or player_protected:
				_change_state(State.WITHDRAW)
			elif dist < attack_radius and _attack_cd <= 0.0:
				_change_state(State.ATTACK)
			elif dist > chase_radius * 1.6:
				_change_state(State.IDLE)
			elif pattern == "charger" and _recovery > 0.0:
				# winded: it cannot close, and it knows it
				velocity = velocity.move_toward(-to_player.normalized() * move_speed * 0.4, 400.0 * delta)
			else:
				velocity = velocity.move_toward(
					_desired_velocity(to_player, dist, delta), 700.0 * delta)

		State.ATTACK:
			_telegraphing = true
			if not _may_press_attack():
				_change_state(State.WITHDRAW)
				sprite.modulate = _tinted()
			velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
			var pulse := 0.5 + 0.5 * sin(_state_time * 24.0)
			sprite.modulate = _tinted().lerp(Color(1.0, 0.85, 0.2), pulse)
			if _state_time >= telegraph_time:
				sprite.modulate = _tinted()
				_attack_cd = attack_cooldown
				if pattern == "charger":
					_begin_charge(to_player)
				else:
					_finish_attack(to_player, dist)
				_change_state(State.CHASE)

		State.FLEE:
			if _player:
				velocity = velocity.move_toward(-to_player.normalized() * move_speed * 1.2, 700.0 * delta)
			if _state_time > FLEE_TIME:
				_change_state(State.CHASE if _player else State.IDLE)

	if state != State.ATTACK and _telegraphing:
		_telegraphing = false
		queue_redraw()
	_separation = _separation_vector()
	if state != State.WITHDRAW:
		velocity += _separation * 60.0
	move_and_slide()
	_update_anim(delta)


func _draw() -> void:
	## Ground-level fight feedback, drawn in the enemy's own local space.
	##
	## H3.3: a telegraphed attack casts a ring on the floor at exactly
	## `attack_radius`, so "it is about to hit me" is readable from the ground
	## instead of from a colour pulse on a 64 px sprite. Melee sweeps a filled
	## disc; ranged draws its firing line.
	if _telegraphing:
		var t := clampf(_state_time / maxf(telegraph_time, 0.01), 0.0, 1.0)
		var col := Color(1.0, 0.55, 0.15, 0.16 + 0.34 * t)
		if behavior == "ranged":
			var aim := Vector2.RIGHT
			if _player != null:
				aim = (_player.global_position - global_position).normalized()
			draw_line(Vector2.ZERO, aim * attack_radius, col, 6.0)
			draw_circle(Vector2.ZERO, attack_radius * 0.5, Color(1.0, 0.55, 0.15, 0.06))
		else:
			draw_circle(Vector2.ZERO, attack_radius, col)
			draw_arc(Vector2.ZERO, attack_radius, 0.0, TAU, 40,
				Color(1.0, 0.8, 0.35, 0.35 + 0.5 * t), 3.0)

	## H3.1: floating health bar, only while it matters.
	if _bar_time <= 0.0 or hp <= 0.0 or state == State.DEAD:
		return
	var w := 44.0
	var y := -40.0 * base_scale.y
	var pct := clampf(hp / maxf(max_hp, 0.01), 0.0, 1.0)
	var fade := clampf(_bar_time / 1.5, 0.0, 1.0)
	draw_rect(Rect2(Vector2(-w * 0.5 - 1, y - 1), Vector2(w + 2, 7)), Color(0, 0, 0, 0.65 * fade))
	draw_rect(Rect2(Vector2(-w * 0.5, y), Vector2(w, 5)), Color(0.25, 0.06, 0.07, 0.9 * fade))
	draw_rect(Rect2(Vector2(-w * 0.5, y), Vector2(w * pct, 5)),
		Color(0.85, 0.22, 0.22, 0.95 * fade).lerp(Color(1.0, 0.85, 0.30, 0.95 * fade), 1.0 - pct))


func _retreat_point() -> Vector2:
	## Where "home" is right now: `_origin` is already legal ground, but if we are
	## standing deep inside a bubble then the nearest way out beats walking to a
	## far home through the middle of town.
	if not Settlement.safe_zone_at(global_position):
		return _origin
	var zone := Settlement.safe_zone_containing(global_position)
	if zone.is_empty():
		return _origin
	var centre: Vector2 = zone["position"]
	var outward := (global_position - centre)
	if outward.length() < 0.001:
		outward = Vector2.RIGHT
	return centre + outward.normalized() * (float(zone["radius"]) + 48.0)


func _separation_vector() -> Vector2:
	## Enemies from one spawner walk independent patrols inside a 360 px spread and
	## used to drift through each other, which looks like jitter rather than a
	## group. A cheap push-apart keeps them legible.
	var push := Vector2.ZERO
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self or not (other is Enemy):
			continue
		var v: Vector2 = global_position - (other as Node2D).global_position
		var d := v.length()
		if d > 0.001 and d < 46.0:
			push += v.normalized() * (46.0 - d) / 46.0
	return push


func _awake() -> bool:
	## Off-screen enemies skip the patrol loop entirely (no movement budget spent
	## animating what nobody can see). They still rest and still react on approach.
	if _player == null:
		return true
	return global_position.distance_to(_player.global_position) < PATROL_AWAKE_RANGE


func _idle_column(step: int) -> int:
	## Which sheet column the nth idle step shows: [base, weight shift, breath,
	## look-around] on a patched sheet, [base, breath] on one that is not.
	var cols := PoseArt.idle_columns(_sheet_path, 2)
	return int(cols[step % cols.size()])


func _resting() -> bool:
	## H5.1's long rest: standing still with three patrols behind it.
	return state == State.IDLE and _patrols_done >= PATROLS_BEFORE_REST


func _rest_glance(delta: float) -> void:
	## A resting monster turns its head/body to a new cardinal direction every
	## few seconds. Without it, four idle frames still play into a fixed facing
	## and the character reads as a statue with better breathing (H5.5).
	_glance_timer -= delta
	if _glance_timer > 0.0:
		return
	_glance_timer = REST_GLANCE_MIN + randf() * (REST_GLANCE_MAX - REST_GLANCE_MIN)
	_anim_dir = String(GLANCE_DIRS[randi() % GLANCE_DIRS.size()])


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

	var base: int = ANIM_FRAMES[_anim_name]
	var count: int = base
	if _anim_name == "idle":
		count = idle_frames
	elif _anim_name == "slash":
		count = attack_frames
	elif _anim_name == "spellcast":
		count = cast_frames
	var fps: float = float(ANIM_FPS[_anim_name])
	if _anim_name == "idle" and _resting():
		fps *= REST_IDLE_SLOWDOWN
	if count < base:
		# Generated attack art has fewer, bigger poses than the LPC block it
		# replaces; keep the animation's wall-clock length so the swing still
		# lands when the damage window does. (More frames than the block — the
		# idle loop — plays at the block's own rate, not slower.)
		fps *= float(base) / float(count)
	_anim_frame += delta * fps
	while _anim_frame >= float(count):
		_anim_frame -= float(count)
	var column := int(_anim_frame)
	if _anim_name == "idle":
		column = _idle_column(column)
	elif _anim_name == "slash" and attack_frames < base:
		column = int(PoseArt.slash_columns(_sheet_path, base)[column])
	elif _anim_name == "spellcast" and cast_frames < base:
		column = int(PoseArt.cast_columns(_sheet_path, base)[column])
	var row: int = int(ANIM_BLOCK[_anim_name]) * 4 + int(DIR_ROW[_anim_dir])
	sprite.frame = row * SHEET_COLS + column


func _apply_sheet(path: String) -> void:
	## Attach the archetype's composed LPC sheet, or clear back to the single
	## placeholder sprite when an archetype has no art.
	_sheet_path = path
	if path == "" or not ResourceLoader.exists(path):
		_sheet_ready = false
		idle_frames = 2
		attack_frames = int(ANIM_FRAMES["slash"])
		cast_frames = int(ANIM_FRAMES["spellcast"])
		sprite.hframes = 1
		sprite.vframes = 1
		sprite.frame = 0
		return
	var tex: Texture2D = load(path)
	if tex == null:
		_sheet_ready = false
		idle_frames = 2
		attack_frames = int(ANIM_FRAMES["slash"])
		cast_frames = int(ANIM_FRAMES["spellcast"])
		return
	sprite.texture = tex
	sprite.hframes = SHEET_COLS
	sprite.vframes = SHEET_ROWS
	sprite.offset = Vector2(0, -10)   # LPC frames sit above the body pivot
	_sheet_ready = true
	idle_frames = PoseArt.count(path, "idle", PoseArt.IDLE_BASE)
	attack_frames = PoseArt.count(path, "slash", int(ANIM_FRAMES["slash"]))
	cast_frames = PoseArt.count(path, "spellcast", int(ANIM_FRAMES["spellcast"]))
	_glance_timer = 1.0
	_anim_name = "idle"
	_anim_dir = "s"
	_anim_frame = 0.0
	sprite.frame = int(DIR_ROW["s"]) * SHEET_COLS


func setup_archetype(id: String, power_scale: float = 1.0, floor: int = 1) -> void:
	## (Re)configure from EnemyDB — used on spawn AND on pool reuse.
	## `floor` applies the archetype's floor_multiplier (Phase E §6), so dungeon
	## spawners only have to set a floor index and get hp/damage/xp scaling.
	archetype = id
	floor_index = maxi(1, floor)
	_base_power_scale = power_scale
	power_scale *= EnemyDB.floor_scale(id, floor_index)
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
	pattern = String(cfg.get("pattern", "melee"))
	telegraph_time = float(cfg.get("telegraph_time", DEFAULT_TELEGRAPH))
	if pattern == "charger":
		telegraph_time = maxf(telegraph_time, 0.55)   # a charge has to be readable
	_strafe = 1.0 if randf() < 0.5 else -1.0
	_strafe_timer = 0.0
	_dash_time = 0.0
	_recovery = 0.0
	projectile_damage = float(cfg.get("projectile_damage", 0.0)) * power_scale
	projectile_speed = float(cfg.get("projectile_speed", 240.0))
	var c: Array = cfg.get("body_color", [0.78, 0.28, 0.28])
	body_color = Color(float(c[0]), float(c[1]), float(c[2]))
	_apply_sheet(String(cfg.get("sheet", "")))
	base_scale = Vector2.ONE * float(cfg.get("sprite_scale", 1.0))

	hp = max_hp
	state = State.IDLE
	_state_time = 0.0
	_patrols_done = 0
	_separation = Vector2.ZERO
	player_protected = false
	_bar_time = 0.0
	_telegraphing = false
	_sync_boss_group()
	queue_redraw()
	_attack_cd = 0.0
	velocity = Vector2.ZERO
	# A monster's home is never inside a settlement: the spawner already refuses to
	# place one there, but a pooled enemy re-homed by a chase must not treat the
	# middle of town as its patrol centre.
	_origin = _legal_origin(global_position)
	sprite.modulate = _tinted()
	modulate.a = 1.0
	scale = base_scale
	show()
	set_physics_process(true)


func setup_floor(floor: int) -> void:
	## Re-apply this archetype's scaling for a deeper dungeon floor, keeping the
	## power_scale the spawner originally asked for.
	setup_archetype(archetype, _base_power_scale, floor)
	for child in get_children():
		if child is CollisionShape2D:
			child.set_deferred("disabled", false)


## Attack resolution hook — Boss overrides this for phase patterns.
func _finish_attack(to_player: Vector2, dist: float) -> void:
	if _player == null:
		return
	if not _may_press_attack():
		return  # safe ground and open conversations are not combat zones
	if behavior == "ranged":
		PoolManager.spawn_projectile(
			global_position, to_player.normalized(),
			projectile_damage, projectile_speed, body_color.lightened(0.2)
		)
		AudioManager.play_sfx("enemy_cast")
	elif dist < attack_radius + 18.0:
		_player.take_hit(contact_damage, to_player.normalized())


func _player_protected() -> bool:
	## Safe ground and open conversations are the two places the player must be
	## able to stand still and read. The safe bubble only ever stopped spawners
	## from *appearing* inside it, so a wolf that was already chasing you walked
	## straight into town behind you; and dialogue left the player taking hits
	## while reading a line. Both are now hard stops for enemies.
	if _player == null:
		return false
	if EventBus.dialogue_open:
		return true
	return Settlement.safe_zone_at(_player.global_position)


func _may_press_attack() -> bool:
	## An enemy never swings at a protected player, and an enemy standing inside a
	## safe zone never swings at all.
	return not player_protected and not Settlement.safe_zone_at(global_position)


func _desired_velocity(to_player: Vector2, dist: float, delta: float) -> Vector2:
	## Each pattern answers "how do I get to you?" differently.
	match pattern:
		"skirmish":
			# Wolves and scouts circle instead of charging down the middle: a
			# tangent component plus a light pull inward. They slip past a straight
			# swing instead of walking into it.
			_strafe_timer -= maxf(delta, 0.001)
			if _strafe_timer <= 0.0:
				_strafe_timer = randf_range(1.0, 1.9)
				if randf() < 0.35:
					_strafe = -_strafe
			var inward := 1.0 if dist > attack_radius * 1.2 else 0.35
			var tangent := to_player.normalized().orthogonal() * _strafe
			return (tangent * 0.85 + to_player.normalized() * inward).normalized() * move_speed
		"charger":
			# A brute backs off to a standoff and then commits; standing inside its
			# standoff is a mistake, not a safe spot.
			if dist < CHARGE_STANDOFF * 0.6:
				return -to_player.normalized() * move_speed * 0.5
			if dist > CHARGE_STANDOFF:
				return to_player.normalized() * move_speed
			return Vector2.ZERO
		"caster":
			if dist < attack_radius * 0.5:
				return -to_player.normalized() * move_speed * 0.7
			if dist > attack_radius * 0.85:
				return to_player.normalized() * move_speed
			return to_player.normalized().orthogonal() * _strafe * move_speed * 0.5
		_:
			return to_player.normalized() * move_speed


func _begin_charge(to_player: Vector2) -> void:
	## The commit: locked direction, locked duration, no steering. Everything the
	## player needs to dodge is visible in the telegraph before this. (Bosses have
	## their own `_start_charge` — the name is taken.)
	_dash_dir = to_player.normalized()
	_dash_time = 0.42
	AudioManager.play_sfx("enemy_cast")


func _charge_tick(delta: float) -> void:
	if not _may_press_attack():
		# The dash breaks off the moment the player reaches safe ground or opens a
		# conversation — a brute that carries its momentum into town is exactly the
		# bug this guards against.
		_dash_time = 0.0
		_recovery = 0.0
		_change_state(State.WITHDRAW)
		return
	_dash_time = maxf(_dash_time - delta, 0.0)
	velocity = _dash_dir * move_speed * CHARGE_DASH_SPEED
	move_and_slide()
	_update_anim(delta)
	if _player != null:
		var gap := _player.global_position - global_position
		if gap.length() < attack_radius + 12.0:
			_player.take_hit(contact_damage * DASH_DAMAGE_MULT, _dash_dir)
			_dash_time = 0.0
	if _dash_time <= 0.0:
		# Winded: stands there for a beat and takes more punishment.
		_recovery = CHARGE_RECOVERY
		_change_state(State.CHASE)


func _change_state(s: State) -> void:
	state = s
	_state_time = 0.0


func _pick_patrol_point() -> void:
	var p := _origin + Vector2(randf_range(-160.0, 160.0), randf_range(-160.0, 160.0))
	if Settlement.safe_zone_at(p):
		p = _origin   # never wander into town, even by a few pixels
	_patrol_target = p


func _legal_origin(from: Vector2) -> Vector2:
	## Push a spawn/home point out of any safe bubble it landed in.
	var zone := Settlement.safe_zone_containing(from)
	if zone.is_empty():
		return from
	var centre: Vector2 = zone["position"]
	var outward := from - centre
	if outward.length() < 0.001:
		outward = Vector2.RIGHT
	return centre + outward.normalized() * (float(zone["radius"]) + 48.0)


func _find_player() -> Player:
	# is_instance_valid, not just is_queued_for_deletion: a player torn down with
	# free() (or mid scene change) is neither null nor queued, and was returned as
	# a stale body to chase, throwing on the next global_position read.
	if is_instance_valid(_player):
		return _player
	_player = get_tree().get_first_node_in_group("player") as Player
	return _player


## Hit entry point — called by the player's attack area (group "hurtbox").
func take_hit(amount: float, dir: Vector2) -> void:
	if state == State.DEAD:
		return
	if _recovery > 0.0:
		amount *= STAGGER_DAMAGE_MULT   # punish the wind-up
	hp -= amount
	_bar_time = 3.0            # hit -> the bar appears and starts its fade
	queue_redraw()
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
	if is_in_group("boss"):
		remove_from_group("boss")
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
