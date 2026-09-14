package runtime.runner
import (
    "compile.internal.compiler"
    "std.env"
)
func main() {
    return compile.internal.compiler.main(std.env.args())
