class_name ChunkRenderer
extends Node2D
## Renders an authored chunk from a packed GID grid using the biome tile atlas
## (single texture, draw_texture_rect_region per non-empty cell).
## GID convention (tools/worldgen): gid = biome * 11 + col + 1, 0 = empty.
## 8 columns carried the terrain (0-7); 8-10 are the decor scatter variants.

@export var grid_w := 32
@export var grid_h := 32
@export var tile_size := 32
@export var tiles: PackedInt32Array = PackedInt32Array()
@export var atlas: Texture2D
@export var base_color: Color = Color(0.24, 0.42, 0.25)

## Columns in the biome atlas. Must match tools/art/build_atlas.py COLS: a gid is
## biome * ATLAS_COLS + column + 1.
const ATLAS_COLS := 11

## Columns 8..10 are decoration (flowers, pebbles, scrub): they are drawn, never
## collided with, so the minimap and tests can tell ground from scatter.
const DECOR_COLUMN_FIRST := 8

var _cache_valid := false


func _ready() -> void:
	z_index = -10
	set_notify_transform(false)


func _draw() -> void:
	var w := float(grid_w * tile_size)
	var h := float(grid_h * tile_size)
	draw_rect(Rect2(0, 0, w, h), base_color)
	if atlas == null or tiles.is_empty():
		return
	var ts := float(tile_size)
	for i in tiles.size():
		var gid := tiles[i]
		if gid <= 0:
			continue
		var col := (gid - 1) % ATLAS_COLS
		var row := (gid - 1) / ATLAS_COLS
		var x := float((i % grid_w) * tile_size)
		var y := float((i / grid_w) * tile_size)
		draw_texture_rect_region(
			atlas,
			Rect2(x, y, ts, ts),
			Rect2(float(col) * ts, float(row) * ts, ts, ts)
		)
