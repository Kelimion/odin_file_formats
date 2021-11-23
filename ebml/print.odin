package ebml
/*
	Copyright 2021 Jeroen van Rijn <nom@duclavier.com>.
	Made available under Odin's BSD-3 license.

	A from-scratch implementation of the Extensible Binary Meta Language (EBML),
	as specified in [IETF RFC 8794](https://www.rfc-editor.org/rfc/rfc8794).

	The EBML format is the base format upon which Matroska (MKV) and WebM are based.

	This file contains print helpers.
*/

import "core:io"
import "core:fmt"
import "core:strings"
import "../common"

_string_common :: common._string

@(thread_local)
string_builder: strings.Builder

@(thread_local)
global_writer:  io.Writer

@(init)
_init_string_builder :: proc() {
	strings.init_builder(&string_builder)
	global_writer = strings.to_writer(&string_builder)
}

_get_string :: proc() -> string {
	return strings.to_string(string_builder)
}

flush_builder_to_output :: proc() {
	fmt.println(_get_string())
	strings.reset_builder(&string_builder)
}

printf :: proc(level: int, format: string, args: ..any) {
	indent(level)
	fmt.wprintf(global_writer, format, ..args)
}

println :: proc(level: int, args: ..any) {
	indent(level)
	fmt.wprintln(global_writer, ..args)
}

indent :: proc(level: int) {
	TABS := []u8{
		'\t', '\t', '\t', '\t', '\t',
		'\t', '\t', '\t', '\t', '\t',
		'\t', '\t', '\t', '\t', '\t',
		'\t', '\t', '\t', '\t', '\t',
	}
	fmt.wprintf(global_writer, "%v", string(TABS[:level]))
}

print_element_header :: proc(element: ^EBML_Element, level := int(0)) {
	printf(level, "[%v] Pos: %d, Size: %d\n", _string(element.id), element.offset, element.payload_size)
}

print_element :: proc(f: ^EBML_File, element: ^EBML_Element, level := int(0), print_siblings := false, recurse := false) {
	element := element

	for element != nil {
		print_element_header(element, level)

		#partial switch element.type {
		case .Unsigned:
			if val, ok := element.payload.(u64); ok {
				printf(level + 1, "Value: %v\n", val)
			}

		case .Signed:
			if val, ok := element.payload.(i64); ok {
				printf(level + 1, "Value: %v\n", val)
			}

		case .Float:
			if val, ok := element.payload.(f64); ok {
				printf(level + 1, "Value: %.2f\n", val)
			}

		case .String:
			if val, ok := element.payload.(String); ok {
				printf(level + 1, "Value: %v\n", val)
			}

		case .UTF_8:
			if val, ok := element.payload.(string); ok {
				printf(level + 1, "Value: %v\n", val)
			}

		case .Binary:
			if val, ok := element.payload.([dynamic]u8); ok {
				#partial switch element.id {
				case .SeekID:
					seek_id := u64be(0)
					for v in val {
						seek_id <<= 8
						seek_id  += u64be(v)
					}
					printf(level + 1, "Value: %v\n", _string(EBML_ID(seek_id)))

				case:
					if len(val) > 20 {
						printf(level + 1, "Value: %X...\n", val[:20])
					} else {
						printf(level + 1, "Value: %X\n", val)
					}
				}
			}

		case .UUID:
			if uuid, ok := element.payload.(UUID); ok {
				printf(level + 1, "UUID: %v\n", _string_common(uuid))
			}

		case .Time:
			if datetime, ok := element.payload.(Time); ok {
				printf(level + 1, "Time: %v\n", datetime)
			}

		case .Matroska_Track_Type:
			if val, ok := element.payload.(Matroska_Track_Type); ok {
				printf(level + 1, "Value: %v\n", val)
			}

		}

		/*
			TODO: Make this some sort of queue so we don't blow the stack.
		*/
		if recurse && element.first_child != nil {
			print_element(f, element.first_child, level + 1, print_siblings, recurse)
		}

		if print_siblings  {
			element = element.next
		}
	}
}

print :: proc(f: ^EBML_File, element: ^EBML_Element = nil, print_siblings := false, recurse := false) {
	if element != nil {
		print_element(f, element, 0, print_siblings, recurse)
	} else {
		for document, doc_idx in f.documents {
			println(0, "")
			printf(0, "Document: #%v\n", doc_idx)
			print_element(f, document.header, 0, true, true)
			flush_builder_to_output()

			print_element(f, document.body,   0, true, true)
			flush_builder_to_output()
		}
	}
}