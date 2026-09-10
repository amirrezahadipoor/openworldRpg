extends Node
## SecretsDB (Phase F6) — the world's secrets, authored in data/secrets.json.
##
## A secret is a thing that is not on the map. Nothing in the game points at one
## until you are standing on it (or a landmark points you at the next one), and
## finding it is remembered in `GameState.quest_flags` like every other durable
## world fact, so it survives save/load and chunk reloads for free.
##
## Discovery is idempotent: the rewards are granted once, by the same code path
## whether the player walked over the cache or picked the vault's lock.

const DATA_PATH := "res://data/secrets.json"

var data: Dictionary = {}
var root: Dictionary = {}
var _find_radius := 96.0
var _by_chunk: Dictionary = {}


func _ready() -> void:
	_load()


func _load() -> void:
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_warning("SecretsDB: cannot read %s" % DATA_PATH)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SecretsDB: %s is not an object" % DATA_PATH)
		return
	root = parsed
	data = (parsed as Dictionary).get("secrets", {})
	_find_radius = float((root.get("counts", {}) as Dictionary).get("find_radius", 96))
	for sid in data.keys():
		var key := chunk_of(String(sid))
		if not _by_chunk.has(key):
			_by_chunk[key] = []
		(_by_chunk[key] as Array).append(String(sid))
	for key in _by_chunk.keys():
		(_by_chunk[key] as Array).sort()


## Secrets whose position falls inside one streamed chunk, so the streamer can
## spawn exactly the ones that belong to a chunk it is building.
func secrets_in_chunk(key: Vector2i) -> Array:
	return _by_chunk.get(key, [])


# --- queries ------------------------------------------------------------------

func all() -> Array:
	var ids := data.keys()
	ids.sort()
	return ids


func total() -> int:
	return data.size()


func get_secret(secret_id: String) -> Dictionary:
	return data.get(secret_id, {})


func flag_of(secret_id: String) -> String:
	return "secret_%s" % secret_id


func is_found(secret_id: String) -> bool:
	return bool(GameState.quest_flags.get(flag_of(secret_id), false))


func found_ids() -> Array:
	var out := []
	for sid in all():
		if is_found(String(sid)):
			out.append(String(sid))
	return out


func found_count() -> int:
	return found_ids().size()


func unfound() -> Array:
	var out := []
	for sid in all():
		if not is_found(String(sid)):
			out.append(String(sid))
	return out


func find_radius() -> float:
	return _find_radius


func visible_from_start(secret_id: String) -> bool:
	## Caches are hidden on purpose; carvings, landmarks and vaults are things you
	## can see from a distance and walk up to.
	return String(get_secret(secret_id).get("kind", "cache")) != "cache"


func nearest_unfound(from: Vector2, avoid: Array = []) -> String:
	var best := ""
	var best_d := INF
	for sid in unfound():
		if avoid.has(sid):
			continue
		var pos := position_of(String(sid))
		var d := from.distance_to(pos)
		if d < best_d:
			best_d = d
			best = String(sid)
	return best


func position_of(secret_id: String) -> Vector2:
	var p: Array = get_secret(secret_id).get("position", [0, 0])
	return Vector2(float(p[0]), float(p[1]))


func chunk_of(secret_id: String) -> Vector2i:
	var pos := position_of(secret_id)
	var size := float(ChunkStreamer.CHUNK_SIZE)
	return Vector2i(int(floorf(pos.x / size)), int(floorf(pos.y / size)))


# --- discovery ----------------------------------------------------------------

func can_open(secret_id: String) -> Dictionary:
	## Returns {ok, reason}. A vault is a lock, and the lock says why it will not
	## turn rather than silently doing nothing.
	var s := get_secret(secret_id)
	var req: Dictionary = s.get("requires", {})
	if req.is_empty():
		return {"ok": true, "reason": ""}
	var need_level := int((req.get("level", 0) as int))
	if GameState.level < need_level:
		return {"ok": false, "reason": "Locked — L%d hands made this" % need_level}
	var need_item := String(req.get("item", ""))
	if need_item != "" and GameState.item_count(need_item) <= 0:
		return {"ok": false, "reason": "Locked — needs %s" % item_name(need_item)}
	return {"ok": true, "reason": ""}


func discover(secret_id: String) -> Dictionary:
	## Grant the find. Idempotent: the second call is a no-op that reports the
	## original find, so a chunk reload can never pay twice.
	if not data.has(secret_id):
		return {"ok": false, "reason": "unknown secret", "already": false}
	if is_found(secret_id):
		return {"ok": false, "reason": "already found", "already": true}
	var s: Dictionary = data[secret_id]
	var check := can_open(secret_id)
	if not bool(check["ok"]):
		return {"ok": false, "reason": String(check["reason"]), "already": false}

	GameState.quest_flags[flag_of(secret_id)] = true

	var reward: Dictionary = s.get("reward", {})
	var xp := int(reward.get("xp", 0))
	var gold := int(reward.get("gold", 0))
	var got: Array = []
	for iid in (reward.get("items", []) as Array):
		# add_item() is void; record the grant only if the bag grew, so a full
		# inventory cannot report goods the player never received.
		var before := GameState.item_count(String(iid))
		GameState.add_item(String(iid), 1)
		if GameState.item_count(String(iid)) > before:
			got.append(String(iid))
	if xp > 0:
		GameState.add_xp(xp)
	if gold > 0:
		GameState.add_gold(gold)

	AudioManager.play_sfx("level_up" if String(s.get("kind", "")) == "vault" else "pickup")
	EventBus.secret_found.emit(secret_id, String(s.get("name", secret_id)),
		found_count(), total())
	return {
		"ok": true, "already": false, "reason": "",
		"name": String(s.get("name", secret_id)),
		"kind": String(s.get("kind", "cache")),
		"xp": xp, "gold": gold, "items": got,
		"text": String(s.get("text", "")),
	}


func hint_from(secret_id: String) -> String:
	## Landmarks and carvings are breadcrumbs: reading one points at the nearest
	## unfound secret, without saying where it is.
	var s := get_secret(secret_id)
	var target := nearest_unfound(position_of(secret_id), [secret_id])
	if target == "":
		return "There is nothing left out here to find."
	var t := get_secret(target)
	var dir := "east"
	var delta := position_of(target) - position_of(secret_id)
	if absf(delta.y) > absf(delta.x):
		dir = "south" if delta.y > 0.0 else "north"
	else:
		dir = "east" if delta.x > 0.0 else "west"
	return "%s Something of the kind lies %s, %d paces off." % [
		String(s.get("carving_lines", [""])[0]) if s.has("carving_lines") else "",
		dir, int(roundf(delta.length() / 8.0))]


func item_name(item_id: String) -> String:
	return ItemsDB.item_name(item_id)


func summary() -> String:
	return "Secrets found: %d / %d" % [found_count(), total()]


func by_kind() -> Dictionary:
	var out := {}
	for sid in all():
		var k := String(get_secret(String(sid)).get("kind", "cache"))
		out[k] = int(out.get(k, 0)) + 1
	return out
