package minecraft

import "core:intrinsics"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:log"
import "core:mem"

SEPARATOR :: filepath.SEPARATOR

Region_Kind :: enum u8 {
	Invalid,
	Anvil,    // .mca
	Region,   // .mcr
}

Region_Offset :: struct #packed {
	sector_offset: [3]u8,
	sector_count:     u8,
}
Region_Timestamp :: u32be

Region_Chunk_Meta :: struct {
	offset:    i64,
	count:     i64,
	timestamp: i64,
}

NBT_Compression :: enum u8 {
	Invalid      = 0,
	GZIP         = 1,
	ZLIB         = 2,
	Uncompressed = 3,

	// External c.x.z.mcc file
	MCC_GZIP         = 129,
	MCC_ZLIB         = 130,
	MCC_Uncompressed = 131,
}

Chunk_Header :: struct #packed {
	size:        u32be,
	compression: NBT_Compression,
}

Region :: struct {
	path:       string,
	chunk_meta: [1024]Region_Chunk_Meta,
	raw:        []u8 `fmt:"-"`,

	coord:      Region_Coord,
	kind:       Region_Kind,
}

open_region_from_world :: proc(world: ^World, dimension: string, coord: World_Coord) -> (region: ^Region, err: Error) {
	return open_region(world, dimension, coordinates_to_region(coord))
}

open_region_from_block :: proc(world: ^World, dimension: string, coord: Block_Coord) -> (region: ^Region, err: Error) {
	return open_region(world, dimension, coordinates_to_region(coord))
}

open_region_from_chunk :: proc(world: ^World, dimension: string, coord: Chunk_Coord) -> (region: ^Region, err: Error) {
	return open_region(world, dimension, coordinates_to_region(coord))
}

open_region_from_region :: proc(world: ^World, dimension: string, coord: Region_Coord) -> (region: ^Region, err: Error) {
	if world == nil {
		return nil, .World_Not_Found
	}

	path_buf: [1024]u8
	b := strings.builder_from_bytes(path_buf[:])

	region = new(Region)
	region.kind = .Anvil

	for region.kind != .Invalid {
		strings.builder_reset(&b)
		strings.write_string(&b, world.path)
		if dimension != "" {
			strings.write_rune  (&b, SEPARATOR)
			strings.write_string(&b, dimension)
		}

		strings.write_rune  (&b, SEPARATOR)
		strings.write_string(&b, "region")
		strings.write_rune  (&b, SEPARATOR)
		strings.write_string(&b, "r.")
		strings.write_int   (&b, int(coord[0]))
		strings.write_rune  (&b, '.')
		strings.write_int   (&b, int(coord[1]))
		strings.write_rune  (&b, '.')

		#partial switch region.kind {
		case .Anvil:
			strings.write_string(&b, "mca")
			filename := strings.to_string(b)

			data, ok := os.read_entire_file(filename)
			if !ok {
				log.infof("Could not find Anvil file: %v", filename)
				region.kind = .Region
				continue
			}

			region.raw   = data
			region.coord = coord
			region.path  = strings.clone(filename)
			parse_region_header(region) or_return
			return

		case .Region:
			strings.write_string(&b, "mcr")
			filename := strings.to_string(b)

			data, ok := os.read_entire_file(filename)
			if !ok {
				log.infof("Could not find Region file: %v", filename)
				region.kind = .Invalid
				continue
			}

			region.raw   = data
			region.coord = coord
			region.path  = strings.clone(filename)
			parse_region_header(region) or_return
			return
		}
	}
	return region, .Region_File_Missing
}

parse_region_header :: proc(region: ^Region) -> (err: Error) {
	if region == nil {
		return .Region_File_Corrupt
	}

	if len(region.raw) < 8192 {
		return .Region_File_Corrupt
	}

	raw_offsets    := mem.slice_data_cast([]Region_Offset,    region.raw[:4096])
	raw_timestamps := mem.slice_data_cast([]Region_Timestamp, region.raw[4096:][:4096])

	for raw, i in raw_offsets {
		meta := Region_Chunk_Meta{
			offset    = 4096 * (i64(raw.sector_offset[0]) << 16 | i64(raw.sector_offset[1]) << 8 | i64(raw.sector_offset[2])),
			count     = i64(raw.sector_count),
			timestamp = i64(raw_timestamps[i]),
		}
		if meta.offset + 4096 * meta.count > i64(len(region.raw)) {
			return .Region_File_Corrupt
		}
		region.chunk_meta[i] = meta
	}
	return
}

get_chunk_from_region :: proc(region: ^Region, coord: Chunk_Coord) -> (chunk: NBT, err: Error) {
	if region == nil {
		return {}, .Region_File_Corrupt
	}

	if coordinates_to_region(coord) != region.coord {
		return {}, .Chunk_Not_In_Region
	}

	return get_chunk_from_chunk_idx(region, chunk_to_index(coord))
}

get_chunk_from_chunk_idx :: proc(region: ^Region, chunk_idx: i64) -> (chunk: NBT, err: Error) {
	if region == nil || chunk_idx < 0 || chunk_idx > 1023 {
		return {}, .Region_File_Corrupt
	}

	meta := region.chunk_meta[chunk_idx]

	if meta.offset + size_of(Chunk_Header) > i64(len(region.raw)) {
		return {}, .Region_File_Corrupt
	}
	chunk_hdr := peek(region.raw[meta.offset:], Chunk_Header) or_return

	if meta.offset + size_of(Chunk_Header) + i64(chunk_hdr.size) > i64(len(region.raw)) {
		return {}, .Region_File_Corrupt
	}
	return parse_nbt_from_slice(region.raw[meta.offset + 5:][:chunk_hdr.size], chunk_hdr.compression)
}

open_region :: proc {
	open_region_from_world,
	open_region_from_block,
	open_region_from_chunk,
	open_region_from_region,
}

destroy_region :: proc(region: ^Region) {
	if region == nil {
		return
	}
	delete(region.path)
	delete(region.raw)
	free(region)
}