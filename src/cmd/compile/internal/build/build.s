package compile.internal.build

use compile.internal.backend.Build as BuildBinary
use compile.internal.backend.Run as RunBinary
use std.vec.Vec

func Main(Vec[String] args) -> i32 {
    if args.len() < 2 {
        return 0
    }

    var command = args[1]
    if command == "help" {
        return 0
    }

    if command == "build" {
        if args.len() < 5 {
            return 1
        }
        if args[3] != "-o" {
            return 1
        }
        var build_result = BuildBinary(args[2], args[4])
        if build_result == 0 {
            return 0
        }
        return 1
    }

    if command == "run" {
        if args.len() < 3 {
            return 1
        }
        var run_result = RunBinary(args[2])
        if run_result == 0 {
            return 0
        }
        return 1
    }

    0
}
