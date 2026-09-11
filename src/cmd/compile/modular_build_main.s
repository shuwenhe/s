package cmd
use compile.internal.backend_elf64.build as build_elf64
use internal.buildcfg.check as buildcfg_check
use internal.buildcfg.goarch as buildcfg_goarch
use compile.internal.arch.dispatch_init as arch_dispatch_init
use std.env.args as host_args
use std.io.eprintln

func main() int {
    args := host_args()
    if len(args) == 2 && args[1] == "--help" {
        eprintln("usage: s_modular build <input.s> -o <output>")
        return 0
    }
    if len(args) != 5 || args[1] != "build" || args[3] != "-o" {
        eprintln("usage: s_modular build <input.s> -o <output>")
        return 2
    }
    buildcfg_err := buildcfg_check()
    if buildcfg_err != "" {
        eprintln("compile: " + buildcfg_err)
        return 2
    }
    goarch := buildcfg_goarch()
    arch_err := arch_dispatch_init(goarch)
    if arch_err != "" {
        eprintln("compile: " + arch_err)
        return 2
    }
    return build_elf64(args[2], args[4], "", false)
}
