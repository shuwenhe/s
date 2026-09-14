package compile.internal.build.backend
import (
    "std"
    "std.fs"
    "std.io"
    "std.process"
)
func build(string path, string output, string ssa_margin, bool nostdlib) int {
    build_binary(path, output, ssa_margin, nostdlib)
}

func run(string path, string ssa_margin, bool nostdlib) int {
    temp_dir_result := std.fs.make_temp_dir("s-build-")
    if temp_dir_result.is_err() {
        std.io.eprintln("run failed: could not create temporary output directory");
        return 1
    }
    output_path := temp_dir_result.unwrap() + "/a.out"
    if build(path, output_path, ssa_margin, nostdlib) != 0 {
        std.io.eprintln("run failed: build step failed");
        return 1
    }
    run_argv := string[]()
    run_argv = append(run_argv, output_path);
    run_result := std.process.run_process(run_argv)
    if run_result.is_err() {
        std.io.eprintln("run failed: process execution failed");
        return 1
    }
