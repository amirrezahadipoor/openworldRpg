extends Node
## EventBus — lightweight pub/sub so gameplay systems stay decoupled.
## Connect to these instead of reaching into other systems directly.

# --- Player ---
signal player_damaged(amount: float)
signal player_healed(amount: float)
signal player_died
signal player_dodged(player: Node)
signal player_leveled_up(new_level: int)
signal milestone_reached(level: int, title: String, text: String)

# --- Combat ---
signal attack_swung(attacker: Node)
signal enemy_hurt(enemy: Node, amount: float, dir: Vector2)
signal enemy_died(enemy: Node)

# --- Items / economy ---
signal item_picked_up(item_id: String, qty: int)
signal item_used(item_id: String)
signal gold_changed(amount: int)

# --- Quests / dialogue ---
signal quest_started(quest_id: String)
signal quest_updated(quest_id: String)
signal quest_completed(quest_id: String)
signal dialogue_opened
signal dialogue_closed

# --- Boss ---
signal boss_phase_changed(phase: int)
signal boss_defeated

# --- World ---
signal chunk_loaded(chunk_key: Vector2i)
signal chunk_unloaded(chunk_key: Vector2i)
signal interactable_used(node: Node)
signal gate_opened(gate_id: String)
signal world_interacted(node: Node)

# --- Meta ---
signal game_saved
signal game_loaded
