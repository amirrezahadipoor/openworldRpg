class_name SecretSite
extends WorldInteractable
## A single secret, dropped into the world by ChunkStreamer (Phase F6).
##
## Caches are hidden — you find them by walking over them, which is the whole
## point of a secret. Carvings, landmarks and vaults are things you can see and
## walk up to. A vault is a lock, so it answers to the interact key and says why
## it will not turn, instead of quietly doing nothing.
##
## Found/not-found persists in GameState.quest_flags via SecretsDB, so a chunk
## reload after a save never re-pays a find.

const PICKUP_SCENE := "res://scenes/world/pickup.tscn"

@export var secret_id := ""

var _info: Dictionary = {}
var _kind := "cache"
var _found := false
var _shimmer: Polygon2D
var _t := 0.0


func _ready() -> void:
	_info = SecretsDB.get_secret(secret_id)
	if _info.is_empty():
		queue_free()
		return
	_kind = String(_info.get("kind", "cache"))
	_found = SecretsDB.is_found(secret_id)
	interact_radius = SecretsDB.find_radius()
	match _kind:
		"vault":
			if not _found:
				prompt_text = "Locked vault"
		"carving":
			if not _found:
				prompt_text = "Read the carving"
		"landmark":
			if not _found:
				prompt_text = "Look out"
	super._ready()
	if _kind == "cache" or _found:
		_prompt.visible = false


func _build_visual() -> void:
	match _kind:
		"cache":
			# Buried goods: a slight rise in the ground, and a glint.
			_poly(PackedVector2Array([
				Vector2(-20, 4), Vector2(-8, -6), Vector2(8, -6), Vector2(20, 4),
			]), Color(0.34, 0.29, 0.19, 0.85))
			_shimmer = _poly(PackedVector2Array([
				Vector2(-2, -2), Vector2(2, -2), Vector2(2, 2), Vector2(-2, 2),
			]), Color(1.0, 0.92, 0.55, 0.30), Vector2(0, -10))
		"carving":
			_poly(PackedVector2Array([
				Vector2(-14, 18), Vector2(-10, -22), Vector2(10, -22), Vector2(14, 18),
			]), Color(0.52, 0.52, 0.50))
			for i in 3:
				_poly(PackedVector2Array([
					Vector2(-7, -14 + i * 8), Vector2(7, -14 + i * 8),
					Vector2(7, -11 + i * 8), Vector2(-7, -11 + i * 8),
				]), Color(0.30, 0.30, 0.32))
		"landmark":
			_poly(PackedVector2Array([
				Vector2(-20, 16), Vector2(-12, -2), Vector2(12, -2), Vector2(20, 16),
			]), Color(0.48, 0.46, 0.42))
			_poly(PackedVector2Array([
				Vector2(-13, -2), Vector2(-7, -16), Vector2(7, -16), Vector2(13, -2),
			]), Color(0.56, 0.54, 0.50))
			_poly(PackedVector2Array([
				Vector2(-7, -16), Vector2(-3, -28), Vector2(3, -28), Vector2(7, -16),
			]), Color(0.62, 0.60, 0.56))
			_poly(PackedVector2Array([  # the long-view flag
				Vector2(0, -28), Vector2(0, -44), Vector2(16, -38), Vector2(0, -32),
			]), Color(0.78, 0.32, 0.24))
			_shimmer = _poly(PackedVector2Array([
				Vector2(-3, -3), Vector2(3, -3), Vector2(3, 3), Vector2(-3, 3),
			]), Color(1.0, 0.85, 0.45, 0.22), Vector2(0, -44))
		"vault":
			_poly(PackedVector2Array([
				Vector2(-22, 10), Vector2(22, 10), Vector2(22, 22), Vector2(-22, 22),
			]), Color(0.10, 0.09, 0.08, 0.5), Vector2.ZERO, -1)
			_poly(PackedVector2Array([
				Vector2(-20, -12), Vector2(20, -12), Vector2(20, 14), Vector2(-20, 14),
			]), Color(0.36, 0.31, 0.26))
			for i in 2:
				_poly(PackedVector2Array([
					Vector2(-18 + i * 30, -12), Vector2(-13 + i * 30, -12),
					Vector2(-13 + i * 30, 14), Vector2(-18 + i * 30, 14),
				]), Color(0.66, 0.56, 0.28))
			_poly(PackedVector2Array([
				Vector2(-4, -4), Vector2(4, -4), Vector2(4, 4), Vector2(-4, 4),
			]), Color(0.82, 0.72, 0.36))


func _process(delta: float) -> void:
	if _found or _shimmer == null:
		return
	_t += delta
	_shimmer.color.a = 0.10 + 0.22 * (0.5 + 0.5 * sin(_t * 2.2))


func _on_body_entered(body: Node) -> void:
	super._on_body_entered(body)
	# Caches whisper: found by walking over them, never announced by a label.
	if _kind == "cache" or _found:
		_prompt.visible = false
	if not body.is_in_group("player") or _found:
		return
	if _kind == "vault":
		return  # a vault is opened, not stumbled into
	_reveal()


func _on_interact() -> void:
	if _found:
		return
	if _kind == "carving":
		# Reading a carving gives you the region's next breadcrumb.
		var reveal := SecretsDB.discover(secret_id)
		if bool(reveal.get("ok", false)):
			_after_find(reveal)
			SecretsDB.mark_rumoured(SecretsDB.rumour_target(secret_id))
			var hud: Node = _hud_node()
			if hud != null:
				hud.show_toast(SecretsDB.hint_from(secret_id))
		return
	_reveal()


func _reveal() -> void:
	var result := SecretsDB.discover(secret_id)
	if not bool(result.get("ok", false)):
		var reason := String(result.get("reason", ""))
		var hud: Node = _hud_node()
		if reason != "" and not bool(result.get("already", false)) and hud != null:
			hud.show_toast(reason)
		return
	_after_find(result)
	# The `hint` field used to sit unread in secrets.json; a found secret should
	# leave you with somewhere to go, not just loot. Marking the target is what
	# puts it on the minimap as a rumour.
	SecretsDB.mark_rumoured(SecretsDB.rumour_target(secret_id))
	var trail := SecretsDB.hint_from(secret_id)
	if trail.is_empty():
		return
	var hud: Node = _hud_node()
	if hud != null:
		hud.show_toast(trail)


func _after_find(result: Dictionary) -> void:
	_found = true
	if _shimmer != null:
		_shimmer.color = Color(1.0, 0.95, 0.7, 0.85)
	AudioManager.play_sfx("pickup")
	EventBus.interactable_used.emit(self)
	# A cache is found from a physics callback (body_entered), and spawning an
	# Area2D there is illegal — Godot is mid-flush. Defer the drop.
	_drop_loot.call_deferred(result)


func _drop_loot(result: Dictionary) -> void:
	## Drop the find on the ground so the player sees what they got.
	var scene: PackedScene = load(PICKUP_SCENE)
	var host := get_tree().current_scene
	if host == null:
		return
	var offset := 0
	for iid in (result.get("items", []) as Array):
		var p: Pickup = scene.instantiate()
		host.add_child(p)
		p.global_position = global_position + Vector2(-12 + offset, -18)
		p.setup_item(String(iid))
		offset += 14
	var gold := int(result.get("gold", 0))
	if gold > 0:
		var g: Pickup = scene.instantiate()
		host.add_child(g)
		g.global_position = global_position + Vector2(0, 8)
		g.setup_gold(gold)


func _hud_node() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get("hud_ref")


func done() -> bool:
	return _found
