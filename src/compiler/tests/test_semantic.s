package compiler.tests

use std.fs.read_to_string
use std.option.Option
use std.result.Result
use std.vec.Vec
use compiler.Diagnostic
use compiler.CheckSource
use compiler.LoadPrelude
use s.parse_source

struct semanticCase {
    String name,
    String path,
    bool should_pass,
    Option[String] expected_message,
}

struct SemanticFailure {
    String name,
    String message,
}

func semanticCases(String fixtures_root) -> Vec[semanticCase] {
    Vec[semanticCase] {
        semanticCase {
            name: "check_ok",
            path: fixtures_root + "/check_ok.s",
            should_pass: true,
            expected_message: Option::None,
        },
        semanticCase {
            name: "check_fail",
            path: fixtures_root + "/check_fail.s",
            should_pass: false,
            expected_message: Option::Some("var value expected bool, got i32"),
        },
        semanticCase {
            name: "borrow_fail",
            path: fixtures_root + "/borrow_fail.s",
            should_pass: false,
            expected_message: Option::Some("use of moved value text"),
        },
        semanticCase {
            name: "generic_bound_fail",
            path: fixtures_root + "/generic_bound_fail.s",
            should_pass: false,
            expected_message: Option::Some("type String does not satisfy bound Copy"),
        },
        semanticCase {
            name: "member_method_sample",
            path: fixtures_root + "/member_method_sample.s",
            should_pass: true,
            expected_message: Option::None,
        },
        semanticCase {
            name: "prelude_methods_ok",
            path: fixtures_root + "/prelude_methods_ok.s",
            should_pass: true,
            expected_message: Option::None,
        },
        semanticCase {
            name: "builtin_field_ok",
            path: fixtures_root + "/builtin_field_ok.s",
            should_pass: true,
            expected_message: Option::None,
        },
    }
}

func RunSemanticSuite(String fixtures_root) -> Vec[SemanticFailure] {
    var failures = Vec[SemanticFailure]()

    for case in semanticCases(fixtures_root) {
        match runCase(case) {
            Result::Ok(()) => (),
            Result::Err(err) => failures.push(err),
        }
    }

    var prelude = LoadPrelude()
    if prelude.name != "std.prelude" {
        failures.push(SemanticFailure {
            name: "prelude",
            message: "prelude name mismatch",
        })
    }

    failures
}

func runCase(semanticCase case) -> Result[(), SemanticFailure] {
    var source =
        match read_to_string(case.path) {
            Result::Ok(value) => value,
            Result::Err(_) => {
                return Result::Err(SemanticFailure {
                    name: case.name,
                    message: "failed to read fixture",
                })
            }
        }

    var parsed =
        match parse_source(source) {
            Result::Ok(value) => value,
            Result::Err(err) => {
                return Result::Err(SemanticFailure {
                    name: case.name,
                    message: "parse error: " + err.message,
                })
            }
        }

    var checked = CheckSource(parsed)
    var ok = checked.diagnostics.len() == 0
    if ok != case.should_pass {
        return Result::Err(SemanticFailure {
            name: case.name,
            message: "unexpected semantic result",
        })
    }

    match case.expected_message {
        Option::Some(message) => {
            if !hasDiagnostic(checked.diagnostics, message) {
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

func hasDiagnostic(Vec[Diagnostic] diagnostics, String expected) -> bool {
    for diagnostic in diagnostics {
        if diagnostic.message == expected {
            return true
        }
    }
    false
}
