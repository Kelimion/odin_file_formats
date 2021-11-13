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

_string :: proc(t: $T) -> (res: string) {
	buffer := PRINT_BUFFER[:]

	/* 6ba7b810-9dad-11d1-80b4-00c04fd430c8 */

	when T == UUID_RFC_4122 {
		using t
		return bprintf(
			buffer[:], "%06x-%02x-%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
			time_low,
			time_mid,
			time_hi_and_version,
			clk_seq_hi_and_reserved,
			clk_seq_low,
			node[0], node[1], node[2], node[3], node[4], node[5],
		)

	} else {
		#panic("to_string: Unsupported type.")
	}
}