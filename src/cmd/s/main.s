package cmd
import (
    "compile.driver"
    "std.env"
)
use std.env.args
func main() {
    return driver_main(args())
}
