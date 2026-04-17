package compile.internal.tests.test_golden

use std.fs.ReadToString
use std.result.Result
use compile.internal.syntax.ReadSource
use compile.internal.syntax.Tokenize
use compile.internal.syntax.DumpTokensText

func RunGoldenSuite(String fixtures_root) -> i32 {
    // Expect fixtures_root to contain sample.s and sample.tokens
    var source_path = fixtures_root + "/sample.s"
    var tokens_path = fixtures_root + "/sample.tokens"

    match ReadSource(source_path) {
        Result::Err(err) => {
            println("failed to read sample.s: " + err.message)
            return 1
        }
        Result::Ok(source) => {
            match Tokenize(source) {
                Result::Err(err2) => {
                    println("lexer error: " + err2.message)
                    return 1
                }
                Result::Ok(tokens) => {
                    var actual = DumpTokensText(tokens)
                    match ReadToString(tokens_path) {
                        Result::Err(err3) => {
                            println("failed to read sample.tokens: " + err3.message)
                            return 1
                        }
                        Result::Ok(expected_raw) => {
                            var expected = expected_raw.trim()
                            if actual.trim() == expected {
                                println("lex_dump: OK")
                                return 0
                            }
                            println("lex_dump: MISMATCH")
                            println("--- expected ---")
                            println(expected)
                            println("--- actual ---")
                            println(actual)
                            return 2
                        }
                    }
                }
            }
        }
    }
}
