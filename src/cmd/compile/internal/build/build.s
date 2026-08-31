package compile.internal.build
use compile.internal.build.exec.run as exec_run
use compile.internal.build.utils.parse_options
use compile.internal.build.utils.usage as parse_usage
use compile.internal.build.utils.report_error as report_error
use compile.internal.build.utils.report_usage
use internal.buildcfg.goarch as buildcfg_goarch
use internal.buildcfg.goos as buildcfg_goos
use std.io.println
use std.slices

func main(string[] args)  int {
    options := parse_options(args)
    if options[0] == "help" {
        report_usage(parse_usage())
        return 0
    }
    emit_target_log(options[0])
    
    if options[0] == "build" {
        use_native := has_native_flag(options)
        exec_result := build_with_backend(options[1], options[2], options[3], use_native)
        if exec_result != 0 {
            report_error_local("build failed")
            return 1
        }
        return 0
    }
    
    exec_result := exec_run(options)
    if options[0] == "run" {
        return exec_result
    }
    if exec_result != 0 {
        report_error_local("execution failed");
        return 1
    }
    0
}

func report_error_local(string message)  () {
    report_error(message)
}

func emit_target_log(string command) () {
    if command == "check" || command == "build" {
        println("buildcfg: target=" + buildcfg_goos() + "/" + buildcfg_goarch())
    }
}

func has_native_flag(string[] options) bool {
    i := 0
    for i < len(options) {
        if options[i] == "native" {
            return true
        }
        i = i + 1
    }
    false
}

func build_with_backend(string path, string output, string ssa_margin, bool use_native) int {
    if use_native {
        return exec_run_native(path, output)
    } else {
        return exec_run(make_build_options(path, output, ssa_margin))
    }
}

func make_build_options(string path, string output, string ssa_margin) string[] {
    options := string[]()
    options = append(options, "build")
    options = append(options, path)
    options = append(options, output)
    options = append(options, ssa_margin)
    options
}

func exec_run_native(string path, string output) int {
    report_error_local("native compilation not yet implemented")
    1
}


