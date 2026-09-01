package cmd
use compile.internal.arch.dispatch_init as arch_dispatch_init
use compile.internal.build.main as build_main
use internal.buildcfg.check as buildcfg_check
use internal.buildcfg.goarch as buildcfg_goarch
use std.env.args as host_args
use std.io.eprintln
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
    eprintln("compile: " + message)
    0
}
