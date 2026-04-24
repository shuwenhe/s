package compile.internal.tests.test_typesys

use compile.internal.typesys.assignable_type
use compile.internal.typesys.comparable_type
use compile.internal.typesys.compatible_type

func run_typesys_suite() int {
    if !assignable_type("int", "u8") {
        return 1
    }
    if assignable_type("u8", "int") {
        return 1
    }

    if !compatible_type("(int, string)", "(int, string)") {
        return 1
    }
    if compatible_type("(int, string)", "(int)") {
        return 1
    }

    if !assignable_type("(int, u64)", "(u8, u32)") {
        return 1
    }
    if assignable_type("(u8, u16)", "(int, u64)") {
        return 1
    }
    if !assignable_type("[]int", "nil") {
        return 1
    }
    if !assignable_type("&int", "nil") {
        return 1
    }
    if !assignable_type("fn", "nil") {
        return 1
    }
    if assignable_type("int", "nil") {
        return 1
    }

    if !comparable_type("int") {
        return 1
    }
    if comparable_type("[]int") {
        return 1
    }
    if comparable_type("map") {
        return 1
    }
    if comparable_type("fn") {
        return 1
    }
    if !comparable_type("(int, bool)") {
        return 1
    }
    if comparable_type("(int, []int)") {
        return 1
    }

    0
}
