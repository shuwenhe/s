package compiler.tests

use std.option.Option
use std.result.Result
use std.vec.Vec
use compiler.TypeBinding
use compiler.load_prelude
use compiler.lower_block
use compiler.parse_type
use frontend.parse_source

pub struct MirFailure {
    name: String,
    message: String,
}

pub fn run_mir_suite() -> Vec[MirFailure] {
    let failures = Vec[MirFailure]()

    match check_locals_versioned() {
        Result::Ok(()) => (),
        Result::Err(err) => failures.push(err),
    }

    match check_mir_shape() {
        Result::Ok(()) => (),
        Result::Err(err) => failures.push(err),
    }

    match check_prelude_shape() {
        Result::Ok(()) => (),
        Result::Err(err) => failures.push(err),
    }

    failures
}

pub fn check_locals_versioned() -> Result[(), MirFailure] {
    let parsed =
        match parse_source(
            "package demo.mir\n\npub fn shadow(x: i32) -> i32 {\n    let x = 1\n    x\n}\n",
        ) {
            Result::Ok(value) => value,
            Result::Err(err) => {
                return Result::Err(MirFailure {
                    name: "locals_versioned",
                    message: "parse error: " + err.message,
                })
            }
        }

    match parsed.items[0] {
        frontend.Item::Function(func) => {
            match func.body {
                Option::Some(body) => {
                    let graph = lower_block(body, Vec[String] { "x" }, Vec[TypeBinding] {
                        TypeBinding { name: "x", value: parse_type("i32") },
                    })
                    if graph.locals.len() == 0 {
                        return Result::Err(MirFailure {
                            name: "locals_versioned",
                            message: "expected MIR locals",
                        })
                    }
                    Result::Ok(())
                }
                Option::None => Result::Err(MirFailure {
                    name: "locals_versioned",
                    message: "function body missing",
                }),
            }
        }
        _ => Result::Err(MirFailure {
            name: "locals_versioned",
            message: "expected function item",
        }),
    }
}

pub fn check_mir_shape() -> Result[(), MirFailure] {
    let parsed =
        match parse_source(
            "package demo.mir\n\npub fn choose(flag: bool) -> i32 {\n    if flag {\n        1\n    } else {\n        2\n    }\n}\n",
        ) {
            Result::Ok(value) => value,
            Result::Err(err) => {
                return Result::Err(MirFailure {
                    name: "mir_shape",
                    message: "parse error: " + err.message,
                })
            }
        }

    match parsed.items[0] {
        frontend.Item::Function(func) => {
            match func.body {
                Option::Some(body) => {
                    let graph = lower_block(body, Vec[String] { "flag" }, Vec[TypeBinding] {
                        TypeBinding { name: "flag", value: parse_type("bool") },
                    })
                    if graph.blocks.len() < 2 {
                        return Result::Err(MirFailure {
                            name: "mir_shape",
                            message: "expected entry and exit blocks",
                        })
                    }
                    Result::Ok(())
                }
                Option::None => Result::Err(MirFailure {
                    name: "mir_shape",
                    message: "function body missing",
                }),
            }
        }
        _ => Result::Err(MirFailure {
            name: "mir_shape",
            message: "expected function item",
        }),
    }
}

pub fn check_prelude_shape() -> Result[(), MirFailure] {
    let prelude = load_prelude()
    if prelude.name != "std.prelude" {
        return Result::Err(MirFailure {
            name: "prelude_shape",
            message: "prelude name mismatch",
        })
    }
    Result::Ok(())
}
