package compile.internal.obj
use compile.internal.codegen
struct elf_output {
    elf_writer writer
    elf_section_header[] sections
    elf_symbol[] symbols
    int32[] section_offsets
    string string_table
}

func make_elf_output() elf_output {
    elf_output {
        writer: make_elf_writer(elf_machine_x86_64),
        sections: elf_section_header[]()(),
        symbols: elf_symbol[]()(),
        section_offsets: int32[]()(),
        string_table: "",
    }
}

func (out* elf_output) add_string_to_table(string s) int32 {
    result := len(out.string_table) as int32
    out.string_table = out.string_table + s + "\x00"
    result
}

func (out* elf_output) create_section(string name, int32 type, int64 flags, int64 size) {
    section := elf_section_header {
        name: out.add_string_to_table(name), type type, flags flags, addr 0 as int64, offset 0 as int64, size size, link 0 as int32, info 0 as int32, addralign 8 as int64, entsize 0 as int64,
    }
    out.sections = append(out.sections, section)
}

func (out* elf_output) build_standard_sections() {
    out.create_section("", 0 as int32, 0 as int64, 0 as int64)
    out.create_section(".text", 1 as int32, 6 as int64, 0 as int64)
    out.create_section(".data", 1 as int32, 3 as int64, 0 as int64)
    out.create_section(".bss", 8 as int32, 3 as int64, 0 as int64)
    out.create_section(".rodata", 1 as int32, 2 as int64, 0 as int64)
    out.create_section(".symtab", 2 as int32, 0 as int64, 0 as int64)
    out.create_section(".strtab", 3 as int32, 0 as int64, 0 as int64)
    out.create_section(".shstrtab", 3 as int32, 0 as int64, 0 as int64)
}

func (out* elf_output) add_symbol(string name, int64 value, int64 size, int8 info, int16 shndx) {
    sym := elf_symbol {
        name: out.add_string_to_table(name), info info, other 0 as int8, shndx shndx, value value, size size,
    }
    out.symbols = append(out.symbols, sym)
}

func (out* elf_output) write_elf_file() int8[] {
    result := int8[]()()
    out.writer.write_elf_header(elf_machine_x86_64)
    result = out.writer.get_data()
    result
}

struct object_file_generator {
    machine_code_gen* code_gen
    symbol_table* symbols
    relocation_context* relocs
    elf_output elf_out
}

func make_object_file_generator(machine_code_gen* cg, symbol_table* st, relocation_context* rc) object_file_generator {
    obj_file_generator {
        code_gen: cg, symbols st, relocs rc, elf_out make_elf_output(),
    }
}

func (gen* object_file_generator) generate() int8[] {
    gen.elf_out.build_standard_sections()
    code := gen.code_gen.get_code()
    gen.elf_out.add_symbol("", 0 as int64, 0 as int64, 0 as int8, 0 as int16)
    i := 0
    for i < gen.symbols.count_symbols() {
        sym := gen.symbols.entries[i]
        info := sym.encode_info()
        gen.elf_out.add_symbol(sym.name, sym.value, sym.size, info, 1 as int16)
        i = i + 1
    }
    return gen.elf_out.write_elf_file()
}

func (gen* object_file_generator) dump_info() string {
    result := "Object File Info:\n"
    result = result + "  Code Size: " + (len(gen.code_gen.get_code()) as string) + " bytes\n"
    result = result + "  Symbols: " + (gen.symbols.count_symbols() as string) + "\n"
    result = result + "  Relocations: " + (len(gen.relocs.relocations) as string) + "\n"
    result = result + "\n" + gen.symbols.dump()
    result = result + "\n" + gen.relocs.dump()
    result
}
