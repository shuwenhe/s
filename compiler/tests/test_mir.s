package compiler.tests

use std.option.Option
use std.result.Result
use std.vec.Vec
use compiler.TypeBinding
use compiler.LoadPrelude
use compiler.LowerBlock
use compiler.ParseType
use frontend.parse_source

pub struct MirFailure {
    name: String,
    message: String,
}

fn RunMirSuite() -> Vec[MirFailure] {
    var failures = Vec[MirFailure]()

    match checkLocalsVersioned() {
        Result::Ok(()) => (),
        Result::Err(err) => failures.push(err),
    }

    match checkMirShape() {
        Result::Ok(()) => (),
        Result::Err(err) => failures.push(err),
    }

    match checkPreludeShape() {
        Result::Ok(()) => (),
        Result::Err(err) => failures.push(err),
    }

    failures
}

fn checkLocalsVersioned() -> Result[(), MirFailure] {
    var parsed =
        match parse_source(
            "package demo.mir\n\nfn shadow(x: i32) -> i32 {\n    var x = 1\n    x\n}\n",
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
                    var graph = LowerBlock(body, Vec[String] { "x" }, Vec[TypeBinding] {
                        TypeBinding { name: "x", value: ParseType("i32") },
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

fn checkMirShape() -> Result[(), MirFailure] {
    var parsed =
        match parse_source(
            "package demo.mir\n\nfn choose(flag: bool) -> i32 {\n    if flag {\n        1\n    } else {\n        2\n    }\n}\n",
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
                    var graph = LowerBlock(body, Vec[String] { "flag" }, Vec[TypeBinding] {
                        TypeBinding { name: "flag", value: ParseType("bool") },
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

fn checkPreludeShape() -> Result[(), MirFailure] {
    var prelude = LoadPrelude()
    if prelude.name != "std.prelude" {
        return Result::Err(MirFailure {
            name: "prelude_shape",
            message: "prelude name mismatch",
        })
    }
    Result::Ok(())
}
