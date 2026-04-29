package compile.internal.noder

use std.fs.write_text_file
use std.result.result

func write_export_file(string path, vec[export_record] exports) result[(), noder_error] {
    switch write_text_file(path, emit_export_payload(exports)) {
        result::ok(_) : result::ok(()),
        result::err(err) : result::err(make_error(code_write_failed(), err.message, path, 0, 0)),
    }
}

func write_link_file(string path, string manifest) result[(), noder_error] {
    switch write_text_file(path, manifest) {
        result::ok(_) : result::ok(()),
        result::err(err) : result::err(make_error(code_write_failed(), err.message, path, 0, 0)),
    }
}

func write_ir_file(string path, vec[ir_node] ir) result[(), noder_error] {
    let out = "ir version=1\n"
    let i = 0
    while i < ir.len() {
        out = out + ir[i].op + " " + ir[i].payload + "\n"
        i = i + 1
    }
    switch write_text_file(path, out) {
        result::ok(_) : result::ok(()),
        result::err(err) : result::err(make_error(code_write_failed(), err.message, path, 0, 0)),
    }
}
