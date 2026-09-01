package compile.internal.obj

use compile.internal.link

// 参考 Go 编译器的对象文件生成器实现
// 直接生成 ELF 格式的可重定位对象文件

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
        writer: writer,
        symtab: symtab,
        reloc_ctx: reloc_ctx,
        text_section: []int8()(),
        data_section: []int8()(),
        rodata_section: []int8()(),
        sections: []elf_section_header()(),
        symbols: []elf_symbol()(),
        string_table: "",
    }
}

// 参考 Go 的 writeSectionHeader，写入节头
func (gen* go_style_elf_generator) write_section_header(string name, int32 type, int64 flags, int64 size) int32 {
    name_offset := gen.add_to_string_table(name)
    
    section := elf_section_header {
        name: name_offset,
        type: type,
        flags: flags,
        addr: 0 as int64,
        offset: 0 as int64,
        size: size,
        link: 0 as int32,
        info: 0 as int32,
        addralign: if type == 1 as int32 { 16 as int64 } else { 1 as int64 },
        entsize: 0 as int64,
    }
    
    gen.sections = append(gen.sections, section)
    (len(gen.sections) - 1) as int32
}

// 参考 Go 的 addStringToSymtab，添加字符串到符号表
func (gen* go_style_elf_generator) add_to_string_table(string s) int32 {
    result := len(gen.string_table) as int32
    gen.string_table = gen.string_table + s + "\x00"
    result
}

// 参考 Go 的 writeSymbol，写入符号
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
        name: name_offset,
        info: info,
        other: 0 as int8,
        shndx: shndx,
        value: value,
        size: size,
    }
    
    gen.symbols = append(gen.symbols, sym)
    (len(gen.symbols) - 1) as int32
}

// 生成标准的节（sections）
func (gen* go_style_elf_generator) create_standard_sections() {
    // NULL 节 (必须)
    gen.write_section_header("", 0 as int32, 0 as int64, 0 as int64)
    
    // .text 节
    gen.write_section_header(".text", 1 as int32, 6 as int64, (len(gen.text_section) as int64))
    
    // .data 节
    gen.write_section_header(".data", 1 as int32, 3 as int64, (len(gen.data_section) as int64))
    
    // .rodata 节
    gen.write_section_header(".rodata", 1 as int32, 2 as int64, (len(gen.rodata_section) as int64))
    
    // .bss 节
    gen.write_section_header(".bss", 8 as int32, 3 as int64, 0 as int64)
    
    // .symtab 节
    gen.write_section_header(".symtab", 2 as int32, 0 as int64, ((len(gen.symbols) * 24) as int64))
    
    // .strtab 节
    gen.write_section_header(".strtab", 3 as int32, 0 as int64, (len(gen.string_table) as int64))
    
    // .shstrtab 节
    gen.write_section_header(".shstrtab", 3 as int32, 0 as int64, (len(gen.string_table) as int64))
    
    // .rel.text 节 (重定位信息)
    gen.write_section_header(".rel.text", 4 as int32, 0 as int64, 0 as int64)
}

// 创建 ELF 文件头 (参考 Go 的 writeHeader)
func (gen* go_style_elf_generator) create_elf_header() []int8 {
    header := []int8()()
    
    // ELF 魔数
    header = append(header, 0x7f as int8)
    header = append(header, 'E' as int8)
    header = append(header, 'L' as int8)
    header = append(header, 'F' as int8)
    
    // 类别 (64-bit)
    header = append(header, 2 as int8)
    
    // 数据编码 (小端)
    header = append(header, 1 as int8)
    
    // 版本
    header = append(header, 1 as int8)
    
    // OS/ABI
    header = append(header, 0 as int8)
    
    // ABI 版本
    header = append(header, 0 as int8)
    
    // 填充
    i := 0
    for i < 7 {
        header = append(header, 0 as int8)
        i = i + 1
    }
    
    // e_type: 可重定位对象 (ET_REL = 1)
    header = append(header, 1 as int8)
    header = append(header, 0 as int8)
    
    // e_machine: x86-64 (62)
    header = append(header, 62 as int8)
    header = append(header, 0 as int8)
    
    // e_version
    header = append(header, 1 as int8)
    header = append(header, 0 as int8)
    header = append(header, 0 as int8)
    header = append(header, 0 as int8)
    
    // e_entry (对象文件为 0)
    i = 0
    for i < 8 {
        header = append(header, 0 as int8)
        i = i + 1
    }
    
    // e_phoff (程序头偏移，对象文件为 0)
    i = 0
    for i < 8 {
        header = append(header, 0 as int8)
        i = i + 1
    }
    
    // e_shoff (节头偏移)
    shoff := 64 as int64  // 假设节头在第 64 字节后
    i = 0
    for i < 8 {
        b := ((shoff >> (i * 8)) & 0xff) as int8
        header = append(header, b)
        i = i + 1
    }
    
    // e_flags
    header = append(header, 0 as int8)
    header = append(header, 0 as int8)
    header = append(header, 0 as int8)
    header = append(header, 0 as int8)
    
    // e_ehsize (ELF 文件头大小 = 64)
    header = append(header, 64 as int8)
    header = append(header, 0 as int8)
    
    // e_phentsize (程序头条目大小)
    header = append(header, 0 as int8)
    header = append(header, 0 as int8)
    
    // e_phnum (程序头条目数)
    header = append(header, 0 as int8)
    header = append(header, 0 as int8)
    
    // e_shentsize (节头条目大小 = 64)
    header = append(header, 64 as int8)
    header = append(header, 0 as int8)
    
    // e_shnum (节头条目数)
    shnum := len(gen.sections) as int8
    header = append(header, shnum)
    header = append(header, 0 as int8)
    
    // e_shstrndx (节头字符串表索引)
    header = append(header, 6 as int8)
    header = append(header, 0 as int8)
    
    header
}

