package compile.internal.gc

use compile.internal.arch.Init as archInit
use compile.internal.build.Main as buildMain
use internal.buildcfg.Check as buildcfgCheck
use internal.buildcfg.GOARCH as buildcfgGOARCH
use std.io.eprintln
use std.vec.Vec

func Main(Vec[String] args) -> i32 {
    var buildcfg_err = buildcfgCheck()
    if buildcfg_err != "" {
        return fail(buildcfg_err)
    } else {
        var arch_err = archInit(buildcfgGOARCH())
        if arch_err != "" {
            return fail(arch_err)
        } else {
            return buildMain(args)
        }
    }
}

func fail(String message) -> i32 {
    eprintln("compile: " + message)
    2
}
