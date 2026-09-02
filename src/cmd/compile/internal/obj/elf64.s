package compile.internal.obj
use compile.internal.link
enum elf_class {
    elf_class_32,
    elf_class_64,
}
enum elf_data {
    elf_data_lsb,
    elf_data_msb,
}
enum elf_type {
    elf_type_relocatable,
    elf_type_executable,
    elf_type_shared,
    elf_type_core,
}
enum elf_machine {
    elf_machine_x86_64 = 62,
    elf_machine_arm64 = 183,
    elf_machine_riscv = 243,
}
struct elf_header {
    []int8 ident
    elf_type type
    elf_machine machine
    int32 version
    int64 entry
    int64 phoff
    int64 shoff
    int32 flags
    int16 ehsize
    int16 phentsize
    int16 phnum
    int16 shentsize
    int16 shnum
    int16 shstrndx
}

struct elf_section_header {
    int32 name
    int32 type
    int64 flags
    int64 addr
    int64 offset
    int64 size
    int32 link
    int32 info
    int64 addralign
    int64 entsize
}

struct elf_symbol {
    int32 name
    int8 info
    int8 other
    int16 shndx
    int64 value
    int64 size
}

struct elf_relocation {
    int64 offset
    int64 info
    int64 addend
}

struct elf_writer {
    []int8 data
    int64 offset
    elf_machine target_machine
}

func make_elf_writer(elf_machine machine) elf_writer {
    elf_writer {
        data: []int8()(), offset 0, target_machine machine,
    }
}

func (w* elf_writer) write_bytes([]int8 bytes) int64 {
    start := w.offset
    i := 0
    for i < len(bytes) {
        w.data = append(w.data, bytes[i])
        w.offset = w.offset + 1
        i = i + 1
    }
    start
}

func (w* elf_writer) write_u32(int32 value) int64 {
    start := w.offset
    b0 := (value as int8)
    b1 := ((value >> 8) as int8)
    b2 := ((value >> 16) as int8)
    b3 := ((value >> 24) as int8)
    w.data = append(w.data, b0)
    w.data = append(w.data, b1)
    w.data = append(w.data, b2)
    w.data = append(w.data, b3)
    w.offset = w.offset + 4
    start
}

func (w* elf_writer) write_u64(int64 value) int64 {
    start := w.offset
    b0 := (value as int8)
    b1 := ((value >> 8) as int8)
    b2 := ((value >> 16) as int8)
    b3 := ((value >> 24) as int8)
    b4 := ((value >> 32) as int8)
    b5 := ((value >> 40) as int8)
    b6 := ((value >> 48) as int8)
    b7 := ((value >> 56) as int8)
    w.data = append(w.data, b0)
    w.data = append(w.data, b1)
    w.data = append(w.data, b2)
    w.data = append(w.data, b3)
    w.data = append(w.data, b4)
    w.data = append(w.data, b5)
    w.data = append(w.data, b6)
    w.data = append(w.data, b7)
    w.offset = w.offset + 8
    start
}

func (w* elf_writer) write_u16(int16 value) int64 {
    start := w.offset
    b0 := (value as int8)
    b1 := ((value >> 8) as int8)
    w.data = append(w.data, b0)
    w.data = append(w.data, b1)
    w.offset = w.offset + 2
    start
}

func (w* elf_writer) write_u8(int8 value) int64 {
    start := w.offset
    w.data = append(w.data, value)
    w.offset = w.offset + 1
    start
}

func (w* elf_writer) pad_to(int64 align) {
    remainder := w.offset % align
    if remainder != 0 {
        padding := align - remainder
        i := 0
        for i < padding {
            w.data = append(w.data, 0 as int8)
            w.offset = w.offset + 1
            i = i + 1
        }
    }
}

func (w* elf_writer) write_elf_header(elf_machine machine) {
    w.write_u8(0x7f as int8)
    w.write_u8(69 as int8)
    w.write_u8(76 as int8)
    w.write_u8(70 as int8)
    w.write_u8(2 as int8)
    w.write_u8(1 as int8)
    w.write_u8(0 as int8)
    w.write_u8(0 as int8)
    i := 8
    for i < 16 {
        w.write_u8(0 as int8)
        i = i + 1
    }
    w.write_u16(2 as int16)
    w.write_u16((machine as int16))
    w.write_u32(1 as int32)
    w.write_u64(0 as int64)
    w.write_u64(0 as int64)
    w.write_u64(64 as int64)
    w.write_u32(0 as int32)
    w.write_u32(0 as int32)
    w.write_u16(64 as int16)
    w.write_u16(0 as int16)
    w.write_u16(0 as int16)
    w.write_u16(64 as int16)
    w.write_u16(1 as int16)
    w.write_u16(0 as int16)
}

func (w* elf_writer) write_section_headers([]elf_section_header sections) {
    i := 0
    for i < len(sections) {
        sh := sections[i]
        w.write_u32(sh.name)
        w.write_u32(sh.type)
        w.write_u64(sh.flags)
        w.write_u64(sh.addr)
        w.write_u64(sh.offset)
        w.write_u64(sh.size)
        w.write_u32(sh.link)
        w.write_u32(sh.info)
        w.write_u64(sh.addralign)
        w.write_u64(sh.entsize)
        i = i + 1
    }
}

func (w* elf_writer) write_symbol_table([]elf_symbol symbols) {
    i := 0
    for i < len(symbols) {
        sym := symbols[i]
        w.write_u32(sym.name)
        w.write_u8(sym.info)
        w.write_u8(sym.other)
        w.write_u16(sym.shndx)
        w.write_u64(sym.value)
        w.write_u64(sym.size)
        i = i + 1
    }
}

func (w* elf_writer) write_relocations([]elf_relocation relocs) {
    i := 0
    for i < len(relocs) {
        r := relocs[i]
        w.write_u64(r.offset)
        w.write_u64(r.info)
        w.write_u64(r.addend)
        i = i + 1
    }
}

func (w* elf_writer) get_data() []int8 {
    w.data
}
