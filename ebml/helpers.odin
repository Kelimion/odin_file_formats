package ebml
/*
	Copyright 2021 Jeroen van Rijn <nom@duclavier.com>.
	Made available under Odin's BSD-3 license.

	A from-scratch implementation of the Extensible Binary Meta Language (EBML),
	as specified in [IETF RFC 8794](https://www.rfc-editor.org/rfc/rfc8794).

	The EBML format is the base format upon which Matroska (MKV) and WebM are based.

	This file contains the EBML type helpers.
*/

import "core:intrinsics"
import "core:runtime"
import "core:reflect"
import "core:time"
import "core:hash"

import "core:fmt"
import "../common"

CRC_BLOCK_SIZE :: 4096

clz :: intrinsics.count_leading_zeros

@thread_local PRINT_BUFFER: [512]u8

read_variable_id :: proc(f: ^EBML_File) -> (res: EBML_ID, length: u8, err: Error) {
	assert(f != nil)

	b0:   u8
	ok:   bool
	data: []u8

	if b0, ok = common.read_u8(f.handle); !ok { return {}, 0, .Read_Error }

	length = clz(b0) + 1
	val   := u64be(b0)

	if length == 1 { return EBML_ID(val), 1, .None }
	if data, ok = common.read_slice(f.handle, length - 1); !ok { return {}, 0, .Read_Error }

	for v in data {
		val <<= 8
		val |=  u64be(v)
	}
	return EBML_ID(val), length, .None
}

read_variable_int :: proc(f: ^EBML_File) -> (res: u64, length: u8, err: Error) {
	assert(f != nil)

	b0:   u8
	ok:   bool
	data: []u8

	if b0, ok = common.read_u8(f.handle); !ok { return {}, 0, .Read_Error }

	length = clz(b0) + 1
	res    = u64(b0)

	if length == 1 { return res & 0x7f, 1, .None }

	if data, ok = common.read_slice(f.handle, length - 1); !ok { return {}, 0, .Read_Error }

	for v in data {
		res <<= 8
		res |=  u64(v)
	}
	return res & ((1 << (length * 7) - 1)), length, .None
}

_read_uint :: proc(f: ^EBML_File, length: u64) -> (res: u64, err: Error) {
	assert(f != nil)

	b0:   u8
	ok:   bool
	data: []u8

	switch length {
	case 0:
		return 0, .None

	case 1:
		if b0, ok = common.read_u8(f.handle); !ok              { return {}, .Read_Error }
		return u64(b0), .None

	case 2..8:
		if data, ok = common.read_slice(f.handle, length); !ok { return {}, .Read_Error }

		for v in data {
			res <<= 8
			res |=  u64(v)
		}
		return res, .None

	case:
		return 0, .Unsigned_Invalid_Length
	}
}

intern_uint :: proc(f: ^EBML_File, length: u64, this: ^EBML_Element) -> (err: Error) {
	assert(f != nil && this != nil)

	this.type        = .Unsigned
	this.payload     = _read_uint(f, length) or_return

	return .None
}

_read_sint :: proc(f: ^EBML_File, length: u64) -> (res: i64, err: Error) {
	assert(f != nil)

	switch length {
	case 0:
		return 0, .None

	case 1..8:
		if data, ok := common.read_slice(f.handle, length); !ok {
			return 0, .Read_Error
		} else {
			res = 0
			if data[0] & 0x80 == 0x80 {
				res = -1
			}

			for v in data {
				res <<= 8
				res |=  i64(v)
			}
			return res, .None
		}

	case:
		return 0, .Signed_Invalid_Length
	}
}

intern_sint :: proc(f: ^EBML_File, length: u64, this: ^EBML_Element) -> (err: Error) {
	assert(f != nil && this != nil)

	this.type        = .Signed
	this.payload     = _read_sint(f, length) or_return

	return .None
}

_read_float :: proc(f: ^EBML_File, length: u64) -> (res: f64, err: Error) {
	assert(f != nil)

	switch length {
	case 0:
		return 0.0, .None

	case 4:
		if f, ok := common.read_data(f.handle, f32be); ok {
			return f64(f), .None
		}
		return 0.0, .Float_Invalid_Length

	case 8:
		if f, ok := common.read_data(f.handle, f64be); ok {
			return f64(f), .None
		}
		return 0.0, .Float_Invalid_Length

	case:
		return 0.0, .Float_Invalid_Length
	}
}

intern_float :: proc(f: ^EBML_File, length: u64, this: ^EBML_Element) -> (err: Error) {
	assert(f != nil && this != nil)

	this.type        = .Float
	this.payload     = _read_float(f, length) or_return

	return .None
}

