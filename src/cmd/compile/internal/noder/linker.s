package compile.internal.noder

use std.vec.vec

struct link_symbol {
    string pkg
    string name
    string kind
}

func build_link_symbols(string pkg_name, vec[export_record] exports) vec[link_symbol] {
    var out = vec[link_symbol]()
    var i = 0
    while i < exports.len() {
        out.push(link_symbol {
            pkg: pkg_name,
            name: pkg_name + "." + exports[i].name,
            kind: exports[i].kind,
        })
        i = i + 1
    }
    out
}

func emit_link_manifest(vec[link_symbol] syms) string {
    var out = "link-manifest version=1\n"
    var i = 0
    while i < syms.len() {
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

func build_link_symbols(string pkg_name, vec[export_record] exports) vec[link_symbol] {
    var out = vec[link_symbol]()
    var i = 0
    while i < exports.len() {
        out.push(link_symbol {
            pkg: pkg_name,
            name: pkg_name + "." + exports[i].name,
            kind: exports[i].kind,
        })
        i = i + 1
    }
    out
}

func emit_link_manifest(vec[link_symbol] syms) string {
    var out = "link-manifest version=1\n"
    var i = 0
    while i < syms.len() {
        out = out + syms[i].kind + " " + syms[i].name + "\n"
        i = i + 1
    }
    out
}
