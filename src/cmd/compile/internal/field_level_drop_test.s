package compile.internal.field_level_drop_test
import (
    "compile.internal.field_level_drop_flag"
    "compile.internal.path"
)
func test_basic_declare_and_use() bool {
    f := compile.internal.field_level_drop_flag.fldf_new()
    x := compile.internal.path.path_new("x")
    f = compile.internal.field_level_drop_flag.fldf_declare(f, x, "Box")
    if compile.internal.field_level_drop_flag.fldf_has_errors(f) { return false }
    f = compile.internal.field_level_drop_flag.fldf_use(f, x)
    if compile.internal.field_level_drop_flag.fldf_has_errors(f) { return false }
    true
}
func test_use_after_move() bool {
    f := compile.internal.field_level_drop_flag.fldf_new()
    x := compile.internal.path.path_new("x")
    y := compile.internal.path.path_new("y")
    f = compile.internal.field_level_drop_flag.fldf_declare(f, x, "Box")
    f = compile.internal.field_level_drop_flag.fldf_move(f, x, y, 10, 0)
    if compile.internal.field_level_drop_flag.fldf_has_errors(f) { return false }
    f = compile.internal.field_level_drop_flag.fldf_use(f, x)
    if !compile.internal.field_level_drop_flag.fldf_has_errors(f) { return false }
    true
}
func test_struct_field_move() bool {
    f := compile.internal.field_level_drop_flag.fldf_new()
    x := compile.internal.path.path_new("x")
    f = compile.internal.field_level_drop_flag.fldf_declare(f, x, "Pair")
    x_left := compile.internal.path.path_field(compile.internal.path.path_new("x"), "left")
    x_right := compile.internal.path.path_field(compile.internal.path.path_new("x"), "right")
    y := compile.internal.path.path_new("y")
    f = compile.internal.field_level_drop_flag.fldf_move(f, x_left, y, 20, 0)
    if compile.internal.field_level_drop_flag.fldf_has_errors(f) { return false }
    f = compile.internal.field_level_drop_flag.fldf_use(f, x_right)
    if compile.internal.field_level_drop_flag.fldf_has_errors(f) { return false }
    f = compile.internal.field_level_drop_flag.fldf_use(f, x_left)
    if !compile.internal.field_level_drop_flag.fldf_has_errors(f) { return false }
    true
}
func test_struct_field_drop_order() bool {
    f := compile.internal.field_level_drop_flag.fldf_new()
    x := compile.internal.path.path_new("x")
    f = compile.internal.field_level_drop_flag.fldf_declare(f, x, "Pair")
    x_left := compile.internal.path.path_field(compile.internal.path.path_new("x"), "left")
    x_right := compile.internal.path.path_field(compile.internal.path.path_new("x"), "right")
    y := compile.internal.path.path_new("y")
    f = compile.internal.field_level_drop_flag.fldf_move(f, x_left, y, 30, 0)
    f_after, drops := compile.internal.field_level_drop_flag.fldf_scope_exit(f)
    if len(drops) != 2 { return false }
    true
}
func test_array_element_move() bool {
    f := compile.internal.field_level_drop_flag.fldf_new()
    v := compile.internal.path.path_new("v")
    f = compile.internal.field_level_drop_flag.fldf_declare(f, v, "[]Box")
    v_0 := compile.internal.path.path_index(compile.internal.path.path_new("v"), 0)
    x := compile.internal.path.path_new("x")
    f = compile.internal.field_level_drop_flag.fldf_move(f, v_0, x, 40, 0)
    if compile.internal.field_level_drop_flag.fldf_has_errors(f) { return false }
    f = compile.internal.field_level_drop_flag.fldf_use(f, v_0)
    if !compile.internal.field_level_drop_flag.fldf_has_errors(f) { return false }
    v_1 := compile.internal.path.path_index(compile.internal.path.path_new("v"), 1)
    f = compile.internal.field_level_drop_flag.fldf_use(f, v_1)
    if compile.internal.field_level_drop_flag.fldf_has_errors(f) { return false }
    true
}
func test_conditional_merge_same_state() bool {
    f_if := compile.internal.field_level_drop_flag.fldf_new()
    f_if = compile.internal.field_level_drop_flag.fldf_declare(f_if, compile.internal.path.path_new("x"), "Box")
    f_else := compile.internal.field_level_drop_flag.fldf_new()
    f_else = compile.internal.field_level_drop_flag.fldf_declare(f_else, compile.internal.path.path_new("x"), "Box")
    f_merged := compile.internal.field_level_drop_flag.fldf_merge_branches(f_if, f_else)
    f_merged = compile.internal.field_level_drop_flag.fldf_use(f_merged, compile.internal.path.path_new("x"))
    if compile.internal.field_level_drop_flag.fldf_has_errors(f_merged) { return false }
    true
}
func test_conditional_merge_different_state() bool {
    f_if := compile.internal.field_level_drop_flag.fldf_new()
    f_if = compile.internal.field_level_drop_flag.fldf_declare(f_if, compile.internal.path.path_new("x"), "Box")
    y := compile.internal.path.path_new("y")
    f_if = compile.internal.field_level_drop_flag.fldf_move(f_if, compile.internal.path.path_new("x"), y, 50, 0)
    f_else := compile.internal.field_level_drop_flag.fldf_new()
    f_else = compile.internal.field_level_drop_flag.fldf_declare(f_else, compile.internal.path.path_new("x"), "Box")
    f_merged := compile.internal.field_level_drop_flag.fldf_merge_branches(f_if, f_else)
    f_merged = compile.internal.field_level_drop_flag.fldf_use(f_merged, compile.internal.path.path_new("x"))
    true
}
func test_nested_field_access() bool {
    f := compile.internal.field_level_drop_flag.fldf_new()
    x := compile.internal.path.path_new("x")
    f = compile.internal.field_level_drop_flag.fldf_declare(f, x, "Outer")
    x_in_value := compile.internal.path.path_field(compile.internal.path.path_field(compile.internal.path.path_new("x"), "in"), "value")
    y := compile.internal.path.path_new("y")
    f = compile.internal.field_level_drop_flag.fldf_move(f, x_in_value, y, 60, 0)
    if compile.internal.field_level_drop_flag.fldf_has_errors(f) { return false }
    f = compile.internal.field_level_drop_flag.fldf_use(f, x_in_value)
    if !compile.internal.field_level_drop_flag.fldf_has_errors(f) { return false }
    true
}
func test_partial_move_two_fields() bool {
    f := compile.internal.field_level_drop_flag.fldf_new()
    p := compile.internal.path.path_new("p")
    f = compile.internal.field_level_drop_flag.fldf_declare(f, p, "Pair")
    p_left := compile.internal.path.path_field(compile.internal.path.path_new("p"), "left")
    p_right := compile.internal.path.path_field(compile.internal.path.path_new("p"), "right")
    y := compile.internal.path.path_new("y")
    z := compile.internal.path.path_new("z")
    f = compile.internal.field_level_drop_flag.fldf_move(f, p_left, y, 70, 0)
    f = compile.internal.field_level_drop_flag.fldf_move(f, p_right, z, 71, 0)
    f, drops := compile.internal.field_level_drop_flag.fldf_scope_exit(f)
    if len(drops) < 2 { return false }
    true
}
func test_reassignment_after_move() bool {
    f := compile.internal.field_level_drop_flag.fldf_new()
    x := compile.internal.path.path_new("x")
    f = compile.internal.field_level_drop_flag.fldf_declare(f, x, "Box")
    y := compile.internal.path.path_new("y")
    f = compile.internal.field_level_drop_flag.fldf_move(f, x, y, 80, 0)
    f = compile.internal.field_level_drop_flag.fldf_reassign(f, x, "Box")
    f = compile.internal.field_level_drop_flag.fldf_use(f, x)
    if compile.internal.field_level_drop_flag.fldf_has_errors(f) { return false }
    true
}
func test_scope_lifo_drop_order() bool {
    f := compile.internal.field_level_drop_flag.fldf_new()
    x := compile.internal.path.path_new("x")
    y := compile.internal.path.path_new("y")
    z := compile.internal.path.path_new("z")
    f = compile.internal.field_level_drop_flag.fldf_declare(f, x, "Box")
    f = compile.internal.field_level_drop_flag.fldf_declare(f, y, "Box")
    f = compile.internal.field_level_drop_flag.fldf_declare(f, z, "Box")
    f, drops := compile.internal.field_level_drop_flag.fldf_scope_exit(f)
    if len(drops) != 3 { return false }
    true
}
func run_field_level_drop_tests() bool {
    tests_passed := 0
    tests_total := 0
    tests_total = tests_total + 1
    if test_basic_declare_and_use() {
        tests_passed = tests_passed + 1
    }
    tests_total = tests_total + 1
    if test_use_after_move() {
        tests_passed = tests_passed + 1
    }
    tests_total = tests_total + 1
    if test_struct_field_move() {
        tests_passed = tests_passed + 1
    }
    tests_total = tests_total + 1
    if test_struct_field_drop_order() {
        tests_passed = tests_passed + 1
    }
    tests_total = tests_total + 1
    if test_array_element_move() {
        tests_passed = tests_passed + 1
    }
    tests_total = tests_total + 1
    if test_conditional_merge_same_state() {
        tests_passed = tests_passed + 1
    }
    tests_total = tests_total + 1
    if test_conditional_merge_different_state() {
        tests_passed = tests_passed + 1
    }
    tests_total = tests_total + 1
    if test_nested_field_access() {
        tests_passed = tests_passed + 1
    }
    tests_total = tests_total + 1
    if test_partial_move_two_fields() {
        tests_passed = tests_passed + 1
    }
    tests_total = tests_total + 1
    if test_reassignment_after_move() {
        tests_passed = tests_passed + 1
    }
    tests_total = tests_total + 1
    if test_scope_lifo_drop_order() {
        tests_passed = tests_passed + 1
    }
    println("════════════════════════════════════════════")
    println("Field-Level Drop Flag Tests")
    println("════════════════════════════════════════════")
    println("Passed: " + tests_passed + " / " + tests_total)
    println("════════════════════════════════════════════")
    tests_passed == tests_total
