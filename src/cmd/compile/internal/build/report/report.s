package compile.internal.build.report
import (
    "std.io"
)
func error(string message) () {
    std.io.eprintln("error: " + message)
}

func usage(string text) () {
    std.io.println(text)
}
