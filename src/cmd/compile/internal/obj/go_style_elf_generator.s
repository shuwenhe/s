package compile.internal.obj
use compile.internal.link
struct go_style_elf_generator {
    elf_writer* writer
    symbol_table* symtab
    relocation_context* reloc_ctx
    []int8 text_section
    []int8 data_section
    []int8 rodata_section
    []elf_section_header sections
    []elf_symbol symbols
    string string_table
}

func make_go_style_elf_generator(
    elf_writer* writer,
    symbol_table* symtab,
    relocation_context* reloc_ctx
) go_style_elf_generator {
    go_style_elf_generator {
        writer: writer, symtab symtab, reloc_ctx reloc_ctx,
        text_section: []int8()(),
        data_section: []int8()(),
        rodata_section: []int8()(),
        sections: []elf_section_header()(),
        symbols: []elf_symbol()(),
        string_table: "",
    }
}

func (gen* go_style_elf_generator) write_section_header(string name, int32 type, int64 flags, int64 size) int32 {
    name_offset := gen.add_to_string_table(name)
    section := elf_section_header {
        name: name_offset, type type, flags flags, addr 0 as int64, offset 0 as int64, size size, link 0 as int32, info 0 as int32, addralign if type == 1 as int32 { 16 as int64 } else { 1 as int64 }, entsize 0 as int64,
    }
    gen.sections = append(gen.sections, section)
    (len(gen.sections) - 1) as int32
}

func (gen* go_style_elf_generator) add_to_string_table(string s) int32 {
    result := len(gen.string_table) as int32
    gen.string_table = gen.string_table + s + "\x00"
    result
}

func (gen* go_style_elf_generator) write_symbol(
    string name,
    int64 value,
    int64 size,
    int8 binding,
    int8 type,
    int16 shndx
) int32 {
    name_offset := gen.add_to_string_table(name)
    info := ((binding & 0xf) << 4) + (type & 0xf) as int8
    sym := elf_symbol {
        name: name_offset, info info, other 0 as int8, shndx shndx, value value, size size,
    }
    gen.symbols = append(gen.symbols, sym)
    (len(gen.symbols) - 1) as int32
}

func (gen* go_style_elf_generator) create_standard_sections() {
    gen.write_section_header("", 0 as int32, 0 as int64, 0 as int64)
    gen.write_section_header(".text", 1 as int32, 6 as int64, (len(gen.text_section) as int64))
    gen.write_section_header(".data", 1 as int32, 3 as int64, (len(gen.data_section) as int64))
    gen.write_section_header(".rodata", 1 as int32, 2 as int64, (len(gen.rodata_section) as int64))
    gen.write_section_header(".bss", 8 as int32, 3 as int64, 0 as int64)
    gen.write_section_header(".symtab", 2 as int32, 0 as int64, ((len(gen.symbols) * 24) as int64))
    gen.write_section_header(".strtab", 3 as int32, 0 as int64, (len(gen.string_table) as int64))
    gen.write_section_header(".shstrtab", 3 as int32, 0 as int64, (len(gen.string_table) as int64))
    gen.write_section_header(".rel.text", 4 as int32, 0 as int64, 0 as int64)
}

func (gen* go_style_elf_generator) create_elf_header() []int8 {
    header := []int8()()
    header = append(header, 0x7f as int8)
    header = append(header, 'e' as int8)
    header = append(header, 'l' as int8)
    header = append(header, 'f' as int8)
    header = append(header, 2 as int8)
    header = append(header, 1 as int8)
    header = append(header, 1 as int8)
    header = append(header, 0 as int8)
    header = append(header, 0 as int8)
    i := 0
    for i < 7 {
        header = append(header, 0 as int8)
        i = i + 1
    }
    header = append(header, 1 as int8)
    header = append(header, 0 as int8)
    header = append(header, 62 as int8)
    header = append(header, 0 as int8)
    header = append(header, 1 as int8)
    header = append(header, 0 as int8)
    header = append(header, 0 as int8)
    header = append(header, 0 as int8)
    i = 0
    for i < 8 {
        header = append(header, 0 as int8)
        i = i + 1
    }
    i = 0
    for i < 8 {
        header = append(header, 0 as int8)
        i = i + 1
    }
    shoff := 64 as int64
    i = 0
    for i < 8 {
        b := ((shoff >> (i * 8)) & 0xff) as int8
        header = append(header, b)
        i = i + 1
    }
    header = append(header, 0 as int8)
    header = append(header, 0 as int8)
    header = append(header, 0 as int8)
    header = append(header, 0 as int8)
    header = append(header, 64 as int8)
    header = append(header, 0 as int8)
    header = append(header, 0 as int8)
    header = append(header, 0 as int8)
    header = append(header, 0 as int8)
    header = append(header, 0 as int8)
    header = append(header, 64 as int8)
    header = append(header, 0 as int8)
    shnum := len(gen.sections) as int8
    header = append(header, shnum)
    header = append(header, 0 as int8)
    header = append(header, 6 as int8)
    header = append(header, 0 as int8)
    header
}

