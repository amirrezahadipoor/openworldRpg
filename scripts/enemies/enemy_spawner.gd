class_name EnemySpawner
extends Node2D
## Spawns `count` enemies of one archetype around itself and respawns each
## slot RESPAWN_TIME seconds after death, reusing pooled enemy nodes.

const ENEMY_SCENE := "res://scenes/enemies/enemy.tscn"
const RESPAWN_TIME := 40.0

@export var archetype := "grunt"
@export var count := 2
@export var spread := 180.0
@export var power_scale := 1.0

var _pool: ObjectPool
var _slots: Array = []


func _ready() -> void:
	_pool = ObjectPool.new(load(ENEMY_SCENE), self, 0)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in count:
		_slots.append(Vector2(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread)))
	call_deferred("_spawn_all")


func _spawn_all() -> void:
	for i in _slots.size():
		_spawn_at(i)


func _spawn_at(slot_idx: int) -> void:
	if not is_inside_tree():
		return
	var e: Enemy = _pool.acquire()
	e.global_position = global_position + _slots[slot_idx]
	e.setup_archetype(archetype, power_scale)
	e.set_meta("slot", slot_idx)
	if not e.recycled.is_connected(_on_enemy_recycled):
		e.recycled.connect(_on_enemy_recycled)


func _on_enemy_recycled(e: Enemy) -> void:
	var slot := int(e.get_meta("slot", 0))
	_pool.release(e)
	await get_tree().create_timer(RESPAWN_TIME).timeout
	if is_inside_tree():
		_spawn_at(slot)
