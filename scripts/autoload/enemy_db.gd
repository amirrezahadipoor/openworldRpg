extends Node
## EnemyDB — loads data/enemies.json; archetype lookup for spawners/enemies.

var archetypes: Dictionary = {}


func _ready() -> void:
	var path := "res://data/enemies.json"
	if not FileAccess.file_exists(path):
		push_error("EnemyDB: data/enemies.json missing")
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		archetypes = (parsed as Dictionary).get("archetypes", {})


func get_archetype(id: String) -> Dictionary:
	return archetypes.get(id, {})


func roll_drops(id: String) -> Dictionary:
	## Returns {"gold": int, "items": [item_id, ...]} rolled from drop tables.
	var cfg: Dictionary = get_archetype(id)
	var drops: Dictionary = cfg.get("drops", {})
	var out := {"gold": 0, "items": []}
	var gold_range: Array = drops.get("gold", [0, 0])
	if gold_range.size() == 2:
		out["gold"] = randi_range(int(gold_range[0]), int(gold_range[1]))
	for entry in drops.get("items", []):
		if entry is Array and entry.size() == 2:
			if randf() < float(entry[1]):
				(out["items"] as Array).append(entry[0])
	return out
