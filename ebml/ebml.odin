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

	This file contains the EBML format parser.
*/

import "core:os"
import "../common"

DEBUG         :: #config(EBML_DEBUG, false)
DEBUG_VERBOSE :: #config(EBML_DEBUG_VERBOSE, 0)

parse_header :: proc(f: ^EBML_File, parse_metadata := true) -> (err: Error) {
	context.allocator = f.allocator

	when DEBUG {
		println(1, "Parsing EBML Header...\n")
		defer {
			println(0, "")
			println(1, "Back from parsing EBML header...")
		}
	}

	offset: i64
	ok:     bool

	document: ^EBML_Document
	parent:   ^EBML_Element
	this:     ^EBML_Element
	prev:     ^EBML_Element

	/*
		Read header.
	*/
	if offset, ok = common.get_pos(f.handle); !ok { return .Read_Error }

	id, id_size  := read_variable_id(f) or_return
	if id != .EBML { return .EBML_Header_Missing_or_Corrupt }

	length, length_size := read_variable_int(f) or_return

	when DEBUG {
		printf(0, "[parse] offset: %v\n", offset)
		printf(1, "ID:     0x%08X (%v), ID Size: %v\n", int(id), id, id_size)
		printf(1, "Length: %v, Length Size: %v\n",      length, length_size)
	}

	document = new(EBML_Document)
	append(&f.documents, document)

	/*
		Set EBML header defaults, in case they're omitted.
	*/
	document.version         = EBML_VERSION // EBMLVersion
	document.read_version    = EBML_VERSION // EBMLReadVersion
	document.max_id_length   = 4            // EBMLMaxIDLength
	document.max_size_length = 8            // EBMLMaxSizeLength

	/*
		Set up common element members.
	*/
	element := EBML_Element {
		offset         = offset,
		size           = i64(id_size) + i64(length_size) + i64(length),
		end            = offset + i64(id_size) + i64(length_size) + i64(length) - 1,
		payload_offset = offset + i64(id_size) + i64(length_size),
		payload_size   = i64(length),
		id             = id,
	}
	this = new_clone(element)

	this.type       = .Master
	this.level      = 0
	this.parent     = this

	document.header = this
	parent          = this
	prev            = this

	loop: for {
		if offset, ok = common.get_pos(f.handle); !ok { return .Read_Error }
		if offset > document.header.end {
			/*
				We're past the header.
			*/
			when DEBUG_VERBOSE >= 1 {
				println(0, "Returning because we've parsed the header...\n")
			}
			break loop
		}

		id,     id_size     = read_variable_id(f) or_return
		length, length_size = read_variable_int(f) or_return

		if id == .EBML {
			/*
				Shouldn't account a header element while parsing a previous one.
			*/
			return .EBML_Header_Duplicated
		}

		when DEBUG_VERBOSE >= 3 {
			printf(0, "[parse] offset: %v\n", offset)
			printf(1, "ID:     0x%08X (%v), ID Size: %v\n", int(id), _string(id), id_size)
			printf(1, "Length: %v, Length Size: %v\n",      length, length_size)
		}

		/*
			Find the parent by what byte range of the file we're at.
		*/
		parent = prev
		for {
			if offset >= parent.end {
				/*
					Parent can't contain this element. Let's look at its parent.
				*/
				when DEBUG_VERBOSE >= 4 {
					printf(2, "[%v] ends past ", _string(id))
					printf(0, "[%v] end, checking if ", _string(parent.id))
					printf(0, "[%v] is our parent.\n", _string(parent.parent.id))
				}
				parent = parent.parent
			} else {
				/*
					Element fits within this parent.
				*/
				break
			}
		}

		/*
			Set up common element members.
		*/
		element = EBML_Element {
			offset         = offset,
			size           = i64(id_size) + i64(length_size) + i64(length),
			end            = offset + i64(id_size) + i64(length_size) + i64(length) - 1,
			payload_offset = offset + i64(id_size) + i64(length_size),
			payload_size   = i64(length),
			id             = id,
			level          = 1,
			parent         = parent,
		}
		this = new_clone(element)

		if parent != this && parent != nil {
			if this.parent.first_child == nil {
				this.parent.first_child = this
			} else {
				/*
					Chain.
				*/
				sibling := this.parent.first_child
				for ; sibling.next != nil; sibling = sibling.next {}
				sibling.next = this
			}
		}

		#partial switch id {
		case .EBMLVersion:
			/*
				Version of the EBML specifications used to create the EBML document.
				Described in Section 11.2.2 of RFC 8794.
			*/
			if length != 1                                                       { return .EBML_Header_Unexpected_Field_Length }
			if document.version, ok = common.read_u8(f.handle); !ok              { return .Read_Error }
			if document.version != EBML_VERSION                                  { return .Unsupported_EBML_Version }

			this.type    = .Unsigned
			this.payload = u64(document.version)

		case .EBMLReadVersion:
			/*
				The minimum EBML version a reader has to support to read this document.
				Described in Section 11.2.3 of RFC 8794.
			*/
			if length != 1                                                       { return .EBML_Header_Unexpected_Field_Length }
			if document.read_version, ok = common.read_u8(f.handle); !ok         { return .Read_Error }
			if document.read_version > EBML_VERSION                              { return .Unsupported_EBML_Version }

			this.type    = .Unsigned
			this.payload = u64(document.read_version)

		case .EBMLMaxIDLength:
			/*
				The EBMLMaxIDLength Element stores the maximum permitted length in octets of the Element
					IDs to be found within the EBML Body.
				Described in Section 11.2.4 of RFC 8794.
			*/
			if length != 1 { return .EBML_Header_Unexpected_Field_Length }


			if document.max_id_length, ok = common.read_u8(f.handle); !ok        { return .Read_Error }
			if document.max_id_length > 8 || document.max_id_length < 4          { return .Max_ID_Length_Invalid }

			this.type = .Unsigned
			this.payload = u64(document.max_id_length)

		case .EBMLMaxSizeLength:
			/*
				The EBMLMaxSizeLength Element stores the maximum permitted length in octets of the
					expressions of all Element Data Sizes to be found within the EBML Body.
				Described in Section 11.2.5 of RFC 8794.
			*/
			if length != 1 { return .EBML_Header_Unexpected_Field_Length }

			if document.max_size_length, ok = common.read_u8(f.handle); !ok      { return .Read_Error }
			if document.max_size_length > 8 || document.max_size_length == 0     { return .Max_Size_Invalid }

			this.type = .Unsigned
			this.payload = u64(document.max_size_length)

		case .DocType:
			/*
				A string that describes and identifies the content of the EBML Body that follows this EBML Header.
				Described in Section 11.2.6 of RFC 8794.
			*/
			if length == 0                                                       { return .DocType_Empty }
			if MAX_DOCTYPE_LENGTH > 0 && length > MAX_DOCTYPE_LENGTH             { return .DocType_Too_Long }

			val := read_string(f, length) or_return

			this.type        = .String
			this.payload     = String(val)
			document.doctype = String(val)

		case .DocTypeVersion:
			/*
				The version of DocType interpreter used to create the EBML Document.
				Described in Section 11.2.7 of RFC 8794.
			*/
			if length != 1                                                       { return .EBML_Header_Unexpected_Field_Length }
			if document.doctype_version, ok = common.read_u8(f.handle); !ok      { return .Read_Error }
			if document.doctype_version == 0                                     { return .DocTypeVersion_Invalid }

			this.type    = .Unsigned
			this.payload = u64(document.doctype_version)

		case .DocTypeReadVersion:
			/*
				The minimum DocType version an EBML Reader has to support to read this EBML Document.
				Described in Section 11.2.8 of RFC 8794.
			*/
			if length != 1 { return .EBML_Header_Unexpected_Field_Length }

			if document.doctype_read_version, ok = common.read_u8(f.handle); !ok { return .Read_Error }
			if document.doctype_read_version == 0                                { return .DocTypeReadVersion_Invalid }

			this.type    = .Unsigned
			this.payload = u64(document.doctype_read_version)


		case .DocTypeExtension:
			/*
				A DocTypeExtension adds extra Elements to the main DocType+DocTypeVersion tuple it's attached to.
				Described in Section 11.2.9 of RFC 8794.
			*/
			this.type   = .Master

		case .DocTypeExtensionName:
			/*
				The name of the DocTypeExtension to differentiate it from other DocTypeExtensions
					of the same DocType+DocTypeVersion tuple.
				Described in Section 11.2.10 of RFC 8794.
			*/
			if length == 0                 { return .DocType_Empty }
			if length > MAX_DOCTYPE_LENGTH { return .DocType_Too_Long }

			intern_string(f, length, this) or_return

		case .DocTypeExtensionVersion:
			/*
				The version of the DocTypeExtension. Different DocTypeExtensionVersion values of the same
					DocType + DocTypeVersion + DocTypeExtensionName tuple contain completely different sets of extra Elements.
				Described in Section 11.2.11 of RFC 8794.
			*/
			if length != 1 { return .EBML_Header_Unexpected_Field_Length }

			if dtev, dtev_ok := common.read_u8(f.handle); !dtev_ok {
				return .Read_Error
			} else {
				this.type    = .Unsigned
				this.payload = u64(dtev)
			}

		case .CRC_32:
			/*
				The CRC-32 Element contains a 32-bit Cyclic Redundancy Check value of all the
					Element Data of the Parent Element as stored except for the CRC-32 Element itself. 
				Described in Section 11.3.1 of RFC 8794.
			*/
			if length != 4 { return .Invalid_CRC_Size }
			if crc32, crc32_ok := common.read_data(f.handle, u32); !crc32_ok {
				return .Read_Error
			} else {
				this.type    = .Unsigned
				this.payload = u64(crc32)
			}

		case .Void:
			/*
				Used to void data or to avoid unexpected behaviors when using damaged data. The
					content is discarded. Also used to reserve space in a subelement for later use. 
				Described in Section 11.3.2 of RFC 8794.
			*/
			fallthrough

		case:
			/*
				We don't know this payload or there is no payload (Void), seek to next.
			*/
			if !common.set_pos(f.handle, this.end + 1) { return .Read_Error }
		}

		prev = this
	}

	if len(document.doctype) == 0                               { return .DocType_Empty }
	if document.doctype_read_version > document.doctype_version { return .DocTypeReadVersion_Invalid }


	return .None
}

