package compile.internal.gc
use std.vec.vec

func dump_asm_header(string pkg_name, vec[string] symbols) string {
    out := "
    i := 0
    while i < symbols.len() {
        out = out + "#define sym_" + symbols[i] + " " + to_string(i) + "\n"
        i = i + 1
    }
    out
}

func dump_export_data(string pkg_name, vec[string] exported_symbols) string {
    out := "package " + pkg_name + "\nexports:\n"
    i := 0
    while i < exported_symbols.len() {
        out = out + "- " + exported_symbols[i] + "\n"
        i = i + 1
    }
    out
}
