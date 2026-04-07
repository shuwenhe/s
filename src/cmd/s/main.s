package cmd

use compiler.main as compilerMain
use std.env.Args
use std.process.Exit

func main() () {
    Exit(compilerMain(Args()))
}
