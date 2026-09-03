package src.cmd.link.internal.ld

import (
	"src/fmt"
	"src/crypto/sha256"
	"src/encoding/binary"
)

enum build_id_type {
	bid_uuid = 0
	bid_md5 = 1
	bid_sha1 = 2
	bid_sha256 = 3
}

struct build_id_manager {
	type    build_id_type
	id u8[]
	version string
}

func new_build_id_manager(t build_id_type) build_id_manager {
	build_id_manager{
		type: t,
		id: make(u8[], 0),
		version: "1.0",
	}
}

func (bim build_id_manager*) generate_build_id(data u8[]) {
	
	hash := sha256.Sum256(data)
	bim.id = make(u8[], len(hash))
	for i, b := range hash {
		bim.id[i] = b
	}
}

func (bim build_id_manager*) get_build_id_string() string {
	s := ""
	for _, b := range bim.id {
		s = fmt.Sprintf("%s%02x", s, b)
	}
	s
}

func (bim build_id_manager*) generate_note_section() u8[] {
	data := make(u8[], 0)

	
	
	
	
	
	

	name := "GNU"
	namesz := i32(len(name) + 1)
	descsz := i32(len(bim.id))

	
	aligned_namesz := (namesz + 3) & ^3
	aligned_descsz := (descsz + 3) & ^3

	
	binary.LittleEndian.PutUint32(data[0:4], u32(namesz))
	data = append(data, 0, 0, 0, 0)

	
	binary.LittleEndian.PutUint32(data[4:8], u32(descsz))
	data = append(data, 0, 0, 0, 0)

	
	binary.LittleEndian.PutUint32(data[8:12], 3)
	data = append(data, 0, 0, 0, 0)

	
	data = append(data, u8[](name)...)
	data = append(data, 0)

	
	for i := namesz; i < aligned_namesz; i += 1 {
		data = append(data, 0)
	}

	
	data = append(data, bim.id...)

	
	for i := descsz; i < aligned_descsz; i += 1 {
		data = append(data, 0)
	}

	data
}

struct got_manager {
	entries got_entry[]
	offset  i64
}

struct got_entry {
	symbol_index i32
	reloc_type   reloc_type
	address     i64
	value       i64
	is_resolved  bool
}

func new_got_manager() got_manager {
	got_manager{
		entries: make(got_entry[], 0),
		offset: 0,
	}
}

func (gm got_manager*) add_entry(sym_idx i32, reloc_type reloc_type) i64 {
	entry := got_entry{
		symbol_index: sym_idx,
		reloc_type: reloc_type,
		address: gm.offset,
		value: 0,
		is_resolved: false,
	}

	gm.entries = append(gm.entries, entry)
	idx := gm.offset
	gm.offset += 8 

	idx
}

func (gm got_manager*) lookup_or_create(sym_idx i32, reloc_type reloc_type) i64 {
	
	for _, entry := range gm.entries {
		if entry.symbol_index == sym_idx && entry.reloc_type == reloc_type {
			entry.address
		}
	}

	
	gm.add_entry(sym_idx, reloc_type)
}

func (gm got_manager*) resolve_entry(index i64, value i64) {
	idx := index / 8
	if idx >= 0 && idx < i64(len(gm.entries)) {
		gm.entries[idx].value = value
		gm.entries[idx].is_resolved = true
	}
}

func (gm got_manager*) generate_got_data() u8[] {
	data := make(u8[], gm.offset)

	for i, entry := range gm.entries {
		offset := i * 8
		binary.LittleEndian.PutUint64(data[offset:offset+8], u64(entry.value))
	}

	data
}

struct plt_manager {
	entries plt_entry[]
	offset  i64
}

struct plt_entry {
	symbol_index  i32
	got_address   i64
	stub_address  i64
	resolver_addr i64
}

func new_plt_manager() plt_manager {
	plt_manager{
		entries: make(plt_entry[], 0),
		offset: 0,
	}
}

func (pm plt_manager*) add_entry(sym_idx i32, got_addr i64) i64 {
	
	plt_size := i64(16)

	entry := plt_entry{
		symbol_index: sym_idx,
		got_address: got_addr,
		stub_address: pm.offset,
		resolver_addr: 0,
	}

	pm.entries = append(pm.entries, entry)
	idx := pm.offset
	pm.offset += plt_size

	idx
}

func (pm plt_manager*) generate_plt_code() u8[] {
	data := make(u8[], pm.offset)

	
	
	
	

	for i, entry := range pm.entries {
		offset := i * 16

		
		data[offset] = 0xff
		data[offset+1] = 0x25

		
		rip_rel_offset := entry.got_address - (entry.stub_address + 6)
		binary.LittleEndian.PutUint32(data[offset+2:offset+6], u32(rip_rel_offset))

		
		data[offset+6] = 0x68
		binary.LittleEndian.PutUint32(data[offset+7:offset+11], u32(entry.symbol_index))

		
		jmp_offset := -i32(offset+11) - 5 
		binary.LittleEndian.PutUint32(data[offset+11:offset+15], u32(jmp_offset))
	}

	data
}

struct tls_manager {
	blocks tls_block[]
	offset i64
}

struct tls_block {
	symbol    string
	size      i64
	offset    i64
	alignment i64
}

func new_tls_manager() tls_manager {
	tls_manager{
		blocks: make(tls_block[], 0),
		offset: 0,
	}
}

func (tm tls_manager*) add_variable(symbol string, size i64, alignment i64) i64 {
	
	if tm.offset % alignment != 0 {
		tm.offset += alignment - (tm.offset % alignment)
	}

	block := tls_block{
		symbol: symbol,
		size: size,
		offset: tm.offset,
		alignment: alignment,
	}

	tm.blocks = append(tm.blocks, block)
	idx := tm.offset
	tm.offset += size

	idx
}

func (tm tls_manager*) get_tls_size() i64 {
	tm.offset
}

func (tm tls_manager*) generate_tls_data() u8[] {
	data := make(u8[], tm.offset)
	
	for i := i64(0); i < tm.offset; i += 1 {
		data[i] = 0
	}
	data
}

struct dynamic_relocation {
	offset   i64
	type     i32  
	sym_index i32
	addend   i64
}

struct dynamic_reloc_manager {
	relocs dynamic_relocation[]
}

func new_dynamic_reloc_manager() dynamic_reloc_manager {
	dynamic_reloc_manager{
		relocs: make(dynamic_relocation[], 0),
	}
}

func (drm dynamic_reloc_manager*) add_relocation(offset i64, rel_type i32, sym_idx i32, addend i64) {
	reloc := dynamic_relocation{
		offset: offset,
		type: rel_type,
		sym_index: sym_idx,
		addend: addend,
	}

	drm.relocs = append(drm.relocs, reloc)
}

func (drm dynamic_reloc_manager*) generate_rela_dyn() u8[] {
	data := make(u8[], 0)

	for _, reloc := range drm.relocs {
		
		
		
		

		binary.LittleEndian.PutUint64(data[0:8], u64(reloc.offset))
		data = append(data, 0, 0, 0, 0, 0, 0, 0, 0)

		info := (u64(reloc.SymIndex) << 32) | u64(reloc.Type)
		binary.LittleEndian.PutUint64(data[8:16], info)
		data = append(data, 0, 0, 0, 0, 0, 0, 0, 0)

		binary.LittleEndian.PutUint64(data[16:24], u64(reloc.Addend))
		data = append(data, 0, 0, 0, 0, 0, 0, 0, 0)
	}

	data
}
