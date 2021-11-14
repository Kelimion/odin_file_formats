package iso_bmff
/*
	Copyright 2021 Jeroen van Rijn <nom@duclavier.com>.
	Made available under Odin's BSD-3 license.

	A from-scratch implementation of ISO base media file format (ISOM),
	as specified in ISO/IEC 14496-12, Fifth edition 2015-12-15.
	The identical text is available as ISO/IEC 15444-12 (JPEG 2000, Part 12).

	See: https://www.iso.org/standard/68960.html and https://www.loc.gov/preservation/digital/formats/fdd/fdd000079.shtml

	This file contains the base media format parser.
*/

import "core:os"
import "core:fmt"

_ :: fmt.println

import "../common"

DEBUG         :: #config(BMFF_DEBUG, false)
DEBUG_VERBOSE :: DEBUG && #config(BMFF_DEBUG_VERBOSE, false)

parse_itunes_metadata :: proc(f: ^BMFF_File) -> (err: Error) {
	assert(f.itunes_metadata != nil)
	when DEBUG {
		fmt.println("\nCalling specialized iTunes metadata parser...")
		defer fmt.println("Back from specialized iTunes metadata parser...\n")
	}

	fd := f.handle

	h:            BMFF_Box_Header
	box:          ^BMFF_Box
	prev:         ^BMFF_Box = f.itunes_metadata
	parent:       ^BMFF_Box = f.itunes_metadata

	ok:           bool

	loop: for {
		/*
			Peek at header and check if this would put us past the end of the iTunes metadata.
		*/
		h, err = read_box_header(fd=fd, read=false)
		if h.offset >= f.root.end || h.offset > f.itunes_metadata.end {
			/*
				Done.
			*/
			err = .None
			break loop
		}

		/*
			Now read it for real.
		*/
		if h, err = read_box_header(fd=fd, read=true); err != .None { return .Error_Parsing_iTunes_Metadata }

		/*
			Create box and set type, size, parent, etc.
		*/
		#partial switch h.type {
		case .data:
			parent = prev
		case .itunes_mean:
			parent = prev
		case:
			parent = f.itunes_metadata
		}

		box = new(BMFF_Box)
		box.header = h
		box.parent = parent

		/*
			Chain it.
		*/
		if parent.first_child == nil {
			/*
				We're either our parent's first child...
			*/
			parent.first_child = box
		} else {
			/*
				Or we walk our siblings until its next pointer is nil.
			*/
			sibling: ^BMFF_Box
			for sibling = parent.first_child; sibling.next != nil; sibling = sibling.next {}
			sibling.next = box
		}

		when DEBUG {
			level := 1 if box.parent == f.itunes_metadata else 2
			if h.type == .uuid {
				printf(level, "[uuid (%v] Pos: %d. Size: %d\n", _string(h.uuid), h.offset, h.payload_size)
			} else {
				printf(level, "[%v (0x%08x)] Pos: %d. Size: %d\n", _string(h.type), int(h.type), h.offset, h.payload_size)
			}
		}

		#partial switch box.type {
		case .data:
			/*
				Apple iTunes mdir metadata tag.
				Found as a child of the various tags under: `moov.udta.meta.ilst`
			*/
			skip := true
			if f.itunes_metadata != nil {
				/*
					We parse if we've previously located the property bag.
				*/
				if parent.parent == f.itunes_metadata {
					skip = false

					payload: []u8
					if payload, ok = common.read_slice(fd, box.payload_size); !ok { return .Read_Error }
					append(&box.payload, ..payload)
				}
			}

			if skip {
				skip_box(fd, box) or_return
			}

		case .itunes_4_dashes:
			payload: []u8
			if payload, ok = common.read_slice(fd, box.payload_size); !ok { return .Read_Error }
			append(&box.payload, ..payload)
		}

		prev = box
	}

	return
}

