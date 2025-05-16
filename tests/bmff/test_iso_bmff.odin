/*
	Copyright 2021 Jeroen van Rijn <nom@duclavier.com>.
	Made available under Odin's BSD-3 license.

	List of contributors:
		Jeroen van Rijn: Initial implementation.

	A test suite for:
	- The ISO Base Media File Format package
*/
package test_core_image

import "core:testing"
import "core:mem"
import "core:fmt"
import "../../bmff"

TEST_count := 0
TEST_fail  := 0

ISOM_Test :: struct {
	filename: string,

}

ISOM_Tests :: []ISOM_Test{
	{
		filename = "assets/bmff/test_metadata.mp4",
	},
}

when ODIN_TEST {
	expect  :: testing.expect
	log     :: testing.log
} else {
	expect  :: proc(t: ^testing.T, condition: bool, message: string, loc := #caller_location) {
		fmt.printf("[%v] ", loc)
		TEST_count += 1
		if !condition {
			TEST_fail += 1
			fmt.println(message)
			return
		}
		fmt.println(" PASS")
	}
	log     :: proc(t: ^testing.T, v: any, loc := #caller_location) {
		fmt.printf("[%v] ", loc)
		fmt.printf("log: %v\n", v)
	}
}

main :: proc() {
	t := testing.T{}
	isom_test(&t)
	fmt.printf("%v/%v tests successful.\n", TEST_count - TEST_fail, TEST_count)
}

@test
isom_test :: proc(t: ^testing.T) {

	error_msg: string

	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)

	for test in ISOM_Tests {
		isom_test_file(t, test)

		for _, v in track.allocation_map {
			error_msg = fmt.tprintf("%v test leaked %v bytes @ loc %v.", test.filename, v.size, v.location)
			expect(t, false, error_msg)
		}
	}
}

isom_test_file :: proc(t: ^testing.T, test: ISOM_Test) -> (err: bmff.Error) {
	f:         ^bmff.BMFF_File
	error_msg: string

	f, err = bmff.open(test.filename)
	defer bmff.close(f)

	error_msg = fmt.tprintf("bmff.open(%v) returned %v", test.filename, err)
	expect(t, err == .None, error_msg)
	if err != .None { return err }

	if err == .None {
		/*
			We opened the file, let's parse it.
		*/
		err = bmff.parse(f)

		error_msg = fmt.tprintf("bmff.open(%v) returned %v", test.filename, err)
		expect(t, err == .None, error_msg)
		if err != .None { return err }

		/*
			TODO(Jeroen): Write node type helpers and helpers to find a given node by path,
			and then test specific fields.
		*/
	}
	return
}