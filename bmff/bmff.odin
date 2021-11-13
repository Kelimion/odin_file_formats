package iso_bmff
/*
	Copyright 2021 Jeroen van Rijn <nom@duclavier.com>.
	Made available under Odin's BSD-3 license.

	A from-scratch implementation of ISO base media file format (ISOM),
	as specified in ISO/IEC 14496-12, Fifth edition 2015-12-15.
	The identical text is available as ISO/IEC 15444-12 (JPEG 2000, Part 12).

	See: https://www.iso.org/standard/68960.html and https://www.loc.gov/preservation/digital/formats/fdd/fdd000079.shtml

	This file contains the base media format parser and type definitions.
*/

import "core:mem"
import "core:os"
import "core:fmt"

_ :: fmt.println

import "../common"

DEBUG         :: #config(BMFF_DEBUG, false)
DEBUG_VERBOSE :: DEBUG && #config(BMFF_DEBUG_VERBOSE, false)

Error :: enum {
	None = 0,
	File_Not_Found,
	File_Not_Opened,
	File_Empty,
	File_Ended_Early,
	Read_Error,
	Wrong_File_Format,
	Error_Parsing_iTunes_Metadata,

	Unknown_MVHD_Version,
	Unknown_TKHD_Version,
	Unknown_MDHD_Version,
}

BCD4   :: distinct [4]u8

