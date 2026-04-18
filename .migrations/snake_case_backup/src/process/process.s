package std.process

use std.result.Result
use std.vec.Vec

struct process_error {
    string message,
}

func run_process(Vec[string] argv) Result[(), process_error] {
    __host_run_process(argv)
}

func Exit(int code) () {
    __host_exit(code)
}

func run_process(Vec[string] argv) Result[(), process_error] {
    run_process(argv)
}

extern "intrinsic" func __host_run_process(Vec[string] argv) Result[(), process_error]

extern "intrinsic" func __host_exit(int code) ()
