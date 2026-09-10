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
const TALENTS_PATH: String = "res://data/talents.json"

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
## What the character has actually received, in order — kind -> text. Quests,
## purchases, sales and level-ups all write here. The audit's point was that a
## player could not answer "what did that job pay me?"; this is the answer, and
## the quest log renders it.
var ledger: Array = []
## The last lines spoken to this character, so a conversation can be re-read
## instead of being a one-shot that vanishes. speaker -> text.
var dialogue_history: Array = []
const LEDGER_MAX := 120
const HISTORY_MAX := 60
# branch -> allocated points
var talents: Dictionary = {"combat": 0, "magic": 0, "utility": 0}
# Temporary effects from consumables. Not serialized: a buff is a moment, not
# progress. kind -> {"kind", "value", "time_left"} where kind is speed/shield/regen.
var buffs: Dictionary = {}
# A Phoenix Draught in the pack buys exactly one fall (consumed on trigger).
var revive_armed: bool = false

signal buffs_changed


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
	buffs = {}
	revive_armed = false
	stats_changed.emit()


func _process(delta: float) -> void:
	_tick_buffs(delta)
	# Clarity talent: passive MP regeneration.
	if mp < max_mp() and mp_regen_per_sec() > 0.0:
		mp = minf(mp + mp_regen_per_sec() * delta, max_mp())


func _tick_buffs(delta: float) -> void:
	if buffs.is_empty():
		return
	var expired: Array = []
	for key in buffs.keys():
		var b: Dictionary = buffs[key]
		b["time_left"] = float(b.get("time_left", 0.0)) - delta
		if float(b["time_left"]) <= 0.0:
			expired.append(key)
		else:
			buffs[key] = b
	for key in expired:
		buffs.erase(key)
	if not expired.is_empty():
		buffs_changed.emit()


func apply_buff(kind: String, value: float, duration: float) -> void:
	## Timed consumable effect. Re-using the same kind refreshes it.
	if duration <= 0.0:
		return
	buffs[kind] = {"kind": kind, "value": value, "time_left": duration}
	buffs_changed.emit()


func buff_value(kind: String) -> float:
	var b: Dictionary = buffs.get(kind, {})
	if b.is_empty():
		return 1.0 if kind in ["speed", "shield"] else 0.0
	return float(b.get("value", 1.0))


func buff_time_left(kind: String) -> float:
	var b: Dictionary = buffs.get(kind, {})
	return float(b.get("time_left", 0.0)) if not b.is_empty() else 0.0


func active_buff_text() -> String:
	## Compact HUD line, e.g. "Haste 6s · Ironskin 3s". Empty when nothing runs.
	var parts: Array = []
	for key in ["speed", "shield", "regen"]:
		var b: Dictionary = buffs.get(key, {})
		if b.is_empty():
			continue
		parts.append("%s %ds" % [String(b.get("label", key)), int(ceil(float(b.get("time_left", 0.0))))])
	return " · ".join(parts)


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
	amount = int(round(float(amount) * xp_mult()))  # Trailwise / Survivor / Veteran
	xp += amount
	while level < XP_MAX_LEVEL and xp >= xp_to_next() and xp_to_next() > 0:
		xp -= xp_to_next()
		level += 1
		talent_points += 1
		hp = max_hp()
		mp = max_mp()
		AudioManager.play_sfx("level_up")
		ledger_add("level", "Level %d reached (+1 talent point)" % level)
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


func respec_talents() -> int:
	## Refund every allocated talent point. There was no way back from a bad
	## build: 60 points spent blind on a phone, with the only remedy a new game.
	## Free (no gold cost) because respeccing is a UI affordance for an
	## irreversible blind decision, not a gold sink. Returns points refunded.
	var refunded := 0
	for branch in talents.keys():
		refunded += int(talents[branch])
		talents[branch] = 0
	if refunded > 0:
		talent_points += refunded
		_clamp_pools()
		stats_changed.emit()
	return refunded


func talent_effect_text(branch: String) -> String:
	## The numeric line the talent screen shows for one branch, e.g.
	## "ATK +25 · DEF +23 · HP +223". Empty when nothing is allocated.
	var totals: Dictionary = {}
	for node in talents_for_branch(branch):
		for k in ((node.get("effects", {}) as Dictionary).keys() as Array):
			totals[k] = float(totals.get(k, 0.0)) + float(node["effects"][k])
	var parts: Array = []
	for k in totals.keys():
		var v := float(totals[k])
		if k in ["atk", "def", "hp", "mp", "speed"]:
			parts.append("%s +%d" % [k.to_upper(), int(round(v))])
		elif k in ["atk_cd", "dmg_taken", "mp_cost", "potion", "whirl", "bolt"]:
			parts.append("%s %d%%" % [k, int(round((v - 1.0) * 100.0))])
		else:
			parts.append("%s +%.2f" % [k, v])
	return " · ".join(parts)


