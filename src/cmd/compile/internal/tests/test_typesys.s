package compile.internal.tests.test_typesys

use compile.internal.typesys.assignable_type
use compile.internal.typesys.comparable_type
use compile.internal.typesys.compatible_type

func run_typesys_suite() int32 {
    if !assignable_type("int32", "u8") {
        return 1
    }
    if assignable_type("u8", "int32") {
        return 1
    }

    if !compatible_type("(int32, string)", "(int32, string)") {
        return 1
    }
    if compatible_type("(int32, string)", "(int32)") {
        return 1
    }

    if !assignable_type("(int32, u64)", "(u8, u32)") {
        return 1
    }
    if assignable_type("(u8, u16)", "(int32, u64)") {
        return 1
    }

    if !comparable_type("int32") {
        return 1
    }
    if comparable_type("[]int32") {
        return 1
    }
    if comparable_type("map") {
        return 1
    }
    if comparable_type("fn") {
        return 1
    }
    if !comparable_type("(int32, bool)") {
        return 1
    }
    if comparable_type("(int32, []int32)") {
        return 1
    }

    0
}
