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

import "base:runtime"
import "core:fmt"
import "core:reflect"
import "core:time"
import "../common"

print_box :: proc(f: ^BMFF_File, box: ^BMFF_Box, level := int(0), print_siblings := false, recurse := false) {
	box := box

	for box != nil {
		box_type := fmt.tprintf("UUID: %v", to_string(box.uuid)) if box.type == .UUID else to_string(box.type)
		printf(level, "[%v] Pos: %d, Size: %d\n", box_type, box.offset, box.payload_size)

		#partial switch v in box.payload {
		case FTYP:         print_ftyp(   v, level + 1)
		case HDLR:         print_hdlr(   v, level + 1)
		case MDHD_V0:      print_mdhd(   v, level + 1)
		case MDHD_V1:      print_mdhd(   v, level + 1)
		case MVHD_V0:      print_mvhd(   v, level + 1)
		case MVHD_V1:      print_mvhd(   v, level + 1)
		case TKHD_V0:      print_tkhd(f, v, level + 1)
		case TKHD_V1:      print_tkhd(f, v, level + 1)
		case ELST_V0:      print_elst(   v, level + 1)
		case ELST_V1:      print_elst(   v, level + 1)
		case Chapter_List: print_chpl(f, v, level + 1)
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
					#partial switch kind in box.payload {
					case iTunes_Metadata: print_itunes_metadata(kind, level + 1)
					}

				}
			}
		}

		if recurse && box.first_child != nil {
			print_box(f, box.first_child, level + 1, print_siblings, recurse)
		}

		box = box.next if print_siblings else nil
	}
}

print :: proc(f: ^BMFF_File, box: ^BMFF_Box = nil, print_siblings := false, recurse := false) {
	if box != nil {
		print_box(f, box,    0, print_siblings, recurse)
	} else {
		print_box(f, f.root, 0, true, true)
	}
}

@(private="package")
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

@(private="package")
print_mdhd :: proc(mdhd: $T, level := int(0)) {
	#assert(T == MDHD_V0 || T == MDHD_V1)

	seconds := f64(mdhd.duration) / f64(mdhd.time_scale)
	printf(level, "duration: %v seconds\n", seconds)
	printf(level, "created:  %v (%v)\n",   to_time(mdhd.creation_time), mdhd.creation_time)
	printf(level, "modified: %v (%v)\n",   to_time(mdhd.modification_time), mdhd.modification_time)
	printf(level, "language: %v\n",        to_string(mdhd.language))
	printf(level, "quality:  %v\n",        mdhd.quality)
}

@(private="package")
print_elst :: proc(elst: $T, level := int(0)) {
	#assert(T == ELST_V0 || T == ELST_V1)
	for e, i in elst.entries {
		printf(level, "edit: %v\n", i)
		printf(level + 1, "segment_duration: %v\n",    e.segment_duration)
		printf(level + 1, "media_time:       %v\n",    e.media_time)
		printf(level + 1, "media_rate:       %v/%v\n", e.media_rate.x, e.media_rate.y)
	}
}

@(private="package")
print_tkhd :: proc(f: ^BMFF_File, tkhd: $T, level := int(0)) {
	#assert(T == TKHD_V0 || T == TKHD_V1)

	seconds := f64(tkhd.duration) / f64(f.time_scale)

	printf(level, "track:    %v\n",         tkhd.track_id)
	printf(level, "flags:    %v\n",         tkhd.flags)
	printf(level, "duration: %v seconds\n", seconds)
	printf(level, "created:  %v (%v)\n",    to_time(tkhd.creation_time), tkhd.creation_time)
	printf(level, "modified: %v (%v)\n",    to_time(tkhd.modification_time), tkhd.modification_time)

	if tkhd.volume == 0 {
		printf(level, "width:    %v\n",     to_f64(tkhd.width))
		printf(level, "height:   %v\n",     to_f64(tkhd.height))
	} else {
		printf(level, "volume:   %v\n",     to_f64(tkhd.volume))
	}
	printf(level, "matrix:   %v\n",         to_matrix(tkhd.view_matrix))
}

@(private="package")
print_mvhd :: proc(mvhd: $T, level := int(0)) {
	#assert(T == MVHD_V0 || T == MVHD_V1)

	seconds := f64(mvhd.duration) / f64(mvhd.time_scale)

	printf(level, "preferred_rate:   %v\n",         to_f64(mvhd.preferred_rate))
	printf(level, "preferred_volume: %v\n",         to_f64(mvhd.preferred_volume))
	printf(level, "duration:         %v seconds\n", seconds)
	printf(level, "created:          %v (%v)\n",    to_time(mvhd.creation_time), mvhd.creation_time)
	printf(level, "modified:         %v (%v)\n",    to_time(mvhd.modification_time), mvhd.modification_time)
	printf(level, "matrix:           %v\n",         to_matrix(mvhd.view_matrix))
	printf(level, "next track id:    %v\n",         mvhd.next_track_id)
}

@(private="package")
print_ftyp :: proc(ftyp: FTYP, level := int(0)) {
	printf(level, "Major Brand:   %v (0x%08x)\n", to_string(ftyp.brand), int(ftyp.brand))
	printf(level, "Minor Version: %v.%v.%v.%v\n", ftyp.version.x, ftyp.version.y, ftyp.version.z, ftyp.version.w)

	println(level, "Compat:")
	for compat in ftyp.compatible {
		println(level + 1, to_string(compat))
	}
}

