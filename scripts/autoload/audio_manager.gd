extends Node
## AudioManager — music/SFX router with pooled players.
## All audio assets must be CC0/royalty-free and are registered by id, e.g.:
##   AudioManager.register_music("biome_meadows", "res://assets/audio/meadow_theme.ogg")
##   AudioManager.register_sfx("attack_swing", "res://assets/audio/sfx/swing.wav")
## See CREDITS.md for licenses. Missing assets no-op gracefully.

const SFX_POOL_SIZE := 8

var music_tracks: Dictionary = {}
var sfx_clips: Dictionary = {}

var _music_player: AudioStreamPlayer
var _sfx_players: Array = []
var _current_track: String = ""


func _ready() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "Music"
	add_child(_music_player)
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "SFX_%d" % i
		add_child(p)
		_sfx_players.append(p)


func register_music(id: String, path: String) -> void:
	music_tracks[id] = path


func register_sfx(id: String, path: String) -> void:
	sfx_clips[id] = path


func play_music(id: String) -> void:
	if id == _current_track:
		return
	_current_track = id
	if not music_tracks.has(id):
		return
	var stream: AudioStream = load(music_tracks[id])
	if stream == null:
		return
	_music_player.stream = stream
	_music_player.play()


func stop_music() -> void:
	_current_track = ""
	_music_player.stop()


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
	_music_player.volume_db = linear_to_db(clampf(linear, 0.0, 1.0))


func set_sfx_volume(linear: float) -> void:
	var db := linear_to_db(clampf(linear, 0.0, 1.0))
	for p in _sfx_players:
		(p as AudioStreamPlayer).volume_db = db
