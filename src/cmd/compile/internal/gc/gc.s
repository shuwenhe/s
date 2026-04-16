package compile.internal.gc

use compile.internal.arch.Init as archInit
use compile.internal.build.Main as buildMain
use internal.buildcfg.Check as buildcfgCheck
use internal.buildcfg.GOARCH as buildcfgGOARCH
use std.io.eprintln
use std.result.Result
use std.vec.Vec

func Main(Vec[String] args) i32 {
    match buildcfgCheck() {
        Result::Ok(_) => (),
        Result::Err(err) => {
            eprintln("compile: " + err.message)
            return 2
        }
    }

    match archInit(buildcfgGOARCH()) {
        Result::Ok(_) => (),
        Result::Err(err) => {
            eprintln("compile: " + err.message)
            return 2
        }
    }

    buildMain(args)
}
