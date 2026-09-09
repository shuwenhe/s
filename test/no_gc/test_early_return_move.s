package test.early_return_move

use std.io.println

// Test: Early return with move semantics
// 测试：所有权在 early return 时的处理

func test_early_return() () {
    x := box(10)
    
    // Early return path - x should be moved out
    if true {
        return  // x 需要在这里被 drop
    }
    
    // Unreachable code - x 已经被 drop
    println("unreachable")
}

func test_conditional_early_return() () {
    x := box(20)
    y := box(30)
    
    if true {
        return   // Both x and y need to be dropped
    }
    
    // x and y 在这里无法到达
    println("unreachable")
}

func test_early_return_with_use() () {
    x := box(5)
    
    if false {
        return
    }
    
    // x 此时应该仍有效
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
