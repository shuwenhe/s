package runtime.runner

use compile.internal.compiler.main as compilerMain
use std.env.Args as hostArgs

func main() int32 {
    return compilerMain(hostArgs())
}
