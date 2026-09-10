extends Node
## GameState — central runtime state: stats, leveling, inventory, quests, talents.
## Serialized by SaveSystem (see DECISIONS.md #5, #7).

const XP_BASE: int = 100
const XP_GROWTH: float = 1.35

signal stats_changed

var level: int = 1
var xp: int = 0
var gold: int = 50
var talent_points: int = 0

# Meta (not serialized inside saves — chosen per session)
var current_slot := 1
var pending_load := false

# Base stats (before level/talent/gear modifiers).
var base_hp: float = 100.0
var base_mp: float = 50.0
var base_attack: float = 10.0
var base_defense: float = 5.0
var base_speed: float = 220.0

# Current pools.
var hp: float = 100.0
var mp: float = 50.0

# item_id -> quantity (stacking handled here; DB lookup in data/items.json)
var inventory: Dictionary = {"health_potion": 2}
# slot -> item_id
var equipment: Dictionary = {"weapon": "", "armor": "", "accessory": ""}
# quest_id -> "active" | "done"
var quests: Dictionary = {}
# quest_id -> { objective_id -> progress_count }
var quest_progress: Dictionary = {}
# free-form story flags (dialogue choices, secret found, ...)
var quest_flags: Dictionary = {}
# branch -> allocated points
var talents: Dictionary = {"combat": 0, "magic": 0, "utility": 0}


func _ready() -> void:
	hp = max_hp()
	mp = max_mp()


func reset() -> void:
	## Fresh-game state (New Game from the main menu).
	level = 1
	xp = 0
	gold = 50
	talent_points = 0
	hp = max_hp()
	mp = max_mp()
	inventory = {"health_potion": 2}
	equipment = {"weapon": "", "armor": "", "accessory": ""}
	quests = {}
	quest_progress = {}
	quest_flags = {}
	talents = {"combat": 0, "magic": 0, "utility": 0}
	stats_changed.emit()


func _process(delta: float) -> void:
	# Clarity talent: passive MP regeneration.
	if mp < max_mp() and mp_regen_per_sec() > 0.0:
		mp = minf(mp + mp_regen_per_sec() * delta, max_mp())


# --- Progression ------------------------------------------------------------

func xp_to_next() -> int:
	return int(XP_BASE * pow(XP_GROWTH, level - 1))


func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	xp += amount
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		talent_points += 1
		hp = max_hp()
		mp = max_mp()
		AudioManager.play_sfx("level_up")
		EventBus.player_leveled_up.emit(level)
	stats_changed.emit()


func spend_talent(branch: String) -> bool:
	if talent_points <= 0 or not talents.has(branch):
		return false
	talent_points -= 1
	talents[branch] = int(talents[branch]) + 1
	_clamp_pools()
	stats_changed.emit()
	return true


# --- Final stats (level + talents; gear is added in Phase 7) ----------------

func max_hp() -> float:
	var bonus := 15.0 if node_active("combat", 2) else 0.0  # Iron Skin
	return base_hp + (level - 1) * 12.0 + bonus + equipment_bonus("hp")


func max_mp() -> float:
	var bonus := 20.0 if node_active("magic", 1) else 0.0  # Arcane Focus
	return base_mp + (level - 1) * 6.0 + bonus + equipment_bonus("mp")


func attack() -> float:
	var bonus := 4.0 if node_active("combat", 1) else 0.0  # Power Strikes
	return base_attack + (level - 1) * 1.5 + bonus + equipment_bonus("atk")


func defense() -> float:
	var bonus := 4.0 if node_active("combat", 2) else 0.0  # Iron Skin
	return base_defense + (level - 1) * 1.0 + bonus + equipment_bonus("def")


func move_speed() -> float:
	var bonus := 22.0 if node_active("utility", 1) else 0.0  # Fleet Foot
	return base_speed + bonus + equipment_bonus("speed")


# --- Talent tree (node-active model, DECISIONS #19) ---------------------------

func node_active(branch: String, tier: int) -> bool:
	return int(talents.get(branch, 0)) >= tier


func attack_cooldown_mult() -> float:
	return 0.8 if node_active("combat", 3) else 1.0  # Swift Strikes


func potion_mult() -> float:
	return 1.35 if node_active("magic", 3) else 1.0  # Potent Brews