FourCC :: enum u32be {
	/*
		File root dummy Box.
	*/
	_file_root = 0,

	/*
		If any atom can follow, `expected` is set to `.any_type`.
	*/
	any_type = 0,

	/*
		Atoms
	*/
	ftyp = 'f' << 24 | 't' << 16 | 'y' << 8 | 'p',                                // 0x66747970

	moov = 'm' << 24 | 'o' << 16 | 'o' << 8 | 'v',                                // 0x6d6f6f76
		mvhd = 'm' << 24 | 'v' << 16 | 'h' << 8 | 'd',                            // 0x6d766864

		trak = 't' << 24 | 'r' << 16 | 'a' << 8 | 'k',                            // 0x7472616b
			tkhd = 't' << 24 | 'k' << 16 | 'h' << 8 | 'd',                        // 0x746b6864
			edts = 'e' << 24 | 'd' << 16 | 't' << 8 | 's',                        // 0x65647473
				elst = 'e' << 24 | 'l' << 16 | 's' << 8 | 't',                    // 0x656c7374
			mdia = 'm' << 24 | 'd' << 16 | 'i' << 8 | 'a',                        // 0x6d646961
				mdhd = 'm' << 24 | 'd' << 16 | 'h' << 8 | 'd',                    // 0x6d646864
				minf = 'm' << 24 | 'i' << 16 | 'n' << 8 | 'f',                    // 0x6d696e66
				hdlr = 'h' << 24 | 'd' << 16 | 'l' << 8 | 'r',                    // 0x68646c72

		udta = 'u' << 24 | 'd' << 16 | 't' << 8 | 'a',                            // 0x75647461
			meta = 'm' << 24 | 'e' << 16 | 't' << 8 | 'a',                        // 0x6d657461
				/*
					Apple Metadata.
					Not part of ISO 14496-12-2015. 
				*/
				ilst = 'i' << 24 | 'l' << 16 | 's' << 8 | 't',                    // 0x696c7374

    				itunes_title        = '©' << 24 | 'n' << 16 | 'a' << 8 | 'm', // 0xa96e616d
    				itunes_author       = '©' << 24 | 'A' << 16 | 'R' << 8 | 'T', // 0xa9415254
    				itunes_album_artist = 'a' << 24 | 'A' << 16 | 'R' << 8 | 'T', // 0x61415254
    				itunes_album        = '©' << 24 | 'a' << 16 | 'l' << 8 | 'b', // 0xa9616c62
    				itunes_grouping     = '©' << 24 | 'g' << 16 | 'r' << 8 | 'p', // 0xa9677270
    				itunes_composer     = '©' << 24 | 'w' << 16 | 'r' << 8 | 't', // 0xa9777274
    				itunes_year         = '©' << 24 | 'd' << 16 | 'a' << 8 | 'y', // 0xa9646179
    				itunes_track        = 't' << 24 | 'r' << 16 | 'k' << 8 | 'n', // 0x74726b6e
    				itunes_disk         = 'd' << 24 | 'i' << 16 | 's' << 8 | 'k', // 0x6469736b
    				itunes_genre        = '©' << 24 | 'g' << 16 | 'e' << 8 | 'n', // 0xa967656e
    				itunes_copyright    = '©' << 24 | 'c' << 16 | 'p' << 8 | 'y', // 0xa9637079
    				itunes_comment      = '©' << 24 | 'c' << 16 | 'm' << 8 | 't', // 0xa9636d74
    				itunes_description  = 'd' << 24 | 'e' << 16 | 's' << 8 | 'c', // 0x64657363
    				itunes_synopsis     = 'l' << 24 | 'd' << 16 | 'e' << 8 | 's', // 0x6c646573
    				itunes_show         = 't' << 24 | 'v' << 16 | 's' << 8 | 'h', // 0x74767368
    				itunes_episode_id   = 't' << 24 | 'v' << 16 | 'e' << 8 | 'n', // 0x7476656e
    				itunes_network      = 't' << 24 | 'v' << 16 | 'n' << 8 | 'n', // 0x74766e6e
    				itunes_lyrics       = '©' << 24 | 'l' << 16 | 'y' << 8 | 'r', // 0xa96c7972
    				itunes_tool         = '©' << 24 | 't' << 16 | 'o' << 8 | 'o', // 0xa9746f6f
	   				itunes_cover        = 'c' << 24 | 'o' << 16 | 'v' << 8 | 'r', // 0x636f7672

						data = 'd' << 24 | 'a' << 16 | 't' << 8 | 'a',            // 0x64617461

	   				/*
						Special. Found at the end of M4A audio book metadata, for example.
						`----` has no data sub-node.
	   				*/
	   				itunes_4_dashes     = '-' << 24 | '-' << 16 | '-' << 8 | '-', // 0x2d2d2d2d
	   					itunes_mean         = 'm' << 24 | 'e' << 16 | 'a' << 8 | 'n', // 

	moof = 'm' << 24 | 'o' << 16 | 'o' << 8 | 'f',                                // 0x6d6f6f66
		traf = 't' << 24 | 'r' << 16 | 'a' << 8 | 'f',                            // 0x74726166
	meco = 'm' << 24 | 'e' << 16 | 'c' << 8 | 'o',                                // 0x6d65636f
	free = 'f' << 24 | 'r' << 16 | 'e' << 8 | 'e',                                // 0x66726565
	mdat = 'm' << 24 | 'd' << 16 | 'a' << 8 | 't',                                // 0x6d646174
	uuid = 'u' << 24 | 'u' << 16 | 'i' << 8 | 'd',                                // 0x75756964
	name = 'n' << 24 | 'a' << 16 | 'm' << 8 | 'e',                                // 0x6e616d65

	/*
		Brands
	*/
	isom = 'i' << 24 | 's' << 16 | 'o' << 8 | 'm',                                // 0x69736f6d
	iso2 = 'i' << 24 | 's' << 16 | 'o' << 8 | '2',                                // 0x69736f32
	iso3 = 'i' << 24 | 's' << 16 | 'o' << 8 | '3',                                // 0x69736f33
	iso4 = 'i' << 24 | 's' << 16 | 'o' << 8 | '4',                                // 0x69736f34
	iso5 = 'i' << 24 | 's' << 16 | 'o' << 8 | '5',                                // 0x69736f35
	iso6 = 'i' << 24 | 's' << 16 | 'o' << 8 | '6',                                // 0x69736f36
	iso7 = 'i' << 24 | 's' << 16 | 'o' << 8 | '7',                                // 0x69736f37
	iso8 = 'i' << 24 | 's' << 16 | 'o' << 8 | '8',                                // 0x69736f38
	iso9 = 'i' << 24 | 's' << 16 | 'o' << 8 | '9',                                // 0x69736f39

	avc1 = 'a' << 24 | 'v' << 16 | 'c' << 8 | '1',                                // 0x61766331
	mp41 = 'm' << 24 | 'p' << 16 | '4' << 8 | '1',                                // 0x6d703431
	mp42 = 'm' << 24 | 'p' << 16 | '4' << 8 | '2',                                // 0x6d703432
	mp71 = 'm' << 24 | 'p' << 16 | '7' << 8 | '1',                                // 0x6d703731

	m4a_ = 'm' << 24 | '4' << 16 | 'a' << 8 | ' ',                                // 0x4d344120

	/*
		Handler types
	*/
	video = 'v' << 24 | 'i' << 16 | 'd' << 8 | 'e',                               // 0x76696465
	sound = 's' << 24 | 'o' << 16 | 'u' << 8 | 'n',                               // 0x736f756e
}

