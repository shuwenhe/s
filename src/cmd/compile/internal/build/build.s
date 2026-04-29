package compile.internal.build

use compile.internal.build.exec.run as exec_run
use compile.internal.build.utils.parse_options
use compile.internal.build.utils.usage as parse_usage
use compile.internal.build.utils.report_error as report_error
use compile.internal.build.utils.report_usage
use internal.buildcfg.goarch as buildcfg_goarch
use internal.buildcfg.goos as buildcfg_goos
use std.io.println
use std.vec.vec

func main(vec[string] args)  int {
    let options = parse_options(args)
    if options[0] == "help" {
        report_usage(parse_usage())
        return 0
    }

    emit_target_log(options[0])

    let exec_result = exec_run(options)
    if options[0] == "run" {
        return exec_result
    }
    if exec_result != 0 {
        report_error_local("execution failed");
        return 1
    }

    0
}

func report_error_local(string message)  () {
    report_error(message)
}

func emit_target_log(string command) () {
    if command == "check" || command == "build" {
        println("buildcfg: target=" + buildcfg_goos() + "/" + buildcfg_goarch())
    }
}
