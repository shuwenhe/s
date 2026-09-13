package compile.internal.noder
use std.fs.write_text_file
use std.result.result
func write_export_file(string path, export_record[] exports) ((), noder_error) {
    switch write_text_file(path, emit_export_payload(exports)) {
        _ : (,
        err : make_error(code_write_failed(), err.message, path, 0, 0),
    }
}

func write_link_file(string path, string manifest) ((), noder_error) {
    switch write_text_file(path, manifest) {
        _ : (,
        err : make_error(code_write_failed(), err.message, path, 0, 0),
    }
}

func write_ir_file(string path, ir_node[] ir) ((), noder_error) {
    out := "ir version=1\n"
    i := 0
    for i < len(ir) {
        out = out + ir[i].op + " " + ir[i].payload + "\n"
        i = i + 1
    }
    switch write_text_file(path, out) {
        _ : (,
        err : make_error(code_write_failed(), err.message, path, 0, 0),
    }
}
