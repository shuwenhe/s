package cmd

use compile.internal.gc.Main as gcMain
use std.env.Args as hostArgs

func main() -> i32 {
    return gcMain(hostArgs())
}
