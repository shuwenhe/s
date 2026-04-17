package compile.internal.tests.test_semantic

use compile.internal.semantic.CheckText
use std.fs.ReadToString

func RunSemanticSuite(String fixtures_root) -> i32 {
    var ok_path = fixtures_root + "/check_ok.s"
    var fail_path = fixtures_root + "/check_fail.s"

    var ok_source_result = ReadToString(ok_path)
    if ok_source_result.is_err() {
        return 1
    }
    var fail_source_result = ReadToString(fail_path)
    if fail_source_result.is_err() {
        return 1
    }

    if CheckText(ok_source_result.unwrap()) != 0 {
        return 1
    }
    if CheckText(fail_source_result.unwrap()) == 0 {
        return 1
    }

    var inline_ok = "package demo.inline\nfunc add(i32 a, i32 b) -> i32 {\n    var sum: i32 = a + b\n    sum\n}"
    if CheckText(inline_ok) != 0 {
        return 1
    }

    var inline_fail = "package demo.inline\nfunc broken() -> bool {\n    var flag: bool = 1\n    flag\n}"
    if CheckText(inline_fail) == 0 {
        return 1
    }

    0
}
