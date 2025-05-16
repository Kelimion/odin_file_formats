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


	A test suite for the EBML/Matroska/WebM package
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
		testing.expectf(t, err == nil, "ebml_test_file(%v) returned %v", test.filename, err)
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