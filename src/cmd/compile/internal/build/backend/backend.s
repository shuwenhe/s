package compile.internal.build.backend

use compile.internal.backend_elf64.build as build_binary
use std.fs.make_temp_dir
use std.io.eprintln
use std.process.run_process
use std.vec.vec

func build(string path, string output) int32 {
    build_binary(path, output)
}

func run(string path) int32 {
    var temp_dir_result = make_temp_dir("s-build-")
    if temp_dir_result.is_err() {
        eprintln("run failed: could not create temporary output directory");
        return 1
    }

    var output_path = temp_dir_result.unwrap() + "/a.out"
    if build(path, output_path) != 0 {
        eprintln("run failed: build step failed");
        return 1
    }

    var run_argv = vec[string]()
    run_argv.push(output_path);
    var run_result = run_process(run_argv)
    if run_result.is_err() {
        eprintln("run failed: process execution failed");
        return 1
    }
    return 0
}