parse_generic_schema :: proc(f: ^EBML_File, document: ^EBML_Document) -> (err: Error) {
	context.allocator = f.allocator

	when DEBUG {
		println(1, "Parsing Unknown EBML Document...\n")
		defer {
			println(0, "")
			println(1, "Back from parsing Unknown EBML Document...")
		}
	}

	offset: i64
	ok:     bool

	if offset, ok = common.get_pos(f.handle); !ok { return .Read_Error }
	id,     id_size     := read_variable_id(f) or_return
	length, length_size := read_variable_int(f) or_return

	/*
		Set up common element members.
	*/
	element := EBML_Element {
		offset         = offset,
		size           = i64(id_size) + i64(length_size) + i64(length),
		end            = offset + i64(id_size) + i64(length_size) + i64(length) - 1,
		payload_offset = offset + i64(id_size) + i64(length_size),
		payload_size   = i64(length),
		id             = id,
	}
	this := new_clone(element)

	this.type          = .Master
	this.level         = 0
	this.parent        = this

	document.body      = this
	parent            := this
	prev              := this

	loop: for {
		if offset, ok = common.get_pos(f.handle); !ok { return .Read_Error }
		if offset >= f.file_info.size {
			/*
				We're past the header.
			*/
			when DEBUG_VERBOSE >= 1 {
				println(0, "Returning because we're at the end of the file...\n")
			}
			break loop
		}

		id,     id_size     = read_variable_id(f) or_return
		length, length_size = read_variable_int(f) or_return

		if id == .EBML {
			/*
				New EBML stream starting.
				Rewind to its offset and let the header parser handle it.
			*/
			if !common.set_pos(f.handle, offset) { return .Read_Error }
			return .None
		}

		when DEBUG_VERBOSE >= 3 {
			printf(0, "[parse] offset: %v\n", offset)
			printf(1, "ID:     0x%08X (%v), ID Size: %v\n", int(id), _string(id), id_size)
			printf(1, "Length: %v, Length Size: %v\n",      length, length_size)
		}

		/*
			Find the parent by what byte range of the file we're at.
		*/
		parent = prev
		for {
			if offset >= parent.end {
				/*
					Parent can't contain this element. Let's look at its parent.
				*/
				when DEBUG_VERBOSE >= 4 {
					printf(2, "[%v] ends past ", _string(id))
					printf(0, "[%v] end, checking if ", _string(parent.id))
					printf(0, "[%v] is our parent.\n", _string(parent.parent.id))
				}
				parent = parent.parent
			} else {
				/*
					Element fits within this parent.
				*/
				break
			}
		}

		/*
			Set up common element members.
		*/
		element = EBML_Element {
			offset         = offset,
			size           = i64(id_size) + i64(length_size) + i64(length),
			end            = offset + i64(id_size) + i64(length_size) + i64(length) - 1,
			payload_offset = offset + i64(id_size) + i64(length_size),
			payload_size   = i64(length),
			id             = id,
			level          = 1,
			parent         = parent,
		}
		this = new_clone(element)

		if parent != this && parent != nil {
			if this.parent.first_child == nil {
				this.parent.first_child = this
			} else {
				/*
					Chain.
				*/
				sibling := this.parent.first_child
				for ; sibling.next != nil; sibling = sibling.next {}
				sibling.next = this
			}
		}

		#partial switch id {
		case .CRC_32:
			/*
				The CRC-32 Element contains a 32-bit Cyclic Redundancy Check value of all the
					Element Data of the Parent Element as stored except for the CRC-32 Element itself. 
				Described in Section 11.3.1 of RFC 8794.
			*/
			if length != 4 { return .Invalid_CRC_Size }
			if crc32, crc32_ok := common.read_data(f.handle, u32); !crc32_ok {
				return .Read_Error
			} else {
				this.type    = .Unsigned
				this.payload = u64(crc32)
			}

		case .Void:
			/*
				Used to void data or to avoid unexpected behaviors when using damaged data. The
					content is discarded. Also used to reserve space in a subelement for later use. 
				Described in Section 11.3.2 of RFC 8794.
			*/
			fallthrough

		case:
			/*
				We don't know this payload or there is no payload (Void), seek to next.
			*/
			if !common.set_pos(f.handle, this.end + 1) { return .Read_Error }
		}
		prev = this
	}

	return .None
}

