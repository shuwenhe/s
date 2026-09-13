package cmd
use std.io.file as file_type
use std.encoding.binary.write as binary_write
use std.encoding.binary.little_endian
const elf_magic = 0x464c457f
const elf_class_64 = 2
const elf_data_le = 1
const elf_version = 1
const elf_osabi = 0
const elf_abiversion = 0
const elf_type_exec = 2
const elf_machine_x86_64 = 0x3_e
struct elf_header {
    magic: u32
    class_: u8
    data: u8
    version: u8
    osabi: u8
    abiversion: u8
    padding: [7]u8
    type_: u16
    machine: u16
    version2: u32
    entry: u64
    program_header_offset: u64
    section_header_offset: u64
    flags: u32
    header_size: u16
    program_header_size: u16
    program_header_count: u16
    section_header_size: u16
    section_header_count: u16
    section_header_string_index: u16
}

struct program_header {
    type_: u32
    flags: u32
    offset: u64
    vaddr: u64
    paddr: u64
    filesz: u64
    memsz: u64
    align: u64
}

struct section_header {
    name: u32
    type_: u32
    flags: u64
    addr: u64
    offset: u64
    size: u64
    link: u32
    info: u32
    addralign: u64
    entsize: u64
}
const pt_load = 1
const pt_dynamic = 3
const pt_interp = 3
const sht_null = 0
const sht_progbits = 1
const sht_symtab = 2
const sht_strtab = 3
const sht_rela = 4
const shf_write = 0x1
const shf_alloc = 0x2
const shf_execinstr = 0x4

struct elf_builder {
    header: elf_header
    program_headers: program_header[]
    section_headers: section_header[]
    code_section: byte[]
    data_section: byte[]
    string_table: byte[]
    symbol_table: byte[]
}

func new_elf_builder() elf_builder {
    return elf_builder{
        header: elf_header{
            magic: elf_magic, class_ elf_class_64, data elf_data_le, version elf_version, osabi elf_osabi, abiversion elf_abiversion, type_ elf_type_exec, machine elf_machine_x86_64, entry 0x400000, header_size 64, program_header_size 56, section_header_size 64,
        },
        program_headers: program_header[]{},
        section_headers: section_header[]{},
        code_section: byte[]{},
        data_section: byte[]{},
        string_table: byte[]{},
        symbol_table: byte[]{},
    }
}

func (elf_builder* builder) add_code(byte[] code) {
    builder.code_section = append_slice(builder.code_section, code)
}

func (elf_builder* builder) generate() byte[] {
    buffer: byte[] = byte[]{}
    return buffer
}

func generate_elf_from_x86_64_asm(string asm_source, string output_binary) error {
    return nil
}
