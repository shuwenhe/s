package cmd

use compile.internal.dispatch.main as dispatch_main
use std.env.args as host_args

func main() int {
    return dispatch_main(host_args())
}
