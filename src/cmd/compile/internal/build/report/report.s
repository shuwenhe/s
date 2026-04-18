package compile.internal.build.report

use std.io.eprintln
use std.io.println

func error(string message) () {
    eprintln("error: " + message)
}

func usage(string text) () {
    println(text)
}
