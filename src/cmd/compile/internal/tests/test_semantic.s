package compile.internal.tests.test_semantic

use compile.internal.semantic.check_text
use compile.internal.semantic.check_detailed
use compile.internal.semantic.semantic_error
use std.fs.read_to_string

func run_semantic_suite(string fixtures_root) int {
    let ok_path = fixtures_root + "/check_ok.s"
    let fail_path = fixtures_root + "/check_fail.s"

    let ok_source_result = read_to_string(ok_path)
    if ok_source_result.is_err() {
        return 1
    }
    let fail_source_result = read_to_string(fail_path)
    if fail_source_result.is_err() {
        return 1
    }

    if check_text(ok_source_result.unwrap()) != 0 {
        return 1
    }
    if check_text(fail_source_result.unwrap()) == 0 {
        return 1
    }

    let inline_ok = "package demo.inline\nfunc add(int a, int b) int {\n    let sum: int = a + b\n    sum\n}"
    if check_text(inline_ok) != 0 {
        return 1
    }

    let inline_fail = "package demo.inline\nfunc broken() bool {\n    let flag: bool = 1\n    flag\n}"
    if check_text(inline_fail) == 0 {
        return 1
    }

    let call_ok = "package demo.call\nfunc add(int a, int b) int {\n  a + b\n}\nfunc main() int {\n  add(1, 2)\n}"
    if check_text(call_ok) != 0 {
        return 1
    }

    let call_fail = "package demo.call\nfunc add(int a, int b) int {\n  a + b\n}\nfunc main() int {\n  add(1, true)\n}"
    if check_text(call_fail) == 0 {
        return 1
    }

    let call_undefined_fail = "package demo.call\nfunc main() int {\n  missing(1)\n}"
    if check_text(call_undefined_fail) == 0 {
        return 1
    }

    let overload_ok = "package demo.call\nfunc f[t](t v) t {\n  v\n}\nfunc f(int v) int {\n  v + 1\n}\nfunc main() int {\n  f(1)\n}"
    if check_text(overload_ok) != 0 {
        return 1
    }

    let overload_generic_ok = "package demo.call\nfunc pick[t](t a, t b) t {\n  a\n}\nfunc main() int {\n  pick(1, 2)\n}"
    if check_text(overload_generic_ok) != 0 {
        return 1
    }

    let overload_generic_fail = "package demo.call\nfunc pick[t](t a, t b) t {\n  a\n}\nfunc main() int {\n  pick(1, true)\n}"
    if check_text(overload_generic_fail) == 0 {
        return 1
    }

    let overload_ambiguous_fail = "package demo.call\nfunc g[t](t v) t {\n  v\n}\nfunc g[u](u v) u {\n  v\n}\nfunc main() int {\n  g(1)\n}"
    if check_text(overload_ambiguous_fail) == 0 {
        return 1
    }

    let option_match_ok = "package demo.switch\nfunc f(option[int] value) int {\n  switch value {\n    some(v) : v,\n    none : 0,\n  }\n}"
    if check_text(option_match_ok) != 0 {
        return 1
    }

    let option_match_exhaust_fail = "package demo.switch\nfunc f(option[int] value) int {\n  switch value {\n    some(v) : v,\n  }\n}"
    if check_text(option_match_exhaust_fail) == 0 {
        return 1
    }

    let option_match_duplicate_fail = "package demo.switch\nfunc f(option[int] value) int {\n  switch value {\n    some(v) : v,\n    some(w) : w,\n    none : 0,\n  }\n}"
    if check_text(option_match_duplicate_fail) == 0 {
        return 1
    }

    let option_match_unreachable_fail = "package demo.switch\nfunc f(option[int] value) int {\n  switch value {\n    _ : 0,\n    some(v) : v,\n  }\n}"
    if check_text(option_match_unreachable_fail) == 0 {
        return 1
    }

    let option_match_bind_type_fail = "package demo.switch\nfunc f(option[int] value) bool {\n  switch value {\n    some(v) : v,\n    none : false,\n  }\n}"
    if check_text(option_match_bind_type_fail) == 0 {
        return 1
    }

    let result_match_ok = "package demo.switch\nfunc f(result[int, string] value) int {\n  switch value {\n    ok(v) : v,\n    err(e) : 0,\n  }\n}"
    if check_text(result_match_ok) != 0 {
        return 1
    }

    let result_match_exhaust_fail = "package demo.switch\nfunc f(result[int, string] value) int {\n  switch value {\n    ok(v) : v,\n  }\n}"
    if check_text(result_match_exhaust_fail) == 0 {
        return 1
    }

    let result_match_duplicate_fail = "package demo.switch\nfunc f(result[int, string] value) int {\n  switch value {\n    ok(v) : v,\n    err(e) : 0,\n    err(e2) : 1,\n  }\n}"
    if check_text(result_match_duplicate_fail) == 0 {
        return 1
    }

    let option_nested_payload_fail = "package demo.switch\nfunc f(option[int] value) int {\n  switch value {\n    some(ok(v)) : v,\n    none : 0,\n  }\n}"
    if check_text(option_nested_payload_fail) == 0 {
        return 1
    }

    let nested_ok = "package demo.switch\nfunc f(option[result[int, string]] value) int {\n  switch value {\n    some(ok(v)) : v,\n    some(err(e)) : 0,\n    none : 0,\n  }\n}"
    if check_text(nested_ok) != 0 {
        return 1
    }

    let diag_src = "package main\nfunc main() int {\n  missing(1)\n  missing(1)\n  0\n}"
    let diagnostics = check_detailed(diag_src)
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

    let saw_summary = false
    let i = 0
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

    let control_src = "package demo.ctrl\nfunc main() int {\n  goto L1\n  0\n}"
    let control_diags = check_detailed(control_src)
    if !has_code(control_diags, "e3022") {
        return 1
    }

    let recover_src = "package demo.recover\nfunc main() int {\n  recover()\n  0\n}"
    let recover_diags = check_detailed(recover_src)
    if !has_code(recover_diags, "e3025") {
        return 1
    }
    if !has_code(recover_diags, "e3033") {
        return 1
    }

    let go_uncoordinated_src = "package demo.conc\nfunc worker() int {\n  0\n}\nfunc main() int {\n  go(\"worker\")\n  0\n}"
    let go_uncoordinated_diags = check_detailed(go_uncoordinated_src)
    if !has_code(go_uncoordinated_diags, "e3047") {
        return 1
    }

    let sroutine_uncoordinated_src = "package demo.conc\nfunc worker() int {\n  0\n}\nfunc main() int {\n  sroutine worker()\n  0\n}"
    let sroutine_uncoordinated_diags = check_detailed(sroutine_uncoordinated_src)
    if !has_code(sroutine_uncoordinated_diags, "e3047") {
        return 1
    }

    let send_without_recv_src = "package demo.conc\nfunc main() int {\n  let ch = chan_make(1)\n  chan_send(ch, 1)\n  0\n}"
    let send_without_recv_diags = check_detailed(send_without_recv_src)
    if !has_code(send_without_recv_diags, "e3050") {
        return 1
    }

    let select_without_recv_src = "package demo.conc\nfunc main() int {\n  let chs = vec[chan]()\n  select_recv(chs)\n  0\n}"
    let select_without_recv_diags = check_detailed(select_without_recv_src)
    if !has_code(select_without_recv_diags, "e3048") {
        return 1
    }

    let close_overflow_src = "package demo.conc\nfunc main() int {\n  let ch = chan_make(1)\n  chan_close(ch)\n  chan_close(ch)\n  0\n}"
    let close_overflow_diags = check_detailed(close_overflow_src)
    if !has_code(close_overflow_diags, "e3049") {
        return 1
    }

    let panic_src = "package demo.recover\nfunc main() int {\n  panic(\"x\")\n}"
    let panic_diags = check_detailed(panic_src)
    if !has_code(panic_diags, "e3026") {
        return 1
    }
    if !has_code(panic_diags, "e3032") {
        return 1
    }

    let impl_src = "package demo.impl\nimpl Box[T] {\n}"
    let impl_diags = check_detailed(impl_src)
    if !has_code(impl_diags, "e3028") {
        return 1
    }
    if !has_code(impl_diags, "e3030") {
        return 1
    }

    let embed_src = "package demo.impl\nembed Foo\n"
    let embed_diags = check_detailed(embed_src)
    if !has_code(embed_diags, "e3035") {
        return 1
    }

    let complex_goto_src = "package demo.ctrl\nfunc main() int {\n  label L1\n  if true {\n    switch 1 {\n      1 : goto L1,\n      _ : 0,\n    }\n  }\n  0\n}"
    let complex_diags = check_detailed(complex_goto_src)
    if !has_code(complex_diags, "e3037") {
        return 1
    }

    let non_comparable_eq_src = "package demo.eq\nfunc main() int {\n  let a = map[string]func() int{}\n  let b = map[string]func() int{}\n  if a == b {\n    1\n  } else {\n    0\n  }\n}"
    let non_comparable_eq_diags = check_detailed(non_comparable_eq_src)
    if !has_code(non_comparable_eq_diags, "e3039") {
        return 1
    }

    let trait_impl_ok = "package demo.iface\ntrait Adder {\n  func add(int a, int b) int;\n}\nimpl Adder for Calc where Calc {\n  func add(int a, int b) int {\n    a + b\n  }\n}\nfunc main() int {\n  0\n}"
    if check_text(trait_impl_ok) != 0 {
        return 1
    }

    let trait_impl_missing = "package demo.iface\ntrait Adder {\n  func add(int a, int b) int;\n}\nimpl Adder for Calc where Calc {\n  func sub(int a, int b) int {\n    a - b\n  }\n}\nfunc main() int {\n  0\n}"
    let trait_impl_missing_diags = check_detailed(trait_impl_missing)
    if !has_code(trait_impl_missing_diags, "e3041") {
        return 1
    }

    let trait_impl_sig_mismatch = "package demo.iface\ntrait Adder {\n  func add(int a, int b) int;\n}\nimpl Adder for Calc where Calc {\n  func add(bool a, int b) int {\n    b\n  }\n}\nfunc main() int {\n  0\n}"
    let trait_impl_sig_diags = check_detailed(trait_impl_sig_mismatch)
    if !has_code(trait_impl_sig_diags, "e3043") {
        return 1
    }

    let trait_impl_receiver_mismatch = "package demo.iface\ntrait Reader {\n  func read(File self, int count) int;\n}\nimpl Reader for File where File {\n  func read(&File self, int count) int {\n    count\n  }\n}\nfunc main() int {\n  0\n}"
    let trait_impl_receiver_diags = check_detailed(trait_impl_receiver_mismatch)
    if !has_code(trait_impl_receiver_diags, "e3043") {
        return 1
    }

    let method_call_ok = "package demo.method\nstruct Point {\n  int x\n}\ntrait Measure {\n  func size(Point self) int;\n}\nimpl Measure for Point where Point {\n  func size(Point self) int {\n    self.x\n  }\n}\nfunc main() int {\n  let p = Point { x: 4 }\n  p.size()\n}"
    if check_text(method_call_ok) != 0 {
        return 1
    }

    let method_ref_ok = "package demo.method\nstruct Reader {\n  int count\n}\ntrait Peek {\n  func peek(&Reader self) int;\n}\nimpl Peek for Reader where Reader {\n  func peek(&Reader self) int {\n    self.count\n  }\n}\nfunc main() int {\n  let reader = Reader { count: 2 }\n  reader.peek()\n}"
    if check_text(method_ref_ok) != 0 {
        return 1
    }

    let method_temp_ref_fail = "package demo.method\nstruct Reader {\n  int count\n}\ntrait Peek {\n  func peek(&Reader self) int;\n}\nimpl Peek for Reader where Reader {\n  func peek(&Reader self) int {\n    self.count\n  }\n}\nfunc make_reader() Reader {\n  Reader { count: 2 }\n}\nfunc main() int {\n  make_reader().peek()\n}"
    let method_temp_ref_diags = check_detailed(method_temp_ref_fail)
    if !has_code(method_temp_ref_diags, "e3051") {
        return 1
    }

    let method_mut_ref_ok = "package demo.method\nstruct Counter {\n  int count\n}\ntrait Bump {\n  func bump(&mut Counter self) int;\n}\nimpl Bump for Counter where Counter {\n  func bump(&mut Counter self) int {\n    self.count\n  }\n}\nfunc main() int {\n  let counter = Counter { count: 2 }\n  counter.bump()\n}"
    if check_text(method_mut_ref_ok) != 0 {
        return 1
    }

    let method_temp_mut_ref_fail = "package demo.method\nstruct Counter {\n  int count\n}\ntrait Bump {\n  func bump(&mut Counter self) int;\n}\nimpl Bump for Counter where Counter {\n  func bump(&mut Counter self) int {\n    self.count\n  }\n}\nfunc make_counter() Counter {\n  Counter { count: 2 }\n}\nfunc main() int {\n  make_counter().bump()\n}"
    let method_temp_mut_ref_diags = check_detailed(method_temp_mut_ref_fail)
    if !has_code(method_temp_mut_ref_diags, "e3051") {
        return 1
    }

    let trait_impl_unknown = "package demo.iface\nimpl MissingTrait for Calc where Calc {\n  func add(int a, int b) int {\n    a + b\n  }\n}\nfunc main() int {\n  0\n}"
    let trait_impl_unknown_diags = check_detailed(trait_impl_unknown)
    if !has_code(trait_impl_unknown_diags, "e3040") {
        return 1
    }

    let trait_impl_duplicate_method = "package demo.iface\ntrait Adder {\n  func add(int a, int b) int;\n}\nimpl Adder for Calc where Calc {\n  func add(int a, int b) int {\n    a + b\n  }\n  func add(int a, int b) int {\n    a\n  }\n}\nfunc main() int {\n  0\n}"
    let trait_impl_dup_diags = check_detailed(trait_impl_duplicate_method)
    if !has_code(trait_impl_dup_diags, "e3042") {
        return 1
    }

    let const_iota_ok = "package demo.consts\nconst A = iota\nconst B = iota\nfunc main() int {\n  A + B\n}"
    if check_text(const_iota_ok) != 0 {
        return 1
    }

    let const_ref_ok = "package demo.consts\nconst Base = 3\nconst Sum = Base + 2\nfunc main() int {\n  Sum\n}"
    if check_text(const_ref_ok) != 0 {
        return 1
    }

    let iota_outside_const_fail = "package demo.consts\nfunc main() int {\n  iota\n}"
    if check_text(iota_outside_const_fail) == 0 {
        return 1
    }

    let duplicate_const_fail = "package demo.consts\nconst A = 1\nconst A = 2\nfunc main() int {\n  A\n}"
    let duplicate_const_diags = check_detailed(duplicate_const_fail)
    if !has_code(duplicate_const_diags, "e3044") {
        return 1
    }

    let const_group_ok = "package demo.consts\nconst (\n  A = iota\n  B\n  C = A + 1\n)\nfunc main() int {\n  C\n}"
    if check_text(const_group_ok) != 0 {
        return 1
    }

    let const_group_missing_init_fail = "package demo.consts\nconst (\n  A\n)\nfunc main() int {\n  0\n}"
    let const_group_missing_diags = check_detailed(const_group_missing_init_fail)
    if !has_code(const_group_missing_diags, "e3045") {
        return 1
    }

    let const_iota_increment_value_ok = "package demo.consts\nconst (\n  A = iota\n  B\n)\nconst C = 10 / B\nfunc main() int {\n  C\n}"
    if check_text(const_iota_increment_value_ok) != 0 {
        return 1
    }

    let const_iota_div_zero_fail = "package demo.consts\nconst (\n  A = iota\n  B = 10 / A\n)\nfunc main() int {\n  0\n}"
    let const_iota_div_zero_diags = check_detailed(const_iota_div_zero_fail)
    if !has_code(const_iota_div_zero_diags, "e3046") {
        return 1
    }

    let nil_assign_ok = "package demo.nil\nfunc main() int {\n  let f: fn = nil\n  if f == nil {\n    0\n  } else {\n    1\n  }\n}"
    if check_text(nil_assign_ok) != 0 {
        return 1
    }

    let nil_assign_fail = "package demo.nil\nfunc main() int {\n  let x: int = nil\n  x\n}"
    if check_text(nil_assign_fail) == 0 {
        return 1
    }

    0
}

func has_code(vec[semantic_error] diagnostics, string code) bool {
    let i = 0
    while i < diagnostics.len() {
        if diagnostics[i].code == code {
            return true
        }
        i = i + 1
    }
    false
}
