package src.cmd.link.internal.ld

const s_obj_elf = 1
const s_obj_macho = 2
const s_obj_pe = 3
const s_obj_wasm = 4

const s_sym_local = 0
const s_sym_global = 1
const s_sym_weak = 2

const s_vis_default = 0
const s_vis_internal = 1
const s_vis_hidden = 2
const s_vis_protected = 3

const s_reloc_abs64 = 1
const s_reloc_pcrel32 = 2
const s_reloc_got64 = 3
const s_reloc_plt32 = 4
const s_reloc_tls_le64 = 5
const s_reloc_tls_ie64 = 6

struct s_obj_section {
    string name
    int kind
    int flags
    int align
    u8[] data
}

struct s_obj_symbol {
    string name
    int value
    int size
    int binding
    int visibility
    int section
    int comdat
}

struct s_obj_reloc {
    int section
    int offset
    int kind
    int symbol
    int addend
}

struct s_object {
    int format
    int machine
    s_obj_section[] sections
    s_obj_symbol[] symbols
    s_obj_reloc[] relocs
}

struct s_link_layout {
    int got_base
    int plt_base
    int tls_base
    int got_count
    int plt_count
    int tls_size
}

func s_obj_empty() s_object {
    s_object {
        format: s_obj_elf,
        machine: 62,
        sections: s_obj_section[] {},
        symbols: s_obj_symbol[] {},
        relocs: s_obj_reloc[] {}
    }
}

func s_obj_add_section(s_object* obj, string name, int kind, int flags, int align, u8[] data) int {
    index := obj.sections.len()
    obj.sections = append(obj.sections, s_obj_section { name: name, kind: kind, flags: flags, align: align, data: data })
    index
}

func s_obj_add_symbol(s_object* obj, s_obj_symbol sym) int {
    index := obj.symbols.len()
    obj.symbols = append(obj.symbols, sym)
    index
}

func s_obj_add_reloc(s_object* obj, s_obj_reloc reloc) () {
    obj.relocs = append(obj.relocs, reloc)
}

func s_obj_u16(u8[] data, int at) int {
    int(data[at]) | (int(data[at + 1]) << 8)
}

func s_obj_u32(u8[] data, int at) int {
    s_obj_u16(data, at) | (s_obj_u16(data, at + 2) << 16)
}

func s_obj_put_u16(u8[] data, int at, int value) () {
    data[at] = u8(value)
    data[at + 1] = u8(value >> 8)
}

func s_obj_put_u32(u8[] data, int at, int value) () {
    s_obj_put_u16(data, at, value)
    s_obj_put_u16(data, at + 2, value >> 16)
}

func s_obj_put_u64(u8[] data, int at, int value) () {
    s_obj_put_u32(data, at, value)
    s_obj_put_u32(data, at + 4, value >> 32)
}

func s_elf_read_rel_object(u8[] data) (s_object, int) {
    obj := s_obj_empty()
    if data.len() < 64 || data[0] != 0x7f || data[1] != 69 || data[2] != 76 || data[3] != 70 {
        obj.format = 0
        obj, 0
    }
    if data[4] != 2 || data[5] != 1 || s_obj_u32(data, 20) != 1 {
        obj.format = 0
        obj, 0
    }
    if s_obj_u16(data, 16) != 1 {
        obj.format = 0
        obj, 0
    }
    obj.machine = s_obj_u16(data, 18)
    shoff := s_obj_u32(data, 40)
    shentsize := s_obj_u16(data, 58)
    shnum := s_obj_u16(data, 60)
    if shentsize < 64 || shoff < 0 || shoff + shentsize * shnum > data.len() {
        obj.format = 0
        obj, 0
    }
    for i := 0; i < shnum; i = i + 1 {
        at := shoff + i * shentsize
        offset := s_obj_u32(data, at + 24)
        size := s_obj_u32(data, at + 32)
        if offset < 0 || size < 0 || offset + size > data.len() {
            obj.format = 0
            obj, 0
        }
        bytes := u8[] {}
        for j := 0; j < size; j = j + 1 {
            bytes = append(bytes, data[offset + j])
        }
        obj.sections = append(obj.sections, s_obj_section { kind: s_obj_u32(data, at + 4), flags: s_obj_u32(data, at + 8), align: s_obj_u32(data, at + 48), data: bytes })
    }
    obj, 1
}

func s_elf_write_rel_header(int machine, int shoff, int shnum, int shstrndx) u8[] {
    header := new u8[64]
    header[0] = 0x7f
    header[1] = 69
    header[2] = 76
    header[3] = 70
    header[4] = 2
    header[5] = 1
    header[6] = 1
    s_obj_put_u16(header, 16, 1)
    s_obj_put_u16(header, 18, machine)
    s_obj_put_u32(header, 20, 1)
    s_obj_put_u64(header, 40, shoff)
    s_obj_put_u16(header, 52, 64)
    s_obj_put_u16(header, 58, 64)
    s_obj_put_u16(header, 60, shnum)
    s_obj_put_u16(header, 62, shstrndx)
    header
}

func s_obj_find_symbol(s_obj_symbol[] symbols, string name) int {
    for i := 0; i < symbols.len(); i = i + 1 {
        if symbols[i].name == name { i }
    }
    -1
}

