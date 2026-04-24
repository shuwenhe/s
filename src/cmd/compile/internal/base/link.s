package compile.internal.base

use std.vec.vec

struct link_symbol {
    string pkg
    string name
    int abi
}

struct link_context {
    vec[link_symbol] symbols
}

var reserved_imports = vec[string]{"go", "type"}
var ctxt = link_context { symbols: vec[link_symbol]() }

func is_reserved_import(string prefix) bool {
    var i = 0
    while i < reserved_imports.len() {
        if reserved_imports[i] == prefix {
            return true
        }
        i = i + 1
    }
    false
}

func pkg_linksym(string prefix, string name, int abi) link_symbol {
    var sep = "."
    if is_reserved_import(prefix) {
        sep = ":"
    }
    if name == "_" {
        return linksym(prefix, "_", abi)
    }
    linksym(prefix, prefix + sep + name, abi)
}

func linkname(string name, int abi) link_symbol {
    linksym("_", name, abi)
}

func linksym(string pkg, string name, int abi) link_symbol {
    var sym = link_symbol {
        pkg: pkg,
        name: name,
        abi: abi,
    }
    ctxt.symbols.push(sym)
    sym
}
