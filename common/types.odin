package file_format_common

import "core:fmt"

@thread_local PRINT_BUFFER: [512]u8

bprintf :: fmt.bprintf

/*
	UUIDs are compliant with RFC 4122: A Universally Unique IDentifier (UUID) URN Namespace
	                         (https://www.rfc-editor.org/rfc/rfc4122.html)
*/
UUID_RFC_4122 :: struct {
	time_low:                u32be,
	time_mid:                u16be,
	time_hi_and_version:     u16be,
	clk_seq_hi_and_reserved: u8,
	clk_seq_low:             u8,
	node:                    [6]u8,
}
#assert(size_of(UUID_RFC_4122) == 16)

FourCC :: distinct u32be

_string :: proc(type: $T) -> (res: string) {
	/* 6ba7b810-9dad-11d1-80b4-00c04fd430c8 */

	when T == UUID_RFC_4122 {
		buffer := PRINT_BUFFER[:]
		using type
		return bprintf(
			buffer[:], "%06x-%02x-%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
			time_low,
			time_mid,
			time_hi_and_version,
			clk_seq_hi_and_reserved,
			clk_seq_low,
			node[0], node[1], node[2], node[3], node[4], node[5],
		)
	} else when T == FourCC {
		buffer := PRINT_BUFFER[:]

		temp := transmute([4]u8)type
		/*
			We could do `string(t[:4])`, but this also handles e.g. `©too`.
		*/
		if is_printable(temp[:]) {
			return fmt.bprintf(buffer[:], "%c%c%c%c",           temp[0], temp[1], temp[2], temp[3])
		} else {
			return fmt.bprintf(buffer[:], "0x%02x%02x%02x%02x", temp[0], temp[1], temp[2], temp[3])
		}

	} else {
		#panic("to_string: Unsupported type.")
	}
}

is_printable :: proc(buf: []u8) -> (printable: bool) {
	printable = true
	for r in buf {
		switch r {
		case '\r', '\n', '\t':
			continue
		case 0x00..=0x19:
			return false
		case 0x20..=0x7e:
			continue
		case 0x7f..=0xa0:
			return false
		case 0xa1..=0xff: // ¡ through ÿ except for the soft hyphen
			if r == 0xad {
				return false
			}
		}
	}
	return
}