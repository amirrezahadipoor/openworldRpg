extends Node
## Phase F1/F2/F3 headless test — the item economy, the monster roster, the
## boss ladder, and loot reachability.
## Exits 0 on PASS, 1 on FAIL. Run:
##   godot --headless --path . res://tests/ItemsTest.tscn

var failures := 0
var checks := 0


func check(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("  PASS: ", label)
	else:
		failures += 1
		print("  FAIL: ", label)


func _ready() -> void:
	print("[items_test] starting...")
	# Deterministic loot rolls: a coverage failure must be a real data gap, not a
	# bad night for the RNG.
	seed(1337)
	await get_tree().process_frame
	_test_catalogue_size()
	_test_rarity_ordering()
	_test_lifesteal_rules()
	_test_monster_roster()
	_test_placement()
	_test_boss_ladder()
	_test_drop_reachability()
	await _test_boss_runtime()
	_test_audit_economy()
	_test_starter_shelf()
	_test_upgrade_sink()
	_test_revive_persistence()
	await _test_item_icons()
	_report()


func _test_item_icons() -> void:
	print("[items_test] every item ships a real icon, and loot wears it")
	var missing: Array = []
	var null_tex: Array = []
	for id in ItemsDB.items:
		var sid := String(id)
		if not ItemsDB.has_own_icon(sid):
			missing.append(sid)
		elif ItemsDB.icon(sid) == null:
			null_tex.append(sid)
	check(missing.is_empty(), "every item has a shipped icon png (%d missing: %s)"
		% [missing.size(), str(missing.slice(0, 8))])
	check(null_tex.is_empty(), "every item icon loads as a texture (%d bad: %s)"
		% [null_tex.size(), str(null_tex.slice(0, 8))])
	# The generic fallback art itself must exist.
	check(ResourceLoader.exists(ItemsDB.GENERIC_ICON), "the fallback loot icon exists")
	# A representative item of each type has its own art, and a ground drop asks for it.
	for sid in ["health_potion", "slime_gel", "copper_ring", "cloth_tunic", "iron_sword"]:
		check(ItemsDB.has_own_icon(sid), "%s has its own icon" % sid)
	var scene: PackedScene = load("res://scenes/world/pickup.tscn")
	var pk: Pickup = scene.instantiate()
	add_child(pk)
	pk.setup_item("iron_sword", 1)
	await get_tree().process_frame
	check(pk.art_path() == "res://assets/items/iron_sword.png",
		"an item drop wears that item's icon (%s)" % pk.art_path())
	pk.queue_free()


func _test_audit_economy() -> void:
	print("[items_test] stack caps, chest loot and what gold-find multiplies")

	# G6: every item declares a stack size and the bag has to respect it.
	var potion := "health_potion"
	var cap := ItemsDB.stack_size(potion)
	GameState.inventory.erase(potion)
	GameState.add_item(potion, cap + 25)
	check(GameState.item_count(potion) == cap,
		"a consumable stops at its declared stack (%d)" % GameState.item_count(potion))
	var material := "slime_gel"
	var mcap := ItemsDB.stack_size(material)
	check(mcap > 1, "materials stack, so a gather quest can be filled (stack %d)" % mcap)
	GameState.inventory.erase(material)
	GameState.add_item(material, 5)
	check(GameState.item_count(material) == 5, "five materials fit in one stack")
	GameState.add_item(material, mcap * 2)
	check(GameState.item_count(material) == mcap,
		"and they stop at the cap too (%d)" % GameState.item_count(material))
	GameState.inventory.erase(potion)
	GameState.inventory.erase(material)

	# G7: the gold-find talent multiplies loot, not trade.
	var mult := GameState.gold_mult()
	if mult > 1.0:
		GameState.gold = 0
		GameState.add_gold(100, "trade")
		check(GameState.gold == 100, "selling to a vendor is not boosted by gold find (%d)"
			% GameState.gold)
		GameState.gold = 0
		GameState.add_gold(100, "loot")
		check(GameState.gold > 100, "loot still is (%d)" % GameState.gold)
	else:
		check(true, "no gold-find talent taken: nothing to compare (mult %.2f)" % mult)
	GameState.gold = 0


func _test_starter_shelf() -> void:
	print("[items_test] the first shelf has to be affordable")
	# L5: the starting purse is 50 g and merchant_bram's shelf held a 2965 g sword
	# next to the potions, so the shop read as broken for the first ten levels.
	var purse := 50
	var affordable := 0
	for iid in NPCController.stock_for("merchant_bram"):
		if ItemsDB.get_value(String(iid)) <= purse * 2:
			affordable += 1
	check(affordable >= 3,
		"three of the opening vendor's wares are within reach of 50 g (%d)" % affordable)
	check(not NPCController.stock_for("merchant_bram").has("iron_sword"),
		"the 2965 g sword is no longer the first thing a new hero is offered")


func _test_upgrade_sink() -> void:
	print("[items_test] the smith's bench: gold and materials for a better item")

	# v3 audit §4: past the midpoint gold pooled up with one sink in the game. The
	# bench takes gold AND the region's materials, priced off the item's own value.
	GameState.inventory.clear()
	GameState.upgrades.clear()
	GameState.equipment = {"weapon": "", "armor": "", "accessory": ""}
	GameState.gold = 0

	check(GameState.upgrade_cost("weapon").is_empty(), "a bare slot has nothing to upgrade")
	check(GameState.upgrade_reason("weapon") == "nothing to upgrade", "and says so")

	GameState.add_item("iron_sword", 1)
	check(GameState.equip("iron_sword"), "the sword goes on")
	var cost := GameState.upgrade_cost("weapon")
	check(not cost.is_empty(), "an equipped item can be upgraded")
	check(int(cost["gold"]) > 0 and int(cost["qty"]) >= 1,
		"the price is gold plus materials (%d g + %d x %s)"
			% [int(cost["gold"]), int(cost["qty"]), String(cost["material"])])
	check(GameState.upgrade_reason("weapon").contains("g needed"),
		"broke means the shop says how much gold is missing (%s)"
			% GameState.upgrade_reason("weapon"))

	# Paying without the material must still fail, and cost nothing.
	GameState.gold = int(cost["gold"]) * 4
	var gold_before := GameState.gold
	check(not GameState.upgrade_item("weapon"), "no material, no upgrade")
	check(GameState.gold == gold_before, "and a refused upgrade spends nothing")
	check(GameState.upgrade_reason("weapon").contains("needed"),
		"the reason names the material (%s)" % GameState.upgrade_reason("weapon"))

	# Afford it properly.
	GameState.add_item(String(cost["material"]), int(cost["qty"]))
	var atk_before := GameState.equipment_bonus("atk")
	check(GameState.upgrade_item("weapon"), "gold + material buys one step")
	check(GameState.upgrade_level("weapon") == 1, "the level went up")
	check(GameState.equipment_bonus("atk") > atk_before,
		"and the item actually hits harder (%.0f -> %.0f)"
			% [atk_before, GameState.equipment_bonus("atk")])

	# The price rises with the level: a sink has to keep taking money.
	var step1 := int(GameState.upgrade_cost("weapon")["gold"])
	GameState.gold = 9999999
	GameState.add_item(String(cost["material"]), 60)
	while GameState.upgrade_level("weapon") < GameState.UPGRADE_MAX:
		if not GameState.upgrade_item("weapon"):
			break
	check(GameState.upgrade_level("weapon") == GameState.UPGRADE_MAX,
		"the bench goes to +%d" % GameState.UPGRADE_MAX)
	var maxed_mult := GameState.upgrade_mult("weapon")
	check(maxed_mult > 1.5, "+10 is worth %.2fx the item" % maxed_mult)
	check(GameState.upgrade_cost("weapon").is_empty(), "the cap is a hard stop")
	check(not GameState.upgrade_item("weapon"), "and a maxed item refuses more gold")
	var full := GameState.upgrade_cost("armor")
	check(full.is_empty(), "an empty slot still has no price")

	# The gold went into the item: swapping it out starts over.
	GameState.add_item("short_sword", 1)
	GameState.equip("short_sword")
	check(GameState.upgrade_level("weapon") == 0,
		"a different item in the slot starts at +0 (the gold went into the old one)")

	# Upgrades are part of the save.
	GameState.upgrades["armor"] = 3
	var blob := GameState.to_dict()
	GameState.upgrades.clear()
	GameState.from_dict(blob)
	check(GameState.upgrade_level("armor") == 3, "upgrades survive a save round-trip")

	GameState.inventory.clear()
	GameState.upgrades.clear()
	GameState.equipment = {"weapon": "", "armor": "", "accessory": ""}
	GameState.gold = 0
func _test_revive_persistence() -> void:
	print("[items_test] armed revive survives a save round-trip")
	var was := GameState.revive_armed
	GameState.revive_armed = true
	var snap := GameState.to_dict()
	GameState.revive_armed = false
	GameState.from_dict(snap)
	check(GameState.revive_armed == true, "an armed Phoenix Draught survives save/load")
	# A save written before this field existed must load unarmed, not armed.
	var legacy: Dictionary = snap.duplicate()
	legacy.erase("revive_armed")
	GameState.from_dict(legacy)
	check(GameState.revive_armed == false, "old saves without the field default to unarmed")
	GameState.revive_armed = was


func _report() -> void:
	print("ITEMS RESULT: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(1 if failures > 0 else 0)


func _test_catalogue_size() -> void:
	print("[items_test] catalogue size (>=100 kinds, 5 rarities)")
	var ids := ItemsDB.items.keys()
	check(ids.size() >= 100, "at least 100 item kinds (%d)" % ids.size())

	var by_rarity := {}
	var by_type := {}
	for id in ids:
		var r := ItemsDB.get_rarity(String(id))
		by_rarity[r] = int(by_rarity.get(r, 0)) + 1
		var t := ItemsDB.get_type(String(id))
		by_type[t] = int(by_type.get(t, 0)) + 1
	for r in ItemsDB.RARITY_ORDER:
		check(int(by_rarity.get(r, 0)) > 0, "rarity '%s' has items (%d)" % [r, int(by_rarity.get(r, 0))])
	for t in ["weapon", "armor", "accessory", "consumable", "material"]:
		check(int(by_type.get(t, 0)) > 0, "type '%s' has items (%d)" % [t, int(by_type.get(t, 0))])

	# Every entry must be usable: equippable needs a slot, consumable needs an effect.
	var usable := true
	var named := true
	for id in ids:
		var it: Dictionary = ItemsDB.get_item(String(id))
		if String(it.get("name", "")) == "" or String(it.get("desc", "")) == "":
			named = false
		var t := String(it.get("type", ""))
		if t in ["weapon", "armor", "accessory"] and String(it.get("slot", "")) == "":
			usable = false
		# A consumable is usable when it does something: a heal, a mana restore,
		# a timed buff (haste / ward / focus) or an armed revive.
		var does_something := it.has("heal") or it.has("restore_mp") \
			or it.has("speed_mult") or it.has("shield") or it.has("mp_regen") \
			or bool(it.get("revive", false))
		if t == "consumable" and not does_something:
			usable = false
		if int(it.get("value", 0)) <= 0:
			usable = false
	check(named, "every item has a name and a description")
	check(usable, "every item is usable (slot / effect / value present)")


func _test_rarity_ordering() -> void:
	print("[items_test] rarity is a power ordering")
	# Average weighted power per rarity must rise strictly, over EQUIPMENT.
	var totals := {}
	var counts := {}
	for id in ItemsDB.items:
		var it: Dictionary = ItemsDB.get_item(String(id))
		if not (String(it.get("type", "")) in ["weapon", "armor", "accessory"]):
			continue
		var r := ItemsDB.get_rarity(String(id))
		totals[r] = float(totals.get(r, 0.0)) + ItemsDB.stat_budget_used(String(id))
		counts[r] = int(counts.get(r, 0)) + 1
	var avg := {}
	for r in totals:
		avg[r] = float(totals[r]) / maxf(float(counts[r]), 1.0)
	var order := ItemsDB.RARITY_ORDER
	var monotone := true
	var detail := []
	for i in order.size() - 1:
		detail.append("%s=%.1f" % [order[i], avg.get(order[i], 0.0)])
		if float(avg.get(order[i], 0.0)) >= float(avg.get(order[i + 1], 0.0)):
			monotone = false
	detail.append("%s=%.1f" % [order[-1], avg.get(order[-1], 0.0)])
	check(monotone, "each rarity out-powers the one below it (%s)" % " ".join(detail))

	# And every individual item must respect its tier's budget.
	var over := []
	for id in ItemsDB.items:
		if not ItemsDB.within_budget(String(id)):
			over.append(String(id))
	check(over.is_empty(), "every item fits its rarity's stat budget (over: %s)" % str(over))


func _test_lifesteal_rules() -> void:
	print("[items_test] lifesteal is a rare find, not a starter gift")
	var leech := []
	for id in ItemsDB.items:
		if ItemsDB.has_lifesteal(String(id)):
			leech.append(String(id))
	check(leech.size() >= 5, "several lifesteal items exist (%d)" % leech.size())
	var bad := []
	for id in leech:
		if ItemsDB.rarity_rank(String(id)) < ItemsDB.RARITY_ORDER.find("rare"):
			bad.append(String(id))
	check(bad.is_empty(), "no lifesteal below rare (offenders: %s)" % str(bad))

	# A common/uncommon roll can never produce one.
	var ran_clean := true
	for i in 400:
		var low := EnemyDB.roll_item_of_rarity("common")
		if low != "" and ItemsDB.has_lifesteal(low):
			ran_clean = false
		var mid := EnemyDB.roll_item_of_rarity("uncommon")
		if mid != "" and ItemsDB.has_lifesteal(mid):
			ran_clean = false
	check(ran_clean, "800 common/uncommon rolls produced no lifesteal gear")

	# Equipping a leech item must actually raise the combat hook.
	var before := GameState.lifesteal()
	var previous: String = GameState.equipment.get("weapon", "")
	GameState.add_item(String(leech[0]), 1)
	GameState.equip(String(leech[0]))
	check(GameState.lifesteal() > before, "equipping leech gear raises GameState.lifesteal()")
	if previous != "":
		GameState.equip(previous)


func _test_monster_roster() -> void:
	print("[items_test] monster roster (>=10 kinds, weak -> strong)")
	var monsters := EnemyDB.monsters()
	check(monsters.size() >= 10, "at least 10 monster kinds (%d)" % monsters.size())

	# Tiers must be contiguous 1..N and each tier populated.
	var tiers := {}
	for m in monsters:
		var t := EnemyDB.tier_of(String(m))
		tiers[t] = int(tiers.get(t, 0)) + 1
	check(tiers.size() >= 5, "monsters span 5+ tiers (%s)" % str(tiers))
	var contiguous := true
	for t in range(1, tiers.size() + 1):
		if int(tiers.get(t, 0)) == 0:
			contiguous = false
	check(contiguous, "tiers are contiguous 1..%d with no gaps" % tiers.size())

	# Power must rise with tier: compare average hp per tier.
	var hp := {}
	var n := {}
	for m in monsters:
		var t := EnemyDB.tier_of(String(m))
		hp[t] = float(hp.get(t, 0.0)) + float(EnemyDB.get_archetype(String(m)).get("max_hp", 0.0))
		n[t] = int(n.get(t, 0)) + 1
	var rising := true
	var prev := 0.0
	for t in range(1, tiers.size() + 1):
		var a := float(hp.get(t, 0.0)) / maxf(float(n.get(t, 0)), 1.0)
		if a <= prev:
			rising = false
		prev = a
	check(rising, "average monster HP rises with every tier")

	# Art must exist for each one (no placeholder-only monsters).
	var sheeted := true
	var missing := []
	for m in monsters:
		var sheet := String(EnemyDB.get_archetype(String(m)).get("sheet", ""))
		if sheet == "" or not ResourceLoader.exists(sheet):
			sheeted = false
			missing.append(String(m))
	check(sheeted, "every monster has composed art (missing: %s)" % str(missing))

	# H5.5/H7.2: the pose art pasted into those sheets has to be real art, not an
	# empty column, a copy of frame 0, or a pose spilling into its neighbour.
	# (tools/make_idle_frames.py --check proves the same thing offline.)
	var manifest: Dictionary = PoseArt.all()
	check(not manifest.is_empty(), "pose art manifest lists patched sheets (%d)" % manifest.size())
	var bad_geometry := []
	var copies := []
	var overflow := []
	var idle_sheets := 0
	var attack_sheets := 0
	for stem in manifest:
		var entry: Dictionary = manifest[stem]
		var img := Image.load_from_file("res://assets/lpc/%s.png" % stem)
		if img == null or img.get_width() != 13 * 64 or img.get_height() != 20 * 64:
			bad_geometry.append(String(stem))
			continue
		for anim in entry:
			# Animation block index of each patched kind, spelled out here so the
			# test does not have to trust the tool's own table:
			# 0 idle · 2 slash (melee attack) · 3 spellcast (a ranged attack).
			var block := 0
			if String(anim) == "slash":
				block = 2
			elif String(anim) == "spellcast":
				block = 3
			var frames := int(entry[anim])
			if String(anim) == "idle":
				idle_sheets += 1
			else:
				attack_sheets += 1
			for d in 4:
				for c in range(1, frames):
					if not _cell_has_art(img, block * 4 + d, c):
						bad_geometry.append("%s/%s/%d/%d empty" % [stem, anim, d, c])
					elif _cell_difference(img, block * 4 + d, 0, c) < 4.0:
						copies.append("%s/%s/%d/%d" % [stem, anim, d, c])
				if _cell_has_art(img, block * 4 + d, frames):
					overflow.append("%s/%s/%d" % [stem, anim, d])
	check(idle_sheets > 0, "generated idle frames exist (%d sheets)" % idle_sheets)
	check(bad_geometry.is_empty(), "every generated pose frame has art (%s)" % str(bad_geometry))
	check(copies.is_empty(), "no generated pose is a copy of frame 0 (%s)" % str(copies))
	check(overflow.is_empty(), "generated pose blocks stay inside their frames (%s)" % str(overflow))
	check(idle_sheets == manifest.size(),
		"every patched sheet has idle art (%d/%d)" % [idle_sheets, manifest.size()])

	# "The enemies should have fight animations too." Every archetype that deals
	# physical damage must animate an attack, in all four directions, that is not
	# just its walk cycle — checked on the composed sheet, so a missing weapon
	# layer or a placeholder pose fails here instead of in a player's hands.
	var physical: Array = []
	for id in EnemyDB.monsters() + EnemyDB.bosses():
		var cfg: Dictionary = EnemyDB.get_archetype(String(id))
		var behavior := String(cfg.get("behavior", "melee"))
		if behavior == "ranged":
			continue                      # casters throw, they do not swing
		physical.append(String(id))
	var no_attack := []
	var same_as_walk := []
	var seen_sheets := {}
	for id in physical:
		var sheet := String(EnemyDB.get_archetype(String(id)).get("sheet", ""))
		if seen_sheets.has(sheet):
			continue
		seen_sheets[sheet] = true
		var img := Image.load_from_file(sheet)
		if img == null:
			no_attack.append(String(id))
			continue
		for dir_row in 4:
			if not _block_has_art(img, dir_row, 2):
				no_attack.append("%s/dir%d empty" % [id, dir_row])
			elif _block_difference(img, dir_row, 1, 2) < 4.0:
				same_as_walk.append("%s/dir%d" % [id, dir_row])
	check(no_attack.is_empty(),
		"every physical archetype animates an attack in all 4 directions (%s)" % str(no_attack))
	check(same_as_walk.is_empty(),
		"the attack animation is not just the walk cycle (%s)" % str(same_as_walk))


func _test_placement() -> void:
	print("[items_test] placement: nothing spawns outside its band")
	var bad := []
	for biome in EnemyDB.spawns():
		var entry: Dictionary = EnemyDB.spawns()[biome]
		var band: Array = entry.get("level_band", [1, 100])
		for m in (entry.get("archetypes", []) as Array):
			var mb: Array = EnemyDB.level_band(String(m))
			# The monster's band must overlap the biome's band...
			if int(mb[1]) < int(band[0]) or int(mb[0]) > int(band[1]):
				bad.append("%s in %s (%s vs %s)" % [m, biome, str(mb), str(band)])
			# ...and it must belong to that biome.
			if EnemyDB.biome_of(String(m)) != String(biome):
				bad.append("%s is a %s monster listed in %s" % [m, EnemyDB.biome_of(String(m)), biome])
	check(bad.is_empty(), "every biome table respects bands and biomes (%s)" % str(bad))

	# Dungeon floors must be level-appropriate for the dungeon they sit in, and
	# a floor flagged as a boss gate must hold exactly one named boss.
	var bad2 := []
	var boss_floors := 0
	for id in Dungeon.all():
		var d: Dictionary = (Dungeon.all() as Dictionary)[id]
		var band: Array = d.get("level_band", [1, 100])
		var floors: Array = d.get("floors", [])
		for i in floors.size():
			var fd: Dictionary = floors[i]
			var named := []
			for m in (fd.get("enemies", []) as Array):
				var arch: Dictionary = EnemyDB.get_archetype(String(m))
				if arch.is_empty():
					bad2.append("%s floor %d: '%s' is not in the roster" % [id, i + 1, m])
					continue
				var mb: Array = arch.get("level_band", [1, 100])
				if int(mb[1]) < int(band[0]) or int(mb[0]) > int(band[1]):
					bad2.append("%s floor %d: %s (%s) outside dungeon band %s" %
						[id, i + 1, m, str(mb), str(band)])
				if EnemyDB.is_boss(String(m)):
					named.append(String(m))
			if bool(fd.get("boss", false)):
				boss_floors += 1
				if named.size() != 1:
					bad2.append("%s floor %d is a boss gate holding %s" %
						[id, i + 1, str(named)])
			elif named.size() > 0:
				bad2.append("%s floor %d holds %s without being a boss gate" %
					[id, i + 1, str(named)])
			# Depth must get harder: every non-boss floor must be easier than the
			# next one. Boss gates are exempt - the Ember Warden's arena owns its
			# own scaling, and the named bosses bring their phase tables.
			if not bool(fd.get("boss", false)):
				var next: Dictionary = next_combat_floor(floors, i)
				if not next.is_empty() and float(fd.get("power_scale", 1.0)) \
						>= float(next.get("power_scale", 1.0)):
					bad2.append("%s floor %d is as hard as a deeper floor" % [id, i + 1])
	check(bad2.is_empty(), "dungeon floors are level-appropriate (%s)" % str(bad2))
	check(boss_floors == 6, "six floors gate the six dungeons (%d)" % boss_floors)

	# Every biome must actually be able to spawn something.
	for biome in ["meadow", "barrens", "frost"]:
		check(EnemyDB.spawn_table(biome).size() > 0,
			"biome '%s' has a spawn table (%d)" % [biome, EnemyDB.spawn_table(biome).size()])


func _test_boss_ladder() -> void:
	print("[items_test] six bosses, escalating")
	var bosses := EnemyDB.bosses()
	check(bosses.size() == 6, "exactly six bosses (%d)" % bosses.size())

	# Order by HP and require a real step up each time.
	var ladder := bosses.duplicate()
	ladder.sort_custom(func(a, b) -> bool:
		return float(EnemyDB.get_archetype(a).get("max_hp", 0.0)) \
			< float(EnemyDB.get_archetype(b).get("max_hp", 0.0)))
	var rising := true
	var hp_line := []
	var prev := 0.0
	for b in ladder:
		var h := float(EnemyDB.get_archetype(String(b)).get("max_hp", 0.0))
		hp_line.append("%s=%.0f" % [b, h])
		if h <= prev * 1.25:
			rising = false
		prev = h
	check(rising, "each boss is >=25%% tougher than the last (%s)" % " ".join(hp_line))

	# The Ember Warden stays the strongest AND the final fight.
	check(ladder[-1] == "ember_warden", "the Ember Warden is the strongest boss")
	check(not EmberWardenPhasesTouched(), "the Warden keeps its own phase script")

	# Five data-driven bosses must declare a usable phase table; the Warden
	# deliberately declares none (its phases live in boss.gd).
	var with_phases := 0
	var phased_ok := true
	for b in bosses:
		if String(b) == "ember_warden":
			continue
		var phases: Array = EnemyDB.get_archetype(String(b)).get("phases", [])
		if phases.size() >= 2:
			with_phases += 1
		var last := 0.0
		for p in phases:
			var above := float((p as Dictionary).get("hp_above", 0.0))
			if above >= last and last != 0.0:
				phased_ok = false
			last = above
	check(with_phases == 5, "five bosses declare data-driven phases (%d)" % with_phases)
	check(phased_ok, "phase thresholds descend (they are walked strongest-last)")

	# Every boss must be placed at the end of a dungeon.
	var placed := {}
	for id in Dungeon.all():
		var floors: Array = (Dungeon.all() as Dictionary)[id].get("floors", [])
		for f in floors:
			if bool((f as Dictionary).get("boss", false)):
				for m in ((f as Dictionary).get("enemies", []) as Array):
					if EnemyDB.is_boss(String(m)):
						placed[String(m)] = String(id)
	var unplaced := []
	for b in bosses:
		if not placed.has(String(b)):
			unplaced.append(String(b))
	check(unplaced.is_empty(), "every boss is placed in a dungeon (unplaced: %s)" % str(unplaced))
	check(placed.size() >= 6, "the six bosses sit in %d dungeon(s)" % placed.size())


func EmberWardenPhasesTouched() -> bool:
	## The Warden's phases must NOT be restated in data — boss.gd owns them.
	return not (EnemyDB.get_archetype("ember_warden").get("phases", []) as Array).is_empty()


func _test_boss_runtime() -> void:
	print("[items_test] bosses actually spawn and phase-change in play")
	# A boss floor must produce a live DataBoss, not just a data entry.
	var d := Dungeon.new()
	add_child(d)
	d.setup("drowned_mill", 2)
	var found := _find_boss(d)
	check(found != null, "drowned_mill's boss floor spawns a DataBoss node")
	if found != null:
		check(found.archetype == "goblin_king", "it is the floor's named boss (%s)" % found.archetype)
		check(found.max_hp > 0.0, "it has hp (%.0f)" % found.max_hp)
		# Drive it down through its phase table and watch the phases fire. A phase
		# change grants a short invulnerability window (the transformation), so
		# let physics tick between blows.
		var seen := []
		found.phase_changed.connect(func(n: int) -> void: seen.append(n))
		for i in 3:
			found.take_hit(found.max_hp * 0.30, Vector2.RIGHT)
			for f in 45:
				await get_tree().physics_frame
		check(seen.size() >= 2, "crossing hp thresholds fires phase changes (%s)" % str(seen))
		check(seen == [2, 3], "phases advance in order, once each (%s)" % str(seen))
		check(is_equal_approx(found.hp, found.max_hp * 0.10),
			"damage lands between transformations (hp %.0f of %.0f)" % [found.hp, found.max_hp])
		var tuned := found.move_speed > 0.0 and found.telegraph_time > 0.0
		check(tuned, "later phases retune speed and telegraph (%.0f / %.2f)" %
			[found.move_speed, found.telegraph_time])
	d.queue_free()
	await get_tree().process_frame


func _find_boss(node: Node) -> DataBoss:
	if node is DataBoss:
		return node
	for c in node.get_children():
		var hit := _find_boss(c)
		if hit != null:
			return hit
	return null


func next_combat_floor(floors: Array, from: int) -> Dictionary:
	## The next floor that is not a boss gate (gates bring their own scaling).
	for i in range(from + 1, floors.size()):
		if not bool((floors[i] as Dictionary).get("boss", false)):
			return floors[i]
	return {}


func _test_drop_reachability() -> void:
	print("[items_test] every item is obtainable from loot")
	# Roll each monster's table many times and collect what actually drops.
	var obtainable := {}
	var gear_by_tier := {}
	for m in EnemyDB.archetypes:
		var arch := String(m)
		var tier := EnemyDB.tier_of(arch)
		for i in 400:
			var d := EnemyDB.roll_drops(arch)
			for it in (d.get("items", []) as Array):
				obtainable[String(it)] = true
				if not gear_by_tier.has(tier):
					gear_by_tier[tier] = {}
				var g: Dictionary = gear_by_tier[tier]
				g[String(it)] = true

	var missing := []
	for id in ItemsDB.items:
		if not obtainable.has(String(id)):
			missing.append(String(id))
	# Materials that only exist as quest turn-ins are allowed to be unreachable
	# by loot, but nothing else is.
	var truly_missing := []
	for id in missing:
		if ItemsDB.get_type(String(id)) != "material":
			truly_missing.append(String(id))
	check(truly_missing.is_empty(),
		"every non-material item drops from at least one monster (%d rolled, missing: %s)" %
		[obtainable.size(), str(truly_missing)])

	# Higher tiers must actually drop better gear.
	var top: Dictionary = gear_by_tier.get(6, {})
	var low: Dictionary = gear_by_tier.get(1, {})
	var top_best := 0
	for id in top:
		top_best = maxi(top_best, ItemsDB.rarity_rank(String(id)))
	var low_best := 0
	for id in low:
		low_best = maxi(low_best, ItemsDB.rarity_rank(String(id)))
	check(top_best >= low_best, "top-tier monsters drop the best gear (%d vs %d)" %
		[top_best, low_best])
	check(top_best >= ItemsDB.RARITY_ORDER.find("rare"),
		"tier-6 monsters can drop rare-or-better gear")


func _cell_has_art(img: Image, dir_row: int, col: int) -> bool:
	## A 64 px idle cell is "not empty" when a sample of it is more than opaque
	## enough to be a character rather than the keyed-out background.
	var solid := 0
	for y in range(0, 64, 2):
		for x in range(0, 64, 2):
			if img.get_pixel(col * 64 + x, dir_row * 64 + y).a > 0.45:
				solid += 1
	return solid > 12


func _cell_difference(img: Image, dir_row: int, a_col: int, b_col: int) -> float:
	## Mean per-channel difference between two idle cells, sampled every other
	## pixel. A pasted frame that is really frame 0 again scores near zero.
	var total := 0.0
	var n := 0
	for y in range(0, 64, 2):
		for x in range(0, 64, 2):
			var a := img.get_pixel(a_col * 64 + x, dir_row * 64 + y)
			var b := img.get_pixel(b_col * 64 + x, dir_row * 64 + y)
			if a.a <= 0.45 and b.a <= 0.45:
				continue
			total += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) + absf(a.a - b.a)
			n += 1
	if n == 0:
		return 0.0
	return (total / float(n)) * 255.0 / 4.0


func _block_has_art(img: Image, dir_row: int, block: int) -> bool:
	## Any of the 13 frames of one animation block, in one direction, has art?
	var solid := 0
	for c in 13:
		for y in range(0, 64, 4):
			for x in range(0, 64, 4):
				if img.get_pixel(c * 64 + x, (block * 4 + dir_row) * 64 + y).a > 0.45:
					solid += 1
					if solid > 40:
						return true
	return false


func _block_difference(img: Image, dir_row: int, a_block: int, b_block: int) -> float:
	## Mean per-channel difference between two animation blocks of one direction.
	var total := 0.0
	var n := 0
	for c in 6:
		for y in range(0, 64, 2):
			for x in range(0, 64, 2):
				var a := img.get_pixel(c * 64 + x, (a_block * 4 + dir_row) * 64 + y)
				var b := img.get_pixel(c * 64 + x, (b_block * 4 + dir_row) * 64 + y)
				if a.a <= 0.45 and b.a <= 0.45:
					continue
				total += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) + absf(a.a - b.a)
				n += 1
	if n == 0:
		return 0.0
	return (total / float(n)) * 255.0 / 4.0
