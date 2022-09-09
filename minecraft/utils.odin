package minecraft

import "core:math"

World_Coord  :: distinct [3]f64
Block_Coord  :: distinct [3]i64
Chunk_Coord  :: distinct [3]i64
Region_Coord :: distinct [2]i64

coordinates_block_to_chunk :: proc(block: Block_Coord) -> (chunk: Chunk_Coord) {
	chunk = {block.x >> 4, block.y >> 4, block.z >> 4}
	return
}

coordinates_block_to_chunk_relative :: proc(block: Block_Coord) -> (relative: Chunk_Coord) {
	chunk   := coordinates_to_chunk(block)
	relative = {block.x - chunk.x << 4, block.y - chunk.y << 4, block.z - chunk.z << 4}
	return
}

coordinates_world_to_chunk :: proc(world: World_Coord) -> (chunk: Chunk_Coord) {
	block := coordinates_to_block(world)
	return coordinates_to_chunk(block)
}


coordinates_to_block :: proc(world: World_Coord) -> (block: Block_Coord) {
	return Block_Coord{
		i64(math.floor(world.x)),
		i64(math.floor(world.y)),
		i64(math.floor(world.z)),
	}
}

coordinates_world_to_region :: proc(world: World_Coord) -> (region: Region_Coord) {
	return coordinates_to_region(coordinates_to_chunk(world))
}

coordinates_block_to_region :: proc(block: Block_Coord) -> (region: Region_Coord) {
	return coordinates_to_region(coordinates_to_chunk(block))
}

coordinates_chunk_to_region :: proc(chunk: Chunk_Coord) -> (region: Region_Coord) {
	return {chunk.x >> 5, chunk.z >> 5}
}

coordinates_to_chunk  :: proc {
	coordinates_world_to_chunk,
	coordinates_block_to_chunk,
}

coordinates_to_region :: proc {
	coordinates_world_to_region,
	coordinates_block_to_region,
	coordinates_chunk_to_region,
}

chunk_to_index :: proc(chunk: Chunk_Coord) -> (index: i64) {
	return chunk.x & 31 + chunk.z & 31 << 5
}