package iso_bmff
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


	A from-scratch implementation of ISO base media file format (ISOM),
	as specified in ISO/IEC 14496-12, Fifth edition 2015-12-15.
	The identical text is available as ISO/IEC 15444-12 (JPEG 2000, Part 12).

	See: https://www.iso.org/standard/68960.html and https://www.loc.gov/preservation/digital/formats/fdd/fdd000079.shtml

	This file is a debug helper that prints the parse tree.
*/

import "core:fmt"
import "../common"

print_itunes_metadata :: proc(tag: iTunes_Metadata, level := int(0)) {
	#partial switch tag.type {
		case .Text: println(level, string(tag.data.(cstring)))
		case .JPEG: printf(level, "Thumbnail Type: JPEG\n")
		case .PNG:  printf(level, "Thumbnail Type: PNG\n")
		case:
			switch v in tag.data {
			case [dynamic]u8:
				if common.is_printable(v[:]) {
					println(level, string(v[:]))
				} else {
					println(level, "Bytes:", v)
				}
			case iTunes_Track:
				printf(level, "Track: %v/%v\n", v.current, v.disk_total)

			case iTunes_Disk:
				printf(level, "Disk:  %v/%v\n", v.current, v.total)

			case cstring:
				// Already handled above.
			}

	}
}

print_mdhd :: proc(mdhd: $T, level := int(0)) {
	#assert(T == MDHD_V0 || T == MDHD_V1)

	seconds := f64(mdhd.duration) / f64(mdhd.time_scale)
	printf(level, "duration: %v seconds\n", seconds)
	printf(level, "created:  %v (%v)\n",   _time(mdhd.creation_time), mdhd.creation_time)
	printf(level, "modified: %v (%v)\n",   _time(mdhd.modification_time), mdhd.modification_time)
	printf(level, "language: %v\n",        _string(mdhd.language))
	printf(level, "quality:  %v\n",        mdhd.quality)
}

print_elst :: proc(elst: $T, level := int(0)) {
	#assert(T == ELST_V0 || T == ELST_V1)
	for e, i in elst.entries {
		printf(level, "edit: %v\n", i)
		printf(level + 1, "segment_duration: %v\n",    e.segment_duration)
		printf(level + 1, "media_time:       %v\n",    e.media_time)
		printf(level + 1, "media_rate:       %v/%v\n", e.media_rate.x, e.media_rate.y)
	}
}

print_tkhd :: proc(f: ^BMFF_File, tkhd: $T, level := int(0)) {
	#assert(T == TKHD_V0 || T == TKHD_V1)

	seconds := f64(tkhd.duration) / f64(f.time_scale)

	printf(level, "track:    %v\n",         tkhd.track_id)
	printf(level, "flags:    %v\n",         tkhd.flags_3)
	printf(level, "duration: %v seconds\n", seconds)
	printf(level, "created:  %v (%v)\n",    _time(tkhd.creation_time), tkhd.creation_time)
	printf(level, "modified: %v (%v)\n",    _time(tkhd.modification_time), tkhd.modification_time)

	if tkhd.volume == 0 {
		printf(level, "width:    %v\n",     _f64(tkhd.width))
		printf(level, "height:   %v\n",     _f64(tkhd.height))
	} else {
		printf(level, "volume:   %v\n",     _f64(tkhd.volume))
	}
	printf(level, "matrix:   %v\n",         _matrix(tkhd.view_matrix))
}

print_mvhd :: proc(mvhd: $T, level := int(0)) {
	#assert(T == MVHD_V0 || T == MVHD_V1)

	seconds := f64(mvhd.duration) / f64(mvhd.time_scale)

	printf(level, "preferred_rate:   %v\n",         _f64(mvhd.preferred_rate))
	printf(level, "preferred_volume: %v\n",         _f64(mvhd.preferred_volume))
	printf(level, "duration:         %v seconds\n", seconds)
	printf(level, "created:          %v (%v)\n",    _time(mvhd.creation_time), mvhd.creation_time)
	printf(level, "modified:         %v (%v)\n",    _time(mvhd.modification_time), mvhd.modification_time)
	printf(level, "matrix:           %v\n",         _matrix(mvhd.view_matrix))
	printf(level, "next track id:    %v\n",         mvhd.next_track_id)
}

