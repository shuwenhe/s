package test.use_after_move

use std.io.println

// Test: Use after move should be compile error
// 测试：移出后再使用应该编译失败

// 这些函数应该导致编译错误
// 如果编译器能正确检查 move 语义

func should_fail_use_after_move() () {
    x := box(10)
    y := x        // Move x to y
    
    // ❌ 这行应该编译失败：use of moved value 'x'
    println(x)
}

func should_fail_double_move() () {
    x := box(20)
    y := x        // First move
    z := x        // ❌ Second move - should fail
}

func should_fail_move_after_borrow() () {
    x := box(30)
    r := &x       // Borrow x
    
    y := x        // ❌ Cannot move while borrowed
}

func should_fail_borrow_after_move() () {
    x := box(40)
    y := x        // Move
    
    r := &y       // ✓ OK - borrowing y (the new owner)
    r2 := &x      // ❌ Should fail - x has been moved
}

func main() () {
    println("=== Test: Use After Move (should fail to compile) ===")
    println("These tests verify compile-time rejection of unsafe code")
}
