package iso_bmff
/*
	Copyright 2021 Jeroen van Rijn <nom@duclavier.com>.
	Made available under Odin's BSD-3 license.

	A from-scratch implementation of ISO base media file format (ISOM),
	as specified in ISO/IEC 14496-12, Fifth edition 2015-12-15.
	The identical text is available as ISO/IEC 15444-12 (JPEG 2000, Part 12).

	See: https://www.iso.org/standard/68960.html and https://www.loc.gov/preservation/digital/formats/fdd/fdd000079.shtml

	This file contains type conversion helpers.
*/

import "core:time"
import "../common"

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
		if type == ._file_root {
			return "_file_root"
		}
		return _string_common(common.FourCC(type))
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
	using mat
	m = matrix[3, 3]f64{
		_f64(a), _f64(b), _f64(u),
		_f64(c), _f64(d), _f64(v),
		_f64(x), _f64(y), _f64(w),
	}
	return
}