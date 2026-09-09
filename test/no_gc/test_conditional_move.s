package test.conditional_move

use std.io.println

func test_simple_conditional_move() () {
    x := box(10)
    y := box(20)

    if true {
        z := x
        println("x moved to z")
    }

}

func test_move_in_both_branches() () {
    x := box(100)
    y := box(200)

    if true {
        z := x
    } else {
        w := x
    }

}

func test_move_one_branch_only() () {
    x := box(50)
    y := box(60)

    if true {
        z := x
    }

}

func test_conditional_initialization() () {
    a := box(1)

    b := box(10)
    if false {
        b = a
    }

}

func main() () {
    println("=== Test: Conditional Move ===")

    test_simple_conditional_move()
    println("✓ test_simple_conditional_move passed")

    test_move_in_both_branches()
    println("✓ test_move_in_both_branches passed")

    test_move_one_branch_only()
    println("✓ test_move_one_branch_only passed")

    test_conditional_initialization()
    println("✓ test_conditional_initialization passed")
}