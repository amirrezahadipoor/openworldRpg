extends Node
## PoolManager — shared pools for high-frequency objects (projectiles).

const PROJECTILE_SCENE := "res://scenes/combat/projectile.tscn"
const PROJECTILE_PREWARM := 16

var _projectiles: ObjectPool


func _ready() -> void:
	var holder := Node2D.new()
	holder.name = "Projectiles"
	add_child(holder)
	_projectiles = ObjectPool.new(load(PROJECTILE_SCENE), holder, PROJECTILE_PREWARM)


func spawn_projectile(pos: Vector2, dir: Vector2, damage: float, speed: float, color: Color, friendly: bool = false) -> void:
	var p: Projectile = _projectiles.acquire()
	p.launch(pos, dir, damage, speed, color, friendly)


func release_projectile(p: Projectile) -> void:
	_projectiles.release(p)
