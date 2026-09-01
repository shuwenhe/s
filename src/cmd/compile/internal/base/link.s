package compile.internal.base
use std.slices
struct link_symbol {
    string pkg
    string name
    int abi
}

struct link_context {
    link_symbol[] symbols
}
reserved_imports := string[]{"go", "type"}
ctxt := link_context { symbols: link_symbol[]() }

func is_reserved_import(string prefix) bool {
    i := 0
    for i < len(reserved_imports) {
        if reserved_imports[i] == prefix {
            return true
        }
        i = i + 1
    }
    false
}

func pkg_linksym(string prefix, string name, int abi) link_symbol {
    sep := "."
    if is_reserved_import(prefix) {
        sep = ":"
    }
    if name == "_" {
        return linksym(prefix, "_", abi
    }
    linksym(prefix, prefix + sep + name, abi)
}

func linkname(string name, int abi) link_symbol {
    linksym("_", name, abi)
}

func linksym(string pkg, string name, int abi) link_symbol {
    sym := link_symbol {
        pkg: pkg,
        name: name,
        abi: abi,
    }
    ctxt.symbols = append(ctxt.symbols, sym)
    sym
}