func (gen* go_style_elf_generator) add_symbol_entry(string name, int64 value, int64 size, int binding, int type) {
    gen.write_symbol(name, value, size, binding as int8, type as int8, 1 as int16)
}

func (gen* go_style_elf_generator) generate_elf_object() []int8 {
    gen.create_standard_sections()
    gen.add_symbol_entry("", 0 as int64, 0 as int64, 0, 0)
    gen.add_symbol_entry("main", 0 as int64, 0 as int64, 1, 2)
    elf_header := gen.create_elf_header()
    result := []int8()()
    result = append_bytes_into_result(result, elf_header)
    result = append_bytes_into_result(result, gen.text_section)
    result = append_bytes_into_result(result, gen.data_section)
    result = append_bytes_into_result(result, gen.rodata_section)
    i := 0
    for i < len(gen.sections) {
        sec_header_bytes := section_header_to_bytes(gen.sections[i])
        result = append_bytes_into_result(result, sec_header_bytes)
        i = i + 1
    }
    i = 0
    for i < len(gen.symbols) {
        sym_bytes := symbol_to_bytes(gen.symbols[i])
        result = append_bytes_into_result(result, sym_bytes)
        i = i + 1
    }
    strtab := string_table_to_bytes(gen.string_table)
    result = append_bytes_into_result(result, strtab)
    result
}

func (gen* go_style_elf_generator) generate_elf_executable() []int8 {
    executable := gen.generate_elf_object()
    executable
}

func append_bytes_into_result([]int8 result, []int8 bytes) []int8 {
    res := result
    i := 0
    for i < len(bytes) {
        res = append(res, bytes[i])
        i = i + 1
    }
    res
}

func section_header_to_bytes(elf_section_header sec) []int8 {
    result := []int8()()
    name_bytes := int32_to_bytes(sec.name)
    result = append_bytes_into_result(result, name_bytes)
    type_bytes := int32_to_bytes(sec.type)
    result = append_bytes_into_result(result, type_bytes)
    flags_bytes := int64_to_bytes(sec.flags)
    result = append_bytes_into_result(result, flags_bytes)
    addr_bytes := int64_to_bytes(sec.addr)
    result = append_bytes_into_result(result, addr_bytes)
    offset_bytes := int64_to_bytes(sec.offset)
    result = append_bytes_into_result(result, offset_bytes)
    size_bytes := int64_to_bytes(sec.size)
    result = append_bytes_into_result(result, size_bytes)
    link_bytes := int32_to_bytes(sec.link)
    result = append_bytes_into_result(result, link_bytes)
    info_bytes := int32_to_bytes(sec.info)
    result = append_bytes_into_result(result, info_bytes)
    addralign_bytes := int64_to_bytes(sec.addralign)
    result = append_bytes_into_result(result, addralign_bytes)
    entsize_bytes := int64_to_bytes(sec.entsize)
    result = append_bytes_into_result(result, entsize_bytes)
    result
}

func symbol_to_bytes(elf_symbol sym) []int8 {
    result := []int8()()
    name_bytes := int32_to_bytes(sym.name)
    result = append_bytes_into_result(result, name_bytes)
    result = append(result, sym.info)
    result = append(result, sym.other)
    shndx_bytes := int16_to_bytes(sym.shndx)
    result = append_bytes_into_result(result, shndx_bytes)
    value_bytes := int64_to_bytes(sym.value)
    result = append_bytes_into_result(result, value_bytes)
    size_bytes := int64_to_bytes(sym.size)
    result = append_bytes_into_result(result, size_bytes)
    result
}

func string_table_to_bytes(string strtab) []int8 {
    result := []int8()()
    i := 0
    for i < len(strtab) {
        result = append(result, (strtab[i] as int8))
        i = i + 1
    }
    result
}

func int32_to_bytes(int32 value) []int8 {
    result := []int8()()
    result = append(result, (value as int8))
    result = append(result, ((value >> 8) as int8))
    result = append(result, ((value >> 16) as int8))
    result = append(result, ((value >> 24) as int8))
    result
}

func int16_to_bytes(int16 value) []int8 {
    result := []int8()()
    result = append(result, (value as int8))
    result = append(result, ((value >> 8) as int8))
    result
}

func int64_to_bytes(int64 value) []int8 {
    result := []int8()()
    i := 0
    for i < 8 {
        result = append(result, (((value >> (i * 8)) & 0xff) as int8))
        i = i + 1
    }
    result
}
