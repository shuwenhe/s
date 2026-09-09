package test.use_after_move

use std.io.println

func should_fail_use_after_move() () {
    x := box(10)
    y := x

    println(x)
}

func should_fail_double_move() () {
    x := box(20)
    y := x
    z := x
}

func should_fail_move_after_borrow() () {
    x := box(30)
    r := &x

    y := x
}

func should_fail_borrow_after_move() () {
    x := box(40)
    y := x

    r := &y
    r2 := &x
}

func main() () {
    println("=== Test: Use After Move (should fail to compile) ===")
    println("These tests verify compile-time rejection of unsafe code")
}