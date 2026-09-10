class_name Projectile
extends Area2D
## Pooled projectile (see PoolManager). `friendly` = cast by the player and
## damages enemies via their "hurtbox" areas; otherwise damages the player.
## A short arm-time prevents hitting the caster at spawn.

var velocity := Vector2.ZERO
var damage := 8.0
var lifetime := 0.0
var friendly := false

const MAX_LIFETIME := 3.5
const ARM_TIME := 0.08

var _armed := false
var _arm_timer := 0.0
## Set the moment the projectile connects. A pooled projectile is released from
## inside its own body_entered/area_entered signal, so it is parked on top of the
## thing it just hit while its Area2D is still live; without this flag the next
## contact dealt damage again (phantom hits with no projectile in flight).
var _spent := false

@onready var _sprite: Sprite2D = $Sprite


func launch(pos: Vector2, dir: Vector2, dmg: float, speed: float, color: Color, is_friendly: bool = false) -> void:
	global_position = pos
	velocity = dir.normalized() * speed
	damage = dmg
	lifetime = MAX_LIFETIME
	friendly = is_friendly
	rotation = velocity.angle()
	_sprite.modulate = color
	_spent = false
	monitoring = true
	_armed = false
	_arm_timer = ARM_TIME
	if friendly:
		collision_mask = 2  # enemy hurtboxes
	else:
		collision_mask = 1  # player body


func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		PoolManager.release_projectile(self)
		return
	if not _armed:
		_arm_timer -= delta
		if _arm_timer <= 0.0:
			_armed = true
	global_position += velocity * delta


func _on_body_entered(body: Node2D) -> void:
	# Hostile projectiles damage the player.
	if _spent or friendly or not _armed:
		return
	if body.is_in_group("player") and body.has_method("take_hit"):
		_spent = true
		body.take_hit(damage, velocity.normalized())
		PoolManager.release_projectile(self)


func _on_area_entered(area: Area2D) -> void:
	# Friendly projectiles damage enemy hurtboxes (take_hit lives on the owner).
	if _spent or not friendly or not _armed:
		return
	if area.is_in_group("hurtbox"):
		var target: Node = area.get_parent()
		if target != null and target.has_method("take_hit"):
			_spent = true
			target.take_hit(damage, velocity.normalized())
			PoolManager.release_projectile(self)


func on_pool_acquire() -> void:
	_spent = false
	_armed = false
	monitoring = true


func on_pool_release() -> void:
	# Deferred, not direct: the pool releases from inside the physics signal that
	# fired the hit, and Godot refuses a direct assignment there ("Function
	# blocked during in/out signal") — which used to leave the parked projectile
	# live and dealing damage. Deferred calls are FIFO, so a re-acquire in the
	# same frame still ends with monitoring back on.
	set_deferred("monitoring", false)
	velocity = Vector2.ZERO
