package compile.internal.backend

use std.fs.MakeTempDir

func Build(String path, String output) -> i32 {
    __host_run_process_argv(
        "/app/s/bin/s-native<<ARG>>build<<ARG>>" + path + "<<ARG>>-o<<ARG>>" + output
    )
}

func Run(String path) -> i32 {
    var temp_dir_result = MakeTempDir("s-compile-")
    if temp_dir_result.is_err() {
        return 1
    }

    var output = temp_dir_result.unwrap() + "/a.out"
    var build_result = Build(path, output)
    if build_result != 0 {
        return 1
    }

    __host_run_process_argv(output)
}