BMFF_Box_Header_File :: struct {
	size: u32be,
	type: FourCC,
}
#assert(size_of(BMFF_Box_Header_File) == 8)


/*
	UUIDs are compliant with RFC 4122: A Universally Unique IDentifier (UUID) URN Namespace
	                         (https://www.rfc-editor.org/rfc/rfc4122.html)
*/
UUID :: common.UUID_RFC_4122

BMFF_Box_Header :: struct {
	/*
		Box file offset, and size including header.
	*/
	offset:         i64,
	size:           i64,
	end:            i64,

	payload_offset: i64,
	payload_size:   i64,

	type:           FourCC,
	uuid:           UUID,
}

BMFF_Box :: struct {
	using header: BMFF_Box_Header,

	parent:         ^BMFF_Box,
	next:           ^BMFF_Box,
	first_child:    ^BMFF_Box,

	/*
		Payload can be empty
	*/
	payload:        [dynamic]u8,
}

BMFF_File :: struct {
	/*
		Root atom
	*/
	root: ^BMFF_Box,

	/*
		Important atoms
	*/
	ftyp: ^BMFF_Box,
	moov: ^BMFF_Box,
	mvhd: ^BMFF_Box,
	mdat: ^BMFF_Box,

	/*
		Apple Metadata isd not specified in ISO 14496-12-2015.
		Nevertheless, we add support for it.

		If `moov.udta.meta.hdlr` == `mdir/appl`,
		then `itunes_metadata` is set to `moov.udta.meta.ilst`
	*/
	itunes_metadata: ^BMFF_Box,

	/*
		Useful file members
	*/
	time_scale: u32be,

	/*
		Implementation
	*/
	file_info: os.File_Info,
	handle:    os.Handle,
	allocator: mem.Allocator,
}

Fixed_16_16    :: distinct u32be
Fixed_2_30     :: distinct u32be
Fixed_8_8      :: distinct u16be
Rational_16_16 :: distinct [2]u16be
ISO_639_2      :: distinct u16be

View_Matrix :: struct #packed {
	a: Fixed_16_16, b: Fixed_16_16, u: Fixed_2_30,
	c: Fixed_16_16, d: Fixed_16_16, v: Fixed_2_30,
	x: Fixed_16_16, y: Fixed_16_16, w: Fixed_2_30,
}

MVHD_Predefined :: struct {
	foo: [6]u32be,
}

/*
	Files that don't start with 'ftyp' have this synthetic one.
*/
DEFAULT_FTYP :: struct{
	brand: FourCC,
	version: BCD4,
	compat: FourCC,
}{
	brand   = .mp41,
	version = 0,
	compat  = .mp41,
}

Version_and_Flags :: struct #packed {
	version:           u8,
	flags:             [3]u8,	
}

MVHD_V0 :: struct #packed {
	using vf:          Version_and_Flags,
	creation_time:     u32be,
	modification_time: u32be,
	time_scale:        u32be,
	duration:          u32be,
	preferred_rate:    Fixed_16_16,
	preferred_volume:  Fixed_8_8,
	_reserved:         [10]u8,
	view_matrix:       View_Matrix,
	predefined:        MVHD_Predefined,
	next_track_id:     u32be,
}
#assert(size_of(MVHD_V0) == 100)

