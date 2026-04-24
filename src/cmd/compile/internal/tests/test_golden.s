package compile.internal.tests.test_golden

use std.fs.read_to_string
use std.io.println
use compile.internal.syntax.read_source
use compile.internal.syntax.tokenize
use compile.internal.syntax.dump_tokens_text

func run_golden_suite(string fixtures_root) int {

    var source_path = fixtures_root + "/sample.s"
    var tokens_path = fixtures_root + "/sample.tokens"

    var source_result = read_source(source_path)
    if source_result.is_err() {
        println("failed to read sample.s");
        return 1
    }

    var token_result = tokenize(source_result.unwrap())
    if token_result.is_err() {
        println("lexer error");
        return 1
    }

    var actual = dump_tokens_text(token_result.unwrap())

    var expected_result = read_to_string(tokens_path)
    if expected_result.is_err() {
        println("failed to read sample.tokens");
        return 1
    }

    var expected = expected_result.unwrap()
    if actual == expected {
        println("lex_dump: ok");
        return 0
    }
    println("lex_dump: mismatch");
    println("--- expected ---");
    println(expected);
    println("--- actual ---");
    println(actual);
    2
}
