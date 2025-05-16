package iso_bmff_example
/*
	This is free and unencumbered software released into the public domain.

	Anyone is free to copy, modify, publish, use, compile, sell, or
	distribute this software, either in source code form or as a compiled
	binary, for any purpose, commercial or non-commercial, and by any
	means.

	In jurisdictions that recognize copyright laws, the author or authors
	of this software dedicate any and all copyright interest in the
	software to the public domain. We make this dedication for the benefit
	of the public at large and to the detriment of our heirs and
	successors. We intend this dedication to be an overt act of
	relinquishment in perpetuity of all present and future rights to this
	software under copyright law.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
	EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
	MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
	IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
	OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
	ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
	OTHER DEALINGS IN THE SOFTWARE.

	For more information, please refer to <https://unlicense.org/>


	This file is an example that parses an ISO base media file (mp4/m4a/...) and prints the parse tree.
*/

import "core:fmt"
import "core:mem"
import "core:os"
import "core:time"
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

	if err != nil {
		fmt.printf("Couldn't open '%v'. Err: %v\n", file, err)
		return
	}

	fmt.printf("\nOpened '%v'\n", file)
	fmt.printf("\tFile size: %v\n", f.file_info.size)
	fmt.printf("\tCreated:   %v\n", f.file_info.creation_time)
	fmt.printf("\tModified:  %v\n", f.file_info.modification_time)

	fmt.println("\n-=-=-=-=-=-=- PARSED FILE -=-=-=-=-=-=-")

	parse_start := time.now()
	e := bmff.parse(f, parse_metadata)
	parse_end   := time.now()
	parse_diff  := time.diff(parse_start, parse_end)

	print_start := time.now()
	bmff.print(f)
	print_end   := time.now()
	print_diff  := time.diff(print_start, print_end)

	fmt.println("\n-=-=-=-=-=-=- PARSED FILE -=-=-=-=-=-=-")
	fmt.printf("Parse Error: %v\n\n", e)

	parse_speed := f64(time.Second) / f64(parse_diff) * f64(f.file_info.size) / f64(1024 * 1024)
	fmt.printfln("Parse: %.3f ms (%f MiB/s).", 1_000 * time.duration_seconds(parse_diff), parse_speed)
	fmt.printfln("Print: %.3f ms.", 1_000 * time.duration_seconds(print_diff))
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