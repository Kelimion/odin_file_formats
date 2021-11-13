package iso_bmff
/*
	Copyright 2021 Jeroen van Rijn <nom@duclavier.com>.
	Made available under Odin's BSD-3 license.

	A from-scratch implementation of ISO base media file format (ISOM),
	as specified in ISO/IEC 14496-12, Fifth edition 2015-12-15.
	The identical text is available as ISO/IEC 15444-12 (JPEG 2000, Part 12).

	See: https://www.iso.org/standard/68960.html and https://www.loc.gov/preservation/digital/formats/fdd/fdd000079.shtml

	This file is a debug helper that prints the parse tree.
*/

import "core:fmt"
import "core:runtime"

print_itunes_metadata :: proc(f: ^BMFF_File, metadata: ^BMFF_Box, level := int(0)) {
	payload   := metadata.payload[:]
	ilst_data := (^ILST_DATA)(raw_data(payload))^
	payload    = payload[size_of(ILST_DATA):]

	#partial switch metadata.parent.type {
	case .itunes_cover:
		#partial switch ilst_data.type {
		case .JPEG: printf(level, "Thumbnail Type: JPEG\n")
		case .PNG:  printf(level, "Thumbnail Type: PNG\n")
		case:       printf(level, "Thumbnail Type: Unknown\n")
		}
	case .itunes_track, .itunes_disk:
		// Not ASCII
	case:
		if is_printable(payload) {
			println(level, string(payload))
		} else {
			println(level, "Bytes:", payload)
		}
	}
}

print_mdhd :: proc(f: ^BMFF_File, mdhd: $T, level := int(0)) {
	using mdhd

	seconds := f64(duration) / f64(time_scale)
	printf(level, "duration: %v seconds\n", seconds)
	printf(level, "created:  %v (%v)\n",   _time(creation_time), creation_time)
	printf(level, "modified: %v (%v)\n",   _time(modification_time), modification_time)
	printf(level, "language: %v\n",        _string(language))
	printf(level, "quality:  %v\n",        quality)
}

print_elst :: proc(f: ^BMFF_File, elst: []$T, level := int(0)) {
	for e, i in elst {
		using e
		printf(level, "edit: %v\n", i)
		printf(level + 1, "segment_duration: %v\n",    segment_duration)
		printf(level + 1, "media_time:       %v\n",    media_time)
		printf(level + 1, "media_rate:       %v/%v\n", media_rate.x, media_rate.y)
	}
}

print_tkhd :: proc(f: ^BMFF_File, tkhd: $T, level := int(0)) {
	using tkhd
	seconds := f64(duration) / f64(f.time_scale)

	printf(level, "track:    %v\n",         track_id)
	printf(level, "flags:    %v\n",         flags)
	printf(level, "duration: %v seconds\n", seconds)
	printf(level, "created:  %v (%v)\n",    _time(creation_time), creation_time)
	printf(level, "modified: %v (%v)\n",    _time(modification_time), modification_time)

	if volume == 0 {
		printf(level, "width:    %v\n",     _f64(width))
		printf(level, "height:   %v\n",     _f64(height))
	} else {
		printf(level, "volume:   %v\n",     _f64(volume))
	}
	printf(level, "matrix:   %v\n",         _matrix(view_matrix))
}

print_mvhd :: proc(f: ^BMFF_File, mvhd: $T, level := int(0)) {
	using mvhd
	seconds := f64(duration) / f64(time_scale)

	printf(level, "preferred_rate:   %v\n",         _f64(preferred_rate))
	printf(level, "preferred_volume: %v\n",         _f64(preferred_volume))
	printf(level, "duration:         %v seconds\n", seconds)
	printf(level, "created:          %v (%v)\n",    _time(creation_time), creation_time)
	printf(level, "modified:         %v (%v)\n",    _time(modification_time), modification_time)
	printf(level, "matrix:           %v\n",         _matrix(view_matrix))
	printf(level, "next track id:    %v\n",         next_track_id)
}

print_ftyp :: proc(f: ^BMFF_File, atom: ^BMFF_Box, level := int(0)) {
	assert(atom.type == .ftyp)

	if len(atom.payload) == 0 { return }
	payload := atom.payload[:]

	brand_major := (^FourCC)(raw_data(payload))^
	payload     = payload[size_of(FourCC):]

	version_minor := (^BCD4)(raw_data(payload))^
	payload     = payload[size_of(BCD4):]

	printf(level, "Major Brand:   %v (0x%08x)\n", _string(brand_major), int(brand_major))
	printf(level, "Minor Version: %v.%v.%v.%v\n", version_minor.x, version_minor.y, version_minor.z, version_minor.w)

	println(level, "Compat:")
	for len(payload) > 0 {
		brand   := (^FourCC)(raw_data(payload))^
		payload  = payload[size_of(FourCC):]
		println(level + 1, _string(brand))
	}
}