@(private="package")
print_hdlr :: proc(hdlr: $T, level := int(0)) {
	#assert(T == HDLR)

	if hdlr.component_type != nil {
		printf(level, "Type:         %v\n", to_string(hdlr.component_type))
	}

	if hdlr.component_subtype != nil {
		printf(level, "Sub-Type:     %v\n", to_string(hdlr.component_subtype))
	}

	if hdlr.component_manufacturer != nil {
		printf(level, "Manufacturer: %v\n", to_string(hdlr.component_manufacturer))
	}

	if len(hdlr.name) > 0 {
		printf(level, "Name:         %v\n", hdlr.name)
	}
}

@(private="package")
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

@(private="package")
printf :: proc(level: int, format: string, args: ..any) {
	indent(level)
	fmt.printf(format, ..args)
}

@(private="package")
println :: proc(level: int, args: ..any) {
	indent(level)
	fmt.println(..args)
}

@(private="package")
indent :: proc(level: int) {
	TABS := []u8{
		'\t', '\t', '\t', '\t', '\t',
		'\t', '\t', '\t', '\t', '\t',
		'\t', '\t', '\t', '\t', '\t',
		'\t', '\t', '\t', '\t', '\t',
	}
	fmt.printf(string(TABS[:level]))
}

// Internal type conversion helpers
@(private="package")
to_string :: proc(type: $T) -> (res: string) {
	when T == ISO_639_2 {
		buffer := PRINT_BUFFER[:]

		l := int(type)
		buffer[0] = u8(96 + (l >> 10)     )
		buffer[1] = u8(96 + (l >>  5) & 31)
		buffer[2] = u8(96 + (l      ) & 31)

		return string(buffer[:3])

	} else when T == FourCC {
		has_prefix :: proc(s, prefix: string) -> bool {
			return len(s) >= len(prefix) && s[0:len(prefix)] == prefix
		}

		if type == .Root {
			return "<ROOT>"
		}
		id := runtime.typeid_base(typeid_of(FourCC))
		type_info := type_info_of(id)

		buffer := PRINT_BUFFER[:]
		name:     string

		#partial switch e in type_info.variant {
		case runtime.Type_Info_Enum:
			Enum_Value :: runtime.Type_Info_Enum_Value

			ev_, _ := reflect.as_i64(type)
			ev := Enum_Value(ev_)

			for val, idx in e.values {
				if val == ev {
					name = fmt.bprintf(buffer[:], "%v", e.names[idx])
					if has_prefix(name, "iTunes") {
						buffer[6] = ':'
					}
					for v, i in name {
						if v == '_' {
							buffer[i] = ' '
						}
					}
					return name

				}
			}
		}

		temp := transmute([4]u8)type
		/*
			We could do `string(t[:4])`, but this also handles e.g. `©too`.
		*/
		if common.is_printable(temp[:]) {
			return fmt.bprintf(buffer[:], "%c%c%c%c 0x%08x", temp[0], temp[1], temp[2], temp[3], i64(type))
		} else {
			return fmt.bprintf(buffer[:], "0x%08x",          i64(type))
		}

	} else when T == UUID {
		return common._string(type)
	} else {
		#panic("to_string: Unsupported type.")
	}
}

@(private="package")
to_f64 :: proc(fixed: $T) -> (res: f64) {
	when T == Fixed_16_16 {
		FRACT :: 16
		f := u32(fixed)

		res  = f64(f >> FRACT)
		res += f64(f & (1 << FRACT - 1)) / f64(1 << FRACT)
	} else when T == Fixed_2_30 {
		FRACT :: 30
		f := u32(fixed)

		res  = f64(f >> FRACT)
		res += f64(f & (1 << FRACT - 1)) / f64(1 << FRACT)
	} else when T == Fixed_8_8 {
		FRACT :: 8
		f := u16(fixed)

		res  = f64(f >> FRACT)
		res += f64(f & (1 << FRACT - 1)) / f64(1 << FRACT)
	} else {
		#panic("to_f64: Unsupported type.")
	}
	return
}

@(private="package")
to_time :: proc(seconds: $T) -> time.Time {
	// MPEG4 (ISO/IEC 14496) dates are in seconds since midnight, Jan. 1, 1904, in UTC time
	MPEG_YEAR :: -66
	MPEG_TO_INTERNAL :: i64((MPEG_YEAR*365 + MPEG_YEAR/4 - MPEG_YEAR/100 + MPEG_YEAR/400 - 1) * time.SECONDS_PER_DAY)

	return time.Time{(i64(seconds) + MPEG_TO_INTERNAL) * 1e9}
}

@(private="package")
to_matrix :: proc(mat: View_Matrix) -> (m: matrix[3, 3]f64) {
	m = matrix[3, 3]f64{
		to_f64(mat.a), to_f64(mat.b), to_f64(mat.u),
		to_f64(mat.c), to_f64(mat.d), to_f64(mat.v),
		to_f64(mat.x), to_f64(mat.y), to_f64(mat.w),
	}
	return
}
@thread_local PRINT_BUFFER: [512]u8