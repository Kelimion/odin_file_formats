package iso_bmff_example
/*
	This file is an example that parses an ISO base media file (mp4/m4a/...) and prints the parse tree.

	The example is in the public domain (unlicense.org).
*/

import "core:mem"
import "core:os"
import "core:fmt"
import bmff ".."

parse_metadata := true

_main :: proc() {
	EXE_NAME := os.args[0]

	if len(os.args) == 1 {
		fmt.println("ISO Base Media File Format parser example")
		fmt.printf("Usage: %v [bmff filename]\n\n", EXE_NAME)
		os.exit(1)
	}

	file := os.args[1]
	f, err := bmff.open(file)
	defer bmff.close(f)

	if err != .None {
		fmt.printf("Couldn't open '%v'\n", file)
		return
	}

	fmt.printf("\nOpened '%v'\n", file)
	fmt.printf("\tFile size: %v\n", f.file_info.size)
	fmt.printf("\tCreated:   %v\n", f.file_info.creation_time)
	fmt.printf("\tModified:  %v\n", f.file_info.modification_time)

	fmt.println("\n-=-=-=-=-=-=- PARSED FILE -=-=-=-=-=-=-")
	e := bmff.parse(f, parse_metadata)
	bmff.print(f)
	fmt.println("\n-=-=-=-=-=-=- PARSED FILE -=-=-=-=-=-=-")
	fmt.printf("Parse Error: %v\n\n", e)

	when false {
		println("----")
		for v in bmff.FourCC {
			fmt.printf("[%v]: 0x%08x\n", bmff._string(v), int(v))
		}
	}
}

main :: proc() {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)

	_main()

	if len(track.allocation_map) > 0 {
		fmt.println()
		for _, v in track.allocation_map {
			fmt.printf("Leaked %v bytes @ loc %v\n", v.size, v.location)
		}
	}
}