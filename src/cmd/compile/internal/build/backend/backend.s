package compile.internal.build.backend

use std.fs.MakeTempDir
use std.io.eprintln

func Build(String path, String output) -> i32 {
    __host_build_executable(path, output)
}

func Run(String path) -> i32 {
    var temp_dir_result = MakeTempDir("s-build-")
    if temp_dir_result.is_err() {
        eprintln("run failed: could not create temporary output directory");
        return 1
    }

    var output_path = temp_dir_result.unwrap() + "/a.out"
    if Build(path, output_path) != 0 {
        eprintln("run failed: build step failed");
        return 1
    }

    return __host_run_executable(output_path)
}
