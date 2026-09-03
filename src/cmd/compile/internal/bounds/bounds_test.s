package compile.internal.bounds_test
use compile.internal.bounds.bounds_prove_constant_index
use compile.internal.bounds.bounds_prove_loop
use compile.internal.bounds.bounds_should_eliminate

func run_bounds_test() int {
    constant := bounds_prove_constant_index(3, 8)
    if !bounds_should_eliminate(constant) {
        return 1
    }
    if bounds_should_eliminate(bounds_prove_constant_index(-1, 8)) {
        return 2
    }
    loop := bounds_prove_loop(0, 16, 1, 16)
    if !bounds_should_eliminate(loop) {
        return 3
    }
    if bounds_should_eliminate(bounds_prove_loop(0, 17, 1, 16)) {
        return 4
    }
    if bounds_should_eliminate(bounds_prove_loop(0, 16, 0, 16)) {
        return 5
    }
    0
}
