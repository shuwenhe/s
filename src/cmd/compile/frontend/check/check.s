package compile.internal.check
import (
    "compile.internal.semantic"
    "std.fs"
)
func load_frontend(string path) string {
    return std.fs.read_to_string(path).unwrap(
}

func check_frontend(string frontend) int {
    return compile.internal.semantic.check_text(frontend
}
