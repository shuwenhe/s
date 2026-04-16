package compile.internal.build

use compile.internal.backend.Build as BuildBinary
use compile.internal.backend.Run as RunBinary
use compile.internal.build.parse.ParseOptions
use std.vec.Vec

func Main(Vec[String] args) -> i32 {
    var options_result = ParseOptions(args)
    if options_result.is_err() {
        return 1
    }

    var options = options_result.unwrap()
    if options.command == "help" {
        return 0
    }

    if options.command == "build" {
        var build_result = BuildBinary(options.path, options.output)
        if build_result.is_ok() {
            return 0
        }
        return 1
    }

    if options.command == "run" {
        var run_result = RunBinary(options.path)
        if run_result.is_ok() {
            return 0
        }
        return 1
    }

    0
}
