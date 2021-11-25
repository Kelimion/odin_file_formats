/*
	Copyright 2021 Jeroen van Rijn <nom@duclavier.com>.
	Made available under Odin's BSD-3 license.

	List of contributors:
		Jeroen van Rijn: Initial implementation.

	A test suite for:
	- The EBML/Matroska/WebM package
*/
package test_core_image

import "core:testing"
import "core:mem"
import "core:fmt"
import "../../ebml"

TEST_count := 0
TEST_fail  := 0

EBML_Test :: struct {
	filename: string,
	subtitles: []string,

}

EBML_Tests :: []EBML_Test{
	{
		filename  = "assets/ebml/subtitles.mkv",
		subtitles = { "hun", "ger", "fre", "spa", "ita", "jpn"},
	},
	{
		filename  = "assets/ebml/damaged.mkv",
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
	ebml_test(&t)
	fmt.printf("%v/%v tests successful.\n", TEST_count - TEST_fail, TEST_count)
}

@test
ebml_test :: proc(t: ^testing.T) {

	error_msg: string

	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)

	for test in EBML_Tests {
		ebml_test_file(t, test)

		for _, v in track.allocation_map {
			error_msg = fmt.tprintf("%v test leaked %v bytes @ loc %v.", test.filename, v.size, v.location)
			expect(t, false, error_msg)
		}
	}
}

ebml_test_file :: proc(t: ^testing.T, test: EBML_Test) -> (err: ebml.Error) {
	f:         ^ebml.EBML_File
	error_msg: string

	f, err = ebml.open(test.filename)
	defer ebml.close(f)

	error_msg = fmt.tprintf("ebml.open(%v) returned %v", test.filename, err)
	expect(t, err == .None, error_msg)
	if err != .None { return err }

	if err == .None {
		/*
			We opened the file, let's parse it.
		*/
		err = ebml.parse(f)

		error_msg = fmt.tprintf("ebml.open(%v) returned %v", test.filename, err)
		expect(t, err == .None, error_msg)
		if err != .None { return err }

		/*
			TODO(Jeroen): Write node type helpers and helpers to find a given node by path,
			and then test specific fields.
		*/

		elements: [dynamic]^ebml.EBML_Element
		ebml.find_element_by_type(f, .Matroska_CodecID, &elements)
		defer delete(elements)

		for lang in test.subtitles {
			subtitle_found := false

			for element in elements {
				codec_type, codec_type_ok := element.payload.(ebml.String)
				expect(t, codec_type_ok, "Unexpected payload type.")

				if codec_type == "S_TEXT/UTF8" {
					/*
						Next element should be the language tag (nil for default language)
					*/
					if element.next != nil && element.next.id == .Matroska_Language {
						language, language_ok := element.next.payload.(string)
						expect(t, language_ok, "Unexpected payload type.")

						if language == lang {
							subtitle_found = true
						}
					}
				}
			}

			subtitle_error := fmt.tprintf("Subtitle not found: %v", lang)
			expect(t, subtitle_found, subtitle_error)
		}
	}
	return
}