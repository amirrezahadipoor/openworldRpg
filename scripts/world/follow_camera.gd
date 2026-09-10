class_name FollowCamera
extends Camera2D
## Smooth-follow camera with a decaying shake API.
## Usage: camera.target = player ; camera.shake(0.4)

@export var follow_speed := 8.0

var target: Node2D
var _shake := 0.0


func _ready() -> void:
	make_current()


func _process(delta: float) -> void:
	if target != null:
		var t := clampf(follow_speed * delta, 0.0, 1.0)
		global_position = global_position.lerp(target.global_position, t)
	if _shake > 0.0:
		_shake = maxf(_shake - delta * 2.5, 0.0)
		offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake * 14.0
	else:
		offset = Vector2.ZERO


func shake(power: float) -> void:
	_shake = clampf(_shake + power, 0.0, 1.0)
