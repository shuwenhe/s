package compile.internal.tests.test_typesys
import (
    "compile.internal.typesys"
)
func run_typesys_suite() int {
    if !compile.internal.typesys.assignable_type("int", "u8") {
        return 1
    }
    if compile.internal.typesys.assignable_type("u8", "int") {
        return 1
    }
    if !compile.internal.typesys.compatible_type("(int, string)", "(int, string)") {
        return 1
    }
    if compile.internal.typesys.compatible_type("(int, string)", "(int)") {
        return 1
    }
    if !compile.internal.typesys.assignable_type("(int, u64)", "(u8, u32)") {
        return 1
    }
    if compile.internal.typesys.assignable_type("(u8, u16)", "(int, u64)") {
        return 1
    }
    if !compile.internal.typesys.assignable_type("int[]", "nil") {
        return 1
    }
    if compile.internal.typesys.assignable_type("int[4]", "nil") {
        return 1
    }
    if !compile.internal.typesys.assignable_type("*int", "nil") {
        return 1
    }
    if !compile.internal.typesys.assignable_type("fn", "nil") {
        return 1
    }
    if compile.internal.typesys.assignable_type("int", "nil") {
        return 1
    }
    if !compile.internal.typesys.comparable_type("int") {
        return 1
    }
    if compile.internal.typesys.comparable_type("int[]") {
        return 1
    }
    if compile.internal.typesys.comparable_type("int[4]") {
        return 1
    }
    if compile.internal.typesys.comparable_type("map") {
        return 1
    }
    if compile.internal.typesys.comparable_type("fn") {
        return 1
    }
    if !compile.internal.typesys.comparable_type("(int, bool)") {
        return 1
    }
    if compile.internal.typesys.comparable_type("(int, int[])") {
        return 1
    }
    if !compile.internal.typesys.is_copy_type("int") || !compile.internal.typesys.is_copy_type("&int") {
        return 1
    }
    if !compile.internal.typesys.is_copy_type("int[4]") {
        return 1
    }
    if compile.internal.typesys.is_copy_type("string") || compile.internal.typesys.is_copy_type("box[int]") || compile.internal.typesys.is_copy_type("int[]") {
        return 1
    }
    if compile.internal.typesys.ownership_mode("int") != "copy" || compile.internal.typesys.ownership_mode("&int") != "borrow" {
        return 1
    }
    if compile.internal.typesys.ownership_mode("box[int]") != "owned" || compile.internal.typesys.ownership_mode("string") != "move" {
        return 1
    }
    if !compile.internal.typesys.requires_drop("box[int]") || !compile.internal.typesys.requires_drop("string") || compile.internal.typesys.requires_drop("int") {
        return 1
    }
    0
}
