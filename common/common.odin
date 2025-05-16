package file_format_common
/*
	Copyright 2021 Jeroen van Rijn <nom@duclavier.com>.
	Made available under Odin's BSD-3 license.

	File format parser helpers.
*/

import "base:intrinsics"
import "core:os"
import "core:fmt"

SEEK_SET :: 0
SEEK_CUR :: 1
SEEK_END :: 2

get_pos :: proc(f: os.Handle) -> (pos: i64, ok: bool) {
	if p, e := os.seek(f, 0, os.SEEK_CUR); e == nil {
		return p, true
	}
	return 0, false
}

set_pos :: proc(f: os.Handle, pos: i64) -> (ok: bool) {
	if _, e := os.seek(f, pos, os.SEEK_SET); e == nil {
		return true
	}
	return false
}

size :: proc(f: os.Handle) -> (res: i64, ok: bool) {
	cur, end: i64
	err: os.Errno

	// Remember current position
	if cur, ok = get_pos(f); !ok { return 0, ok }

	if cur != 0 {
		// Rewind
		if ok = set_pos(f, 0); !ok { return 0, ok }
	}
	// Seek to end
	if end, err = os.seek(f, 0, os.SEEK_END); err != nil { return 0, false }

	// Restore original position
	if ok = set_pos(f, cur); !ok { return 0, ok }

	return end, true
}

@(optimization_mode="favor_size")
read_slice :: #force_inline proc(fd: os.Handle, size: $S, allocator := context.temp_allocator, loc := #caller_location) -> (res: []u8, ok: bool) where intrinsics.type_is_integer(S) {
	res = make([]u8, int(size), allocator, loc=loc)
	if res == nil {
		return nil, false
	}

	bytes_read, read_err := os.read(fd, res)
	if read_err != os.ERROR_NONE && read_err != os.ERROR_EOF {
		fmt.printfln("read_err: %v", read_err)
		delete(res)
		return nil, false
	}
	return res[:bytes_read], true
}

@(optimization_mode="favor_size")
read_data :: #force_inline proc(fd: os.Handle, $T: typeid, allocator := context.temp_allocator, loc := #caller_location) -> (res: T, ok: bool) {
	b, e := read_slice(fd, size_of(T), loc=loc)

	if e {
		return (^T)(raw_data(b))^, e
	}

	return T{}, false
}

@(optimization_mode="favor_size")
read_u8 :: #force_inline proc(fd: os.Handle, loc := #caller_location) -> (res: u8, ok: bool) {
	b, e := read_slice(fd, 1, context.temp_allocator, loc=loc)
	if e {
		return b[0], e
	}
	return 0, e
}

@(optimization_mode="favor_size")
peek_data :: #force_inline proc(fd: os.Handle, $T: typeid, loc := #caller_location) -> (res: T, ok: bool) {

	cur: i64
	errno: os.Errno

	// Remember current position
	if cur, errno = os.seek(fd, 0, os.SEEK_CUR); errno != nil { return {}, false }

	res, ok = read_data(fd, T, context.temp_allocator, loc=loc)

	if _, errno = os.seek(fd, cur, os.SEEK_SET); errno != nil { return {}, false }

	return res, ok
}

@(optimization_mode="favor_size")
peek_u8 :: #force_inline proc(fd: os.Handle, allocator := context.temp_allocator, loc := #caller_location) -> (res: u8, ok: bool) {

	cur: i64
	errno: os.Errno

	// Remember current position
	if cur, errno = os.seek(fd, 0, os.SEEK_CUR); errno != nil { return {}, false }

	res, ok = read_data(fd, u8, allocator, loc=loc)

	if _, errno = os.seek(fd, cur, os.SEEK_SET); errno != nil { return {}, false }

	return res, ok
}