print_hdlr :: proc(f: ^BMFF_File, atom: $T, level := int(0)) {
	payload := atom.payload[:]
	hdlr    := (^HDLR)(raw_data(payload))^
	using hdlr

	if component_type != .any_type {
		printf(level, "Type:         %v\n", _string(component_type))
	}

	if component_subtype != .any_type {
		printf(level, "Sub-Type:     %v\n", _string(component_subtype))
	}

	if component_manufacturer != .any_type {
		printf(level, "Manufacturer: %v\n", _string(component_manufacturer))
	}

	payload  = payload[size_of(HDLR):]
	name    := cstring(&payload[0])

	if len(name) > 0 {
		printf(level, "Name:         %v\n", name)
	}
}

print_atom :: proc(f: ^BMFF_File, atom: ^BMFF_Box, level := int(0), print_siblings := false, recurse := false) {
	if atom.type == .uuid {
		printf(level, "[uuid (%v] Pos: %d. Size: %d\n", _string(atom.uuid), atom.offset, atom.payload_size)
	} else {
		printf(level, "[%v (0x%08x)] Pos: %d. Size: %d\n", _string(atom.type), int(atom.type), atom.offset, atom.payload_size)
	}

	#partial switch atom.type {
	case .ftyp:
		print_ftyp(f, atom, level + 1)
	case .mvhd:
		if len(atom.payload) > 0 {
			payload := atom.payload[:]
			version := payload[0]

			switch version {
			case 0:
				mvhd := (^MVHD_V0)(raw_data(payload))^
				print_mvhd(f, mvhd, level + 1)
			case 1:
				mvhd := (^MVHD_V1)(raw_data(payload))^
				print_mvhd(f, mvhd, level + 1)
			case:
				unreachable()
			}
		}
	case .tkhd:
		if len(atom.payload) > 0 {
			payload := atom.payload[:]
			version := payload[0]

			switch version {
			case 0:
				tkhd := (^TKHD_V0)(raw_data(payload))^
				print_tkhd(f, tkhd, level + 1)
			case 1:
				tkhd := (^TKHD_V1)(raw_data(payload))^
				print_tkhd(f, tkhd, level + 1)
			case:
				unreachable()
			}
		}
	case .elst:
		if len(atom.payload) > 0 {
			payload := atom.payload[:]
			version := payload[0]

			elst_hdr := (^ELST_Header)(raw_data(payload))^
			payload   = payload[size_of(ELST_Header):]
			switch version {
			case 0:
				_entries := runtime.Raw_Slice{
					data = raw_data(payload),
					len  = int(elst_hdr.entry_count),
				}
				entries := transmute([]ELST_Entry_V0)_entries
				print_elst(f, entries, level + 1)
			case 1:
				_entries := runtime.Raw_Slice{
					data = raw_data(payload),
					len  = int(elst_hdr.entry_count),
				}
				entries := transmute([]ELST_Entry_V1)_entries
				print_elst(f, entries, level + 1)
			case:
				unreachable()
			}
		}
	case .mdhd:
		if len(atom.payload) > 0 {
			payload := atom.payload[:]
			version := payload[0]

			switch version {
			case 0:
				mdhd := (^MDHD_V0)(raw_data(payload))^
				print_mdhd(f, mdhd, level + 1)
			case 1:
				mdhd := (^MDHD_V1)(raw_data(payload))^
				print_mdhd(f, mdhd, level + 1)
			case:
				unreachable()
			}
		}
	case .hdlr:
		print_hdlr(f, atom, level + 1)

	case .name:
		if atom.parent.type == .udta && len(atom.payload) > 0 {
			printf(level + 1, "Name: %v\n", string(atom.payload[:]))
		}

	case .data:
		if atom.parent != nil && atom.parent.parent != nil && atom.parent.parent == f.itunes_metadata && len(atom.payload) > 0 {
			print_itunes_metadata(f, atom, level + 1)
		}
	}

	if recurse && atom.first_child != nil {
		print_atom(f, atom.first_child, level + 1, print_siblings, recurse)
	}

	if print_siblings && atom.next != nil {
		print_atom(f, atom.next, level, print_siblings, recurse)
	}
}

print :: proc(f: ^BMFF_File, box: ^BMFF_Box = nil, print_siblings := false, recurse := false) {
	if box != nil {
		print_atom(f, box,    0, print_siblings, recurse)
	} else {
		print_atom(f, f.root, 0, true, true)
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