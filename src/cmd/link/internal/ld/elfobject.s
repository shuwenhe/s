package src.cmd.link.internal.ld

import (
	"src/encoding/binary"
	"src/io"
	"src/fmt"
	"src/os"
)

// ELF 常量定义
const (
	elf_magic = 0x464c457f // "\x7fELF"
	elf_class_32 = 1
	elf_class_64 = 2
	elf_endian_little = 1
	elf_endian_big = 2
	elf_version_current = 1
	elf_osabi_sysv = 0
	elf_osabi_linux = 3
)

// ELF 文件类型
enum elf_type {
	et_none = 0
	et_rel = 1     // 可重定位目标文件
	et_exec = 2    // 可执行文件
	et_dyn = 3     // 共享目标文件
	et_core = 4    // 核心文件
	et_loproc = 0xff00
	et_hiproc = 0xffff
}

// ELF Header
struct elf_header {
	magic         u32
	class         u8  // 32/64-bit
	endian        u8  // 大/小端
	version       u8
	os_abi        u8
	abi_version   u8
	padding       [7]u8
	type          i16
	machine       i16
	version       i32
	entry         u64
	phdr_offset   u64
	shdr_offset   u64
	flags         i32
	ehdr_size     i16
	phdr_entry_size i16
	phdr_num      i16
	shdr_entry_size i16
	shdr_num      i16
	shdr_str_index i16
}

// Section Header
struct section_header {
	name        i32
	type        i32
	flags       i64
	addr        i64
	offset      i64
	size        i64
	link        i32
	info        i32
	addr_align  i64
	entry_size  i64
}

// Program Header（用于动态链接）
struct program_header {
	type       i32
	flags      i32
	offset     i64
	virt_addr  i64
	phys_addr  i64
	file_size  i64
	mem_size   i64
	align      i64
}

// ELF 目标文件处理器
struct elf_object {
	header           elf_header
	sections section_header[]
	section_data     map[i32]u8[]    // section 索引 -> 数据
	symbols symbol_entry[]
	string_table     map[i32]string  // 字符串表
	relocations relocation[]
	machine          i16             // EM_X86_64, EM_ARM, 等
	flags            i32
	endian           int             // binary.LittleEndian 或 binary.BigEndian
}

// 创建 ELF 目标文件
func new_elf_object(machine i16) elf_object {
	obj := elf_object{
		sections: make(section_header[], 0),
		section_data: make(map[i32]u8[]),
		symbols: make(symbol_entry[], 0),
		string_table: make(map[i32]string),
		relocations: make(relocation[], 0),
		machine: machine,
		flags: 0,
		endian: int(binary.LittleEndian),
	}

	// 初始化 ELF 头
	obj.header.magic = elf_magic
	obj.header.class = elf_class_64
	obj.header.endian = elf_endian_little
	obj.header.version = elf_version_current
	obj.header.os_abi = elf_osabi_linux
	obj.header.abi_version = 0
	obj.header.type = i16(et_rel)
	obj.header.machine = machine
	obj.header.version = 1
	obj.header.entry = 0

	obj
}

// 添加 section
func (elf_object* eo) add_section(name string, sec_type i32, flags i64, data u8[]) i32 {
	idx := i32(len(eo.sections))

	shdr := section_header{
		name: 0,    // 稍后设置
		type: sec_type,
		flags: flags,
		addr: 0,
		offset: 0,
		size: i64(len(data)),
		link: 0,
		info: 0,
		addr_align: 8,
		entry_size: 0,
	}

	eo.sections = append(eo.sections, shdr)
	if data != nil {
		eo.section_data[idx] = data
	}

	idx
}

// 添加符号
func (elf_object* eo) add_symbol(sym symbol_entry) i32 {
	idx := i32(len(eo.symbols))
	eo.symbols = append(eo.symbols, sym)
	idx
}

