package cmd
import (
    "compile.internal.dispatch"
    "std.env"
)
func main() {
    return compile.internal.dispatch.main(std.env.args())
}
