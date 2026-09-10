class_name Lever
extends WorldInteractable
## Single-use lever that opens a SecretGate (by gate_id). State persists in
## GameState.quest_flags ("lever_<id>" / "gate_<gate_id>_open").

@export var lever_id := "lever"
@export var gate_id := ""

var _stick: Polygon2D


func is_pulled() -> bool:
	return bool(GameState.quest_flags.get("lever_%s" % lever_id, false))


func _ready() -> void:
	if is_pulled():
		prompt_text = "Already pulled"
	super._ready()


func _build_visual() -> void:
	_poly(PackedVector2Array([
		Vector2(-10, 6), Vector2(10, 6), Vector2(10, 14), Vector2(-10, 14),
	]), Color(0.35, 0.33, 0.32))
	_stick = Polygon2D.new()
	_stick.polygon = PackedVector2Array([
		Vector2(-2, 0), Vector2(2, 0), Vector2(2, -26), Vector2(-2, -26),
	])
	_stick.color = Color(0.55, 0.42, 0.26)
	_stick.position = Vector2(0, 8)
	_stick.rotation = deg_to_rad(-30) if not is_pulled() else deg_to_rad(30)
	add_child(_stick)
	var knob := Polygon2D.new()
	knob.polygon = PackedVector2Array([
		Vector2(-4, 0), Vector2(4, 0), Vector2(4, 6), Vector2(-4, 6),
	])
	knob.color = Color(0.78, 0.66, 0.30)
	knob.position = Vector2(0, -26)
	_stick.add_child(knob)


func _on_interact() -> void:
	if is_pulled():
		return
	GameState.quest_flags["lever_%s" % lever_id] = true
	GameState.quest_flags["gate_%s_open" % gate_id] = true
	_stick.rotation = deg_to_rad(30)
	AudioManager.play_sfx("item_use")
	EventBus.gate_opened.emit(gate_id)
	EventBus.interactable_used.emit(self)
	set_prompt("Already pulled")
