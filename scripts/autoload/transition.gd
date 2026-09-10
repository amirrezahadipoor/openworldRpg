extends CanvasLayer
## Global fade transition for scene changes. Autoload persists across the
## change, so one call covers fade-out -> switch -> fade-in.

var _rect: ColorRect
var _busy := false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.color = Color(0, 0, 0, 1)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	fade_in(0.5)


func go_to(path: String) -> void:
	if _busy:
		return
	_busy = true
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(_rect, "color:a", 1.0, 0.26)
	await tw.finished
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	fade_in(0.4)


func fade_in(duration: float) -> void:
	var tw := create_tween()
	tw.tween_property(_rect, "color:a", 0.0, duration)
	await tw.finished
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false
