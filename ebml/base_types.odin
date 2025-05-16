package ebml
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


	A from-scratch implementation of the Extensible Binary Meta Language (EBML),
	as specified in [IETF RFC 8794](https://www.rfc-editor.org/rfc/rfc8794).

	The EBML format is the base format upon which Matroska (MKV) and WebM are based.

	This file contains the base EBML types.
*/

import "core:os"
import "core:mem"
import "core:time"
import "../common"

Matroska_UUID :: common.UUID_RFC_4122
Matroska_Time :: time.Time

/*
	Version of the EBML specification we support. As of the time of writing, only EBML v1 exists.
*/
EBML_VERSION       :: 1
MAX_DOCTYPE_LENGTH :: 1_024

Error :: enum {
	None = 0,
	File_Not_Found,
	File_Not_Opened,
	File_Empty,
	File_Ended_Early,
	Read_Error,

	EBML_Header_Missing_or_Corrupt,
	EBML_Header_Unexpected_Field_Length,
	EBML_Header_Duplicated,

	Element_out_of_Range,
	Unsupported_EBML_Version,
	DocType_Empty,
	DocType_Too_Long,
	DocTypeVersion_Invalid,
	DocTypeReadVersion_Invalid,
	Max_ID_Length_Invalid,
	Max_Size_Invalid,
	Invalid_CRC_Size,
	Invalid_CRC,
	Validation_Failed,
	Unsigned_Invalid_Length,
	Signed_Invalid_Length,
	Float_Invalid_Length,
	Matroska_Track_Type_Invalid_Length,

	VINT_All_Zeroes,
	VINT_All_Ones,
	VINT_Out_of_Range,

	Unprintable_String,
	Wrong_File_Format,

	Matroska_Body_Root_Wrong_ID,
	Matroska_Broken_SeekPosition,
	Matroska_SegmentUID_Invalid_Length,
}

/*
	RFC 8794 - An EBML Stream is a file that consists of one or more EBML Documents that are concatenated
	together. An occurrence of an EBML Header at the Root Level marks the beginning of an EBML Document.
*/
EBML_Document :: struct {
	header:               ^EBML_Element,
	body:                 ^EBML_Element,

	/*
		Useful document variables.
	*/
	version:              u8,     // EBMLVersion
	read_version:         u8,     // EBMLReadVersion
	doctype:              String, // DocType
	doctype_version:      u8,     // EBMLDocTypeVersion
	doctype_read_version: u8,     // EBMLDocTypeReadVersion
	max_id_length:        u8,     // EBMLMaxIDLength
	max_size_length:      u8,     // EBMLMaxSizeLength
}

EBML_File :: struct {
	documents:   [dynamic]^EBML_Document,

	/*
		Implementation
	*/
	file_info: os.File_Info,
	handle:    os.Handle,
	allocator: mem.Allocator,
}

VINT_MAX :: (1 << 56) - 1   // 72,057,594,037,927,934
String   :: distinct string // Printable string only, RFC 0020
Date     :: distinct i64    // Default value: 2001-01-01T00:00:00.000000000 UTC, RFC 3339.

Matroska_Track_Type :: enum u8 {
	Video    = 1,
	Audio    = 2,
	Complex  = 3,
	Logo     = 16,
	Subtitle = 17,
	Buttons  = 18,
	Control  = 32,
	Metadata = 33,
}

Payload_Types :: union {
	i64,
	u64,
	f64,
	String,
	string,
	Date,
	[dynamic]u8,

	Matroska_UUID,
	Matroska_Time,
	Matroska_Track_Type,
}

EBML_Element :: struct {
	/*
		Element file offset, and size including header.
	*/
	offset:         i64,
	size:           i64,
	end:            i64,

	payload_offset: i64,
	payload_size:   i64,

	parent:         ^EBML_Element,
	next:           ^EBML_Element,
	first_child:    ^EBML_Element,

	id:             EBML_ID,
	type:           EBML_Type,
	level:          int,

	/*
		Payload can be empty
	*/
	payload:        Payload_Types,
}

EBML_Type :: enum {
	Unhandled, // Not (yet) handled.

	Signed,    // Section 7.1 of RFC 8794
	Unsigned,  // Section 7.2 of RFC 8794
	Float,     // Section 7.3 of RFC 8794
	String,    // Section 7.4 of RFC 8794
	UTF_8,     // Section 7.5 of RFC 8794
	Date,      // Section 7.6 of RFC 8794
	Master,    // Section 7.7 of RFC 8794
	Binary,    // Section 7.8 of RFC 8794

	/*
		Custom types for Matroska
	*/
	Matroska_UUID,
	Matroska_Time,
	Matroska_Track_Type,
}

EBML_ID :: enum u64be {
	/*
		=================== =================== EBML IDs =================== ===================
		As specified in IETF RFC 8794. See: https://datatracker.ietf.org/doc/rfc8794/
		=================== =================== EBML IDs =================== ===================
	*/

	/*
		Every EBML Document has to start with this ID.
		Described in Section 11.2.1 of RFC 8794.
	*/
	EBML                               = 0x1A_45_DF_A3,

	/*
		Version of the EBML specifications used to create the EBML document.
		Described in Section 11.2.2 of RFC 8794.
	*/
	EBMLVersion                        = 0x4286,

	/*
		The minimum EBML version a reader has to support to read this document.
		Described in Section 11.2.3 of RFC 8794.
	*/
	EBMLReadVersion                    = 0x42F7,

	/*
		The EBMLMaxIDLength Element stores the maximum permitted length in octets of the Element
			IDs to be found within the EBML Body.
		Described in Section 11.2.4 of RFC 8794.
	*/
	EBMLMaxIDLength                    = 0x42F2,

	/*
		The EBMLMaxSizeLength Element stores the maximum permitted length in octets of the
			expressions of all Element Data Sizes to be found within the EBML Body.
		Described in Section 11.2.5 of RFC 8794.
	*/
	EBMLMaxSizeLength                  = 0x42F3,
										
	/*
		A string that describes and identifies the content of the EBML Body that follows this EBML Header.
		Described in Section 11.2.6 of RFC 8794.
	*/
	DocType                            = 0x4282,

	/*
		The version of DocType interpreter used to create the EBML Document.
		Described in Section 11.2.7 of RFC 8794.
	*/
	DocTypeVersion                     = 0x4287,

	/*
		The minimum DocType version an EBML Reader has to support to read this EBML Document.
		Described in Section 11.2.8 of RFC 8794.
	*/
	DocTypeReadVersion                 = 0x4285,

	/*
		A DocTypeExtension adds extra Elements to the main DocType+DocTypeVersion tuple it's attached to.
		Described in Section 11.2.9 of RFC 8794.
	*/
	DocTypeExtension                   = 0x4281,

	/*
		The name of the DocTypeExtension to differentiate it from other DocTypeExtensions
			of the same DocType+DocTypeVersion tuple.
		Described in Section 11.2.10 of RFC 8794.
	*/
	DocTypeExtensionName               = 0x4283,

	/*
		The version of the DocTypeExtension. Different DocTypeExtensionVersion values of the same
			DocType + DocTypeVersion + DocTypeExtensionName tuple contain completely different sets of extra Elements.
		Described in Section 11.2.11 of RFC 8794.
	*/
	DocTypeExtensionVersion            = 0x4284,

	/*
		The CRC-32 Element contains a 32-bit Cyclic Redundancy Check value of all the
			Element Data of the Parent Element as stored except for the CRC-32 Element itself. 
		Described in Section 11.3.1 of RFC 8794.
	*/
	CRC_32                             = 0xBF,

	/*
		Used to void data or to avoid unexpected behaviors when using damaged data. The
			content is discarded. Also used to reserve space in a subelement for later use. 
		Described in Section 11.3.2 of RFC 8794.
	*/
	Void                               = 0xEC,

	/*
		=================== =================== MATROSKA IDs =================== ===================
		As specified in IETF draft draft-ietf-cellar-matroska-08
		See: https://www.ietf.org/archive/id/draft-ietf-cellar-matroska-08.html#name-segment-element
		=================== =================== MATROSKA IDs =================== ===================
	*/

	/*
		The Root Element that contains all other Top-Level Elements (Elements defined only at Level 1).
			A Matroska file is composed of 1 Segment.
		Described in Section 8.1 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_Segment                            = 0x18538067,

	/*
		Contains the Segment Position of other Top-Level Elements.
		Described in Section 8.1.1 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_SeekHead                           = 0x114D9B74,

	/*
		Contains a single seek entry to an EBML Element.
		Described in Section 8.1.1.1 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_Seek                               = 0x4DBB,

	/*
		The binary ID corresponding to the Element name.
		Described in Section 8.1.1.1.1 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_SeekID                             = 0x53AB,

	/*
		The Segment Position of the Element.
		Described in Section 8.1.1.1.2 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_SeekPosition                       = 0x53AC,

	/*
		Contains general information about the Segment.
		Described in Section 8.1.2 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_Info                               = 0x1549A966,

	/*
		A randomly generated unique ID to identify the Segment amongst many others (128 bits).
		Described in Section 8.1.2.1 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_SegmentUID                         = 0x73A4,

	/*
		A filename corresponding to this Segment.
		Described in Section 8.1.2.2 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_SegmentFilename                    = 0x7384,

	/*
		A unique ID to identify the previous Segment of a Linked Segment (128 bits).
		Described in Section 8.1.2.3 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_PrevUID                            = 0x3CB923,

	/*
		A filename corresponding to the file of the previous Linked Segment.
		Described in Section 8.1.2.4 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_PrevFilename                       = 0x3C83AB,

	/*
		A unique ID to identify the previous Segment of a Linked Segment (128 bits).
		Described in Section 8.1.2.5 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_NextUID                            = 0x3EB923,

	/*
		A filename corresponding to the file of the previous Linked Segment.
		Described in Section 8.1.2.6 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_NextFilename                       = 0x3E83BB,

	/*
		A randomly generated unique ID that all Segments of a Linked Segment MUST share (128 bits).
		Described in Section 8.1.2.7 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_SegmentFamily                      = 0x4444,

	/*
		A tuple of corresponding ID used by chapter codecs to represent this Segment.
		Described in Section 8.1.2.8 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ChapterTranslate                   = 0x6924,

	/*
		Specify an edition UID on which this correspondence applies. When not specified,
			it means for all editions found in the Segment.
		Described in Section 8.1.2.8.1 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ChapterTranslateEditionUID         = 0x69FC,

	/*
		The chapter codec; see Section 8.1.7.1.4.15.
		Described in Section 8.1.2.8.2 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ChapterTranslateCodec              = 0x69BF,

	/*
		The binary value used to represent this Segment in the chapter codec data.
		The format depends on the ChapProcessCodecID used; see Section 8.1.7.1.4.15.

		Described in Section 8.1.2.8.3 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ChapterTranslateID                 = 0x69A5,

	/*
		Timestamp scale in nanoseconds (1_000_000 means all timestamps in the Segment are expressed in milliseconds).

		Described in Section 8.1.2.9 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_TimestampScale                     = 0x2AD7B1,

	/*
		Duration of the Segment in nanoseconds based on TimestampScale.

		Described in Section 8.1.2.10 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_Duration                           = 0x4489,

	/*
		The date and time that the Segment was created by the muxing application or library.

		Described in Section 8.1.2.11 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_DateUTC                            = 0x4461,

	/*
		General name of the Segment.

		Described in Section 8.1.2.12 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_Title                              = 0x7BA9,

	/*
		Muxing application or library (example: "libmatroska-0.4.3").

		Described in Section 8.1.2.13 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_MuxingApp                          = 0x4D80,

	/*
		Writing application (example: "mkvmerge-0.3.3").

		Described in Section 8.1.2.14 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_WritingApp                         = 0x5741,

	/*
		The Top-Level Element containing the (monolithic) Block structure.

		Described in Section 8.1.3 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_Cluster                            = 0x1F43B675,

	/*
		Absolute timestamp of the cluster (based on TimestampScale).

		Described in Section 8.1.3.1 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_Timestamp                          = 0xE7,

	/*
		The Segment Position of the Cluster in the Segment (0 in live streams).
		It might help to resynchronise offset on damaged streams.

		Described in Section 8.1.3.2 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_Position                           = 0xA7,

	/*
		Size of the previous Cluster, in octets. Can be useful for backward playing.

		Described in Section 8.1.3.3 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_PrevSize                           = 0xAB,

	/*
		Similar to Block, see Section 12, but without all the extra information,
			mostly used to reduce overhead when no extra feature is needed;
			see Section 12.4 on SimpleBlock Structure.

		Described in Section 8.1.3.4 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_SimpleBlock                        = 0xA3,

	/*
		Basic container of information containing a single Block and information specific to that Block.

		Described in Section 8.1.3.5 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_BlockGroup                         = 0xA0,

	/*
		Block containing the actual data to be rendered and a timestamp relative to the
			Cluster Timestamp; see Section 12 on Block Structure.

		Described in Section 8.1.3.5.1 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_Block                              = 0xA1,

	/*
		Contain additional blocks to complete the main one. An EBML parser that has no knowledge
			of the Block structure could still see and use/skip these data.

		Described in Section 8.1.3.5.2 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_BlockAdditions                     = 0x75A1,

	/*
		Contain the BlockAdditional and some parameters.

		Described in Section 8.1.3.5.2.1 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_BlockMore                          = 0xA6,

	/*
		An ID to identify the BlockAdditional level. If BlockAddIDType of the corresponding block is 0,
			this value is also the value of BlockAddIDType for the meaning of the content of BlockAdditional.

		Described in Section 8.1.3.5.2.2 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_BlockAddID                         = 0xEE,

	/*
		Interpreted by the codec as it wishes (using the BlockAddID).

		Described in Section 8.1.3.5.2.3 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_BlockAdditional                    = 0xA5,

	/*
		The duration of the Block (based on TimestampScale). The BlockDuration Element can be useful at the end
			of a Track to define the duration of the last frame (as there is no subsequent Block available),
			or when there is a break in a track like for subtitle tracks.

		Described in Section 8.1.3.5.3 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_BlockDuration                      = 0x9B,

	/*
		This frame is referenced and has the specified cache priority. In cache only a frame of the
			same or higher priority can replace this frame. A value of 0 means the frame is not referenced.

		Described in Section 8.1.3.5.4 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ReferencePriority                  = 0xFA,

	/*
		Timestamp of another frame used as a reference (ie: B or P frame). The timestamp is relative
			to the block it's attached to.

		Described in Section 8.1.3.5.5 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ReferenceBlock                     = 0xFB,

	/*
		The new codec state to use. Data interpretation is private to the codec.
			This information SHOULD always be referenced by a seek entry.

		Described in Section 8.1.3.5.6 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_CodecState                         = 0xA4,

	/*
		Duration in nanoseconds of the silent data added to the Block (padding at the end of the Block
			for positive value, at the beginning of the Block for negative value). The duration of
			DiscardPadding is not calculated in the duration of the TrackEntry and SHOULD be discarded
			during playback.

		Described in Section 8.1.3.5.7 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_DiscardPadding                     = 0x75A2,

	/*
		Contains slices description.

		Described in Section 8.1.3.5.8 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_Slices                             = 0x8E,

	/*
		Contains extra time information about the data contained in the Block.
			Being able to interpret this Element is not REQUIRED for playback.

		Described in Section 8.1.3.5.8.1 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_TimeSlice                          = 0xE8,

	/*
		The reverse number of the frame in the lace (0 is the last frame, 1 is the next to last, etc).
			Being able to interpret this Element is not REQUIRED for playback.

		Described in Section 8.1.3.5.8.2 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_LaceNumber                         = 0xCC,

	/*
		A Top-Level Element of information with many tracks described.

		Described in Section 8.1.4 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_Tracks                             = 0x1654AE6B,

	/*
		Describes a track with all Elements.

		Described in Section 8.1.4.1 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_TrackEntry                         = 0xAE,

	/*
		The track number as used in the Block Header (using more than 127 tracks is not encouraged,
			though the design allows an unlimited number).

		Described in Section 8.1.4.1.1 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_TrackNumber                        = 0xD7,

	/*
		The value of this Element SHOULD be kept the same when making a direct stream copy to another file.

		Described in Section 8.1.4.1.2 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_TrackUID                           = 0x73C5,

	/*
		A set of track types coded on 8 bits.

		Described in Section 8.1.4.1.3 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_TrackType                          = 0x83,

	/*
		Set to 1 if the track is usable. It is possible to turn a not usable track into a
			usable track using chapter codecs or control tracks.

		Described in Section 8.1.4.1.4 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_FlagEnabled                        = 0xB8,

	/*
		Set if that track (audio, video or subs) SHOULD be eligible for automatic selection by the player;
			see Section 21 for more details.

		Described in Section 8.1.4.1.5 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_FlagDefault                        = 0x88,

	/*
		Applies only to subtitles. Set if that track SHOULD be eligible for automatic selection by the player
			if it matches the user's language preference, even if the user's preferences would normally not
			enable subtitles with the selected audio track; this can be used for tracks containing only
			translations of foreign-language audio or onscreen text. See Section 21 for more details.

		Described in Section 8.1.4.1.6 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_FlagForced                         = 0x55AA,

	/*
		Set to 1 if that track is suitable for users with hearing impairments,
		set to 0 if it is unsuitable for users with hearing impairments.

		Described in Section 8.1.4.1.7 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_FlagHearingImpaired                = 0x55AB,

	/*
		Set to 1 if that track is suitable for users with visual impairments,
		set to 0 if it is unsuitable for users with visual impairments.

		Described in Section 8.1.4.1.8 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_FlagVisualImpaired                 = 0x55AC,

	/*
		Set to 1 if that track contains textual descriptions of video content,
		set to 0 if that track does not contain textual descriptions of video content.

		Described in Section 8.1.4.1.9 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_FlagTextDescriptions               = 0x55AD,

	/*
		Set to 1 if that track is in the content's original language,
		set to 0 if it is a translation.

		Described in Section 8.1.4.1.10 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_FlagOriginal                       = 0x55AE,

	/*
		Set to 1 if that track contains commentary,
		set to 0 if it does not contain commentary.

		Described in Section 8.1.4.1.11 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_FlagCommentary                     = 0x55AF,

	/*
		Set to 1 if the track MAY contain blocks using lacing.

		Described in Section 8.1.4.1.12 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_FlagLacing                         = 0x9C,

	/*
		The minimum number of frames a player SHOULD be able to cache during playback.
		If set to 0, the reference pseudo-cache system is not used.

		Described in Section 8.1.4.1.13 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_MinCache                           = 0x6DE7,

	/*
		The maximum cache size necessary to store referenced frames in and the current frame.
		0 means no cache is needed.

		Described in Section 8.1.4.1.14 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_MaxCache                           = 0x6DF8,

	/*
		Number of nanoseconds (not scaled via TimestampScale) per frame
		(frame in the Matroska sense -- one Element put into a (Simple)Block).

		Described in Section 8.1.4.1.15 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_DefaultDuration                    = 0x23E383,

	/*
		The period in nanoseconds (not scaled by TimestampScale) between two successive fields at
		the output of the decoding process, see Section 11 for more information

		Described in Section 8.1.4.1.16 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_DefaultDecodedFieldDuration        = 0x234E7A,

	/*
		DEPRECATED, DO NOT USE. The scale to apply on this track to work at normal speed in relation with other tracks
		(mostly used to adjust video speed when the audio length differs).

		Described in Section 8.1.4.1.17 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_TrackTimestampScale                = 0x23314F,

	/*
		The maximum value of BlockAddID (Section 8.1.3.5.2.2).
		A value 0 means there is no BlockAdditions (Section 8.1.3.5.2) for this track.

		Described in Section 8.1.4.1.18 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_MaxBlockAdditionID                 = 0x55EE,

	/*
		Contains elements that extend the track format, by adding content either to each frame,
		with BlockAddID (Section 8.1.3.5.2.2), or to the track as a whole with BlockAddIDExtraData.

		Described in Section 8.1.4.1.19 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_BlockAdditionMapping               = 0x41E4,

	/*
		If the track format extension needs content beside frames, the value refers to the BlockAddID
		(Section 8.1.3.5.2.2), value being described. To keep MaxBlockAdditionID as low as possible,
		small values SHOULD be used.

		Described in Section 8.1.4.1.19.1 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_BlockAddIDValue                    = 0x41F0,

	/*
		A human-friendly name describing the type of BlockAdditional data,
		as defined by the associated Block Additional Mapping.

		Described in Section 8.1.4.1.19.2 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_BlockAddIDName                     = 0x41A4,

	/*
		Stores the registered identifier of the Block Additional Mapping to define how the
		BlockAdditional data should be handled.

		Described in Section 8.1.4.1.19.3 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_BlockAddIDType                     = 0x41E7,

	/*
		Extra binary data that the BlockAddIDType can use to interpret the BlockAdditional data.
		The interpretation of the binary data depends on the BlockAddIDType value and the corresponding
		Block Additional Mapping.

		Described in Section 8.1.4.1.19.4 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_BlockAddIDExtraData                = 0x41ED,

	/*
		A human-readable track name.

		Described in Section 8.1.4.1.20 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_Track_Name                         = 0x536E,

	/*
		Specifies the language of the track in the Matroska languages form; see Section 6 on language codes.
		This Element MUST be ignored if the LanguageIETF Element is used in the same TrackEntry.

		Described in Section 8.1.4.1.21 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_Language                           = 0x22B59C,

	/*
		Specifies the language of the track according to [BCP47] and using the IANA Language Subtag Registry
		[IANALangRegistry]. If this Element is used, then any Language Elements used in the same TrackEntry
		MUST be ignored.

		Described in Section 8.1.4.1.22 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_Language_IETF                      = 0x22B59D,

	/*
		An ID corresponding to the codec, see [MatroskaCodec] for more info.

		Described in Section 8.1.4.1.23 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_CodecID                            = 0x86,

	/*
		Private data only known to the codec.

		Described in Section 8.1.4.1.24 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_CodecPrivate                       = 0x63A2,

	/*
		A human-readable string specifying the codec.

		Described in Section 8.1.4.1.25 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_CodecName                          = 0x258688,

	/*
		The UID of an attachment that is used by this codec.

		Described in Section 8.1.4.1.26 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_AttachmentLink                     = 0x7446,

	/*
		Specify that this track is an overlay track for the Track specified (in the u-integer).
		That means when this track has a gap, see Section 26.3.1 on SilentTracks, the overlay track
		SHOULD be used instead.

		Described in Section 8.1.4.1.27 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_TrackOverlay                       = 0x6FAB,

	/*
		CodecDelay is The codec-built-in delay in nanoseconds. This value MUST be subtracted from each block
		timestamp in order to get the actual timestamp. The value SHOULD be small so the muxing of tracks with
		the same actual timestamp are in the same Cluster.

		Described in Section 8.1.4.1.28 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_CodecDelay                         = 0x56AA,

	/*
		After a discontinuity, SeekPreRoll is the duration in nanoseconds of the data the decoder
		MUST decode before the decoded data is valid.

		Described in Section 8.1.4.1.29 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_SeekPreRoll                        = 0x56BB,

	/*
		The track identification for the given Chapter Codec.

		Described in Section 8.1.4.1.30 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_TrackTranslate                     = 0x6624,

	/*
		Specify an edition UID on which this translation applies.
		When not specified, it means for all editions found in the Segment.

		Described in Section 8.1.4.1.30.1 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_TrackTranslateEditionUID           = 0x66FC,

	/*
		The chapter codec; see Section 8.1.7.1.4.15.

		Described in Section 8.1.4.1.30.2 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_TrackTranslateCodec                = 0x66BF,

	/*
		The binary value used to represent this track in the chapter codec data.
		The format depends on the ChapProcessCodecID used; see Section 8.1.7.1.4.15.

		Described in Section 8.1.4.1.30.3 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_TrackTranslateTrackID              = 0x66A5,

	/*
		Video settings.

		Described in Section 8.1.4.1.31 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_Video                              = 0xE0,

	/*
		Specify whether the video frames in this track are interlaced or not.

		Described in Section 8.1.4.1.31.1 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_FlagInterlaced                     = 0x9A,

	/*
		Specify the field ordering of video frames in this track.

		Described in Section 8.1.4.1.31.2 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_FieldOrder                         = 0x9D,

	/*
		Stereo-3D video mode. There are some more details in Section 20.10.

		Described in Section 8.1.4.1.31.3 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_StereoMode                         = 0x53B8,

	/*
		Alpha Video Mode. Presence of this Element indicates that the BlockAdditional Element could contain Alpha data.

		Described in Section 8.1.4.1.31.4 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_AlphaMode                          = 0x53C0,

	/*
		Width, Height of the encoded video frames in pixels.

		Described in Section 8.1.4.1.31.5 .. 6 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_PixelWidth                         = 0xB0,
	Matroska_PixelHeight                        = 0xBA,

	/*
		The number of video pixels to remove at the bottom, top, left, right of the image.

		Described in Section 8.1.4.1.31.7 .. 10 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_PixelCropBottom                    = 0x54AA,
	Matroska_PixelCropTop                       = 0x54BB,
	Matroska_PixelCropLeft                      = 0x54CC,
	Matroska_PixelCropRight                     = 0x54DD,

	/*
		Display Width + Height, and how DisplayWidth & DisplayHeight are interpreted.

		Described in Section 8.1.4.1.31.11 .. 13 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_DisplayWidth                       = 0x54B0,
	Matroska_DisplayHeight                      = 0x54BA,
	Matroska_DisplayUnit                        = 0x54B2,

	/*
		Specify the pixel format used for the Track's data as a FourCC.
		This value is similar in scope to the biCompression value of AVI's BITMAPINFOHEADER.

		Described in Section 8.1.4.1.31.14 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ColourSpace                        = 0x2EB524,

	/*
		Settings describing the colour format.

		Described in Section 8.1.4.1.31.15 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_Colour                             = 0x55B0,

	/*
		The Matrix Coefficients of the video used to derive luma and chroma values from
		red, green, and blue color primaries. For clarity, the value and meanings for
		MatrixCoefficients are adopted from Table 4 of ISO/IEC 23001-8:2016 or ITU-T H.273.

		Described in Section 8.1.4.1.31.16 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_MatrixCoefficients                 = 0x55B1,

	/*
		Number of decoded bits per channel. A value of 0 indicates that the BitsPerChannel is unspecified.

		Described in Section 8.1.4.1.31.17 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_BitsPerChannel                     = 0x55B2,

	/*
		The amount of pixels to remove in the Cr and Cb channels for every pixel not removed horizontally.
		Example: For video with 4:2:0 chroma subsampling, the ChromaSubsamplingHorz SHOULD be set to 1.

		The amount of pixels to remove in the Cr and Cb channels for every pixel not removed vertically.
		Example: For video with 4:2:0 chroma subsampling, the ChromaSubsamplingVert SHOULD be set to 1.

		Described in Section 8.1.4.1.31.18 .. 23 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ChromaSubsamplingHorz              = 0x55B3,
	Matroska_ChromaSubsamplingVert              = 0x55B4,
	Matroska_CbSubsamplingHorz                  = 0x55B5,
	Matroska_CbSubsamplingVert                  = 0x55B6,
	Matroska_ChromaSitingHorz                   = 0x55B7,
	Matroska_ChromaSitingVert                   = 0x55B8,

	/*
		Clipping of the color ranges.

		Described in Section 8.1.4.1.31.24 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_Range                              = 0x55B9,

	/*
		The transfer characteristics of the video. For clarity, the value and meanings for
		TransferCharacteristics are adopted from Table 3 of ISO/IEC 23091-4 or ITU-T H.273.

		The colour primaries of the video. For clarity, the value and meanings for Primaries
		are adopted from Table 2 of ISO/IEC 23091-4 or ITU-T H.273.

		Described in Section 8.1.4.1.31.25 .. 26 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_TransferCharacteristics            = 0x55BA,
	Matroska_Primaries                          = 0x55BB,


	/*
		Maximum brightness of a single pixel (Maximum Content Light Level) in candelas per square meter (cd/m2).
		Maximum brightness of a single full frame (Maximum Frame-Average Light Level) in candelas per square meter (cd/m2).

		Described in Section 8.1.4.1.31.27 .. 28 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_MaxCLL                             = 0x55BC,
	Matroska_MaxFALL                            = 0x55BD,

	/*
		SMPTE 2086 mastering data.

		Described in Section 8.1.4.1.31.29 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_MasteringMetadata                  = 0x55D0,

	/*
		RGB-W chromaticity coordinates, as defined by CIE 1931.

		Described in Section 8.1.4.1.31.30 .. 37 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_PrimaryRChromaticityX              = 0x55D1,
	Matroska_PrimaryRChromaticityY              = 0x55D2,
	Matroska_PrimaryGChromaticityX              = 0x55D3,
	Matroska_PrimaryGChromaticityY              = 0x55D4,
	Matroska_PrimaryBChromaticityX              = 0x55D5,
	Matroska_PrimaryBChromaticityY              = 0x55D6,
	Matroska_WhitePointChromaticityX            = 0x55D7,
	Matroska_WhitePointChromaticityY            = 0x55D8,

	/*
		Maximum/Minimum luminance. Represented in candelas per square meter (cd/m2).

		Described in Section 8.1.4.1.31.38 .. 39 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_LuminanceMax                       = 0x55D9,
	Matroska_LuminanceMin                       = 0x55DA,

	/*
		* Describes the video projection details. Used to render spherical and VR videos.
		* Describes the projection used for this video track.
		* Private data that only applies to a specific projection.

		Described in Section 8.1.4.1.31.40 .. 42 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_Projection                         = 0x7670,
	Matroska_ProjectionType                     = 0x7671,
	Matroska_ProjectionPrivate                  = 0x7672,

	/*
		Projection vector rotation.

		Described in Section 8.1.4.1.31.43 .. 45 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ProjectionPoseYaw                  = 0x7673,
	Matroska_ProjectionPosePitch                = 0x7674,
	Matroska_ProjectionPoseRoll                 = 0x7675,

	/*
		Audio settings.

		Described in Section 8.1.4.1.32 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_Audio                              = 0xE1,
	Matroska_SamplingFrequency                  = 0xB5,
	Matroska_OutputSamplingFrequency            = 0x78B5,
	Matroska_Channels                           = 0x9F,
	Matroska_BitDepth                           = 0x6264,

	/*
		Operation that needs to be applied on tracks to create this virtual track.
		For more details look at Section 20.8.

		Contains the list of all video plane tracks that need to be combined to create this 3D track.

		Contains a video plane track that need to be combined to create this 3D track.

		Described in Section 8.1.4.1.33 .. 33.2 of IETF draft-ietf-cellar-matroska-08	
	*/
	Matroska_TrackOperation                     = 0xE2,
	Matroska_TrackCombinePlanes                 = 0xE3,
	Matroska_TrackPlane                         = 0xE4,

	/*
		The trackUID number of the track representing the plane.
		The kind of plane this track corresponds to.

		Described in Section 8.1.4.1.33.3 .. 4 of IETF draft-ietf-cellar-matroska-08	
	*/
	Matroska_TrackPlaneUID                      = 0xE5,
	Matroska_TrackPlaneType                     = 0xE6,

	/*
		Contains the list of all tracks whose Blocks need to be combined to create this virtual track.

		Described in Section 8.1.4.1.33.5 of IETF draft-ietf-cellar-matroska-08	
	*/
	Matroska_TrackJoinBlocks                    = 0xE9,

	/*
		The trackUID number of a track whose blocks are used to create this virtual track.

		Described in Section 8.1.4.1.33.6 of IETF draft-ietf-cellar-matroska-08	
	*/
	Matroska_TrackJoinUID                       = 0xED,

	/*
		Settings for several content encoding mechanisms like compression or encryption.

		Described in Section 8.1.4.1.34 of IETF draft-ietf-cellar-matroska-08	
	*/
	Matroska_ContentEncodings                   = 0x6D80,

	/*
		Settings for one content encoding like compression or encryption.

		Described in Section 8.1.4.1.34.1 of IETF draft-ietf-cellar-matroska-08	
	*/
	Matroska_ContentEncoding                    = 0x6240,

	/*
		Tells when this modification was used during encoding/muxing starting with 0 and counting upwards.
		The decoder/demuxer has to start with the highest order number it finds and work its way down.
		This value has to be unique over all ContentEncodingOrder Elements in the TrackEntry that
		contains this ContentEncodingOrder element.

		Described in Section 8.1.4.1.34.2 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ContentEncodingOrder               = 0x5031,

	/*
		A bit field that describes which Elements have been modified in this way.
		Values (big-endian) can be OR'ed.

		Described in Section 8.1.4.1.34.3 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ContentEncodingScope               = 0x5032,

	/*
		A value describing what kind of transformation is applied.

		Described in Section 8.1.4.1.34.4 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ContentEncodingType                = 0x5033,

	/*
		Settings describing the compression used. This Element MUST be present if the value of
		ContentEncodingType is 0 and absent otherwise. Each block MUST be decompressable even if no
		previous block is available in order not to prevent seeking.

		Described in Section 8.1.4.1.34.5 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ContentCompression                 = 0x5034,

	/*
		The compression algorithm used.

		Described in Section 8.1.4.1.34.6 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ContentCompAlgo                    = 0x4254,

	/*
		Settings that might be needed by the decompressor. For Header Stripping (ContentCompAlgo=3),
		the bytes that were removed from the beginning of each frames of the track.

		Described in Section 8.1.4.1.34.7 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ContentCompSettings                = 0x4255,

	/*
		Settings describing the encryption used. This Element MUST be present if the value of
		ContentEncodingType is 1 (encryption) and MUST be ignored otherwise.

		Described in Section 8.1.4.1.34.8 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ContentEncryption                  = 0x5035,

	/*
		The encryption algorithm used. The value "0" means that the contents have not been encrypted.

		Described in Section 8.1.4.1.34.9 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ContentEncAlgo                     = 0x47E1,

	/*
		For public key algorithms this is the ID of the public key the the data was encrypted with.

		Described in Section 8.1.4.1.34.10 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ContentEncKeyID                    = 0x47E2,

	/*
		Settings describing the encryption algorithm used. If ContentEncAlgo != 5 this MUST be ignored.

		Described in Section 8.1.4.1.34.11 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ContentEncAESSettings              = 0x47E7,

	/*
		The AES cipher mode used in the encryption.

		Described in Section 8.1.4.1.34.12 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_AESSettingsCipherMode              = 0x47E8,

	/*
		A Top-Level Element to speed seeking access. All entries are local to the Segment.

		Described in Section 8.1.5 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_Cues                               = 0x1C53BB6B,

	/*
		Contains all information relative to a seek point in the Segment.

		Described in Section 8.1.5.1 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_CuePoint                           = 0xBB,

	/*
		Absolute timestamp according to the Segment time base.

		Described in Section 8.1.5.1.1 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_CueTime                            = 0xB3,

	/*
		Contains all information relative to a seek point in the Segment.

		Described in Section 8.1.5.1.2 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_CueTrackPositions                  = 0xB7,

	/*
		The track for which a position is given.

		Described in Section 8.1.5.1.2.1 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_CueTrack                           = 0xF7,

	/*
		The Segment Position of the Cluster containing the associated Block.

		Described in Section 8.1.5.1.2.2 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_CueClusterPosition                 = 0xF1,

	/*
		The relative position inside the Cluster of the referenced SimpleBlock or BlockGroup with 0
		being the first possible position for an Element inside that Cluster.

		Described in Section 8.1.5.1.2.3 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_CueRelativePosition                = 0xF0,

	/*
		The duration of the block according to the Segment time base. If missing the track's
		DefaultDuration does not apply and no duration information is available in terms of the cues.

		Described in Section 8.1.5.1.2.4 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_CueDuration                        = 0xB2,

	/*
		Number of the Block in the specified Cluster.

		Described in Section 8.1.5.1.2.5 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_CueBlockNumber                     = 0x5378,

	/*
		The Segment Position of the Codec State corresponding to this Cue Element.
		0 means that the data is taken from the initial Track Entry.

		Described in Section 8.1.5.1.2.6 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_CueCodecState                      = 0xEA,

	/*
		The Clusters containing the referenced Blocks.

		Described in Section 8.1.5.1.2.7 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_CueReference                       = 0xDB,

	/*
		Timestamp of the referenced Block.

		Described in Section 8.1.5.1.2.8 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_CueRefTime                         = 0x96,


	/*
		Contain attached files.

		Described in Section 8.1.6 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_Segment_Attachment                 = 0x1941A469,

	/*
		An attached file.

		Described in Section 8.1.6.1 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_AttachedFile                       = 0x61A7,

	/*
		A human-friendly name for the attached file.

		Described in Section 8.1.6.1.1 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_FileDescription                    = 0x467E,

	/*
		Filename of the attached file.

		Described in Section 8.1.6.1.2 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_FileName                           = 0x466E,

	/*
		MIME type of the file.

		Described in Section 8.1.6.1.3 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_FileMimeType                       = 0x4660,

	/*
		The data of the file.

		Described in Section 8.1.6.1.4 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_FileData                           = 0x465C,

	/*
		Unique ID representing the file, as random as possible.

		Described in Section 8.1.6.1.5 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_FileUID                            = 0x46AE,

	/*
		A system to define basic menus and partition data. For more detailed information,
		look at the Chapters explanation in Section 22.

		Described in Section 8.1.7 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_Chapters                           = 0x1043A770,

	/*
		Contains all information about a Segment edition.

		Described in Section 8.1.7.1 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_EditionEntry                       = 0x45B9,

	/*
		A unique ID to identify the edition. It's useful for tagging an edition.

		Described in Section 8.1.7.1.1 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_EditionUID                         = 0x45BC,

	/*
		Set to 1 if an edition is hidden. Hidden editions **SHOULD NOT** be available to the user interface.

		Described in https://www.matroska.org/technical/elements.html
	*/
	Matroska_EditionFlagHidden                  = 0x45BD,

	/*
		Set to 1 if the edition SHOULD be used as the default one.

		Described in Section 8.1.7.1.2 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_EditionFlagDefault                 = 0x45DB,

	/*
		Set to 1 if the chapters can be defined multiple times and the order to play them is enforced; see Section 22.1.3.

		Described in Section 8.1.7.1.3 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_EditionFlagOrdered                 = 0x45DD,

	/*
		Contains the atom information to use as the chapter atom (apply to all tracks).

		Described in Section 8.1.7.1.4 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ChapterAtom                        = 0xB6,

	/*
		A unique ID to identify the Chapter.

		Described in Section 8.1.7.1.4.1 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ChapterUID                         = 0x73C4,

	/*
		A unique string ID to identify the Chapter. Use for WebVTT cue identifier storage [WebVTT].

		Described in Section 8.1.7.1.4.2 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ChapterStringUID                   = 0x5654,

	/*
		Timestamp of the start of Chapter (not scaled).

		Described in Section 8.1.7.1.4.3 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ChapterTimeStart                   = 0x91,

	/*
		Timestamp of the end of Chapter (timestamp excluded, not scaled).
		The value MUST be strictly greater than the ChapterTimeStart of the same ChapterAtom.

		Described in Section 8.1.7.1.4.4 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ChapterTimeEnd                     = 0x92,

	/*
		Set to 1 if a chapter is hidden. Hidden chapters it SHOULD NOT be available to the user interface
		(but still to Control Tracks; see Section 22.2.3 on Chapter flags).

		Described in Section 8.1.7.1.4.5 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ChapterFlagHidden                  = 0x98,

	/*
		Set to 1 if the chapter is enabled. It can be enabled/disabled by a Control Track.
		When disabled, the movie **SHOULD** skip all the content between the TimeStart and TimeEnd of this chapter;
		see notes on Chapter flags.

		Described in https://www.matroska.org/technical/elements.html
	*/
	Matroska_ChapterFlagEnabled                 = 0x4598,

	/*
		The SegmentUID of another Segment to play during this chapter.

		Described in Section 8.1.7.1.4.6 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ChapterSegmentUID                  = 0x6E67,

	/*
		The EditionUID to play from the Segment linked in ChapterSegmentUID.
		If ChapterSegmentEditionUID is undeclared, then no Edition of the linked Segment is used;
		see Section 19.2 on medium-linking Segments.

		Described in Section 8.1.7.1.4.7 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ChapterSegmentEditionUID           = 0x6EBC,

	/*
		Specify the physical equivalent of this ChapterAtom like "DVD" (60) or "SIDE" (50);
		see Section 22.4 for a complete list of values.

		Described in Section 8.1.7.1.4.8 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ChapterPhysicalEquiv               = 0x63C3,

	/*
		Contains all possible strings to use for the chapter display.

		Described in Section 8.1.7.1.4.9 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ChapterDisplay                     = 0x80,

	/*
		Contains the string to use as the chapter atom.

		Described in Section 8.1.7.1.4.10 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ChapString                         = 0x85,

	/*
		A language corresponding to the string, in the bibliographic ISO-639-2 form [ISO639-2].
		This Element MUST be ignored if a ChapLanguageIETF Element is used within the same ChapterDisplay Element.

		Described in Section 8.1.7.1.4.11 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ChapLanguage                       = 0x437C,

	/*
		Specifies a language corresponding to the ChapString in the format defined in [BCP47]
		and using the IANA Language Subtag Registry [IANALangRegistry].
		If a ChapLanguageIETF Element is used, then any ChapLanguage and ChapCountry Elements used in the same
		ChapterDisplay MUST be ignored.

		Described in Section 8.1.7.1.4.12 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ChapLanguageIETF                   = 0x437D,

	/*
		A country corresponding to the string, using the same 2 octets country-codes as in Internet domains
		[IANADomains] based on [ISO3166-1] alpha-2 codes. This Element MUST be ignored if a ChapLanguageIETF
		Element is used within the same ChapterDisplay Element.

		Described in Section 8.1.7.1.4.13 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ChapCountry                        = 0x437E,

	/*
		Contains all the commands associated to the Atom.

		Described in Section 8.1.7.1.4.14 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ChapProcess                        = 0x6944,

	/*
		Contains the type of the codec used for the processing. A value of 0 means native Matroska processing
		(to be defined), a value of 1 means the DVD command set is used; see Section 22.3 on DVD menus.
		More codec IDs can be added later.

		Described in Section 8.1.7.1.4.15 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ChapProcessCodecID                 = 0x6955,

	/*
		Some optional data attached to the ChapProcessCodecID information. For ChapProcessCodecID = 1,
		it is the "DVD level" equivalent; see Section 22.3 on DVD menus.

		Described in Section 8.1.7.1.4.16 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ChapProcessPrivate                 = 0x450D,

	/*
		Contains all the commands associated to the Atom.

		Described in Section 8.1.7.1.4.17 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ChapProcessCommand                 = 0x6911,

	/*
		Defines when the process command SHOULD be handled.

		Described in Section 8.1.7.1.4.18 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ChapProcessTime                    = 0x6922,

	/*
		Contains the command information. The data SHOULD be interpreted depending on the ChapProcessCodecID value.
		For ChapProcessCodecID = 1, the data correspond to the binary DVD cell pre/post commands;
		see Section 22.3 on DVD menus.

		Described in Section 8.1.7.1.4.19 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_ChapProcessData                    = 0x6933,

	/*
		Element containing metadata describing Tracks, Editions, Chapters, Attachments, or the Segment as a whole.
		A list of valid tags can be found in [MatroskaTags].

		Described in Section 8.1.8 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_Tags                               = 0x1254C367,

	/*
		A single metadata descriptor.

		Described in Section 8.1.8.1 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_Tag                                = 0x7373,

	/*
		Specifies which other elements the metadata represented by the Tag applies to.
		If empty or not present, then the Tag describes everything in the Segment.

		Described in Section 8.1.8.1.1 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_Targets                            = 0x63C0,

	/*
		A number to indicate the logical level of the target.

		Described in Section 8.1.8.1.1.1 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_TargetTypeValue                    = 0x68CA,

	/*
		An informational string that can be used to display the logical level of the target like
		"ALBUM", "TRACK", "MOVIE", "CHAPTER", etc ; see Section 6.4 of [MatroskaTags].

		Described in Section 8.1.8.1.1.2 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_TargetType                         = 0x63CA,

	/*
		A unique ID to identify the Track(s) the tags belong to.

		Described in Section 8.1.8.1.1.3 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_TagTrackUID                        = 0x63C5,

	/*
		A unique ID to identify the EditionEntry(s) the tags belong to.

		Described in Section 8.1.8.1.1.4 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_TagEditionUID                      = 0x63C9,

	/*
		A unique ID to identify the Chapter(s) the tags belong to.

		Described in Section 8.1.8.1.1.5 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_TagChapterUID                      = 0x63C4,

	/*
		A unique ID to identify the Attachment(s) the tags belong to.

		Described in Section 8.1.8.1.1.6 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_TagAttachmentUID                   = 0x63C6,

	/*
		Contains general information about the target.

		Described in Section 8.1.8.1.2 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_SimpleTag                          = 0x67C8,

	/*
		The name of the Tag that is going to be stored.

		Described in Section 8.1.8.1.2.1 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_TagName                            = 0x45A3,

	/*
		Specifies the language of the tag specified, in the Matroska languages form; see Section 6 on language codes.
		This Element MUST be ignored if the TagLanguageIETF Element is used within the same SimpleTag Element.

		Described in Section 8.1.8.1.2.2 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_TagLanguage                        = 0x447A,

	/*
		Specifies the language used in the TagString according to [BCP47] and using the IANA Language Subtag Registry
		[IANALangRegistry]. If this Element is used, then any TagLanguage Elements used in the same SimpleTag MUST be ignored.

		Described in Section 8.1.8.1.2.3 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_TagLanguageIETF                    = 0x447B,

	/*
		A boolean value to indicate if this is the default/original language to use for the given tag.

		Described in Section 8.1.8.1.2.4 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_TagDefault                         = 0x4484,

	/*
		The value of the Tag.

		Described in Section 8.1.8.1.2.5 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_TagString                          = 0x4487,

	/*
		The values of the Tag, if it is binary. Note that this cannot be used in the same SimpleTag as TagString.

		Described in Section 8.1.8.1.2.6 of IETF draft-ietf-cellar-matroska-08
	*/
	Matroska_TagBinary                          = 0x4485,



}

/*
	TODO(Jeroen): Think about replacing the parsers with table-driven ones.
	where an array indexed by the id decides whether to intern (and as what type), skip, or handle in a special manner.
*/

EBML_ID_Operation :: enum {
	/*
		Intern by type
	*/
	Intern,
	/*
		Handle the ID specially
	*/
	Special,
	/*
		Just save offsets, etc, and skip to the next element.
	*/
	Skip,
}

EBML_Type_Info :: struct {
	type:	   EBML_Type,
	operation: EBML_ID_Operation,
	name:      string,
}

Matroska_Schema :: #partial #sparse[EBML_ID]EBML_Type_Info {
	.Matroska_Segment = {
		.Master, .Intern, "Segment",
	},
}