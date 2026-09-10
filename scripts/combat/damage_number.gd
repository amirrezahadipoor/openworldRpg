class_name DamageNumber
extends Label
## Floating damage number. Spawned via DamageNumber.spawn(...) — drifts up,
## fades out, frees itself.


static func spawn(parent: Node, pos: Vector2, text: String, color: Color) -> void:
	var n := DamageNumber.new()
	n.text = text
	n.add_theme_color_override("font_color", color)
	n.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	n.add_theme_constant_override("outline_size", 4)
	n.add_theme_font_size_override("font_size", 17)
	parent.add_child(n)
	n.global_position = pos
	n._animate()


func _animate() -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "position", position + Vector2(randf_range(-10.0, 10.0), -48.0), 0.7)
	tw.tween_property(self, "modulate:a", 0.0, 0.7)
	tw.chain().tween_callback(queue_free)
