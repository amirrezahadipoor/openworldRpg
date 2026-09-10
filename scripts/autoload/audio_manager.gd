extends Node
## AudioManager — music/SFX router with pooled players.
## All audio assets must be CC0/royalty-free and are registered by id, e.g.:
##   AudioManager.register_music("biome_meadows", "res://assets/audio/meadow_theme.ogg")
##   AudioManager.register_sfx("attack_swing", "res://assets/audio/sfx/swing.wav")
## See CREDITS.md for licenses. Missing assets no-op gracefully.

const SFX_POOL_SIZE := 8
const MUSIC_FADE := 1.4
const AMBIENT_FADE := 2.0
## Real buses, created at runtime (AudioServer.add_bus routes by index, and the
## project ships no default_bus_layout). Mixing dialogue, ambience and music
## through one fader was the reason "volume" could not actually be tuned.
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const BUS_AMBIENT := "Ambience"

var music_tracks: Dictionary = {}
var sfx_clips: Dictionary = {}

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _active: AudioStreamPlayer  # currently fading-in / playing deck
var _sfx_players: Array = []
var _current_track: String = ""
var _music_vol := 1.0
var _ambient_a: AudioStreamPlayer
var _ambient_b: AudioStreamPlayer
var _active_ambient: AudioStreamPlayer
var _current_ambient := ""
var ambient_clips: Dictionary = {}


func _ready() -> void:
	_music_a = AudioStreamPlayer.new()
	_music_a.name = "MusicA"
	_music_b = AudioStreamPlayer.new()
	_music_b.name = "MusicB"
	add_child(_music_a)
	add_child(_music_b)
	_active = _music_a
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "SFX_%d" % i
		add_child(p)
		_sfx_players.append(p)
	_ambient_a = AudioStreamPlayer.new()
	_ambient_a.name = "AmbientA"
	_ambient_b = AudioStreamPlayer.new()
	_ambient_b.name = "AmbientB"
	add_child(_ambient_a)
	add_child(_ambient_b)
	_active_ambient = _ambient_a
	# Buses last: this routes every player, so they all have to exist first.
	_ensure_buses()
	_register_builtin_sfx()
	_register_builtin_music()
	_register_builtin_ambient()


func _ensure_buses() -> void:
	## Idempotent: creating the same bus twice would silently double-route.
	for bus_name in [BUS_MUSIC, BUS_SFX, BUS_AMBIENT]:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
	if AudioServer.get_bus_index(BUS_MUSIC) != -1:
		_music_a.bus = BUS_MUSIC
		_music_b.bus = BUS_MUSIC
	if AudioServer.get_bus_index(BUS_SFX) != -1:
		for p in _sfx_players:
			(p as AudioStreamPlayer).bus = BUS_SFX
	if AudioServer.get_bus_index(BUS_AMBIENT) != -1:
		if _ambient_a != null:
			_ambient_a.bus = BUS_AMBIENT
		if _ambient_b != null:
			_ambient_b.bus = BUS_AMBIENT


func _register_builtin_ambient() -> void:
	## Weather and place: wind, water, fire, cave. Without these the world was
	## silent except for the score. Layers are our own synthesised loops
	## (tools/gen_ambient.py), so they carry no third-party licence.
	var ids := ["amb_meadow", "amb_frost", "amb_lava", "amb_campfire", "amb_water",
		"amb_cave", "amb_town"]
	for id in ids:
		var path := _resolve("res://assets/audio/ambient/%s" % id)
		if path != "":
			ambient_clips[id] = path


func play_ambient(id: String) -> void:
	if id == _current_ambient:
		return
	_current_ambient = id
	if id == "" or not ambient_clips.has(id):
		# fade out whatever is running
		var tw_out := create_tween()
		tw_out.tween_property(_active_ambient, "volume_db", linear_to_db(0.0001), AMBIENT_FADE)
		tw_out.tween_callback(_active_ambient.stop)
		return
	var stream: AudioStream = load(ambient_clips[id])
	if stream == null:
		return
	_loopify(stream)
	var incoming := _ambient_b if _active_ambient == _ambient_a else _ambient_a
	incoming.stream = stream
	incoming.volume_db = linear_to_db(0.0001)
	incoming.play()
	var outgoing := _active_ambient
	_active_ambient = incoming
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(incoming, "volume_db", linear_to_db(0.6), AMBIENT_FADE)
	tw.tween_property(outgoing, "volume_db", linear_to_db(0.0001), AMBIENT_FADE)
	tw.chain().tween_callback(outgoing.stop)


