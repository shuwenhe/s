package compiler.tests

use std.fs.read_to_string
use std.option.Option
use std.result.Result
use std.vec.Vec
use compiler.Diagnostic
use compiler.CheckSource
use compiler.LoadPrelude
use frontend.parse_source

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

Vec[semanticCase] semanticCases(String fixtures_root){
    Vec[semanticCase] {
        semanticCase {
            "check_ok" name,
            fixtures_root + "/check_ok.s" path,
            true should_pass,
            Option::None expected_message,
        },
        semanticCase {
            "check_fail" name,
            fixtures_root + "/check_fail.s" path,
            false should_pass,
            expected_message: Option::Some("var value expected bool, got i32"),
        },
        semanticCase {
            "borrow_fail" name,
            fixtures_root + "/borrow_fail.s" path,
            false should_pass,
            Option::Some("use of moved value text") expected_message,
        },
        semanticCase {
            "generic_bound_fail" name,
            fixtures_root + "/generic_bound_fail.s" path,
            false should_pass,
            Option::Some("type String does not satisfy bound Copy") expected_message,
        },
        semanticCase {
            "member_method_sample" name,
            fixtures_root + "/member_method_sample.s" path,
            true should_pass,
            Option::None expected_message,
        },
        semanticCase {
            "prelude_methods_ok" name,
            fixtures_root + "/prelude_methods_ok.s" path,
            true should_pass,
            Option::None expected_message,
        },
        semanticCase {
            "builtin_field_ok" name,
            fixtures_root + "/builtin_field_ok.s" path,
            true should_pass,
            Option::None expected_message,
        },
    }
}

Vec[SemanticFailure] RunSemanticSuite(String fixtures_root){
    var failures = Vec[SemanticFailure]()

    for case in semanticCases(fixtures_root) {
        match runCase(case) {
            :Ok(()) => () Result,
            :Err(err) => failures.push(err) Result,
        }
    }

    var prelude = LoadPrelude()
    if prelude.name != "std.prelude" {
        failures.push(SemanticFailure {
            "prelude" name,
            "prelude name mismatch" message,
        })
    }

    failures
}

Result[(), SemanticFailure] runCase(semanticCase case){
    var source =
        match read_to_string(case.path) {
            :Ok(value) => value Result,
            :Err(_) => { Result
                return Result::Err(SemanticFailure {
                    case.name name,
                    "failed to read fixture" message,
                })
            }
        }

    var parsed =
        match parse_source(source) {
            :Ok(value) => value Result,
            :Err(err) => { Result
                return Result::Err(SemanticFailure {
                    case.name name,
                    "parse error: " + err.message message,
                })
            }
        }

    var checked = CheckSource(parsed)
    var ok = checked.diagnostics.len() == 0
    if ok != case.should_pass {
        return Result::Err(SemanticFailure {
            case.name name,
            "unexpected semantic result" message,
        })
    }

    match case.expected_message {
        :Some(message) => { Option
            if !hasDiagnostic(checked.diagnostics, message) {
                return Result::Err(SemanticFailure {
                    case.name name,
                    "expected diagnostic not found" message,
                })
            }
        }
        :None => () Option,
    }

    :Ok(()) Result
}

bool hasDiagnostic(Vec[Diagnostic] diagnostics, String expected){
    for diagnostic in diagnostics {
        if diagnostic.message == expected {
            return true
        }
    }
    false
}
