package iso_bmff_example
/*
	This file is an example that parses an ISO base media file (mp4/m4a/...) and prints the parse tree.

	The example is in the public domain (unlicense.org).
*/

import "core:mem"
import "core:os"
import "core:fmt"
import isom ".."

parse_metadata := true

_main :: proc() {
	using fmt

	EXE_NAME := os.args[0]

	if len(os.args) == 1 {
		println("ISO Base Media File Format parser example")
		printf("Usage: %v [isom filename]\n\n", EXE_NAME)
		os.exit(1)
	}

	file := os.args[1]
	f, err := isom.open(file)
	defer isom.close(f)

	if err != .None {
		printf("Couldn't open '%v'\n", file)
		return
	}

	printf("\nOpened '%v'\n", file)
	printf("\tFile size: %v\n", f.file_info.size)
	printf("\tCreated:   %v\n", f.file_info.creation_time)
	printf("\tModified:  %v\n", f.file_info.modification_time)

	println("\n-=-=-=-=-=-=- PARSED FILE -=-=-=-=-=-=-")
	e := isom.parse(f, parse_metadata)
	isom.print(f)
	println("\n-=-=-=-=-=-=- PARSED FILE -=-=-=-=-=-=-")
	printf("Parse Error: %v\n\n", e)

	when false {
		println("----")
		for v in isom.FourCC {
			printf("[%v]: 0x%08x\n", isom._string(v), int(v))
		}
	}
}

main :: proc() {
	using fmt

	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)

	_main()

	if len(track.allocation_map) > 0 {
		println()
		for _, v in track.allocation_map {
			printf("Leaked %v bytes @ loc %v\n", v.size, v.location)
		}
	}
}