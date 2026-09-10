class_name Juice
extends Node2D
## Lightweight one-shot particle bursts for combat/progression feedback.
## Listens to EventBus; every burst is a self-freeing CPUParticles2D.


func _ready() -> void:
	z_index = 40
	EventBus.enemy_hurt.connect(_on_enemy_hurt)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.player_leveled_up.connect(_on_level_up)
	EventBus.player_dodged.connect(_on_dodged)
	EventBus.item_picked_up.connect(_on_picked_up)


func burst(world_pos: Vector2, color: Color, amount: int, speed: float,
		spread_deg: float, life: float, gravity: Vector2 = Vector2(0, 60),
		scale_amount: float = 2.5) -> void:
	var p := CPUParticles2D.new()
	p.position = world_pos
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = life
	p.direction = Vector2.UP
	p.spread = spread_deg
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = gravity
	p.scale_amount_min = scale_amount * 0.5
	p.scale_amount_max = scale_amount
	p.color = color
	add_child(p)
	p.restart()
	get_tree().create_timer(life + 0.15).timeout.connect(p.queue_free)


func _on_enemy_hurt(enemy: Node, _amount: float, dir: Vector2) -> void:
	if enemy is Node2D:
		var pos: Vector2 = (enemy as Node2D).global_position
		burst(pos - dir * 6.0, Color(1, 0.92, 0.65, 0.95), 6, 130.0, 50.0, 0.22,
			Vector2(-dir.x * 140.0, -40.0), 1.8)


func _on_enemy_died(enemy: Node) -> void:
	if enemy is Node2D:
		burst((enemy as Node2D).global_position, Color(0.55, 0.5, 0.48, 0.8),
			14, 95.0, 180.0, 0.5, Vector2(0, -30), 3.2)


func _on_level_up(_new_level: int) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player is Node2D:
		burst((player as Node2D).global_position, Color(1.0, 0.85, 0.35, 0.95),
			26, 190.0, 180.0, 0.8, Vector2(0, 140), 2.6)


func _on_dodged(player: Node) -> void:
	if player is Node2D:
		burst((player as Node2D).global_position + Vector2(0, 10),
			Color(0.8, 0.78, 0.7, 0.55), 8, 60.0, 120.0, 0.3, Vector2(0, -10), 2.0)


func _on_picked_up(_item_id: String, _qty: int) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player is Node2D:
		burst((player as Node2D).global_position, Color(0.65, 0.9, 1.0, 0.9),
			8, 110.0, 160.0, 0.4, Vector2(0, -60), 1.8)
