/*
	Copyright 2022 Jeroen van Rijn <nom@duclavier.com>.

	Made available under Odin's BSD-3 license.

	A from-scratch implementation of the Minecraft NBT format and associated helpers.
	Very work-in-progress, but it works with MC 1.19.2 data.
*/
package minecraft

import "core:path/filepath"
import "core:strings"
import "core:os"
import "core:log"

World :: struct {
	name:   string,
	path:   string,

	level:  NBT,
	intern: strings.Intern `fmt:"-"`,
}

World_Error :: enum {
	None                    = 0,
	Path_Not_Found          = 1,
	World_Not_Found,

	Level_Data_Missing      = 100,
	Region_Dir_Missing,
	Region_File_Missing,
	Region_File_Corrupt,
	Chunk_Not_In_Region,
}

Error :: union {
	World_Error,
	NBT_Error,
}

REQUIRED_PATHS := map[string]Error{
	"level.dat" = .Level_Data_Missing,
	"region"    = .Region_Dir_Missing,
}

open_world_from_path :: proc(path: string) -> (world: ^World, err: Error) {
	if !os.is_dir(path) {
		log.errorf("%v is not a directory.", path)
		return nil, .Path_Not_Found
	}

	for required in REQUIRED_PATHS {
		required_path := filepath.join({path, required})
		defer delete(required_path)

		if !os.exists(required_path) {
			log.errorf("%v not found.", required_path)
			return nil, REQUIRED_PATHS[required]
		}
	}

	world = new(World)
	strings.intern_init(&world.intern)
	world.path, _ = strings.intern_get(&world.intern, path)

	level_data_path := filepath.join({world.path, "level.dat"})
	defer delete(level_data_path)

	world.level, err = parse_nbt_from_path(level_data_path, .GZIP)
	return
}

open_world_from_instance :: proc(instance_path: string, world_name: string) -> (world: ^World, err: Error) {
	path := filepath.join({instance_path, "saves", world_name})
	defer delete(path)
	return open_world_from_path(path)
}
open_world :: proc{open_world_from_instance, open_world_from_path}


destroy_world :: proc(world: ^World) {
	if world == nil {
		return
	}
	strings.intern_destroy(&world.intern)
	destroy_nbt(world.level)
	free(world)
}
destroy :: proc{destroy_world, destroy_nbt, destroy_nbt_tag, destroy_region}