parse_matroska :: proc(f: ^EBML_File, document: ^EBML_Document, skip_clusters := true, return_after_cluster := true) -> (err: Error) {
	context.allocator = f.allocator

	when DEBUG {
		println(1, "Parsing Matroska Document...\n")
		defer {
			println(0, "")
			println(1, "Back from parsing Matroska Document...")
		}
	}

	offset: i64
	ok:     bool

	if offset, ok = common.get_pos(f.handle); !ok { return .Read_Error }
	id,     id_size     := read_variable_id(f) or_return
	length, length_size := read_variable_int(f) or_return

	/*
		TODO(Jeroen): Do this only if we've just started parsing the body, not when we're parsing incrementally.
	*/
	if id != .Matroska_Segment { return .Matroska_Body_Root_Wrong_ID }

	/*
		Set up common element members.
	*/
	element := EBML_Element {
		offset         = offset,
		size           = i64(id_size) + i64(length_size) + i64(length),
		end            = offset + i64(id_size) + i64(length_size) + i64(length) - 1,
		payload_offset = offset + i64(id_size) + i64(length_size),
		payload_size   = i64(length),
		id             = id,
	}
	this := new_clone(element)

	this.type          = .Master
	this.level         = 0
	this.parent        = this

	document.body      = this
	parent            := this
	prev              := this

	last_cluster: ^EBML_Element

	loop: for {
		if offset, ok = common.get_pos(f.handle); !ok { return .Read_Error }

		if return_after_cluster && last_cluster != nil {
			if offset == last_cluster.end + 1 {
				return .None
			}
		}

		if offset >= f.file_info.size {
			/*
				We're past the header.
			*/
			when DEBUG_VERBOSE >= 1 {
				println(0, "Returning because we're at the end of the file...\n")
			}
			break loop
		}

		id,     id_size     = read_variable_id(f) or_return
		length, length_size = read_variable_int(f) or_return

		if id == .EBML {
			/*
				New EBML stream starting.
				Rewind to its offset and let the header parser handle it.
			*/
			if !common.set_pos(f.handle, offset) { return .Read_Error }
			return .None
		}

		when DEBUG_VERBOSE >= 3 {
			printf(0, "[parse] offset: %v\n", offset)
			printf(1, "ID:     0x%X (%v), ID Size: %v\n", int(id), _string(id), id_size)
			printf(1, "Length: %v, Length Size: %v\n",      length, length_size)
		}

		/*
			Find the parent by what byte range of the file we're at.
		*/
		parent = prev
		for {
			if offset >= parent.end {
				/*
					Parent can't contain this element. Let's look at its parent.
				*/
				when DEBUG_VERBOSE >= 4 {
					printf(2, "[%v] ends past ", _string(id))
					printf(0, "[%v] end, checking if ", _string(parent.id))
					printf(0, "[%v] is our parent.\n", _string(parent.parent.id))
				}
				parent = parent.parent
			} else {
				/*
					Element fits within this parent.
				*/
				break
			}
		}

		/*
			Set up common element members.
		*/
		element = EBML_Element {
			offset         = offset,
			size           = i64(id_size) + i64(length_size) + i64(length),
			end            = offset + i64(id_size) + i64(length_size) + i64(length) - 1,
			payload_offset = offset + i64(id_size) + i64(length_size),
			payload_size   = i64(length),
			id             = id,
			level          = 1,
			parent         = parent,
		}
		this = new_clone(element)

		if parent != this && parent != nil {
			if this.parent.first_child == nil {
				this.parent.first_child = this
			} else {
				/*
					Chain.
				*/
				sibling := this.parent.first_child
				for ; sibling.next != nil; sibling = sibling.next {}
				sibling.next = this
			}
		}

		#partial switch id {
		case .CRC_32:
			/*
				The CRC-32 Element contains a 32-bit Cyclic Redundancy Check value of all the
					Element Data of the Parent Element as stored except for the CRC-32 Element itself. 
				Described in Section 11.3.1 of RFC 8794.
			*/
			if length != 4 { return .Invalid_CRC_Size }
			if crc32, crc32_ok := common.read_data(f.handle, u32); !crc32_ok {
				return .Read_Error
			} else {
				this.type    = .Unsigned
				this.payload = u64(crc32)
			}

		case .Matroska_SeekHead:
			/*
				Contains the Segment Position of other Top-Level Elements.
			*/
			this.type        = .Master

		case .Matroska_Seek:
			/*
				Contains a single seek entry to an EBML Element.
			*/
			this.type        = .Master

		case .Matroska_SeekID:
			/*
				The binary ID corresponding to the Element name.
			*/
			intern_binary(f, length, this) or_return

		case .Matroska_SeekPosition:
			/*
				The Segment Position of the Element.
			*/
			seek_pos := _read_uint(f, length) or_return

			/*
				SeekPosition is relative to the beginning of the SeekHead offset.
			*/
			if this.parent.id != .Matroska_Seek && this.parent.id != .Matroska_SeekHead { return .Matroska_Broken_SeekPosition }
			seek_pos += u64(this.parent.parent.offset)

			this.type        = .Unsigned
			this.payload     = seek_pos

		case .Matroska_Info:
			/*
				Contains general information about the Segment.
				Described in Section 8.1.2 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type        = .Master

		case .Matroska_SegmentUID, .Matroska_PrevUID, .Matroska_NextUID, .Matroska_SegmentFamily:
			/*
				A randomly generated unique ID to identify this, the next or previous Segment amongst many others (128 bits).
				Described in Sections 8.1.2.1, 8.1.2.3, 8.1.2.5 and 8.1.2.7 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type        = .Matroska_UUID

			if length != 16 { return .Matroska_SegmentUID_Invalid_Length }

			if payload, payload_ok := common.read_slice(f.handle, length); !payload_ok {
				return .Read_Error
			} else {
				this.payload = (^Matroska_UUID)(raw_data(payload))^
			}

		case .Matroska_SegmentFilename, .Matroska_PrevFilename, .Matroska_NextFilename:
			/*
				A filename corresponding to this, the previous or next Segment.
				Described in Sections 8.1.2.2. 8.1.2.4 and 8.1.2.6 of IETF draft-ietf-cellar-matroska-08	
			*/
			intern_utf8(f, length, this) or_return

		case .Matroska_ChapterTranslate:
			/*
				A tuple of corresponding ID used by chapter codecs to represent this Segment.
			*/
			this.type        = .Master

		case .Matroska_ChapterTranslateEditionUID:
			/*
				Specify an edition UID on which this correspondence applies. When not specified,
					it means for all editions found in the Segment.
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_ChapterTranslateCodec:
			/*
				The chapter codec; see Section 8.1.7.1.4.15.
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_ChapterTranslateID:
			/*
				The binary value used to represent this Segment in the chapter codec data.
				The format depends on the ChapProcessCodecID used; see Section 8.1.7.1.4.15.

				Described in Section 8.1.2.8.3 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_binary(f, length, this) or_return

		case .Matroska_TimestampScale:
			/*
				Timestamp scale in nanoseconds (1_000_000 means all timestamps in the Segment are expressed in milliseconds).

				Described in Section 8.1.2.9 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_Duration:
			/*
				Duration of the Segment in nanoseconds based on TimestampScale.

				Described in Section 8.1.2.10 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_float(f, length, this) or_return

		case .Matroska_DateUTC:
			/*
				The date and time that the Segment was created by the muxing application or library.

				Described in Section 8.1.2.11 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type        = .Matroska_Time
			nanoseconds     := _read_sint(f, length) or_return
			this.payload     = nanoseconds_to_time(nanoseconds)

		case .Matroska_Title, .Matroska_MuxingApp, .Matroska_WritingApp:
			/*
				General name of the Segment, its MuxingApp and WritingApp.				

				Described in Sections 8.1.2.12. 8.1.2.13 and 8.1.2.14 of IETF draft-ietf-cellar-matroska-08	
			*/
			intern_utf8(f, length, this) or_return

		case .Matroska_Cluster:
			/*
				The Top-Level Element containing the (monolithic) Block structure.

				Described in Section 8.1.3 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type        = .Master
			last_cluster     = this

			if skip_clusters {
				if !common.set_pos(f.handle, this.end + 1) { return .Read_Error }	
			}

		case .Matroska_Timestamp:
			/*
				Absolute timestamp of the cluster (based on TimestampScale).

				Described in Section 8.1.3.1 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_Position:
			/*
				The Segment Position of the Cluster in the Segment (0 in live streams).
				It might help to resynchronise offset on damaged streams.

				Described in Section 8.1.3.2 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_PrevSize:
			/*
				Size of the previous Cluster, in octets. Can be useful for backward playing.

				Described in Section 8.1.3.3 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_SimpleBlock:
			/*
				Similar to Block, see Section 12, but without all the extra information,
					mostly used to reduce overhead when no extra feature is needed;
					see Section 12.4 on SimpleBlock Structure.

				Described in Section 8.1.3.4 of IETF draft-ietf-cellar-matroska-08

				We don't intern the payload, for obvious reasons.
				The offsets and lengths are enough for a player/tool to use.
			*/
			skip_binary(f, length, this) or_return

		case .Matroska_BlockGroup:
			/*
				Basic container of information containing a single Block and information specific to that Block.

				Described in Section 8.1.3.5 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type        = .Master

		case .Matroska_Block:
			/*
				Block containing the actual data to be rendered and a timestamp relative to the
					Cluster Timestamp; see Section 12 on Block Structure.

				Described in Section 8.1.3.5.1 of IETF draft-ietf-cellar-matroska-08
			*/
			skip_binary(f, length, this) or_return

		case .Matroska_BlockAdditions:
			/*
				Contain additional blocks to complete the main one. An EBML parser that has no knowledge
					of the Block structure could still see and use/skip these data.

				Described in Section 8.1.3.5.2 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type        = .Master

		case .Matroska_BlockMore:
			/*
				Contain the BlockAdditional and some parameters.

				Described in Section 8.1.3.5.2.1 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type        = .Master

		case .Matroska_BlockAddID:
			/*
				Contain the BlockAdditional and some parameters.

				Described in Section 8.1.3.5.2.2 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_BlockAdditional:
			/*
				Contain the BlockAdditional and some parameters.

				Described in Section 8.1.3.5.2.3 of IETF draft-ietf-cellar-matroska-08
			*/
			skip_binary(f, length, this) or_return

		case .Matroska_BlockDuration:
			/*
				The duration of the Block (based on TimestampScale).

				Described in Section 8.1.3.5.3 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_ReferencePriority:
			/*
				This frame is referenced and has the specified cache priority. In cache only a frame of the
					same or higher priority can replace this frame. A value of 0 means the frame is not referenced.

				Described in Section 8.1.3.5.4 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_ReferenceBlock:
			/*
				Timestamp of another frame used as a reference (ie: B or P frame).
					The timestamp is relative to the block it's attached to.

				Described in Section 8.1.3.5.5 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_CodecState:
			/*
				The new codec state to use. Data interpretation is private to the codec.
					This information SHOULD always be referenced by a seek entry.

				Described in Section 8.1.3.5.6 of IETF draft-ietf-cellar-matroska-08
			*/
			skip_binary(f, length, this) or_return

		case .Matroska_DiscardPadding:
			/*
				Duration in nanoseconds of the silent data added to the Block (padding at the end of the Block
					for positive value, at the beginning of the Block for negative value). The duration of
					DiscardPadding is not calculated in the duration of the TrackEntry and SHOULD be discarded
					during playback.

				Described in Section 8.1.3.5.7 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_sint(f, length, this) or_return

		case .Matroska_Slices:
			/*
				Contains slices description.

				Described in Section 8.1.3.5.8 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type        = .Master

		case .Matroska_TimeSlice:
			/*
				Contains extra time information about the data contained in the Block.
					Being able to interpret this Element is not REQUIRED for playback.

				Described in Section 8.1.3.5.8.1 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type        = .Master

		case .Matroska_LaceNumber:
			/*
				The reverse number of the frame in the lace (0 is the last frame, 1 is the next to last, etc).
					Being able to interpret this Element is not REQUIRED for playback.

				Described in Section 8.1.3.5.8.2 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_Tracks:
			/*
				A Top-Level Element of information with many tracks described.

				Described in Section 8.1.4 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type        = .Master
	
		case .Matroska_TrackEntry:
			/*
				Describes a track with all Elements.

				Described in Section 8.1.4.1 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type        = .Master

		case .Matroska_TrackNumber:
			/*
				The track number as used in the Block Header (using more than 127 tracks is not encouraged,
					though the design allows an unlimited number).

				Described in Section 8.1.4.1.1 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_TrackUID:
			/*
				A unique ID to identify the Track.

				Described in Section 8.1.4.1.2 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_TrackType:
			/*
				A set of track types coded on 8 bits.

				Described in Section 8.1.4.1.3 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type        = .Matroska_Track_Type
			if length != 1 { return .Matroska_Track_Type_Invalid_Length }

			track_type      := _read_uint(f, length) or_return
			this.payload     = Matroska_Track_Type(u8(track_type))

		case .Matroska_FlagEnabled, .Matroska_FlagDefault, .Matroska_FlagForced:
			/*
				Set to 1 if the track is usable. etc.

				Described in Section 8.1.4.1.4 .. 8.1.4.1.6 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_FlagHearingImpaired, .Matroska_FlagVisualImpaired, .Matroska_FlagTextDescriptions, .Matroska_FlagOriginal, .Matroska_FlagCommentary, .Matroska_FlagLacing:
			/*
				Set to 1 if the track is usable. etc.

				Described in Section 8.1.4.1.7 .. 12
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_MinCache, .Matroska_MaxCache:
			/*
				The minimum/maximum cache size necessary to store referenced frames in and the current frame.
				0 means no cache is needed.

				Described in Section 8.1.4.1.13 .. 14
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_DefaultDuration:
			/*
				Number of nanoseconds (not scaled via TimestampScale) per frame
				(frame in the Matroska sense -- one Element put into a (Simple)Block).

				Described in Section 8.1.4.1.15 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_DefaultDecodedFieldDuration:
			/*
				The period in nanoseconds (not scaled by TimestampScale) between two successive fields at
				the output of the decoding process, see Section 11 for more information

				Described in Section 8.1.4.1.16 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_TrackTimestampScale:
			/*
				DEPRECATED, DO NOT USE. The scale to apply on this track to work at normal speed in relation with other tracks
				s(mostly used to adjust video speed when the audio length differs).

				Described in Section 8.1.4.1.17 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_float(f, length, this) or_return

		case .Matroska_MaxBlockAdditionID:
			/*
				The maximum value of BlockAddID (Section 8.1.3.5.2.2).
				A value 0 means there is no BlockAdditions (Section 8.1.3.5.2) for this track.

				Described in Section 8.1.4.1.18 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_BlockAdditionMapping:
			/*
				Contains elements that extend the track format, by adding content either to each frame,
				with BlockAddID (Section 8.1.3.5.2.2), or to the track as a whole with BlockAddIDExtraData.

				Described in Section 8.1.4.1.19 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type        = .Master

		case .Matroska_BlockAddIDValue:
			/*
				If the track format extension needs content beside frames, the value refers to the BlockAddID
				(Section 8.1.3.5.2.2), value being described. To keep MaxBlockAdditionID as low as possible,
				small values SHOULD be used.

				Described in Section 8.1.4.1.19.1 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_BlockAddIDName:
			/*
				A human-friendly name describing the type of BlockAdditional data,
				as defined by the associated Block Additional Mapping.

				Described in Section 8.1.4.1.19.2 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_string(f, length, this) or_return

		case .Matroska_BlockAddIDType:
			/*
				Stores the registered identifier of the Block Additional Mapping to define how the BlockAdditional
				data should be handled.

				Described in Section 8.1.4.1.19.3 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_BlockAddIDExtraData:
			/*
				Extra binary data that the BlockAddIDType can use to interpret the BlockAdditional data.
				The interpretation of the binary data depends on the BlockAddIDType value and the corresponding
				Block Additional Mapping.

				Described in Section 8.1.4.1.19.4 of IETF draft-ietf-cellar-matroska-08
			*/
			skip_binary(f, length, this) or_return

		case .Matroska_Track_Name:
			/*
				A human-readable track name.

				Described in Section 8.1.4.1.20 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_utf8(f, length, this) or_return

		case .Matroska_Language:
			/*
				Specifies the language of the track in the Matroska languages form; see Section 6 on language codes.
				This Element MUST be ignored if the LanguageIETF Element is used in the same TrackEntry.

				Described in Section 8.1.4.1.21 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_utf8(f, length, this) or_return

		case .Matroska_Language_IETF:
			/*
				Specifies the language of the track according to [BCP47] and using the IANA Language Subtag Registry
				[IANALangRegistry]. If this Element is used, then any Language Elements used in the same TrackEntry
				MUST be ignored.

				Described in Section 8.1.4.1.22 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_string(f, length, this) or_return

		case .Matroska_CodecID:
			/*
				An ID corresponding to the codec, see [MatroskaCodec] for more info.

				Described in Section 8.1.4.1.23 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_string(f, length, this) or_return

		case .Matroska_CodecPrivate:
			/*
				Private data only known to the codec.

				Described in Section 8.1.4.1.24 of IETF draft-ietf-cellar-matroska-08
			*/
			skip_binary(f, length, this) or_return

		case .Matroska_CodecName:
			/*
				A human-readable string specifying the codec.

				Described in Section 8.1.4.1.25 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_utf8(f, length, this) or_return

		case .Matroska_AttachmentLink:
			/*
				The UID of an attachment that is used by this codec.

				Described in Section 8.1.4.1.26 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_TrackOverlay:
			/*
				Specify that this track is an overlay track for the Track specified (in the u-integer).
				That means when this track has a gap, see Section 26.3.1 on SilentTracks, the overlay track
				SHOULD be used instead.

				Described in Section 8.1.4.1.27 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_CodecDelay:
			/*
				CodecDelay is The codec-built-in delay in nanoseconds. This value MUST be subtracted from each block
				timestamp in order to get the actual timestamp. The value SHOULD be small so the muxing of tracks with
				the same actual timestamp are in the same Cluster.

				Described in Section 8.1.4.1.28 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_SeekPreRoll:
			/*
				After a discontinuity, SeekPreRoll is the duration in nanoseconds of the data the decoder
				MUST decode before the decoded data is valid.

				Described in Section 8.1.4.1.29 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_TrackTranslate:
			/*
				The track identification for the given Chapter Codec.

				Described in Section 8.1.4.1.30 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type        = .Master

		case .Matroska_TrackTranslateEditionUID:
			/*
				Specify an edition UID on which this translation applies.
				When not specified, it means for all editions found in the Segment.

				Described in Section 8.1.4.1.30.1 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_TrackTranslateCodec:
			/*
				The chapter codec; see Section 8.1.7.1.4.15.

				Described in Section 8.1.4.1.30.2 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_TrackTranslateTrackID:
			/*
				The binary value used to represent this track in the chapter codec data.
				The format depends on the ChapProcessCodecID used; see Section 8.1.7.1.4.15.

				Described in Section 8.1.4.1.30.3 of IETF draft-ietf-cellar-matroska-08
			*/
			skip_binary(f, length, this) or_return

		case .Matroska_Video:
			/*
				Video settings.

				Described in Section 8.1.4.1.31 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type        = .Master

		case .Matroska_FlagInterlaced:
			/*
				Specify whether the video frames in this track are interlaced or not.

				Described in Section 8.1.4.1.31.1 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_FieldOrder:
			/*
				Specify the field ordering of video frames in this track.

				Described in Section 8.1.4.1.31.2 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_StereoMode:
			/*
				Stereo-3D video mode. There are some more details in Section 20.10.

				Described in Section 8.1.4.1.31.3 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_AlphaMode:
			/*
				Alpha Video Mode. Presence of this Element indicates that the BlockAdditional Element could contain Alpha data.

				Described in Section 8.1.4.1.31.4 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_PixelWidth, .Matroska_PixelHeight:
			/*
				Width, Height of the encoded video frames in pixels.

				Described in Section 8.1.4.1.31.5 .. 6 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_PixelCropBottom, .Matroska_PixelCropTop, .Matroska_PixelCropLeft, .Matroska_PixelCropRight:
			/*
				Crops.

				Described in Section 8.1.4.1.31.7 .. 10 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_DisplayWidth, .Matroska_DisplayHeight:
			/*
				Display Width + Height

				Described in Section 8.1.4.1.31.11 .. 12 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_DisplayUnit:
			/*
				How DisplayWidth & DisplayHeight are interpreted.

				Described in Section 8.1.4.1.31.13 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_ColourSpace:
			/*
				Specify the pixel format used for the Track's data as a FourCC.
				This value is similar in scope to the biCompression value of AVI's BITMAPINFOHEADER.

				Described in Section 8.1.4.1.31.14 of IETF draft-ietf-cellar-matroska-08
			*/
			skip_binary(f, length, this) or_return

		case .Matroska_Colour:
			/*
				Settings describing the colour format.

				Described in Section 8.1.4.1.31.15 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type        = .Master

		case .Matroska_MatrixCoefficients:
			/*
				The Matrix Coefficients of the video used to derive luma and chroma values from
				red, green, and blue color primaries. For clarity, the value and meanings for
				MatrixCoefficients are adopted from Table 4 of ISO/IEC 23001-8:2016 or ITU-T H.273.

				Described in Section 8.1.4.1.31.16 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_ChromaSubsamplingHorz, .Matroska_ChromaSubsamplingVert,
			 .Matroska_CbSubsamplingHorz,     .Matroska_CbSubsamplingVert,
			 .Matroska_ChromaSitingHorz,      .Matroska_ChromaSitingVert:
			/*
				The amount of pixels to remove in the Cr and Cb channels for every pixel not removed horizontally.
				Example: For video with 4:2:0 chroma subsampling, the ChromaSubsamplingHorz SHOULD be set to 1.

				The amount of pixels to remove in the Cr and Cb channels for every pixel not removed vertically.
				Example: For video with 4:2:0 chroma subsampling, the ChromaSubsamplingVert SHOULD be set to 1.

				Described in Section 8.1.4.1.31.18 .. 23 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_Range:
			/*
				Clipping of the color ranges.

				Described in Section 8.1.4.1.31.24 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_TransferCharacteristics, .Matroska_Primaries:
			/*
				The transfer characteristics of the video. For clarity, the value and meanings for
				TransferCharacteristics are adopted from Table 3 of ISO/IEC 23091-4 or ITU-T H.273.

				The colour primaries of the video. For clarity, the value and meanings for Primaries
				are adopted from Table 2 of ISO/IEC 23091-4 or ITU-T H.273.

				Described in Section 8.1.4.1.31.25 .. 26 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_MaxCLL, .Matroska_MaxFALL:
			/*
				Maximum brightness of a single pixel (Maximum Content Light Level) in candelas per square meter (cd/m2).
				Maximum brightness of a single full frame (Maximum Frame-Average Light Level) in candelas per square meter (cd/m2).

				Described in Section 8.1.4.1.31.27 .. 28 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_MasteringMetadata:
			/*
				SMPTE 2086 mastering data.

				Described in Section 8.1.4.1.31.29 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type        = .Master

		case .Matroska_PrimaryRChromaticityX,   .Matroska_PrimaryRChromaticityY,
			 .Matroska_PrimaryGChromaticityX,   .Matroska_PrimaryGChromaticityY,
			 .Matroska_PrimaryBChromaticityX,   .Matroska_PrimaryBChromaticityY,
			 .Matroska_WhitePointChromaticityX, .Matroska_WhitePointChromaticityY:
			/*
				RGB-W chromaticity coordinates, as defined by CIE 1931.

				Described in Section 8.1.4.1.31.30 .. 37 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_float(f, length, this) or_return

		case .Matroska_LuminanceMax, .Matroska_LuminanceMin:
			/*
				Maximum/Minimum luminance. Represented in candelas per square meter (cd/m2).

				Described in Section 8.1.4.1.31.38 .. 39 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_float(f, length, this) or_return

		case .Matroska_Projection:
			/*
				Describes the video projection details. Used to render spherical and VR videos.

				Described in Section 8.1.4.1.31.40 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type        = .Master

		case .Matroska_ProjectionType:
			/*
				Describes the projection used for this video track.

				Described in Section 8.1.4.1.31.41 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_ProjectionPrivate:
			/*
				Private data that only applies to a specific projection.

				Described in Section 8.1.4.1.31.42 of IETF draft-ietf-cellar-matroska-08
			*/
			skip_binary(f, length, this) or_return

		case .Matroska_ProjectionPoseYaw, .Matroska_ProjectionPosePitch, .Matroska_ProjectionPoseRoll:
			/*
				Projection vector rotation.

				Described in Section 8.1.4.1.31.43 .. 45 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_float(f, length, this) or_return

		case .Matroska_Audio:
			/*
				Audio settings.

				Described in Section 8.1.4.1.32 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type        = .Master

		case .Matroska_SamplingFrequency:
			/*
				Sampling Frequency.

				Described in Section 8.1.4.1.32.1 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_float(f, length, this) or_return

		case .Matroska_OutputSamplingFrequency:
			/*
				Real output sampling frequency in Hz (used for SBR techniques).

				Described in Section 8.1.4.1.32.2 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_float(f, length, this) or_return

		case .Matroska_Channels, .Matroska_BitDepth:
			/*
				Channel count, bit depth.

				Described in Section 8.1.4.1.32.3 .. 4 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_TrackOperation, .Matroska_TrackCombinePlanes, .Matroska_TrackPlane:
			/*
				Operation that needs to be applied on tracks to create this virtual track.
				For more details look at Section 20.8.

				Contains the list of all video plane tracks that need to be combined to create this 3D track.

				Contains a video plane track that need to be combined to create this 3D track.

				Described in Section 8.1.4.1.33 .. 33.2 of IETF draft-ietf-cellar-matroska-08	
			*/
			this.type = .Master

		case .Matroska_TrackPlaneUID, .Matroska_TrackPlaneType:
			/*
				The trackUID number of the track representing the plane.
				The kind of plane this track corresponds to.

				Described in Section 8.1.4.1.33.3 .. 4 of IETF draft-ietf-cellar-matroska-08	
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_TrackJoinBlocks:
			/*
				Contains the list of all tracks whose Blocks need to be combined to create this virtual track.

				Described in Section 8.1.4.1.33.5 of IETF draft-ietf-cellar-matroska-08	
			*/
			this.type        = .Master

		case .Matroska_TrackJoinUID:
			/*
				The trackUID number of a track whose blocks are used to create this virtual track.

				Described in Section 8.1.4.1.33.6 of IETF draft-ietf-cellar-matroska-08	
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_ContentEncodings, .Matroska_ContentEncoding:
			/*
				Settings for several content encoding mechanisms like compression or encryption.
				Settings for one content encoding like compression or encryption.

				Described in Section 8.1.4.1.34, 34.1 of IETF draft-ietf-cellar-matroska-08	
			*/
			this.type        = .Master

		case .Matroska_ContentEncodingOrder, .Matroska_ContentEncodingScope, .Matroska_ContentEncodingType:
			/*
				Tells when this modification was used during encoding/muxing starting with 0 and counting upwards.
				The decoder/demuxer has to start with the highest order number it finds and work its way down.
				This value has to be unique over all ContentEncodingOrder Elements in the TrackEntry that
				contains this ContentEncodingOrder element.

				A bit field that describes which Elements have been modified in this way.
				Values (big-endian) can be OR'ed.

				A value describing what kind of transformation is applied.

				Described in Section 8.1.4.1.34.2 .. 4 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_ContentCompression:
			/*
				Settings describing the compression used. This Element MUST be present if the value of
				ContentEncodingType is 0 and absent otherwise. Each block MUST be decompressable even if no
				previous block is available in order not to prevent seeking.

				Described in Section 8.1.4.1.34.5 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type        = .Master

		case .Matroska_ContentCompAlgo:
			/*
				The compression algorithm used.

				Described in Section 8.1.4.1.34.6 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_ContentCompSettings:
			/*
				Settings that might be needed by the decompressor. For Header Stripping (ContentCompAlgo=3),
				the bytes that were removed from the beginning of each frames of the track.

				Described in Section 8.1.4.1.34.7 of IETF draft-ietf-cellar-matroska-08
			*/
			skip_binary(f, length, this) or_return

		case .Matroska_ContentEncryption:
			/*
				Settings describing the encryption used. This Element MUST be present if the value of
				ContentEncodingType is 1 (encryption) and MUST be ignored otherwise.

				Described in Section 8.1.4.1.34.8 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type        = .Master

		case .Matroska_ContentEncAlgo:
			/*
				The encryption algorithm used. The value "0" means that the contents have not been encrypted.

				Described in Section 8.1.4.1.34.9 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_ContentEncKeyID:
			/*
				For public key algorithms this is the ID of the public key the the data was encrypted with.

				Described in Section 8.1.4.1.34.10 of IETF draft-ietf-cellar-matroska-08
			*/
			skip_binary(f, length, this) or_return

		case .Matroska_ContentEncAESSettings:
			/*
				Settings describing the encryption algorithm used. If ContentEncAlgo != 5 this MUST be ignored.

				Described in Section 8.1.4.1.34.11 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type        = .Master

		case .Matroska_AESSettingsCipherMode:
			/*
				The AES cipher mode used in the encryption.

				Described in Section 8.1.4.1.34.12 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_Cues:
			/*
				A Top-Level Element to speed seeking access. All entries are local to the Segment.

				Described in Section 8.1.5 of IETF draft-ietf-cellar-matroska-08
			*/
			//this.type        = .Master
			skip_binary(f, length, this) or_return

		case .Matroska_CuePoint:
			/*
				Contains all information relative to a seek point in the Segment.

				Described in Section 8.1.5.1 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type        = .Master

		case .Matroska_CueTime:
			/*
				Absolute timestamp according to the Segment time base.

				Described in Section 8.1.5.1.1 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_CueTrackPositions:
			/*
				Contains all information relative to a seek point in the Segment.

				Described in Section 8.1.5.1.2 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type        = .Master


		case .Matroska_CueTrack:
			/*
				The track for which a position is given.

				Described in Section 8.1.5.1.2.1 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_CueClusterPosition:
			/*
				The Segment Position of the Cluster containing the associated Block.

				Described in Section 8.1.5.1.2.2 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_CueRelativePosition:
			/*
				The relative position inside the Cluster of the referenced SimpleBlock or BlockGroup with 0
				being the first possible position for an Element inside that Cluster.

				Described in Section 8.1.5.1.2.3 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_CueDuration:
			/*
				The duration of the block according to the Segment time base. If missing the track's
				DefaultDuration does not apply and no duration information is available in terms of the cues.

				Described in Section 8.1.5.1.2.4 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_CueBlockNumber:
			/*
				Number of the Block in the specified Cluster.

				Described in Section 8.1.5.1.2.5 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_CueCodecState:
			/*
				The Segment Position of the Codec State corresponding to this Cue Element.
				0 means that the data is taken from the initial Track Entry.

				Described in Section 8.1.5.1.2.6 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_CueReference:
			/*
				The Clusters containing the referenced Blocks.

				Described in Section 8.1.5.1.2.7 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type = .Master

		case .Matroska_CueRefTime:
			/*
				Timestamp of the referenced Block.

				Described in Section 8.1.5.1.2.8 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return


		case .Matroska_Segment_Attachment:
			/*
				Contain attached files.

				Described in Section 8.1.6 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type = .Master

		case .Matroska_AttachedFile:
			/*
				An attached file.

				Described in Section 8.1.6.1 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type = .Master

		case .Matroska_FileDescription:
			/*
				A human-friendly name for the attached file.

				Described in Section 8.1.6.1.1 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_utf8(f, length, this) or_return

		case .Matroska_FileName:
			/*
				Filename of the attached file.

				Described in Section 8.1.6.1.2 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_utf8(f, length, this) or_return

		case .Matroska_FileMimeType:
			/*
				MIME type of the file.

				Described in Section 8.1.6.1.3 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_utf8(f, length, this) or_return

		case .Matroska_FileData:
			/*
				The data of the file.

				Described in Section 8.1.6.1.4 of IETF draft-ietf-cellar-matroska-08
			*/
			skip_binary(f, length, this) or_return

		case .Matroska_FileUID:
			/*
				Unique ID representing the file, as random as possible.

				Described in Section 8.1.6.1.5 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return


		case .Matroska_Chapters:
			/*
				A system to define basic menus and partition data. For more detailed information,
				look at the Chapters explanation in Section 22.

				Described in Section 8.1.7 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type = .Master

		case .Matroska_EditionEntry:
			/*
				Contains all information about a Segment edition.

				Described in Section 8.1.7.1 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type = .Master

		case .Matroska_EditionUID:
			/*
				A unique ID to identify the edition. It's useful for tagging an edition.

				Described in Section 8.1.7.1.1 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_EditionFlagHidden:
			/*
				Set to 1 if an edition is hidden. Hidden editions **SHOULD NOT** be available to the user interface.

				Described in https://www.matroska.org/technical/elements.html
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_EditionFlagDefault:
			/*
				Set to 1 if the edition SHOULD be used as the default one.

				Described in Section 8.1.7.1.2 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_EditionFlagOrdered:
			/*
				Set to 1 if the chapters can be defined multiple times and the order to play them is enforced; see Section 22.1.3.

				Described in Section 8.1.7.1.3 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_ChapterAtom:
			/*
				Contains the atom information to use as the chapter atom (apply to all tracks).

				Described in Section 8.1.7.1.4 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type = .Master

		case .Matroska_ChapterUID:
			/*
				A unique ID to identify the Chapter.

				Described in Section 8.1.7.1.4.1 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_ChapterStringUID:
			/*
				A unique string ID to identify the Chapter. Use for WebVTT cue identifier storage [WebVTT].

				Described in Section 8.1.7.1.4.2 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_utf8(f, length, this) or_return

		case .Matroska_ChapterTimeStart:
			/*
				Timestamp of the start of Chapter (not scaled).

				Described in Section 8.1.7.1.4.3 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_ChapterTimeEnd:
			/*
				Timestamp of the end of Chapter (timestamp excluded, not scaled).
				The value MUST be strictly greater than the ChapterTimeStart of the same ChapterAtom.

				Described in Section 8.1.7.1.4.4 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_ChapterFlagHidden:
			/*
				Set to 1 if a chapter is hidden. Hidden chapters it SHOULD NOT be available to the user interface
				(but still to Control Tracks; see Section 22.2.3 on Chapter flags).

				Described in Section 8.1.7.1.4.5 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_ChapterFlagEnabled:
			/*
				Set to 1 if the chapter is enabled. It can be enabled/disabled by a Control Track.
				When disabled, the movie **SHOULD** skip all the content between the TimeStart and TimeEnd of this chapter;
				see notes on Chapter flags.

				Described in https://www.matroska.org/technical/elements.html
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_ChapterSegmentUID:
			/*
				The SegmentUID of another Segment to play during this chapter.

				Described in Section 8.1.7.1.4.6 of IETF draft-ietf-cellar-matroska-08
			*/
			skip_binary(f, length, this) or_return

		case .Matroska_ChapterSegmentEditionUID:
			/*
				The EditionUID to play from the Segment linked in ChapterSegmentUID.
				If ChapterSegmentEditionUID is undeclared, then no Edition of the linked Segment is used;
				see Section 19.2 on medium-linking Segments.

				Described in Section 8.1.7.1.4.7 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_ChapterPhysicalEquiv:
			/*
				Specify the physical equivalent of this ChapterAtom like "DVD" (60) or "SIDE" (50);
				see Section 22.4 for a complete list of values.

				Described in Section 8.1.7.1.4.8 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_ChapterDisplay:
			/*
				Contains all possible strings to use for the chapter display.

				Described in Section 8.1.7.1.4.9 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type = .Master

		case .Matroska_ChapString:
			/*
				Contains the string to use as the chapter atom.

				Described in Section 8.1.7.1.4.10 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_utf8(f, length, this) or_return

		case .Matroska_ChapLanguage:
			/*
				A language corresponding to the string, in the bibliographic ISO-639-2 form [ISO639-2].
				This Element MUST be ignored if a ChapLanguageIETF Element is used within the same ChapterDisplay Element.

				Described in Section 8.1.7.1.4.11 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_string(f, length, this) or_return

		case .Matroska_ChapLanguageIETF:
			/*
				Specifies a language corresponding to the ChapString in the format defined in [BCP47]
				and using the IANA Language Subtag Registry [IANALangRegistry].
				If a ChapLanguageIETF Element is used, then any ChapLanguage and ChapCountry Elements used in the same
				ChapterDisplay MUST be ignored.

				Described in Section 8.1.7.1.4.12 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_string(f, length, this) or_return

		case .Matroska_ChapCountry:
			/*
				A country corresponding to the string, using the same 2 octets country-codes as in Internet domains
				[IANADomains] based on [ISO3166-1] alpha-2 codes. This Element MUST be ignored if a ChapLanguageIETF
				Element is used within the same ChapterDisplay Element.

				Described in Section 8.1.7.1.4.13 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_string(f, length, this) or_return

		case .Matroska_ChapProcess:
			/*
				Contains all the commands associated to the Atom.

				Described in Section 8.1.7.1.4.14 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type = .Master

		case .Matroska_ChapProcessCodecID:
			/*
				Contains the type of the codec used for the processing. A value of 0 means native Matroska processing
				(to be defined), a value of 1 means the DVD command set is used; see Section 22.3 on DVD menus.
				More codec IDs can be added later.

				Described in Section 8.1.7.1.4.15 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_ChapProcessPrivate:
			/*
				Some optional data attached to the ChapProcessCodecID information. For ChapProcessCodecID = 1,
				it is the "DVD level" equivalent; see Section 22.3 on DVD menus.

				Described in Section 8.1.7.1.4.16 of IETF draft-ietf-cellar-matroska-08
			*/
			skip_binary(f, length, this) or_return

		case .Matroska_ChapProcessCommand:
			/*
				Contains all the commands associated to the Atom.

				Described in Section 8.1.7.1.4.17 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type = .Master

		case .Matroska_ChapProcessTime:
			/*
				Defines when the process command SHOULD be handled.

				Described in Section 8.1.7.1.4.18 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_ChapProcessData:
			/*
				Contains the command information. The data SHOULD be interpreted depending on the ChapProcessCodecID value.
				For ChapProcessCodecID = 1, the data correspond to the binary DVD cell pre/post commands;
				see Section 22.3 on DVD menus.

				Described in Section 8.1.7.1.4.19 of IETF draft-ietf-cellar-matroska-08
			*/
			skip_binary(f, length, this) or_return

		case .Matroska_Tags:
			/*
				Element containing metadata describing Tracks, Editions, Chapters, Attachments, or the Segment as a whole.
				A list of valid tags can be found in [MatroskaTags].

				Described in Section 8.1.8 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type = .Master

		case .Matroska_Tag:
			/*
				A single metadata descriptor.

				Described in Section 8.1.8.1 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type = .Master

		case .Matroska_Targets:
			/*
				Specifies which other elements the metadata represented by the Tag applies to.
				If empty or not present, then the Tag describes everything in the Segment.

				Described in Section 8.1.8.1.1 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type = .Master

		case .Matroska_TargetTypeValue:
			/*
				A number to indicate the logical level of the target.

				Described in Section 8.1.8.1.1.1 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_TargetType:
			/*
				An informational string that can be used to display the logical level of the target like
				"ALBUM", "TRACK", "MOVIE", "CHAPTER", etc ; see Section 6.4 of [MatroskaTags].

				Described in Section 8.1.8.1.1.2 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_string(f, length, this) or_return

		case .Matroska_TagTrackUID:
			/*
				A unique ID to identify the Track(s) the tags belong to.

				Described in Section 8.1.8.1.1.3 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_TagEditionUID:
			/*
				A unique ID to identify the EditionEntry(s) the tags belong to.

				Described in Section 8.1.8.1.1.4 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_TagChapterUID:
			/*
				A unique ID to identify the Chapter(s) the tags belong to.

				Described in Section 8.1.8.1.1.5 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_TagAttachmentUID:
			/*
				A unique ID to identify the Attachment(s) the tags belong to.

				Described in Section 8.1.8.1.1.6 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_SimpleTag:
			/*
				Contains general information about the target.

				Described in Section 8.1.8.1.2 of IETF draft-ietf-cellar-matroska-08
			*/
			this.type = .Master

		case .Matroska_TagName:
			/*
				The name of the Tag that is going to be stored.

				Described in Section 8.1.8.1.2.1 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_utf8(f, length, this) or_return

		case .Matroska_TagLanguage:
			/*
				Specifies the language of the tag specified, in the Matroska languages form; see Section 6 on language codes.
				This Element MUST be ignored if the TagLanguageIETF Element is used within the same SimpleTag Element.

				Described in Section 8.1.8.1.2.2 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_string(f, length, this) or_return

		case .Matroska_TagLanguageIETF:
			/*
				Specifies the language used in the TagString according to [BCP47] and using the IANA Language Subtag Registry
				[IANALangRegistry]. If this Element is used, then any TagLanguage Elements used in the same SimpleTag MUST be ignored.

				Described in Section 8.1.8.1.2.3 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_string(f, length, this) or_return

		case .Matroska_TagDefault:
			/*
				A boolean value to indicate if this is the default/original language to use for the given tag.

				Described in Section 8.1.8.1.2.4 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_uint(f, length, this) or_return

		case .Matroska_TagString:
			/*
				The value of the Tag.

				Described in Section 8.1.8.1.2.5 of IETF draft-ietf-cellar-matroska-08
			*/
			intern_utf8(f, length, this) or_return

		case .Matroska_TagBinary:
			/*
				The values of the Tag, if it is binary. Note that this cannot be used in the same SimpleTag as TagString.

				Described in Section 8.1.8.1.2.6 of IETF draft-ietf-cellar-matroska-08
			*/
			skip_binary(f, length, this) or_return


		case .Void:
			/*
				Contain positions for different tracks corresponding to the timestamp.

				Described in Section 11.3.2 of RFC 8794.
			*/
			skip_binary(f, length, this) or_return

		case:
			/*
				We don't know this payload or there is no payload (Void), seek to next.
			*/
			skip_binary(f, length, this) or_return
		}
		prev = this
	}

	return .None
}

