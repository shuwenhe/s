package compile.internal.build.backend
use compile.internal.backend_elf64.build as build_binary
use std.fs.make_temp_dir
use std.io.eprintln
use std.process.run_process
use std.slices

func build(string path, string output, string ssa_margin, bool nostdlib) int {
    build_binary(path, output, ssa_margin, nostdlib)
}

func run(string path, string ssa_margin, bool nostdlib) int {
    temp_dir_result := make_temp_dir("s-build-")
    if temp_dir_result.is_err() {
        eprintln("run failed: could not create temporary output directory");
        return 1
    }
    output_path := temp_dir_result.unwrap() + "/a.out"
    if build(path, output_path, ssa_margin, nostdlib) != 0 {
        eprintln("run failed: build step failed");
        return 1
    }
    run_argv := string[]()
    run_argv = append(run_argv, output_path);
    run_result := run_process(run_argv)
    if run_result.is_err() {
        eprintln("run failed: process execution failed");
        return 1
    }
    return 0
}
