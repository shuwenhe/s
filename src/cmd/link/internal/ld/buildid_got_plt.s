package src.cmd.link.internal.ld

import (
	"src/fmt"
	"src/crypto/sha256"
	"src/encoding/binary"
)

// Build-ID 类型
enum build_id_type {
	bid_uuid = 0
	bid_md5 = 1
	bid_sha1 = 2
	bid_sha256 = 3
}

// Build-ID 管理器
struct build_id_manager {
	type    build_id_type
	id u8[]
	version string
}

// 创建 Build-ID 管理器
func new_build_id_manager(t build_id_type) build_id_manager {
	build_id_manager{
		type: t,
		id: make(u8[], 0),
		version: "1.0",
	}
}

// 生成 Build-ID（SHA256）
func (bim build_id_manager*) generate_build_id(data u8[]) {
	// 对所有二进制数据计算 SHA256
	hash := sha256.Sum256(data)
	bim.id = make(u8[], len(hash))
	for i, b := range hash {
		bim.id[i] = b
	}
}

// 获取 Build-ID 字符串
func (bim build_id_manager*) get_build_id_string() string {
	s := ""
	for _, b := range bim.id {
		s = fmt.Sprintf("%s%02x", s, b)
	}
	s
}

// 生成 .note.gnu.build-id section
func (bim build_id_manager*) generate_note_section() u8[] {
	data := make(u8[], 0)

	// note 格式：
	// namesz (4 bytes)
	// descsz (4 bytes)
	// type (4 bytes)
	// name (namesz bytes, 对齐到 4 bytes)
	// desc (descsz bytes, 对齐到 4 bytes)

	name := "GNU"
	namesz := i32(len(name) + 1)
	descsz := i32(len(bim.id))

	// 对齐到 4 bytes
	aligned_namesz := (namesz + 3) & ^3
	aligned_descsz := (descsz + 3) & ^3

	// namesz
	binary.LittleEndian.PutUint32(data[0:4], u32(namesz))
	data = append(data, 0, 0, 0, 0)

	// descsz
	binary.LittleEndian.PutUint32(data[4:8], u32(descsz))
	data = append(data, 0, 0, 0, 0)

	// type (NT_GNU_BUILD_ID = 3)
	binary.LittleEndian.PutUint32(data[8:12], 3)
	data = append(data, 0, 0, 0, 0)

	// name
	data = append(data, u8[](name)...)
	data = append(data, 0)

	// 对齐填充
	for i := namesz; i < aligned_namesz; i += 1 {
		data = append(data, 0)
	}

	// desc (build-id)
	data = append(data, bim.id...)

	// 对齐填充
	for i := descsz; i < aligned_descsz; i += 1 {
		data = append(data, 0)
	}

	data
}

// GOT (Global Offset Table) 管理
struct got_manager {
	entries got_entry[]
	offset  i64
}

// GOT 条目
struct got_entry {
	symbol_index i32
	reloc_type   reloc_type
	address     i64
	value       i64
	is_resolved  bool
}

// 创建 GOT 管理器
func new_got_manager() got_manager {
	got_manager{
		entries: make(got_entry[], 0),
		offset: 0,
	}
}

// 添加 GOT 条目
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
	gm.offset += 8 // 64-bit GOT 条目

	idx
}

// 查找或创建 GOT 条目
func (gm got_manager*) lookup_or_create(sym_idx i32, reloc_type reloc_type) i64 {
	// 检查是否已存在
	for _, entry := range gm.entries {
		if entry.symbol_index == sym_idx && entry.reloc_type == reloc_type {
			entry.address
		}
	}

	// 创建新条目
	gm.add_entry(sym_idx, reloc_type)
}

// 解析 GOT 条目
func (gm got_manager*) resolve_entry(index i64, value i64) {
	idx := index / 8
	if idx >= 0 && idx < i64(len(gm.entries)) {
		gm.entries[idx].value = value
		gm.entries[idx].is_resolved = true
	}
}

// 生成 GOT 数据
func (gm got_manager*) generate_got_data() u8[] {
	data := make(u8[], gm.offset)

	for i, entry := range gm.entries {
		offset := i * 8
		binary.LittleEndian.PutUint64(data[offset:offset+8], u64(entry.value))
	}

	data
}

