class_name BossArena
extends Node2D
## Fixed-position boss arena. Summons the Ember Warden when the player enters
## the aggro circle; remembers defeat across saves via GameState.quest_flags.

const BOSS_SCENE := "res://scenes/enemies/boss.tscn"
const AGGRO_RADIUS := 360.0

var boss: Boss = null
var defeated := false

var _poll := 0.0
var _ring: Line2D


func _ready() -> void:
	_build_visual()
	defeated = bool(GameState.quest_flags.get("boss_defeated", false))
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
		_summon()


func _summon() -> void:
	var scene: PackedScene = load(BOSS_SCENE)
	boss = scene.instantiate()
	add_child(boss)
	boss.global_position = global_position
	boss.setup_archetype("ember_warden")
	boss.recycled.connect(_on_boss_defeated)
	EventBus.boss_phase_changed.emit(1)
	DamageNumber.spawn(get_parent(), global_position + Vector2(0, -90), "THE EMBER WARDEN AWAKENS", Color(1.0, 0.5, 0.2))
	AudioManager.play_music("boss")   # was "combat_theme": never registered, so it played nothing


func _on_boss_defeated(_e: Enemy) -> void:
	defeated = true
	QuestManager.register_flag("boss_defeated")
	boss = null
	if _ring:
		_ring.default_color = Color(0.45, 0.45, 0.5, 0.35)
	DamageNumber.spawn(get_parent(), global_position + Vector2(0, -70), "BOSS DEFEATED!", Color(1.0, 0.85, 0.3))
	EventBus.boss_defeated.emit()
	AudioManager.play_music("meadow")  # was "biome_meadows": never registered
