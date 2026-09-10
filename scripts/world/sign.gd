class_name Sign
extends WorldInteractable
## Readable signpost. Routes through EventBus.world_interacted so main.gd
## can display the text in the dialogue box.

@export var title := "Sign"
@export var text := ""


func _build_visual() -> void:
	_poly(PackedVector2Array([
		Vector2(-3, -4), Vector2(3, -4), Vector2(3, 14), Vector2(-3, 14),
	]), Color(0.36, 0.26, 0.16))
	_poly(PackedVector2Array([
		Vector2(-16, -22), Vector2(16, -22), Vector2(16, -6), Vector2(-16, -6),
	]), Color(0.52, 0.38, 0.22))
	_poly(PackedVector2Array([
		Vector2(-13, -19), Vector2(13, -19), Vector2(13, -9), Vector2(-13, -9),
	]), Color(0.62, 0.48, 0.30))


func _on_interact() -> void:
	AudioManager.play_sfx("ui_click")
	EventBus.world_interacted.emit(self)
