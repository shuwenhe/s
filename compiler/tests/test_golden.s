package compiler.tests

use std.result.Result
use std.vec.Vec
use compiler.GoldenCase
use compiler.GoldenFailure
use compiler.lexer_cases
use compiler.parser_cases
use compiler.run_lexer_case
use compiler.run_parser_case

pub struct SuiteResult {
    passed: i32,
    failed: Vec[GoldenFailure],
}

pub fn run(fixtures_root: String) -> SuiteResult {
    let failures = Vec[GoldenFailure]()
    let passed = 0

    for case in lexer_cases(fixtures_root) {
        match run_lexer_case(case) {
            Result::Ok(()) => passed = passed + 1,
            Result::Err(err) => failures.push(err),
        }
    }

    for case in parser_cases(fixtures_root) {
        match run_parser_case(case) {
            Result::Ok(()) => passed = passed + 1,
            Result::Err(err) => failures.push(err),
        }
    }

    SuiteResult {
        passed: passed,
        failed: failures,
    }
}
