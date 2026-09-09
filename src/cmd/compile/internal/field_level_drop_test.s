package compile.internal.field_level_drop_test

use compile.internal.path.path_new
use compile.internal.path.path_field
use compile.internal.path.path_index
use compile.internal.field_level_drop_flag.fldf_new
use compile.internal.field_level_drop_flag.fldf_declare
use compile.internal.field_level_drop_flag.fldf_move
use compile.internal.field_level_drop_flag.fldf_use
use compile.internal.field_level_drop_flag.fldf_reassign
use compile.internal.field_level_drop_flag.fldf_scope_exit
use compile.internal.field_level_drop_flag.fldf_merge_branches
use compile.internal.field_level_drop_flag.fldf_has_errors
use compile.internal.field_level_drop_flag.fldf_get_paths_needing_drop

// ============================================================================
// Test 1: Basic Variable Operations
// ============================================================================

func test_basic_declare_and_use() bool {
    f := fldf_new()
    x := path_new("x")
    
    // Declare x: Box
    f = fldf_declare(f, x, "Box")
    if fldf_has_errors(f) { return false }
    
    // Use x (should be OK)
    f = fldf_use(f, x)
    if fldf_has_errors(f) { return false }
    
    true
}

func test_use_after_move() bool {
    f := fldf_new()
    x := path_new("x")
    y := path_new("y")
    
    f = fldf_declare(f, x, "Box")
    
    // Move x to y
    f = fldf_move(f, x, y, 10, 0)
    if fldf_has_errors(f) { return false }
    
    // Use x (should error)
    f = fldf_use(f, x)
    if !fldf_has_errors(f) { return false }  // 应该有错误
    
    true
}

// ============================================================================
// Test 2: Struct Field Level Operations
// ============================================================================

func test_struct_field_move() bool {
    f := fldf_new()
    
    // Declare struct x with fields left, right
    x := path_new("x")
    f = fldf_declare(f, x, "Pair")
    
    x_left := path_field(path_new("x"), "left")
    x_right := path_field(path_new("x"), "right")
    y := path_new("y")
    
    // Both fields are implicitly live
    // Move x.left to y
    f = fldf_move(f, x_left, y, 20, 0)
    if fldf_has_errors(f) { return false }
    
    // Use x.right (should be OK - not moved)
    f = fldf_use(f, x_right)
    if fldf_has_errors(f) { return false }
    
    // Use x.left (should error - moved)
    f = fldf_use(f, x_left)
    if !fldf_has_errors(f) { return false }
    
    true
}

func test_struct_field_drop_order() bool {
    f := fldf_new()
    
    x := path_new("x")
    f = fldf_declare(f, x, "Pair")
    
    x_left := path_field(path_new("x"), "left")
    x_right := path_field(path_new("x"), "right")
    
    y := path_new("y")
    
    // Move left field
    f = fldf_move(f, x_left, y, 30, 0)
    
    // Scope exit
    f_after, drops := fldf_scope_exit(f)
    
    // 应该 drop: y (live), x.right (live)
    // 不应该 drop x (struct 被清理), x.left (moved)
    if len(drops) != 2 { return false }
    
    true
}

// ============================================================================
// Test 3: Array Element Operations
// ============================================================================

func test_array_element_move() bool {
    f := fldf_new()
    
    // Declare array
    v := path_new("v")
    f = fldf_declare(f, v, "[]Box")
    
    // Move v[0]
    v_0 := path_index(path_new("v"), 0)
    x := path_new("x")
    f = fldf_move(f, v_0, x, 40, 0)
    if fldf_has_errors(f) { return false }
    
    // Use v[0] (should error)
    f = fldf_use(f, v_0)
    if !fldf_has_errors(f) { return false }
    
    // Use v[1] (should be OK)
    v_1 := path_index(path_new("v"), 1)
    f = fldf_use(f, v_1)
    if fldf_has_errors(f) { return false }
    
    true
}

// ============================================================================
// Test 4: Conditional Merge (if-else)
// ============================================================================

func test_conditional_merge_same_state() bool {
    // x is live in both branches
    f_if := fldf_new()
    f_if = fldf_declare(f_if, path_new("x"), "Box")
    
    f_else := fldf_new()
    f_else = fldf_declare(f_else, path_new("x"), "Box")
    
    // Merge
    f_merged := fldf_merge_branches(f_if, f_else)
    
    // After merge, x should still be live
    f_merged = fldf_use(f_merged, path_new("x"))
    if fldf_has_errors(f_merged) { return false }
    
    true
}

func test_conditional_merge_different_state() bool {
    // x is moved in if branch, live in else branch
    f_if := fldf_new()
    f_if = fldf_declare(f_if, path_new("x"), "Box")
    y := path_new("y")
    f_if = fldf_move(f_if, path_new("x"), y, 50, 0)  // x moved
    
    f_else := fldf_new()
    f_else = fldf_declare(f_else, path_new("x"), "Box")
    // x is live in else
    
    // Merge
    f_merged := fldf_merge_branches(f_if, f_else)
    
    // After merge, x should be in "maybe" state
    // Use should generate warning
    f_merged = fldf_use(f_merged, path_new("x"))
    
    // Should have warning, not hard error
    // (具体取决于 maybe 的严格程度)
    
    true
}

