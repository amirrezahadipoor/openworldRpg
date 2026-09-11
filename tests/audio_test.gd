extends Node
## Audio regression test.
##
## Guards the bug class found during the Phase B audio pass: scripts requested
## play_music("combat_theme") / play_sfx(...) with ids that AudioManager never
## registered. AudioManager deliberately no-ops on unknown ids, so the game just
## played NOTHING — silently, with no error, in normal play and in CI.
##
## This test (a) asserts every registered id resolves to a real asset file, and
## (b) greps the whole script tree for play_music/play_sfx call sites and asserts
## every literal id used is actually registered.
##
## Prints "AUDIO RESULT: PASS (n checks)" or "AUDIO RESULT: FAIL" and exits
## non-zero on failure, matching the other suites' contract.

const SCRIPT_ROOT := "res://scripts"

var _checks := 0
var _failures: Array[String] = []


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	_check_registered_assets_resolve()
	_check_call_sites_registered()
	_check_music_id_ordering()

	print("")
	if _failures.is_empty():
		print("AUDIO RESULT: PASS (%d checks)" % _checks)
	else:
		for f in _failures:
			print("  FAIL: %s" % f)
		print("AUDIO RESULT: FAIL (%d failures / %d checks)" % [_failures.size(), _checks])
		get_tree().quit(1)
		return
	get_tree().quit(0)


func _check_music_id_ordering() -> void:
	## M4: play_music() stored the requested id as current *before* checking that it
	## exists, so a typo'd id became the current track and every later call for a
	## real one no-op'd against it - the game went silent for the rest of the run.
	print("[audio_test] an unknown music id must not lock the player out")
	AudioManager.play_music("title")
	var good := AudioManager.current_music()
	AudioManager.play_music("not_a_real_track")
	if AudioManager.current_music() == good and good == "title":
		_ok("an unknown track does not become current (M4)")
	else:
		_fail("unknown track replaced the music: %s" % AudioManager.current_music())
	AudioManager.play_music("not_a_real_track")
	AudioManager.play_music("title")
	if AudioManager.current_music() == "title":
		_ok("a real track still plays after a bad request")
	else:
		_fail("the music stopped after a bad request")


func _ok(msg: String) -> void:
	_checks += 1
	print("  PASS: %s" % msg)


func _fail(msg: String) -> void:
	_checks += 1
	_failures.append(msg)
	print("  FAIL: %s" % msg)


# --- (a) registered ids must resolve to real files ---------------------------------

func _check_registered_assets_resolve() -> void:
	for id in AudioManager.music_tracks.keys():
		var path: String = AudioManager.music_tracks[id]
		if ResourceLoader.exists(path):
			_ok("music '%s' -> %s" % [id, path.get_file()])
		else:
			_fail("music '%s' registered but missing on disk: %s" % [id, path])

	for id in AudioManager.sfx_clips.keys():
		var path: String = AudioManager.sfx_clips[id]
		if ResourceLoader.exists(path):
			_ok("sfx '%s' -> %s" % [id, path.get_file()])
		else:
			_fail("sfx '%s' registered but missing on disk: %s" % [id, path])

	if AudioManager.music_tracks.is_empty():
		_fail("no music tracks registered at all")
	if AudioManager.sfx_clips.is_empty():
		_fail("no sfx registered at all")


# --- (b) every literal id used in scripts must be registered -----------------------

func _check_call_sites_registered() -> void:
	var used_music := {}
	var used_sfx := {}
	_scan_dir(SCRIPT_ROOT, used_music, used_sfx)

	if used_music.is_empty() and used_sfx.is_empty():
		_fail("no play_music/play_sfx call sites found — did the scan break?")
		return

	for id in used_music.keys():
		if AudioManager.music_tracks.has(id):
			_ok("play_music(\"%s\") is registered" % id)
		else:
			_fail("play_music(\"%s\") has no registered track — it would play nothing" % id)

	for id in used_sfx.keys():
		if AudioManager.sfx_clips.has(id):
			_ok("play_sfx(\"%s\") is registered" % id)
		else:
			_fail("play_sfx(\"%s\") has no registered clip — it would play nothing" % id)


func _scan_dir(dir_path: String, used_music: Dictionary, used_sfx: Dictionary) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if d.current_is_dir():
			if not name.begins_with("."):
				_scan_dir(full, used_music, used_sfx)
		elif name.ends_with(".gd"):
			_scan_file(full, used_music, used_sfx)
		name = d.get_next()
	d.list_dir_end()


func _scan_file(path: String, used_music: Dictionary, used_sfx: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var src := f.get_as_text()
	f.close()
	_collect(src, "play_music", used_music)
	_collect(src, "play_sfx", used_sfx)


func _collect(src: String, func_name: String, into: Dictionary) -> void:
	# Collect string literals passed to the given function, e.g. play_music("boss")
	var needle := func_name + "("
	var idx := src.find(needle)
	while idx != -1:
		var rest := src.substr(idx + needle.length())
		if rest.begins_with("\""):
			var end := rest.find("\"", 1)
			if end > 1:
				var id := rest.substr(1, end - 1)
				# skip ids built at runtime (e.g. format strings / variables)
				if not id.contains("%") and not id.is_empty():
					into[id] = true
		idx = src.find(needle, idx + needle.length())
