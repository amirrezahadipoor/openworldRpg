class_name PoseArt
extends RefCounted
## Reads `assets/lpc/pose_frames.json` — which composed sheets carry generated
## pose art, and how many frames of it.
##
## The art pipeline (tools/make_idle_frames.py) pastes generated poses into a
## composed LPC sheet:
##
##   idle        columns 2-3 of every direction row (weight shift, look-around)
##   slash       columns 0-3 of every direction row (a four-pose swing)
##   spellcast  columns 0-3 of every direction row (a four-pose cast)
##
## A sheet with idle art plays four frames in the order [base, shift, breath,
## look-around]; without it, the two frames the LPC layers ship. A sheet with
## slash art swings through its own four poses; without it, the six LPC slash
## frames. Both the player and every monster ask this file, so a sheet is never
## animated on assumptions about its columns.
##
## Manifest shape (written by the tool, regenerated with the art):
##   { "enemy_goblin": {"idle": 4}, "player_leather_sword": {"idle": 4, "slash": 4} }

const MANIFEST := "res://assets/lpc/pose_frames.json"
const SHEET_DIR := "res://assets/lpc/"

## Which generated column each idle step shows. The generator is asked for
## [base, look-around] and the LPC sheet's own second frame is the breath, so the
## loop interleaves them instead of playing the two halves back to back.
const IDLE_LOOP := [0, 2, 1, 3]
const IDLE_GENERATED := 4
const IDLE_BASE := 2

static var _sheets: Dictionary = {}


static func all() -> Dictionary:
	## Sheet stem -> {anim: frame count}. Empty when no art has been generated.
	if _sheets.is_empty() and FileAccess.file_exists(MANIFEST):
		var fh := FileAccess.open(MANIFEST, FileAccess.READ)
		if fh:
			var parsed: Variant = JSON.parse_string(fh.get_as_text())
			if parsed is Dictionary:
				_sheets = parsed
	return _sheets


static func for_sheet(path: String) -> Dictionary:
	var entry: Variant = all().get(path.get_file().get_basename(), {})
	return entry as Dictionary if typeof(entry) == TYPE_DICTIONARY else {}


static func has(path: String, anim: String) -> bool:
	return int(for_sheet(path).get(anim, 0)) > 0


static func count(path: String, anim: String, fallback: int) -> int:
	var n := int(for_sheet(path).get(anim, 0))
	return n if n > 0 else fallback


static func idle_columns(path: String, base_frames: int) -> Array:
	## Sheet column for each idle step, in playback order.
	var n := count(path, "idle", base_frames)
	if n < IDLE_GENERATED or base_frames < IDLE_BASE:
		return range(base_frames)
	return IDLE_LOOP


static func slash_columns(path: String, base_frames: int) -> Array:
	## Generated attack art is pasted from column 0, so playback is 0..n-1.
	return _generated_columns(path, "slash", base_frames)


static func cast_columns(path: String, base_frames: int) -> Array:
	## A ranged enemy attacks on the spellcast block, so its generated art lands
	## there and is played back the same way.
	return _generated_columns(path, "spellcast", base_frames)


static func _generated_columns(path: String, anim: String, base_frames: int) -> Array:
	var n := count(path, anim, base_frames)
	if n >= base_frames:
		return range(base_frames)
	return range(n)