// 添加字符串到字符串表
func (elf_object* eo) add_string(s string) i32 {
	// 在实际实现中，这应该使用真实的字符串表
	idx := i32(len(eo.string_table))
	eo.string_table[idx] = s
	idx
}

// 添加重定位
func (elf_object* eo) add_relocation(reloc relocation) {
	eo.relocations = append(eo.relocations, reloc)
}

// 从文件读取 ELF 对象
func read_elf_object(string filename) (elf_object, error) {
	file, err := os.open(filename)
	if err != nil {
		elf_object{}, err
	}
	defer file.close()

	obj := new_elf_object(0)

	// 读取 ELF 头（52 字节）
	hdr_buf := make(u8[], 64)
	n, err := file.read(hdr_buf)
	if err != nil || n < 52 {
		elf_object{}, "failed to read ELF header"
	}

	// 解析 ELF 头
	obj.header.magic = binary.LittleEndian.Uint32(hdr_buf[0:4])
	if obj.header.magic != elf_magic {
		elf_object{}, "invalid ELF magic number"
	}

	obj.header.class = hdr_buf[4]
	obj.header.endian = hdr_buf[5]
	obj.header.version = hdr_buf[6]

	if obj.header.class == elf_class_64 {
		obj.header.type = i16(binary.LittleEndian.Uint16(hdr_buf[16:18]))
		obj.header.machine = i16(binary.LittleEndian.Uint16(hdr_buf[18:20]))
		obj.header.version = i32(binary.LittleEndian.Uint32(hdr_buf[20:24]))
		obj.header.shdr_offset = binary.LittleEndian.Uint64(hdr_buf[32:40])
		obj.header.shdr_num = i16(binary.LittleEndian.Uint16(hdr_buf[48:50]))
		obj.header.shdr_entry_size = i16(binary.LittleEndian.Uint16(hdr_buf[58:60]))
	}

	// 读取 section headers
	for i := i32(0); i < i32(obj.header.shdr_num); i += 1 {
		shdr_buf := make(u8[], 64)
		_, err = file.read_at(shdr_buf, obj.header.shdr_offset + i64(i)*i64(obj.header.shdr_entry_size))
		if err != nil {
			continue
		}

		shdr := section_header{
			name: i32(binary.LittleEndian.Uint32(shdr_buf[0:4])),
			type: i32(binary.LittleEndian.Uint32(shdr_buf[4:8])),
			flags: i64(binary.LittleEndian.Uint64(shdr_buf[8:16])),
			addr: i64(binary.LittleEndian.Uint64(shdr_buf[16:24])),
			offset: i64(binary.LittleEndian.Uint64(shdr_buf[24:32])),
			size: i64(binary.LittleEndian.Uint64(shdr_buf[32:40])),
			link: i32(binary.LittleEndian.Uint32(shdr_buf[40:44])),
			info: i32(binary.LittleEndian.Uint32(shdr_buf[44:48])),
			addr_align: i64(binary.LittleEndian.Uint64(shdr_buf[48:56])),
			entry_size: i64(binary.LittleEndian.Uint64(shdr_buf[56:64])),
		}

		obj.sections = append(obj.sections, shdr)

		// 读取 section 数据
		if shdr.size > 0 {
			data := make(u8[], shdr.size)
			_, err = file.read_at(data, shdr.offset)
			if err == nil {
				obj.section_data[i] = data
			}
		}
	}

	obj, nil
}

