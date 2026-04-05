package compiler.tests

use std.result.Result
use std.vec.Vec
use compiler.GoldenCase
use compiler.GoldenFailure
use compiler.LexerCases
use compiler.ParserCases
use compiler.RunLexerCase
use compiler.RunParserCase

pub struct SuiteResult {
    passed: i32,
    failed: Vec[GoldenFailure],
}

pub fn run_golden_suite(fixtures_root: String) -> SuiteResult {
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

    SuiteResult {
        passed: passed,
        failed: failures,
    }
}