parse :: proc(f: ^EBML_File, parse_metadata := true, skip_clusters := true, return_after_cluster := true) -> (err: Error) {
	context.allocator = f.allocator

	when DEBUG {
		println(0, "Parsing...")
		defer println(0, "Back from parsing...")
	}

	/*
		Read header.
	*/
	parse_header(f) or_return
	last_doc_idx := len(f.documents)
	assert(last_doc_idx >= 1)

	d := f.documents[last_doc_idx - 1]
	h := d.header

	verify_crc32(f, h) or_return

	/*
		Read body.
	*/
	document := f.documents[last_doc_idx - 1]

	switch document.doctype {
	case "matroska":
		/*
			Matroska parse.
		*/
		parse_matroska(f, document, skip_clusters, return_after_cluster) or_return

	case "webm":
		/*
			WebM parse.
		*/
		parse_matroska(f, document, skip_clusters, return_after_cluster) or_return

	case:
		/*
			Generic parse. Adds element nodes with their offset + length, default type and payload not interned.
		*/
		parse_generic_schema(f, document) or_return
	}

	if offset, offset_ok := common.get_pos(f.handle); !offset_ok {
		return .Read_Error
	} else {
		printf(0, "Done parsing at offset: %v\n", offset)
	}

	return .None
}

open_from_filename :: proc(filename: string, allocator := context.allocator) -> (file: ^EBML_File, err: Error) {
	context.allocator = allocator

	fd, os_err := os.open(filename, os.O_RDONLY, 0)
	if os_err == nil {
		return open_from_handle(fd, allocator)
	}
	return {}, .File_Not_Found
}

