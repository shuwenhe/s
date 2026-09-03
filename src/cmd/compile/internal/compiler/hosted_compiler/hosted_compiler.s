package compile.internal.compiler.hosted_compiler
use compile.internal.compiler.run_cli as compiler_run_cli
use std.slices
func run_cli([]string args) int {
    compiler_run_cli(args)
}
