package compile.internal.noder
use std.slices

struct link_symbol {
    string pkg
    string name
    string kind
}

func build_link_symbols(string pkg_name, export_record[] exports) link_symbol[] {
    out := link_symbol[]()
    i := 0
    for i < len(exports) {
        out.push(link_symbol {
            pkg: pkg_name,
            name: pkg_name + "." + exports[i].name,
            kind: exports[i].kind,
        })
        i = i + 1
    }
    out
}

func emit_link_manifest(link_symbol[] syms) string {
    out := "link-manifest version=1\n"
    i := 0
    for i < len(syms) {
        out = out + syms[i].kind + " " + syms[i].name + "\n"
        i = i + 1
    }
    out
}

struct link_symbol {
    string pkg
    string name
    string kind
}

func build_link_symbols(string pkg_name, export_record[] exports) link_symbol[] {
    out := link_symbol[]()
    i := 0
    for i < len(exports) {
        out.push(link_symbol {
            pkg: pkg_name,
            name: pkg_name + "." + exports[i].name,
            kind: exports[i].kind,
        })
        i = i + 1
    }
    out
}

func emit_link_manifest(link_symbol[] syms) string {
    out := "link-manifest version=1\n"
    i := 0
    for i < len(syms) {
        out = out + syms[i].kind + " " + syms[i].name + "\n"
        i = i + 1
    }
    out
}