func spend_talent(branch: String) -> bool:
	if talent_points <= 0 or not talents.has(branch):
		return false
	if int(talents[branch]) >= MAX_BRANCH_POINTS:
		return false  # every node in this branch is already mastered
	talent_points -= 1
	talents[branch] = int(talents[branch]) + 1
	_clamp_pools()
	stats_changed.emit()
	return true


# --- Final stats (level + talents + milestones; gear is added in Phase 7) ----

func max_hp() -> float:
	return base_hp + (level - 1) * 12.0 + talent_sum("hp") \
		+ milestone_bonus("hp") + equipment_bonus("hp")


func max_mp() -> float:
	return base_mp + (level - 1) * 6.0 + talent_sum("mp") \
		+ milestone_bonus("mp") + equipment_bonus("mp")


func attack() -> float:
	return base_attack + (level - 1) * 1.5 + talent_sum("atk") \
		+ milestone_bonus("atk") + equipment_bonus("atk")


func defense() -> float:
	return base_defense + (level - 1) * 1.0 + talent_sum("def") \
		+ milestone_bonus("def") + equipment_bonus("def")


func move_speed() -> float:
	var base: float = base_speed + talent_sum("speed") + milestone_bonus("speed") \
		+ equipment_bonus("speed")
	return base * buff_value("speed")            # Elixir of Haste


# --- Talent tree (Phase E §7: 60 data-driven nodes, DECISIONS #19/#33) --------
#
# A branch is still a single invested-points counter (`talents[branch]`), which
# keeps the three-column UI and the existing saves working. Each node in
# data/talents.json declares `req_points` (points invested in that branch to
# unlock it) and `req_level` (character level gate: tiers open at 5/25/50/75,
# except the three originally shipped starter nodes, which stay at level 1).
# `effects` are summed for additive keys and multiplied for multiplier keys.

const TALENT_POINTS_PER_NODE: int = 1
const MAX_BRANCH_POINTS: int = 20  # one per node in a branch

var _talent_cache: Array = []


func _talent_branches() -> Array:
	if _talent_cache.is_empty():
		var f := FileAccess.open(TALENTS_PATH, FileAccess.READ)
		if f == null:
			push_error("GameState: cannot open %s" % TALENTS_PATH)
			return []
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("GameState: %s is not a JSON object" % TALENTS_PATH)
			return []
		_talent_cache = (parsed as Dictionary).get("branches", [])
	return _talent_cache


func talents_for_branch(branch: String) -> Array:
	for b in _talent_branches():
		if String((b as Dictionary).get("id", "")) == branch:
			return (b as Dictionary).get("nodes", [])
	return []


func node_unlocked(branch: String, node: Dictionary) -> bool:
	## Point cost *and* level gate — the node is live only when both hold.
	if int(talents.get(branch, 0)) < int(node.get("req_points", 1)):
		return false
	return level >= int(node.get("req_level", 1))


func node_locked_reason(branch: String, node: Dictionary) -> String:
	## "" when unlocked, else why not (used by the talent screen).
	if int(talents.get(branch, 0)) < int(node.get("req_points", 1)):
		return "%d pts in %s" % [int(node.get("req_points", 1)), branch]
	if level < int(node.get("req_level", 1)):
		return "Level %d" % int(node.get("req_level", 1))
	return ""


func talent_sum(key: String) -> float:
	## Additive talent effects (atk, def, hp, mp, speed, mp_regen, dodge, lifesteal).
	var total := 0.0
	for b in _talent_branches():
		var bid := String((b as Dictionary).get("id", ""))
		for n in ((b as Dictionary).get("nodes", []) as Array):
			var node := n as Dictionary
			if node_unlocked(bid, node):
				total += float((node.get("effects", {}) as Dictionary).get(key, 0.0))
	return total


func talent_mult(key: String) -> float:
	## Multiplier talent effects, applied as a product so they stack sanely.
	## Floored so that "less of a bad thing" talents can never reach zero.
	var m := 1.0
	for b in _talent_branches():
		var bid := String((b as Dictionary).get("id", ""))
		for n in ((b as Dictionary).get("nodes", []) as Array):
			var node := n as Dictionary
			if node_unlocked(bid, node):
				m *= float((node.get("effects", {}) as Dictionary).get(key, 1.0))
	return maxf(m, 0.4)


func node_active(branch: String, tier: int) -> bool:
	## Legacy helper: "at least this many points invested in the branch".
	## Kept because the original talent effects and the UI were built on it.
	return int(talents.get(branch, 0)) >= tier


func attack_cooldown_mult() -> float:
	return talent_mult("atk_cd")                            # Swift Strikes, Momentum, ...


func potion_mult() -> float:
	return talent_mult("potion")                            # Potent Brews, Alchemist, ...