parse :: proc(f: ^BMFF_File, parse_metadata := true) -> (err: Error) {
	when DEBUG {
		fmt.println("\nParsing...")
		defer fmt.println("\nBack from parsing...")
	}

	fd := f.handle

	h:            BMFF_Box_Header
	box:          ^BMFF_Box
	prev:         ^BMFF_Box = f.root
	parent:       ^BMFF_Box = f.root

	ok:           bool

	/*
		Most files strt with an 'ftyp' atom.
	*/
	h = read_box_header(fd=fd, read=false) or_return
	if h.type != .ftyp {
		/*
			NOTE(Jeroen):
				Files with no file‐type box should be read as if they contained an FTYP box with	
				Major_brand='mp41', minor_version=0, and the single compatible brand `mp41`.
		*/
		box = new(BMFF_Box)
		box.size           = size_of(BMFF_Box_Header_File) + size_of(DEFAULT_FTYP)
		box.type           = .ftyp
		box.parent         = f.root
		f.root.first_child = box

		default_ftyp := DEFAULT_FTYP
		payload := transmute([size_of(DEFAULT_FTYP)]u8)default_ftyp

		append(&box.payload, ..payload[:])
	}

	loop: for {
		h, err = read_box_header(fd=fd, read=true)
		if h.offset >= f.root.size { break loop }
		if err != .None { return err }

		/*
			Find the parent by what byte range of the file we're at.
		*/
		parent = prev
		for {
			if h.offset >= parent.end {
				/*
					Parent can't contain this box. Let's look at its parent.
				*/
				when DEBUG_VERBOSE {
					fmt.printf("\t[%v] ends past ",      _string(h.type))
					fmt.printf("[%v] end, checking if ", _string(parent.type))
					fmt.printf("[%v] is our parent.\n",  _string(parent.parent.type))
				}
				parent = parent.parent
			} else {
				/*
					Box fits within this parent.
				*/
				break
			}
		}

		/*
			Create box and set type, size, parent, etc.
		*/
		box = new(BMFF_Box)
		box.header = h
		box.parent = parent

		/*
			Chain it.
		*/
		if parent.first_child == nil {
			/*
				We're either our parent's first child...
			*/
			parent.first_child = box
		} else {
			/*
				Or we walk our siblings until its next pointer is nil.
			*/
			sibling: ^BMFF_Box
			for sibling = parent.first_child; sibling.next != nil; sibling = sibling.next {}
			sibling.next = box
		}

		if box.end > f.root.size {
			when DEBUG {
				fmt.printf("\t[%v] ended early, expected to end at %v.\n", _string(h.type), box.end)
			}
			return .File_Ended_Early
		}

		when DEBUG {
			level := 0
			for p := box.parent; p != f.root; p = p.parent { level += 1 }

			if box.type == .uuid {
				printf(level, "[uuid (%v] Pos: %d. Size: %d\n", _string(box.uuid), box.offset, box.payload_size)
			} else {
				printf(level, "[%v (0x%08x)] Pos: %d. Size: %d\n", _string(box.type), int(box.type), box.offset, box.payload_size)
			}
		}

		#partial switch h.type {
		case .ftyp:
			/*
				`ftyp` must always be the first child and we can't have two nodes of this type.
			*/
			if f.root.first_child != box {
				return .Wrong_File_Format
			}
			f.ftyp = box

			payload: []u8
			if box.payload_size % size_of(FourCC) != 0 {
				/*
					Remaining:
					- Major Brand: FourCC
					- Minor Brand: BCD4
					- ..FourCC

					All have the same size, so the remaining length of this box should cleanly divide by `size_of(FourCC)`.
				*/
				return .Wrong_File_Format
			}

			if payload, ok = common.read_slice(fd, box.payload_size); !ok { return .Read_Error }
			append(&box.payload, ..payload)

		case .moov:
			f.moov = box

		case .mvhd:
			f.mvhd = box

			version: u8
			if version, ok = common.peek_data(fd, u8); !ok { return .Read_Error }

			if (version == 0 && box.payload_size != size_of(MVHD_V0)) || (version == 1 && box.payload_size != size_of(MVHD_V1)) || version > 1 {
				return .Unknown_MVHD_Version
			}

			payload: []u8
			if payload, ok = common.read_slice(fd, box.payload_size); !ok { return .Read_Error }
			append(&box.payload, ..payload)

			switch version {
			case 0:
				mvhd := (^MVHD_V0)(raw_data(payload))^
				f.time_scale = mvhd.time_scale
			case 1:
				mvhd := (^MVHD_V1)(raw_data(payload))^
				f.time_scale = mvhd.time_scale
			case:
				unreachable()
			}

		case .trak:

		case .tkhd:
			version: u8
			if version, ok = common.peek_data(fd, u8); !ok { return .Read_Error }

			if (version == 0 && box.payload_size != size_of(TKHD_V0)) || (version == 1 && box.payload_size != size_of(TKHD_V1)) || version > 1 {
				return .Unknown_TKHD_Version
			}

			payload: []u8
			if payload, ok = common.read_slice(fd, box.payload_size); !ok { return .Read_Error }
			append(&box.payload, ..payload)

		case .edts:

		case .elst:
			payload:  []u8
			elst_hdr: ELST_Header
			if elst_hdr, ok = common.peek_data(fd, ELST_Header); !ok { return .Read_Error }

			size_expected := i64(size_of(ELST_Header))
			switch elst_hdr.version {
			case 0: size_expected += i64(elst_hdr.entry_count) * size_of(ELST_Entry_V0)
			case 1: size_expected += i64(elst_hdr.entry_count) * size_of(ELST_Entry_V1)
			case:
				unreachable()
			}

			if box.payload_size != size_expected { return .Wrong_File_Format }

			if payload, ok = common.read_slice(fd, box.payload_size); !ok { return .Read_Error }
			append(&box.payload, ..payload)

		case .mdia:

		case .mdhd:
			version: u8
			if version, ok = common.peek_data(fd, u8); !ok { return .Read_Error }

			if (version == 0 && box.payload_size != size_of(MDHD_V0)) || (version == 1 && box.payload_size != size_of(MDHD_V1)) || version > 1 {
				return .Unknown_MDHD_Version
			}

			payload: []u8
			if payload, ok = common.read_slice(fd, box.payload_size); !ok { return .Read_Error }
			append(&box.payload, ..payload)

		case .hdlr:
			/*
				ISO 14496-12-2015, section 8.4.3.1:
				`hdlr` may be contained in a `mdia` or `meta` box.
			*/
			if !(box.parent.type == .mdia || box.parent.type == .meta) {
				return .Wrong_File_Format
			}

			payload: []u8
			if payload, ok = common.read_slice(fd, box.payload_size); !ok { return .Read_Error }
			append(&box.payload, ..payload)

		case .udta:
			if !(   box.parent.type == .moov ||
					box.parent.type == .moof ||
					box.parent.type == .trak ||
					box.parent.type == .traf) {
				return .Wrong_File_Format
			}

		case .meta:
			payload: []u8
			if payload, ok = common.read_slice(fd, size_of(META)); !ok { return .Read_Error }
			append(&box.payload, ..payload)

		case .ilst:
			f.itunes_metadata = box

			if parse_metadata {
				/*
					Apple Metadata. Not part of the ISO standard, but we'll handle it anyway.
				*/
				parse_itunes_metadata(f) or_return
			} else {
				skip_box(fd, box) or_return
			}
		case .name:
			if parent.type == .udta {
				payload: []u8
				if payload, ok = common.read_slice(fd, box.payload_size); !ok { return .Read_Error }
				append(&box.payload, ..payload)				

			} else {
				skip_box(fd, box) or_return
			}

		/*
			Boxes we don't (want to or can yet) parse, we skip.
		*/
		case .mdat:
			f.mdat = box
			skip_box(fd, box) or_return
			
		case:
			if box.end >= i64(f.root.size) { break loop }
			skip_box(fd, box) or_return
			when DEBUG_VERBOSE {
				fmt.printf("[SKIP]", box)
			}
		}

		prev = box
	}
	return .None
}

