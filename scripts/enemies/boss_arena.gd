class_name BossArena
extends Node2D
## Fixed-position boss arena. Summons the Ember Warden when the player enters
## the aggro circle; remembers defeat across saves via GameState.quest_flags.

const BOSS_SCENE := "res://scenes/enemies/boss.tscn"
const AGGRO_RADIUS := 360.0
## Which story flag marks the Warden's defeat. The overworld arena owns the global
## `boss_defeated` (q3 asks for exactly that flag); a dungeon floor that reuses
## this script hands in its own key, so clearing one can never leave the other
## standing forever empty (audit C1).
@export var flag_key := "boss_defeated"
## The keep sits on top of its own dungeon entrance, so the arena used to wake the
## final boss for a level-1 player who merely walked past those coordinates and
## one-shot them (audit C1). It now waits for the story to have reached the Ember
## Omen; a dungeon floor built inside its own walls sets this false.
@export var story_gate := true
const STORY_QUEST := "q3_warden_fall"
const STORY_FLAG := "saw_warden_ring"

var boss: Boss = null
var defeated := false

var _poll := 0.0
var _hinted := false
var _ring: Line2D


func _ready() -> void:
	_build_visual()
	defeated = bool(GameState.quest_flags.get(flag_key, false))
	if defeated:
		_ring.default_color = Color(0.45, 0.45, 0.5, 0.35)  # spent arena


func _build_visual() -> void:
	var floor_disc := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 48:
		var a := TAU * float(i) / 48.0
		pts.append(Vector2.from_angle(a) * AGGRO_RADIUS * 0.92)
	floor_disc.polygon = pts
	floor_disc.color = Color(0.16, 0.10, 0.09, 0.55)
	floor_disc.z_index = -9
	add_child(floor_disc)

	_ring = Line2D.new()
	var ring_pts := PackedVector2Array()
	for i in 65:
		var a := TAU * float(i) / 64.0
		ring_pts.append(Vector2.from_angle(a) * AGGRO_RADIUS * 0.92)
	_ring.points = ring_pts
	_ring.width = 4.0
	_ring.default_color = Color(1.0, 0.45, 0.15, 0.8)
	add_child(_ring)


func _physics_process(delta: float) -> void:
	_poll += delta
	if _poll < 0.5:
		return
	_poll = 0.0
	var player: Node2D = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var dist := global_position.distance_to(player.global_position)
	# Spotting the scorched ring from a distance is itself a story beat.
	if dist < AGGRO_RADIUS * 1.8:
		QuestManager.register_flag("saw_warden_ring")
	if not defeated and boss == null and dist < AGGRO_RADIUS:
		if may_summon(player):
			_summon()
		else:
			_hint_once()


func may_summon(player: Node2D) -> bool:
	## Everything that has to be true before the Warden wakes: not already beaten,
	## not already out, and the player has reached the Ember Omen.
	if defeated or boss != null or player == null:
		return false
	if not story_ready():
		return false
	return global_position.distance_to(player.global_position) < AGGRO_RADIUS


func story_ready() -> bool:
	## Reaching the Ember Omen is what wakes the Warden: q2 raises `saw_warden_ring`
	## on approach and hands the player q3, which is the fight itself.
	if not story_gate:
		return true
	if QuestManager.is_active(STORY_QUEST) or QuestManager.is_done(STORY_QUEST):
		return true
	return bool(GameState.quest_flags.get(STORY_FLAG, false)) \
		and QuestManager.is_active("q2_ember_omen")


func _hint_once() -> void:
	## Say why nothing happened, once, instead of leaving a silent ring.
	if _hinted:
		return
	_hinted = true
	DamageNumber.spawn(get_parent(), global_position + Vector2(0, -70),
		"The ring is cold. The Omen has not come.", Color(1.0, 0.8, 0.5))


func _summon() -> void:
	var scene: PackedScene = load(BOSS_SCENE)
	boss = scene.instantiate()
	add_child(boss)
	boss.global_position = global_position
	boss.setup_archetype("ember_warden")
	boss.recycled.connect(_on_boss_defeated)
	EventBus.boss_phase_changed.emit(1)
	# The HUD boss plate (name + health bar + phase pips) only appears on this
	# signal. The dungeon data-boss floors emitted it, but the overworld Ember
	# Warden - the title fight - did not, so its health never showed on screen.
	EventBus.boss_encounter_started.emit("ember_warden", EnemyDB.display_name("ember_warden"))
	DamageNumber.spawn(get_parent(), global_position + Vector2(0, -90), "THE EMBER WARDEN AWAKENS", Color(1.0, 0.5, 0.2))
	AudioManager.play_music("boss")   # was "combat_theme": never registered, so it played nothing


func _on_boss_defeated(_e: Enemy) -> void:
	defeated = true
	QuestManager.register_flag(flag_key)
	boss = null
	if _ring:
		_ring.default_color = Color(0.45, 0.45, 0.5, 0.35)
	DamageNumber.spawn(get_parent(), global_position + Vector2(0, -70), "BOSS DEFEATED!", Color(1.0, 0.85, 0.3))
	EventBus.boss_defeated.emit()
	AudioManager.play_music("meadow")  # was "biome_meadows": never registered
