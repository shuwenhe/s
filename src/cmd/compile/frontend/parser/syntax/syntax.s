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

func read_source(string path) (string, syntax_error) {
    result := std.fs.read_to_string(path)
    if result.is_err() {
        err := result.unwrap_err()
        return syntax_error {
            message: "failed to read source file: " + path + ": " + err.message, line: 0, column: 0,
        }
    }
    result.unwrap()
}

func tokenize(string source) (token[], syntax_error) {
    result := s.new_lexer(source).tokenize()
    if result.is_err() {
        err := result.unwrap_err()
        return syntax_error {
            message: err.message, line: err.line, column: err.column,
        }
    }
    result.unwrap()
}

func parse_source(string source) (source_file, syntax_error) {
    token_result := tokenize(source)
    if token_result.is_err() {
        err := token_result.unwrap_err()
        return syntax_error {
            message: err.message, line: err.line, column: err.column,
        }
    }
    parse_tokens(token_result.unwrap())
}

func parse_tokens(token[] tokens) (source_file, syntax_error) {
    result := s.parse_tokens(tokens)
    if result.is_err() {
        err := result.unwrap_err()
        return syntax_error {
            message: err.message, line: err.line, column: err.column,
        }
    }
    result.unwrap()
}

func dump_tokens_text(token[] tokens) string {
    s.dump_tokens(tokens)
}

func dump_source_text(source_file source) string {
    s.dump_source_file(source)
}
