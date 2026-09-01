package compile.internal.codegen

enum reloc_type {
    reloc_type_abs,
    reloc_type_pc32,
    reloc_type_pc64,
    reloc_type_got,
    reloc_type_gotpc,
    reloc_type_plt32,
    reloc_type_pltoff64,
    reloc_type_pltgot,
}

struct relocation_entry {
    int64 offset
    reloc_type type
    string symbol
    int64 addend
    int32 rel_size
}

struct relocation_context {
    relocation_entry[] relocations
    string[] processed_symbols
}

func make_relocation_context() relocation_context {
    relocation_context {
        relocations: relocation_entry[](),
        processed_symbols: string[](),
    }
}

func (ctx* relocation_context) find_relocation(int64 offset) (relocation_entry*, bool) {
    i := 0
    for i < len(ctx.relocations) {
        if ctx.relocations[i].offset == offset {
            return &ctx.relocations[i], true
        }
        i = i + 1
    }
    nil, false
}

func (ctx* relocation_context) add_relocation(int64 offset, reloc_type type, string symbol, int64 addend, int32 size) string {
    existing, found := ctx.find_relocation(offset)
    if found {
        return "relocation already exists at offset"
    }
    
    rel := relocation_entry {
        offset: offset,
        type: type,
        symbol: symbol,
        addend: addend,
        rel_size: size,
    }
    
    ctx.relocations = append(ctx.relocations, rel)
    ""
}

func (rel* relocation_entry) encode_info(int32 sym_index) int64 {
    info := (sym_index as int64) << 32
    switch rel.type {
        case reloc_type_abs: return info + 1
        case reloc_type_pc32: return info + 2
        case reloc_type_pc64: return info + 24
        case reloc_type_got: return info + 6
        case reloc_type_gotpc: return info + 9
        case reloc_type_plt32: return info + 4
        case reloc_type_pltoff64: return info + 31
        case reloc_type_pltgot: return info + 50
    }
    info + 1
}

func reloc_type_name(reloc_type type) string {
    switch type {
        case reloc_type_abs: return "R_X86_64_64"
        case reloc_type_pc32: return "R_X86_64_PC32"
        case reloc_type_pc64: return "R_X86_64_PC64"
        case reloc_type_got: return "R_X86_64_GOT64"
        case reloc_type_gotpc: return "R_X86_64_GOTPC64"
        case reloc_type_plt32: return "R_X86_64_PLT32"
        case reloc_type_pltoff64: return "R_X86_64_PLTOFF64"
        case reloc_type_pltgot: return "R_X86_64_PLTGOT"
    }
    "UNKNOWN"
}

func (ctx* relocation_context) has_symbol_relocation(string symbol) bool {
    i := 0
    for i < len(ctx.relocations) {
        if ctx.relocations[i].symbol == symbol {
            return true
        }
        i = i + 1
    }
    false
}

func (ctx* relocation_context) get_symbol_relocations(string symbol) relocation_entry[] {
    result := relocation_entry[]()
    i := 0
    for i < len(ctx.relocations) {
        if ctx.relocations[i].symbol == symbol {
            result = append(result, ctx.relocations[i])
        }
        i = i + 1
    }
    result
}

func (ctx* relocation_context) dump() string {
    result := "Relocations:\n"
    i := 0
    for i < len(ctx.relocations) {
        rel := ctx.relocations[i]
        result = result + "  " + (rel.offset as string) + ": " + reloc_type_name(rel.type) + " -> " + rel.symbol + "\n"
        i = i + 1
    }
    result
}
