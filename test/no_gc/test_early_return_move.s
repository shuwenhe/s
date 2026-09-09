package test.early_return_move

use std.io.println

func test_early_return() () {
    x := box(10)

    if true {
        return
    }

    println("unreachable")
}

func test_conditional_early_return() () {
    x := box(20)
    y := box(30)

    if true {
        return
    }

    println("unreachable")
}

func test_early_return_with_use() () {
    x := box(5)

    if false {
        return
    }

    println("x is still valid")
}

func main() () {
    println("=== Test: Early Return Move ===")

    test_early_return()
    println("✓ test_early_return passed")

    test_conditional_early_return()
    println("✓ test_conditional_early_return passed")

    test_early_return_with_use()
    println("✓ test_early_return_with_use passed")
}