package compile.internal.obj
use compile.internal.link
enum symbol_bind {
    symbol_bind_local,
    symbol_bind_global,
    symbol_bind_weak,
}
enum symbol_type {
    symbol_type_notype,
    symbol_type_object,
    symbol_type_func,
    symbol_type_section,
    symbol_type_file,
}
struct symbol_entry {
    string name
    symbol_bind bind
    symbol_type type
    int64 value
    int64 size
    int section_index
    bool defined
}

struct symbol_table {
    symbol_entry[] entries
    []string names
    int64 string_table_offset
}

func make_symbol_table() symbol_table {
    symbol_table {
        entries: symbol_entry[](), names []string(), string_table_offset 0,
    }
}

func (st* symbol_table) add_symbol(string name, symbol_bind bind, symbol_type type, int64 value, int64 size, int section_idx) int {
    entry := symbol_entry {
        name: name, bind bind, type type, value value, size size, section_index section_idx, defined true,
    }
    st.entries = append(st.entries, entry)
    st.names = append(st.names, name)
    len(st.entries) - 1
}

func (st* symbol_table) lookup_symbol(string name) (symbol_entry*, bool) {
    i := 0
    for i < len(st.names) {
        if st.names[i] == name {
            return &st.entries[i], true
        }
        i = i + 1
    }
    nil, false
}

func (st* symbol_table) get_symbol_index(string name) (int, bool) {
    i := 0
    for i < len(st.names) {
        if st.names[i] == name {
            return i, true
        }
        i = i + 1
    }
    0, false
}

func (st* symbol_table) count_symbols() int {
    len(st.entries)
}

func (st* symbol_table) get_string_table_size() int64 {
    total := 0 as int64
    i := 0
    for i < len(st.names) {
        total = total + (len(st.names[i]) as int64) + 1
        i = i + 1
    }
    total
}

func symbol_bind_value(symbol_bind b) int8 {
    switch b {
        case symbol_bind_local: return 0 as int8
        case symbol_bind_global: return 1 as int8
        case symbol_bind_weak: return 2 as int8
    }
    0 as int8
}

func symbol_type_value(symbol_type t) int8 {
    switch t {
        case symbol_type_notype: return 0 as int8
        case symbol_type_object: return 1 as int8
        case symbol_type_func: return 2 as int8
        case symbol_type_section: return 3 as int8
        case symbol_type_file: return 4 as int8
    }
    0 as int8
}

func (se* symbol_entry) encode_info() int8 {
    bind := symbol_bind_value(se.bind)
    type_val := symbol_type_value(se.type)
    ((bind << 4) + type_val) as int8
}

func (st* symbol_table) dump() string {
    result := "Symbol Table:\n"
    i := 0
    for i < len(st.entries) {
        sym := st.entries[i]
        result = result + "  " + sym.name + ": value=" + (sym.value as string) + ", size=" + (sym.size as string) + "\n"
        i = i + 1
    }
    result
}

func (st* symbol_table) encode_elf_symbols() []elf_symbol {
    result := []elf_symbol()()
    null_sym := elf_symbol {
        name: 0 as int32, info 0 as int8, other 0 as int8, shndx 0 as int16, value 0 as int64, size 0 as int64,
    }
    result = append(result, null_sym)
    i := 0
    for i < len(st.entries) {
        entry := st.entries[i]
        sym := elf_symbol {
            name: (i as int32) + 1, info entry.encode_info(), other 0 as int8,
            shndx: (entry.section_index as int16), value entry.value, size entry.size,
        }
        result = append(result, sym)
        i = i + 1
    }
    result
}
