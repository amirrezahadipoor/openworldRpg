class_name Biome
extends RefCounted
## Biome geography, shared by the generator and the game.
##
## tools/worldgen/build_world.py stamps each chunk with a biome id, and this is
## the same function in GDScript so runtime code (music, ambience, world flags)
## agrees with the map instead of guessing. The borders are slow sinusoids, not
## straight lines: winter seeps south around x = 1-2 and the barrens wedge in
## from the south-east, which is what makes the seams read as a coastline rather
## than a grid.
##
## KEEP THIS IN SYNC WITH tools/worldgen/build_world.py (_wobble / frost_line /
## barrens_line / biome_of). tests/world_map_test.gd checks them against the
## generated chunk files.

const MEADOW := 0
const BARRENS := 1
const FROST := 2

const BIOME_NAMES := {
	MEADOW: "meadow", BARRENS: "barrens", FROST: "frost",
}


static func _wobble(v: float, phase: float, amp: float = 1.2, freq: float = 0.9) -> int:
	return int(round(sin(v * freq + phase) * amp))


static func frost_line(cx: int) -> int:
	return -1 + _wobble(float(cx), 0.4)


static func barrens_line(cy: int) -> int:
	return 2 + _wobble(float(cy), -0.7, 1.2, 1.1)


static func biome_of(cx: int, cy: int) -> int:
	if cy <= frost_line(cx):
		return FROST
	if cx >= barrens_line(cy):
		return BARRENS
	return MEADOW


static func biome_name_of(cx: int, cy: int) -> String:
	return String(BIOME_NAMES.get(biome_of(cx, cy), "meadow"))


static func biome_at_position(pos: Vector2, chunk_size: int) -> int:
	return biome_of(int(floorf(pos.x / float(chunk_size))),
		int(floorf(pos.y / float(chunk_size))))


static func name_at_position(pos: Vector2, chunk_size: int) -> String:
	return String(BIOME_NAMES.get(biome_at_position(pos, chunk_size), "meadow"))
