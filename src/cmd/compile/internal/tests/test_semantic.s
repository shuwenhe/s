package compile.internal.tests.test_semantic

use compile.internal.semantic.check_text
use std.fs.read_to_string

func run_semantic_suite(string fixtures_root) int32 {
    var ok_path = fixtures_root + "/check_ok.s"
    var fail_path = fixtures_root + "/check_fail.s"

    var ok_source_result = read_to_string(ok_path)
    if ok_source_result.is_err() {
        return 1
    }
    var fail_source_result = read_to_string(fail_path)
    if fail_source_result.is_err() {
        return 1
    }

    if check_text(ok_source_result.unwrap()) != 0 {
        return 1
    }
    if check_text(fail_source_result.unwrap()) == 0 {
        return 1
    }

    var inline_ok = "package demo.inline\nfunc add(int32 a, int32 b) int32 {\n    var sum: int32 = a + b\n    sum\n}"
    if check_text(inline_ok) != 0 {
        return 1
    }

    var inline_fail = "package demo.inline\nfunc broken() bool {\n    var flag: bool = 1\n    flag\n}"
    if check_text(inline_fail) == 0 {
        return 1
    }

    var call_ok = "package demo.call\nfunc add(int32 a, int32 b) int32 {\n  a + b\n}\nfunc main() int32 {\n  add(1, 2)\n}"
    if check_text(call_ok) != 0 {
        return 1
    }

    var call_fail = "package demo.call\nfunc add(int32 a, int32 b) int32 {\n  a + b\n}\nfunc main() int32 {\n  add(1, true)\n}"
    if check_text(call_fail) == 0 {
        return 1
    }

    var call_undefined_fail = "package demo.call\nfunc main() int32 {\n  missing(1)\n}"
    if check_text(call_undefined_fail) == 0 {
        return 1
    }

    var overload_ok = "package demo.call\nfunc f[t](t v) t {\n  v\n}\nfunc f(int32 v) int32 {\n  v + 1\n}\nfunc main() int32 {\n  f(1)\n}"
    if check_text(overload_ok) != 0 {
        return 1
    }

    var overload_generic_ok = "package demo.call\nfunc pick[t](t a, t b) t {\n  a\n}\nfunc main() int32 {\n  pick(1, 2)\n}"
    if check_text(overload_generic_ok) != 0 {
        return 1
    }

    var overload_generic_fail = "package demo.call\nfunc pick[t](t a, t b) t {\n  a\n}\nfunc main() int32 {\n  pick(1, true)\n}"
    if check_text(overload_generic_fail) == 0 {
        return 1
    }

    var overload_ambiguous_fail = "package demo.call\nfunc g[t](t v) t {\n  v\n}\nfunc g[u](u v) u {\n  v\n}\nfunc main() int32 {\n  g(1)\n}"
    if check_text(overload_ambiguous_fail) == 0 {
        return 1
    }

    var option_match_ok = "package demo.switch\nfunc f(option[int32] value) int32 {\n  switch value {\n    some(v) : v,\n    none : 0,\n  }\n}"
    if check_text(option_match_ok) != 0 {
        return 1
    }

    var option_match_exhaust_fail = "package demo.switch\nfunc f(option[int32] value) int32 {\n  switch value {\n    some(v) : v,\n  }\n}"
    if check_text(option_match_exhaust_fail) == 0 {
        return 1
    }

    var option_match_duplicate_fail = "package demo.switch\nfunc f(option[int32] value) int32 {\n  switch value {\n    some(v) : v,\n    some(w) : w,\n    none : 0,\n  }\n}"
    if check_text(option_match_duplicate_fail) == 0 {
        return 1
    }

    var option_match_unreachable_fail = "package demo.switch\nfunc f(option[int32] value) int32 {\n  switch value {\n    _ : 0,\n    some(v) : v,\n  }\n}"
    if check_text(option_match_unreachable_fail) == 0 {
        return 1
    }

    var option_match_bind_type_fail = "package demo.switch\nfunc f(option[int32] value) bool {\n  switch value {\n    some(v) : v,\n    none : false,\n  }\n}"
    if check_text(option_match_bind_type_fail) == 0 {
        return 1
    }

    var result_match_ok = "package demo.switch\nfunc f(result[int32, string] value) int32 {\n  switch value {\n    ok(v) : v,\n    err(e) : 0,\n  }\n}"
    if check_text(result_match_ok) != 0 {
        return 1
    }

    var result_match_exhaust_fail = "package demo.switch\nfunc f(result[int32, string] value) int32 {\n  switch value {\n    ok(v) : v,\n  }\n}"
    if check_text(result_match_exhaust_fail) == 0 {
        return 1
    }

    var result_match_duplicate_fail = "package demo.switch\nfunc f(result[int32, string] value) int32 {\n  switch value {\n    ok(v) : v,\n    err(e) : 0,\n    err(e2) : 1,\n  }\n}"
    if check_text(result_match_duplicate_fail) == 0 {
        return 1
    }

    var option_nested_payload_fail = "package demo.switch\nfunc f(option[int32] value) int32 {\n  switch value {\n    some(ok(v)) : v,\n    none : 0,\n  }\n}"
    if check_text(option_nested_payload_fail) == 0 {
        return 1
    }

    var nested_ok = "package demo.switch\nfunc f(option[result[int32, string]] value) int32 {\n  switch value {\n    some(ok(v)) : v,\n    some(err(e)) : 0,\n    none : 0,\n  }\n}"
    if check_text(nested_ok) != 0 {
        return 1
    }

    0
}
