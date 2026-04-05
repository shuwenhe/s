package compiler.tests

use std.result.Result
use std.vec.Vec
use compiler.GoldenCase
use compiler.GoldenFailure
use compiler.LexerCases
use compiler.ParserCases
use compiler.RunLexerCase
use compiler.RunParserCase

struct suiteResult {
    passed: i32,
    failed: Vec[GoldenFailure],
}

pub fn RunGoldenSuite(fixtures_root: String) -> suiteResult {
    let failures = Vec[GoldenFailure]()
    let passed = 0

    for case in LexerCases(fixtures_root) {
        match RunLexerCase(case) {
            Result::Ok(()) => passed = passed + 1,
            Result::Err(err) => failures.push(err),
        }
    }

    for case in ParserCases(fixtures_root) {
        match RunParserCase(case) {
            Result::Ok(()) => passed = passed + 1,
            Result::Err(err) => failures.push(err),
        }
    }

    suiteResult {
        passed: passed,
        failed: failures,
    }
}
