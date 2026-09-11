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
const STEP_INTERVAL := 0.34      # footstep pacing while walking

var _step_timer := 0.0
## The active window, in seconds. Widened from 0.12 to 0.16 (H3.4): the swing
## used to be resolved by a single `await process_frame` sample inside this
## window, so at 30 fps on a phone — where one frame is a third of the window —
## a hit could land in a frame the sampler never looked at.
const ATTACK_ACTIVE_TIME := 0.16
const COMBO_WINDOW := 0.62         # time after a swing to keep the chain alive
const COMBO_FINISHER_MULT := 1.5   # third hit lands harder and pushes back
const FINISHER_RECOVERY := 1.8     # ...but it costs you the next swing
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
var _combo := 0            # 0,1 = jabs · 2 = the finisher
var _combo_timer := 0.0
var _attack_mult := 1.0
## Instance ids already hit by the current swing, so sampling overlaps every
## physics frame cannot double-hit the same target.
var _hit_this_swing: Array = []
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
var _sheet_path := ""
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
	_step_timer -= delta
	_dodge_cd = maxf(_dodge_cd - delta, 0.0)
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	_whirl_cd = maxf(_whirl_cd - delta, 0.0)
	_bolt_cd = maxf(_bolt_cd - delta, 0.0)
	_cast_anim = maxf(_cast_anim - delta, 0.0)
	_combo_timer = maxf(_combo_timer - delta, 0.0)
	if _combo_timer <= 0.0 and _combo != 0:
		_combo = 0
		_attack_mult = 1.0
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
		# Sample the overlaps on every physics frame of the window instead of
		# once: frame-rate independent, and a fast target cannot slip between two
		# samples the way it could with one.
		_sample_attack_hits()
		if _attack_active <= 0.0:
			attack_shape.disabled = true
			_hit_this_swing.clear()
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
	_update_footsteps()


func _update_footsteps() -> void:
	## Footsteps for the walk cycle. The world used to be silent between fights —
	## music over nothing. A stride you can hear is most of what makes walking
	## feel like walking, so this is paced to the step, not to the frame.
	if velocity.length() < 12.0 or _dodge_timer > 0.0 or _hurt_anim > 0.0:
		return
	if _step_timer > 0.0:
		return
	_step_timer = STEP_INTERVAL
	AudioManager.play_sfx("footstep")


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


func _tween_swing_fallback() -> void:
	## Used only for a sheet without generated attack art: rotate the whole sprite
	## through the swing so the hero still visibly hits, instead of standing still
	## through eight frames of an 6 fps slideshow.
	if sprite == null or uses_generated_art("slash"):
		return
	var tw := create_tween()
	var dir := -1.0 if facing.x < 0.0 else 1.0
	tw.tween_property(sprite, "rotation", deg_to_rad(13.0) * dir, 0.07)
	tw.tween_property(sprite, "rotation", deg_to_rad(-16.0) * dir, 0.12)
	tw.tween_property(sprite, "rotation", 0.0, 0.13)


func _start_attack() -> void:
	## Three-hit chain. The first two swings are quick jabs; the third is a heavy
	## finisher that reaches further, hits for COMBO_FINISHER_MULT and shoves what
	## it hits — and leaves you open for longer, so mashing is not strictly better
	## than reading the fight. Without this every click was the same click.
	_combo = (_combo + 1) % 3
	_combo_timer = COMBO_WINDOW
	var finisher := _combo == 2
	_attack_mult = COMBO_FINISHER_MULT if finisher else 1.0
	var recovery := ATTACK_COOLDOWN * (FINISHER_RECOVERY if finisher else 1.0)
	_attack_cd = recovery * GameState.attack_cooldown_mult()
	_attack_active = ATTACK_ACTIVE_TIME * (1.5 if finisher else 1.0)
	_hit_this_swing.clear()
	attack_shape.disabled = false
	if attack_shape.shape is CircleShape2D:
		# the finisher sweeps a wider arc
		(attack_shape.shape as CircleShape2D).radius = 26.0 if finisher else 18.0
	EventBus.attack_swung.emit(self)
	AudioManager.play_sfx("attack_swing")
	_tween_swing_fallback()
	if finisher:
		_finisher_flash()
	_sample_attack_hits()   # first sample now; the rest come from _physics_process


