package std.process

use std.result.Result
use std.vec.Vec

struct ProcessError {
    message: String,
}

func RunProcess(argv: Vec[String]) -> Result[(), ProcessError] {
    __host_run_process(argv)
}

func Exit(code: int) -> () {
    __host_exit(code)
}

func run_process(argv: Vec[String]) -> Result[(), ProcessError] {
    RunProcess(argv)
}

extern "intrinsic" func __host_run_process(argv: Vec[String]) -> Result[(), ProcessError]

extern "intrinsic" func __host_exit(code: int) -> ()
