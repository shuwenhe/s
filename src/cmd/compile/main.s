package cmd

use compile.internal.arch.dispatch_init as arch_dispatch_init
use compile.internal.build.main as build_main
use internal.buildcfg.check as buildcfg_check
use internal.buildcfg.goarch as buildcfg_goarch
use std.env.args as host_args
use std.io.eprintln

func main() int32 {
    var args = host_args()
    var goarch = buildcfg_goarch()

    var buildcfg_err = buildcfg_check()
    if buildcfg_err != "" {
        report_compile_error(buildcfg_err)
        return 2
    }

    var arch_init_name = resolve_arch_init_name(goarch)
    if arch_init_name == "" {
        report_compile_error("unknown architecture \"" + goarch + "\"")
        return 2
    }

    var arch_err = arch_dispatch_init(goarch)
    if arch_err != "" {
        report_compile_error(arch_err)
        return 2
    }

    return build_main(args)
}

func resolve_arch_init_name(string goarch) string {
    if goarch == "386" {
        return "x86_init"
    }
    if goarch == "amd64" {
        return "amd64_init"
    }
    if goarch == "arm" {
        return "arm_init"
    }
    if goarch == "arm64" {
        return "arm64_init"
    }
    if goarch == "loong64" {
        return "loong64_init"
    }
    if goarch == "mips" || goarch == "mipsle" {
        return "mips_init"
    }
    if goarch == "mips64" || goarch == "mips64le" {
        return "mips64_init"
    }
    if goarch == "ppc64" || goarch == "ppc64le" {
        return "ppc64_init"
    }
    if goarch == "riscv64" {
        return "riscv64_init"
    }
    if goarch == "s390x" {
        return "s390x_init"
    }
    if goarch == "wasm" {
        return "wasm_init"
    }
    ""
}

func report_compile_error(string message) () {
    eprintln("compile: " + message)
}
