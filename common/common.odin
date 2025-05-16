package file_format_common
/*
	Copyright 2021 Jeroen van Rijn <nom@duclavier.com>.
	Made available under Odin's BSD-3 license.

	File format parser helpers.
*/

import "base:intrinsics"
import "core:os"

SEEK_SET :: 0
SEEK_CUR :: 1
SEEK_END :: 2

Handle :: os.Handle

get_pos :: proc(f: Handle) -> (pos: i64, ok: bool) {
	if p, e := os.seek(f, 0, SEEK_CUR); e == 0 {
		return p, true
	}
	return 0, false
}

set_pos :: proc(f: Handle, pos: i64) -> (ok: bool) {
	if _, e := os.seek(f, pos, SEEK_SET); e == 0 {
		return true
	}
	return false
}

size :: proc(f: Handle) -> (res: i64, ok: bool) {
	cur, end: i64
	err: os.Errno

	// Remember current position
	if cur, ok = get_pos(f); !ok { return 0, ok }

	if cur != 0 {
		// Rewind
		if ok = set_pos(f, 0); !ok { return 0, ok }
	}
	// Seek to end
	if end, err = os.seek(f, 0, SEEK_END); err != 0 { return 0, false }

	// Restore original position
	if ok = set_pos(f, cur); !ok { return 0, ok }

	return end, true
}

@(optimization_mode="favor_size")
read_slice :: #force_inline proc(fd: Handle, size: $S, allocator := context.temp_allocator) -> (res: []u8, ok: bool) where intrinsics.type_is_integer(S) {

    res = make([]u8, int(size), allocator)
    if res == nil {
        return nil, false
    }

    bytes_read, read_err := os.read(fd, res)
    if read_err != os.ERROR_NONE {
        delete(res)
        return nil, false
    }
    return res[:bytes_read], true
}

@(optimization_mode="favor_size")
read_data :: #force_inline proc(fd: Handle, $T: typeid, allocator := context.temp_allocator) -> (res: T, ok: bool) {
	b, e := read_slice(fd, size_of(T))

	if e {
		return (^T)(raw_data(b))^, e
	}

	return T{}, false
}

@(optimization_mode="favor_size")
read_u8 :: #force_inline proc(fd: Handle) -> (res: u8, ok: bool) {
	b, e := read_slice(fd, 1, context.temp_allocator)
	if e {
		return b[0], e
	}
	return 0, e
}

@(optimization_mode="favor_size")
peek_data :: #force_inline proc(fd: Handle, $T: typeid) -> (res: T, ok: bool) {

	cur: i64
	errno: os.Errno

	// Remember current position
	if cur, errno = os.seek(fd, 0, SEEK_CUR); errno != 0 { return {}, false }

	res, ok = read_data(fd, T, context.temp_allocator)

	if _, errno = os.seek(fd, cur, SEEK_SET); errno != 0 { return {}, false }

	return res, ok
}

@(optimization_mode="favor_size")
peek_u8 :: #force_inline proc(fd: Handle, allocator := context.temp_allocator) -> (res: u8, ok: bool) {

	cur: i64
	errno: os.Errno

	// Remember current position
	if cur, errno = os.seek(fd, 0, SEEK_CUR); errno != 0 { return {}, false }

	res, ok = read_data(fd, u8, allocator)

	if _, errno = os.seek(fd, cur, SEEK_SET); errno != 0 { return {}, false }

	return res, ok
}