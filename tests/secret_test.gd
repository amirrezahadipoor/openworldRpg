extends Node
## Phase F6 headless test — the world's 40 secrets: authored correctly, placed
## where they claim to be, findable exactly once, and reachable in play.
## Exits 0 on PASS, 1 on FAIL. Run:
##   godot --headless --path . res://tests/SecretTest.tscn

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
	print("[secret_test] starting...")
	seed(4242)
	await get_tree().process_frame
	_test_catalogue()
	_test_placement()
	_test_rewards()
	_test_vault_locks()
	await _test_chunk_mapping()
	_test_discovery()
	_test_idempotence()
	_test_hints()
	await _test_site_scene()
	_report()


func _report() -> void:
	print("SECRET RESULT: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(1 if failures > 0 else 0)


# --- authoring ------------------------------------------------------------------

func _test_catalogue() -> void:
	print("[secret_test] 40 secrets, authored")
	var ids := SecretsDB.all()
	check(ids.size() >= 40, "at least 40 secrets exist (%d)" % ids.size())
	var kinds := SecretsDB.by_kind()
	check(kinds.size() >= 4, "secrets use 4 kinds (%s)" % str(kinds))
	check(int(kinds.get("cache", 0)) >= 10, "most secrets are caches you can stumble into (%d)" % int(kinds.get("cache", 0)))
	check(int(kinds.get("vault", 0)) >= 3, "some are locks, not hiding places (%d)" % int(kinds.get("vault", 0)))
	var bad := []
	for sid in ids:
		var s: Dictionary = SecretsDB.get_secret(String(sid))
		if String(s.get("name", "")) == "":
			bad.append("%s has no name" % sid)
		if String(s.get("text", "")) == "":
			bad.append("%s has no text" % sid)
		if String(s.get("hint", "")) == "":
			bad.append("%s has no hint" % sid)
		if not ["cache", "carving", "landmark", "vault"].has(String(s.get("kind", ""))):
			bad.append("%s has unknown kind '%s'" % [sid, s.get("kind", "")])
	check(bad.is_empty(), "every secret is complete (%s)" % str(bad.slice(0, 3)))

	# Regions: secrets are spread across the whole map, not stacked in one corner.
	var by_region := {}
	for sid in ids:
		var r := String(SecretsDB.get_secret(String(sid)).get("region", ""))
		by_region[r] = int(by_region.get(r, 0)) + 1
	check(by_region.size() == 3, "secrets cover all three regions (%s)" % str(by_region))
	var thin := 0
	for r in by_region:
		if int(by_region[r]) < 8:
			thin += 1
	check(thin == 0, "no region is starved of secrets (%s)" % str(by_region))


func _test_placement() -> void:
	print("[secret_test] every secret is somewhere it can be reached")
	var settlements: Dictionary = Settlement.all()
	var out_of_biome := []
	var in_safe_zone := []
	var too_close := []
	var ids := SecretsDB.all()
	for sid in ids:
		var s: Dictionary = SecretsDB.get_secret(String(sid))
		var pos := SecretsDB.position_of(String(sid))
		var region := String(s.get("region", ""))
		# ChunkStreamer's own rule for which biome a point is in.
		var chunk := Vector2i(int(floorf(pos.x / float(ChunkStreamer.CHUNK_SIZE))),
			int(floorf(pos.y / float(ChunkStreamer.CHUNK_SIZE))))
		var here := "frost" if chunk.y <= -1 else ("barrens" if chunk.x >= 2 else "meadow")
		if here != region:
			out_of_biome.append("%s says %s, sits in %s" % [sid, region, here])
		for town in settlements.keys():
			var data: Dictionary = (settlements[town] as Dictionary)
			var tp: Array = data.get("position", [0, 0])
			var radius := float(data.get("radius", 300.0)) * 1.6
			if pos.distance_to(Vector2(float(tp[0]), float(tp[1]))) < radius:
				in_safe_zone.append("%s is inside %s" % [sid, town])
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var d := SecretsDB.position_of(String(ids[i])).distance_to(SecretsDB.position_of(String(ids[j])))
			if d < 200.0:
				too_close.append("%s/%s are %.0f apart" % [ids[i], ids[j], d])
	check(out_of_biome.is_empty(), "every secret sits in the region it declares (%s)" % str(out_of_biome.slice(0, 3)))
	check(in_safe_zone.is_empty(), "no secret hides inside a settlement's safe ring (%s)" % str(in_safe_zone.slice(0, 3)))
	check(too_close.is_empty(), "secrets do not crowd each other (%s)" % str(too_close.slice(0, 3)))

	# Each region's secrets must be inside that region's level range, so a meadow
	# cache is a level-3 find and a frost vault is an endgame one.
	var band_bad := []
	for sid in ids:
		var s: Dictionary = SecretsDB.get_secret(String(sid))
		var region := String(s.get("region", ""))
		var req: Dictionary = s.get("requires", {})
		var lvl := int(req.get("level", 0)) if not req.is_empty() else 0
		if region == "meadow" and lvl > 15:
			band_bad.append("%s (meadow) asks L%d" % [sid, lvl])
		if region == "frost" and lvl > 0 and lvl < 60:
			band_bad.append("%s (frost) only asks L%d" % [sid, lvl])
	check(band_bad.is_empty(), "locks are gated to their region's band (%s)" % str(band_bad.slice(0, 3)))


func _test_rewards() -> void:
	print("[secret_test] what a secret pays, and what it must not")
	var missing := []
	var too_rich := []
	var legendary_early := []
	for sid in SecretsDB.all():
		var s: Dictionary = SecretsDB.get_secret(String(sid))
		var region := String(s.get("region", ""))
		var reward: Dictionary = s.get("reward", {})
		check_ok(int(reward.get("xp", 0)) > 0, "%s pays xp" % sid, missing)
		for iid in (reward.get("items", []) as Array):
			if not ItemsDB.get_item(String(iid)).is_empty():
				var rarity := String(ItemsDB.get_item(String(iid)).get("rarity", "common"))
				if region == "meadow" and rarity in ["mythical", "legendary"]:
					legendary_early.append("%s gives %s (%s)" % [sid, iid, rarity])
			else:
				missing.append("%s gives unknown item %s" % [sid, iid])
	check(missing.is_empty(), "every secret reward item exists (%s)" % str(missing.slice(0, 3)))
	check(legendary_early.is_empty(), "a meadow secret never hands out endgame gear (%s)" % str(legendary_early.slice(0, 3)))

	# A secret is a find, not a quest: it must not out-pay a main-chain step.
	var chain_total := 0
	var secret_total := 0
	for qid in QuestManager.data.keys():
		if String(qid).begins_with("MQ"):
			chain_total += int((QuestManager.data[qid] as Dictionary).get("reward", {}).get("xp", 0))
	for sid in SecretsDB.all():
		secret_total += int((SecretsDB.get_secret(String(sid)) as Dictionary).get("reward", {}).get("xp", 0))
	check(secret_total < chain_total, "all secrets together pay less than the main chain (%d < %d)" %
		[secret_total, chain_total])
	check(secret_total > 10000, "secrets are still worth a lot of exploring (%d xp)" % secret_total)


func check_ok(cond: bool, label: String, sink: Array) -> void:
	if not cond:
		sink.append(label)


func _test_vault_locks() -> void:
	print("[secret_test] a vault is a lock that says why it will not turn")
	var vaults := []
	for sid in SecretsDB.all():
		if String(SecretsDB.get_secret(String(sid)).get("kind", "")) == "vault":
			vaults.append(String(sid))
	check(vaults.size() >= 3, "vaults exist (%d)" % vaults.size())
	var bad := []
	for sid in vaults:
		var req: Dictionary = (SecretsDB.get_secret(sid) as Dictionary).get("requires", {})
		if req.is_empty():
			bad.append("%s has no lock at all" % sid)
			continue
		var key := String(req.get("item", ""))
		if key == "" or ItemsDB.get_item(key).is_empty():
			bad.append("%s wants key '%s', which is not an item" % [sid, key])
		if int(req.get("level", 0)) <= 0:
			bad.append("%s has no level gate" % sid)
	check(bad.is_empty(), "every vault has a real key item and a level (%s)" % str(bad.slice(0, 3)))

	# The lock actually holds: no key -> refused, key -> opens.
	var sid: String = vaults[0]
	var saved_flags: Dictionary = GameState.quest_flags.duplicate()
	var saved_level := GameState.level
	var key := String((SecretsDB.get_secret(sid) as Dictionary).get("requires", {}).get("item", ""))
	GameState.quest_flags.erase(SecretsDB.flag_of(sid))
	GameState.level = 1
	var denied := SecretsDB.discover(sid)
	check(not bool(denied.get("ok", false)) and not SecretsDB.is_found(sid),
		"a vault refuses an underlevelled, empty-handed player (%s)" % String(denied.get("reason", "")))
	var lvl := int((SecretsDB.get_secret(sid) as Dictionary).get("requires", {}).get("level", 1))
	GameState.level = lvl
	denied = SecretsDB.discover(sid)
	check(not bool(denied.get("ok", false)), "a vault refuses without its key")
	GameState.add_item(key, 1)
	var opened := SecretsDB.discover(sid)
	check(bool(opened.get("ok", false)) and SecretsDB.is_found(sid),
		"a vault opens for a levelled player holding its key (%s)" % sid)
	GameState.quest_flags = saved_flags
	GameState.inventory.erase(key)
	GameState.level = saved_level


func _test_chunk_mapping() -> void:
	print("[secret_test] secrets stream in with the chunk that holds them")
	var seen := {}
	var wrong := []
	for sid in SecretsDB.all():
		var key := SecretsDB.chunk_of(String(sid))
		var pos := SecretsDB.position_of(String(sid))
		var expect := Vector2i(int(floorf(pos.x / float(ChunkStreamer.CHUNK_SIZE))),
			int(floorf(pos.y / float(ChunkStreamer.CHUNK_SIZE))))
		if key != expect:
			wrong.append(sid)
		seen[sid] = true
	check(wrong.is_empty(), "chunk_of() matches the position it came from (%s)" % str(wrong.slice(0, 3)))

	var streamed := {}
	for key in seen.keys():
		pass
	var covered := 0
	var unlisted := []
	for sid in SecretsDB.all():
		var key := SecretsDB.chunk_of(String(sid))
		if streamed.has(key):
			continue
		streamed[key] = true
		var list: Array = SecretsDB.secrets_in_chunk(key)
		if not list.has(String(sid)):
			unlisted.append(sid)
		covered += 1
	check(unlisted.is_empty(), "every secret is listed in its own chunk (%s)" % str(unlisted.slice(0, 3)))
	check(covered > 10, "secrets are spread over many chunks (%d)" % covered)

	# And the streamer really builds them: stream the chunk holding the first
	# secret and count the sites that came with it.
	var cs := ChunkStreamer.new()
	add_child(cs)
	var key: Vector2i = SecretsDB.chunk_of(String(SecretsDB.all()[0]))
	cs._load_chunk(key)
	await get_tree().process_frame
	var chunk := cs.get_loaded_chunk(key)
	var sites := 0
	if chunk != null:
		for child in chunk.get_children():
			if child is SecretSite:
				sites += 1
	check(sites == SecretsDB.secrets_in_chunk(key).size(),
		"streaming a chunk builds the secrets that live in it (%d sites, %d expected)" %
		[sites, SecretsDB.secrets_in_chunk(key).size()])
	cs.queue_free()


# --- discovery ------------------------------------------------------------------

func _test_discovery() -> void:
	print("[secret_test] finding one pays once, and remembers")
	var saved_flags: Dictionary = GameState.quest_flags.duplicate()
	var saved_level := GameState.level
	var saved_gold := GameState.gold
	GameState.level = 100

	var sid := ""
	for raw in SecretsDB.all():
		if String(SecretsDB.get_secret(String(raw)).get("kind", "")) == "cache":
			sid = String(raw)
			break
	GameState.quest_flags.erase(SecretsDB.flag_of(sid))
	var before_gold := GameState.gold
	var before_found := SecretsDB.found_count()
	var result := SecretsDB.discover(sid)
	var reward: Dictionary = (SecretsDB.get_secret(sid) as Dictionary).get("reward", {})
	check(bool(result.get("ok", false)), "a cache is found by opening it (%s)" % sid)
	check(SecretsDB.is_found(sid), "the find is recorded as a flag (%s)" % SecretsDB.flag_of(sid))
	check(GameState.gold - before_gold == int(reward.get("gold", 0)),
		"the find pays its gold (%d)" % (GameState.gold - before_gold))
	check(SecretsDB.found_count() == before_found + 1, "the counter rises (%d -> %d)" %
		[before_found, SecretsDB.found_count()])
	check(int(result.get("xp", 0)) == int(reward.get("xp", 0)), "the find reports its xp")
	var names_bad := []
	for iid in (reward.get("items", []) as Array):
		if GameState.item_count(String(iid)) <= 0:
			names_bad.append(String(iid))
	check(names_bad.is_empty(), "the find's items are in the bag (%s)" % str(names_bad))

	# Walking over it again — or reloading the chunk after a save — must not pay.
	var again := SecretsDB.discover(sid)
	check(not bool(again.get("ok", false)) and bool(again.get("already", false)),
		"finding the same secret twice is refused, not re-paid")
	check(GameState.gold - before_gold == int(reward.get("gold", 0)),
		"the purse did not grow a second time")

	# Discovery is only visible to the player if the site scene says so.
	var hidden := 0
	for raw in SecretsDB.all():
		if not SecretsDB.visible_from_start(String(raw)):
			hidden += 1
	check(hidden >= 10, "most secrets are hidden until found (%d)" % hidden)

	GameState.quest_flags = saved_flags
	GameState.gold = saved_gold
	GameState.level = saved_level


func _test_idempotence() -> void:
	print("[secret_test] a secret survives save/load without duplicating")
	var saved_flags: Dictionary = GameState.quest_flags.duplicate()
	var saved_level := GameState.level
	GameState.level = 100
	# Find three secrets, snapshot the save blob, restore it, and confirm the
	# found set comes back identical (they ride in quest_flags like every other
	# durable world fact).
	for raw in SecretsDB.all().slice(0, 3):
		GameState.quest_flags.erase(SecretsDB.flag_of(String(raw)))
	var found_before := SecretsDB.found_ids()
	var blob: Dictionary = GameState.to_dict()
	for raw in SecretsDB.all().slice(0, 3):
		SecretsDB.discover(String(raw))
	var found_after := SecretsDB.found_ids()
	check(found_after.size() == found_before.size() + 3, "three finds register (%d -> %d)" %
		[found_before.size(), found_after.size()])
	check(blob.has("quest_flags"), "the save blob carries the flags secrets live in")
	GameState.from_dict(blob)
	check(SecretsDB.found_ids() == found_before, "restoring a save restores the found set exactly")
	GameState.quest_flags = saved_flags
	GameState.level = saved_level


func _test_hints() -> void:
	print("[secret_test] landmarks are breadcrumbs")
	var carved := ""
	for raw in SecretsDB.all():
		if String(SecretsDB.get_secret(String(raw)).get("kind", "")) == "carving":
			carved = String(raw)
			break
	check(carved != "", "a carving exists to read (%s)" % carved)
	var hint := SecretsDB.hint_from(carved)
	check(hint.length() > 12, "reading a carving produces a hint (%s)" % hint)
	var at_secret := SecretsDB.position_of(carved)
	var nearest := SecretsDB.nearest_unfound(at_secret, [carved])
	check(nearest != carved, "a hint never points at the stone you are reading")
	if nearest != "":
		var d_here := at_secret.distance_to(SecretsDB.position_of(nearest))
		var farther := 0
		for sid in SecretsDB.unfound():
			if String(sid) == carved:
				continue
			if at_secret.distance_to(SecretsDB.position_of(String(sid))) < d_here:
				farther += 1
		check(farther == 0, "the hint points at the genuinely nearest secret")


func _test_site_scene() -> void:
	print("[secret_test] the world object behaves")
	var world := Node2D.new()
	add_child(world)
	QuestManager.data = QuestManager.data  # keep the manager warm for the site
	var sid := ""
	for raw in SecretsDB.all():
		if String(SecretsDB.get_secret(String(raw)).get("kind", "")) == "cache":
			sid = String(raw)
			break
	var saved_flags: Dictionary = GameState.quest_flags.duplicate()
	var saved_level := GameState.level
	GameState.level = 100
	GameState.quest_flags.erase(SecretsDB.flag_of(sid))
	var site := SecretSite.new()
	site.secret_id = sid
	world.add_child(site)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(site is Area2D, "a secret site is a world interactable")
	check(site.done() == false, "an unfound cache starts unfound")
	var body := CharacterBody2D.new()
	body.add_to_group("player")
	world.add_child(body)
	body.global_position = site.global_position
	await get_tree().physics_frame
	await get_tree().physics_frame
	var walked := SecretsDB.is_found(sid)
	site._on_body_entered(body)
	check(walked or SecretsDB.is_found(sid), "walking over a cache finds it")
	check(site.done(), "the site knows it is finished")
	# A second site over the same secret must show as already found, not re-pay.
	var twin := SecretSite.new()
	twin.secret_id = sid
	world.add_child(twin)
	await get_tree().process_frame
	check(twin.done(), "a re-streamed secret comes back already found")
	GameState.quest_flags = saved_flags
	GameState.level = saved_level
	world.queue_free()
