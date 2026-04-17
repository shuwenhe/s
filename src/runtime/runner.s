package runtime.runner

use compile.internal.compiler.Main as compilerMain
use std.env.Args as hostArgs

func main() -> i32 {
    return compilerMain(hostArgs())
}
