package ebml
/*
	Copyright 2021 Jeroen van Rijn <nom@duclavier.com>.
	Made available under Odin's BSD-3 license.

	A from-scratch implementation of the Extensible Binary Meta Language (EBML),
	as specified in [IETF RFC 8794](https://www.rfc-editor.org/rfc/rfc8794).

	The EBML format is the base format upon which Matroska (MKV) and WebM are based.

	This file contains the base EBML types.
*/

import "core:os"
import "core:mem"
import "core:time"
import "../common"

UUID :: common.UUID_RFC_4122
Time :: time.Time

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

	UUID,
	Time,
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
	UUID,
	Time,
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
	Segment                            = 0x18538067,

	/*
		Contains the Segment Position of other Top-Level Elements.
		Described in Section 8.1.1 of IETF draft-ietf-cellar-matroska-08
	*/
	SeekHead                           = 0x114D9B74,

	/*
		Contains a single seek entry to an EBML Element.
		Described in Section 8.1.1.1 of IETF draft-ietf-cellar-matroska-08
	*/
	Seek                               = 0x4DBB,

	/*
		The binary ID corresponding to the Element name.
		Described in Section 8.1.1.1.1 of IETF draft-ietf-cellar-matroska-08
	*/
	SeekID                             = 0x53AB,

	/*
		The Segment Position of the Element.
		Described in Section 8.1.1.1.2 of IETF draft-ietf-cellar-matroska-08
	*/
	SeekPosition                       = 0x53AC,

	/*
		Contains general information about the Segment.
		Described in Section 8.1.2 of IETF draft-ietf-cellar-matroska-08
	*/
	Info                               = 0x1549A966,

	/*
		A randomly generated unique ID to identify the Segment amongst many others (128 bits).
		Described in Section 8.1.2.1 of IETF draft-ietf-cellar-matroska-08
	*/
	SegmentUID                         = 0x73A4,

	/*
		A filename corresponding to this Segment.
		Described in Section 8.1.2.2 of IETF draft-ietf-cellar-matroska-08
	*/
	SegmentFilename                    = 0x7384,

	/*
		A unique ID to identify the previous Segment of a Linked Segment (128 bits).
		Described in Section 8.1.2.3 of IETF draft-ietf-cellar-matroska-08
	*/
	PrevUID                            = 0x3CB923,

	/*
		A filename corresponding to the file of the previous Linked Segment.
		Described in Section 8.1.2.4 of IETF draft-ietf-cellar-matroska-08
	*/
	PrevFilename                       = 0x3C83AB,

	/*
		A unique ID to identify the previous Segment of a Linked Segment (128 bits).
		Described in Section 8.1.2.5 of IETF draft-ietf-cellar-matroska-08
	*/
	NextUID                            = 0x3EB923,

	/*
		A filename corresponding to the file of the previous Linked Segment.
		Described in Section 8.1.2.6 of IETF draft-ietf-cellar-matroska-08
	*/
	NextFilename                       = 0x3E83BB,

	/*
		A randomly generated unique ID that all Segments of a Linked Segment MUST share (128 bits).
		Described in Section 8.1.2.7 of IETF draft-ietf-cellar-matroska-08
	*/
	SegmentFamily                      = 0x4444,

	/*
		A tuple of corresponding ID used by chapter codecs to represent this Segment.
		Described in Section 8.1.2.8 of IETF draft-ietf-cellar-matroska-08
	*/
	ChapterTranslate                   = 0x6924,

	/*
		Specify an edition UID on which this correspondence applies. When not specified,
			it means for all editions found in the Segment.
		Described in Section 8.1.2.8.1 of IETF draft-ietf-cellar-matroska-08
	*/
	ChapterTranslateEditionUID         = 0x69FC,

	/*
		The chapter codec; see Section 8.1.7.1.4.15.
		Described in Section 8.1.2.8.2 of IETF draft-ietf-cellar-matroska-08
	*/
	ChapterTranslateCodec              = 0x69BF,

	/*
		The binary value used to represent this Segment in the chapter codec data.
		The format depends on the ChapProcessCodecID used; see Section 8.1.7.1.4.15.

		Described in Section 8.1.2.8.3 of IETF draft-ietf-cellar-matroska-08
	*/
	ChapterTranslateID                 = 0x69A5,

	/*
		Timestamp scale in nanoseconds (1_000_000 means all timestamps in the Segment are expressed in milliseconds).

		Described in Section 8.1.2.9 of IETF draft-ietf-cellar-matroska-08
	*/
	TimestampScale                     = 0x2AD7B1,

	/*
		Duration of the Segment in nanoseconds based on TimestampScale.

		Described in Section 8.1.2.10 of IETF draft-ietf-cellar-matroska-08
	*/
	Duration                           = 0x4489,

	/*
		The date and time that the Segment was created by the muxing application or library.

		Described in Section 8.1.2.11 of IETF draft-ietf-cellar-matroska-08
	*/
	DateUTC                            = 0x4461,

	/*
		General name of the Segment.

		Described in Section 8.1.2.12 of IETF draft-ietf-cellar-matroska-08
	*/
	Title                              = 0x7BA9,

	/*
		Muxing application or library (example: "libmatroska-0.4.3").

		Described in Section 8.1.2.13 of IETF draft-ietf-cellar-matroska-08
	*/
	MuxingApp                          = 0x4D80,

	/*
		Writing application (example: "mkvmerge-0.3.3").

		Described in Section 8.1.2.14 of IETF draft-ietf-cellar-matroska-08
	*/
	WritingApp                         = 0x5741,

	/*
		The Top-Level Element containing the (monolithic) Block structure.

		Described in Section 8.1.3 of IETF draft-ietf-cellar-matroska-08
	*/
	Cluster                            = 0x1F43B675,

	/*
		Absolute timestamp of the cluster (based on TimestampScale).

		Described in Section 8.1.3.1 of IETF draft-ietf-cellar-matroska-08
	*/
	Timestamp                          = 0xE7,

	/*
		The Segment Position of the Cluster in the Segment (0 in live streams).
		It might help to resynchronise offset on damaged streams.

		Described in Section 8.1.3.2 of IETF draft-ietf-cellar-matroska-08
	*/
	Position                           = 0xA7,

	/*
		Size of the previous Cluster, in octets. Can be useful for backward playing.

		Described in Section 8.1.3.3 of IETF draft-ietf-cellar-matroska-08
	*/
	PrevSize                           = 0xAB,

	/*
		Similar to Block, see Section 12, but without all the extra information,
			mostly used to reduce overhead when no extra feature is needed;
			see Section 12.4 on SimpleBlock Structure.

		Described in Section 8.1.3.4 of IETF draft-ietf-cellar-matroska-08
	*/
	SimpleBlock                        = 0xA3,

	/*
		Basic container of information containing a single Block and information specific to that Block.

		Described in Section 8.1.3.5 of IETF draft-ietf-cellar-matroska-08
	*/
	BlockGroup                         = 0xA0,

	/*
		Block containing the actual data to be rendered and a timestamp relative to the
			Cluster Timestamp; see Section 12 on Block Structure.

		Described in Section 8.1.3.5.1 of IETF draft-ietf-cellar-matroska-08
	*/
	Block                              = 0xA1,

	/*
		Contain additional blocks to complete the main one. An EBML parser that has no knowledge
			of the Block structure could still see and use/skip these data.

		Described in Section 8.1.3.5.2 of IETF draft-ietf-cellar-matroska-08
	*/
	BlockAdditions                     = 0x75A1,

	/*
		Contain the BlockAdditional and some parameters.

		Described in Section 8.1.3.5.2.1 of IETF draft-ietf-cellar-matroska-08
	*/
	BlockMore                          = 0xA6,

	/*
		An ID to identify the BlockAdditional level. If BlockAddIDType of the corresponding block is 0,
			this value is also the value of BlockAddIDType for the meaning of the content of BlockAdditional.

		Described in Section 8.1.3.5.2.2 of IETF draft-ietf-cellar-matroska-08
	*/
	BlockAddID                         = 0xEE,

	/*
		Interpreted by the codec as it wishes (using the BlockAddID).

		Described in Section 8.1.3.5.2.3 of IETF draft-ietf-cellar-matroska-08
	*/
	BlockAdditional                    = 0xA5,

	/*
		The duration of the Block (based on TimestampScale). The BlockDuration Element can be useful at the end
			of a Track to define the duration of the last frame (as there is no subsequent Block available),
			or when there is a break in a track like for subtitle tracks.

		Described in Section 8.1.3.5.3 of IETF draft-ietf-cellar-matroska-08
	*/
	BlockDuration                      = 0x9B,

	/*
		This frame is referenced and has the specified cache priority. In cache only a frame of the
			same or higher priority can replace this frame. A value of 0 means the frame is not referenced.

		Described in Section 8.1.3.5.4 of IETF draft-ietf-cellar-matroska-08
	*/
	ReferencePriority                  = 0xFA,

	/*
		Timestamp of another frame used as a reference (ie: B or P frame). The timestamp is relative
			to the block it's attached to.

		Described in Section 8.1.3.5.5 of IETF draft-ietf-cellar-matroska-08
	*/
	ReferenceBlock                     = 0xFB,

	/*
		The new codec state to use. Data interpretation is private to the codec.
			This information SHOULD always be referenced by a seek entry.

		Described in Section 8.1.3.5.6 of IETF draft-ietf-cellar-matroska-08
	*/
	CodecState                         = 0xA4,

	/*
		Duration in nanoseconds of the silent data added to the Block (padding at the end of the Block
			for positive value, at the beginning of the Block for negative value). The duration of
			DiscardPadding is not calculated in the duration of the TrackEntry and SHOULD be discarded
			during playback.

		Described in Section 8.1.3.5.7 of IETF draft-ietf-cellar-matroska-08
	*/
	DiscardPadding                     = 0x75A2,

	/*
		Contains slices description.

		Described in Section 8.1.3.5.8 of IETF draft-ietf-cellar-matroska-08
	*/
	Slices                             = 0x8E,

	/*
		Contains extra time information about the data contained in the Block.
			Being able to interpret this Element is not REQUIRED for playback.

		Described in Section 8.1.3.5.8.1 of IETF draft-ietf-cellar-matroska-08
	*/
	TimeSlice                          = 0xE8,

	/*
		The reverse number of the frame in the lace (0 is the last frame, 1 is the next to last, etc).
			Being able to interpret this Element is not REQUIRED for playback.

		Described in Section 8.1.3.5.8.2 of IETF draft-ietf-cellar-matroska-08
	*/
	LaceNumber                         = 0xCC,

	/*
		A Top-Level Element of information with many tracks described.

		Described in Section 8.1.4 of IETF draft-ietf-cellar-matroska-08
	*/
	Tracks                             = 0x1654AE6B,

	/*
		Describes a track with all Elements.

		Described in Section 8.1.4.1 of IETF draft-ietf-cellar-matroska-08
	*/
	TrackEntry                         = 0xAE,

	/*
		The track number as used in the Block Header (using more than 127 tracks is not encouraged,
			though the design allows an unlimited number).

		Described in Section 8.1.4.1.1 of IETF draft-ietf-cellar-matroska-08
	*/
	TrackNumber                        = 0xD7,

	/*
		The value of this Element SHOULD be kept the same when making a direct stream copy to another file.

		Described in Section 8.1.4.1.2 of IETF draft-ietf-cellar-matroska-08
	*/
	TrackUID                           = 0x73C5,

	/*
		A set of track types coded on 8 bits.

		Described in Section 8.1.4.1.3 of IETF draft-ietf-cellar-matroska-08
	*/
	TrackType                          = 0x83,

	/*
		Set to 1 if the track is usable. It is possible to turn a not usable track into a
			usable track using chapter codecs or control tracks.

		Described in Section 8.1.4.1.4 of IETF draft-ietf-cellar-matroska-08
	*/
	FlagEnabled                        = 0xB8,

	/*
		Set if that track (audio, video or subs) SHOULD be eligible for automatic selection by the player;
			see Section 21 for more details.

		Described in Section 8.1.4.1.5 of IETF draft-ietf-cellar-matroska-08
	*/
	FlagDefault                        = 0x88,

	/*
		Applies only to subtitles. Set if that track SHOULD be eligible for automatic selection by the player
			if it matches the user's language preference, even if the user's preferences would normally not
			enable subtitles with the selected audio track; this can be used for tracks containing only
			translations of foreign-language audio or onscreen text. See Section 21 for more details.

		Described in Section 8.1.4.1.6 of IETF draft-ietf-cellar-matroska-08
	*/
	FlagForced                         = 0x55AA,

	/*
		Set to 1 if that track is suitable for users with hearing impairments,
		set to 0 if it is unsuitable for users with hearing impairments.

		Described in Section 8.1.4.1.7 of IETF draft-ietf-cellar-matroska-08
	*/
	FlagHearingImpaired                = 0x55AB,

	/*
		Set to 1 if that track is suitable for users with visual impairments,
		set to 0 if it is unsuitable for users with visual impairments.

		Described in Section 8.1.4.1.8 of IETF draft-ietf-cellar-matroska-08
	*/
	FlagVisualImpaired                 = 0x55AC,

	/*
		Set to 1 if that track contains textual descriptions of video content,
		set to 0 if that track does not contain textual descriptions of video content.

		Described in Section 8.1.4.1.9 of IETF draft-ietf-cellar-matroska-08
	*/
	FlagTextDescriptions               = 0x55AD,

	/*
		Set to 1 if that track is in the content's original language,
		set to 0 if it is a translation.

		Described in Section 8.1.4.1.10 of IETF draft-ietf-cellar-matroska-08
	*/
	FlagOriginal                       = 0x55AE,

	/*
		Set to 1 if that track contains commentary,
		set to 0 if it does not contain commentary.

		Described in Section 8.1.4.1.11 of IETF draft-ietf-cellar-matroska-08
	*/
	FlagCommentary                     = 0x55AF,

	/*
		Set to 1 if the track MAY contain blocks using lacing.

		Described in Section 8.1.4.1.12 of IETF draft-ietf-cellar-matroska-08
	*/
	FlagLacing                         = 0x9C,

	/*
		The minimum number of frames a player SHOULD be able to cache during playback.
		If set to 0, the reference pseudo-cache system is not used.

		Described in Section 8.1.4.1.13 of IETF draft-ietf-cellar-matroska-08
	*/
	MinCache                           = 0x6DE7,

	/*
		The maximum cache size necessary to store referenced frames in and the current frame.
		0 means no cache is needed.

		Described in Section 8.1.4.1.14 of IETF draft-ietf-cellar-matroska-08
	*/
	MaxCache                           = 0x6DF8,

	/*
		Number of nanoseconds (not scaled via TimestampScale) per frame
		(frame in the Matroska sense -- one Element put into a (Simple)Block).

		Described in Section 8.1.4.1.15 of IETF draft-ietf-cellar-matroska-08
	*/
	DefaultDuration                    = 0x23E383,

	/*
		The period in nanoseconds (not scaled by TimestampScale) between two successive fields at
		the output of the decoding process, see Section 11 for more information

		Described in Section 8.1.4.1.16 of IETF draft-ietf-cellar-matroska-08
	*/
	DefaultDecodedFieldDuration        = 0x234E7A,

	/*
		DEPRECATED, DO NOT USE. The scale to apply on this track to work at normal speed in relation with other tracks
		(mostly used to adjust video speed when the audio length differs).

		Described in Section 8.1.4.1.17 of IETF draft-ietf-cellar-matroska-08
	*/
	TrackTimestampScale                = 0x23314F,

	/*
		The maximum value of BlockAddID (Section 8.1.3.5.2.2).
		A value 0 means there is no BlockAdditions (Section 8.1.3.5.2) for this track.

		Described in Section 8.1.4.1.18 of IETF draft-ietf-cellar-matroska-08
	*/
	MaxBlockAdditionID                 = 0x55EE,

	/*
		Contains elements that extend the track format, by adding content either to each frame,
		with BlockAddID (Section 8.1.3.5.2.2), or to the track as a whole with BlockAddIDExtraData.

		Described in Section 8.1.4.1.19 of IETF draft-ietf-cellar-matroska-08
	*/
	BlockAdditionMapping               = 0x41E4,

	/*
		If the track format extension needs content beside frames, the value refers to the BlockAddID
		(Section 8.1.3.5.2.2), value being described. To keep MaxBlockAdditionID as low as possible,
		small values SHOULD be used.

		Described in Section 8.1.4.1.19.1 of IETF draft-ietf-cellar-matroska-08
	*/
	BlockAddIDValue                    = 0x41F0,

	/*
		A human-friendly name describing the type of BlockAdditional data,
		as defined by the associated Block Additional Mapping.

		Described in Section 8.1.4.1.19.2 of IETF draft-ietf-cellar-matroska-08
	*/
	BlockAddIDName                     = 0x41A4,

	/*
		Stores the registered identifier of the Block Additional Mapping to define how the
		BlockAdditional data should be handled.

		Described in Section 8.1.4.1.19.3 of IETF draft-ietf-cellar-matroska-08
	*/
	BlockAddIDType                     = 0x41E7,

	/*
		Extra binary data that the BlockAddIDType can use to interpret the BlockAdditional data.
		The interpretation of the binary data depends on the BlockAddIDType value and the corresponding
		Block Additional Mapping.

		Described in Section 8.1.4.1.19.4 of IETF draft-ietf-cellar-matroska-08
	*/
	BlockAddIDExtraData                = 0x41ED,

	/*
		A human-readable track name.

		Described in Section 8.1.4.1.20 of IETF draft-ietf-cellar-matroska-08
	*/
	TrackEntry_Name                    = 0x536E,

	/*
		Specifies the language of the track in the Matroska languages form; see Section 6 on language codes.
		This Element MUST be ignored if the LanguageIETF Element is used in the same TrackEntry.

		Described in Section 8.1.4.1.21 of IETF draft-ietf-cellar-matroska-08
	*/
	TrackEntry_Language                = 0x22B59C,

	/*
		Specifies the language of the track according to [BCP47] and using the IANA Language Subtag Registry
		[IANALangRegistry]. If this Element is used, then any Language Elements used in the same TrackEntry
		MUST be ignored.

		Described in Section 8.1.4.1.22 of IETF draft-ietf-cellar-matroska-08
	*/
	TrackEntry_Language_IETF           = 0x22B59D,

	/*
		An ID corresponding to the codec, see [MatroskaCodec] for more info.

		Described in Section 8.1.4.1.23 of IETF draft-ietf-cellar-matroska-08
	*/
	TrackEntry_CodecID                 = 0x86,

	/*
		Private data only known to the codec.

		Described in Section 8.1.4.1.24 of IETF draft-ietf-cellar-matroska-08
	*/
	TrackEntry_CodecPrivate            = 0x63A2,

	/*
		A human-readable string specifying the codec.

		Described in Section 8.1.4.1.25 of IETF draft-ietf-cellar-matroska-08
	*/
	TrackEntry_CodecName               = 0x258688,

	/*
		The UID of an attachment that is used by this codec.

		Described in Section 8.1.4.1.26 of IETF draft-ietf-cellar-matroska-08
	*/
	TrackEntry_AttachmentLink          = 0x7446,

	/*
		Specify that this track is an overlay track for the Track specified (in the u-integer).
		That means when this track has a gap, see Section 26.3.1 on SilentTracks, the overlay track
		SHOULD be used instead.

		Described in Section 8.1.4.1.27 of IETF draft-ietf-cellar-matroska-08
	*/
	TrackEntry_TrackOverlay            = 0x6FAB,

	/*
		CodecDelay is The codec-built-in delay in nanoseconds. This value MUST be subtracted from each block
		timestamp in order to get the actual timestamp. The value SHOULD be small so the muxing of tracks with
		the same actual timestamp are in the same Cluster.

		Described in Section 8.1.4.1.28 of IETF draft-ietf-cellar-matroska-08
	*/
	TrackEntry_CodecDelay              = 0x56AA,

	/*
		After a discontinuity, SeekPreRoll is the duration in nanoseconds of the data the decoder
		MUST decode before the decoded data is valid.

		Described in Section 8.1.4.1.29 of IETF draft-ietf-cellar-matroska-08
	*/
	SeekPreRoll                        = 0x56BB,

	/*
		The track identification for the given Chapter Codec.

		Described in Section 8.1.4.1.30 of IETF draft-ietf-cellar-matroska-08
	*/
	TrackTranslate                     = 0x6624,

	/*
		Specify an edition UID on which this translation applies.
		When not specified, it means for all editions found in the Segment.

		Described in Section 8.1.4.1.30.1 of IETF draft-ietf-cellar-matroska-08
	*/
	TrackTranslateEditionUID           = 0x66FC,

	/*
		The chapter codec; see Section 8.1.7.1.4.15.

		Described in Section 8.1.4.1.30.2 of IETF draft-ietf-cellar-matroska-08
	*/
	TrackTranslateCodec                = 0x66BF,

	/*
		The binary value used to represent this track in the chapter codec data.
		The format depends on the ChapProcessCodecID used; see Section 8.1.7.1.4.15.

		Described in Section 8.1.4.1.30.3 of IETF draft-ietf-cellar-matroska-08
	*/
	TrackTranslateTrackID              = 0x66A5,

	/*
		Video settings.

		Described in Section 8.1.4.1.31 of IETF draft-ietf-cellar-matroska-08
	*/
	TrackEntry_Video                   = 0xE0,

	/*
		Specify whether the video frames in this track are interlaced or not.

		Described in Section 8.1.4.1.31.1 of IETF draft-ietf-cellar-matroska-08
	*/
	Video_FlagInterlaced               = 0x9A,

	/*
		Specify the field ordering of video frames in this track.

		Described in Section 8.1.4.1.31.2 of IETF draft-ietf-cellar-matroska-08
	*/
	Video_FieldOrder                   = 0x9D,

	/*
		Stereo-3D video mode. There are some more details in Section 20.10.

		Described in Section 8.1.4.1.31.3 of IETF draft-ietf-cellar-matroska-08
	*/
	Video_StereoMode                   = 0x53B8,

	/*
		Alpha Video Mode. Presence of this Element indicates that the BlockAdditional Element could contain Alpha data.

		Described in Section 8.1.4.1.31.4 of IETF draft-ietf-cellar-matroska-08
	*/
	Video_AlphaMode                    = 0x53C0,

	/*
		Width, Height of the encoded video frames in pixels.

		Described in Section 8.1.4.1.31.5 .. 6 of IETF draft-ietf-cellar-matroska-08
	*/
	Video_PixelWidth                   = 0xB0,
	Video_PixelHeight                  = 0xBA,

	/*
		The number of video pixels to remove at the bottom, top, left, right of the image.

		Described in Section 8.1.4.1.31.7 .. 10 of IETF draft-ietf-cellar-matroska-08
	*/
	Video_PixelCropBottom              = 0x54AA,
	Video_PixelCropTop                 = 0x54BB,
	Video_PixelCropLeft                = 0x54CC,
	Video_PixelCropRight               = 0x54DD,

	/*
		Display Width + Height, and how DisplayWidth & DisplayHeight are interpreted.

		Described in Section 8.1.4.1.31.11 .. 13 of IETF draft-ietf-cellar-matroska-08
	*/
	Video_DisplayWidth                 = 0x54B0,
	Video_DisplayHeight                = 0x54BA,
	Video_DisplayUnit                  = 0x54B2,

	/*
		Specify the pixel format used for the Track's data as a FourCC.
		This value is similar in scope to the biCompression value of AVI's BITMAPINFOHEADER.

		Described in Section 8.1.4.1.31.14 of IETF draft-ietf-cellar-matroska-08
	*/
	Video_ColourSpace                  = 0x2EB524,

	/*
		Settings describing the colour format.

		Described in Section 8.1.4.1.31.15 of IETF draft-ietf-cellar-matroska-08
	*/
	Video_Colour                       = 0x55B0,

	/*
		The Matrix Coefficients of the video used to derive luma and chroma values from
		red, green, and blue color primaries. For clarity, the value and meanings for
		MatrixCoefficients are adopted from Table 4 of ISO/IEC 23001-8:2016 or ITU-T H.273.

		Described in Section 8.1.4.1.31.16 of IETF draft-ietf-cellar-matroska-08
	*/
	Colour_MatrixCoefficients          = 0x55B1,

	/*
		Number of decoded bits per channel. A value of 0 indicates that the BitsPerChannel is unspecified.

		Described in Section 8.1.4.1.31.17 of IETF draft-ietf-cellar-matroska-08
	*/
	Colour_BitsPerChannel              = 0x55B2,

	/*
		The amount of pixels to remove in the Cr and Cb channels for every pixel not removed horizontally.
		Example: For video with 4:2:0 chroma subsampling, the ChromaSubsamplingHorz SHOULD be set to 1.

		The amount of pixels to remove in the Cr and Cb channels for every pixel not removed vertically.
		Example: For video with 4:2:0 chroma subsampling, the ChromaSubsamplingVert SHOULD be set to 1.

		Described in Section 8.1.4.1.31.18 .. 23 of IETF draft-ietf-cellar-matroska-08
	*/
	Colour_ChromaSubsamplingHorz       = 0x55B3,
	Colour_ChromaSubsamplingVert       = 0x55B4,
	CbSubsamplingHorz                  = 0x55B5,
	CbSubsamplingVert                  = 0x55B6,
	ChromaSitingHorz                   = 0x55B7,
	ChromaSitingVert                   = 0x55B8,

	/*
		Clipping of the color ranges.

		Described in Section 8.1.4.1.31.24 of IETF draft-ietf-cellar-matroska-08
	*/
	Colour_Range                       = 0x55B9,

	/*
		The transfer characteristics of the video. For clarity, the value and meanings for
		TransferCharacteristics are adopted from Table 3 of ISO/IEC 23091-4 or ITU-T H.273.

		The colour primaries of the video. For clarity, the value and meanings for Primaries
		are adopted from Table 2 of ISO/IEC 23091-4 or ITU-T H.273.

		Described in Section 8.1.4.1.31.25 .. 26 of IETF draft-ietf-cellar-matroska-08
	*/
	Colour_TransferCharacteristics     = 0x55BA,
	Colour_Primaries                   = 0x55BB,


	/*
		Maximum brightness of a single pixel (Maximum Content Light Level) in candelas per square meter (cd/m2).
		Maximum brightness of a single full frame (Maximum Frame-Average Light Level) in candelas per square meter (cd/m2).

		Described in Section 8.1.4.1.31.27 .. 28 of IETF draft-ietf-cellar-matroska-08
	*/
	Colour_MaxCLL                      = 0x55BC,
	Colour_MaxFALL                     = 0x55BD,

	/*
		SMPTE 2086 mastering data.

		Described in Section 8.1.4.1.31.29 of IETF draft-ietf-cellar-matroska-08
	*/
	Colour_MasteringMetadata           = 0x55D0,

	/*
		RGB-W chromaticity coordinates, as defined by CIE 1931.

		Described in Section 8.1.4.1.31.30 .. 37 of IETF draft-ietf-cellar-matroska-08
	*/
	PrimaryRChromaticityX              = 0x55D1,
	PrimaryRChromaticityY              = 0x55D2,
	PrimaryGChromaticityX              = 0x55D3,
	PrimaryGChromaticityY              = 0x55D4,
	PrimaryBChromaticityX              = 0x55D5,
	PrimaryBChromaticityY              = 0x55D6,
	WhitePointChromaticityX            = 0x55D7,
	WhitePointChromaticityY            = 0x55D8,

	/*
		Maximum/Minimum luminance. Represented in candelas per square meter (cd/m2).

		Described in Section 8.1.4.1.31.38 .. 39 of IETF draft-ietf-cellar-matroska-08
	*/
	LuminanceMax                       = 0x55D9,
	LuminanceMin                       = 0x55DA,

	/*
		* Describes the video projection details. Used to render spherical and VR videos.
		* Describes the projection used for this video track.
		* Private data that only applies to a specific projection.

		Described in Section 8.1.4.1.31.40 .. 42 of IETF draft-ietf-cellar-matroska-08
	*/
	Video_Projection                   = 0x7670,
	Video_ProjectionType               = 0x7671,
	Video_ProjectionPrivate            = 0x7672,

	/*
		Projection vector rotation.

		Described in Section 8.1.4.1.31.43 .. 45 of IETF draft-ietf-cellar-matroska-08
	*/
	Video_ProjectionPoseYaw            = 0x7673,
	Video_ProjectionPosePitch          = 0x7674,
	Video_ProjectionPoseRoll           = 0x7675,

	/*
		Audio settings.

		Described in Section 8.1.4.1.32 of IETF draft-ietf-cellar-matroska-08
	*/
	Audio                              = 0xE1,
	Audio_SamplingFrequency            = 0xB5,
	Audio_OutputSamplingFrequency      = 0x78B5,
	Audio_Channels                     = 0x9F,
	Audio_BitDepth                     = 0x6264,

	/*
		Operation that needs to be applied on tracks to create this virtual track.
		For more details look at Section 20.8.

		Contains the list of all video plane tracks that need to be combined to create this 3D track.

		Contains a video plane track that need to be combined to create this 3D track.

		Described in Section 8.1.4.1.33 .. 33.2 of IETF draft-ietf-cellar-matroska-08	
	*/
	Track_Operation                    = 0xE2,
	TrackCombinePlanes                 = 0xE3,
	TrackPlane                         = 0xE4,

	/*
		The trackUID number of the track representing the plane.
		The kind of plane this track corresponds to.

		Described in Section 8.1.4.1.33.3 .. 4 of IETF draft-ietf-cellar-matroska-08	
	*/
	TrackPlaneUID                      = 0xE5,
	TrackPlaneType                     = 0xE6,

	/*
		Contains the list of all tracks whose Blocks need to be combined to create this virtual track.

		Described in Section 8.1.4.1.33.5 of IETF draft-ietf-cellar-matroska-08	
	*/
	TrackJoinBlocks                    = 0xE9,

	/*
		The trackUID number of a track whose blocks are used to create this virtual track.

		Described in Section 8.1.4.1.33.6 of IETF draft-ietf-cellar-matroska-08	
	*/
	TrackJoinUID                       = 0xED,

	/*
		Settings for several content encoding mechanisms like compression or encryption.

		Described in Section 8.1.4.1.34 of IETF draft-ietf-cellar-matroska-08	
	*/
	ContentEncodings                   = 0x6D80,

	/*
		Settings for one content encoding like compression or encryption.

		Described in Section 8.1.4.1.34.1 of IETF draft-ietf-cellar-matroska-08	
	*/
	ContentEncoding                    = 0x6240,

	/*
		Tells when this modification was used during encoding/muxing starting with 0 and counting upwards.
		The decoder/demuxer has to start with the highest order number it finds and work its way down.
		This value has to be unique over all ContentEncodingOrder Elements in the TrackEntry that
		contains this ContentEncodingOrder element.

		Described in Section 8.1.4.1.34.2 of IETF draft-ietf-cellar-matroska-08
	*/
	ContentEncodingOrder               = 0x5031,

	/*
		A bit field that describes which Elements have been modified in this way.
		Values (big-endian) can be OR'ed.

		Described in Section 8.1.4.1.34.3 of IETF draft-ietf-cellar-matroska-08
	*/
	ContentEncodingScope               = 0x5032,

	/*
		A value describing what kind of transformation is applied.

		Described in Section 8.1.4.1.34.4 of IETF draft-ietf-cellar-matroska-08
	*/
	ContentEncodingType                = 0x5033,

	/*
		Settings describing the compression used. This Element MUST be present if the value of
		ContentEncodingType is 0 and absent otherwise. Each block MUST be decompressable even if no
		previous block is available in order not to prevent seeking.

		Described in Section 8.1.4.1.34.5 of IETF draft-ietf-cellar-matroska-08
	*/
	ContentCompression                 = 0x5034,

	/*
		The compression algorithm used.

		Described in Section 8.1.4.1.34.6 of IETF draft-ietf-cellar-matroska-08
	*/
	ContentCompAlgo                    = 0x4254,

	/*
		Settings that might be needed by the decompressor. For Header Stripping (ContentCompAlgo=3),
		the bytes that were removed from the beginning of each frames of the track.

		Described in Section 8.1.4.1.34.7 of IETF draft-ietf-cellar-matroska-08
	*/
	ContentCompSettings                = 0x4255,

	/*
		Settings describing the encryption used. This Element MUST be present if the value of
		ContentEncodingType is 1 (encryption) and MUST be ignored otherwise.

		Described in Section 8.1.4.1.34.8 of IETF draft-ietf-cellar-matroska-08
	*/
	ContentEncryption                  = 0x5035,

	/*
		The encryption algorithm used. The value "0" means that the contents have not been encrypted.

		Described in Section 8.1.4.1.34.9 of IETF draft-ietf-cellar-matroska-08
	*/
	ContentEncAlgo                     = 0x47E1,

	/*
		For public key algorithms this is the ID of the public key the the data was encrypted with.

		Described in Section 8.1.4.1.34.10 of IETF draft-ietf-cellar-matroska-08
	*/
	ContentEncKeyID                    = 0x47E2,

	/*
		Settings describing the encryption algorithm used. If ContentEncAlgo != 5 this MUST be ignored.

		Described in Section 8.1.4.1.34.11 of IETF draft-ietf-cellar-matroska-08
	*/
	ContentEncAESSettings              = 0x47E7,

	/*
		The AES cipher mode used in the encryption.

		Described in Section 8.1.4.1.34.12 of IETF draft-ietf-cellar-matroska-08
	*/
	AESSettingsCipherMode              = 0x47E8,

	/*
		A Top-Level Element to speed seeking access. All entries are local to the Segment.

		Described in Section 8.1.5 of IETF draft-ietf-cellar-matroska-08
	*/
	Segment_Cues                       = 0x1C53BB6B,

	/*
		Contains all information relative to a seek point in the Segment.

		Described in Section 8.1.5.1 of IETF draft-ietf-cellar-matroska-08
	*/
	CuePoint                           = 0xBB,

	/*
		Absolute timestamp according to the Segment time base.

		Described in Section 8.1.5.1.1 of IETF draft-ietf-cellar-matroska-08
	*/
	CueTime                            = 0xB3,

	/*
		Contains all information relative to a seek point in the Segment.

		Described in Section 8.1.5.1.2 of IETF draft-ietf-cellar-matroska-08
	*/
	CueTrackPositions                  = 0xB7,

	/*
		The track for which a position is given.

		Described in Section 8.1.5.1.2.1 of IETF draft-ietf-cellar-matroska-08
	*/
	CueTrack                           = 0xF7,

	/*
		The Segment Position of the Cluster containing the associated Block.

		Described in Section 8.1.5.1.2.2 of IETF draft-ietf-cellar-matroska-08
	*/
	CueClusterPosition                 = 0xF1,

	/*
		The relative position inside the Cluster of the referenced SimpleBlock or BlockGroup with 0
		being the first possible position for an Element inside that Cluster.

		Described in Section 8.1.5.1.2.3 of IETF draft-ietf-cellar-matroska-08
	*/
	CueRelativePosition                = 0xF0,

	/*
		The duration of the block according to the Segment time base. If missing the track's
		DefaultDuration does not apply and no duration information is available in terms of the cues.

		Described in Section 8.1.5.1.2.4 of IETF draft-ietf-cellar-matroska-08
	*/
	CueDuration                        = 0xB2,

	/*
		Number of the Block in the specified Cluster.

		Described in Section 8.1.5.1.2.5 of IETF draft-ietf-cellar-matroska-08
	*/
	CueBlockNumber                     = 0x5378,

	/*
		The Segment Position of the Codec State corresponding to this Cue Element.
		0 means that the data is taken from the initial Track Entry.

		Described in Section 8.1.5.1.2.6 of IETF draft-ietf-cellar-matroska-08
	*/
	CueCodecState                      = 0xEA,

	/*
		The Clusters containing the referenced Blocks.

		Described in Section 8.1.5.1.2.7 of IETF draft-ietf-cellar-matroska-08
	*/
	CueReference                       = 0xDB,

	/*
		Timestamp of the referenced Block.

		Described in Section 8.1.5.1.2.8 of IETF draft-ietf-cellar-matroska-08
	*/
	CueRefTime                         = 0x96,




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

Matroska_Schema :: #partial [EBML_ID]EBML_Type_Info {
	.Segment = {
		.Master, .Intern, "Segment",
	},

}