package compile.internal.compiler

use compile.internal.arch.Init as arch_init
use compile.internal.build.Main as build_main
use internal.buildcfg.Check as buildcfg_check
use internal.buildcfg.GOARCH as buildcfg_goarch
use std.vec.Vec

func main(Vec[string] args) int32 {
    var buildcfg_err = buildcfg_check()
    if buildcfg_err != "" {
        return 2
    }

    var arch_err = arch_init(buildcfg_goarch())
    if arch_err != "" {
        return 2
    }

    return build_main(args)
}

// Compatibility wrapper expected by some bootstrap imports.
func Main(Vec[string] args) int32 {
    return main(args)
}
