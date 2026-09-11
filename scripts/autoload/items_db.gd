extends Node
## ItemsDB — loads data/items.json once; single source of truth for every
## system that touches items (inventory, loot, shop, equipment).

## Rarity is a POWER ORDERING, not a label: `RARITY_ORDER` is the canonical
## weakest-to-strongest sequence, and `RARITY_BUDGET` is the maximum total stat
## points an item of that tier may carry. `tools/gen_items.py` authors items to
## the budget and `tests/items_test.gd` enforces it.
const RARITY_ORDER: Array[String] = ["common", "uncommon", "rare", "mythical", "legendary"]
const RARITY_BUDGET := {
	"common": 12.0,
	"uncommon": 26.0,
	"rare": 48.0,
	"mythical": 78.0,
	"legendary": 120.0,
}
const RARITY_COLOR := {
	"common": Color(0.82, 0.82, 0.82),
	"uncommon": Color(0.45, 0.85, 0.45),
	"rare": Color(0.40, 0.65, 1.00),
	"mythical": Color(0.78, 0.45, 1.00),
	"legendary": Color(1.00, 0.66, 0.20),
}
## Stat keys that count toward the budget, weighted by how strong a point is.
const STAT_WEIGHT := {
	"atk": 3.0,
	"def": 2.5,
	"hp": 0.35,
	"mp": 0.25,
	"speed": 1.2,
	"mp_regen": 25.0,
	"crit": 60.0,
	"lifesteal": 220.0,
}

var items: Dictionary = {}

## Per-item pixel-art icons authored as sprite sheets and split by
## tools/art/make_item_icons.py. Before these existed every item — a potion, a
## sword, a relic — showed only as text (or one generic loot bag in the world).
const ICON_DIR := "res://assets/items/"
const GENERIC_ICON := "res://assets/world/loot.png"
var _icon_cache: Dictionary = {}


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


func get_rarity(id: String) -> String:
	return String(get_item(id).get("rarity", "common"))


func rarity_color(id: String) -> Color:
	return RARITY_COLOR.get(get_rarity(id), Color.WHITE)


func icon_path(id: String) -> String:
	## res:// path of the item's own icon, or the generic loot sprite.
	var own := ICON_DIR + id + ".png"
	return own if ResourceLoader.exists(own) else GENERIC_ICON


func has_own_icon(id: String) -> bool:
	return ResourceLoader.exists(ICON_DIR + id + ".png")


func icon(id: String) -> Texture2D:
	## Cached icon texture (null only if even the fallback is missing).
	if _icon_cache.has(id):
		return _icon_cache[id]
	var tex: Texture2D = null
	var path := icon_path(id)
	if ResourceLoader.exists(path):
		tex = load(path)
	_icon_cache[id] = tex
	return tex


func rarity_rank(id: String) -> int:
	## 0 = common ... 4 = legendary. Used for sorting and drop weighting.
	return RARITY_ORDER.find(get_rarity(id))


func stat_budget_used(id: String) -> float:
	## Weighted stat total, so "is this item within its rarity budget?" is a
	## single number both the generator and the tests can agree on.
	##
	## The budget is a GEAR ladder. Consumables and materials are excluded: a
	## timed buff (e.g. +30% speed for 10s) is not a stat line, and counting it
	## would make a potion "outrank" a legendary sword on the rarity ladder.
	var t := get_type(id)
	if t not in ["weapon", "armor", "accessory"]:
		return 0.0
	var total := 0.0
	for key in STAT_WEIGHT:
		total += absf(float(get_item(id).get(key, 0))) * float(STAT_WEIGHT[key])
	return total


func within_budget(id: String) -> bool:
	return stat_budget_used(id) <= float(RARITY_BUDGET.get(get_rarity(id), 12.0)) + 0.001


func has_lifesteal(id: String) -> bool:
	return float(get_item(id).get("lifesteal", 0.0)) > 0.0


func affordable_tier(max_rarity: String) -> Array:
	## Every item at or below a rarity tier — lets shops scale with progress.
	var limit := rarity_rank(max_rarity)
	var out := []
	for id in items:
		if rarity_rank(String(id)) <= limit:
			out.append(id)
	return out