read_string :: proc(f: ^EBML_File, length: u64, utf8 := false) -> (res: String, err: Error) {
	assert(f != nil)

	if data, ok := common.read_slice(f.handle, length, f.allocator); !ok {
		return "", .Read_Error
	} else {
		for ch, i in data {
			printable, terminator := is_printable(ch)

			if terminator {
				data = data[:i]
				break
			}

			if !printable && !utf8 {
				delete(data)
				return "", .Unprintable_String
			}
		}
		return String(data), .None
	}
}

intern_string :: proc(f: ^EBML_File, length: u64, this: ^EBML_Element) -> (err: Error) {
	assert(f != nil && this != nil)

	this.type    = .String
	this.payload = read_string(f, length) or_return

	return .None
}

read_utf8 :: proc(f: ^EBML_File, length: u64) -> (res: string, err: Error) {
	s, e := read_string(f, length, true)

	return string(s), e
}

intern_utf8 :: proc(f: ^EBML_File, length: u64, this: ^EBML_Element) -> (err: Error) {
	assert(f != nil && this != nil)

	this.type    = .UTF_8
	this.payload = read_utf8(f, length) or_return

	return .None
}

skip_binary :: proc(f: ^EBML_File, length: u64, this: ^EBML_Element) -> (err: Error) {
	this.type = .Binary
	if !common.set_pos(f.handle, this.end + 1) { return .Read_Error }
	return
}

intern_binary :: proc(f: ^EBML_File, length: u64, this: ^EBML_Element) -> (err: Error) {
	this.type        = .Binary
	this.payload     = [dynamic]u8{}

	if payload, payload_ok := common.read_slice(f.handle, length); !payload_ok {
		return .Read_Error
	} else {
		append(&this.payload.([dynamic]u8), ..payload)
	}

	return .None
}


verify_crc32 :: proc(f: ^EBML_File, element: ^EBML_Element) -> (err: Error) {
	if f == nil || element == nil {
		/*
			Return false if given a bogus element.
		*/
		return .Invalid_CRC
	}

	if element.first_child == nil || element.first_child.id != .CRC_32 {
		/*
			This element doesn't have a CRC-32 check, so consider it verified.
		*/
		return .None
	}

	if checksum, checksum_ok := element.first_child.payload.(u64); !checksum_ok {
		/*
			A CRC-32 payload always has to be the first element, per the spec.
		*/
		return .Invalid_CRC
	} else {
		if cur_pos, cur_ok := common.get_pos(f.handle); cur_ok {

			start := element.first_child.end + 1
			end   := element.end             + 1

			if !common.set_pos(f.handle, start)   { return .Read_Error }

			size := end - start
			computed_crc: u32

			for size > 0 {
				block_size     := min(size, CRC_BLOCK_SIZE)

				data, data_ok  := common.read_slice(f.handle, block_size)
				computed_crc    = hash.crc32(data, computed_crc)
				cur_pos, cur_ok = common.get_pos(f.handle)

				size -= block_size
			}

			when DEBUG {
				printf(0, "CRC_32 Expected: %08x, Computed: %08x.\n", checksum, computed_crc)	
			}

			if u64(computed_crc) != checksum      { return .Invalid_CRC }

			/*
				Restore original seek head.
			*/
			if !common.set_pos(f.handle, cur_pos) { return .Read_Error }

			/*
				CRC32 matched.
			*/
			return .None
		}
	}
	return .Invalid_CRC
}

MATROSKA_TO_INTERNAL :: 978_307_200_000_000_000

nanoseconds_to_time :: proc(nanoseconds: i64) -> (res: time.Time) {
	return time.Time{ MATROSKA_TO_INTERNAL + nanoseconds }
}

is_printable :: #force_inline proc(ch: u8) -> (printable: bool, terminator: bool) {
	switch ch {
	case 0x20..0x7E:
		return true, false
	case 0x00:
		// Terminator
		return true, true
	case:
		// Unprintable
		return false, false
	}
}

_string :: proc(type: $T) -> (res: string) {
	when T == EBML_ID {
		has_prefix :: proc(s, prefix: string) -> bool {
			return len(s) >= len(prefix) && s[0:len(prefix)] == prefix
		}

		id := runtime.typeid_base(typeid_of(EBML_ID))
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
					for v, i in name {
						if v == '_' {
							buffer[i] = ' '
						}
					}
					return name

				}
			}
		}

		temp := transmute([8]u8)type
		/*
			We could do `string(t[:4])`, but this also handles e.g. `©too`.
		*/
		if common.is_printable(temp[:]) {
			return fmt.bprintf(buffer[:], "%c%c%c%c 0x%08x", temp[0], temp[1], temp[2], temp[3], i64(type))
		} else {
			return fmt.bprintf(buffer[:], "0x%08x",          i64(type))
		}

	} else when T == time.Time {
		buffer := PRINT_BUFFER[:]
		return fmt.bprintf(buffer[:], "%v", type)

	} else {
		#panic("to_string: Unsupported type.")
	}
}