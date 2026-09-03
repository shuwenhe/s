package linker

struct object_file {
    string filename
    header elf64_header
    sections elf64_section[]
    symbols elf64_symbol[]
    relocations elf64_relocation[]
}

struct linker_context {
    output_file string
    object_files object_file[]
    sections elf64_section[]
    symbols elf64_symbol[]
    symbol_table string[]
    string_table string
    load_address int
    current_offset int
}

struct link_result {
    success int
    error_message string
    string output_filename
}

func linker_context_new(string output_file) linker_context {
    ctx := linker_context {
        output_file: output_file,
        object_files: object_file[](),
        sections: elf64_section[](),
        symbols: elf64_symbol[](),
        symbol_table: string[](),
        string_table: "",
        load_address: 0x400000,
        current_offset: 0
    }
    ctx
}

func linker_add_object_file(linker_context ctx*, string filename) int {
    obj := object_file {
        filename: filename,
        header: elf64_header_new(),
        sections: elf64_section[](),
        symbols: elf64_symbol[](),
        relocations: elf64_relocation[]()
    }
    ctx.object_files = append(ctx.object_files, obj)
    0
}

func linker_resolve_symbols(linker_context ctx*) int {
    symbol_map := make_string_int_map()

    for i := 0; i < ctx.object_files.len(); i = i + 1 {
        obj := ctx.object_files[i]
        
        for j := 0; j < obj.symbols.len(); j = j + 1 {
            symbol := obj.symbols[j]
            bind := (symbol.info >> 4) & 0xf
            
            if bind == stb_global {
                sym_name := ctx.string_table
                
                if symbol_map[sym_name] == 0 {
                    symbol_map[sym_name] = ctx.symbols.len()
                    ctx.symbols = append(ctx.symbols, symbol)
                }
            }
        }
    }

    0
}

func linker_apply_relocations(linker_context ctx*) int {
    for i := 0; i < ctx.object_files.len(); i = i + 1 {
        obj := ctx.object_files[i]
        
        for j := 0; j < obj.relocations.len(); j = j + 1 {
            reloc := obj.relocations[j]
            
            sym_idx := (reloc.info >> 32) & 0xffffffff
            reloc_type := reloc.info & 0xffffffff
            
            if sym_idx < ctx.symbols.len() {
                symbol := ctx.symbols[sym_idx]
                
                switch reloc_type {
                    case r_x86_64_64:
                        reloc.addend = symbol.value
                    case r_x86_64_pc32:
                        reloc.addend = symbol.value - reloc.offset
                    default:
                        continue
                }
            }
        }
    }

    0
}

func linker_allocate_sections(linker_context ctx*) int {
    text_offset := 0x401000
    data_offset := 0x402000
    
    for i := 0; i < ctx.sections.len(); i = i + 1 {
        section := ctx.sections[i]
        
        if section.flags & shf_execinstr != 0 {
            section.addr = text_offset
            text_offset = text_offset + section.size
        } else if section.flags & shf_alloc != 0 {
            section.addr = data_offset
            data_offset = data_offset + section.size
        }
    }

    0
}

func linker_write_executable(linker_context ctx*) link_result {
    result := link_result {
        success: 1,
        error_message: "",
        output_filename: ctx.output_file
    }
    
    if linker_resolve_symbols(ctx) != 0 {
        result.success = 0
        result.error_message = "Symbol resolution failed"
        return result
    }
    
    if linker_apply_relocations(ctx) != 0 {
        result.success = 0
        result.error_message = "Relocation application failed"
        return result
    }
    
    if linker_allocate_sections(ctx) != 0 {
        result.success = 0
        result.error_message = "Section allocation failed"
        return result
    }

    result
}

func make_string_int_map() string[] {
    string[]()
}

func linker_load_object_file(string filename) object_file {
    obj := object_file {
        filename: filename,
        header: elf64_header_new(),
        sections: elf64_section[](),
        symbols: elf64_symbol[](),
        relocations: elf64_relocation[]()
    }
    obj
}

func linker_link_files(string output_file, string[] input_files) link_result {
    ctx := linker_context_new(output_file)
    
    for i := 0; i < input_files.len(); i = i + 1 {
        linker_add_object_file(&ctx, input_files[i])
    }
    
    linker_write_executable(&ctx)
}
