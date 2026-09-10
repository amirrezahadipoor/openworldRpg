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

@onready var _sprite: Sprite2D = $Sprite


func launch(pos: Vector2, dir: Vector2, dmg: float, speed: float, color: Color, is_friendly: bool = false) -> void:
	global_position = pos
	velocity = dir.normalized() * speed
	damage = dmg
	lifetime = MAX_LIFETIME
	friendly = is_friendly
	rotation = velocity.angle()
	_sprite.modulate = color
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
	if not friendly and _armed and body.is_in_group("player") and body.has_method("take_hit"):
		body.take_hit(damage, velocity.normalized())
		PoolManager.release_projectile(self)


func _on_area_entered(area: Area2D) -> void:
	# Friendly projectiles damage enemy hurtboxes (take_hit lives on the owner).
	if friendly and _armed and area.is_in_group("hurtbox"):
		var target: Node = area.get_parent()
		if target != null and target.has_method("take_hit"):
			target.take_hit(damage, velocity.normalized())
			PoolManager.release_projectile(self)


func on_pool_acquire() -> void:
	monitoring = true


func on_pool_release() -> void:
	monitoring = false
	velocity = Vector2.ZERO
