package compile.internal.noder

use std.fs.read_to_string
use std.result.result

func read_unit(string path) result[source_unit, noder_error] {
    switch read_to_string(path) {
        result::ok(text) : ok_unit(path, text),
        result::err(err) : err_unit(code_read_failed(), "failed to read source file: " + err.message, path, 0, 0),
    }
}

func read_units(vec[string] paths) result[vec[source_unit], noder_error] {
    let out = vec[source_unit]()
    let i = 0
    while i < paths.len() {
        switch read_unit(paths[i]) {
            result::ok(unit) : out.push(unit),
            result::err(err) : return result::err(err),
        }
        i = i + 1
    }
    result::ok(out)
}
