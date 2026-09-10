class_name Projectile
extends Area2D
## Enemy projectile. Pooled via PoolManager — never queue_free() directly.

var velocity := Vector2.ZERO
var damage := 8.0
var lifetime := 0.0

const MAX_LIFETIME := 3.5


func launch(pos: Vector2, dir: Vector2, dmg: float, speed: float, color: Color) -> void:
	global_position = pos
	velocity = dir.normalized() * speed
	damage = dmg
	lifetime = MAX_LIFETIME
	rotation = velocity.angle()
	$Sprite.modulate = color
	monitoring = true


func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		PoolManager.release_projectile(self)
		return
	global_position += velocity * delta


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and body.has_method("take_hit"):
		body.take_hit(damage, velocity.normalized())
		PoolManager.release_projectile(self)


func on_pool_acquire() -> void:
	monitoring = true


func on_pool_release() -> void:
	monitoring = false
	velocity = Vector2.ZERO
