package compile.internal.gc
use compile.internal.arch.dispatch_init as arch_dispatch_init
use internal.buildcfg.check as buildcfg_check
use internal.buildcfg.goarch as buildcfg_goarch
use std.vec.vec

func compile_main(vec[string] args) int {
    init_err := init_compile_environment()
    if init_err != "" {
        return 2
    }
    result := compile_package(args)
    return result.status
}

func init_compile_environment() string {
    cfg_err := buildcfg_check()
    if cfg_err != "" {
        return cfg_err
    }
    arch_err := arch_dispatch_init(buildcfg_goarch())
    if arch_err != "" {
        return arch_err
    }
    ""
}