MVHD_V1 :: struct #packed {
	using vf:          Version_and_Flags,
	creation_time:     u64be,
	modification_time: u64be,
	time_scale:        u32be,
	duration:          u64be,
	preferred_rate:    Fixed_16_16,
	preferred_volume:  Fixed_8_8,
	_reserved:         [10]u8,
	view_matrix:       View_Matrix,
	predefined:        MVHD_Predefined,
	next_track_id:     u32be,
}
#assert(size_of(MVHD_V1) == 112)

Track_Header_Flag :: enum u8 {
	track_enabled              = 0,
	track_in_movie             = 1,
	track_size_is_aspect_ratio = 2,
}
Track_Header_Flags :: bit_set[Track_Header_Flag; u8]

TKHD_V0 :: struct #packed {
	version:           u8,
	_flags:            [2]u8,
	flags:             Track_Header_Flags,
	creation_time:     u32be,
	modification_time: u32be,
	track_id:          u32be,
	_reserved_1:       u32be,
	duration:          u32be,
	_reserved_2:       [2]u32be,
	layer:             i16be,
	alternate_group:   i16be,
	volume:            Fixed_8_8,
	reserved_3:        u16be,
	view_matrix:       View_Matrix,
	width:             Fixed_16_16,
	height:            Fixed_16_16,
}
#assert(size_of(TKHD_V0) == 84)

TKHD_V1 :: struct #packed {
	version:           u8,
	_flags:            [2]u8,
	flags:             Track_Header_Flags,
	creation_time:     u64be,
	modification_time: u64be,
	track_id:          u32be,
	_reserved_1:       u32be,
	duration:          u64be,
	_reserved_2:       [2]u32be,
	layer:             i16be,
	alternate_group:   i16be,
	volume:            Fixed_8_8,
	reserved_3:        u16be,
	view_matrix:       View_Matrix,
	width:             Fixed_16_16,
	height:            Fixed_16_16,
}
#assert(size_of(TKHD_V1) == 96)

ELST_Header :: struct #packed {
	using vf:          Version_and_Flags,
	entry_count:       u32be,
}

ELST_Entry_V0 :: struct #packed {
	segment_duration:  u32be,
	media_time:        i32be,
	media_rate:        Rational_16_16,
}
#assert(size_of(ELST_Entry_V0) == 12)

ELST_Entry_V1 :: struct #packed {
	segment_duration:  u64be,
	media_time:        i32be,
	media_rate:        Rational_16_16,
}
#assert(size_of(ELST_Entry_V1) == 16)

MDHD_V0 :: struct #packed {
	using vf:          Version_and_Flags,
	creation_time:     u32be,
	modification_time: u32be,
	time_scale:        u32be,
	duration:          u32be,
	language:          ISO_639_2, // ISO-639-2/T language code
	quality:           u16be,
}
#assert(size_of(MDHD_V0) == 24)

MDHD_V1 :: struct #packed {
	using vf:          Version_and_Flags,
	creation_time:     u64be,
	modification_time: u64be,
	time_scale:        u32be,
	duration:          u64be,
	language:          ISO_639_2, // ISO-639-2/T language code
	quality:           u16be,
}
#assert(size_of(MDHD_V1) == 36)

HDLR :: struct #packed {
	using vf:               Version_and_Flags,
	component_type:         FourCC,
	component_subtype:      FourCC,
	component_manufacturer: FourCC,
	component_flags:        u32be,
	reserved:               u32be,
}
#assert(size_of(HDLR) == 24)

META :: struct #packed {
	using vf:               Version_and_Flags,
}
#assert(size_of(META) == 4)

ILST_DATA_Type :: enum u32be {
	Default =  1,

	JPEG    = 13, // moov.udta.meta.ilst.covr.data
	PNG     = 14, // moov.udta.meta.ilst.covr.data
}

/*
	Apple iTunes mdir metadata tag.
	Found as a child of the various tags under:
		`moov.udta.meta.ilst`
*/
ILST_DATA :: struct {
	type:    ILST_DATA_Type,
	subtype: u32be,
}
#assert(size_of(ILST_DATA) == 8)

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
	if file.handle    != 0 {
		os.close(file.handle)
	}
	if file.root      != nil {
		free_atom(file.root)
	}
	free(file)

	when DEBUG_VERBOSE {
		fmt.println("-=-=-=-=-=-=- CLEANED UP -=-=-=-=-=-=-")
	}
}