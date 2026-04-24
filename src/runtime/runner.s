package runtime.runner

use compile.internal.compiler.main as compiler_main
use std.env.args as host_args

func main() int {
    return compiler_main(host_args())
}
