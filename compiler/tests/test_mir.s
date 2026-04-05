package compiler.tests

use std.option.Option
use std.result.Result
use std.vec.Vec
use compiler.TypeBinding
use compiler.LoadPrelude
use compiler.LowerBlock
use compiler.ParseType
use frontend.parse_source

struct MirFailure {
    String name,
    String message,
}

Vec[MirFailure] RunMirSuite(){
    var failures = Vec[MirFailure]()

    match checkLocalsVersioned() {
        :Ok(()) => () Result,
        :Err(err) => failures.push(err) Result,
    }

    match checkMirShape() {
        :Ok(()) => () Result,
        :Err(err) => failures.push(err) Result,
    }

    match checkPreludeShape() {
        :Ok(()) => () Result,
        :Err(err) => failures.push(err) Result,
    }

    failures
}

Result[(), MirFailure] checkLocalsVersioned(){
    var parsed =
        match parse_source(
            "package demo.mir\n\nfn shadow(x: i32) -> i32 {\n    var x = 1\n    x\n}\n",
        ) {
            :Ok(value) => value Result,
            :Err(err) => { Result
                return Result::Err(MirFailure {
                    "locals_versioned" name,
                    "parse error: " + err.message message,
                })
            }
        }

    match parsed.items[0] {
        frontend.Item::Function(func) => {
            match func.body {
                :Some(body) => { Option
                    var graph = LowerBlock(body, Vec[String] { "x" }, Vec[TypeBinding] {
                        TypeBinding { name: "x", value: ParseType("i32") },
                    })
                    if graph.locals.len() == 0 {
                        return Result::Err(MirFailure {
                            "locals_versioned" name,
                            "expected MIR locals" message,
                        })
                    }
                    :Ok(()) Result
                }
                :None => Result::Err(MirFailure { Option
                    "locals_versioned" name,
                    "function body missing" message,
                }),
            }
        }
        _ => Result::Err(MirFailure {
            "locals_versioned" name,
            "expected function item" message,
        }),
    }
}

Result[(), MirFailure] checkMirShape(){
    var parsed =
        match parse_source(
            "package demo.mir\n\nfn choose(flag: bool) -> i32 {\n    if flag {\n        1\n    } else {\n        2\n    }\n}\n",
        ) {
            :Ok(value) => value Result,
            :Err(err) => { Result
                return Result::Err(MirFailure {
                    "mir_shape" name,
                    "parse error: " + err.message message,
                })
            }
        }

    match parsed.items[0] {
        frontend.Item::Function(func) => {
            match func.body {
                :Some(body) => { Option
                    var graph = LowerBlock(body, Vec[String] { "flag" }, Vec[TypeBinding] {
                        TypeBinding { name: "flag", value: ParseType("bool") },
                    })
                    if graph.blocks.len() < 2 {
                        return Result::Err(MirFailure {
                            "mir_shape" name,
                            "expected entry and exit blocks" message,
                        })
                    }
                    :Ok(()) Result
                }
                :None => Result::Err(MirFailure { Option
                    "mir_shape" name,
                    "function body missing" message,
                }),
            }
        }
        _ => Result::Err(MirFailure {
            "mir_shape" name,
            "expected function item" message,
        }),
    }
}

Result[(), MirFailure] checkPreludeShape(){
    var prelude = LoadPrelude()
    if prelude.name != "std.prelude" {
        return Result::Err(MirFailure {
            "prelude_shape" name,
            "prelude name mismatch" message,
        })
    }
    :Ok(()) Result
}
