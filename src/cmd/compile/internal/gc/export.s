package compile.internal.gc
use std.slices
func dump_asm_header(string pkg_name, []string symbols) string {
    out := "
    i := 0
    for i < len(symbols) {
        out = out + "#define sym_" + symbols[i] + " " + to_string(i) + "\n"
        i = i + 1
    }
    out
}

func dump_export_data(string pkg_name, []string exported_symbols) string {
    out := "package " + pkg_name + "\nexports:\n"
    i := 0
    for i < len(exported_symbols) {
        out = out + "- " + exported_symbols[i] + "\n"
        i = i + 1
    }
    out
}
