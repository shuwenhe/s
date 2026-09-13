package compile.internal.build.emit
import (
    "s"
    "std"
    "std.io"
)
func check_ok(string path) () {
    std.io.println("ok: " + path)
}

func tokens(token[] tokens) () {
    std.io.println(s.dump_tokens(tokens))
}

func ast(source_file ast) () {
    std.io.println(s.dump_source_file(ast))
}

func built(string output) () {
    std.io.println("built: " + output)
}