skip_box :: proc(fd: os.Handle, box: ^BMFF_Box) -> (err: Error) {
	assert(box != nil)
	if !common.set_pos(fd, box.end + 1) {
		return .Read_Error
	}
	return .None
}

read_box_header :: #force_inline proc(fd: os.Handle, read := true) -> (header: BMFF_Box_Header, err: Error) {
	h:    BMFF_Box_Header_File
	e:    bool

	if header.offset, e   = common.get_pos(fd); !e { return header, .Read_Error }
	header.payload_offset = header.offset

	/*
		Read the basic box header.
	*/
	if h, e = common.read_data(fd, BMFF_Box_Header_File); !e { return header, .Read_Error }

	header.size            = i64(h.size)
	header.type            = h.type
	header.payload_offset += size_of(BMFF_Box_Header_File)

	if header.size == 1 {
		/*
			This atom has a 64-bit size.
		*/
		hsize: u64be
		if hsize, e = common.read_data(fd, u64be); !e { return header, .Read_Error }
		header.payload_offset += size_of(u64be)
		header.size            = i64(hsize)

	} else if header.size == 0 {
		/*
			This atom runs until the end of the file.
		*/
		file_size: i64
		if file_size, e = common.size(fd); !e { return header, .Read_Error }
		header.size = file_size - header.offset
	}

	header.end = header.offset + header.size - 1

	if header.type == .uuid {
		/*
			Read extended type.
		*/
		if header.uuid, e = common.read_data(fd, UUID); !e { return header, .Read_Error }
		header.payload_offset += size_of(UUID)
	}

	header.payload_size = header.end - header.payload_offset + 1

	when DEBUG_VERBOSE {
		verb: string
		if read {
			verb = "read_box_header"
		} else {
			verb = "peek_box_header"
		}
		if header.type == .uuid {
			fmt.printf("[%v] 'uuid' (%v) Size: %v\n", verb, _string(header.uuid), header.size)
		} else {
			fmt.printf("[%v] '%v' (0x%08x) Size: %v\n", verb, _string(FourCC(header.type)), int(header.type), header.size)
		}
	}

	/*
		Rewind if peeking.
	*/
	if !read && !common.set_pos(fd, header.offset) { return header, .Read_Error }

	return header, .None if e else .Read_Error
}