func s_obj_merge_symbol(s_obj_symbol[] symbols, s_obj_symbol candidate) int {
    old := s_obj_find_symbol(symbols, candidate.name)
    if old < 0 { old }
    if symbols[old].binding == s_sym_weak && candidate.binding != s_sym_weak {
        old
    } else if symbols[old].binding != s_sym_weak && candidate.binding == s_sym_weak {
        old
    } else if candidate.comdat != 0 {
        old
    } else {
        old
    }
}

func s_obj_merge_into(s_object* obj, s_obj_symbol candidate) int {
    old := s_obj_find_symbol(obj.symbols, candidate.name)
    if old < 0 {
        obj.symbols = append(obj.symbols, candidate)
        obj.symbols.len() - 1
    }
    current := obj.symbols[old]
    if current.binding == s_sym_weak && candidate.binding != s_sym_weak {
        obj.symbols[old] = candidate
    } else if current.binding == s_sym_local && candidate.binding != s_sym_local {
        obj.symbols[old] = candidate
    } else if current.comdat == 0 && candidate.comdat != 0 {
        obj.symbols[old] = candidate
    }
    old
}

func s_obj_exportable(s_obj_symbol sym) bool {
    if sym.binding == s_sym_local || sym.visibility == s_vis_hidden || sym.visibility == s_vis_internal { false }
    true
}

func s_obj_layout_new() s_link_layout {
    s_link_layout { got_base: 0, plt_base: 0, tls_base: 0, got_count: 0, plt_count: 0, tls_size: 0 }
}

func s_obj_got_entry(s_link_layout* layout, int symbol) int {
    index := layout.got_base + layout.got_count * 8
    layout.got_count = layout.got_count + 1
    index
}

func s_obj_plt_entry(s_link_layout* layout, int symbol) int {
    index := layout.plt_base + layout.plt_count * 16
    layout.plt_count = layout.plt_count + 1
    index
}

func s_obj_tls_alloc(s_link_layout* layout, int size, int align) int {
    value := layout.tls_base + layout.tls_size
    if align > 1 {
        value = (value + align - 1) & (0 - align)
    }
    layout.tls_size = value + size - layout.tls_base
    value
}

func s_obj_apply_reloc(u8[] data, int offset, int kind, int symbol_value, int addend) int {
    if offset < 0 || offset + 8 > data.len() { 0 }
    value := symbol_value + addend
    if kind == s_reloc_pcrel32 || kind == s_reloc_plt32 { value = value - offset }
    if kind == s_reloc_tls_le64 || kind == s_reloc_tls_ie64 { value = value + addend }
    if kind == s_reloc_pcrel32 || kind == s_reloc_plt32 {
        s_obj_put_u32(data, offset, value)
    } else {
        s_obj_put_u64(data, offset, value)
    }
    1
}

func s_obj_probe_format(u8[] data) int {
    if data.len() >= 4 && data[0] == 0x7f && data[1] == 69 && data[2] == 76 && data[3] == 70 { s_obj_elf }
    if data.len() >= 4 && data[0] == 0xcf && data[1] == 0xfa && data[2] == 0xed && data[3] == 0xfe { s_obj_macho }
    if data.len() >= 2 && data[0] == 77 && data[1] == 90 { s_obj_pe }
    if data.len() >= 4 && data[0] == 0x00 && data[1] == 0x61 && data[2] == 0x73 && data[3] == 0x6d { s_obj_wasm }
    0
}

func s_obj_format_ready(int format) bool {
    format == s_obj_elf || format == s_obj_macho || format == s_obj_pe || format == s_obj_wasm
}

struct s_build_id {
    u8[] bytes
}

func s_build_id_for(u8[] data) s_build_id {
    a := 2166136261
    b := 16777619
    for i := 0; i < data.len(); i = i + 1 {
        a = (a ^ int(data[i])) * 16777619
        b = (b + int(data[i]) + i) * 2166136261
    }
    result := u8[] {}
    for i := 0; i < 5; i = i + 1 {
        result = append(result, u8(a >> (i * 8)))
        result = append(result, u8(b >> (i * 8)))
    }
    s_build_id { bytes: result }
}

struct s_dwarf_range {
    int start
    int length
    string file
    int line
}

struct s_unwind_entry {
    int start
    int length
    int cfa_register
    int cfa_offset
    u8[] instructions
}

func s_dwarf_line_program(s_dwarf_range[] ranges) u8[] {
    data := u8[] {}
    for i := 0; i < ranges.len(); i = i + 1 {
        item := ranges[i]
        data = append(data, u8(item.start), u8(item.start >> 8), u8(item.start >> 16), u8(item.start >> 24))
        data = append(data, u8(item.length), u8(item.length >> 8), u8(item.length >> 16), u8(item.length >> 24))
        data = append(data, u8(item.line), u8(item.line >> 8), u8(item.line >> 16), u8(item.line >> 24))
    }
    data
}

func s_unwind_cfi(int cfa_register, int cfa_offset) u8[] {
    
    data := u8[] { 0x0c, u8(cfa_register), u8(cfa_offset) }
    data
}

func s_unwind_add(s_unwind_entry[] entries, int start, int length, int reg, int offset) s_unwind_entry[] {
    entries = append(entries, s_unwind_entry {
        start: start,
        length: length,
        cfa_register: reg,
        cfa_offset: offset,
        instructions: s_unwind_cfi(reg, offset)
    })
    entries
}
