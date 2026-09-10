extends Node
## AudioManager — music/SFX router with pooled players.
## All audio assets must be CC0/royalty-free and are registered by id, e.g.:
##   AudioManager.register_music("biome_meadows", "res://assets/audio/meadow_theme.ogg")
##   AudioManager.register_sfx("attack_swing", "res://assets/audio/sfx/swing.wav")
## See CREDITS.md for licenses. Missing assets no-op gracefully.

const SFX_POOL_SIZE := 8
const MUSIC_FADE := 1.4

var music_tracks: Dictionary = {}
var sfx_clips: Dictionary = {}

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _active: AudioStreamPlayer  # currently fading-in / playing deck
var _sfx_players: Array = []
var _current_track: String = ""
var _music_vol := 1.0


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
	_register_builtin_sfx()
	_register_builtin_music()


func _register_builtin_sfx() -> void:
	## Real SFX: Kenney "RPG Audio" / "Interface Sounds" / "Impact Sounds" (CC0).
	## Vendored by tools/audio/vendor_audio.sh; see CREDITS.md.
	var ids := [
		"attack_swing", "hit", "player_hurt", "dodge", "pickup", "ui_click",
		"item_use", "purchase", "level_up", "enemy_cast", "boss_roar",
		"ability_whirl", "ability_bolt",
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
	var ids := ["title", "meadow", "barrens", "frost", "combat", "boss"]
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
	_active.volume_db = linear_to_db(maxf(_music_vol, 0.0001))


func set_sfx_volume(linear: float) -> void:
	var db := linear_to_db(clampf(linear, 0.0, 1.0))
	for p in _sfx_players:
		(p as AudioStreamPlayer).volume_db = db