open_from_handle :: proc(handle: os.Handle, allocator := context.allocator) -> (file: ^EBML_File, err: Error) {
	context.allocator = allocator

	file = new(EBML_File, allocator)
	file.allocator = allocator
	file.handle    = handle

	os_err: os.Errno
	file.file_info, os_err = os.fstat(handle)

	if file.file_info.size == 0 || os_err != nil {
		when DEBUG {
			printf(0, "OS returned: %v\n", os_err)
		}
		close(file)
		return file, .File_Empty
	}
	return
}

open :: proc { open_from_filename, open_from_handle, }

free_element :: proc(element: ^EBML_Element, allocator := context.allocator) {
	element := element

	for element != nil {
		when DEBUG_VERBOSE >= 4 {
			printf(0, "Freeing '%v'.\n", _string(element.id))
		}

		if element.payload != nil {
			#partial switch v in element.payload {
			case [dynamic]u8: delete(v)
			case String: delete(string(v))
			case string: delete(v)
			case:
			}
		}

		if element.first_child != nil {
			free_element(element.first_child)
		}

		ptr_to_free := element
		element = element.next
		free(ptr_to_free)
	}
}

close :: proc(f: ^EBML_File) {
	if f == nil {
		return
	}

	context.allocator = f.allocator

	when DEBUG_VERBOSE >= 4 {
		println(0, "\n-=-=-=-=-=-=- CLEANING UP -=-=-=-=-=-=-")
		defer println(0, "-=-=-=-=-=-=- CLEANED UP -=-=-=-=-=-=-")
	}

	for document in f.documents {
		free_element(document.header)
		free_element(document.body)
		free(document)
	}

	delete(f.documents)

	os.file_info_delete(f.file_info)
	if f.handle != 0 {
		os.close(f.handle)
	}
	free(f)
}
