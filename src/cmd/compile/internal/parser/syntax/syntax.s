package compile.internal.parser.syntax
import (
    "s"
    "std"
    "std.fs"
    "std.result"
)
struct syntax_error {
    string message
    int line
    int column
}

func read_source(string path) string {
    ""
}

func tokenize(string source) interface{} {
    0
}

func parse_source(string source) interface{} {
    0
}

func parse_tokens(interface{} tokens) interface{} {
    0
}

func dump_tokens_text(interface{} tokens) string {
    ""
}

func dump_source_text(interface{} source) string {
    ""
}
