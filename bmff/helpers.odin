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

	This file contains type conversion helpers.
*/

import "core:time"
import "../common"
import "base:runtime"
import "core:reflect"
import "core:fmt"

_string_common :: common._string

@thread_local PRINT_BUFFER: [512]u8

/*
	MPEG4 (ISO/IEC 14496) dates are in seconds since midnight, Jan. 1, 1904, in UTC time
*/
MPEG_YEAR :: -66
MPEG_TO_INTERNAL :: i64((MPEG_YEAR*365 + MPEG_YEAR/4 - MPEG_YEAR/100 + MPEG_YEAR/400 - 1) * time.SECONDS_PER_DAY)

_string :: proc(type: $T) -> (res: string) {
	when T == ISO_639_2 {
		buffer := PRINT_BUFFER[:]

		l := int(type)
		buffer[0] = u8(96 + (l >> 10)     )
		buffer[1] = u8(96 + (l >>  5) & 31)
		buffer[2] = u8(96 + (l      ) & 31)

		return string(buffer[:3])
	} else when T == FourCC {
		has_prefix :: proc(s, prefix: string) -> bool {
			return len(s) >= len(prefix) && s[0:len(prefix)] == prefix
		}

		if type == .Root {
			return "<ROOT>"
		}
		id := runtime.typeid_base(typeid_of(FourCC))
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
					if has_prefix(name, "iTunes") {
						buffer[6] = ':'
					}
					for v, i in name {
						if v == '_' {
							buffer[i] = ' '
						}
					}
					return name

				}
			}
		}

		temp := transmute([4]u8)type
		/*
			We could do `string(t[:4])`, but this also handles e.g. `©too`.
		*/
		if common.is_printable(temp[:]) {
			return fmt.bprintf(buffer[:], "%c%c%c%c 0x%08x", temp[0], temp[1], temp[2], temp[3], i64(type))
		} else {
			return fmt.bprintf(buffer[:], "0x%08x",          i64(type))
		}

	} else when T == UUID {
		return _string_common(type)
	} else {
		#panic("to_string: Unsupported type.")
	}
}

_f64 :: proc(fixed: $T) -> (res: f64) {
	when T == Fixed_16_16 {
		FRACT :: 16
		f := u32(fixed)

		res  = f64(f >> FRACT)
		res += f64(f & (1 << FRACT - 1)) / f64(1 << FRACT)
	} else when T == Fixed_2_30 {
		FRACT :: 30
		f := u32(fixed)

		res  = f64(f >> FRACT)
		res += f64(f & (1 << FRACT - 1)) / f64(1 << FRACT)
	} else when T == Fixed_8_8 {
		FRACT :: 8
		f := u16(fixed)

		res  = f64(f >> FRACT)
		res += f64(f & (1 << FRACT - 1)) / f64(1 << FRACT)
	} else {
		#panic("to_f64: Unsupported type.")
	}
	return
}

_time :: proc(seconds: $T) -> time.Time {
	return time.Time{(i64(seconds) + MPEG_TO_INTERNAL) * 1e9}
}

_matrix :: proc(mat: View_Matrix) -> (m: matrix[3, 3]f64) {
	m = matrix[3, 3]f64{
		_f64(mat.a), _f64(mat.b), _f64(mat.u),
		_f64(mat.c), _f64(mat.d), _f64(mat.v),
		_f64(mat.x), _f64(mat.y), _f64(mat.w),
	}
	return
}