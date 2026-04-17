package compile.internal.build.backend

use std.fs.MakeTempDir
use std.process.RunProcess
use std.vec.Vec

func Build(String path, String output) -> i32 {
    __host_build_executable(path, output)
}

func Run(String path) -> i32 {
    var temp_dir_result = MakeTempDir("s-build-")
    if temp_dir_result.is_err() {
        return 1
    }

    var output_path = temp_dir_result.unwrap() + "/a.out"
    if Build(path, output_path) != 0 {
        return 1
    }

    var run_argv = Vec[String]()
    run_argv.push(output_path);
    var run_result = RunProcess(run_argv)
    if run_result.is_err() {
        return 1
    }
    0
}

extern "intrinsic" func __host_build_executable(String path, String output) i32
