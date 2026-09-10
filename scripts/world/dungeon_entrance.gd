class_name DungeonEntrance
extends WorldInteractable
## Phase E §1 — the surface mouth of a dungeon. A stair sinking into the
## ground with the dungeon's name over it; interacting asks main.gd to move the
## player into the dungeon interior.

signal entered(dungeon_id: String)

var dungeon_id := ""
var dungeon_name := "Dungeon"
var depth := 1


func configure(id: String) -> void:
	dungeon_id = id
	var d := Dungeon.get_data(id)
	dungeon_name = String(d.get("name", id))
	depth = (d.get("floors", []) as Array).size()
	prompt_text = "Enter %s" % dungeon_name


func _build_visual() -> void:
	# A dark stair mouth in the ground with a lit rim.
	_poly(PackedVector2Array([
		Vector2(-38, -22), Vector2(38, -22), Vector2(28, 22), Vector2(-28, 22),
	]), Color(0.10, 0.09, 0.11))
	for i in 4:
		var y := -16.0 + float(i) * 10.0
		_poly(PackedVector2Array([
			Vector2(-30, y), Vector2(30, y), Vector2(26, y + 5), Vector2(-26, y + 5),
		]), Color(0.22, 0.20, 0.23).lightened(float(i) * 0.05))

	var light := PointLight2D.new()
	light.texture = load("res://assets/placeholder/light.svg")
	light.color = Color(1.0, 0.6, 0.3)
	light.energy = 0.5
	light.texture_scale = 1.4
	light.position = Vector2(0, 10)
	add_child(light)

	var plate := Label.new()
	plate.text = "%s\n%d floors" % [dungeon_name, depth]
	plate.position = Vector2(-90, 26)
	plate.custom_minimum_size = Vector2(180, 0)
	plate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plate.add_theme_font_size_override("font_size", 12)
	plate.add_theme_color_override("font_color", Color(1, 0.88, 0.7, 0.9))
	plate.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	plate.add_theme_constant_override("outline_size", 4)
	add_child(plate)


func _on_interact() -> void:
	entered.emit(dungeon_id)
	interacted.emit(self)