open_from_filename :: proc(filename: string, allocator := context.allocator) -> (file: ^BMFF_File, err: Error) {
	context.allocator = allocator

	fd, os_err := os.open(filename, os.O_RDONLY, 0)

	switch os_err {
	case 0:
		// Success
		if os_err != 0 {
			os.close(fd)
			return {}, .File_Not_Found
		}

		return open_from_handle(fd, allocator)
	}

	return {}, .File_Not_Found
}

open_from_handle :: proc(handle: os.Handle, allocator := context.allocator) -> (file: ^BMFF_File, err: Error) {
	context.allocator = allocator

	file = new(BMFF_File, allocator)
	file.allocator = allocator
	file.handle    = handle

	os_err: os.Errno
	file.file_info, os_err = os.fstat(handle)

	if file.file_info.size == 0 || os_err != 0 {
		when DEBUG {
			fmt.printf("OS returned: %v\n", os_err)
		}
		close(file)
		return file, .File_Empty
	}

	file.root                = new(BMFF_Box, allocator)
	file.root.offset         = 0
	file.root.size           = file.file_info.size
	file.root.end            = file.file_info.size - 1
	file.root.type           = ._file_root
	file.root.payload_offset = 0
	file.root.payload_size   = file.file_info.size

	return
}

open :: proc { open_from_filename, open_from_handle, }

close :: proc(file: ^BMFF_File) {
	if file == nil {
		return
	}

	context.allocator = file.allocator

	free_atom :: proc(atom: ^BMFF_Box) {
		if atom.first_child != nil {
			free_atom(atom.first_child)
		}

		if atom.next != nil {
			free_atom(atom.next)			
		}

		when DEBUG_VERBOSE {
			fmt.printf("Freeing '%v' (0x%08x).\n", _string(atom.type), int(atom.type))
		}

		delete(atom.payload)
		free(atom)
	}

	when DEBUG_VERBOSE {
		fmt.println("\n-=-=-=-=-=-=- CLEANING UP -=-=-=-=-=-=-")
	}

	os.file_info_delete(file.file_info)
	if file.handle != 0 {
		os.close(file.handle)
	}
	if file.root != nil {
		free_atom(file.root)
	}
	free(file)

	when DEBUG_VERBOSE {
		fmt.println("-=-=-=-=-=-=- CLEANED UP -=-=-=-=-=-=-")
	}
}