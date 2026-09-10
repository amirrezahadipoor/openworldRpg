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
	_report()


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