func gold_mult() -> float:
	return 1.2 if node_active("utility", 2) else 1.0  # Fortune


func mp_regen_per_sec() -> float:
	return 0.6 if node_active("magic", 2) else 0.0  # Clarity


func dodge_duration_bonus() -> float:
	return 0.08 if node_active("utility", 3) else 0.0  # Shadow Step


func equipment_bonus(key: String) -> float:
	var total := 0.0
	for slot in equipment:
		var id: String = equipment[slot]
		if id == "":
			continue
		total += float(ItemsDB.get_item(id).get(key, 0))
	return total


# --- Equipment & consumables ---------------------------------------------------

func equip(item_id: String) -> bool:
	if int(inventory.get(item_id, 0)) < 1:
		return false
	var slot := ItemsDB.get_slot(item_id)
	if slot == "" or not equipment.has(slot):
		return false
	var prev: String = equipment[slot]
	remove_item(item_id, 1)
	equipment[slot] = item_id
	if prev != "":
		add_item(prev, 1)
	_clamp_pools()
	stats_changed.emit()
	return true


func unequip(slot: String) -> bool:
	if not equipment.has(slot) or equipment[slot] == "":
		return false
	var prev: String = equipment[slot]
	equipment[slot] = ""
	add_item(prev, 1)
	_clamp_pools()
	stats_changed.emit()
	return true


func use_item(item_id: String) -> bool:
	if int(inventory.get(item_id, 0)) < 1:
		return false
	var it: Dictionary = ItemsDB.get_item(item_id)
	if String(it.get("type", "")) != "consumable":
		return false
	var heal := float(it.get("heal", 0)) * potion_mult()
	var mana := float(it.get("restore_mp", 0)) * potion_mult()
	if heal > 0.0:
		hp = clampf(hp + heal, 0.0, max_hp())
		EventBus.player_healed.emit(heal)
	if mana > 0.0:
		mp = clampf(mp + mana, 0.0, max_mp())
	remove_item(item_id, 1)
	EventBus.item_used.emit(item_id)
	AudioManager.play_sfx("item_use")
	return true


# --- Inventory ---------------------------------------------------------------

func add_item(item_id: String, qty: int = 1) -> void:
	inventory[item_id] = int(inventory.get(item_id, 0)) + qty
	if int(inventory[item_id]) <= 0:
		inventory.erase(item_id)


func remove_item(item_id: String, qty: int = 1) -> bool:
	if int(inventory.get(item_id, 0)) < qty:
		return false
	add_item(item_id, -qty)
	return true


func add_gold(amount: int) -> void:
	var gained := int(round(float(amount) * gold_mult())) if amount > 0 else amount
	gold = maxi(0, gold + gained)
	EventBus.gold_changed.emit(gold)


func _clamp_pools() -> void:
	hp = clampf(hp, 0.0, max_hp())
	mp = clampf(mp, 0.0, max_mp())


# --- Serialization ------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"level": level, "xp": xp, "gold": gold, "talent_points": talent_points,
		"hp": hp, "mp": mp,
		"inventory": inventory.duplicate(),
		"equipment": equipment.duplicate(),
		"quests": quests.duplicate(),
		"quest_progress": quest_progress.duplicate(true),
		"quest_flags": quest_flags.duplicate(),
		"talents": talents.duplicate(),
	}


func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	level = int(d.get("level", 1))
	xp = int(d.get("xp", 0))
	gold = int(d.get("gold", 50))
	talent_points = int(d.get("talent_points", 0))
	inventory = (d.get("inventory", {}) as Dictionary).duplicate()
	equipment = (d.get("equipment", {"weapon": "", "armor": "", "accessory": ""}) as Dictionary).duplicate()
	quests = (d.get("quests", {}) as Dictionary).duplicate()
	quest_progress = (d.get("quest_progress", {}) as Dictionary).duplicate(true)
	quest_flags = (d.get("quest_flags", {}) as Dictionary).duplicate()
	talents = (d.get("talents", {"combat": 0, "magic": 0, "utility": 0}) as Dictionary).duplicate()
	hp = clampf(float(d.get("hp", max_hp())), 0.0, max_hp())
	mp = clampf(float(d.get("mp", max_mp())), 0.0, max_mp())
	stats_changed.emit()
