package compile.internal.tests.test_driver
import (
    "compile.driver"
    "std.io"
)
use std.io.eprintln

func run_driver_suite() int {
    if expect_build(["s", "hello.s", "-o", "hello"], "hello.s", "hello") != 0 { return 1 }
    if expect_build(["s", "-o", "hello", "hello.s"], "hello.s", "hello") != 0 { return 1 }
    if expect_build(["s", "build", "hello.s", "-o", "hello"], "hello.s", "hello") != 0 { return 1 }
    if expect_build(["s", "hello.s"], "hello.s", "hello") != 0 { return 1 }
    if expect_forward(["s", "--emit-c", "hello.s", "hello.c"], "--emit-c") != 0 { return 1 }
    if expect_forward(["s", "--emit-mir", "hello.s", "hello.mir"], "--emit-mir") != 0 { return 1 }
    if expect_usage(["s", "-o"]) != 0 { return 1 }
    if expect_usage(["s", "--version"]) != 0 { return 1 }
    if expect_usage(["s", "--unknown"]) != 0 { return 1 }
    eprintln("driver: ok")
    return 0
}

func expect_build(string[] args, string input, string output) int {
    config := parse_arguments(args)
    if config.action != "build" || config.input != input || config.output != output {
        eprintln("driver parse build mismatch")
        return 1
    }
    return 0
}

func expect_forward(string[] args, string mode) int {
    config := parse_arguments(args)
    if config.action != "forward" || len(config.forwarded_args) != len(args) || config.forwarded_args[1] != mode {
        eprintln("driver parse forward mismatch")
        return 1
    }
    return 0
}

func expect_usage(string[] args) int {
    config := parse_arguments(args)
    if config.action != "usage" || config.exit_code != 2 {
        eprintln("driver parse usage mismatch")
        return 1
    }
    return 0
}
