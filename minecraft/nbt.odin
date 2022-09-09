/*
	Copyright 2022 Jeroen van Rijn <nom@duclavier.com>.

	Made available under Odin's BSD-3 license.

	A from-scratch implementation of the Minecraft NBT format and associated helpers.
	Very work-in-progress, but it works with MC 1.19.2 data.
*/
package minecraft

import "core:os"
import "core:compress/gzip"
import "core:compress/zlib"
import "core:bytes"
import "core:log"

NBT :: struct {
	root: NBT_Tag,
	raw:  []u8 `fmt:"-"`,
}

NBT_Tag :: struct #packed {
	name:    string,
	value:   NBT_Tag_Value,
}

NBT_Tag_Value :: union {
	i8,
	i16,
	i32,
	i64,
	f32,
	f64,
	[]i8,
	string,
	NBT_List,
	NBT_Compound,
	[]i32,
	[]i64,
}

NBT_List :: struct {
	tag:   Tag_Id,
	value: []NBT_Tag_Value,
}

NBT_Compound :: []NBT_Tag

NBT_Tag_Raw :: struct #packed {
	tag:          Tag_Id,
	name_len:     u16be,
}

Tag_Id :: enum u8 {
	End        =  0, // zero-length end of compound tag, or empty list
	Byte       =  1, // i8
	Short      =  2, // i16be
	Int        =  3, // i32be
	Long       =  4, // i64be,
	Float      =  5, // f32be,
	Double     =  6, // f64be,
	Byte_Array =  7, // Int payload size, then payload
	String     =  8, // u16be size, followed by UTF-8 data
	List       =  9, // Byte payload type, Int payload size, payload
	Compound   = 10, // A list of tags followed by End, must have unique names
	Int_Array  = 11, // Int payload size, Int payloads
	Long_Array = 12, // Int payload size, Long payloads
}

NBT_Error :: enum {
	None,
	Unpack_Error,
	EOF,
	Unrecognized_Tag_Id,
	Unhandled_Compression,
}

parse_nbt_from_path :: proc(nbt_path: string, compression: NBT_Compression) -> (root: NBT, err: Error) {
	raw_data, ok := os.read_entire_file(nbt_path)
	if !ok {
		log.errorf("Unable to read %v", nbt_path)
		return root, .Path_Not_Found
	}
	defer delete(raw_data)

	return parse_nbt_from_slice(raw_data, compression)
}

parse_nbt_from_slice :: proc(raw_data: []u8, compression: NBT_Compression) -> (root: NBT, err: Error) {
	#partial switch compression {
	case .GZIP:
		buf: bytes.Buffer
		if gzip_err := gzip.load(raw_data, &buf); gzip_err != nil {
			bytes.buffer_destroy(&buf)
			log.errorf("Unpacking NBT w/ GZIP returned %v", gzip_err)
			return root, .Unpack_Error
		}
		shrink(&buf.buf)
		root.raw = buf.buf[:]

	case .ZLIB:
		buf: bytes.Buffer
		if zlib_err := zlib.inflate(raw_data, &buf); zlib_err != nil {
			bytes.buffer_destroy(&buf)
			log.errorf("Unpacking NBT w/ ZLIB returned %v", zlib_err)
			return root, .Unpack_Error
		}
		shrink(&buf.buf)
		root.raw = buf.buf[:]

	case .Uncompressed:
		root.raw = make([]u8, len(raw_data))
		copy(root.raw, raw_data)

	case:
		return {}, .Unhandled_Compression
	}

	raw := root.raw
	root.root = parse_nbt_tag(&raw) or_return
	return
}

get_value_by_name :: proc(tag: NBT_Tag, name: []string) -> (res: NBT_Tag_Value, ok: bool) {
	// If there's nothing to match, we're done.
	if len(name) == 0 {
		return {}, false
	}

	// If the (partial) name doesn't match, we're done.
	if tag.name != name[0] {
		return {}, false
	}

	// The name matches and we're the last piece to match, we're done.
	if len(name) == 1 {
		return tag.value, true
	}

	// If we're not the last piece but the current piece is a compound,
	// we might still be able to find the item.
	if c, c_ok := tag.value.(NBT_Compound); c_ok {
		for t in c {
			if res, ok = get_value_by_name(t, name[1:]); ok {
				return res, ok
			}
		}
	}

	// It wasn't a compound.
	return {}, false
}


read_byte :: proc(data: ^[]u8) -> (val: i8, err: Error) {
	return #force_inline read(data, i8)
}

read_short :: proc(data: ^[]u8) -> (val: i16, err: Error) {
	v := #force_inline read(data, i16be) or_return
	return i16(v), nil
}

read_int :: proc(data: ^[]u8) -> (val: i32, err: Error) {
	v := #force_inline read(data, i32be) or_return
	return i32(v), nil
}

read_long :: proc(data: ^[]u8) -> (val: i64, err: Error) {
	v := #force_inline read(data, i64be) or_return
	return i64(v), nil
}

read_float :: proc(data: ^[]u8) -> (val: f32, err: Error) {
	v := #force_inline read(data, f32be) or_return
	return f32(v), nil
}

read_double :: proc(data: ^[]u8) -> (val: f64, err: Error) {
	v := #force_inline read(data, f64be) or_return
	return f64(v), nil
}

