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

func test_basic_declare_and_use() bool {
    f := fldf_new()
    x := path_new("x")

    f = fldf_declare(f, x, "Box")
    if fldf_has_errors(f) { return false }

    f = fldf_use(f, x)
    if fldf_has_errors(f) { return false }

    true
}

func test_use_after_move() bool {
    f := fldf_new()
    x := path_new("x")
    y := path_new("y")

    f = fldf_declare(f, x, "Box")

    f = fldf_move(f, x, y, 10, 0)
    if fldf_has_errors(f) { return false }

    f = fldf_use(f, x)
    if !fldf_has_errors(f) { return false }

    true
}

func test_struct_field_move() bool {
    f := fldf_new()

    x := path_new("x")
    f = fldf_declare(f, x, "Pair")

    x_left := path_field(path_new("x"), "left")
    x_right := path_field(path_new("x"), "right")
    y := path_new("y")

    f = fldf_move(f, x_left, y, 20, 0)
    if fldf_has_errors(f) { return false }

    f = fldf_use(f, x_right)
    if fldf_has_errors(f) { return false }

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

    f = fldf_move(f, x_left, y, 30, 0)

    f_after, drops := fldf_scope_exit(f)

    if len(drops) != 2 { return false }

    true
}

func test_array_element_move() bool {
    f := fldf_new()

    v := path_new("v")
    f = fldf_declare(f, v, "[]Box")

    v_0 := path_index(path_new("v"), 0)
    x := path_new("x")
    f = fldf_move(f, v_0, x, 40, 0)
    if fldf_has_errors(f) { return false }

    f = fldf_use(f, v_0)
    if !fldf_has_errors(f) { return false }

    v_1 := path_index(path_new("v"), 1)
    f = fldf_use(f, v_1)
    if fldf_has_errors(f) { return false }

    true
}

func test_conditional_merge_same_state() bool {

    f_if := fldf_new()
    f_if = fldf_declare(f_if, path_new("x"), "Box")

    f_else := fldf_new()
    f_else = fldf_declare(f_else, path_new("x"), "Box")

    f_merged := fldf_merge_branches(f_if, f_else)

    f_merged = fldf_use(f_merged, path_new("x"))
    if fldf_has_errors(f_merged) { return false }

    true
}

func test_conditional_merge_different_state() bool {

    f_if := fldf_new()
    f_if = fldf_declare(f_if, path_new("x"), "Box")
    y := path_new("y")
    f_if = fldf_move(f_if, path_new("x"), y, 50, 0)

    f_else := fldf_new()
    f_else = fldf_declare(f_else, path_new("x"), "Box")

    f_merged := fldf_merge_branches(f_if, f_else)

    f_merged = fldf_use(f_merged, path_new("x"))

    true
}

func test_nested_field_access() bool {
    f := fldf_new()

    x := path_new("x")
    f = fldf_declare(f, x, "Outer")

    x_in_value := path_field(path_field(path_new("x"), "in"), "value")

    y := path_new("y")
    f = fldf_move(f, x_in_value, y, 60, 0)
    if fldf_has_errors(f) { return false }

    f = fldf_use(f, x_in_value)
    if !fldf_has_errors(f) { return false }

    true
}

func test_partial_move_two_fields() bool {
    f := fldf_new()

    p := path_new("p")
    f = fldf_declare(f, p, "Pair")

    p_left := path_field(path_new("p"), "left")
    p_right := path_field(path_new("p"), "right")

    y := path_new("y")
    z := path_new("z")

    f = fldf_move(f, p_left, y, 70, 0)
    f = fldf_move(f, p_right, z, 71, 0)

    f, drops := fldf_scope_exit(f)

    if len(drops) < 2 { return false }

    true
}

func test_reassignment_after_move() bool {
    f := fldf_new()

    x := path_new("x")
    f = fldf_declare(f, x, "Box")

    y := path_new("y")
    f = fldf_move(f, x, y, 80, 0)

    f = fldf_reassign(f, x, "Box")

    f = fldf_use(f, x)
    if fldf_has_errors(f) { return false }

    true
}

func test_scope_lifo_drop_order() bool {
    f := fldf_new()

    x := path_new("x")
    y := path_new("y")
    z := path_new("z")

    f = fldf_declare(f, x, "Box")
    f = fldf_declare(f, y, "Box")
    f = fldf_declare(f, z, "Box")

    f, drops := fldf_scope_exit(f)

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
}