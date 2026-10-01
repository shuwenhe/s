package cmd
import (
    "std.io"
)

func main() int {
    args := host_args()
    buildcfg_err := buildcfg_check()
    if buildcfg_err != "" {
        report_compile_error(buildcfg_err)
        return 2
    }
    goarch := buildcfg_goarch()
    arch_err := arch_dispatch_init(goarch)
    if arch_err != "" {
        report_compile_error(arch_err)
        return 2
    }
    return build_main(args)
}

func report_compile_error(string message) int {
    std.io.eprintln("compile: " + message)
    0
}
