package std.process

use std.result.Result
use std.vec.Vec

struct ProcessError {
    String message,
}

func RunProcess(Vec[String] argv) -> Result[(), ProcessError] {
    __host_run_process(argv)
}

func Exit(int code) -> () {
    __host_exit(code)
}

func run_process(Vec[String] argv) -> Result[(), ProcessError] {
    RunProcess(argv)
}

extern "intrinsic" func __host_run_process(Vec[String] argv) -> Result[(), ProcessError]

extern "intrinsic" func __host_exit(int code) -> ()
