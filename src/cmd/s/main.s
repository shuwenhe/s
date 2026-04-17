package cmd

use compile.internal.dispatch.main as dispatchMain
use std.env.Args as hostArgs

func main() int32 {
    return dispatchMain(hostArgs())
}
