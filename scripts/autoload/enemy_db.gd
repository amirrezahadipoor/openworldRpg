extends Node
## EnemyDB — loads data/enemies.json; archetype lookup for spawners/enemies.

var archetypes: Dictionary = {}
var _spawns: Dictionary = {}


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
		_spawns = (parsed as Dictionary).get("spawns", {})


func get_archetype(id: String) -> Dictionary:
	return archetypes.get(id, {})


func floor_scale(id: String, floor: int) -> float:
	## Phase E §6: deeper dungeon floors scale hp/damage/xp.
	## scale = 1.0 + floor_multiplier * (floor - 1)
	var fm := float(get_archetype(id).get("floor_multiplier", 0.0))
	return 1.0 + fm * float(maxi(1, floor) - 1)


func roll_rarity(id: String) -> String:
	## Phase F1: the bonus-gear roll. Better tiers weight rare+ higher, which is
	## the only route to lifesteal gear (lifesteal exists solely on rare-or-better
	## items), so "a bit of leech" is always a genuine find, never a starter gift.
	var table: Dictionary = get_archetype(id).get("drops", {}).get("rarity_table", {})
	var total := 0.0
	for r in table:
		total += maxf(float(table[r]), 0.0)
	if total <= 0.0:
		return ""
	var roll := randf() * total
	for r in ItemsDB.RARITY_ORDER:
		var w := maxf(float(table.get(r, 0.0)), 0.0)
		if roll < w:
			return r
		roll -= w
	return ""


func roll_item_of_rarity(rarity: String) -> String:
	## Picks a random item at exactly that rarity. Equipment is preferred over
	## materials so a "rare drop" feels like a rare drop, but materials are
	## included as a fallback so every table has entries.
	var gear: Array = []
	var any: Array = []
	for item_id in ItemsDB.items:
		if ItemsDB.get_rarity(item_id) != rarity:
			continue
		any.append(item_id)
		if ItemsDB.get_type(item_id) in ["weapon", "armor", "accessory"]:
			gear.append(item_id)
	var pool: Array = gear if not gear.is_empty() else any
	if pool.is_empty():
		return ""
	return String(pool[randi() % pool.size()])


func roll_bonus_loot(id: String) -> String:
	## One rarity-weighted item, or "" when the roll comes up empty.
	var rarity := roll_rarity(id)
	if rarity == "":
		return ""
	return roll_item_of_rarity(rarity)


func tier_of(id: String) -> int:
	return int(get_archetype(id).get("tier", 1))


func level_band(id: String) -> Array:
	return get_archetype(id).get("level_band", [1, 100])


func biome_of(id: String) -> String:
	return String(get_archetype(id).get("biome", ""))


func is_boss(id: String) -> bool:
	return bool(get_archetype(id).get("boss", false))


func spawn_table(biome: String) -> Array:
	## Placement is data-driven: a biome's table is derived from each
	## archetype's own band, so a monster can never spawn outside its level band.
	var entry: Dictionary = _spawns.get(biome, {})
	return entry.get("archetypes", [])


func spawns() -> Dictionary:
	return _spawns


func spawnable_band(biome: String) -> Array:
	return ((_spawns.get(biome, {}) as Dictionary).get("level_band", [1, 100]))


func band_power_scale(band: Array) -> float:
	## Deeper-fields monsters are tougher: scale the archetype's own stats by how
	## far into its band a biome sits. Keeps one archetype usable across a whole
	## region without a second copy of it in the data.
	var lo := float(band[0]) if band.size() == 2 else 1.0
	return 1.0 + maxf(lo - 1.0, 0.0) * 0.022


func monsters() -> Array:
	var out := []
	for id in archetypes:
		if not bool(archetypes[id].get("boss", false)):
			out.append(id)
	return out


func bosses() -> Array:
	var out := []
	for id in archetypes:
		if bool(archetypes[id].get("boss", false)):
			out.append(id)
	return out


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
	# One rarity-weighted bonus roll (Phase F1). Out here rather than in the
	# drop table so every monster shares the same scaling rule.
	var bonus := roll_bonus_loot(id)
	if bonus != "":
		(out["items"] as Array).append(bonus)
	return out
