package iso_bmff
/*
	Copyright 2021 Jeroen van Rijn <nom@duclavier.com>.
	Made available under Odin's BSD-3 license.

	A from-scratch implementation of ISO base media file format (ISOM),
	as specified in ISO/IEC 14496-12, Fifth edition 2015-12-15.
	The identical text is available as ISO/IEC 15444-12 (JPEG 2000, Part 12).

	See: https://www.iso.org/standard/68960.html and https://www.loc.gov/preservation/digital/formats/fdd/fdd000079.shtml

	This file contains base type definitions.
*/

import "../common"

Error :: enum {
	None = 0,
	File_Not_Found,
	File_Not_Opened,
	File_Empty,
	File_Ended_Early,
	Read_Error,

	Wrong_File_Format,
	Error_Parsing_iTunes_Metadata,

	ELST_Unknown_Version,
	ELST_Invalid_Size,

	FTYP_Duplicated,
	FTYP_Invalid_Size,

	HDLR_Unexpected_Parent,
	HDLR_Invalid_Size,

	MDHD_Unknown_Version,
	MDHD_Invalid_Size,

	MVHD_Unknown_Version,
	MVHD_Invalid_Size,

	TKHD_Unknown_Version,
	TKHD_Invalid_Size,
}

BCD4   :: distinct [4]u8

FourCC :: enum common.FourCC {
	/*
		File root dummy Box.
	*/
	_file_root = 0,

	/*
		Atoms
	*/
	ftyp = 'f' << 24 | 't' << 16 | 'y' << 8 | 'p', // 0x66747970

	moov = 'm' << 24 | 'o' << 16 | 'o' << 8 | 'v', // 0x6d6f6f76
		mvhd = 'm' << 24 | 'v' << 16 | 'h' << 8 | 'd', // 0x6d766864

		trak = 't' << 24 | 'r' << 16 | 'a' << 8 | 'k', // 0x7472616b
			tkhd = 't' << 24 | 'k' << 16 | 'h' << 8 | 'd', // 0x746b6864
			edts = 'e' << 24 | 'd' << 16 | 't' << 8 | 's', // 0x65647473
				elst = 'e' << 24 | 'l' << 16 | 's' << 8 | 't', // 0x656c7374
			mdia = 'm' << 24 | 'd' << 16 | 'i' << 8 | 'a', // 0x6d646961
				mdhd = 'm' << 24 | 'd' << 16 | 'h' << 8 | 'd', // 0x6d646864
				minf = 'm' << 24 | 'i' << 16 | 'n' << 8 | 'f', // 0x6d696e66
				hdlr = 'h' << 24 | 'd' << 16 | 'l' << 8 | 'r', // 0x68646c72

		udta = 'u' << 24 | 'd' << 16 | 't' << 8 | 'a', // 0x75647461
			meta = 'm' << 24 | 'e' << 16 | 't' << 8 | 'a', // 0x6d657461
				/*
					Apple Metadata.
					Not part of ISO 14496-12-2015. 
				*/
				ilst = 'i' << 24 | 'l' << 16 | 's' << 8 | 't', // 0x696c7374

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
	   				itunes_cover = 'c' << 24 | 'o' << 16 | 'v' << 8 | 'r', // 0x636f7672
						data = 'd' << 24 | 'a' << 16 | 't' << 8 | 'a', // 0x64617461

	   				/*
						Special. Found at the end of M4A audio book metadata, for example.
						`----` has no data sub-node.
	   				*/
	   				itunes_4_dashes = '-' << 24 | '-' << 16 | '-' << 8 | '-', // 0x2d2d2d2d
	   					itunes_mean = 'm' << 24 | 'e' << 16 | 'a' << 8 | 'n', // 

	moof = 'm' << 24 | 'o' << 16 | 'o' << 8 | 'f', // 0x6d6f6f66
		traf = 't' << 24 | 'r' << 16 | 'a' << 8 | 'f', // 0x74726166
	meco = 'm' << 24 | 'e' << 16 | 'c' << 8 | 'o', // 0x6d65636f
	free = 'f' << 24 | 'r' << 16 | 'e' << 8 | 'e', // 0x66726565
	mdat = 'm' << 24 | 'd' << 16 | 'a' << 8 | 't', // 0x6d646174
	uuid = 'u' << 24 | 'u' << 16 | 'i' << 8 | 'd', // 0x75756964
	name = 'n' << 24 | 'a' << 16 | 'm' << 8 | 'e', // 0x6e616d65

	/*
		Brands
	*/
	isom = 'i' << 24 | 's' << 16 | 'o' << 8 | 'm', // 0x69736f6d
	iso2 = 'i' << 24 | 's' << 16 | 'o' << 8 | '2', // 0x69736f32
	iso3 = 'i' << 24 | 's' << 16 | 'o' << 8 | '3', // 0x69736f33
	iso4 = 'i' << 24 | 's' << 16 | 'o' << 8 | '4', // 0x69736f34
	iso5 = 'i' << 24 | 's' << 16 | 'o' << 8 | '5', // 0x69736f35
	iso6 = 'i' << 24 | 's' << 16 | 'o' << 8 | '6', // 0x69736f36
	iso7 = 'i' << 24 | 's' << 16 | 'o' << 8 | '7', // 0x69736f37
	iso8 = 'i' << 24 | 's' << 16 | 'o' << 8 | '8', // 0x69736f38
	iso9 = 'i' << 24 | 's' << 16 | 'o' << 8 | '9', // 0x69736f39

	avc1 = 'a' << 24 | 'v' << 16 | 'c' << 8 | '1', // 0x61766331
	mp41 = 'm' << 24 | 'p' << 16 | '4' << 8 | '1', // 0x6d703431
	mp42 = 'm' << 24 | 'p' << 16 | '4' << 8 | '2', // 0x6d703432
	mp71 = 'm' << 24 | 'p' << 16 | '7' << 8 | '1', // 0x6d703731

	m4a_ = 'm' << 24 | '4' << 16 | 'a' << 8 | ' ', // 0x4d344120

	/*
		Handler types
	*/
	video = 'v' << 24 | 'i' << 16 | 'd' << 8 | 'e', // 0x76696465
	sound = 's' << 24 | 'o' << 16 | 'u' << 8 | 'n', // 0x736f756e
}

/*
	UUIDs are compliant with RFC 4122: A Universally Unique IDentifier (UUID) URN Namespace
	                         (https://www.rfc-editor.org/rfc/rfc4122.html)
*/
UUID :: common.UUID_RFC_4122

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
#assert(size_of(View_Matrix) == 9 * size_of(u32be))

MVHD_Predefined :: struct {
	foo: [6]u32be,
}