func gold_mult() -> float:
	return talent_mult("gold")                              # Fortune, Gilded Hand, ...


func mp_regen_per_sec() -> float:
	var b: Dictionary = buffs.get("regen", {})
	var burst := float(b.get("value", 0.0)) if not b.is_empty() else 0.0
	return talent_sum("mp_regen") + burst                   # Clarity, Focused Mind, Focus Draught


func dodge_duration_bonus() -> float:
	return talent_sum("dodge")                              # Shadow Step, Ghost Walk, ...


func whirl_mult() -> float:
	return talent_mult("whirl")                             # Blade Storm, Emberstorm, ...


func bolt_mult() -> float:
	return talent_mult("bolt")                              # Kindled Bolt, Vessel's Spark


func mp_cost_mult() -> float:
	return talent_mult("mp_cost")                           # Efficient Casting


func damage_taken_mult() -> float:
	## Talent multiplier for damage taken, reduced further by a Ward/Ironskin
	## buff (see shield_fraction()).
	return talent_mult("dmg_taken") * (1.0 - shield_fraction())


func shield_fraction() -> float:
	## Fraction of incoming damage removed by a Ward/Ironskin buff (0 = none).
	var b: Dictionary = buffs.get("shield", {})
	if b.is_empty():
		return 0.0
	return clampf(float(b.get("value", 0.0)), 0.0, 0.75)


func lifesteal() -> float:
	## Talent lifesteal (Bloodletter / Sanguine Edge) plus any gear affix.
	## The bible's rule: lifesteal exists only as a rare-or-better find.
	return clampf(talent_sum("lifesteal") + equipment_bonus("lifesteal"), 0.0, 0.5)


func crit_chance() -> float:
	## Equipment + talent crit, capped so it can never become a guarantee.
	return clampf(equipment_bonus("crit") + talent_sum("crit"), 0.0, 0.60)


func xp_mult() -> float:
	return talent_mult("xp")                                # Trailwise, Survivor, Veteran


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
	# Timed / triggered effects (see tools/gen_items.py `_consumable_buff`).
	var dur := float(it.get("duration", 0.0))
	if it.has("speed_mult"):
		apply_buff("speed", float(it["speed_mult"]), dur)
		_label_buff("speed", "Haste")
	if it.has("shield"):
		apply_buff("shield", float(it["shield"]), dur)
		_label_buff("shield", "Ironskin")
	if it.has("mp_regen"):
		apply_buff("regen", float(it["mp_regen"]), dur)
		_label_buff("regen", "Focus")
	if bool(it.get("revive", false)):
		revive_armed = true
	remove_item(item_id, 1)
	EventBus.item_used.emit(item_id)
	AudioManager.play_sfx("item_use")
	return true


func _label_buff(kind: String, label: String) -> void:
	var b: Dictionary = buffs.get(kind, {})
	if not b.is_empty():
		b["label"] = label
		buffs[kind] = b


func consume_revive() -> bool:
	## Called by the player when a hit would be lethal. Returns true if the
	## draught burned instead of the player (one use, then it is gone).
	if not revive_armed:
		return false
	revive_armed = false
	return true


func reset_buffs() -> void:
	buffs.clear()
	revive_armed = false
	buffs_changed.emit()


# --- Inventory ---------------------------------------------------------------

func ledger_add(kind: String, text: String) -> void:
	ledger.append({"kind": kind, "text": text, "level": level})
	while ledger.size() > LEDGER_MAX:
		ledger.pop_front()
	EventBus.ledger_changed.emit()


func ledger_entries(kind: String = "") -> Array:
	if kind == "":
		return ledger.duplicate()
	var out: Array = []
	for e in ledger:
		if String((e as Dictionary).get("kind", "")) == kind:
			out.append(e)
	return out


func record_line(speaker: String, text: String) -> void:
	dialogue_history.append({"speaker": speaker, "text": text})
	while dialogue_history.size() > HISTORY_MAX:
		dialogue_history.pop_front()
	EventBus.ledger_changed.emit()


func add_item(item_id: String, qty: int = 1) -> void:
	inventory[item_id] = int(inventory.get(item_id, 0)) + qty
	if int(inventory[item_id]) <= 0:
		inventory.erase(item_id)


func item_count(item_id: String) -> int:
	## How many of an item the player is carrying (Phase E §5 collect quests).
	return int(inventory.get(item_id, 0))


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
		"ledger": ledger.duplicate(true),
		"dialogue_history": dialogue_history.duplicate(true),
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
	ledger = (d.get("ledger", []) as Array).duplicate(true)
	dialogue_history = (d.get("dialogue_history", []) as Array).duplicate(true)
	hp = clampf(float(d.get("hp", max_hp())), 0.0, max_hp())
	mp = clampf(float(d.get("mp", max_mp())), 0.0, max_mp())
	stats_changed.emit()
