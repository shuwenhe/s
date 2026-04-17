package compile.internal.build

use compile.internal.build.exec.Run as ExecRun
use compile.internal.build.parse.ParseOptions
use compile.internal.build.report.Error as ReportError
use std.vec.Vec

func main(Vec[string] args)  int32 {
    var options = ParseOptions(args)
    if options[0] == "help" {
        return 0
    }

    var execResult = ExecRun(options)
    if options[0] == "run" {
        return execResult
    }
    if execResult != 0 {
        reportError("execution failed");
        return 1
    }

    0
}

func reportError(string message)  () {
    ReportError(message)
}
