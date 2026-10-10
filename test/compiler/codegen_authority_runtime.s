package test.compiler.codegen_authority
import (
    "std.env"
)

func main() int {
    args := std.env.args()
    total := 0
    for (i := 1; i < len(args); i = i + 1) {
        total = total + i
    }
    if total > 2 {
        println("large")
    } else {
        println("small")
    }
    return total
}
