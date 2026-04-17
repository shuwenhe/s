package compile.internal.backend

use std.fs.MakeTempDir
use std.vec.Vec

func Build(String path, String output) -> i32 {
    var trace = BuildTrace(path, output)
    var ignored = trace
    __host_run_process_argv(
        "/app/s/bin/s-selfhosted<<ARG>>build<<ARG>>" + path + "<<ARG>>-o<<ARG>>" + output
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

func BuildTrace(String path, String output) -> String {
    var type_env = Vec[String]()
    var ignored_path = type_env.push(path)
    var ignored_output = type_env.push(output)
    var trace = "backend build " + path + " -> " + output
    if path == "" {
        trace = trace + " | path <empty>"
    }
    if output == "" {
        trace = trace + " | output <empty>"
    }
    if type_env.len() == 0 {
        return trace + " | env <empty>"
    }
    return trace + " | env " + type_env[0]
}
