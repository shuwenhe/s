package compile.internal.bounds_test
import (
    "compile.internal.bounds"
)

func run_bounds_test() int {
    constant := compile.internal.bounds.bounds_prove_constant_index(3, 8)
    if !compile.internal.bounds.bounds_should_eliminate(constant) {
        return 1
    }
    if compile.internal.bounds.bounds_should_eliminate(compile.internal.bounds.bounds_prove_constant_index(-1, 8)) {
        return 2
    }
    loop := compile.internal.bounds.bounds_prove_loop(0, 16, 1, 16)
    if !compile.internal.bounds.bounds_should_eliminate(loop) {
        return 3
    }
    if compile.internal.bounds.bounds_should_eliminate(compile.internal.bounds.bounds_prove_loop(0, 17, 1, 16)) {
        return 4
    }
    if compile.internal.bounds.bounds_should_eliminate(compile.internal.bounds.bounds_prove_loop(0, 16, 0, 16)) {
        return 5
    }
    0
}
