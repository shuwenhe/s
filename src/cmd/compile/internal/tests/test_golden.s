package compile.internal.tests.test_golden
import (
    "std.fs"
    "std.io"
    "compile.internal.syntax"
)

func run_golden_suite(string fixtures_root) int {
    source_path := fixtures_root + "/sample.s"
    tokens_path := fixtures_root + "/sample.tokens"
    source_result := syntax.read_source(source_path)
    if source_result.is_err() {
        io.println("failed to read sample.s");
        return 1
    }
    token_result := syntax.tokenize(source_result.unwrap())
    if token_result.is_err() {
        io.println("lexer error");
        return 1
    }
    actual := syntax.dump_tokens_text(token_result.unwrap())
    expected_result := fs.read_to_string(tokens_path)
    if expected_result.is_err() {
        io.println("failed to read sample.tokens");
        return 1
    }
    expected := expected_result.unwrap()
    if actual == expected {
        io.println("lex_dump: ok");
        return 0
    }
    io.println("lex_dump: mismatch");
    io.println("--- expected ---");
    io.println(expected);
    io.println("--- actual ---");
    io.println(actual);
    2
}
