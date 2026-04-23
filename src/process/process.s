package std.process

use std.result.result
use std.vec.vec

struct process_error {
    string message
}

func run_process(vec[string] argv) result[(), process_error] {
    __host_run_process(argv)
}

func exit(int code) () {
    __host_exit(code)
}

extern "intrinsic" func __host_run_process(vec[string] argv) result[(), process_error]

extern "intrinsic" func __host_exit(int code) ()
