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
import "../../ebml"

EBML_Test :: struct {
	filename:  string,
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

@test
ebml_test :: proc(t: ^testing.T) {
	for test in EBML_Tests {
		err := ebml_test_file(t, test)
		testing.expectf(t, err == .None, "ebml_test_file(%v) returned %v", test.filename, err)
	}
}

ebml_test_file :: proc(t: ^testing.T, test: EBML_Test) -> (err: ebml.Error) {
	f := ebml.open(test.filename) or_return
	defer ebml.close(f)

	/*
		We opened the file, let's parse it.
	*/
	ebml.parse(f) or_return

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
			testing.expect(t, codec_type_ok, "Unexpected payload type.")

			if codec_type == "S_TEXT/UTF8" {
				/*
					Next element should be the language tag (nil for default language)
				*/
				if element.next != nil && element.next.id == .Matroska_Language {
					language, language_ok := element.next.payload.(string)
					testing.expect(t, language_ok, "Unexpected payload type.")

					if language == lang {
						subtitle_found = true
					}
				}
			}
		}
		testing.expectf(t, subtitle_found, "Subtitle %v not found.", lang)
	}
	return
}