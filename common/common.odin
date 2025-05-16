package file_format_common
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


	File format parser helpers.
*/

import "base:intrinsics"
import os "core:os/os2"

Error :: os.Error

SEEK_SET :: 0
SEEK_CUR :: 1
SEEK_END :: 2

get_pos :: proc(f: ^os.File) -> (pos: i64, err: Error) {
	p := os.seek(f, 0, .Current) or_return
	return p, nil
}

set_pos :: proc(f: ^os.File, pos: i64) -> (err: Error) {
	os.seek(f, pos, .Start) or_return
	return
}

@(optimization_mode="favor_size")
read_slice :: #force_inline proc(fd: ^os.File, size: $S, allocator := context.temp_allocator, loc := #caller_location) -> (res: []u8, err: Error) where intrinsics.type_is_integer(S) {
	res = make([]u8, int(size), allocator, loc=loc) or_return

	bytes_read, read_err := os.read(fd, res)
	if read_err != nil && read_err != .EOF {
		delete(res)
		return nil, .Unexpected_EOF
	}
	return res[:bytes_read], nil
}

@(optimization_mode="favor_size")
read_data :: #force_inline proc(fd: ^os.File, $T: typeid, allocator := context.temp_allocator, loc := #caller_location) -> (res: T, err: Error) {
	b := read_slice(fd, size_of(T), loc=loc) or_return

	return (^T)(raw_data(b))^, nil
}

@(optimization_mode="favor_size")
read_u8 :: #force_inline proc(fd: ^os.File, loc := #caller_location) -> (res: u8, err: Error) {
	b := read_slice(fd, 1, context.temp_allocator, loc=loc) or_return
	return b[0], nil
}

@(optimization_mode="favor_size")
peek_data :: #force_inline proc(fd: ^os.File, $T: typeid, loc := #caller_location) -> (res: T, err: Error) {
	cur := get_pos(fd)  or_return
	res  = read_data(fd, T, context.temp_allocator, loc=loc) or_return
	set_pos(fd, cur) or_return

	return res, nil
}

@(optimization_mode="favor_size")
peek_u8 :: #force_inline proc(fd: ^os.File, allocator := context.temp_allocator, loc := #caller_location) -> (res: u8, err: Error) {
	cur := get_pos(fd)  or_return
	res  = read_data(fd, u8, context.temp_allocator, loc=loc) or_return
	set_pos(fd, cur) or_return

	return res, nil
}