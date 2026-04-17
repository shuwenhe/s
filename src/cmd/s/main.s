package cmd

use compile.internal.dispatch.Main as dispatch_main
use std.env.Args as host_args

func main() int32 {
    return dispatch_main(host_args())
}
