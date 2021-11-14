package iso_bmff
/*
	Copyright 2021 Jeroen van Rijn <nom@duclavier.com>.
	Made available under Odin's BSD-3 license.

	A from-scratch implementation of ISO base media file format (ISOM),
	as specified in ISO/IEC 14496-12, Fifth edition 2015-12-15.
	The identical text is available as ISO/IEC 15444-12 (JPEG 2000, Part 12).

	See: https://www.iso.org/standard/68960.html and https://www.loc.gov/preservation/digital/formats/fdd/fdd000079.shtml

	This file contains box type definitions.
*/
import "core:os"
import "core:mem"

/*
	On-disk structures are prefixed with a `_`.
	The parsed versions lack this prefix. If they're the same, there's no prefixed version.
*/

_BMFF_Box_Header :: struct {
	size: u32be,
	type: FourCC,
}
#assert(size_of(_BMFF_Box_Header) == 8)

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

Payload_Types :: union {
	[dynamic]u8,
	ELST_V0, ELST_V1,
	FTYP,
	HDLR,
	MVHD_V0, MVHD_V1,
	MDHD_V0, MDHD_V1,
	TKHD_V0, TKHD_V1,

	iTunes_Metadata,
}

BMFF_Box :: struct {
	using header: BMFF_Box_Header,

	parent:         ^BMFF_Box,
	next:           ^BMFF_Box,
	first_child:    ^BMFF_Box,

	/*
		Payload can be empty
	*/
	payload:        Payload_Types,
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

/*
	Files that don't start with 'ftyp' have this synthetic one.
*/
_FTYP :: struct {
	brand:   FourCC,
	version: BCD4,
}

FTYP :: struct {
	using header: _FTYP,
	compatible:   [dynamic]FourCC,
}

Header_Flag_3 :: enum u8 {
	track_enabled              = 0,
	track_in_movie             = 1,
	track_size_is_aspect_ratio = 2,
}
Header_Flags_3 :: bit_set[Header_Flag_3; u8]

Version_and_Flags :: struct #packed {
	version: u8,
	flag:    [2]u8,
	flags_3: Header_Flags_3,
}

Times :: struct($type_width: typeid) #packed {
	creation_time:     type_width,
	modification_time: type_width,
}

MVHD :: struct($type_width: typeid) #packed {
	using _vf:         Version_and_Flags,
	using _times:      Times(type_width),
	time_scale:        u32be,
	duration:          type_width,
	preferred_rate:    Fixed_16_16,
	preferred_volume:  Fixed_8_8,
	_reserved:         [10]u8,
	view_matrix:       View_Matrix,
	predefined:        MVHD_Predefined,
	next_track_id:     u32be,
}
MVHD_V0 :: distinct MVHD(u32be)
MVHD_V1 :: distinct MVHD(u64be)
#assert(size_of(MVHD_V0) == 100 && size_of(MVHD_V1) == 112)
 
TKHD :: struct($type_width: typeid) #packed {
	using _vf:         Version_and_Flags,
	using _times:      Times(type_width),
	track_id:          u32be,
	_reserved_1:       u32be,
	duration:          type_width,

	_reserved_2:       [2]u32be,
	layer:             i16be,
	alternate_group:   i16be,
	volume:            Fixed_8_8,
	reserved_3:        u16be,
	view_matrix:       View_Matrix,
	width:             Fixed_16_16,
	height:            Fixed_16_16,
}
TKHD_V0 :: distinct TKHD(u32be)
TKHD_V1 :: distinct TKHD(u64be)
#assert(size_of(TKHD_V0) == 84 && size_of(TKHD_V1) == 96)

_ELST :: struct #packed {
	using _vf:         Version_and_Flags,
	entry_count:       u32be,
}
#assert(size_of(_ELST) == 8)

ELST_Entry :: struct($type_width: typeid) #packed {
	segment_duration:  type_width,
	media_time:        i32be,
	media_rate:        Rational_16_16,
}
ELST_Entry_V0 :: distinct ELST_Entry(u32be)
ELST_Entry_V1 :: distinct ELST_Entry(u64be)
#assert(size_of(ELST_Entry_V0) == 12 && size_of(ELST_Entry_V1) == 16)

ELST :: struct($type_width: typeid) #packed {
	using header:      _ELST,
	entries:           [dynamic]ELST_Entry(type_width),
}
ELST_V0 :: distinct ELST(u32be)
ELST_V1 :: distinct ELST(u64be)

MDHD :: struct($type_width: typeid) #packed {
	using _vf:         Version_and_Flags,
	using _times:      Times(type_width),
	time_scale:        u32be,
	duration:          type_width,
	language:          ISO_639_2, // ISO-639-2/T language code
	quality:           u16be,
}
MDHD_V0 :: distinct MDHD(u32be)
MDHD_V1 :: distinct MDHD(u64be)
#assert(size_of(MDHD_V0) == 24 && size_of(MDHD_V1) == 36)

_HDLR :: struct #packed {
	using _vf:              Version_and_Flags,
	component_type:         FourCC,
	component_subtype:      FourCC,
	component_manufacturer: FourCC,
	component_flags:        u32be,
	reserved:               u32be,
}
#assert(size_of(_HDLR) == 24)

HDLR :: struct #packed {
	using _hdlr:            _HDLR,
	name:                   cstring,
}

META :: struct #packed {
	using vf:               Version_and_Flags,
}
#assert(size_of(META) == 4)

ILST_DATA_Type :: enum u32be {
	Binary =  0, // e.g. moov.udta.meta.ilst.trkn.data
	Text   =  1,

	JPEG   = 13, //      moov.udta.meta.ilst.covr.data
	PNG    = 14, //      moov.udta.meta.ilst.covr.data
}

/*
	Apple iTunes mdir metadata tag.
	Found as a child of the various tags under:
		`moov.udta.meta.ilst`
*/
_ILST_DATA :: struct {
	type:    ILST_DATA_Type,
	subtype: u32be,
}
#assert(size_of(_ILST_DATA) == 8)

iTunes_Metadata :: struct {
	using _ilst_data:       _ILST_DATA,

	data: union {
		[dynamic]u8, // Binary, JPEG, PNG and unknown sub-types
		cstring,     // Text
	},
}