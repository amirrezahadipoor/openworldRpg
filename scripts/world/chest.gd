class_name Chest
extends WorldInteractable
## One-shot loot chest. Opened state persists via GameState.quest_flags
## ("chest_<id>_opened"), so it survives save/load and chunk reloads.

@export var chest_id := "chest"
@export var gold := 0
@export var item_id := ""

const PICKUP_SCENE := "res://scenes/world/pickup.tscn"

var _lid: Polygon2D


func _flag_key() -> String:
	return "chest_%s_opened" % chest_id


func is_opened() -> bool:
	return bool(GameState.quest_flags.get(_flag_key(), false))


func _ready() -> void:
	if is_opened():
		prompt_text = "Empty chest"
	super._ready()


func _build_visual() -> void:
	_poly(PackedVector2Array([
		Vector2(-18, 6), Vector2(18, 6), Vector2(18, 16), Vector2(-18, 16),
	]), Color(0.10, 0.08, 0.06, 0.55), Vector2.ZERO, -1)  # shadow
	var body := _poly(PackedVector2Array([
		Vector2(-16, -6), Vector2(16, -6), Vector2(16, 12), Vector2(-16, 12),
	]), Color(0.45, 0.30, 0.16))
	body.add_child(_metal_band())
	_lid = _poly(PackedVector2Array([
		Vector2(-17, -14), Vector2(17, -14), Vector2(17, -6), Vector2(-17, -6),
	]), Color(0.55, 0.38, 0.20))
	if is_opened():
		_lid.color = Color(0.30, 0.24, 0.18)


func _metal_band() -> Polygon2D:
	var band := Polygon2D.new()
	band.polygon = PackedVector2Array([
		Vector2(-3, -6), Vector2(3, -6), Vector2(3, 12), Vector2(-3, 12),
	])
	band.color = Color(0.72, 0.62, 0.30)
	return band


func _on_interact() -> void:
	if is_opened():
		return
	GameState.quest_flags[_flag_key()] = true
	AudioManager.play_sfx("pickup")
	EventBus.interactable_used.emit(self)
	var scene: PackedScene = load(PICKUP_SCENE)
	var host := get_tree().current_scene
	if gold > 0:
		var g: Pickup = scene.instantiate()
		host.add_child(g)
		g.global_position = global_position + Vector2(0, -6)
		g.setup_gold(gold)
	if item_id != "":
		var it: Pickup = scene.instantiate()
		host.add_child(it)
		it.global_position = global_position + Vector2(18, -12)
		it.setup_item(item_id)
	_lid.color = Color(0.30, 0.24, 0.18)
	set_prompt("Empty chest")
