extends Node
## Phase E §1 visual verification — renders every settlement and one dungeon
## floor from the REAL game, so "3 villages / 3 towns / 3 cities" is checked
## with pixels instead of only with data.
##
## The camera is a smooth-follow rig (`FollowCamera.follow_speed = 8`), so after
## teleporting the player we must call `camera.snap()` and then wait for the
## chunk streamer (0.25 s update interval) before shooting — otherwise the shot
## is of empty space between chunks.
##
## Usage:
##   xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --path . res://tools/art/capture_settlements.tscn --resolution 1280x720
##
## Output: /tmp/rpg_settlement_<id>.png and /tmp/rpg_dungeon_<id>_f<n>.png

const OUT_DIR := "/tmp"
const SETTLE_FRAMES := 40   # ~0.66 s: streamer update interval is 0.25 s
const DUNGEON_FRAMES := 20

var _main: Node
var _player: Node2D
var _shots := 0
var _queue: Array = []
var _wait := 0
var _pending := {}


func _ready() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	var ids: Array = []
	for id in Settlement.all():
		ids.append(id)
	ids.sort()
	for id in ids:
		_queue.append({"kind": "settlement", "id": String(id)})
	_queue.append({"kind": "dungeon", "id": "slagworks", "floor": 1})
	_queue.append({"kind": "dungeon", "id": "slagworks", "floor": 2})


func _process(_delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node2D
		if _player == null:
			return

	if _wait > 0:
		_wait -= 1
		if _wait > 0:
			return
		await RenderingServer.frame_post_draw
		_emit_shot()
		return

	if _queue.is_empty():
		print("CAPTURED %d images" % _shots)
		get_tree().quit(0)
		return

	_pending = _queue.pop_front() as Dictionary
	match String(_pending.get("kind", "")):
		"settlement":
			var s := Settlement.get_data(String(_pending["id"]))
			var p: Array = s.get("position", [0, 0])
			# Stand just south of the plaza so the ring of houses is in view.
			_player.global_position = Vector2(float(p[0]), float(p[1]) + 60.0)
			_snap_camera()
			_wait = SETTLE_FRAMES
		"dungeon":
			var floor_idx := int(_pending.get("floor", 1))
			if floor_idx <= 1:
				_main.enter_dungeon(String(_pending["id"]))
			else:
				_main.current_dungeon().descend()
			_snap_camera()
			_wait = DUNGEON_FRAMES


func _snap_camera() -> void:
	## The follow rig lerps; snapping is what fast travel does.
	var cam: Node = _main.get("camera")
	if cam != null and cam.has_method("snap"):
		cam.call("snap")


func _emit_shot() -> void:
	var name := ""
	match String(_pending.get("kind", "")):
		"settlement":
			name = "rpg_settlement_%s" % String(_pending["id"])
		"dungeon":
			name = "rpg_dungeon_%s_f%d" % [String(_pending["id"]), int(_pending.get("floor", 1))]
	if name == "":
		return
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	img.save_png(path)
	_shots += 1
	print("SHOT %s -> %s" % [name, path])
