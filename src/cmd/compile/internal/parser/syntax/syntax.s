package compile.internal.syntax
import (
    "compile.internal.ast"
    "std"
    "std.fs"
)
struct parse_error {
    string message
    int line
    int column
}

func read_source(string path) string {
    ""
}

func tokenize(string source) (string[], parse_error) {
    empty := string[]()
    return empty, parse_error { message: "tokenizer not connected", line: 0, column: 0 }
}

func parse_source(string source) (ast.source_file, parse_error) {
    if len(source) < 8 || __host_slice(source, 0, 7) != "package" {
        empty := ast.source_file {}
        return empty, parse_error { message: "expected package declaration", line: 1, column: 1 }
    }
    line_end := 0
    for line_end < len(source) && __host_char_at(source, line_end) != "\n" {
        line_end = line_end + 1
    }
    header := __host_slice(source, 0, line_end)
    if len(header) < 9 || __host_slice(header, 7, 8) != " " {
        empty := ast.source_file {}
        return empty, parse_error { message: "expected package name", line: 1, column: 8 }
    }
    package_name := __host_slice(header, 8, len(header))
    if package_name == "" {
        empty := ast.source_file {}
        return empty, parse_error { message: "expected package name", line: 1, column: 9 }
    }
    if !contains_source_text(source, "func") {
        empty := ast.source_file {}
        return empty, parse_error { message: "expected function declaration", line: 1, column: 1 }
    }
    return ast.source_file {
        pkg: package_name,
        uses: ast.use_decl[](),
        items: ast.item[](),
        item_packages: string[](),
    }, parse_error {}
}

func contains_source_text(string source, string needle) bool {
    if needle == "" { return true }
    limit := len(source) - len(needle)
    i := 0
    for i <= limit {
        if __host_slice(source, i, i + len(needle)) == needle { return true }
        i = i + 1
    }
    false
}

func parse_tokens(string[] tokens) (ast.source_file, parse_error) {
    empty := ast.source_file {}
    return empty, parse_error { message: "parser not connected", line: 0, column: 0 }
}

func dump_tokens_text(string[] tokens) string {
    ""
}

func dump_source_text(ast.source_file source) string {
    ""
}
