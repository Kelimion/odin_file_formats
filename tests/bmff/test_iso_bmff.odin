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

import "../../bmff"

ISOM_Test :: string

ISOM_Tests :: []ISOM_Test{
	"assets/bmff/test_metadata.mp4",
}

@test
isom_test :: proc(t: ^testing.T) {
	for test in ISOM_Tests {
		err := isom_test_file(t, test)
		testing.expectf(t, err == .None, "isom_test_file(%v) returned %v", test, err)
	}
}

isom_test_file :: proc(t: ^testing.T, test: ISOM_Test) -> (err: bmff.Error) {
	f := bmff.open(test) or_return
	defer bmff.close(f)
	/*
		We opened the file, let's parse it.
	*/
	bmff.parse(f) or_return
	/*
		TODO(Jeroen): Write node type helpers and helpers to find a given node by path,
		and then test specific fields.
	*/
	return
}