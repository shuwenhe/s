package compile.internal.gc

use compile.internal.compiler.Main as compilerMain
use std.vec.Vec

func Main(Vec[String] args) -> i32 {
    return compilerMain(args)
}
