extends Node
## GameState — central runtime state: stats, leveling, inventory, quests, talents.
## Serialized by SaveSystem (see DECISIONS.md #5, #7).

# --- Level curve (Phase E §6, DECISIONS #21) --------------------------------
# Three tapering segments over levels 1-100, exactly as the content bible
# specifies: 1-20 (80 x L^1.8), 21-60 (x1.3 growth), 61-100 (x1.15 growth).
# The bible's literal mid/late formulas restart from a small constant, which
# makes the curve *decrease* at the 20->21 and 60->61 seams (L20 costs 17,576 XP
# but L21 would cost 1,500). Each segment is therefore anchored to the previous
# segment's terminal cost, which keeps the curves monotonic and seamless while
# preserving the authored exponents and segment boundaries.
const XP_BASE: float = 80.0
const XP_EXP_EARLY: float = 1.8
const XP_EXP_MID: float = 1.3
const XP_EXP_LATE: float = 1.15
const XP_SEG1_END: int = 20
const XP_SEG2_END: int = 60
const XP_MAX_LEVEL: int = 100
const MILESTONE_STEP: int = 10
const MILESTONES_PATH: String = "res://data/milestones.json"

signal stats_changed

var level: int = 1
var xp: int = 0
var gold: int = 50
var talent_points: int = 0
var milestones_claimed: Array[int] = []

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
	milestones_claimed = []
	hp = max_hp()
	mp = max_mp()
	inventory = {"health_potion": 2}
	equipment = {"weapon": "", "armor": "", "accessory": ""}
	quests = {}
	quest_progress = {}
	quest_flags = {"wp_camp": true}  # starting campfire is always lit
	talents = {"combat": 0, "magic": 0, "utility": 0}
	stats_changed.emit()


func _process(delta: float) -> void:
	# Clarity talent: passive MP regeneration.
	if mp < max_mp() and mp_regen_per_sec() > 0.0:
		mp = minf(mp + mp_regen_per_sec() * delta, max_mp())


# --- Progression ------------------------------------------------------------

func xp_to_next(at_level: int = -1) -> int:
	## XP required to advance FROM the given level. 0 at the level cap.
	var lv: int = level if at_level < 0 else at_level
	if lv >= XP_MAX_LEVEL:
		return 0
	if lv <= XP_SEG1_END:
		return int(round(XP_BASE * pow(float(lv), XP_EXP_EARLY)))
	if lv <= XP_SEG2_END:
		return int(round(float(_seg1_end()) * pow(float(lv - 1) / float(XP_SEG1_END), XP_EXP_MID)))
	return int(round(float(_seg2_end()) * pow(float(lv - 1) / float(XP_SEG2_END), XP_EXP_LATE)))


func _seg1_end() -> int:
	return int(round(XP_BASE * pow(float(XP_SEG1_END), XP_EXP_EARLY)))


func _seg2_end() -> int:
	return int(round(float(_seg1_end()) * pow(float(XP_SEG2_END - 1) / float(XP_SEG1_END), XP_EXP_MID)))


func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	if level >= XP_MAX_LEVEL:
		xp = 0  # capped: excess XP is discarded rather than looping
		return
	xp += amount
	while level < XP_MAX_LEVEL and xp >= xp_to_next() and xp_to_next() > 0:
		xp -= xp_to_next()
		level += 1
		talent_points += 1
		hp = max_hp()
		mp = max_mp()
		AudioManager.play_sfx("level_up")
		EventBus.player_leveled_up.emit(level)
		_grant_milestone(level)
	if level >= XP_MAX_LEVEL:
		xp = 0
	stats_changed.emit()


# --- Milestone rewards (Phase E §6) -----------------------------------------

func milestone_data() -> Array:
	var f := FileAccess.open(MILESTONES_PATH, FileAccess.READ)
	if f == null:
		push_error("GameState: cannot open %s" % MILESTONES_PATH)
		return []
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("GameState: %s is not a JSON object" % MILESTONES_PATH)
		return []
	return (parsed as Dictionary).get("milestones", [])


func milestone_for(lv: int) -> Dictionary:
	for m in milestone_data():
		if int((m as Dictionary).get("level", -1)) == lv:
			return m
	return {}


func milestone_bonus(key: String) -> float:
	## Sum of every claimed milestone's permanent stat effects.
	var total := 0.0
	for m in milestone_data():
		if not milestones_claimed.has(int((m as Dictionary).get("level", -1))):
			continue
		total += float(((m as Dictionary).get("effects", {}) as Dictionary).get(key, 0.0))
	return total


func _grant_milestone(lv: int) -> void:
	if lv % MILESTONE_STEP != 0 or milestones_claimed.has(lv):
		return
	var m := milestone_for(lv)
	if m.is_empty():
		return
	milestones_claimed.append(lv)
	talent_points += int(m.get("talent_points", 0))
	var gold_grant := int(m.get("gold", 0))
	if gold_grant > 0:
		add_gold(gold_grant)
	_clamp_pools()
	EventBus.milestone_reached.emit(lv, String(m.get("title", "")), String(m.get("text", "")))


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
	return base_hp + (level - 1) * 12.0 + bonus + milestone_bonus("hp") + equipment_bonus("hp")


func max_mp() -> float:
	var bonus := 20.0 if node_active("magic", 1) else 0.0  # Arcane Focus
	return base_mp + (level - 1) * 6.0 + bonus + milestone_bonus("mp") + equipment_bonus("mp")


func attack() -> float:
	var bonus := 4.0 if node_active("combat", 1) else 0.0  # Power Strikes
	return base_attack + (level - 1) * 1.5 + bonus + milestone_bonus("atk") + equipment_bonus("atk")


func defense() -> float:
	var bonus := 4.0 if node_active("combat", 2) else 0.0  # Iron Skin
	return base_defense + (level - 1) * 1.0 + bonus + milestone_bonus("def") + equipment_bonus("def")


func move_speed() -> float:
	var bonus := 22.0 if node_active("utility", 1) else 0.0  # Fleet Foot
	return base_speed + bonus + milestone_bonus("speed") + equipment_bonus("speed")


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
		"milestones_claimed": milestones_claimed.duplicate(),
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
	milestones_claimed.clear()
	for m in (d.get("milestones_claimed", []) as Array):
		milestones_claimed.append(int(m))
	inventory = (d.get("inventory", {}) as Dictionary).duplicate()
	equipment = (d.get("equipment", {"weapon": "", "armor": "", "accessory": ""}) as Dictionary).duplicate()
	quests = (d.get("quests", {}) as Dictionary).duplicate()
	quest_progress = (d.get("quest_progress", {}) as Dictionary).duplicate(true)
	quest_flags = (d.get("quest_flags", {}) as Dictionary).duplicate()
	talents = (d.get("talents", {"combat": 0, "magic": 0, "utility": 0}) as Dictionary).duplicate()
	hp = clampf(float(d.get("hp", max_hp())), 0.0, max_hp())
	mp = clampf(float(d.get("mp", max_mp())), 0.0, max_mp())
	stats_changed.emit()
