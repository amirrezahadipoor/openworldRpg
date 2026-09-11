class_name Minimap
extends Control
## Real terrain minimap centered on the player. Samples authored chunk tile
## grids (biome palette fallback for placeholder chunks), draws lit waypoints
## and the player facing arrow. Redraws at a fixed interval, not per frame.

const WORLD_SPAN := 2304.0  # world px shown edge to edge
## 72 cells over 2304 px is a 32 px sample grid, which is finer than the map is
## wide: each cell was drawn at ~1.4 px and the whole thing cost 5184 texture
## lookups every 0.3 s for detail nobody could see (audit L3). 48 cells still
## resolve the authored 32 px tiles one-to-one once the map is at full size.
const CELLS := 48
const REFRESH := 0.3

var player: Node2D
var streamer: ChunkStreamer

var _timer := REFRESH  # draw immediately once player is set
var _drawn_once := false

## Per-column colors for authored tiles (index by (gid-1) % ChunkRenderer.ATLAS_COLS).
const BIOME_BASE := [
	Color(0.27, 0.45, 0.28),   # meadow
	Color(0.50, 0.42, 0.31),   # barrens
	Color(0.62, 0.66, 0.72),   # frost
]
const HAZARD_COLOR := [
	Color(0.23, 0.44, 0.58),   # water
	Color(0.80, 0.38, 0.15),   # lava
	Color(0.55, 0.70, 0.82),   # ice
]
const PATH_COLOR := [
	Color(0.45, 0.38, 0.27),
	Color(0.36, 0.29, 0.24),
	Color(0.50, 0.53, 0.58),
]
const ROCK_COLOR := [
	Color(0.13, 0.25, 0.13),
	Color(0.25, 0.21, 0.18),
	Color(0.19, 0.27, 0.30),
]
const WALL_COLOR := Color(0.30, 0.29, 0.27)


func setup(p: Node2D, s: ChunkStreamer) -> void:
	player = p
	streamer = s


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	_timer += delta
	if _timer >= REFRESH or not _drawn_once:
		_timer = 0.0
		_drawn_once = true
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color(0.04, 0.05, 0.07, 0.78))
	if player == null:
		return

	var scale_px := size.x / WORLD_SPAN
	var origin := player.global_position - Vector2(WORLD_SPAN, WORLD_SPAN) * 0.5
	var cell_world := WORLD_SPAN / float(CELLS)
	var cell_px := size / Vector2(CELLS, CELLS)

	for cy in CELLS:
		var wy := origin.y + (float(cy) + 0.5) * cell_world
		for cx in CELLS:
			var wx := origin.x + (float(cx) + 0.5) * cell_world
			var c := _sample(Vector2(wx, wy))
			if c.a > 0.01:
				draw_rect(Rect2(Vector2(float(cx), float(cy)) * cell_px, cell_px + Vector2(0.5, 0.5)), c)

	# Lit waypoints.
	for wp_id in Waypoint.registry.keys():
		if not bool(GameState.quest_flags.get("wp_%s" % wp_id, false)):
			continue
		var pos: Vector2 = Waypoint.registry[wp_id]
		var local := (pos - origin) * scale_px
		if rect.has_point(local):
			draw_circle(local, 3.2, Color(1.0, 0.62, 0.2))
			draw_circle(local, 1.4, Color(1.0, 0.9, 0.6))

	# Rumoured secrets: somewhere out there, unhinted in position but marked on the
	# map once you have been told they exist.
	for sid in SecretsDB.unfound():
		if not SecretsDB.is_rumoured(String(sid)):
			continue
		var probe := (SecretsDB.position_of(String(sid)) - origin) * scale_px
		if rect.has_point(probe):
			draw_rect(Rect2(probe - Vector2(2.0, 2.0), Vector2(4.0, 4.0)),
				Color(0.75, 0.85, 1.0, 0.7))

	# Player arrow.
	var center := size * 0.5
	var facing := Vector2.DOWN
	if player is Player:
		facing = (player as Player).facing
	var tip := center + facing * 9.0
	var side_a := center + facing.rotated(2.5) * 7.0
	var side_b := center + facing.rotated(-2.5) * 7.0
	draw_colored_polygon(PackedVector2Array([tip, side_a, side_b]), Color(1, 1, 1, 0.95))

	# Legend. The map has always drawn six different colours and never once said
	# what any of them meant — read at a glance, gold is a campfire, green is the
	# meadow, red is something that will hurt you.
	_draw_legend(rect)

	# Frame + north mark.
	draw_rect(rect, Color(0.85, 0.75, 0.5, 0.55), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(size.x * 0.5 - 5.0, 14.0), "N",
		HORIZONTAL_ALIGNMENT_CENTER, -1, 13, Color(1, 0.95, 0.8, 0.9))


func _draw_legend(rect: Rect2) -> void:
	## The map has always drawn six colours and never said what any of them meant.
	## Read at a glance: gold is a lit campfire, red is something that will bite.
	var items := [
		[Color(1.0, 0.62, 0.2), "fire"],
		[Color(0.80, 0.38, 0.15), "hazard"],
		[Color(0.30, 0.29, 0.27), "wall"],
		[Color(0.75, 0.85, 1.0), "rumour"],
	]
	var font := ThemeDB.fallback_font
	var y := rect.position.y + 8.0
	for it in items:
		draw_rect(Rect2(Vector2(8.0, y + 2.0), Vector2(9.0, 9.0)), it[0])
		draw_string(font, Vector2(21.0, y + 11.0), String(it[1]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.72))
		y += 15.0


func _sample(wpos: Vector2) -> Color:
	var key := Vector2i(
		int(floorf(wpos.x / float(ChunkStreamer.CHUNK_SIZE))),
		int(floorf(wpos.y / float(ChunkStreamer.CHUNK_SIZE)))
	)
	var chunk := streamer.get_loaded_chunk(key) if streamer != null else null
	var renderer := chunk.get_node_or_null("Renderer") as ChunkRenderer if chunk != null else null
	if renderer != null and not renderer.tiles.is_empty():
		var local := wpos - Vector2(key) * float(ChunkStreamer.CHUNK_SIZE)
		var tx := clampi(int(local.x / 32.0), 0, renderer.grid_w - 1)
		var ty := clampi(int(local.y / 32.0), 0, renderer.grid_h - 1)
		var gid: int = renderer.tiles[ty * renderer.grid_w + tx]
		if gid <= 0:
			return renderer.base_color  # bare ground
		# Decode against the same atlas width the renderer uses (it grew to 11
		# columns with the decor pass); clamp biome so a future atlas row can
		# never index the palette arrays out of range.
		var col := (gid - 1) % ChunkRenderer.ATLAS_COLS
		var biome := clampi((gid - 1) / ChunkRenderer.ATLAS_COLS, 0, BIOME_BASE.size() - 1)
		match col:
			2:
				return PATH_COLOR[biome]
			3:
				return HAZARD_COLOR[biome]
			4:
				return ROCK_COLOR[biome]
			5:
				return WALL_COLOR
			_:
				return BIOME_BASE[biome]
	# Placeholder / unloaded: deterministic biome guess (matches streamer).
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) & 0x7FFFFFFF
	return BIOME_BASE[rng.randi_range(0, 2)].darkened(0.25)
