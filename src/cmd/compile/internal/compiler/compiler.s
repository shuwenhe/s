package compile.internal.compiler

use compile.internal.arch.dispatch_init as arch_dispatch_init
use compile.internal.build.main as build_main
use internal.buildcfg.check as buildcfg_check
use internal.buildcfg.goarch as buildcfg_goarch
use std.vec.vec

func main(vec[string] args) int32 {
    var buildcfg_err = buildcfg_check()
    if buildcfg_err != "" {
        return 2
    }

    var arch_err = arch_dispatch_init(buildcfg_goarch())
    if arch_err != "" {
        return 2
    }

    return build_main(args)
}