print_ftyp :: proc(ftyp: FTYP, level := int(0)) {
	printf(level, "Major Brand:   %v (0x%08x)\n", _string(ftyp.brand), int(ftyp.brand))
	printf(level, "Minor Version: %v.%v.%v.%v\n", ftyp.version.x, ftyp.version.y, ftyp.version.z, ftyp.version.w)

	println(level, "Compat:")
	for compat in ftyp.compatible {
		println(level + 1, _string(compat))
	}
}

print_hdlr :: proc(hdlr: $T, level := int(0)) {
	#assert(T == HDLR)

	if hdlr.component_type != nil {
		printf(level, "Type:         %v\n", _string(hdlr.component_type))
	}

	if hdlr.component_subtype != nil {
		printf(level, "Sub-Type:     %v\n", _string(hdlr.component_subtype))
	}

	if hdlr.component_manufacturer != nil {
		printf(level, "Manufacturer: %v\n", _string(hdlr.component_manufacturer))
	}

	if len(hdlr.name) > 0 {
		printf(level, "Name:         %v\n", hdlr.name)
	}
}

print_chpl :: proc(f: ^BMFF_File, chpl: Chapter_List, level := int(0)) {
	time_scale := f.time_scale if chpl.version == 0 else 10_000_000

	for chapter, i in chpl.chapters {
		start := f64(chapter.timestamp) / f64(time_scale)

		printf(level, "Chapter #: %v\n", i + 1)
		printf(level + 1, "Title: %v\n", chapter.title)
		printf(level + 1, "Start: %.2f seconds\n", start)
		if i + 1 < len(chpl.chapters) {
			println(0)
		}
	}

}

print_box_header :: proc(box: ^BMFF_Box, level := int(0)) {
	box_type := fmt.tprintf("UUID: %v", _string(box.uuid)) if box.type == .UUID else _string(box.type)
	printf(level, "[%v] Pos: %d, Size: %d\n", box_type, box.offset, box.payload_size)
}

print_box :: proc(f: ^BMFF_File, box: ^BMFF_Box, level := int(0), print_siblings := false, recurse := false) {
	box := box

	for box != nil {
		print_box_header(box, level)

		#partial switch v in box.payload {
		case FTYP:
			print_ftyp(v, level + 1)

		case HDLR:
			print_hdlr(v, level + 1)

		case MDHD_V0:
			print_mdhd(v, level + 1)

		case MDHD_V1:
			print_mdhd(v, level + 1)

		case MVHD_V0:
			print_mvhd(v, level + 1)

		case MVHD_V1:
			print_mvhd(v, level + 1)

		case TKHD_V0:
			print_tkhd(f, v, level + 1)

		case TKHD_V1:
			print_tkhd(f, v, level + 1)

		case ELST_V0:
			print_elst(v, level + 1)

		case ELST_V1:
			print_elst(v, level + 1)

		case Chapter_List:
			print_chpl(f, v, level + 1)

		case:
			#partial switch box.type {
			case .Name:
				payload := box.payload.([dynamic]u8)[:]
				if len(payload) == 0 { return }

				if box.parent.type == .User_Data {
					printf(level + 1, "Name: %v\n", string(payload))
				}
			}

			if box.parent == f.itunes_metadata {
				if box.type != .iTunes_Extended {
					print_itunes_metadata(box.payload.(iTunes_Metadata), level + 1)	
				}
			}
		}

		if recurse && box.first_child != nil {
			print_box(f, box.first_child, level + 1, print_siblings, recurse)
		}

		if print_siblings {
			box = box.next
		}
	}
}

print :: proc(f: ^BMFF_File, box: ^BMFF_Box = nil, print_siblings := false, recurse := false) {
	if box != nil {
		print_box(f, box,    0, print_siblings, recurse)
	} else {
		print_box(f, f.root, 0, true, true)
	}
}

printf :: proc(level: int, format: string, args: ..any) {
	indent(level)
	fmt.printf(format, ..args)
}

println :: proc(level: int, args: ..any) {
	indent(level)
	fmt.println(..args)
}

indent :: proc(level: int) {
	TABS := []u8{
		'\t', '\t', '\t', '\t', '\t',
		'\t', '\t', '\t', '\t', '\t',
		'\t', '\t', '\t', '\t', '\t',
		'\t', '\t', '\t', '\t', '\t',
	}
	fmt.printf(string(TABS[:level]))
}