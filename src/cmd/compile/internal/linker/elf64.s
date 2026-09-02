package linker

const ELF64_HEADER_SIZE = 64
const ELF64_PROG_HEADER_SIZE = 56
const ELF64_SECT_HEADER_SIZE = 64

const ELFMAG0 = 0x7f
const ELFCLASS64 = 2
const ELFDATA2LSB = 1
const ELFOSABI_SYSV = 0
const ET_EXEC = 2
const ET_DYN = 3
const EM_X86_64 = 62

const SHT_NULL = 0
const SHT_PROGBITS = 1
const SHT_SYMTAB = 2
const SHT_STRTAB = 3
const SHT_RELA = 4
const SHT_NOBITS = 8
const SHT_REL = 9

const SHF_WRITE = 1
const SHF_ALLOC = 2
const SHF_EXECINSTR = 4

const PT_NULL = 0
const PT_LOAD = 1
const PT_DYNAMIC = 3
const PT_INTERP = 3
const PT_PHDR = 4

const STB_LOCAL = 0
const STB_GLOBAL = 1
const STB_WEAK = 2

const STT_NOTYPE = 0
const STT_OBJECT = 1
const STT_FUNC = 2
const STT_SECTION = 3

const R_X86_64_NONE = 0
const R_X86_64_64 = 1
const R_X86_64_PC32 = 2
const R_X86_64_GOT32 = 3
const R_X86_64_PLT32 = 4
const R_X86_64_RELATIVE = 8

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
        class: ELFCLASS64,
        data: ELFDATA2LSB,
        version: 1,
        osabi: ELFOSABI_SYSV,
        abiversion: 0,
        type: ET_EXEC,
        machine: EM_X86_64,
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
