class_name VirtualJoystick
extends Control
## Dynamic virtual joystick: the base appears wherever the player touches
## inside this control's rect. Emits `vector_changed` (also readable as
## `output`). Works with real touch and emulated touch from mouse.

signal vector_changed(vec: Vector2)

const DEADZONE := 0.18

var output := Vector2.ZERO

var _touch_index := -1
var _base_center := Vector2.ZERO


func _ready() -> void:
	custom_minimum_size = Vector2(190, 190)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _touch_index == -1:
			_touch_index = t.index
			_base_center = t.position
			_update(t.position)
			accept_event()
		elif not t.pressed and t.index == _touch_index:
			_release()
			accept_event()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_update((event as InputEventScreenDrag).position)
		accept_event()


func _release() -> void:
	_touch_index = -1
	output = Vector2.ZERO
	vector_changed.emit(output)
	queue_redraw()


func _update(pos: Vector2) -> void:
	var radius := minf(size.x, size.y) * 0.42
	var vec := (pos - _base_center) / maxf(radius, 1.0)
	if vec.length() > 1.0:
		vec = vec.normalized()
	output = vec if vec.length() > DEADZONE else Vector2.ZERO
	vector_changed.emit(output)
	queue_redraw()


func _draw() -> void:
	var radius := minf(size.x, size.y) * 0.42
	var center := _base_center if _touch_index != -1 else size * 0.5
	draw_circle(center, radius, Color(1, 1, 1, 0.07))
	draw_arc(center, radius, 0.0, TAU, 48, Color(1, 1, 1, 0.22), 2.0)
	draw_circle(center + output * radius * 0.6, radius * 0.34, Color(1, 1, 1, 0.28))
