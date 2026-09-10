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
signal npc_barked(npc_id: String, display_name: String, text: String)

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
## Fired when a boss floor instantiates its boss, with the roster id and the
## name the player will read. Lets the game speak the antagonist's line.
signal boss_encounter_started(boss_id: String, display_name: String)
## Millhaven burns once the player leaves the valley (MQ020). World state, not
## a cutscene: the camp literally loses its elder.
signal camp_burned

# --- World ---
signal chunk_loaded(chunk_key: Vector2i)
signal chunk_unloaded(chunk_key: Vector2i)
signal interactable_used(node: Node)
signal gate_opened(gate_id: String)
signal world_interacted(node: Node)

## Phase F6: secrets. `secret_found` fires once per secret, ever; `secret_hinted`
## fires when a carving or landmark points at the next one.
signal secret_found(secret_id: String, secret_name: String, index: int, total: int)
signal secret_hinted(secret_id: String)

# --- Meta ---
signal game_saved
signal game_loaded
