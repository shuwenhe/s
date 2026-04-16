package compile.internal.build.report

use std.io.eprintln
use std.io.println

func Error(String message) -> () {
    eprintln("error: " + message)
}

func Usage(String text) -> () {
    println(text)
}
