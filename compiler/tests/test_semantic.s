package compiler.tests

use std.fs.read_to_string
use std.option.Option
use std.result.Result
use std.vec.Vec
use compiler.check_source
use compiler.load_prelude
use compiler.lookup_builtin_type
use frontend.parse_source

pub struct SemanticCase {
    name: String,
    path: String,
    should_pass: bool,
    expected_message: Option[String],
}

pub struct SemanticFailure {
    name: String,
    message: String,
}

pub fn semantic_cases(fixtures_root: String) -> Vec[SemanticCase] {
    Vec[SemanticCase] {
        SemanticCase {
            name: "check_ok",
            path: fixtures_root + "/check_ok.s",
            should_pass: true,
            expected_message: Option::None,
        },
        SemanticCase {
            name: "check_fail",
            path: fixtures_root + "/check_fail.s",
            should_pass: false,
            expected_message: Option::Some("let value expected bool, got i32"),
        },
        SemanticCase {
            name: "borrow_fail",
            path: fixtures_root + "/borrow_fail.s",
            should_pass: false,
            expected_message: Option::Some("use of moved value text"),
        },
        SemanticCase {
            name: "generic_bound_fail",
            path: fixtures_root + "/generic_bound_fail.s",
            should_pass: false,
            expected_message: Option::Some("type String does not satisfy bound Copy"),
        },
        SemanticCase {
            name: "member_method_sample",
            path: fixtures_root + "/member_method_sample.s",
            should_pass: true,
            expected_message: Option::None,
        },
        SemanticCase {
            name: "prelude_methods_ok",
            path: fixtures_root + "/prelude_methods_ok.s",
            should_pass: true,
            expected_message: Option::None,
        },
        SemanticCase {
            name: "builtin_field_ok",
            path: fixtures_root + "/builtin_field_ok.s",
            should_pass: true,
            expected_message: Option::None,
        },
    }
}

pub fn run(fixtures_root: String) -> Vec[SemanticFailure] {
    let failures = Vec[SemanticFailure]()

    for case in semantic_cases(fixtures_root) {
        match run_case(case) {
            Result::Ok(()) => (),
            Result::Err(err) => failures.push(err),
        }
    }

    let prelude = load_prelude()
    if prelude.name != "std.prelude" {
        failures.push(SemanticFailure {
            name: "prelude",
            message: "prelude name mismatch",
        })
    }

    failures
}

pub fn run_case(case: SemanticCase) -> Result[(), SemanticFailure] {
    let source =
        match read_to_string(case.path) {
            Result::Ok(value) => value,
            Result::Err(_) => {
                return Result::Err(SemanticFailure {
                    name: case.name,
                    message: "failed to read fixture",
                })
            }
        }

    let parsed =
        match parse_source(source) {
            Result::Ok(value) => value,
            Result::Err(err) => {
                return Result::Err(SemanticFailure {
                    name: case.name,
                    message: "parse error: " + err.message,
                })
            }
        }

    let checked = check_source(parsed)
    let ok = checked.diagnostics.len() == 0
    if ok != case.should_pass {
        return Result::Err(SemanticFailure {
            name: case.name,
            message: "unexpected semantic result",
        })
    }

    match case.expected_message {
        Option::Some(message) => {
            if !has_diagnostic(checked.diagnostics, message) {
                return Result::Err(SemanticFailure {
                    name: case.name,
                    message: "expected diagnostic not found",
                })
            }
        }
        Option::None => (),
    }

    Result::Ok(())
}

pub fn has_diagnostic(diagnostics: Vec[compiler.Diagnostic], expected: String) -> bool {
    for diagnostic in diagnostics {
        if diagnostic.message == expected {
            return true
        }
    }
    false
}
