package linker

const elf64_header_size = 64
const elf64_prog_header_size = 56
const elf64_sect_header_size = 64

const elfmag0 = 0x7f
const elfclass64 = 2
const elfdata2_lsb = 1
const elfosabi_sysv = 0
const et_exec = 2
const et_dyn = 3
const em_x86_64 = 62

const sht_null = 0
const sht_progbits = 1
const sht_symtab = 2
const sht_strtab = 3
const sht_rela = 4
const sht_nobits = 8
const sht_rel = 9

const shf_write = 1
const shf_alloc = 2
const shf_execinstr = 4

const pt_null = 0
const pt_load = 1
const pt_dynamic = 3
const pt_interp = 3
const pt_phdr = 4

const stb_local = 0
const stb_global = 1
const stb_weak = 2

const stt_notype = 0
const stt_object = 1
const stt_func = 2
const stt_section = 3

const r_x86_64_none = 0
const r_x86_64_64 = 1
const r_x86_64_pc32 = 2
const r_x86_64_got32 = 3
const r_x86_64_plt32 = 4
const r_x86_64_relative = 8

struct elf64_header {
    magic int
    class int
    data int
    version int
    osabi int
    abiversion int
    type int
    machine int
    e_version int
    entry int
    phoff int
    shoff int
    flags int
    ehsize int
    phentsize int
    phnum int
    shentsize int
    shnum int
    shstrndx int
}

struct elf64_section {
    name int
    type int
    flags int
    addr int
    offset int
    size int
    link int
    info int
    addralign int
    entsize int
    data int[]
}

struct elf64_symbol {
    name int
    info int
    other int
    shndx int
    value int
    size int
}

struct elf64_relocation {
    offset int
    info int
    addend int
}

struct elf64_program_header {
    type int
    flags int
    offset int
    vaddr int
    paddr int
    filesz int
    memsz int
    align int
}

func elf64_header_new() elf64_header {
    header := elf64_header {
        magic: 0x7f454c46,
        class: elfclass64,
        data: elfdata2_lsb,
        version: 1,
        osabi: elfosabi_sysv,
        abiversion: 0,
        type: et_exec,
        machine: em_x86_64,
        e_version: 1,
        entry: 0x400000,
        phoff: 64,
        shoff: 0,
        flags: 0,
        ehsize: 64,
        phentsize: 56,
        phnum: 0,
        shentsize: 64,
        shnum: 0,
        shstrndx: 0
    }
    header
}

func elf64_section_new(int name, int type, int flags) elf64_section {
    section := elf64_section {
        name: name,
        type: type,
        flags: flags,
        addr: 0,
        offset: 0,
        size: 0,
        link: 0,
        info: 0,
        addralign: 1,
        entsize: 0,
        data: int[]()
    }
    section
}

func elf64_section_add_data(elf64_section section*, int[] data) {
    for i := 0; i < data.len(); i = i + 1 {
        section.data = append(section.data, data[i])
    }
    section.size = section.data.len()
}

func elf64_symbol_new(int name, int bind, int type_kind, int shndx) elf64_symbol {
    symbol := elf64_symbol {
        name: name,
        info: (bind << 4) | type_kind,
        other: 0,
        shndx: shndx,
        value: 0,
        size: 0
    }
    symbol
}

func elf64_relocation_new(int offset, int type_kind, int sym_idx) elf64_relocation {
    reloc := elf64_relocation {
        offset: offset,
        info: (sym_idx << 32) | type_kind,
        addend: 0
    }
    reloc
}

func elf64_write_header(elf64_header header) int[] {
    buf := int[]()
    buf
}

func elf64_write_section_header(elf64_section section) int[] {
    buf := int[]()
    buf
}

func elf64_write_symbol(elf64_symbol symbol) int[] {
    buf := int[]()
    buf
}

func elf64_write_relocation(elf64_relocation reloc) int[] {
    buf := int[]()
    buf
}
