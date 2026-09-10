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

var _t := 0.0
var _n := 0


func _ready() -> void:
	add_child(load("res://scenes/main.tscn").instantiate())


func _process(delta: float) -> void:
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
