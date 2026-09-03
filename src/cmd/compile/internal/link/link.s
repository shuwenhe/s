package compile.internal.link
enum sym_type {
    sym_type_text,
    sym_type_data,
    sym_type_bss,
    sym_type_rodata,
    sym_type_extern,
}
struct link_sym {
    string name
    sym_type type
    int64 size
    int64 value
    []int8 data
    link_reloc[] relocs
    bool is_defined
}

struct link_reloc {
    int64 offset
    int64 size
    string target_sym
    int64 add_end
}

struct link_context {
    link_sym[] symbols
    []string symbol_names
    int64 text_size
    int64 data_size
    int64 bss_size
}

func make_link_context() link_context {
    link_context {
        symbols: link_sym[](), symbol_names []string(), text_size 0, data_size 0, bss_size 0,
    }
}

func (ctx* link_context) lookup_symbol(string name) (link_sym*, bool) {
    i := 0
    for i < len(ctx.symbol_names) {
        if ctx.symbol_names[i] == name {
            return &ctx.symbols[i], true
        }
        i = i + 1
    }
    nil, false
}

func (ctx* link_context) create_symbol(string name, sym_type type) (link_sym*, string) {
    existing, found := ctx.lookup_symbol(name)
    if found {
        return existing, "symbol already exists"
    }
    sym := link_sym {
        name: name, type type, size 0, value 0,
        data: []int8()(), relocs link_reloc[](), is_defined false,
    }
    ctx.symbols = append(ctx.symbols, sym)
    ctx.symbol_names = append(ctx.symbol_names, name)
    return &ctx.symbols[len(ctx.symbols) - 1], ""
}

func (ctx* link_context) allocate_text(int64 size) int64 {
    prev := ctx.text_size
    ctx.text_size = ctx.text_size + size
    prev
}

func (ctx* link_context) allocate_data(int64 size) int64 {
    prev := ctx.data_size
    ctx.data_size = ctx.data_size + size
    prev
}

func (ctx* link_context) add_relocation(string sym_name, int64 offset, int64 size, string target, int64 add) string {
    sym, found := ctx.lookup_symbol(sym_name)
    if !found {
        return "symbol not found"
    }
    reloc := link_reloc {
        offset: offset, size size, target_sym target, add_end add,
    }
    sym.relocs = append(sym.relocs, reloc)
    ""
}
