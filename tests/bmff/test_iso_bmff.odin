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


	A test suite for the ISO Base Media File Format package
*/
package test_bmff
import "core:testing"

import "../../bmff"

ISOM_Test :: string

ISOM_Tests :: []ISOM_Test{
	"../assets/bmff/test_metadata.mp4",
}

@test
isom_test :: proc(t: ^testing.T) {
	for test in ISOM_Tests {
		err := isom_test_file(t, test)
		testing.expectf(t, err == nil, "isom_test_file(%v) returned %v", test, err)
	}
}

isom_test_file :: proc(t: ^testing.T, test: ISOM_Test) -> (err: bmff.Error) {
	f := bmff.open(test) or_return
	defer bmff.close(f)

	bmff.parse(f) or_return

	// TODO(Jeroen): Write node type helpers and helpers to find a given node by path.
	return
}