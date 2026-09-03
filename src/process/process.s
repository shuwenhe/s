package std.process
use std.result.result
use std.slices
struct process_error {
    string message
}

func run_process(string[] argv) ((), process_error) {
    __host_run_process(argv)
}

func run_process_output(string[] argv) (string, process_error) {
    __host_run_process_output(argv)
}

func exit(int code) () {
    __host_exit(code)
}
extern "intrinsic" func __host_run_process(string[] argv) ((), process_error)
extern "intrinsic" func __host_run_process_output(string[] argv) (string, process_error)
extern "intrinsic" func __host_exit(int code) ()
