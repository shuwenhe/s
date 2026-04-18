package runtime.runner

use compile.internal.compiler.Main as compiler_main
use std.env.Args as host_args

func main() int32 {
    return compiler_main(host_args())
}