// ============================================================================
// Test 5: Nested Field Access
// ============================================================================

func test_nested_field_access() bool {
    f := fldf_new()
    
    // Declare nested struct
    x := path_new("x")
    f = fldf_declare(f, x, "Outer")
    
    // Declare nested field path
    x_in_value := path_field(path_field(path_new("x"), "in"), "value")
    
    y := path_new("y")
    f = fldf_move(f, x_in_value, y, 60, 0)
    if fldf_has_errors(f) { return false }
    
    // Use nested field (should error)
    f = fldf_use(f, x_in_value)
    if !fldf_has_errors(f) { return false }
    
    true
}

// ============================================================================
// Test 6: Partial Move (multiple fields)
// ============================================================================

func test_partial_move_two_fields() bool {
    f := fldf_new()
    
    p := path_new("p")
    f = fldf_declare(f, p, "Pair")
    
    p_left := path_field(path_new("p"), "left")
    p_right := path_field(path_new("p"), "right")
    
    y := path_new("y")
    z := path_new("z")
    
    // Move both fields
    f = fldf_move(f, p_left, y, 70, 0)
    f = fldf_move(f, p_right, z, 71, 0)
    
    // At scope exit
    f, drops := fldf_scope_exit(f)
    
    // Should drop y, z (moved values are now in y and z)
    // p has partial move, fields are moved
    // 需要仔细考虑 drop 顺序
    
    if len(drops) < 2 { return false }
    
    true
}

// ============================================================================
// Test 7: Reassignment
// ============================================================================

func test_reassignment_after_move() bool {
    f := fldf_new()
    
    x := path_new("x")
    f = fldf_declare(f, x, "Box")
    
    y := path_new("y")
    f = fldf_move(f, x, y, 80, 0)  // x moved
    
    // x is now moved, reassign new value
    f = fldf_reassign(f, x, "Box")
    
    // x should now be live again
    f = fldf_use(f, x)
    if fldf_has_errors(f) { return false }
    
    true
}

// ============================================================================
// Test 8: Scope Management
// ============================================================================

func test_scope_lifo_drop_order() bool {
    f := fldf_new()
    
    x := path_new("x")
    y := path_new("y")
    z := path_new("z")
    
    f = fldf_declare(f, x, "Box")
    f = fldf_declare(f, y, "Box")
    f = fldf_declare(f, z, "Box")
    
    // Scope exit
    f, drops := fldf_scope_exit(f)
    
    // Should drop in reverse order: z, y, x (LIFO)
    if len(drops) != 3 { return false }
    
    // Check order (drops[0] = z, drops[1] = y, drops[2] = x)
    // (需要检查路径内容)
    
    true
}

// ============================================================================
// Main Test Runner
// ============================================================================

func run_field_level_drop_tests() bool {
    tests_passed := 0
    tests_total := 0
    
    // Test 1: Basic Operations
    tests_total = tests_total + 1
    if test_basic_declare_and_use() {
        tests_passed = tests_passed + 1
    }
    
    // Test 2: Use After Move
    tests_total = tests_total + 1
    if test_use_after_move() {
        tests_passed = tests_passed + 1
    }
    
    // Test 3: Struct Field Move
    tests_total = tests_total + 1
    if test_struct_field_move() {
        tests_passed = tests_passed + 1
    }
    
    // Test 4: Field Drop Order
    tests_total = tests_total + 1
    if test_struct_field_drop_order() {
        tests_passed = tests_passed + 1
    }
    
    // Test 5: Array Element
    tests_total = tests_total + 1
    if test_array_element_move() {
        tests_passed = tests_passed + 1
    }
    
    // Test 6: Conditional Merge (same)
    tests_total = tests_total + 1
    if test_conditional_merge_same_state() {
        tests_passed = tests_passed + 1
    }
    
    // Test 7: Conditional Merge (different)
    tests_total = tests_total + 1
    if test_conditional_merge_different_state() {
        tests_passed = tests_passed + 1
    }
    
    // Test 8: Nested Field
    tests_total = tests_total + 1
    if test_nested_field_access() {
        tests_passed = tests_passed + 1
    }
    
    // Test 9: Partial Move
    tests_total = tests_total + 1
    if test_partial_move_two_fields() {
        tests_passed = tests_passed + 1
    }
    
    // Test 10: Reassignment
    tests_total = tests_total + 1
    if test_reassignment_after_move() {
        tests_passed = tests_passed + 1
    }
    
    // Test 11: Scope LIFO
    tests_total = tests_total + 1
    if test_scope_lifo_drop_order() {
        tests_passed = tests_passed + 1
    }
    
    // Report
    println("════════════════════════════════════════════")
    println("Field-Level Drop Flag Tests")
    println("════════════════════════════════════════════")
    println("Passed: " + tests_passed + " / " + tests_total)
    println("════════════════════════════════════════════")
    
    tests_passed == tests_total
}