// 将 ELF 对象写入文件
func (elf_object* eo) write_to_file(string filename) error {
	file, err := os.create(filename)
	if err != nil {
		err
	}
	defer file.close()

	// 写入 ELF 头
	hdr_buf := make(u8[], 64)

	// Magic 和身份信息
	binary.LittleEndian.PutUint32(hdr_buf[0:4], eo.header.magic)
	hdr_buf[4] = eo.header.class
	hdr_buf[5] = eo.header.endian
	hdr_buf[6] = eo.header.version
	hdr_buf[7] = eo.header.os_abi
	hdr_buf[8] = eo.header.abi_version

	// 文件类型和机器类型
	binary.LittleEndian.PutUint16(hdr_buf[16:18], u16(eo.header.type))
	binary.LittleEndian.PutUint16(hdr_buf[18:20], u16(eo.header.machine))
	binary.LittleEndian.PutUint32(hdr_buf[20:24], u32(eo.header.version))

	// Section 头表
	binary.LittleEndian.PutUint64(hdr_buf[32:40], eo.header.shdr_offset)
	binary.LittleEndian.PutUint16(hdr_buf[48:50], u16(eo.header.shdr_num))
	binary.LittleEndian.PutUint16(hdr_buf[50:52], u16(eo.header.shdr_str_index))
	binary.LittleEndian.PutUint16(hdr_buf[58:60], u16(eo.header.shdr_entry_size))

	_, err = file.write(hdr_buf)
	if err != nil {
		err
	}

	// 写入 section 数据和头部

	// 计算偏移量
	var offset i64 = i64(len(hdr_buf))
	var shdr_offset i64 = 0

	// 首先计算 section 数据的总大小
	for _, shdr := range eo.sections {
		if shdr.type != 8 { // SHT_NOBITS
			offset += shdr.size
		}
	}

	shdr_offset = offset

	// 写入 section 数据
	current_offset := i64(len(hdr_buf))
	for i, shdr := range eo.sections {
		if shdr.type != 8 { // SHT_NOBITS
			if data, ok := eo.section_data[i32(i)]; ok {
				_, err = file.write_at(data, current_offset)
				if err != nil {
					err
				}
				current_offset += i64(len(data))
			}
		}
	}

	// 写入 section 头表
	eo.header.shdr_offset = u64(shdr_offset)
	eo.header.shdr_num = i16(len(eo.sections))
	eo.header.shdr_entry_size = 64

	for _, shdr := range eo.sections {
		shdr_buf := make(u8[], 64)

		binary.LittleEndian.PutUint32(shdr_buf[0:4], u32(shdr.name))
		binary.LittleEndian.PutUint32(shdr_buf[4:8], u32(shdr.type))
		binary.LittleEndian.PutUint64(shdr_buf[8:16], u64(shdr.flags))
		binary.LittleEndian.PutUint64(shdr_buf[16:24], u64(shdr.addr))
		binary.LittleEndian.PutUint64(shdr_buf[24:32], u64(shdr.offset))
		binary.LittleEndian.PutUint64(shdr_buf[32:40], u64(shdr.size))
		binary.LittleEndian.PutUint32(shdr_buf[40:44], u32(shdr.link))
		binary.LittleEndian.PutUint32(shdr_buf[44:48], u32(shdr.info))
		binary.LittleEndian.PutUint64(shdr_buf[48:56], u64(shdr.addr_align))
		binary.LittleEndian.PutUint64(shdr_buf[56:64], u64(shdr.entry_size))

		_, err = file.write(shdr_buf)
		if err != nil {
			err
		}
	}

	nil
}

// ELF section 类型常量
const (
	sht_null = 0
	sht_progbits = 1
	sht_symtab = 2
	sht_strtab = 3
	sht_rela = 4
	sht_hash = 5
	sht_dynamic = 6
	sht_note = 7
	sht_nobits = 8
	sht_rel = 9
	sht_shlib = 10
	sht_dynsym = 11
	sht_init_array = 14
	sht_fini_array = 15
	sht_preinit_array = 16
	sht_group = 17
	sht_symtab_shndx = 18
)

// ELF section 标志
const (
	shf_write = 0x1
	shf_alloc = 0x2
	shf_execinstr = 0x4
	shf_merge = 0x10
	shf_strings = 0x20
	shf_info_link = 0x40
	shf_link_order = 0x80
	shf_os_nonconforming = 0x100
	shf_group = 0x200
	shf_tls = 0x400
	shf_compressed = 0x800
	shf_gnu_retain = 0x200000
)