func current_music() -> String:
	return _current_track


func _register_builtin_sfx() -> void:
	## Real SFX: Kenney "RPG Audio" / "Interface Sounds" / "Impact Sounds" (CC0).
	## Vendored by tools/audio/vendor_audio.sh; see CREDITS.md.
	var ids := [
		"attack_swing", "hit", "player_hurt", "dodge", "pickup", "ui_click",
		"item_use", "purchase", "level_up", "enemy_cast", "boss_roar",
		"ability_whirl", "ability_bolt",
		# Added with the audit fix pass: the world had one sound per system and
		# nothing for equipping, for a quest landing, for a secret, for money or
		# for a refusal.
		"equip", "coin", "quest_accept", "quest_complete", "secret_found",
		"denied", "footstep",
	]
	for id in ids:
		var path := _resolve("res://assets/audio/sfx/%s" % id)
		if path != "":
			register_sfx(id, path)


func _resolve(stem: String) -> String:
	## Prefer .ogg (real vendored audio), fall back to .wav (legacy placeholders).
	for ext in [".ogg", ".wav"]:
		if FileAccess.file_exists(stem + ext):
			return stem + ext
	return ""


func register_music(id: String, path: String) -> void:
	music_tracks[id] = path


func register_sfx(id: String, path: String) -> void:
	sfx_clips[id] = path


func _register_builtin_music() -> void:
	## Real score: "Generic 8-bit JRPG Soundtrack" by Avgvst (CC-BY 3.0/4.0).
	## Vendored by tools/audio/vendor_audio.sh; see CREDITS.md.
	var ids := ["title", "meadow", "barrens", "frost", "combat", "boss",
		"town", "dungeon", "camp", "victory", "danger"]
	for id in ids:
		var path := _resolve("res://assets/audio/music/%s" % id)
		if path != "":
			register_music(id, path)


func play_music(id: String) -> void:
	if id == _current_track:
		return
	_current_track = id
	if not music_tracks.has(id):
		return
	var stream: AudioStream = load(music_tracks[id])
	if stream == null:
		return
	_loopify(stream)
	var incoming := _music_b if _active == _music_a else _music_a
	incoming.stream = stream
	incoming.volume_db = linear_to_db(0.0001)
	incoming.play()
	var outgoing := _active
	_active = incoming
	var target_db := linear_to_db(clampf(_music_vol, 0.0, 1.0))
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(incoming, "volume_db", target_db, MUSIC_FADE)
	tw.tween_property(outgoing, "volume_db", linear_to_db(0.0001), MUSIC_FADE)
	tw.chain().tween_callback(outgoing.stop)


func _loopify(stream: AudioStream) -> void:
	## The vendored score is OGG; without this the biome tracks would play once
	## and stop instead of looping. Legacy procedural WAVs stay supported.
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = wav.data.size() / 2  # 16-bit mono


func stop_music() -> void:
	_current_track = ""
	_music_a.stop()
	_music_b.stop()


func play_sfx(id: String) -> void:
	if not sfx_clips.has(id):
		return
	var stream: AudioStream = load(sfx_clips[id])
	if stream == null:
		return
	for p in _sfx_players:
		if not (p as AudioStreamPlayer).playing:
			p.stream = stream
			p.play()
			return


func set_music_volume(linear: float) -> void:
	_music_vol = clampf(linear, 0.0, 1.0)
	# Through the bus: the individual players keep their own fade curves, so
	# setting volume on each player fought the cross-fade tween.
	var idx := AudioServer.get_bus_index(BUS_MUSIC)
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(_music_vol, 0.0001)))
		AudioServer.set_bus_mute(idx, _music_vol <= 0.001)
	else:
		_active.volume_db = linear_to_db(maxf(_music_vol, 0.0001))


func set_sfx_volume(linear: float) -> void:
	var v := clampf(linear, 0.0, 1.0)
	var db := linear_to_db(maxf(v, 0.0001))
	var idx := AudioServer.get_bus_index(BUS_SFX)
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, db)
		AudioServer.set_bus_mute(idx, v <= 0.001)
	else:
		for p in _sfx_players:
			(p as AudioStreamPlayer).volume_db = db


func set_ambient_volume(linear: float) -> void:
	var v := clampf(linear, 0.0, 1.0)
	var idx := AudioServer.get_bus_index(BUS_AMBIENT)
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(idx, v <= 0.001)
