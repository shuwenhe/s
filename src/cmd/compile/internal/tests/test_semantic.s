package compile.internal.tests.test_semantic
use compile.internal.semantic.check_text
use compile.internal.semantic.check_detailed
use compile.internal.semantic.semantic_error
use compile.internal.safety.prove_safety
use std.fs.read_to_string
func run_semantic_suite(string fixtures_root) int {
    ok_path := fixtures_root + "/check_ok.s"
    fail_path := fixtures_root + "/check_fail.s"
    ok_source_result := read_to_string(ok_path)
    if ok_source_result.is_err() {
        return 1
    }
    fail_source_result := read_to_string(fail_path)
    if fail_source_result.is_err() {
        return 1
    }
    if check_text(ok_source_result.unwrap()) != 0 {
        return 1
    }
    if check_text(fail_source_result.unwrap()) == 0 {
        return 1
    }
    inline_ok := "package demo.inline\nfunc add(int a, int b) int {\n    sum: int = a + b\n    sum\n}"
    if check_text(inline_ok) != 0 {
        return 1
    }
    inline_proof := prove_safety(inline_ok)
    if !inline_proof.proven || inline_proof.diagnostic_count != 0 {
        return 1
    }
    inline_fail := "package demo.inline\nfunc broken() bool {\n    flag: bool = 1\n    flag\n}"
    if check_text(inline_fail) == 0 {
        return 1
    }
    inline_fail_proof := prove_safety(inline_fail)
    if inline_fail_proof.proven || inline_fail_proof.type_errors == 0 {
        return 1
    }
    call_ok := "package demo.call\nfunc add(int a, int b) int {\n  a + b\n}\nfunc main() {\n  add(1, 2)\n}"
    if check_text(call_ok) != 0 {
        return 1
    }
    call_fail := "package demo.call\nfunc add(int a, int b) int {\n  a + b\n}\nfunc main() {\n  add(1, true)\n}"
    if check_text(call_fail) == 0 {
        return 1
    }
    call_undefined_fail := "package demo.call\nfunc main() {\n  missing(1)\n}"
    if check_text(call_undefined_fail) == 0 {
        return 1
    }
    array_ok := "package demo.array\nfunc first(int[4] data) int {\n  data[0]\n}"
    if check_text(array_ok) != 0 {
        return 1
    }
    overload_ok := "package demo.call\nfunc f[t](t v) t {\n  v\n}\nfunc f(int v) int {\n  v + 1\n}\nfunc main() {\n  f(1)\n}"
    if check_text(overload_ok) != 0 {
        return 1
    }
    overload_generic_ok := "package demo.call\nfunc pick[t](t a, t b) t {\n  a\n}\nfunc main() {\n  pick(1, 2)\n}"
    if check_text(overload_generic_ok) != 0 {
        return 1
    }
    overload_generic_fail := "package demo.call\nfunc pick[t](t a, t b) t {\n  a\n}\nfunc main() {\n  pick(1, true)\n}"
    if check_text(overload_generic_fail) == 0 {
        return 1
    }
    overload_ambiguous_fail := "package demo.call\nfunc g[t](t v) t {\n  v\n}\nfunc g[u](u v) u {\n  v\n}\nfunc main() {\n  g(1)\n}"
    if check_text(overload_ambiguous_fail) == 0 {
        return 1
    }
    option_match_ok := "package demo.switch\nfunc f(option[int] value) int {\n  switch value {\n    some(v) : v,\n    none : 0,\n  }\n}"
    if check_text(option_match_ok) != 0 {
        return 1
    }
    option_match_exhaust_fail := "package demo.switch\nfunc f(option[int] value) int {\n  switch value {\n    some(v) : v,\n  }\n}"
    if check_text(option_match_exhaust_fail) == 0 {
        return 1
    }
    option_match_duplicate_fail := "package demo.switch\nfunc f(option[int] value) int {\n  switch value {\n    some(v) : v,\n    some(w) : w,\n    none : 0,\n  }\n}"
    if check_text(option_match_duplicate_fail) == 0 {
        return 1
    }
    option_match_unreachable_fail := "package demo.switch\nfunc f(option[int] value) int {\n  switch value {\n    _ : 0,\n    some(v) : v,\n  }\n}"
    if check_text(option_match_unreachable_fail) == 0 {
        return 1
    }
    option_match_bind_type_fail := "package demo.switch\nfunc f(option[int] value) bool {\n  switch value {\n    some(v) : v,\n    none : false,\n  }\n}"
    if check_text(option_match_bind_type_fail) == 0 {
        return 1
    }
    result_match_ok := "package demo.switch\nfunc f((int, string) value) int {\n  switch value {\n    ok(v) : v,\n    err(e) : 0,\n  }\n}"
    if check_text(result_match_ok) != 0 {
        return 1
    }
    result_match_exhaust_fail := "package demo.switch\nfunc f((int, string) value) int {\n  switch value {\n    ok(v) : v,\n  }\n}"
    if check_text(result_match_exhaust_fail) == 0 {
        return 1
    }
    result_match_duplicate_fail := "package demo.switch\nfunc f((int, string) value) int {\n  switch value {\n    ok(v) : v,\n    err(e) : 0,\n    err(e2) : 1,\n  }\n}"
    if check_text(result_match_duplicate_fail) == 0 {
        return 1
    }
    option_nested_payload_fail := "package demo.switch\nfunc f(option[int] value) int {\n  switch value {\n    some(ok(v)) : v,\n    none : 0,\n  }\n}"
    if check_text(option_nested_payload_fail) == 0 {
        return 1
    }
    nested_ok := "package demo.switch\nfunc f(option[(int, string)] value) int {\n  switch value {\n    some(ok(v)) : v,\n    some(err(e)) : 0,\n    none : 0,\n  }\n}"
    if check_text(nested_ok) != 0 {
        return 1
    }
    diag_src := "package main\nfunc main() {\n  missing(1)\n  missing(1)\n  0\n}"
    diagnostics := check_detailed(diag_src)
    if len(diagnostics) == 0 {
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
    saw_summary := false
    i := 0
    for i < len(diagnostics) {
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
    control_src := "package demo.ctrl\nfunc main() {\n  goto L1\n  0\n}"
    control_diags := check_detailed(control_src)
    if !has_code(control_diags, "e3022") {
        return 1
    }
    recover_src := "package demo.recover\nfunc main() {\n  recover()\n  0\n}"
    recover_diags := check_detailed(recover_src)
    if !has_code(recover_diags, "e3025") {
        return 1
    }
    if !has_code(recover_diags, "e3033") {
        return 1
    }
    go_uncoordinated_src := "package demo.conc\nfunc worker() int {\n  0\n}\nfunc main() {\n  go(\"worker\")\n  0\n}"
    go_uncoordinated_diags := check_detailed(go_uncoordinated_src)
    if !has_code(go_uncoordinated_diags, "e3047") {
        return 1
    }
    sroutine_uncoordinated_src := "package demo.conc\nfunc worker() int {\n  0\n}\nfunc main() {\n  sroutine worker()\n  0\n}"
    sroutine_uncoordinated_diags := check_detailed(sroutine_uncoordinated_src)
    if !has_code(sroutine_uncoordinated_diags, "e3047") {
        return 1
    }
    send_without_recv_src := "package demo.conc\nfunc main() {\n  ch := chan_make(1)\n  chan_send(ch, 1)\n  0\n}"
    send_without_recv_diags := check_detailed(send_without_recv_src)
    if !has_code(send_without_recv_diags, "e3050") {
        return 1
    }
    select_without_recv_src := "package demo.conc\nfunc main() {\n  chs := chan[]()\n  select_recv(chs)\n  0\n}"
    select_without_recv_diags := check_detailed(select_without_recv_src)
    if !has_code(select_without_recv_diags, "e3048") {
        return 1
    }
    close_overflow_src := "package demo.conc\nfunc main() {\n  ch := chan_make(1)\n  chan_close(ch)\n  chan_close(ch)\n  0\n}"
    close_overflow_diags := check_detailed(close_overflow_src)
    if !has_code(close_overflow_diags, "e3049") {
        return 1
    }
    panic_src := "package demo.recover\nfunc main() {\n  panic(\"x\")\n}"
    panic_diags := check_detailed(panic_src)
    if !has_code(panic_diags, "e3026") {
        return 1
    }
    if !has_code(panic_diags, "e3032") {
        return 1
    }
    legacy_impl_src := "package demo.legacy\nimpl Box[T] {\n}"
    if check_text(legacy_impl_src) == 0 {
        return 1
    }
    embed_src := "package demo.impl\nembed Foo\n"
    embed_diags := check_detailed(embed_src)
    if !has_code(embed_diags, "e3035") {
        return 1
    }
    complex_goto_src := "package demo.ctrl\nfunc main() {\n  label L1\n  if true {\n    switch 1 {\n      1 : goto L1,\n      _ : 0,\n    }\n  }\n  0\n}"
    complex_diags := check_detailed(complex_goto_src)
    if !has_code(complex_diags, "e3037") {
        return 1
    }
    non_comparable_eq_src := "package demo.eq\nfunc main() {\n  a := map[string]func() int{}\n  b := map[string]func() int{}\n  if a == b {\n    1\n  } else {\n    0\n  }\n}"
    non_comparable_eq_diags := check_detailed(non_comparable_eq_src)
    if !has_code(non_comparable_eq_diags, "e3039") {
        return 1
    }
    implicit_trait_ok := "package demo.iface\nstruct Calc {}\ntrait Adder {\n  func add(int a, int b) int;\n}\nfunc ( c Calc) add(int a, int b) int {\n  a + b\n}\nfunc use_adder(Adder a) int {\n  a.add(1, 2)\n}\nfunc main() {\n  use_adder(Calc {})\n}"
    if check_text(implicit_trait_ok) != 0 {
        return 1
    }
    implicit_trait_missing := "package demo.iface\nstruct Calc {}\ntrait Adder {\n  func add(int a, int b) int;\n}\nfunc ( c Calc) sub(int a, int b) int {\n  a - b\n}\nfunc use_adder(Adder a) int {\n  0\n}\nfunc main() {\n  use_adder(Calc {})\n}"
    implicit_trait_missing_diags := check_detailed(implicit_trait_missing)
    if !has_code(implicit_trait_missing_diags, "e1002") {
        return 1
    }
    implicit_trait_sig_mismatch := "package demo.iface\nstruct Calc {}\ntrait Adder {\n  func add(int a, int b) int;\n}\nfunc ( c Calc) add(bool a, int b) int {\n  b\n}\nfunc use_adder(Adder a) int {\n  0\n}\nfunc main() {\n  use_adder(Calc {})\n}"
    implicit_trait_sig_diags := check_detailed(implicit_trait_sig_mismatch)
    if !has_code(implicit_trait_sig_diags, "e1002") {
        return 1
    }
    method_call_ok := "package demo.method\nstruct Point {\n  int x\n}\ntrait Measure {\n  func size() int;\n}\nfunc ( p Point) size() int {\n  p.x\n}\nfunc main() {\n  p := Point { x: 4 }\n  p.size()\n}"
    if check_text(method_call_ok) != 0 {
        return 1
    }
    method_ref_ok := "package demo.method\nstruct Reader {\n  int count\n}\ntrait Peek {\n  func peek() int;\n}\nfunc (Reader* reader) peek() int {\n  reader.count\n}\nfunc main() {\n  reader := Reader { count: 2 }\n  reader.peek()\n}"
    if check_text(method_ref_ok) != 0 {
        return 1
    }
    method_temp_ref_fail := "package demo.method\nstruct Reader {\n  int count\n}\ntrait Peek {\n  func peek() int;\n}\nfunc (Reader* reader) peek() int {\n  reader.count\n}\nfunc make_reader() Reader {\n  Reader { count: 2 }\n}\nfunc main() {\n  make_reader().peek()\n}"
    method_temp_ref_diags := check_detailed(method_temp_ref_fail)
    if !has_code(method_temp_ref_diags, "e3051") {
        return 1
    }
    method_mut_ref_ok := "package demo.method\nstruct Counter {\n  int count\n}\ntrait Bump {\n  func bump() int;\n}\nfunc (Counter* counter) bump() int {\n  counter.count\n}\nfunc main() {\n  counter := Counter { count: 2 }\n  counter.bump()\n}"
    if check_text(method_mut_ref_ok) != 0 {
        return 1
    }
    method_temp_mut_ref_fail := "package demo.method\nstruct Counter {\n  int count\n}\ntrait Bump {\n  func bump() int;\n}\nfunc (Counter* counter) bump() int {\n  counter.count\n}\nfunc make_counter() Counter {\n  Counter { count: 2 }\n}\nfunc main() {\n  make_counter().bump()\n}"
    method_temp_mut_ref_diags := check_detailed(method_temp_mut_ref_fail)
    if !has_code(method_temp_mut_ref_diags, "e3051") {
        return 1
    }
    move_after_use_ok := "package demo.move\nfunc take(int v) int {\n  v\n}\nfunc main() {\n  n := 1\n  take(n)\n  n\n}"
    if check_text(move_after_use_ok) != 0 {
        return 1
    }
    copy_integer_ok := "package demo.copy\nfunc take(u32 value) int {\n  0\n}\nfunc main() {\n  value := 1\n  take(value)\n  value\n}"
    if check_text(copy_integer_ok) != 0 {
        return 1
    }
    move_after_move_fail := "package demo.move\nstruct Box {\n  int n\n}\nfunc take(Box b) int {\n  b.n\n}\nfunc main() {\n  b := Box { n: 1 }\n  take(b)\n  b.n\n}"
    move_after_move_diags := check_detailed(move_after_move_fail)
    if !has_code(move_after_move_diags, "e3059") {
        return 1
    }
    shared_borrow_ok := "package demo.borrow\nfunc read_pair(&int left, &int right) int {\n  left\n}\nfunc main() {\n  value := 1\n  read_pair(&value, &value)\n  value\n}"
    if check_text(shared_borrow_ok) != 0 {
        return 1
    }
    shared_then_mutable_fail := "package demo.borrow\nfunc read_then_write(&int left, &mut int right) int {\n  left\n}\nfunc main() {\n  value := 1\n  read_then_write(&value, &mut value)\n}"
    shared_then_mutable_diags := check_detailed(shared_then_mutable_fail)
    if !has_code(shared_then_mutable_diags, "e3057") {
        return 1
    }
    mutable_then_shared_fail := "package demo.borrow\nfunc write_then_read(&mut int left, &int right) int {\n  right\n}\nfunc main() {\n  value := 1\n  write_then_read(&mut value, &value)\n}"
    mutable_then_shared_diags := check_detailed(mutable_then_shared_fail)
    if !has_code(mutable_then_shared_diags, "e3058") {
        return 1
    }
    return_local_reference_fail := "package demo.lifetime\nfunc bad() &int {\n  local := 1\n  return &local\n}\nfunc main() {\n  bad()\n}"
    return_local_reference_diags := check_detailed(return_local_reference_fail)
    if !has_code(return_local_reference_diags, "e3053") {
        return 1
    }
    disjoint_field_borrows_ok := "package demo.fields\nstruct Pair {\n  int left\n  int right\n}\nfunc use_fields(&int left, &mut int right) int {\n  left\n}\nfunc main() {\n  pair := Pair { left: 1, right: 2 }\n  use_fields(&pair.left, &mut pair.right)\n}"
    if check_text(disjoint_field_borrows_ok) != 0 {
        return 1
    }
    same_field_borrow_fail := "package demo.fields\nstruct Pair {\n  int left\n  int right\n}\nfunc use_fields(&int left, &mut int right) int {\n  left\n}\nfunc main() {\n  pair := Pair { left: 1, right: 2 }\n  use_fields(&pair.left, &mut pair.left)\n}"
    same_field_borrow_diags := check_detailed(same_field_borrow_fail)
    if !has_code(same_field_borrow_diags, "e3057") {
        return 1
    }
    whole_struct_field_borrow_fail := "package demo.fields\nstruct Pair {\n  int left\n  int right\n}\nfunc use_pair(&Pair whole, &mut int field) int {\n  field\n}\nfunc main() {\n  pair := Pair { left: 1, right: 2 }\n  use_pair(&pair, &mut pair.left)\n}"
    whole_struct_field_borrow_diags := check_detailed(whole_struct_field_borrow_fail)
    if !has_code(whole_struct_field_borrow_diags, "e3057") {
        return 1
    }
    branch_move_fail := "package demo.flow\nstruct Box {\n  int n\n}\nfunc take(Box value) int {\n  value.n\n}\nfunc main() {\n  box := Box { n: 1 }\n  if true {\n    take(box)\n  }\n  box.n\n}"
    branch_move_diags := check_detailed(branch_move_fail)
    if !has_code(branch_move_diags, "e3059") {
        return 1
    }
    loop_move_fail := "package demo.flow\nstruct Box {\n  int n\n}\nfunc take(Box value) int {\n  value.n\n}\nfunc main() {\n  box := Box { n: 1 }\n  while true {\n    take(box)\n  }\n  box.n\n}"
    loop_move_diags := check_detailed(loop_move_fail)
    if !has_code(loop_move_diags, "e3059") {
        return 1
    }
    unsafe_raw_access_fail := "package demo.unsafe\nfunc main() {\n  unsafe.load_i32(ptr)\n}"
    unsafe_raw_access_diags := check_detailed(unsafe_raw_access_fail)
    if !has_code(unsafe_raw_access_diags, "e3060") {
        return 1
    }
    unsafe_asm_fail := "package demo.unsafe\nfunc main() {\n  asm(\"nop\")\n}"
    unsafe_asm_diags := check_detailed(unsafe_asm_fail)
    if !has_code(unsafe_asm_diags, "e3061") {
        return 1
    }
    duplicate_receiver_method := "package demo.iface\nstruct Calc {}\nfunc ( c Calc) add(int a) int {\n  a\n}\nfunc ( c Calc) add(int a) int {\n  a\n}\nfunc main() {\n  0\n}"
    duplicate_receiver_diags := check_detailed(duplicate_receiver_method)
    if !has_code(duplicate_receiver_diags, "e3042") {
        return 1
    }
    const_iota_ok := "package demo.consts\nconst A = iota\nconst B = iota\nfunc main() {\n  A + B\n}"
    if check_text(const_iota_ok) != 0 {
        return 1
    }
    const_ref_ok := "package demo.consts\nconst Base = 3\nconst Sum = Base + 2\nfunc main() {\n  Sum\n}"
    if check_text(const_ref_ok) != 0 {
        return 1
    }
    iota_outside_const_fail := "package demo.consts\nfunc main() {\n  iota\n}"
    if check_text(iota_outside_const_fail) == 0 {
        return 1
    }
    duplicate_const_fail := "package demo.consts\nconst A = 1\nconst A = 2\nfunc main() {\n  A\n}"
    duplicate_const_diags := check_detailed(duplicate_const_fail)
    if !has_code(duplicate_const_diags, "e3044") {
        return 1
    }
    const_group_ok := "package demo.consts\nconst (\n  A = iota\n  B\n  C = A + 1\n)\nfunc main() {\n  C\n}"
    if check_text(const_group_ok) != 0 {
        return 1
    }
    const_group_missing_init_fail := "package demo.consts\nconst (\n  A\n)\nfunc main() {\n  0\n}"
    const_group_missing_diags := check_detailed(const_group_missing_init_fail)
    if !has_code(const_group_missing_diags, "e3045") {
        return 1
    }
    const_iota_increment_value_ok := "package demo.consts\nconst (\n  A = iota\n  B\n)\nconst C = 10 / B\nfunc main() {\n  C\n}"
    if check_text(const_iota_increment_value_ok) != 0 {
        return 1
    }
    const_iota_div_zero_fail := "package demo.consts\nconst (\n  A = iota\n  B = 10 / A\n)\nfunc main() {\n  0\n}"
    const_iota_div_zero_diags := check_detailed(const_iota_div_zero_fail)
    if !has_code(const_iota_div_zero_diags, "e3046") {
        return 1
    }
    nil_assign_ok := "package demo.nil\nfunc main() {\n  f: fn = nil\n  if f == nil {\n    0\n  } else {\n    1\n  }\n}"
    if check_text(nil_assign_ok) != 0 {
        return 1
    }
    nil_assign_fail := "package demo.nil\nfunc main() {\n  x: int = nil\n  x\n}"
    if check_text(nil_assign_fail) == 0 {
        return 1
    }
    compile_time_div_zero_fail := "package demo.arithmetic\nfunc main() {\n  10 / 0\n}"
    compile_time_div_zero_diags := check_detailed(compile_time_div_zero_fail)
    if !has_code(compile_time_div_zero_diags, "e3065") {
        return 1
    }
    compile_time_mod_zero_fail := "package demo.arithmetic\nfunc main() {\n  10 % 0\n}"
    compile_time_mod_zero_diags := check_detailed(compile_time_mod_zero_fail)
    if !has_code(compile_time_mod_zero_diags, "e3065") {
        return 1
    }
    compile_time_type_fail := "package demo.types\nfunc main() {\n  value: missing.Type = 0\n  value\n}"
    compile_time_type_diags := check_detailed(compile_time_type_fail)
    if !has_code(compile_time_type_diags, "e3063") {
        return 1
    }
    duplicate_local_fail := "package demo.scope\nfunc main() {\n  value := 1\n  value := 2\n  value\n}"
    duplicate_local_diags := check_detailed(duplicate_local_fail)
    if !has_code(duplicate_local_diags, "e3064") {
        return 1
    }
    explicit_box_ok := "package demo.ownership\nfunc main() {\n  value := box(1)\n  box_free(value)\n  0\n}"
    if check_text(explicit_box_ok) != 0 {
        return 1
    }
    implicit_box_free_fail := "package demo.ownership\nfunc main() {\n  box_free(1)\n  0\n}"
    implicit_box_free_diags := check_detailed(implicit_box_free_fail)
    if !has_code(implicit_box_free_diags, "e3067") {
        return 1
    }
    box_double_free_fail := "package demo.ownership\nfunc main() {\n  value := box(1)\n  box_free(value)\n  box_free(value)\n  0\n}"
    box_double_free_diags := check_detailed(box_double_free_fail)
    if !has_code(box_double_free_diags, "e3059") {
        return 1
    }
    assignment_move_fail := "package demo.ownership\nfunc main() {\n  left := \"left\"\n  right := \"right\"\n  left = right\n  right\n}"
    assignment_move_diags := check_detailed(assignment_move_fail)
    if !has_code(assignment_move_diags, "e3059") {
        return 1
    }
    0
}

func has_code(semantic_error[] diagnostics, string code) bool {
    i := 0
    for i < len(diagnostics) {
        if diagnostics[i].code == code {
            return true
        }
        i = i + 1
    }
    false
}