func _sample_attack_hits() -> void:
	if attack_area == null or attack_shape.disabled:
		return
	for area in attack_area.get_overlapping_areas():
		if not area.is_in_group("hurtbox"):
			continue
		var target: Node = area.get_parent()
		if target == null or not target.has_method("take_hit"):
			continue
		var id := target.get_instance_id()
		if _hit_this_swing.has(id):
			continue
		_hit_this_swing.append(id)
		var dmg := roll_damage(GameState.attack() * _attack_mult)
		target.take_hit(dmg, facing)
		_apply_lifesteal(dmg)
		if _attack_mult > 1.0:
			_shove(target)
			AudioManager.play_sfx("hit")


## Kept for callers that awaited the old single-shot resolver (tests included):
## resolves one pass immediately, without waiting a frame.
func _resolve_attack_hits(finisher: bool = false) -> void:
	if finisher and _attack_mult <= 1.0:
		_attack_mult = 1.0
	_sample_attack_hits()


func _shove(target: Node) -> void:
	## The finisher pushes what it hits. Enemies knock themselves around in
	## take_hit via their own velocity, so this only needs to add to it.
	if target is CharacterBody2D:
		var body := target as CharacterBody2D
		body.velocity += facing * 260.0


func _protected_ground() -> bool:
	## No damage on safe ground, and none mid-conversation.
	if EventBus.dialogue_open:
		return true
	return Settlement.safe_zone_at(global_position)


func _finisher_flash() -> void:
	## A brighter, wider swing arc for the third hit so the chain reads on screen.
	var flash := Polygon2D.new()
	flash.polygon = PackedVector2Array([
		Vector2(0, -26), Vector2(46, -18), Vector2(58, 0),
		Vector2(46, 18), Vector2(0, 26),
	])
	flash.color = Color(1.0, 0.94, 0.72, 0.55)
	attack_pivot.add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "modulate:a", 0.0, 0.18)
	tw.tween_callback(flash.queue_free)


## Whirlwind — 360° melee spin hitting every hurtbox in WHIRL_RADIUS.
func cast_whirlwind() -> void:
	var cost := whirl_mp_cost()
	if GameState.mp < cost:
		AudioManager.play_sfx("denied")   # out of mana says so
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
		AudioManager.play_sfx("denied")
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
	if _protected_ground():
		# Last gate before any damage lands. Enemies already refuse to attack here
		# (Enemy._may_press_attack), but a projectile fired a moment before the
		# player crossed the line, or a boss that does not run the field FSM, would
		# still land — and being killed while reading a line of dialogue is the
		# single worst way to lose a run.
		return
	var dmg := maxf(1.0, amount - GameState.defense() * 0.5) * GameState.damage_taken_mult()
	GameState.hp = clampf(GameState.hp - dmg, 0.0, GameState.max_hp())
	EventBus.player_damaged.emit(dmg)
	_hurt_anim = 0.3
	_squash(Vector2(0.8, 1.22))
	if GameState.hp <= 0.0:
		if GameState.consume_revive():
			# Phoenix Draught: it burns instead of you, once.
			GameState.hp = GameState.max_hp() * 0.5
			invulnerable = true
			_dodge_timer = maxf(_dodge_timer, DODGE_DURATION)
			EventBus.player_healed.emit(GameState.hp)
			EventBus.item_used.emit("phoenix_elixir")
			AudioManager.play_sfx("level_up")
			return
		EventBus.player_died.emit()


# --- LPC animation (Phase 3) -------------------------------------------------

func uses_generated_art(anim: String) -> bool:
	## Does the hero's CURRENT sheet carry generated poses for this animation?
	## (The equipment decides the sheet, and not every sheet has art yet.)
	return PoseArt.has(_sheet_path, anim)


