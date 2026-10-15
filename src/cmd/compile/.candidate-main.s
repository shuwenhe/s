package compile.internal.main

import (
    "compile.driver"
    "std.env"
)

use std.env.args

func main() int {
    return driver_main(args())
}