// 添加符号
func (gen* go_style_elf_generator) add_symbol_entry(string name, int64 value, int64 size, int binding, int type) {
    gen.write_symbol(name, value, size, binding as int8, type as int8, 1 as int16)
}

// 生成完整的 ELF 对象文件
func (gen* go_style_elf_generator) generate_elf_object() []int8 {
    // 第 1 步：创建标准节
    gen.create_standard_sections()
    
    // 第 2 步：添加符号
    gen.add_symbol_entry("", 0 as int64, 0 as int64, 0, 0)  // NULL symbol
    gen.add_symbol_entry("main", 0 as int64, 0 as int64, 1, 2)  // GLOBAL FUNC
    
    // 第 3 步：生成 ELF 头
    elf_header := gen.create_elf_header()
    
    // 第 4 步：组合所有部分
    result := []int8()()
    result = append_bytes_into_result(result, elf_header)
    
    // 第 5 步：写入节数据
    result = append_bytes_into_result(result, gen.text_section)
    result = append_bytes_into_result(result, gen.data_section)
    result = append_bytes_into_result(result, gen.rodata_section)
    
    // 第 6 步：写入节头
    i := 0
    for i < len(gen.sections) {
        sec_header_bytes := section_header_to_bytes(gen.sections[i])
        result = append_bytes_into_result(result, sec_header_bytes)
        i = i + 1
    }
    
    // 第 7 步：写入符号表
    i = 0
    for i < len(gen.symbols) {
        sym_bytes := symbol_to_bytes(gen.symbols[i])
        result = append_bytes_into_result(result, sym_bytes)
        i = i + 1
    }
    
    // 第 8 步：写入字符串表
    strtab := string_table_to_bytes(gen.string_table)
    result = append_bytes_into_result(result, strtab)
    
    result
}

// 生成可执行文件（完整的 ELF 可执行文件）
func (gen* go_style_elf_generator) generate_elf_executable() []int8 {
    // 可执行文件生成过程与对象文件类似，但需要：
    // 1. 设置程序头（Program Headers）
    // 2. 链接多个对象文件
    // 3. 解决重定位
    // 4. 设置入口点
    
    // 这里简化为基本结构
    executable := gen.generate_elf_object()
    executable
}

// 辅助函数
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
    
    // sh_name
    name_bytes := int32_to_bytes(sec.name)
    result = append_bytes_into_result(result, name_bytes)
    
    // sh_type
    type_bytes := int32_to_bytes(sec.type)
    result = append_bytes_into_result(result, type_bytes)
    
    // sh_flags
    flags_bytes := int64_to_bytes(sec.flags)
    result = append_bytes_into_result(result, flags_bytes)
    
    // sh_addr
    addr_bytes := int64_to_bytes(sec.addr)
    result = append_bytes_into_result(result, addr_bytes)
    
    // sh_offset
    offset_bytes := int64_to_bytes(sec.offset)
    result = append_bytes_into_result(result, offset_bytes)
    
    // sh_size
    size_bytes := int64_to_bytes(sec.size)
    result = append_bytes_into_result(result, size_bytes)
    
    // sh_link
    link_bytes := int32_to_bytes(sec.link)
    result = append_bytes_into_result(result, link_bytes)
    
    // sh_info
    info_bytes := int32_to_bytes(sec.info)
    result = append_bytes_into_result(result, info_bytes)
    
    // sh_addralign
    addralign_bytes := int64_to_bytes(sec.addralign)
    result = append_bytes_into_result(result, addralign_bytes)
    
    // sh_entsize
    entsize_bytes := int64_to_bytes(sec.entsize)
    result = append_bytes_into_result(result, entsize_bytes)
    
    result
}

func symbol_to_bytes(elf_symbol sym) []int8 {
    result := []int8()()
    
    // st_name
    name_bytes := int32_to_bytes(sym.name)
    result = append_bytes_into_result(result, name_bytes)
    
    // st_info
    result = append(result, sym.info)
    
    // st_other
    result = append(result, sym.other)
    
    // st_shndx
    shndx_bytes := int16_to_bytes(sym.shndx)
    result = append_bytes_into_result(result, shndx_bytes)
    
    // st_value
    value_bytes := int64_to_bytes(sym.value)
    result = append_bytes_into_result(result, value_bytes)
    
    // st_size
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