func _update_anim() -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	var anim := "idle"
	if _dead or _hurt_anim > 0.0:
		anim = "hurt"
	elif _attack_active > 0.0:
		# A swing that only advances a frame every 0.17 s (the LPC block's 6 fps)
		# reads as a slideshow. When the art is not there yet, the hero's visible
		# wind-up rides the arm-swing tween instead (see _start_attack).
		anim = "slash" if uses_generated_art("slash") else "idle"
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
##
## The armour ladder is read off the item the player is WEARING, so every piece
## of gear in the game is visible on the character: cloth (nothing heavy yet),
## leather, plate and legion as defence rises. The weapon shows on the sheet
## whenever anything is held in the weapon slot.
const ARMOR_LOOK_DEF := [8.0, 20.0, 34.0]   # def thresholds -> leather/plate/legion


func _variant_key() -> String:
	var armor: String = String(GameState.equipment.get("armor", ""))
	var weapon: String = String(GameState.equipment.get("weapon", ""))
	return "player_%s_%s" % [_armor_look(armor), "sword" if weapon != "" else "none"]


func _armor_look(armor_id: String) -> String:
	if armor_id == "":
		return "none"
	var def := float(ItemsDB.get_item(armor_id).get("def", 0.0))
	if def >= ARMOR_LOOK_DEF[2]:
		return "legion"
	if def >= ARMOR_LOOK_DEF[1]:
		return "plate"
	if def >= ARMOR_LOOK_DEF[0]:
		return "leather"
	return "none"


func _rebuild_sprite_frames() -> void:
	## The hero's sheet is chosen by equipment (see _variant_key) and read the
	## same way a monster's is: PoseArt says whether this sheet carries generated
	## pose art, so the hero breathes on four idle frames and swings through his
	## own attack poses exactly like the enemies do, and falls back to the LPC
	## frames for anything that has not been generated yet.
	_last_variant = _variant_key()
	_sheet_path = LPC_SHEET % [_last_variant.split("_")[1], _last_variant.split("_")[2]]
	var tex := load(_sheet_path)
	if tex == null:
		return
	var sf := SpriteFrames.new()
	for a_i in LPC_ANIMS.size():
		var anim: String = LPC_ANIMS[a_i]
		var columns: Array = _columns_for(anim, _sheet_path)
		var speed: float = float(LPC_FPS[anim])
		if columns.size() < int(LPC_FRAMES[anim]):
			# Generated attack art replaces six LPC frames with four larger poses:
			# hold the animation's wall-clock length so the swing still lands
			# inside the attack window. More frames than the block (idle) plays at
			# the block's own rate.
			speed *= float(LPC_FRAMES[anim]) / float(columns.size())
		for d_i in LPC_DIRS.size():
			var name := "%s_%s" % [anim, LPC_DIRS[d_i]]
			sf.add_animation(name)
			sf.set_animation_speed(name, speed)
			sf.set_animation_loop(name, anim in ["idle", "walk"])
			for col in columns:
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(float(col) * 64.0, (a_i * 4 + d_i) * 64.0, 64.0, 64.0)
				sf.add_frame(name, at)
	sprite.sprite_frames = sf
	sprite.centered = true
	sprite.offset = Vector2(0, -10)  # LPC frames are taller than the body pivot


func _columns_for(anim: String, sheet: String) -> Array:
	if anim == "idle":
		return PoseArt.idle_columns(sheet, int(LPC_FRAMES["idle"]))
	if anim == "slash":
		return PoseArt.slash_columns(sheet, int(LPC_FRAMES["slash"]))
	return range(int(LPC_FRAMES[anim]))


func revive() -> void:
	## Bring the hero back after a respawn. _dead was only ever set, never
	## cleared, so the hurt frame and the 90-degree death tilt survived into the
	## next life (audit M7).
	_dead = false
	_hurt_anim = 0.0
	if sprite != null:
		sprite.rotation = 0.0
	_update_anim()


func _on_died() -> void:
	_dead = true
	if sprite != null:
		var tw := create_tween()
		tw.tween_property(sprite, "rotation", deg_to_rad(90.0), 0.35)
