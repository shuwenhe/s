package compile.internal.noder
use std.fs.read_to_string
use std.result.result
func read_unit(string path) (source_unit, noder_error) {
    switch read_to_string(path) {
        text : ok_unit(path, text),
        err : err_unit(code_read_failed(), "failed to read source file: " + err.message, path, 0, 0),
    }
}

func read_units([]string paths) (source_unit[], noder_error) {
    out := source_unit[]()
    i := 0
    for i < len(paths) {
        switch read_unit(paths[i]) {
            unit : out = append(out, unit),
            err : return err,
        }
        i = i + 1
    }
    out
}
