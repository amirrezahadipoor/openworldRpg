class_name ObjectPool
extends RefCounted
## Generic scene-node pool (Roadmap Phase 5: pooling for projectiles/enemies).
## Pooled nodes implement optional hooks:
##   on_pool_acquire() / on_pool_release()

var _scene: PackedScene
var _parent: Node
var _free: Array = []


func _init(scene: PackedScene, parent: Node, prewarm: int = 0) -> void:
	_scene = scene
	_parent = parent
	for i in prewarm:
		var n: Node = _scene.instantiate()
		_parent.add_child(n)
		_deactivate(n)
		_free.append(n)


func acquire() -> Node:
	var n: Node
	if _free.size() > 0:
		n = _free.pop_back()
	else:
		n = _scene.instantiate()
		_parent.add_child(n)
	n.visible = true
	n.set_physics_process(true)
	if n.has_method("on_pool_acquire"):
		n.call("on_pool_acquire")
	return n


func release(n: Node) -> void:
	if n == null or not is_instance_valid(n):
		return
	# Releasing the same node twice used to put it in the free list twice, so
	# acquire() could hand one enemy or projectile to two callers at once
	# (audit M6).
	if n in _free:
		return
	_deactivate(n)
	_free.append(n)


func _deactivate(n: Node) -> void:
	n.set_physics_process(false)
	n.visible = false
	if n.has_method("on_pool_release"):
		n.call("on_pool_release")
