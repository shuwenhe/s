package compile.internal.check

use compile.internal.semantic.check_text
use std.fs.read_to_string

func load_frontend(string path) string {
    return read_to_string(path).unwrap()
}

func check_frontend(string frontend) int {
    return check_text(frontend)
}
