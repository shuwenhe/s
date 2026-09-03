package compile.internal.noder
use std.result.result
use std.slices
func compile_unit(string source_path, string export_out, string ir_out, string link_out) (noder_output, noder_error) {
    quirks := []string()
    quirks = append(quirks, "normalize-import-quotes")
    out := run_unified(source_path, quirks)?
    write_export_file(export_out, out.exports)?
    write_ir_file(ir_out, out.ir)?
    links := build_link_symbols(out.ast.pkg, out.exports)
    write_link_file(link_out, emit_link_manifest(links))?
    out
}

func compile_unit_default_paths(string source_path) (noder_output, noder_error) {
    compile_unit(source_path, source_path + ".export", source_path + ".ir", source_path + ".link")
}
