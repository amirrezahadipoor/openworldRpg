class_name NPCController
extends Area2D
## Phase E §3 — data-driven NPC daily schedule + state machine.
##
## Mirrors the enemy FSM (`scripts/enemies/enemy.gd`): an enum state, a
## `_state_time` counter, and a single `_physics_process` switch. NPCs do not
## fight — the states are the ones the bible names:
##
##   IDLE_SCHEDULE — standing at wherever the clock says they should be
##   WALK_TO_POINT — moving to the next schedule point
##   TALK          — frozen while a conversation is open
##   FLEE_COMBAT   — running away from a hostile that got too close
##
## The clock is the existing `DayNight` node (group "day_night"); schedule
## points are offsets from the position the NPC was placed at, so one roster
## works in any settlement layout.

signal schedule_changed(slot: String)
signal barked(text: String)

enum State { IDLE_SCHEDULE, WALK_TO_POINT, TALK, FLEE_COMBAT }

## Composed LPC sheet geometry: row = block * 4 + DIR_ROW[dir], frame = row * 13 + f,
## with blocks idle(0) / walk(1) / slash(2) / spellcast(3) / hurt(4) and dir rows
## n(0) / w(1) / s(2) / e(3). South-facing idle is therefore frame 2 * 13.
const ROW_WIDTH := 13
const IDLE_BLOCK_BASE := 0 * 4 * ROW_WIDTH
const WALK_BLOCK_BASE := 1 * 4 * ROW_WIDTH
const IDLE_FRAME_BASE := 2 * 13  # south-facing idle, used before the first tick
const IDLE_FRAMES := 2
const WALK_FRAMES := 9
const IDLE_FPS := 4.0
const WALK_FPS := 12.0

@export var npc_id: String = ""
@export var move_speed := 46.0
@export var arrive_radius := 8.0
@export var flee_radius := 170.0
@export var bark_radius := 190.0
@export var bark_interval := 24.0
## Minimum gap two NPCs keep between each other (H5.4 / the "everyone stands on
## everyone" report). 26 px of hard separation, tapering to nothing at 46 px.
@export var personal_space := 46.0
@export var schedule_enabled := true
## Test/debug override for the clock ("" = read DayNight).
@export var time_override: String = ""

var state: State = State.IDLE_SCHEDULE
var home := Vector2.ZERO
var target := Vector2.ZERO
var slot: String = "Day"
var _state_time := 0.0
var _schedule: Dictionary = {}
var _clock: DayNight
var _bark_timer := 0.0
var _anim_time := 0.0

static var _roster_cache: Dictionary = {}


static func roster() -> Dictionary:
	## data/npcs.json, cached — the whole named-NPC roster with its schedules.
	if not _roster_cache.is_empty():
		return _roster_cache
	var f := FileAccess.open("res://data/npcs.json", FileAccess.READ)
	if f == null:
		push_error("NPCController: data/npcs.json missing")
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("NPCController: data/npcs.json is not a JSON object")
		return {}
	_roster_cache = (parsed as Dictionary).get("npcs", {})
	return _roster_cache


static func roster_entry(id: String) -> Dictionary:
	return (roster() as Dictionary).get(id, {})


static func stock_for(id: String) -> Array:
	## A vendor's own shelf, from data/npcs.json. Before this every shop in the
	## valley sold the same four things (camp.gd's MERCHANT_STOCK).
	return roster_entry(id).get("stock", []) as Array


static func is_vendor_id(id: String) -> bool:
	return not stock_for(id).is_empty()


func _ready() -> void:
	add_to_group("npc")
	home = position
	load_schedule()
	target = schedule_point(time_of_day())
	slot = time_of_day()
	_bark_timer = bark_interval * randf()
	_rng_randomize_bark()


func _rng_randomize_bark() -> void:
	_bark_timer = randf_range(bark_interval * 0.35, bark_interval)


func load_schedule() -> void:
	_schedule = (roster_entry(npc_id).get("schedule", {}) as Dictionary).duplicate()
	home = position


func schedule_point(time_name: String) -> Vector2:
	## Schedule values are offsets from `home`; unknown slots fall back to home.
	var off: Variant = _schedule.get(time_name, _schedule.get("Day", [0, 0]))
	if typeof(off) != TYPE_ARRAY or (off as Array).size() != 2:
		return home
	var a := off as Array
	return home + Vector2(float(a[0]), float(a[1]))


func time_of_day() -> String:
	if time_override != "":
		return time_override
	if _clock == null or not is_instance_valid(_clock):
		_clock = get_tree().get_first_node_in_group("day_night") as DayNight
	if _clock == null:
		return "Day"
	return _clock.time_of_day_name()


