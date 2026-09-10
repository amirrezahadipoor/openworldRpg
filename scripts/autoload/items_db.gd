extends Node
## ItemsDB — loads data/items.json once; single source of truth for every
## system that touches items (inventory, loot, shop, equipment).

var items: Dictionary = {}


func _ready() -> void:
	var path := "res://data/items.json"
	if not FileAccess.file_exists(path):
		push_error("ItemsDB: data/items.json missing")
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		items = (parsed as Dictionary).get("items", {})


func get_item(id: String) -> Dictionary:
	return items.get(id, {})


func item_name(id: String) -> String:
	return String(get_item(id).get("name", id))


func get_type(id: String) -> String:
	return String(get_item(id).get("type", ""))


func get_slot(id: String) -> String:
	return String(get_item(id).get("slot", ""))


func stack_size(id: String) -> int:
	return int(get_item(id).get("stack", 1))


func get_value(id: String) -> int:
	return int(get_item(id).get("value", 0))


func get_desc(id: String) -> String:
	return String(get_item(id).get("desc", ""))
