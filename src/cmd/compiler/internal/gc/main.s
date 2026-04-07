package compiler.internal.gc

use compiler.internal.base.cliError
use std.io.eprintln
use std.result.Result
use std.vec.Vec

func Main(Vec[String] args) i32 {
    match Run(args) {
        Result::Ok(()) => 0,
        Result::Err(err) => {
            eprintln("error: " + err.message)
            1
        }
    }
}

func Run(Vec[String] args) Result[(), cliError] {
    RunCommand(args)
}
