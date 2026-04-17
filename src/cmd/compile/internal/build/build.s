package compile.internal.build

use compile.internal.build.exec.Run as ExecRun
use compile.internal.build.parse.ParseOptions
use compile.internal.build.report.Error as ReportError
use std.vec.Vec

func Main(Vec[String] args) -> i32 {
    var parsed = ParseOptions(args)
    if parsed.is_err() {
        report_error("parse failed")
    }
    if parsed.is_err() {
        return 1
    }

    var options = parsed.unwrap()
    if options.command == "help" {
        return 0
    }

    var exec_result = ExecRun(options)
    if exec_result.is_err() {
        report_error("execution failed")
    }
    if exec_result.is_err() {
        return 1
    }

    0
}

func report_error(String message) -> () {
    ReportError(message)
}
