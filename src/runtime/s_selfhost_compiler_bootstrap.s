package runtime

use compile.internal.compiler.main as compiler_main
use std.env.args as host_args

// Pure S launcher: invoke the compiler entry directly instead of bouncing through C.
func main() int {
    return compiler_main(host_args())
}
