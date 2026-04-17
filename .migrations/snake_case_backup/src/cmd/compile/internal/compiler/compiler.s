package compile.internal.compiler

use compile.internal.arch.Init as archInit
use compile.internal.build.Main as buildMain
use internal.buildcfg.Check as buildcfgCheck
use internal.buildcfg.GOARCH as buildcfgGOARCH
use std.vec.Vec

func main(Vec[string] args) int32 {
    var buildcfgErr = buildcfgCheck()
    if buildcfgErr != "" {
        return 2
    }

    var archErr = archInit(buildcfgGOARCH())
    if archErr != "" {
        return 2
    }

    return buildMain(args)
}

// Compatibility wrapper expected by some bootstrap imports.
func Main(Vec[string] args) int32 {
    return main(args)
}