// PLT (Procedure Linkage Table) 管理
struct plt_manager {
	entries plt_entry[]
	offset  i64
}

// PLT 条目（x86-64）
struct plt_entry {
	symbol_index  i32
	got_address   i64
	stub_address  i64
	resolver_addr i64
}

// 创建 PLT 管理器
func new_plt_manager() plt_manager {
	plt_manager{
		entries: make(plt_entry[], 0),
		offset: 0,
	}
}

// 添加 PLT 条目
func (pm plt_manager*) add_entry(sym_idx i32, got_addr i64) i64 {
	// PLT stub 大小：16 字节
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

// 生成 PLT 代码（x86-64）
func (pm plt_manager*) generate_plt_code() u8[] {
	data := make(u8[], pm.offset)

	// PLT stub 格式（x86-64）：
	// 0: ff 25 xx xx xx xx      jmp [rip + offset]  (GOT 条目地址)
	// 6: 68 xx xx xx xx         push imm32          (符号索引)
	// b: e9 xx xx xx xx         jmp PLT_resolver

	for i, entry := range pm.entries {
		offset := i * 16

		// jmp [rip + offset]
		data[offset] = 0xff
		data[offset+1] = 0x25

		// 计算 RIP 相对偏移
		rip_rel_offset := entry.got_address - (entry.stub_address + 6)
		binary.LittleEndian.PutUint32(data[offset+2:offset+6], u32(rip_rel_offset))

		// push imm32
		data[offset+6] = 0x68
		binary.LittleEndian.PutUint32(data[offset+7:offset+11], u32(entry.symbol_index))

		// jmp PLT resolver (相对于当前位置 + 5 字节指令长度)
		jmp_offset := -i32(offset+11) - 5 // 计算相对偏移（通常指向 PLT[0]）
		binary.LittleEndian.PutUint32(data[offset+11:offset+15], u32(jmp_offset))
	}

	data
}

// TLS (Thread Local Storage) 管理
struct tls_manager {
	blocks tls_block[]
	offset i64
}

// TLS 块
struct tls_block {
	symbol    string
	size      i64
	offset    i64
	alignment i64
}

// 创建 TLS 管理器
func new_tls_manager() tls_manager {
	tls_manager{
		blocks: make(tls_block[], 0),
		offset: 0,
	}
}

// 添加 TLS 变量
func (tm tls_manager*) add_variable(symbol string, size i64, alignment i64) i64 {
	// 对齐偏移
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

// 获取 TLS 块大小
func (tm tls_manager*) get_tls_size() i64 {
	tm.offset
}

// 生成 TLS 初始化数据
func (tm tls_manager*) generate_tls_data() u8[] {
	data := make(u8[], tm.offset)
	// 初始化为零
	for i := i64(0); i < tm.offset; i += 1 {
		data[i] = 0
	}
	data
}

// Dynamic Relocation 处理（用于延迟绑定）
struct dynamic_relocation {
	offset   i64
	type     i32  // R_X86_64_JUMP_SLOT, R_X86_64_GLOB_DAT 等
	sym_index i32
	addend   i64
}

// Dynamic Relocation 管理器
struct dynamic_reloc_manager {
	relocs dynamic_relocation[]
}

// 创建 Dynamic Relocation 管理器
func new_dynamic_reloc_manager() dynamic_reloc_manager {
	dynamic_reloc_manager{
		relocs: make(dynamic_relocation[], 0),
	}
}

// 添加动态重定位
func (drm dynamic_reloc_manager*) add_relocation(offset i64, rel_type i32, sym_idx i32, addend i64) {
	reloc := dynamic_relocation{
		offset: offset,
		type: rel_type,
		sym_index: sym_idx,
		addend: addend,
	}

	drm.relocs = append(drm.relocs, reloc)
}

// 生成 .rela.dyn section 数据
func (drm dynamic_reloc_manager*) generate_rela_dyn() u8[] {
	data := make(u8[], 0)

	for _, reloc := range drm.relocs {
		// Elf64_Rela 格式
		// offset (8 bytes)
		// info (8 bytes) = (SymIndex << 32) | Type
		// addend (8 bytes)

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
