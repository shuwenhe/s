package cmd
import (
    "compile.internal.syntax"
    "std.io"
    "std.result"
)
func main() {
    args := host_args()
    if len(args) < 2 {
        std.io.println("usage: ast_dump <path>");
        return 1
    }
    path := args[1]
    switch compile.internal.syntax.read_source(path) {
        result.err(err) : {
            std.io.println("error: " + err.message);
            return 1
        },
        result.ok(source) : {
            switch compile.internal.syntax.parse_source(source) {
                result.err(err2) : {
                    std.io.println("error: " + err2.message);
                    return 1
                },
                result.ok(ast) : {
                    std.io.println(compile.internal.syntax.dump_source_text(ast));
                    return 0
                },
            }
        },
    }
}
