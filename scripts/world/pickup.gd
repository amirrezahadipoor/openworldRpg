class_name Pickup
extends Area2D
## Loot pickup: gold or item. Bobs, magnetizes to the player when close,
## collects on contact (gold -> GameState.add_gold, item -> inventory).

enum Kind { GOLD, ITEM }

var kind: Kind = Kind.GOLD
var amount := 1
var item_id := ""

const MAGNET_RADIUS := 90.0
const MAGNET_SPEED := 320.0

var _bob_t := 0.0

@onready var sprite: Sprite2D = $Sprite


func setup_gold(value: int) -> void:
	kind = Kind.GOLD
	amount = value
	_apply_texture()


func setup_item(id: String, qty: int = 1) -> void:
	kind = Kind.ITEM
	item_id = id
	amount = qty
	_apply_texture()


func _apply_texture() -> void:
	if sprite == null:
		return
	if kind == Kind.GOLD:
		sprite.texture = load("res://assets/placeholder/gold.svg")
	else:
		sprite.texture = load("res://assets/placeholder/item_drop.svg")


func _ready() -> void:
	_apply_texture()


func _physics_process(delta: float) -> void:
	_bob_t += delta
	sprite.offset.y = sin(_bob_t * 3.0) * 3.0
	var player: Node2D = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var to_player := player.global_position - global_position
	if to_player.length() < MAGNET_RADIUS:
		global_position += to_player.normalized() * MAGNET_SPEED * delta


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if kind == Kind.GOLD:
		GameState.add_gold(amount)
		DamageNumber.spawn(get_parent(), global_position + Vector2(0, -14), "%d gold" % amount, Color(1.0, 0.85, 0.3))
	else:
		GameState.add_item(item_id, amount)
		EventBus.item_picked_up.emit(item_id, amount)
		DamageNumber.spawn(get_parent(), global_position + Vector2(0, -14), "+%s" % ItemsDB.item_name(item_id), Color(0.6, 0.85, 1.0))
	AudioManager.play_sfx("pickup")
	queue_free()