read_byte_array :: proc(data: ^[]u8) -> (val: []i8, err: Error) {
	array_count := read(data, i32be)  or_return

	// TODO optimize by just making it a slice into the raw data
	val = make([]i8, array_count)
	for i in 1..=array_count {
		val[i - 1] = read(data, i8) or_return
	}
	return
}

read_int_array :: proc(data: ^[]u8) -> (val: []i32, err: Error) {
	array_count := read(data, i32be)  or_return

	// TODO optimize by just making it a slice into the raw data
	val = make([]i32, array_count)
	for i in 1..=array_count {
		v := read(data, i32be) or_return
		val[i - 1] = i32(v)
	}
	return
}

read_long_array :: proc(data: ^[]u8) -> (val: []i64, err: Error) {
	array_count := read(data, i32be)  or_return

	// TODO optimize by just making it a slice into the raw data
	val = make([]i64, array_count)
	for i in 1..=array_count {
		v := read(data, i64be) or_return
		val[i - 1] = i64(v)
	}
	return
}


parse_nbt_tag :: proc(data: ^[]u8, level := 0) -> (tag: NBT_Tag, err: Error) {
	assert(data != nil)

	tag_id := read(data, Tag_Id) or_return
	if tag_id == .End {
		return {}, nil
	}
	tag.name = read_string(data) or_return

	switch tag_id {
	case .End:
	case .Byte:       tag.value = read_byte(data)                or_return
 	case .Short:      tag.value = read_short(data)               or_return
	case .Int:        tag.value = read_int(data)                 or_return
	case .Long:       tag.value = read_long(data)                or_return
	case .Float:      tag.value = read_float(data)               or_return
	case .Double:     tag.value = read_double(data)              or_return
	case .Byte_Array: tag.value = read_byte_array(data)          or_return
	case .String:     tag.value = read_string(data)              or_return
	case .List:       tag.value = read_list(data,     level + 1) or_return
	case .Compound:   tag.value = read_compound(data, level + 1) or_return
	case .Int_Array:  tag.value = read_int_array(data)           or_return
	case .Long_Array: tag.value = read_long_array(data)          or_return
	case:
		return {}, .Unrecognized_Tag_Id
	}
	return
}

read_list :: proc(data: ^[]u8, level := 0) -> (res: NBT_List, err: Error) {
	list_tag_kind   := read(data, Tag_Id) or_return
	list_item_count := read(data, i32be)  or_return

	res = NBT_List{
		tag   = list_tag_kind,
		value = make([]NBT_Tag_Value, list_item_count),
	}

	for i in 1..=list_item_count {
		switch list_tag_kind {
		case .End:        // Empty list
		case .Byte:       res.value[i - 1] = read_byte(data)                or_return
		case .Short:      res.value[i - 1] = read_short(data)               or_return
		case .Int:        res.value[i - 1] = read_int(data)                 or_return
		case .Long:       res.value[i - 1] = read_long(data)                or_return
		case .Float:      res.value[i - 1] = read_float(data)               or_return
		case .Double:     res.value[i - 1] = read_double(data)              or_return
		case .Byte_Array: res.value[i - 1] = read_byte_array(data)          or_return
		case .String:     res.value[i - 1] = read_string(data)              or_return
		case .List:       res.value[i - 1] = read_list(data,     level + 1) or_return
		case .Compound:   res.value[i - 1] = read_compound(data, level + 1) or_return
		case .Int_Array:  res.value[i - 1] = read_int_array(data)           or_return
		case .Long_Array: res.value[i - 1] = read_long_array(data)          or_return
		case: return res, .Unrecognized_Tag_Id
		}
	}
	return
}

read_compound :: proc(data: ^[]u8, level := 0) -> (res: NBT_Compound, err: Error) {
	values: [dynamic]NBT_Tag
	for {
		child_tag, child_err := parse_nbt_tag(data, level + 1)
		if child_err != nil {
			delete(values)
			return {}, child_err
		} else if child_tag.value == nil { // .End
			break
		}
		append(&values, child_tag)
	}
	return values[:], nil
}


read :: proc(data: ^[]u8, $T: typeid) -> (res: T, err: Error) {
	if size_of(T) > len(data) {
		return {}, .EOF
	}
	res   = (transmute(^T)(raw_data(data^)))^
	data^ = data[size_of(T):]
	return
}

peek :: proc(data: []u8, $T: typeid) -> (res: T, err: Error) {
	data := data

	if size_of(T) > len(data) {
		return {}, .EOF
	}
	res   = (transmute(^T)(raw_data(data)))^
	return
}

read_string :: proc(data: ^[]u8, #any_int name_len: int = -1) -> (res: string, err: Error) {
	name_len := name_len
	if name_len == -1 {
		// Read from data
		nl := read(data, u16be) or_return
		name_len = int(nl)
	}

	if name_len > len(data) {
		return {}, .EOF
	}
	res = string(data[:name_len])
	data^ = data[name_len:]
	return
}

destroy_nbt :: proc(root: NBT) {
	delete(root.raw)
	destroy_nbt_tag(root.root.value)
}

destroy_nbt_tag :: proc(tag: NBT_Tag_Value) {
	#partial switch v in tag {
	case []i8:
		delete(v)
	case NBT_List:
		for item in v.value {
			destroy_nbt_tag(item)
		}
		delete(v.value)

	case NBT_Compound:
		for item in v {
			destroy_nbt_tag(item.value)
		}
		delete(tag.(NBT_Compound))

	case []i32:
		delete(v)

	case []i64:
		delete(v)
	}
}