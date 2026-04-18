package compile.internal.build

use compile.internal.build.exec.run as exec_run
use compile.internal.build.parse.parse_options
use compile.internal.build.report.error as report_error
use std.vec.vec

func main(vec[string] args)  int32 {
    var options = parse_options(args)
    if options[0] == "help" {
        return 0
    }

    var exec_result = exec_run(options)
    if options[0] == "run" {
        return exec_result
    }
    if exec_result != 0 {
        report_error("execution failed");
        return 1
    }

    0
}

func report_error(string message)  () {
    report_error(message)
}