func is_walking() -> bool:
	return state == State.WALK_TO_POINT or state == State.FLEE_COMBAT


func anim_block_base() -> int:
	return WALK_BLOCK_BASE if is_walking() else IDLE_BLOCK_BASE


func anim_frame_count() -> int:
	return WALK_FRAMES if is_walking() else IDLE_FRAMES


func anim_fps() -> float:
	return WALK_FPS if is_walking() else IDLE_FPS


## Advances the sprite's frame on the shared sheet, facing `dir_row`
## (0 = n, 1 = w, 2 = s, 3 = e). Returns false when no LPC sheet is attached.
func advance_sprite_anim(delta: float, sprite: Sprite2D, dir_row: int = 2) -> bool:
	if sprite == null or sprite.texture == null:
		return false
	_anim_time += delta * anim_fps()
	var count := anim_frame_count()
	while _anim_time >= float(count):
		_anim_time -= float(count)
	sprite.frame = anim_block_base() + clampi(dir_row, 0, 3) * ROW_WIDTH + int(_anim_time)
	return true


func talk() -> void:
	state = State.TALK
	target = position


func end_talk() -> void:
	if state == State.TALK:
		state = State.IDLE_SCHEDULE


func _physics_process(delta: float) -> void:
	_state_time += delta

	if state == State.TALK:
		return

	# FLEE_COMBAT outranks the schedule: a hostile nearby sends the NPC running.
	var threat := _nearest_threat()
	if threat != null:
		var away := (global_position - threat.global_position)
		if away.length() < 0.001:
			away = Vector2.RIGHT
		state = State.FLEE_COMBAT
		_move_toward(global_position + away.normalized() * 64.0, delta)
		_maybe_bark(delta)
		return

	# Schedule: walk to the clock's point, then stand there.
	var want_slot := time_of_day()
	if want_slot != slot:
		slot = want_slot
		schedule_changed.emit(slot)
	if schedule_enabled:
		var want := schedule_point(slot)
		if global_position.distance_to(want) > arrive_radius:
			state = State.WALK_TO_POINT
			target = want
			_move_toward(want, delta)
		else:
			state = State.IDLE_SCHEDULE
			global_position = want
	else:
		state = State.IDLE_SCHEDULE
	_separate_from_neighbours()
	_maybe_bark(delta)


func _separate_from_neighbours() -> void:
	## Two residents whose schedule points are close used to end up standing
	## inside each other — the schedules are offsets from each NPC's own seat, so
	## nothing ever compared them. A soft push keeps a readable gap instead: full
	## separation starts at `personal_space` and the push is capped per frame.
	var push := Vector2.ZERO
	for other in get_tree().get_nodes_in_group("npc"):
		if other == self or not (other is Node2D):
			continue
		var v: Vector2 = global_position - (other as Node2D).global_position
		var d := v.length()
		if d < 0.001:
			v = Vector2.RIGHT.rotated(float(npc_id.hash() % 360))
			d = 0.001
		if d < personal_space:
			push += v.normalized() * (personal_space - d) * 0.5
	if push == Vector2.ZERO:
		return
	# Cap the correction so a crowded frame cannot teleport anyone.
	global_position += push.limit_length(6.0)


func _move_toward(point: Vector2, delta: float) -> void:
	var step := move_speed * delta
	if global_position.distance_to(point) <= step:
		global_position = point
	else:
		global_position = global_position.move_toward(point, step)


func _nearest_threat() -> Node2D:
	## Only enemies that are actually alive and nearby make an NPC run.
	var best: Node2D = null
	var best_d := flee_radius
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node2D) or not (e as Node2D).visible:
			continue
		var en := e as Node2D
		var d := global_position.distance_to(en.global_position)
		if d < best_d:
			best_d = d
			best = en
	return best


func _maybe_bark(delta: float) -> void:
	## Idle barks: only while standing still, only with the player nearby, and
	## rate-limited so an NPC never becomes a chatterbox.
	if state != State.IDLE_SCHEDULE or npc_id == "":
		return
	_bark_timer -= delta
	if _bark_timer > 0.0:
		return
	_bark_timer = bark_interval
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null or global_position.distance_to(player.global_position) > bark_radius:
		return
	var line := DialogueDB.pick_bark(npc_id, slot)
	if line == "":
		return
	barked.emit(line)
	EventBus.npc_barked.emit(npc_id, display_name_of(), line)


func display_name_of() -> String:
	var n := String(roster_entry(npc_id).get("display_name", ""))
	return n if n != "" else name
