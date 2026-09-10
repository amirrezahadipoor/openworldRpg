extends Node
## Visual capture harness — renders the REAL game and saves PNGs.
##
## Why this exists: the automated suite runs headless, so it renders nothing.
## Every visual defect found in the Phase B art pass (bilinear-blurred pixel art,
## checkerboard terrain, canopy blocks reading as dark rectangles, a hard-edged
## mud circle for the camp floor, enemies crushed to black silhouettes by
## modulate) was invisible to CI and only showed up in an actual render.
##
## Usage (needs a display; on a headless box use xvfb-run):
##   xvfb-run -a -s "-screen 0 1280x720x24" \
##     /tmp/rpg-toolchain/bin/godot --path . res://tools/art/capture_screenshot.tscn \
##     --resolution 1280x720
##
## Output: /tmp/rpg_shot_<n>.png
const OUT_DIR := "/tmp"
const SHOT_AT := [2.0, 3.0]

const WATCHDOG_MS := 90_000   # fail loudly instead of hitting the job timeout

var _t := 0.0
var _n := 0
var _started_ms := 0
var _pause_reported := false


func _ready() -> void:
	# The harness must not be hostage to the game's own pauses: a death screen or
	# an open dialogue pauses the tree, which used to freeze this node too and
	# hang the CI job until its 25-minute timeout.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_started_ms = Time.get_ticks_msec()
	add_child(load("res://scenes/main.tscn").instantiate())


func _process(delta: float) -> void:
	if get_tree().paused and not _pause_reported:
		_pause_reported = true
		var ds := get_tree().root.find_child("DeathScreen", true, false)
		print("DIAG: game paused at t=%.1f (death screen=%s) — capturing anyway"
			% [_t, str(ds != null and (ds as CanvasItem).visible)])
	if Time.get_ticks_msec() - _started_ms > WATCHDOG_MS:
		printerr("::error::capture watchdog fired after %d s (t=%.1f, shots=%d)"
			% [WATCHDOG_MS / 1000, _t, _n])
		get_tree().quit(2)
		return
	_t += delta
	if _n >= SHOT_AT.size() or _t < SHOT_AT[_n]:
		return
	_n += 1
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/rpg_shot_%d.png" % [OUT_DIR, _n]
	img.save_png(path)
	print("SHOT %d saved %dx%d -> %s" % [_n, img.get_width(), img.get_height(), path])
	if _n >= SHOT_AT.size():
		get_tree().quit(0)
