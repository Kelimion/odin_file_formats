package ebml_example
/*
	This file is an example that parses an EBML file (mkv/webm/...) and prints the parse tree.

	The example is in the public domain (unlicense.org).
*/

import "core:mem"
import "core:os"
import "core:fmt"
import "core:time"
import ebml ".."
import "../../common"

parse_metadata       := true
skip_clusters        := false
return_after_cluster := false

_main :: proc() {
	EXE_NAME := os.args[0]

	if len(os.args) == 1 {
		fmt.println("EBML File Format parser example")
		fmt.printf("Usage: %v [ebml filename]\n\n", EXE_NAME)
		os.exit(1)
	}

	file := os.args[1]
	f, err := ebml.open(file)
	defer ebml.close(f)

	if err != .None {
		fmt.printf("Couldn't open '%v'\n", file)
		return
	}

	fmt.printf("\nOpened '%v'\n", file)
	fmt.printf("\tFile size: %v\n", f.file_info.size)
	fmt.printf("\tCreated:   %v\n", f.file_info.creation_time)
	fmt.printf("\tModified:  %v\n", f.file_info.modification_time)

	fmt.println("\n-=-=-=-=-=-=- PARSING FILE -=-=-=-=-=-=-")

	parse_start := time.now()
	e := ebml.parse(f, parse_metadata, skip_clusters, return_after_cluster)
	parse_end   := time.now()
	parse_diff  := time.diff(parse_start, parse_end)

	fmt.println("\n-=-=-=-=-=-=- PARSED FILE -=-=-=-=-=-=-")
	fmt.printf("Parse Error: %v\n\n", e)

	fmt.print_start := time.now()
	ebml.print(f)
	print_end   := time.now()
	print_diff  := time.diff(print_start, print_end)

	size: i64
	if return_after_cluster {
		if pos, pos_ok := common.get_pos(f.handle); !pos_ok {
			return
		} else {
			size = pos
		}
	} else {
		size = f.file_info.size
	}

	parse_speed := f64(time.Second) / f64(parse_diff) * f64(f.file_info.size) / f64(1024 * 1024)

	fmt.printf("Parse: %.2fs (%f MiB/s).\n", time.duration_seconds(parse_diff), parse_speed)
	fmt.printf("Print: %.2fs.\n", time.duration_seconds(print_diff))
}

main :: proc() {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)

	_main()

	if len(track.allocation_map) > 0 {
		fmt.println()
		for _, v in track.allocation_map {
			fmt.printf("%v Leaked %v bytes: %#v\n", v.location, v.size, (^ebml.EBML_Element)(v.memory)^)
		}
	}
}