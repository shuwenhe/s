package linker

struct relocation_context {
    section_index int
    symbol_index int
    relocation_type int
    offset int
    addend int
}

struct relocation_result {
    success int
    resolved_address int
    error_message string
}

func relocation_apply_64(int symbol_value, int offset, int addend) int {
    symbol_value + addend
}

func relocation_apply_pc32(int symbol_value, int offset, int addend) int {
    (symbol_value + addend) - offset
}

func relocation_resolve(relocation_context ctx*, int symbol_value, int load_base) relocation_result {
    result := relocation_result {
        success: 1,
        resolved_address: 0,
        error_message: ""
    }
    
    switch ctx.relocation_type {
        case R_X86_64_64:
            result.resolved_address = symbol_value + load_base + ctx.addend
            return result
        
        case R_X86_64_PC32:
            pc := load_base + ctx.offset
            result.resolved_address = (symbol_value + load_base) - pc + ctx.addend
            return result
        
        case R_X86_64_RELATIVE:
            result.resolved_address = load_base + ctx.addend
            return result
        
        default:
            result.success = 0
            result.error_message = "Unknown relocation type"
            return result
    }
    
    result
}

func relocation_get_type_name(int reloc_type) string {
    switch reloc_type {
        case R_X86_64_NONE:
            return "R_X86_64_NONE"
        case R_X86_64_64:
            return "R_X86_64_64"
        case R_X86_64_PC32:
            return "R_X86_64_PC32"
        case R_X86_64_RELATIVE:
            return "R_X86_64_RELATIVE"
        default:
            return "UNKNOWN"
    }
}

func relocation_is_absolute(int reloc_type) int {
    if reloc_type == R_X86_64_64 {
        return 1
    }
    if reloc_type == R_X86_64_RELATIVE {
        return 1
    }
    0
}

func relocation_is_relative(int reloc_type) int {
    if reloc_type == R_X86_64_PC32 {
        return 1
    }
    0
}

func relocation_is_plt(int reloc_type) int {
    if reloc_type == R_X86_64_PLT32 {
        return 1
    }
    0
}

func relocation_create_entry(int offset, int symbol_index, int reloc_type) elf64_relocation {
    info := (symbol_index << 32) | reloc_type
    reloc := elf64_relocation {
        offset: offset,
        info: info,
        addend: 0
    }
    reloc
}

func relocation_verify(elf64_relocation reloc, int num_symbols) int {
    sym_idx := (reloc.info >> 32) & 0xffffffff
    
    if sym_idx >= num_symbols {
        return 0
    }
    
    1
}
