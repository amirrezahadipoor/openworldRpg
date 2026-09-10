class_name SecretGate
extends StaticBody2D
## Removable rock barrier. Opens when EventBus.gate_opened fires with the
## matching id, or if the flag was already set (save loaded).

@export var gate_id := ""


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_build_visual()
	EventBus.gate_opened.connect(_on_gate_opened)
	if GameState.quest_flags.get("gate_%s_open" % gate_id, false):
		_open(true)


func _build_visual() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(gate_id) & 0x7FFFFFFF
	for i in 5:
		var rock := Polygon2D.new()
		var pts := PackedVector2Array()
		var r := rng.randf_range(18.0, 30.0)
		for k in 7:
			var a := TAU * float(k) / 7.0
			pts.append(Vector2(cos(a), sin(a)) * r * rng.randf_range(0.8, 1.1))
		rock.polygon = pts
		rock.color = Color(0.42, 0.40, 0.38).darkened(rng.randf_range(0.0, 0.25))
		rock.position = Vector2(rng.randf_range(-26, 26), rng.randf_range(-16, 16))
		add_child(rock)
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(96, 64)
	cs.shape = rect
	add_child(cs)


func _on_gate_opened(id: String) -> void:
	if id == gate_id:
		_open(false)


func _open(instant: bool) -> void:
	EventBus.gate_opened.disconnect(_on_gate_opened)
	for child in get_children():
		if child is CollisionShape2D:
			(child as CollisionShape2D).set_deferred("disabled", true)
	if instant:
		queue_free()
		return
	AudioManager.play_sfx("hit")
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.7)
	tw.tween_callback(queue_free)
