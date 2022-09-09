package minecraft_example

import "core:fmt"
import "core:mem"
import mc "ff:minecraft"

DO_LOG :: false
when DO_LOG {
	import "core:log"
}

MC_LOCATION :: "<Path to MC installation>"
MC_WORLD    :: "Hermitcraft S9 Blank"

_main :: proc() {
	world, err := mc.open_world(MC_LOCATION, MC_WORLD)
	defer mc.destroy(world)
	if err != nil {
		fmt.printf("Error opening world: %v, %v\n", MC_WORLD, err)
		return
	}

	player_pos, player_pos_ok := mc.get_value_by_name(world.level.root, {"", "Data", "Player", "Pos"})
	if !player_pos_ok {
		fmt.println("Unable to locate Data/Player/Pos in level.dat")
		return
	}

	player_coord := mc.World_Coord{}

	if v, v_ok := player_pos.(mc.NBT_List); !v_ok {
		fmt.println("Expected Data/Player/Pos to be a []Double")
		return
	} else if len(v.value) != 3 {
		fmt.println("Expected Data/Player/Pos to be [3]Double")
		return
	} else {
		for f, i in v.value {
			player_coord[i] = f.(f64)
		}
	}

	b   := mc.coordinates_to_block(player_coord)
	c   := mc.coordinates_to_chunk(b)
	idx := mc.chunk_to_index(c)
	cr  := mc.coordinates_block_to_chunk_relative(b)
	rc  := mc.coordinates_to_region(c)

	fmt.printf("XYZ:       %v\n", player_coord)
	fmt.printf("Block:     %v\n", b)
	fmt.printf("Chunk rel: %v\n", cr)
	fmt.printf("Chunk:     %v (idx: %v)\n", c, idx)
	fmt.printf("Region:    %v\n", rc)

	// Overworld
	reg, reg_err := mc.open_region(world, "", player_coord)
	defer mc.destroy(reg)

	if reg_err != nil {
		fmt.printf("Error opening Region for %v: %v\n", player_coord, reg_err)
		return
	}

	fmt.println(" ---  ---  ---  ---  ---  ---  --- ")
	fmt.printf("Region size: %v bytes\n", len(reg.raw))

	chunk, chunk_err := mc.get_chunk_from_region(reg, c)
	defer mc.destroy(chunk)
	if chunk_err != nil {
		fmt.printf("Error opening chunk: %v, %v\n", c, chunk_err)
		return
	}
	fmt.printf("%#v\n", chunk.root.value)
}

main :: proc() {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)

	when DO_LOG {
		logger := log.create_console_logger(log.Level.Debug, log.Default_File_Logger_Opts)
		context.logger = logger
	}

	_main()

	when DO_LOG {
		log.destroy_console_logger(logger)
	}

	for _, leak in track.allocation_map {
		fmt.printf("%v leaked %v bytes\n", leak.location, leak.size)
	}
	for bad_free in track.bad_free_array {
		fmt.printf("%v allocation %p was freed badly\n", bad_free.location, bad_free.memory)
	}
}