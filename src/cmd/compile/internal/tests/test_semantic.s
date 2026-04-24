package compile.internal.tests.test_semantic

use compile.internal.semantic.check_text
use compile.internal.semantic.check_detailed
use compile.internal.semantic.semantic_error
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

    var diag_src = "package main\nfunc main() int32 {\n  missing(1)\n  missing(1)\n  0\n}"
    var diagnostics = check_detailed(diag_src)
    if diagnostics.len() == 0 {
        return 1
    }
    if diagnostics[0].severity == "" {
        return 1
    }
    if diagnostics[0].hint == "" {
        return 1
    }
    if diagnostics[0].repeat_count < 1 {
        return 1
    }
    if diagnostics[0].anchor == "" {
        return 1
    }
    if diagnostics[0].stage != "semantic" {
        return 1
    }
    if diagnostics[0].chain_id == "" {
        return 1
    }

    var saw_summary = false
    var i = 0
    while i < diagnostics.len() {
        if diagnostics[i].code == "s0001" {
            saw_summary = true
            if diagnostics[i].upstream_code == "" {
                return 1
            }
        }
        i = i + 1
    }
    if !saw_summary {
        return 1
    }

    var control_src = "package demo.ctrl\nfunc main() int32 {\n  goto L1\n  0\n}"
    var control_diags = check_detailed(control_src)
    if !has_code(control_diags, "e3022") {
        return 1
    }

    var recover_src = "package demo.recover\nfunc main() int32 {\n  recover()\n  0\n}"
    var recover_diags = check_detailed(recover_src)
    if !has_code(recover_diags, "e3025") {
        return 1
    }
    if !has_code(recover_diags, "e3033") {
        return 1
    }

    var panic_src = "package demo.recover\nfunc main() int32 {\n  panic(\"x\")\n}"
    var panic_diags = check_detailed(panic_src)
    if !has_code(panic_diags, "e3026") {
        return 1
    }
    if !has_code(panic_diags, "e3032") {
        return 1
    }

    var impl_src = "package demo.impl\nimpl Box[T] {\n}"
    var impl_diags = check_detailed(impl_src)
    if !has_code(impl_diags, "e3028") {
        return 1
    }
    if !has_code(impl_diags, "e3030") {
        return 1
    }

    var embed_src = "package demo.impl\nembed Foo\n"
    var embed_diags = check_detailed(embed_src)
    if !has_code(embed_diags, "e3035") {
        return 1
    }

    var complex_goto_src = "package demo.ctrl\nfunc main() int32 {\n  label L1\n  if true {\n    switch 1 {\n      1 : goto L1,\n      _ : 0,\n    }\n  }\n  0\n}"
    var complex_diags = check_detailed(complex_goto_src)
    if !has_code(complex_diags, "e3037") {
        return 1
    }

    var non_comparable_eq_src = "package demo.eq\nfunc main() int32 {\n  var a = map[string]func() int32{}\n  var b = map[string]func() int32{}\n  if a == b {\n    1\n  } else {\n    0\n  }\n}"
    var non_comparable_eq_diags = check_detailed(non_comparable_eq_src)
    if !has_code(non_comparable_eq_diags, "e3039") {
        return 1
    }

    var trait_impl_ok = "package demo.iface\ntrait Adder {\n  func add(int32 a, int32 b) int32;\n}\nimpl Adder for Calc where Calc {\n  func add(int32 a, int32 b) int32 {\n    a + b\n  }\n}\nfunc main() int32 {\n  0\n}"
    if check_text(trait_impl_ok) != 0 {
        return 1
    }

    var trait_impl_missing = "package demo.iface\ntrait Adder {\n  func add(int32 a, int32 b) int32;\n}\nimpl Adder for Calc where Calc {\n  func sub(int32 a, int32 b) int32 {\n    a - b\n  }\n}\nfunc main() int32 {\n  0\n}"
    var trait_impl_missing_diags = check_detailed(trait_impl_missing)
    if !has_code(trait_impl_missing_diags, "e3041") {
        return 1
    }

    var trait_impl_sig_mismatch = "package demo.iface\ntrait Adder {\n  func add(int32 a, int32 b) int32;\n}\nimpl Adder for Calc where Calc {\n  func add(bool a, int32 b) int32 {\n    b\n  }\n}\nfunc main() int32 {\n  0\n}"
    var trait_impl_sig_diags = check_detailed(trait_impl_sig_mismatch)
    if !has_code(trait_impl_sig_diags, "e3043") {
        return 1
    }

    var trait_impl_unknown = "package demo.iface\nimpl MissingTrait for Calc where Calc {\n  func add(int32 a, int32 b) int32 {\n    a + b\n  }\n}\nfunc main() int32 {\n  0\n}"
    var trait_impl_unknown_diags = check_detailed(trait_impl_unknown)
    if !has_code(trait_impl_unknown_diags, "e3040") {
        return 1
    }

    var trait_impl_duplicate_method = "package demo.iface\ntrait Adder {\n  func add(int32 a, int32 b) int32;\n}\nimpl Adder for Calc where Calc {\n  func add(int32 a, int32 b) int32 {\n    a + b\n  }\n  func add(int32 a, int32 b) int32 {\n    a\n  }\n}\nfunc main() int32 {\n  0\n}"
    var trait_impl_dup_diags = check_detailed(trait_impl_duplicate_method)
    if !has_code(trait_impl_dup_diags, "e3042") {
        return 1
    }

    var const_iota_ok = "package demo.consts\nconst A = iota\nconst B = iota\nfunc main() int32 {\n  A + B\n}"
    if check_text(const_iota_ok) != 0 {
        return 1
    }

    var const_ref_ok = "package demo.consts\nconst Base = 3\nconst Sum = Base + 2\nfunc main() int32 {\n  Sum\n}"
    if check_text(const_ref_ok) != 0 {
        return 1
    }

    var iota_outside_const_fail = "package demo.consts\nfunc main() int32 {\n  iota\n}"
    if check_text(iota_outside_const_fail) == 0 {
        return 1
    }

    var duplicate_const_fail = "package demo.consts\nconst A = 1\nconst A = 2\nfunc main() int32 {\n  A\n}"
    var duplicate_const_diags = check_detailed(duplicate_const_fail)
    if !has_code(duplicate_const_diags, "e3044") {
        return 1
    }

    var const_group_ok = "package demo.consts\nconst (\n  A = iota\n  B\n  C = A + 1\n)\nfunc main() int32 {\n  C\n}"
    if check_text(const_group_ok) != 0 {
        return 1
    }

    var const_group_missing_init_fail = "package demo.consts\nconst (\n  A\n)\nfunc main() int32 {\n  0\n}"
    var const_group_missing_diags = check_detailed(const_group_missing_init_fail)
    if !has_code(const_group_missing_diags, "e3045") {
        return 1
    }

    var const_iota_increment_value_ok = "package demo.consts\nconst (\n  A = iota\n  B\n)\nconst C = 10 / B\nfunc main() int32 {\n  C\n}"
    if check_text(const_iota_increment_value_ok) != 0 {
        return 1
    }

    var const_iota_div_zero_fail = "package demo.consts\nconst (\n  A = iota\n  B = 10 / A\n)\nfunc main() int32 {\n  0\n}"
    var const_iota_div_zero_diags = check_detailed(const_iota_div_zero_fail)
    if !has_code(const_iota_div_zero_diags, "e3046") {
        return 1
    }

    0
}

func has_code(vec[semantic_error] diagnostics, string code) bool {
    var i = 0
    while i < diagnostics.len() {
        if diagnostics[i].code == code {
            return true
        }
        i = i + 1
    }
    false
}
