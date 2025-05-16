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

	This file contains base type definitions.
*/

import "../common"

Error :: union #shared_nil {
	BMFF_Error,
	common.Error,
}

BMFF_Error :: enum {
	File_Not_Found,
	File_Not_Opened,
	File_Empty,
	File_Ended_Early,
	Read_Error,

	Wrong_File_Format,
	Error_Parsing_iTunes_Metadata,

	CHPL_Unknown_Version,
	CHPL_Invalid_Size,

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
	Root = 0,

	/*
		File type
	*/
	File_Type                                       = 'f' << 24 | 't' << 16 | 'y' << 8 | 'p', // 0x66747970

	/*
		Box types
	*/
	Data                                            = 'd' << 24 | 'a' << 16 | 't' << 8 | 'a', // 0x64617461

	Movie                                           = 'm' << 24 | 'o' << 16 | 'o' << 8 | 'v', // 0x6d6f6f76
		Movie_Header                            = 'm' << 24 | 'v' << 16 | 'h' << 8 | 'd', // 0x6d766864

		Track                                   = 't' << 24 | 'r' << 16 | 'a' << 8 | 'k', // 0x7472616b
			Edit                            = 'e' << 24 | 'd' << 16 | 't' << 8 | 's', // 0x65647473
				Edit_List               = 'e' << 24 | 'l' << 16 | 's' << 8 | 't', // 0x656c7374
			Media                           = 'm' << 24 | 'd' << 16 | 'i' << 8 | 'a', // 0x6d646961
				Handler_Reference       = 'h' << 24 | 'd' << 16 | 'l' << 8 | 'r', // 0x68646c72
				Media_Header            = 'm' << 24 | 'd' << 16 | 'h' << 8 | 'd', // 0x6d646864
				Media_Information       = 'm' << 24 | 'i' << 16 | 'n' << 8 | 'f', // 0x6d696e66
			Track_Header                    = 't' << 24 | 'k' << 16 | 'h' << 8 | 'd', // 0x746b6864

		User_Data                               = 'u' << 24 | 'd' << 16 | 't' << 8 | 'a', // 0x75647461
			Meta                            = 'm' << 24 | 'e' << 16 | 't' << 8 | 'a', // 0x6d657461
				/*
					Apple Metadata.
					Not part of ISO 14496-12-2015. 
				*/
				iTunes_Metadata         = 'i' << 24 | 'l' << 16 | 's' << 8 | 't', // 0x696c7374

				iTunes_Album            = '©' << 24 | 'a' << 16 | 'l' << 8 | 'b', // 0xa9616c62
				iTunes_Album_Artist     = 'a' << 24 | 'A' << 16 | 'R' << 8 | 'T', // 0x61415254
				iTunes_Author           = '©' << 24 | 'A' << 16 | 'R' << 8 | 'T', // 0xa9415254
				ìTunes_Category         = 'c' << 24 | 'a' << 16 | 't' << 8 | 'g', // 0x63617467
				iTunes_Comment          = '©' << 24 | 'c' << 16 | 'm' << 8 | 't', // 0xa9636d74
				iTunes_Composer         = '©' << 24 | 'w' << 16 | 'r' << 8 | 't', // 0xa9777274
				iTunes_Copyright        = 'c' << 24 | 'p' << 16 | 'r' << 8 | 't', // 0x63707274
				iTunes_Copyright_Alt    = '©' << 24 | 'c' << 16 | 'p' << 8 | 'y', // 0xa9637079
				iTunes_Cover            = 'c' << 24 | 'o' << 16 | 'v' << 8 | 'r', // 0x636f7672
				iTunes_Description      = 'd' << 24 | 'e' << 16 | 's' << 8 | 'c', // 0x64657363
				iTunes_Disk             = 'd' << 24 | 'i' << 16 | 's' << 8 | 'k', // 0x6469736b
				iTunes_Encoder          = '©' << 24 | 't' << 16 | 'o' << 8 | 'o', // 0xa9746f6f
				ìTunes_Episode_GUID     = 'e' << 24 | 'g' << 16 | 'i' << 8 | 'd', // 0x65676964
				iTunes_Episode_Name     = 't' << 24 | 'v' << 16 | 'e' << 8 | 'n', // 0x7476656e
				ìTunes_Gapless_Playback = 'p' << 24 | 'g' << 16 | 'a' << 8 | 'p', // 0x70676170
				iTunes_Genre            = '©' << 24 | 'g' << 16 | 'e' << 8 | 'n', // 0xa967656e
				iTunes_Grouping         = '©' << 24 | 'g' << 16 | 'r' << 8 | 'p', // 0xa9677270
				ìTunes_Keywords         = 'k' << 24 | 'e' << 16 | 'y' << 8 | 'w', // 0x6b657977
				ìTunes_Lyricist         = '©' << 24 | 's' << 16 | 'w' << 8 | 'f', // 0xa9737766
				iTunes_Lyrics           = '©' << 24 | 'l' << 16 | 'y' << 8 | 'r', // 0xa96c7972
				ìTunes_Media_Type       = 's' << 24 | 't' << 16 | 'i' << 8 | 'k', // 0x7374696b
				iTunes_Network          = 't' << 24 | 'v' << 16 | 'n' << 8 | 'n', // 0x74766e6e
				ìTunes_Performers       = '©' << 24 | 'p' << 16 | 'r' << 8 | 'f', // 0xa9707266
				ìTunes_Podcast          = 'p' << 24 | 'c' << 16 | 's' << 8 | 't', // 0x70637374
				ìTunes_Podcast_URL      = 'p' << 24 | 'u' << 16 | 'r' << 8 | 'l', // 0x7075726c
				ìTunes_Predefined_Genre = 'g' << 24 | 'n' << 16 | 'r' << 8 | 'e', // 0x676e7265
				ìTunes_Producer         = '©' << 24 | 'p' << 16 | 'r' << 8 | 'd', // 0xa9707264
				ìTunes_Purchase_Date    = 'p' << 24 | 'u' << 16 | 'r' << 8 | 'd', // 0x70757264
				ìTunes_Rating           = 'r' << 24 | 't' << 16 | 'n' << 8 | 'g', // 0x72746e67
				ìTunes_Record_Label     = '©' << 24 | 'l' << 16 | 'a' << 8 | 'b', // 0xa96c6162
				iTunes_Role             = 'r' << 24 | 'o' << 16 | 'l' << 8 | 'e', // 0x726f6c65
				iTunes_Show             = 't' << 24 | 'v' << 16 | 's' << 8 | 'h', // 0x74767368
				iTunes_Synopsis         = 'l' << 24 | 'd' << 16 | 'e' << 8 | 's', // 0x6c646573
				iTunes_Tempo            = 't' << 24 | 'm' << 16 | 'p' << 8 | 'o', // 0x746d706f
				iTunes_Title            = '©' << 24 | 'n' << 16 | 'a' << 8 | 'm', // 0xa96e616d
				iTunes_Track            = 't' << 24 | 'r' << 16 | 'k' << 8 | 'n', // 0x74726b6e
				iTunes_Year             = '©' << 24 | 'd' << 16 | 'a' << 8 | 'y', // 0xa9646179
				ìTunes_TV_Episode       = 't' << 24 | 'v' << 16 | 'e' << 8 | 's', // 0x74766573
				ìTunes_TV_Season        = 't' << 24 | 'v' << 16 | 's' << 8 | 'n', // 0x7476736e

				/*
					Special. Found at the end of M4A audio book metadata, for example.
					`----` has no data sub-node.
				*/
				iTunes_Extended         = '-' << 24 | '-' << 16 | '-' << 8 | '-', // 0x2d2d2d2d
					iTunes_Mean     = 'm' << 24 | 'e' << 16 | 'a' << 8 | 'n', //

	Movie_Fragment                                  = 'm' << 24 | 'o' << 16 | 'o' << 8 | 'f', // 0x6d6f6f66
		Track_Fragment                          = 't' << 24 | 'r' << 16 | 'a' << 8 | 'f', // 0x74726166
	Additional_Metadata_Container                   = 'm' << 24 | 'e' << 16 | 'c' << 8 | 'o', // 0x6d65636f

	Media_Data                                      = 'm' << 24 | 'd' << 16 | 'a' << 8 | 't', // 0x6d646174

	Chapter_List                                    = 'c' << 24 | 'h' << 16 | 'p' << 8 | 'l', // 0x6368706c
	Name                                            = 'n' << 24 | 'a' << 16 | 'm' << 8 | 'e', // 0x6e616d65
	Padding                                         = 'f' << 24 | 'r' << 16 | 'e' << 8 | 'e', // 0x66726565
	UUID                                            = 'u' << 24 | 'u' << 16 | 'i' << 8 | 'd', // 0x75756964

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
	Video = 'v' << 24 | 'i' << 16 | 'd' << 8 | 'e', // 0x76696465
	Sound = 's' << 24 | 'o' << 16 | 'u' << 8 | 'n', // 0x736f756e
	Text  = 't' << 24 | 'e' << 16 | 'x' << 8 | 't', // 0x74657874
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