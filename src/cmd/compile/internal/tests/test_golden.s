package compile.internal.tests.test_golden

use std.fs.ReadToString
use std.io.println
use compile.internal.syntax.ReadSource
use compile.internal.syntax.Tokenize
use compile.internal.syntax.DumpTokensText

func RunGoldenSuite(string fixtures_root) int32 {
    // Expect fixturesRoot to contain sample.s and sample.tokens
    var source_path = fixtures_root + "/sample.s"
    var tokens_path = fixtures_root + "/sample.tokens"

    var source_result = ReadSource(source_path)
    if source_result.is_err() {
        println("failed to read sample.s");
        return 1
    }

    var token_result = Tokenize(source_result.unwrap())
    if token_result.is_err() {
        println("lexer error");
        return 1
    }

    var actual = DumpTokensText(token_result.unwrap())

    var expected_result = ReadToString(tokens_path)
    if expected_result.is_err() {
        println("failed to read sample.tokens");
        return 1
    }

    var expected = expected_result.unwrap()
    if actual == expected {
        println("lexDump: OK");
        return 0
    }
    println("lexDump: MISMATCH");
    println("--- expected ---");
    println(expected);
    println("--- actual ---");
    println(actual);
    2
}
