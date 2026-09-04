package compile.internal.semantic
use compile.internal.prelude.lookup_builtin_field_type
use compile.internal.prelude.lookup_builtin_method_arity
use compile.internal.prelude.lookup_builtin_method_type
use compile.internal.typesys.assignable_type
use compile.internal.typesys.base_type_name
use compile.internal.typesys.comparable_type
use compile.internal.typesys.compatible_type
use compile.internal.typesys.extract_type_args
use compile.internal.typesys.parse_type
use compile.internal.typesys.parse_type_ref
use compile.internal.typesys.rules_consistent
use compile.internal.typesys.same_type
use compile.internal.typesys.same_type_ref
use compile.internal.typesys.type_arg
use compile.internal.typesys.type_ref
use compile.internal.typesys.has_unknown_component
use compile.internal.typesys.is_copy_type
use s.block_expr
use s.expr
use s.function_decl
use s.receiver_method_decl
use s.item
use s.pattern
use s.stmt
use s.parse_source
use s.param_decl
use std.option.option
use std.prelude.char_at
use std.prelude.len
use std.prelude.slice
use std.slices
struct type_binding {
    string name
    string type_name
}

struct function_binding {
    string name
    string owner_type
    bool has_receiver
    string receiver_mode
    string[] generic_names
    string[] param_types
    string return_type
}

struct method_binding {
    string name
    string receiver_mode
    string[] param_types
    string return_type
}

struct trait_binding {
    string name
    method_binding[] methods
}

struct const_binding {
    string name
    string type_name
    bool has_int_value
    int int_value
}

struct const_eval_int_result {
    bool ok
    int value
    string error
}

struct borrow_record {
    string name
    bool mutable
    bool moved
    bool copyable
}

struct signature_match {
    bool ok
    string return_type
    string instance_name
    int score
    int generic_bind_count
    int unknown_arg_count
}

struct check_result {
    string type_name
    int errors
}

struct pattern_check_result {
    type_binding[] bindings
    int errors
}

struct source_pos {
    int line
    int column
}

struct semantic_error {
    string code
    string message
    string stage
    string chain_id
    string upstream_code
    string severity
    string hint
    string anchor
    int tier
    int repeat_count
    int line
    int column
}

func check_text(string source) int {
    diagnostics := check_detailed(source);
    if len(diagnostics) > 0 {
        return 1;
    }
    0
}

func borrow_state_new() borrow_record[] {
    borrow_record[]()
}

func borrow_state_clone(borrow_record[] state) borrow_record[] {
    copied := borrow_record[]()
    i := 0
    for i < len(state) {
        copied.push(state[i])
        i = i + 1
    }
    copied
}

func borrow_state_merge_moves(borrow_record[] target, borrow_record[] source) {
    i := 0
    for i < len(source) {
        if source[i].moved {
            index := borrow_state_find(target, source[i].name)
            if index < 0 {
                target.push(source[i])
            } else {
                target[index].moved = true
            }
        }
        i = i + 1
    }
}

func borrow_state_push(borrow_record[] state, string name, bool mutable) {
    state.push(borrow_record {
        name: name, mutable mutable, moved: false, copyable: false,
    })
}

func borrow_state_clear(borrow_record[] state) {
    kept := borrow_record[]()
    i := 0
    for i < len(state) {
        if state[i].moved {
            kept.push(state[i])
        }
        i = i + 1
    }
    state.clear()
    i = 0
    for i < len(kept) {
        state.push(kept[i])
        i = i + 1
    }
}

func borrow_state_has_conflict(borrow_record[] state, string name, bool mutable) bool {
    i := 0
    for i < len(state) {
        if borrow_places_overlap(state[i].name, name) {
            if mutable || state[i].mutable {
                return true
            }
        }
        i = i + 1
    }
    false
}

func borrow_places_overlap(string left, string right) bool {
    if left == right { return true }
    if left == "" || right == "" { return false }
    if starts_with(left, right) {
        return len(left) > len(right) && string(left[len(right)]) == "."
    }
    if starts_with(right, left) {
        return len(right) > len(left) && string(right[len(left)]) == "."
    }
    false
}

func borrow_state_find(borrow_record[] state, string name) int {
    i := 0
    for i < len(state) {
        if state[i].name == name { return i }
        i = i + 1
    }
    -1
}

func borrow_type_is_copy(string type_name) bool {
    is_copy_type(type_name)
}

func borrow_state_mark_move(borrow_record[] state, string name, string type_name) {
    index := borrow_state_find(state, name)
    copyable := borrow_type_is_copy(type_name)
    if index < 0 {
        state.push(borrow_record {
            name: name, mutable: false, moved: !copyable, copyable: copyable,
        })
    } else if !state[index].copyable {
        state[index].moved = true
    }
}

func borrow_state_is_moved(borrow_record[] state, string name) bool {
    index := borrow_state_find(state, name)
    index >= 0 && state[index].moved
}

func borrow_place_name(expr value) string {
    switch value {
        expr::name(name_value) : name_value.name,
        expr::member(member_value) : {
            base := borrow_place_name(member_value.target.value)
            if base == "" { "" } else { base + "." + member_value.member }
        }
        _ : "",
    }
}

func check_detailed(string source) semantic_error[] {
    diagnostics := semantic_error[]()
    if !rules_consistent() {
        add_error(source, diagnostics, "e0002", "type rules consistency check failed", "package")
        return finalize_diagnostics(diagnostics)
    }
    run_preparse_semantic_completeness_checks(source, diagnostics)
    parsed := parse_source(source)
    if parsed.is_err() {
        add_error(source, diagnostics, "e0001", "parse failed", "package");
        return finalize_diagnostics(diagnostics)
    }
    file := parsed.unwrap()
    functions := collect_functions(file.items)
    traits := collect_traits(file.items)
    consts := collect_consts(file.items, functions, traits, source, diagnostics)
    validate_function_set(functions, source, diagnostics)
    i := 0
    for i < len(file.items) {
        ignored := check_item(file.items[i], functions, traits, consts, source, diagnostics)
        i = i + 1
    }
    finalize_diagnostics(diagnostics)
}

func run_preparse_semantic_completeness_checks(string source, semantic_error[] diagnostics) {
    ignored0 := validate_control_flow_semantics(source, diagnostics)
    ignored1 := validate_recovery_semantics(source, diagnostics)
    ignored2 := validate_method_interface_semantics(source, diagnostics)
    ignored3 := validate_concurrency_semantics(source, diagnostics)
    ignored4 := validate_semantic_proof_chain(source, diagnostics)
}

func validate_concurrency_semantics(string source, semantic_error[] diagnostics) int {
    errors := 0
    go_count := count_token_text(source, "\ngo(") + count_token_text(source, "\ngo ")
    sroutine_count := count_token_text(source, "\nsroutine ")
    launch_count := go_count + sroutine_count
    make_count := count_token_text(source, "chan_make(")
    send_count := count_token_text(source, "chan_send(") + count_token_text(source, "select_send(") + count_token_text(source, "select_send_default(") + count_token_text(source, "select_send_timeout(") + count_token_text(source, "case send(")
    recv_count := count_token_text(source, "chan_recv(") + count_token_text(source, "case recv(")
    close_count := count_token_text(source, "chan_close(")
    select_count := count_token_text(source, "select_recv(")
        + count_token_text(source, "select_recv_default(")
        + count_token_text(source, "select_recv_weighted(")
        + count_token_text(source, "select_recv_timeout(")
        + count_token_text(source, "select_send(")
        + count_token_text(source, "select_send_default(")
        + count_token_text(source, "select_send_timeout(")
        + count_token_text(source, "select {")
    if launch_count > 0 && make_count == 0 && select_count == 0 {
        errors = errors + add_error(source, diagnostics, "e3047", "routine launched without channel/select coordination", "go")
    }
    if select_count > 0 && recv_count == 0 {
        errors = errors + add_error(source, diagnostics, "e3048", "select requires at least one receive path", "select")
    }
    if close_count > make_count {
        errors = errors + add_error(source, diagnostics, "e3049", "channel close count exceeds channel creation count", "chan_close")
    }
    if send_count > 0 && recv_count == 0 && select_count == 0 {
        errors = errors + add_error(source, diagnostics, "e3050", "channel send path has no receive/select consumer", "chan_send")
    }
    errors
}

func validate_control_flow_semantics(string source, semantic_error[] diagnostics) int {
    errors := 0
    label_defs := count_token_text(source, "label ")
    goto_uses := count_token_text(source, "goto ")
    if goto_uses > 0 && label_defs == 0 {
        errors = errors + add_error(source, diagnostics, "e3022", "goto target label not declared", "goto")
    }
    if goto_uses > label_defs {
        errors = errors + add_error(source, diagnostics, "e3023", "goto/label count mismatch", "goto")
    }
    if label_defs > 0 && count_token_text(source, "break ") > 0 && goto_uses > 0 {
        errors = errors + add_error(source, diagnostics, "e3031", "goto mixed with break/label requires structured-control proof", "goto")
    }
    if goto_uses > 0 && count_token_text(source, "defer ") > 0 {
        errors = errors + add_error(source, diagnostics, "e3024", "goto across deferred region requires strict control-flow proof", "defer")
    }
    errors
}

func validate_recovery_semantics(string source, semantic_error[] diagnostics) int {
    errors := 0
    defer_count := count_token_text(source, "defer ")
    panic_count := count_token_text(source, "panic(")
    recover_count := count_token_text(source, "recover(")
    if recover_count > 0 && defer_count == 0 {
        errors = errors + add_error(source, diagnostics, "e3025", "recover requires deferred context", "recover")
    }
    if panic_count > 0 && defer_count == 0 {
        errors = errors + add_error(source, diagnostics, "e3026", "panic without defer may violate unwind contract", "panic")
    }
    if recover_count > defer_count {
        errors = errors + add_error(source, diagnostics, "e3027", "recover coverage exceeds deferred handlers", "recover")
    }
    if panic_count > 0 && count_token_text(source, "return") == 0 {
        errors = errors + add_error(source, diagnostics, "e3032", "panic path requires explicit return or recovery bridge", "panic"
    }
    if recover_count > 0 && panic_count == 0 {
        errors = errors + add_error(source, diagnostics, "e3033", "recover without panic path may break semantic equivalence", "recover")
    }
    errors
}

func validate_method_interface_semantics(string source, semantic_error[] diagnostics) int {
    errors := 0
    receiver_mut := count_token_text(source, "&")
    receiver_ref := count_token_text(source, "&")
    if receiver_mut > 0 && receiver_ref > receiver_mut {
        errors = errors + add_error(source, diagnostics, "e3029", "mixed receiver variants require method-set consistency proof", "func")
    }
    if count_token_text(source, "[") > 0 && count_token_text(source, "]") > 0 && count_token_text(source, " where ") == 0 {
        errors = errors + add_error(source, diagnostics, "e3030", "generic constraints are incomplete without explicit where-clause", "where")
    }
    if count_token_text(source, "embed ") > 0 && count_token_text(source, "interface ") == 0 {
        errors = errors + add_error(source, diagnostics, "e3035", "embedded method set requires explicit interface boundary", "embed")
    }
    errors
}

func validate_semantic_proof_chain(string source, semantic_error[] diagnostics) int {
    errors := 0
    defer_count := count_token_text(source, "defer ")
    panic_count := count_token_text(source, "panic(")
    recover_count := count_token_text(source, "recover(")
    goto_count := count_token_text(source, "goto ")
    label_count := count_token_text(source, "label ")
    nested_if := count_token_text(source, "if ")
    nested_switch := count_token_text(source, "switch ")
    if panic_count > 0 && recover_count > 0 && defer_count == 0 {
        errors = errors + add_error(source, diagnostics, "e3036", "panic/recover equivalence chain requires defer checkpoint", "defer")
    }
    if goto_count > 0 && label_count > 0 && (nested_if + nested_switch) > 2 {
        errors = errors + add_error(source, diagnostics, "e3037", "complex nested goto/label requires full control-flow proof chain", "goto")
    }
    errors
}

func count_token_text(string text, string token) int {
    if token == "" {
        return 0
    }
    count := 0
    i := 0
    for i <= len(text) - len(token) {
        if slice(text, i, i + len(token)) == token {
            count = count + 1
            i = i + len(token)
        } else {
            i = i + 1
        }
    }
    count
}

func finalize_diagnostics(semantic_error[] diagnostics) semantic_error[] {
    deduped := dedupe_diagnostics(diagnostics)
    anchored := append_anchor_summaries(deduped)
    ordered := sort_diagnostics(anchored)
    apply_diagnostic_budget(ordered)
}

func append_anchor_summaries(semantic_error[] diagnostics) semantic_error[] {
    out := semantic_error[]()
    i := 0
    for i < len(diagnostics) {
        out = append(out, diagnostics[i])
        i = i + 1
    }
    summaries := semantic_error[]()
    i = 0
    for i < len(diagnostics) {
        d := diagnostics[i]
        if d.anchor != "" {
            at := find_anchor_summary_index(summaries, d.anchor)
            if at < 0 {
                summaries.push(semantic_error {
                    code: "s0001",
                    message: "anchor summary",
                    stage: "semantic", chain_id chain_id_from_anchor(d.anchor), upstream_code d.code,
                    severity: "warning",
                    hint: "multiple diagnostics share recovery anchor " + d.anchor, anchor d.anchor, tier 3, repeat_count d.repeat_count, line d.line, column d.column,
                })
            } else {
                summaries[at].repeat_count = summaries[at].repeat_count + d.repeat_count
            }
        }
        i = i + 1
    }
    i = 0
    for i < len(summaries) {
        if summaries[i].repeat_count > 1 {
            out = append(out, summaries[i])
        }
        i = i + 1
    }
    out
}

func find_anchor_summary_index(semantic_error[] diagnostics, string anchor) int {
    i := 0
    for i < len(diagnostics) {
        if diagnostics[i].anchor == anchor {
            return i
        }
        i = i + 1
    }
    0 - 1
}

func dedupe_diagnostics(semantic_error[] diagnostics) semantic_error[] {
    out := semantic_error[]()
    i := 0
    for i < len(diagnostics) {
        d := diagnostics[i]
        idx := find_diagnostic_index(out, d)
        if idx < 0 {
            out = append(out, d)
        } else {
            out[idx].repeat_count = out[idx].repeat_count + 1
            if out[idx].hint == "" {
                out[idx].hint = d.hint
            }
        }
        i = i + 1
    }
    out
}

func find_diagnostic_index(semantic_error[] diagnostics, semantic_error candidate) int {
    i := 0
    for i < len(diagnostics) {
        if diagnostics[i].code == candidate.code
            && diagnostics[i].message == candidate.message
            && diagnostics[i].line == candidate.line
            && diagnostics[i].column == candidate.column {
            return i
        }
        i = i + 1
    }
    0 - 1
}

func sort_diagnostics(semantic_error[] diagnostics) semantic_error[] {
    out := semantic_error[]()
    i := 0
    for i < len(diagnostics) {
        item := diagnostics[i]
        insert := len(out)
        j := 0
        for j < len(out) {
            if diagnostic_before(item, out[j]) {
                insert = j
                j = len(out)
            } else {
                j = j + 1
            }
        }
        insert_diagnostic(out, insert, item)
        i = i + 1
    }
    out
}

func insert_diagnostic(semantic_error[] diagnostics, int at, semantic_error item) {
    diagnostics = append(diagnostics, item)
    i := len(diagnostics) - 1
    for i > at {
        diagnostics[i] = diagnostics[i - 1]
        i = i - 1
    }
    diagnostics[at] = item
}

func diagnostic_before(semantic_error left, semantic_error right) bool {
    if left.tier != right.tier {
        return left.tier < right.tier
    }
    ls := severity_rank(left.severity)
    rs := severity_rank(right.severity)
    if ls != rs {
        return ls < rs
    }
    if left.line != right.line {
        return left.line < right.line
    }
    if left.column != right.column {
        return left.column < right.column
    }
    left.code < right.code
}

func severity_rank(string severity) int {
    if severity == "fatal" {
        return 0
    }
    if severity == "error" {
        return 1
    }
    if severity == "warning" {
        return 2
    }
    3
}

func apply_diagnostic_budget(semantic_error[] diagnostics) semantic_error[] {
    max_total := 128
    max_warnings := 24
    if len(diagnostics) <= max_total {
        return diagnostics
    }
    out := semantic_error[]()
    warnings := 0
    i := 0
    for i < len(diagnostics) && len(out) < max_total {
        d := diagnostics[i]
        if d.severity == "warning" {
            if warnings >= max_warnings {
                i = i + 1
                continue
            }
            warnings = warnings + 1
        }
        out = append(out, d)
        i = i + 1
    }
    out
}

func validate_function_set(function_binding[] functions, string source, semantic_error[] diagnostics) int {
    errors := 0
    i := 0
    has_main := false
    for i < len(functions) {
        if !functions[i].has_receiver && functions[i].name == "main" {
            has_main = true
        }
        j := i + 1
        for j < len(functions) {
            if !functions[i].has_receiver && !functions[j].has_receiver && functions[i].name == functions[j].name {
                errors = errors + add_error(source, diagnostics, "e3010", "duplicate function declaration", functions[i].name)
            }
            if functions[i].has_receiver
                && functions[j].has_receiver
                && functions[i].owner_type == functions[j].owner_type
                && functions[i].name == functions[j].name
                && same_param_types(functions[i].param_types, functions[j].param_types) {
                errors = errors + add_error(source, diagnostics, "e3042", "duplicate receiver method", functions[i].name)
            }
            j = j + 1
        }
        i = i + 1
    }
    if is_main_package(source) && !has_main {
        errors = errors + add_error(source, diagnostics, "e3011", "entry function main not found", "main")
    }
    errors
}

func same_param_types(string[] left, string[] right) bool {
    if len(left) != len(right) {
        return false
    }
    i := 0
    for i < len(left) {
        if !same_type(left[i], right[i]) {
            return false
        }
        i = i + 1
    }
    true
}

func is_main_package(string source) bool {
    contains_token(source, "package main")
}

func collect_functions(item[] items) function_binding[] {
    out := function_binding[]()
    i := 0
    for i < len(items) {
        switch items[i] {
            item.function(function_decl) : out = append(out, make_function_binding(function_decl)),
            item.method(method_decl) : out = append(out, make_receiver_method_binding(method_decl)),
            _ : {},
        }
        i = i + 1
    }
    out
}

func make_function_binding(function_decl function_decl) function_binding {
    generic_names := string[]()
    i := 0
    for i < len(function_decl.sig.generics) {
        generic_names = append(generic_names, generic_name(function_decl.sig.generics[i]));
        i = i + 1
    }
    params := string[]()
    i = 0
    for i < len(function_decl.sig.params) {
        params = append(params, parse_type(function_decl.sig.params[i].type_name));
        i = i + 1
    }
    return_type :=
        switch function_decl.sig.return_type {
            option.some(type_name) : parse_type(type_name),
            option.none : "()",
        }
    return function_binding {
        name: function_decl.sig.name,
        owner_type: "", has_receiver false,
        receiver_mode: "value", generic_names generic_names, param_types params, return_type return_type,
    };
}

func make_receiver_method_binding(receiver_method_decl method_decl) function_binding {
    binding := make_function_binding(method_decl.method)
    params := string[]()
    params = append(params, parse_type(method_decl.receiver_type))
    i := 0
    for i < len(binding.param_types) {
        params = append(params, binding.param_types[i])
        i = i + 1
    }
    binding.owner_type = method_owner_type(parse_type(method_decl.receiver_type))
    binding.has_receiver = true
    binding.receiver_mode = receiver_mode_from_type(method_decl.receiver_type)
    binding.param_types = params
    binding
}

func check_item(item item, function_binding[] functions, trait_binding[] traits, const_binding[] consts, string source, semantic_error[] diagnostics) int {
    switch item {
        item.function(function_decl) : check_function(function_decl, functions, traits, consts, source, diagnostics),
        item.method(method_decl) : check_receiver_method(method_decl, functions, traits, consts, source, diagnostics),
        _ : 0,
    }
}

func collect_consts(item[] items, function_binding[] functions, trait_binding[] traits, string source, semantic_error[] diagnostics) const_binding[] {
    out := const_binding[]()
    type_env := type_binding[]()
    last_const_expr := option::none
    i := 0
    for i < len(items) {
        switch items[i] {
            item.const(const_decl) : {
                if lookup_name_type(type_env, const_decl.name) != "unknown" {
                    ignored := add_error(source, diagnostics, "e3044", "duplicate const declaration", const_decl.name)
                }
                local_env := clone_env(type_env)
                local_env.push(type_binding {
                    name: "iota",
                    type_name: "int",
                })
                ;
                expr_to_check := option::none
                switch const_decl.value {
                    option.some(value) : {
                        expr_to_check = option::some(value)
                        last_const_expr = option::some(value)
                    }
                    option.none : expr_to_check = last_const_expr,
                }
                ty := "unknown"
                has_int_value := false
                int_value := 0
                if expr_to_check.is_none() {
                    ignored2 := add_error(source, diagnostics, "e3045", "const declaration missing initializer and no prior expression in group", const_decl.name)
                } else {
                    inferred := infer_expr(expr_to_check.unwrap(), local_env, borrow_state_new(), "()", functions, traits, source, diagnostics)
                    ty = inferred.type_name
                    if is_unknown(ty) {
                        ty = "unknown"
                    } else if same_type(ty, "int") {
                        eval_result := eval_const_int_expr(expr_to_check.unwrap(), out, const_decl.iota_index)
                        if eval_result.ok {
                            has_int_value = true
                            int_value = eval_result.value
                        } else {
                            ignored3 := add_error(source, diagnostics, "e3046", "const int expression evaluation failed: " + eval_result.error, const_decl.name)
                        }
                    }
                }
                out.push(const_binding {
                    name: const_decl.name, type_name ty, has_int_value has_int_value, int_value int_value,
                })
                ;
                type_env.push(type_binding {
                    name: const_decl.name, type_name ty,
                })
                ;
            }
            _ : (),
        }
        i = i + 1
    }
    out
}

func eval_const_int_expr(expr value, const_binding[] known_consts, int iota_value) const_eval_int_result {
    switch value {
        expr::int(int_expr) : const_eval_int_result {
            ok: true, value parse_const_int_literal(int_expr.value),
            error: "",
        },
        expr::name(name_expr) : {
            if name_expr.name == "iota" {
                return const_eval_int_result {
                    ok: true, value iota_value,
                    error: "",
                }
            }
            i := len(known_consts)
            for i > 0 {
                i = i - 1
                if known_consts[i].name == name_expr.name {
                    if known_consts[i].has_int_value {
                        return const_eval_int_result {
                            ok: true, value known_consts[i].int_value,
                            error: "",
                        }
                    }
                    return const_eval_int_result {
                        ok: false, value 0,
                        error: "name " + name_expr.name + " is not an int constant",
                    }
                }
            }
            const_eval_int_result {
                ok: false, value 0,
                error: "unknown constant name " + name_expr.name,
            }
        }
        expr::binary(binary_expr) : {
            left := eval_const_int_expr(binary_expr.left.value, known_consts, iota_value)
            if !left.ok {
                return left
            }
            right := eval_const_int_expr(binary_expr.right.value, known_consts, iota_value)
            if !right.ok {
                return right
            }
            if binary_expr.op == "+" {
                return const_eval_int_result { ok: true, value left.value + right.value, error: "" }
            }
            if binary_expr.op == "-" {
                return const_eval_int_result { ok: true, value left.value - right.value, error: "" }
            }
            if binary_expr.op == "*" {
                return const_eval_int_result { ok: true, value left.value * right.value, error: "" }
            }
            if binary_expr.op == "/" {
                if right.value == 0 {
                    return const_eval_int_result { ok: false, value 0, error: "division by zero" }
                }
                return const_eval_int_result { ok: true, value left.value / right.value, error: "" }
            }
            if binary_expr.op == "%" {
                if right.value == 0 {
                    return const_eval_int_result { ok: false, value 0, error: "modulo by zero" }
                }
                return const_eval_int_result { ok: true, value left.value % right.value, error: "" }
            }
            const_eval_int_result {
                ok: false, value 0,
                error: "unsupported int operator " + binary_expr.op,
            }
        }
        _ : const_eval_int_result {
            ok: false, value 0,
            error: "expression is not a supported int const form",
        },
    }
}

func parse_const_int_literal(string literal) int {
    text := literal
    sign := 1
    i := 0
    if len(text) > 0 && char_at(text, 0) == "-" {
        sign = -1
        i = 1
    }
    out := 0
    for i < len(text) {
        ch := char_at(text, i)
        if ch != "_" {
            out = out * 10 + const_digit_value(ch)
        }
        i = i + 1
    }
    sign * out
}

func const_digit_value(string ch) int {
    if ch == "0" {
        return 0
    }
    if ch == "1" {
        return 1
    }
    if ch == "2" {
        return 2
    }
    if ch == "3" {
        return 3
    }
    if ch == "4" {
        return 4
    }
    if ch == "5" {
        return 5
    }
    if ch == "6" {
        return 6
    }
    if ch == "7" {
        return 7
    }
    if ch == "8" {
        return 8
    }
    if ch == "9" {
        return 9
    }
    0
}

func collect_traits(item[] items) trait_binding[] {
    out := trait_binding[]()
    i := 0
    for i < len(items) {
        switch items[i] {
            item.trait(trait_decl) : {
                methods := method_binding[]()
                mi := 0
                for mi < len(trait_decl.methods) {
                    params := string[]()
                    pi := 0
                    for pi < trait_decl.methods[mi]len(.params) {
                        params = append(params, parse_type(trait_decl.methods[mi].params[pi].type_name));
                        pi = pi + 1
                    }
                    return_type :=
                        switch trait_decl.methods[mi].return_type {
                            option.some(type_name) : parse_type(type_name),
                            option.none : "()",
                        }
                    methods.push(method_binding {
                        name: trait_decl.methods[mi].name, receiver_mode receiver_mode_from_param_name(trait_decl.methods[mi].params), param_types params, return_type return_type,
                    })
                    ;
                    mi = mi + 1
                }
                out.push(trait_binding {
                    name: trait_decl.name, methods methods,
                })
                ;
            }
            _ : (),
        }
        i = i + 1
    }
    out
}

func find_trait_binding(trait_binding[] traits, string name) option[trait_binding] {
    i := 0
    for i < len(traits) {
        if traits[i].name == name || traits[i].name == base_type_name(name) {
            return option.some(traits[i]
        }
        i = i + 1
    }
    option.none
}

func find_trait_method(trait_binding trait_info, string name) option[method_binding] {
    i := 0
    for i < len(trait_info.methods) {
        if trait_info.methods[i].name == name {
            return option.some(trait_info.methods[i]
        }
        i = i + 1
    }
    option.none
}

func receiver_type_implements_trait(string receiver_type, trait_binding trait_info, function_binding[] functions) bool {
    mi := 0
    for mi < len(trait_info.methods) {
        matched := false
        fi := 0
        for fi < len(functions) {
            if functions[fi].has_receiver
                && functions[fi].owner_type == method_owner_type(parse_type(receiver_type))
                && method_binding_matches_trait(functions[fi], trait_info.methods[mi]) {
                matched = true
            }
            fi = fi + 1
        }
        if !matched {
            return false
        }
        mi = mi + 1
    }
    true
}

func method_binding_matches_trait(function_binding method, method_binding requirement) bool {
    if method.name != requirement.name {
        return false
    }
    if len(method.param_types) != len(requirement.param_types) + 1 {
        return false
    }
    i := 0
    for i < len(requirement.param_types) {
        if !same_type(method.param_types[i + 1], requirement.param_types[i]) {
            return false
        }
        i = i + 1
    }
    same_type(method.return_type, requirement.return_type)
}

func receiver_mode_from_type(string receiver_type) string {
    if starts_with(receiver_type, "&") || starts_with(receiver_type, "*") {
        return "ref"
    }
    if starts_with(receiver_type, "&") || starts_with(receiver_type, "*") {
        return "ref"
    }
    "value"
}

func receiver_mode_from_signature(function_decl method_decl) string {
    receiver_mode_from_params(method_decl.sig.params)
}

func receiver_mode_from_param_name(param_decl[] params) string {
    receiver_mode_from_params(params)
}

func receiver_mode_from_params(param_decl[] params) string {
    if len(params) == 0 {
        return "value"
    }
    if params[0].name != "self" {
        return "value"
    }
    if starts_with(params[0].type_name, "&") {
        return "mut_ref"
    }
    if starts_with(params[0].type_name, "&") {
        return "ref"
    }
    "value"
}

func check_receiver_method(receiver_method_decl method_decl, function_binding[] functions, trait_binding[] traits, const_binding[] consts, string source, semantic_error[] diagnostics) int {
    method := method_decl.method
    if method.body.is_none() {
        return 0
    }
    pre_errors := validate_function_signature(method, source, diagnostics)
    expected_return :=
        switch method.sig.return_type {
            option.some(type_name) : parse_type(type_name),
            option.none : "()",
        }
    env := type_binding[]()
    i := 0
    for i < len(consts) {
        env.push(type_binding {
            name: consts[i].name, type_name consts[i].type_name,
        })
        i = i + 1
    }
    env.push(type_binding {
        name: method_decl.receiver_name, type_name parse_type(method_decl.receiver_type),
    })
    i = 0
    for i < len(method.sig.params) {
        param := method.sig.params[i]
        env.push(type_binding {
            name: param.name, type_name parse_type(param.type_name),
        })
        i = i + 1
    }
    result := infer_block_expr(method.body.unwrap(), env, borrow_state_new(), expected_return, functions, traits, source, diagnostics)
    if expected_return != "()" && !is_unknown(expected_return) && !is_unknown(result.type_name) {
        if !same_type(expected_return, result.type_name) {
            return pre_errors + result.errors + add_error(source, diagnostics, "e3004", "method return type mismatch", method.sig.name
        }
    }
    pre_errors + result.errors
}

func check_function(function_decl function_decl, function_binding[] functions, trait_binding[] traits, const_binding[] consts, string source, semantic_error[] diagnostics) int {
    if function_decl.body.is_none() {
        return 0
    }
    pre_errors := validate_function_signature(function_decl, source, diagnostics)
    expected_return :=
        switch function_decl.sig.return_type {
            option.some(type_name) : parse_type(type_name),
            option.none : "()",
        }
    env := type_binding[]()
    i := 0
    for i < len(consts) {
        env.push(type_binding {
            name: consts[i].name, type_name consts[i].type_name,
        })
        ;
        i = i + 1
    }
    i = 0
    for i < len(function_decl.sig.params) {
        param := function_decl.sig.params[i]
        env.push(type_binding {
            name: param.name, type_name parse_type(param.type_name),
        })
        ;
        i = i + 1
    }
    result := infer_block_expr(function_decl.body.unwrap(), env, borrow_state_new(), expected_return, functions, traits, source, diagnostics)
    if expected_return != "()" && !is_unknown(expected_return) && !is_unknown(result.type_name) {
        if !same_type(expected_return, result.type_name) {
            return pre_errors + result.errors + add_error(source, diagnostics, "e3004", "function return type mismatch", function_decl.sig.name
        }
    }
    pre_errors + result.errors
}

func validate_function_signature(function_decl function_decl, string source, semantic_error[] diagnostics) int {
    errors := 0
    i := 0
    for i < len(function_decl.sig.generics) {
        gi := generic_name(function_decl.sig.generics[i])
        j := i + 1
        for j < len(function_decl.sig.generics) {
            if gi == generic_name(function_decl.sig.generics[j]) {
                errors = errors + add_error(source, diagnostics, "e3012", "duplicate generic parameter", gi)
            }
            j = j + 1
        }
        i = i + 1
    }
    i = 0
    for i < len(function_decl.sig.params) {
        pi := function_decl.sig.params[i].name
        pj := i + 1
        for pj < len(function_decl.sig.params) {
            if pi == function_decl.sig.params[pj].name {
                errors = errors + add_error(source, diagnostics, "e3013", "duplicate parameter name", pi)
            }
            pj = pj + 1
        }
        i = i + 1
    }
    switch function_decl.sig.return_type {
        option.some(rt) : {
            if has_unknown_component(rt) {
                errors = errors + add_error(source, diagnostics, "e3014", "return type has unknown component", function_decl.sig.name
            }
        }
        option.none : (),
    }
    errors
}

func infer_block_expr(block_expr block, type_binding[] outer_env, borrow_record[] incoming_borrows, string expected_return, function_binding[] functions, trait_binding[] traits, string source, semantic_error[] diagnostics) check_result {
    local_env := clone_env(outer_env)
    borrow_state := borrow_state_clone(incoming_borrows)
    errors := 0
    i := 0
    for i < len(block.statements) {
        errors = errors + check_stmt(block.statements[i], local_env, borrow_state, expected_return, functions, traits, source, diagnostics)
        borrow_state_clear(borrow_state)
        i = i + 1
    }
    switch block.final_expr {
        option.some(final_expr) : {
            final_result := infer_expr(final_expr, local_env, borrow_state, expected_return, functions, traits, source, diagnostics)
            borrow_state_merge_moves(incoming_borrows, borrow_state)
            check_result {
                type_name: final_result.type_name, errors errors + final_result.errors,
            }
        }
        option.none : check_result {
            borrow_state_merge_moves(incoming_borrows, borrow_state)
            type_name: "()", errors errors,
        },
    }
}

func check_stmt(stmt stmt, type_binding[] env, borrow_record[] borrow_state, string expected_return, function_binding[] functions, trait_binding[] traits, string source, semantic_error[] diagnostics) int {
    switch stmt {
        stmt.let(value) : {
            rhs := infer_expr(value.value, env, borrow_state, expected_return, functions, traits, source, diagnostics)
            errors := rhs.errors
            if is_borrow_expr(value.value) {
                errors = errors + add_error(source, diagnostics, "e3052", "borrowed reference cannot be stored in a local binding before lifetime checking is implemented", value.name)
            }
            binding_type := rhs.type_name
            if value.type_name.is_some() {
                declared := parse_type(value.type_name.unwrap())
                if !types_compatible(declared, rhs.type_name) {
                    errors = errors + add_error(source, diagnostics, "e3001", "variable initializer type mismatch", value.name)
                }
                binding_type = declared
            }
            env.push(type_binding {
                name: value.name, type_name binding_type,
            })
            switch value.value {
                expr::name(name_value) : borrow_state_mark_move(borrow_state, name_value.name, rhs.type_name),
                _ : (),
            }
            ;
            errors
        }
        stmt.assign(value) : {
            target_type := lookup_name_type(env, value.name)
            if borrow_state_has_conflict(borrow_state, value.name, true) {
                return add_error(source, diagnostics, "e3056", "cannot assign to a borrowed value", value.name)
            }
            rhs := infer_expr(value.value, env, borrow_state, expected_return, functions, traits, source, diagnostics)
            errors := rhs.errors
            if is_unknown(target_type) {
                return errors + add_error(source, diagnostics, "e3002", "assignment to undefined name", value.name
            }
            if !types_compatible(target_type, rhs.type_name) {
                return errors + add_error(source, diagnostics, "e3003", "assignment type mismatch", value.name
            }
            errors
        }
        stmt.increment(value) : {
            ty := lookup_name_type(env, value.name)
            if borrow_state_has_conflict(borrow_state, value.name, true) {
                return add_error(source, diagnostics, "e3056", "cannot mutate a borrowed value", value.name)
            }
            if !types_compatible("int", ty) {
                return add_error(source, diagnostics, "e3005", "increment requires int", value.name
            }
            0
        }
        stmt.c_for(value) : {
            errors := 0
            errors = errors + check_stmt(value.init.value, env, borrow_state, expected_return, functions, traits, source, diagnostics)
            cond := infer_expr(value.condition, env, borrow_state, expected_return, functions, traits, source, diagnostics)
            errors = errors + cond.errors
            if !types_compatible("bool", cond.type_name) {
                errors = errors + add_error(source, diagnostics, "e3006", "for condition must be bool", "for")
            }
            errors = errors + check_stmt(value.step.value, env, borrow_state, expected_return, functions, traits, source, diagnostics)
            body_result := infer_block_expr(value.body, env, borrow_state, expected_return, functions, traits, source, diagnostics)
            errors = errors + body_result.errors
            errors
        }
        stmt.return(value) : {
            switch value.value {
                option.some(expr) : {
                    expr_result := infer_expr(expr, env, borrow_state, expected_return, functions, traits, source, diagnostics)
                    if is_borrow_expr(expr) {
                        return expr_result.errors + add_error(source, diagnostics, "e3053", "cannot return a reference to a local value because it does not live long enough", "return"
                    }
                    if expected_return == "()" {
                        return expr_result.errors + add_error(source, diagnostics, "e3007", "unexpected return value", "return"
                    }
                    if !types_compatible(expected_return, expr_result.type_name) {
                        return expr_result.errors + add_error(source, diagnostics, "e3008", "return type mismatch", "return"
                    }
                    switch expr {
                        expr::name(name_value) : borrow_state_mark_move(borrow_state, name_value.name, expr_result.type_name),
                        _ : (),
                    }
                    expr_result.errors
                }
                option.none : {
                    if expected_return == "()" {
                        return 0
                    }
                    add_error(source, diagnostics, "e3009", "missing return value", "return"
                }
            }
        }
        stmt.expr(value) : {
            infer_expr(value.expr, env, borrow_state, expected_return, functions, traits, source, diagnostics).errors
        }
        stmt.defer(value) : {
            infer_expr(value.expr, env, borrow_state, expected_return, functions, traits, source, diagnostics).errors
        }
        stmt.sroutine(value) : {
            infer_expr(value.expr, env, borrow_state, expected_return, functions, traits, source, diagnostics).errors
        }
    }
}

func infer_expr(expr expr, type_binding[] env, borrow_record[] borrow_state, string expected_return, function_binding[] functions, trait_binding[] traits, string source, semantic_error[] diagnostics) check_result {
    switch expr {
        expr::int(_) : ok_type("int"),
        expr::string(_) : ok_type("string"),
        expr::bool(_) : ok_type("bool"),
        expr::name(value) : {
            if value.name == "nil" {
                return ok_type("nil"
            }
            ty := lookup_name_type(env, value.name)
            if borrow_state_is_moved(borrow_state, value.name) {
                return check_result {
                    type_name: "unknown", errors add_error(source, diagnostics, "e3059", "use of moved value", value.name),
                }
            }
            if is_unknown(ty) {
                fn_candidates := lookup_functions(functions, value.name)
                if len(fn_candidates) > 0 {
                    return ok_type("fn"
                }
                return check_result {
                    type_name: "unknown", errors add_error(source, diagnostics, "e3010", "undefined identifier", value.name),
                }
            }
            ok_type(ty)
        }
        expr::borrow(value) : {
            target_name := borrow_place_name(value.target.value)
            if target_name == "" {
                return check_result {
                    type_name: "unknown", errors add_error(source, diagnostics, "e3055", "borrow target must be a named local, parameter, or field", "&"),
                }
            }
            root_name := target_name
            dot := 0
            for dot < len(root_name) {
                if string(root_name[dot]) == "." {
                    root_name = slice(root_name, 0, dot)
                    break
                }
                dot = dot + 1
            }
            if is_unknown(lookup_name_type(env, root_name)) {
                return check_result {
                    type_name: "unknown", errors add_error(source, diagnostics, "e3054", "cannot borrow an undefined name", root_name),
                }
            }
            if borrow_state_has_conflict(borrow_state, target_name, value.mutable) {
                code := if value.mutable { "e3057" } else { "e3058" }
                message := if value.mutable { "cannot mutably borrow because it is already borrowed" } else { "cannot borrow because it is already mutably borrowed" }
                return check_result {
                    type_name: "unknown", errors add_error(source, diagnostics, code, message, target_name),
                }
            }
            base := infer_expr(value.target.value, env, borrow_state, expected_return, functions, traits, source, diagnostics)
            if is_unknown(base.type_name) {
                return base
            }
            borrow_state_push(borrow_state, target_name, value.mutable)
            prefix := if value.mutable { "&mut " } else { "&" }
            check_result {
                type_name: prefix + base.type_name, errors base.errors,
            }
        }
        expr::binary(value) : {
            left := infer_expr(value.left.value, env, borrow_state, expected_return, functions, traits, source, diagnostics)
            right := infer_expr(value.right.value, env, borrow_state, expected_return, functions, traits, source, diagnostics)
            infer_binary(value.op, left, right, source, diagnostics)
        }
        expr::member(value) : {
            target := infer_expr(value.target.value, env, borrow_state, expected_return, functions, traits, source, diagnostics)
            field_type := lookup_builtin_field_type(target.type_name, value.member)
            if field_type == "" {
                return check_result {
                    type_name: "unknown", errors target.errors + add_error(source, diagnostics, "e3011", "unknown member", value.member),
                }
            }
            check_result {
                type_name: parse_type(field_type), errors target.errors,
            }
        }
        expr::index(value) : {
            target := infer_expr(value.target.value, env, borrow_state, expected_return, functions, traits, source, diagnostics)
            index := infer_expr(value.index.value, env, borrow_state, expected_return, functions, traits, source, diagnostics)
            errors := target.errors + index.errors
            if starts_with(target.type_name, "[]") {
                if !types_compatible("int", index.type_name) {
                    errors = errors + add_error(source, diagnostics, "e3012", "index must be int", "[")
                }
                return check_result {
                    type_name: parse_type(slice(target.type_name, 2, len(target.type_name))), errors errors,
                }
            }
            if starts_with(target.type_name, "[") {
                if !types_compatible("int", index.type_name) {
                    errors = errors + add_error(source, diagnostics, "e3012", "index must be int", "[")
                }
                return check_result {
                    type_name: strip_array_prefix(target.type_name), errors errors,
                }
            }
            if starts_with(target.type_name, "string") {
                if !types_compatible("int", index.type_name) {
                    errors = errors + add_error(source, diagnostics, "e3012", "index must be int", "[")
                }
                return check_result {
                    type_name: "u8", errors errors,
                }
            }
            if target.type_name == "map" {
                return check_result {
                    type_name: "fn", errors errors,
                }
            }
            check_result {
                type_name: "unknown", errors errors + add_error(source, diagnostics, "e3013", "index target is not indexable", "["),
            }
        }
        expr::call(value) : {
            errors := 0
            arg_types := string[]()
            i := 0
            for i < len(value.args) {
                arg_result := infer_expr(value.args[i], env, borrow_state, expected_return, functions, traits, source, diagnostics)
                errors = errors + arg_result.errors
                arg_types = append(arg_types, arg_result.type_name);
                switch value.args[i] {
                    expr::name(name_value) : borrow_state_mark_move(borrow_state, name_value.name, arg_result.type_name),
                    _ : (),
                }
                i = i + 1
            }
            switch value.callee.value {
                expr::member(member) : {
                    target := infer_expr(member.target.value, env, borrow_state, expected_return, functions, traits, source, diagnostics)
                    errors = errors + target.errors
                    named_methods := lookup_named_methods(functions, target.type_name, member.member)
                    methods := lookup_methods(functions, target.type_name, member.member, member.target.value)
                    if len(methods) > 0 {
                        matches := signature_match[]()
                        j := 0
                        for j < len(methods) {
                            method_arg_types := string[]()
                            method_arg_types = append(method_arg_types, method_receiver_arg_type(target.type_name, methods[j].receiver_mode));
                            ai := 0
                            for ai < len(arg_types) {
                                method_arg_types = append(method_arg_types, arg_types[ai]);
                                ai = ai + 1
                            }
                            m := try_match_signature(methods[j], method_arg_types, functions, traits)
                            if m.ok {
                                matches = append(matches, m);
                            }
                            j = j + 1
                        }
                        if len(matches) == 0 {
                            return check_result {
                                type_name: "unknown", errors errors + add_error(source, diagnostics, "e1002", "no matching overload", member.member),
                            }
                        }
                        best := matches[0]
                        ambiguous := false
                        j = 1
                        for j < len(matches) {
                            if better_match(matches[j], best) {
                                best = matches[j]
                                ambiguous = false
                            } else if same_match_rank(matches[j], best) {
                                ambiguous = true
                            }
                            j = j + 1
                        }
                        if ambiguous {
                            return check_result {
                                type_name: "unknown", errors errors + add_error(source, diagnostics, "e1003", "ambiguous overload", member.member),
                            }
                        }
                        return check_result {
                            type_name: best.return_type, errors errors,
                        }
                    }
                    if len(named_methods) > 0 {
                        return check_result {
                            type_name: "unknown", errors errors + add_error(source, diagnostics, "e3051", receiver_requirement_message(member.member, named_methods[0].receiver_mode), member.member),
                        }
                    }
                    trait_result := find_trait_binding(traits, target.type_name)
                    if trait_result.is_some() {
                        required_method := find_trait_method(trait_result.unwrap(), member.member)
                        if required_method.is_some() {
                            requirement := required_method.unwrap()
                            if len(requirement.param_types) != len(arg_types) {
                                return check_result {
                                    type_name: "unknown", errors errors + add_error(source, diagnostics, "e1002", "no matching interface method", member.member),
                                }
                            }
                            ai := 0
                            for ai < len(arg_types) {
                                if !types_compatible(requirement.param_types[ai], arg_types[ai]) {
                                    return check_result {
                                        type_name: "unknown", errors errors + add_error(source, diagnostics, "e1002", "no matching interface method", member.member),
                                    }
                                }
                                ai = ai + 1
                            }
                            return check_result {
                                type_name: requirement.return_type, errors errors,
                            }
                        }
                    }
                    arity := lookup_builtin_method_arity(target.type_name, member.member)
                    if arity >= 0 && arity != len(value.args) {
                        errors = errors + add_error(source, diagnostics, "e1005", "builtin method arity mismatch", member.member)
                    }
                    method_type := lookup_builtin_method_type(target.type_name, member.member)
                    if method_type == "" {
                        return check_result {
                            type_name: "unknown", errors errors + add_error(source, diagnostics, "e1006", "unknown method", member.member),
                        }
                    }
                    check_result {
                        type_name: resolve_method_return(target.type_name, method_type), errors errors,
                    }
                }
                expr::name(callee_name) : {
                    candidates := lookup_functions(functions, callee_name.name)
                    if len(candidates) == 0 {
                        return check_result {
                            type_name: "unknown", errors errors + add_error(source, diagnostics, "e1001", "undefined function", callee_name.name),
                        }
                    }
                    matches := signature_match[]()
                    j := 0
                    for j < len(candidates) {
                        m := try_match_signature(candidates[j], arg_types, functions, traits)
                        if m.ok {
                            matches = append(matches, m);
                        }
                        j = j + 1
                    }
                    if len(matches) == 0 {
                        return check_result {
                            type_name: "unknown", errors errors + add_error(source, diagnostics, "e1002", "no matching overload", callee_name.name),
                        }
                    }
                    best := matches[0]
                    ambiguous := false
                    j = 1
                    for j < len(matches) {
                        if better_match(matches[j], best) {
                            best = matches[j]
                            ambiguous = false
                        } else if same_match_rank(matches[j], best) {
                            ambiguous = true
                        }
                        j = j + 1
                    }
                    if ambiguous {
                        return check_result {
                            type_name: "unknown", errors errors + add_error(source, diagnostics, "e1003", "ambiguous overload", callee_name.name),
                        }
                    }
                    check_result {
                        type_name: best.return_type, errors errors,
                    }
                }
                _ : {
                    callee := infer_expr(value.callee.value, env, borrow_state, expected_return, functions, traits, source, diagnostics)
                    check_result {
                        type_name: "unknown", errors errors + callee.errors,
                    }
                }
            }
        }
        expr::switch(value) : {
            subject := infer_expr(value.subject.value, env, borrow_state, expected_return, functions, traits, source, diagnostics)
            errors := subject.errors
            arm_type := "unknown"
            seen_patterns := pattern[]()
            arm_base_borrows := borrow_state_clone(borrow_state)
            i := 0
            for i < len(value.arms) {
                arm := value.arms[i]
                if pattern_unreachable(seen_patterns, arm.pattern, subject.type_name) {
                    errors = errors + add_error(source, diagnostics, "e2003", "unreachable switch arm", pattern_anchor(arm.pattern))
                }
                if pattern_duplicate(seen_patterns, arm.pattern, subject.type_name) {
                    errors = errors + add_error(source, diagnostics, "e2002", "duplicate switch arm", pattern_anchor(arm.pattern))
                }
                pattern_result := check_pattern(arm.pattern, subject.type_name, source, diagnostics)
                errors = errors + pattern_result.errors
                arm_env := clone_env(env)
                append_bindings(arm_env, pattern_result.bindings)
                arm_borrows := borrow_state_clone(arm_base_borrows)
                arm_result := infer_expr(arm.expr, arm_env, arm_borrows, expected_return, functions, traits, source, diagnostics)
                errors = errors + arm_result.errors
                borrow_state_merge_moves(borrow_state, arm_borrows)
                if is_unknown(arm_type) {
                    arm_type = arm_result.type_name
                } else if !types_compatible(arm_type, arm_result.type_name) {
                    errors = errors + add_error(source, diagnostics, "e2005", "switch arm result type mismatch", "switch")
                }
                seen_patterns = append(seen_patterns, arm.pattern);
                i = i + 1
            }
            base := base_type_name(subject.type_name)
            if (base == "option" || base == "result") && !patterns_cover_type(seen_patterns, subject.type_name) {
                errors = errors + add_error(source, diagnostics, "e2001", "non-exhaustive switch", "switch")
            }
            check_result {
                type_name: arm_type, errors errors,
            }
        }
        expr::if(value) : {
            cond := infer_expr(value.condition.value, env, borrow_state, expected_return, functions, traits, source, diagnostics)
            then_borrows := borrow_state_clone(borrow_state)
            then_result := infer_block_expr(value.then_branch, env, then_borrows, expected_return, functions, traits, source, diagnostics)
            else_borrows := borrow_state_clone(borrow_state)
            errors := cond.errors + then_result.errors
            if !types_compatible("bool", cond.type_name) {
                errors = errors + add_error(source, diagnostics, "e3014", "if condition must be bool", "if")
            }
            switch value.else_branch {
                option::some(else_expr) : {
                    else_result := infer_expr(else_expr.value, env, else_borrows, expected_return, functions, traits, source, diagnostics)
                    errors = errors + else_result.errors
                    borrow_state_merge_moves(borrow_state, then_borrows)
                    borrow_state_merge_moves(borrow_state, else_borrows)
                    if !types_compatible(then_result.type_name, else_result.type_name) {
                        errors = errors + add_error(source, diagnostics, "e3015", "if/else type mismatch", "if")
                    }
                    check_result {
                        type_name: then_result.type_name, errors errors,
                    }
                }
                option::none : check_result {
                    borrow_state_merge_moves(borrow_state, then_borrows)
                    type_name: "()", errors errors,
                },
            }
        }
        expr::while(value) : {
            cond := infer_expr(value.condition.value, env, borrow_state, expected_return, functions, traits, source, diagnostics)
            body_borrows := borrow_state_clone(borrow_state)
            body_result := infer_block_expr(value.body, env, body_borrows, expected_return, functions, traits, source, diagnostics)
            borrow_state_merge_moves(borrow_state, body_borrows)
            errors := cond.errors + body_result.errors
            if !types_compatible("bool", cond.type_name) {
                errors = errors + add_error(source, diagnostics, "e3016", "while condition must be bool", "while")
            }
            check_result {
                type_name: "()", errors errors,
            }
        }
        expr::for(value) : {
            iter := infer_expr(value.iterable.value, env, borrow_state, expected_return, functions, traits, source, diagnostics)
            body_borrows := borrow_state_clone(borrow_state)
            body_result := infer_block_expr(value.body, env, body_borrows, expected_return, functions, traits, source, diagnostics)
            borrow_state_merge_moves(borrow_state, body_borrows)
            check_result {
                type_name: "()", errors iter.errors + body_result.errors,
            }
        }
        expr::block(value) : {
            infer_block_expr(value, env, borrow_state, expected_return, functions, traits, source, diagnostics)
        }
        expr::array(value) : {
            if len(value.items) == 0 {
                return ok_type("unknown[]"
            }
            first := infer_expr(value.items[0], env, borrow_state, expected_return, functions, traits, source, diagnostics)
            errors := first.errors
            i := 1
            for i < len(value.items) {
                item := infer_expr(value.items[i], env, borrow_state, expected_return, functions, traits, source, diagnostics)
                errors = errors + item.errors
                if !types_compatible(first.type_name, item.type_name) {
                    errors = errors + add_error(source, diagnostics, "e3017", "array item type mismatch", "[")
                }
                i = i + 1
            }
            check_result {
                type_name: "[]" + first.type_name, errors errors,
            }
        }
        expr::map(value) : {
            errors := 0
            i := 0
            for i < len(value.entries) {
                errors = errors + infer_expr(value.entries[i].key, env, borrow_state, expected_return, functions, traits, source, diagnostics).errors
                errors = errors + infer_expr(value.entries[i].value, env, borrow_state, expected_return, functions, traits, source, diagnostics).errors
                i = i + 1
            }
            check_result {
                type_name: "map", errors errors,
            }
        }
    }
}

func is_borrow_expr(expr value) bool {
    switch value {
        expr::borrow(_) : true,
        _ : false,
    }
}

func check_pattern(pattern pattern, string expected_type, string source, semantic_error[] diagnostics) pattern_check_result {
    bindings := type_binding[]()
    errors := bind_pattern(pattern, expected_type, bindings, source, diagnostics)
    pattern_check_result {
        bindings: bindings, errors errors,
    }
}

func bind_pattern(pattern pattern, string expected_type, type_binding[] bindings, string source, semantic_error[] diagnostics) int {
    if is_unknown(expected_type) {
        return add_error(source, diagnostics, "e2007", "pattern expected type is unknown", pattern_anchor(pattern))
    }
    switch pattern {
        pattern::name(value) : {
            add_binding(bindings, value.name, expected_type, source, diagnostics)
        }
        pattern::wildcard(_) : 0,
        pattern::literal(value) : {
            literal_type := literal_pattern_type(value)
            if !types_compatible(expected_type, literal_type) {
                return add_error(source, diagnostics, "e2006", "literal pattern type mismatch", literal_pattern_text(value))
            }
            0
        }
        pattern::variant(value) : {
            variant := last_path_segment(value.path)
            base := base_type_name(expected_type)
            if base == "option" {
                if variant == "some" {
                    if len(value.args) != 1 {
                        return add_error(source, diagnostics, "e2004", "some payload arity mismatch", value.path
                    }
                    return bind_pattern(value.args[0], first_type_arg(expected_type), bindings, source, diagnostics
                }
                if variant == "none" {
                    if len(value.args) == 0 {
                        return 0
                    }
                    return add_error(source, diagnostics, "e2004", "none must not have payload", value.path
                }
                return add_error(source, diagnostics, "e2006", "invalid option constructor", value.path
            }
            if base == "result" {
                if variant == "ok" {
                    if len(value.args) != 1 {
                        return add_error(source, diagnostics, "e2004", "ok payload arity mismatch", value.path
                    }
                    return bind_pattern(value.args[0], first_type_arg(expected_type), bindings, source, diagnostics
                }
                if variant == "err" {
                    if len(value.args) != 1 {
                        return add_error(source, diagnostics, "e2004", "err payload arity mismatch", value.path
                    }
                    return bind_pattern(value.args[0], second_type_arg(expected_type), bindings, source, diagnostics
                }
                return add_error(source, diagnostics, "e2006", "invalid result constructor", value.path
            }
            add_error(source, diagnostics, "e2006", "variant pattern not allowed for this type", value.path)
        }
    }
}

func add_binding(type_binding[] bindings, string name, string type_name, string source, semantic_error[] diagnostics) int {
    if name == "_" {
        return 0
    }
    i := 0
    for i < len(bindings) {
        if bindings[i].name == name {
            if !types_compatible(bindings[i].type_name, type_name) {
                return add_error(source, diagnostics, "e2008", "conflicting binding type in pattern", name
            }
            return 0
        }
        i = i + 1
    }
    bindings.push(type_binding {
        name: name, type_name parse_type(type_name),
    })
    ;
    0
}

func append_bindings(type_binding[] target, type_binding[] source) {
    i := 0
    for i < len(source) {
        target = append(target, source[i]);
        i = i + 1
    }
}

func pattern_duplicate(pattern[] seen, pattern current, string expected_type) bool {
    i := 0
    for i < len(seen) {
        if pattern_equivalent(seen[i], current, expected_type) {
            return true
        }
        i = i + 1
    }
    false
}

func pattern_unreachable(pattern[] seen, pattern current, string expected_type) bool {
    i := 0
    for i < len(seen) {
        if pattern_subsumes(seen[i], current, expected_type) {
            return true
        }
        i = i + 1
    }
    false
}

func pattern_equivalent(pattern left, pattern right, string expected_type) bool {
    pattern_subsumes(left, right, expected_type) && pattern_subsumes(right, left, expected_type)
}

func pattern_subsumes(pattern left, pattern right, string expected_type) bool {
    if pattern_is_wild(left) {
        return true
    }
    if pattern_is_wild(right) {
        return false
    }
    switch left {
        pattern::literal(lv) : {
            switch right {
                pattern::literal(rv) : literal_pattern_equals(lv, rv),
                _ : false,
            }
        }
        pattern::variant(lv) : {
            switch right {
                pattern::variant(rv) : {
                    lctor := last_path_segment(lv.path)
                    rctor := last_path_segment(rv.path)
                    if lctor != rctor {
                        return false
                    }
                    if len(lv.args) == 0 && len(rv.args) == 0 {
                        return true
                    }
                    if len(lv.args) != 1 || len(rv.args) != 1 {
                        return false
                    }
                    payload_type := variant_payload_type(expected_type, lctor)
                    if is_unknown(payload_type) {
                        return false
                    }
                    return pattern_subsumes(lv.args[0], rv.args[0], payload_type
                }
                _ : false,
            }
        }
        _ : false,
    }
}

func patterns_cover_type(pattern[] patterns, string expected_type) bool {
    i := 0
    for i < len(patterns) {
        if pattern_is_wild(patterns[i]) {
            return true
        }
        i = i + 1
    }
    base := base_type_name(expected_type)
    if base == "option" {
        return option_patterns_cover(patterns, expected_type
    }
    if base == "result" {
        return result_patterns_cover(patterns, expected_type
    }
    false
}

func option_patterns_cover(pattern[] patterns, string expected_type) bool {
    seen_none := false
    some_patterns := pattern[]()
    i := 0
    for i < len(patterns) {
        switch patterns[i] {
            pattern::variant(value) : {
                ctor := last_path_segment(value.path)
                if ctor == "none" {
                    seen_none = true
                } else if ctor == "some" && len(value.args) == 1 {
                    some_patterns = append(some_patterns, value.args[0]);
                }
            }
            _ : (),
        }
        i = i + 1
    }
    if !seen_none {
        return false
    }
    patterns_cover_type(some_patterns, first_type_arg(expected_type))
}

func result_patterns_cover(pattern[] patterns, string expected_type) bool {
    ok_patterns := pattern[]()
    err_patterns := pattern[]()
    i := 0
    for i < len(patterns) {
        switch patterns[i] {
            pattern::variant(value) : {
                ctor := last_path_segment(value.path)
                if ctor == "ok" && len(value.args) == 1 {
                    ok_patterns = append(ok_patterns, value.args[0]);
                } else if ctor == "err" && len(value.args) == 1 {
                    err_patterns = append(err_patterns, value.args[0]);
                }
            }
            _ : (),
        }
        i = i + 1
    }
    if !patterns_cover_type(ok_patterns, first_type_arg(expected_type)) {
        return false
    }
    patterns_cover_type(err_patterns, second_type_arg(expected_type))
}

func pattern_is_wild(pattern pattern) bool {
    switch pattern {
        pattern::wildcard(_) : true,
        pattern::name(_) : true,
        _ : false,
    }
}

func pattern_anchor(pattern pattern) string {
    switch pattern {
        pattern::name(value) : value.name,
        pattern::wildcard(_) : "_",
        pattern::literal(value) : literal_pattern_text(value),
        pattern::variant(value) : value.path,
    }
}

func literal_pattern_type(literal_pattern value) string {
    switch value.value {
        expr::int(_) : "int",
        expr::string(_) : "string",
        expr::bool(_) : "bool",
        _ : "unknown",
    }
}

func literal_pattern_text(literal_pattern value) string {
    switch value.value {
        expr::int(v) : v.value,
        expr::string(v) : v.value,
        expr::bool(v) : if v.value { "true" } else { "false" },
        _ : "<literal>",
    }
}

func literal_pattern_equals(literal_pattern left, literal_pattern right) bool {
    literal_pattern_type(left) == literal_pattern_type(right) && literal_pattern_text(left) == literal_pattern_text(right)
}

func variant_payload_type(string expected_type, string ctor) string {
    base := base_type_name(expected_type)
    if base == "option" {
        if ctor == "some" {
            return first_type_arg(expected_type
        }
        if ctor == "none" {
            return "()"
        }
    }
    if base == "result" {
        if ctor == "ok" {
            return first_type_arg(expected_type
        }
        if ctor == "err" {
            return second_type_arg(expected_type
        }
    }
    "unknown"
}

func infer_binary(string op, check_result left, check_result right, string source, semantic_error[] diagnostics) check_result {
    errors := left.errors + right.errors
    if op == "+" || op == "-" || op == "*" || op == "/" || op == "%" {
        if !types_compatible("int", left.type_name) || !types_compatible("int", right.type_name) {
            errors = errors + add_error(source, diagnostics, "e3018", "arithmetic requires int", op)
        }
        return check_result {
            type_name: "int", errors errors,
        }
    }
    if op == "<" || op == "<=" || op == ">" || op == ">=" {
        if !types_compatible("int", left.type_name) || !types_compatible("int", right.type_name) {
            errors = errors + add_error(source, diagnostics, "e3019", "ordering compare requires int", op)
        }
        return check_result {
            type_name: "bool", errors errors,
        }
    }
    if op == "==" || op == "!=" {
        if !types_compatible(left.type_name, right.type_name) {
            errors = errors + add_error(source, diagnostics, "e3020", "equality compare requires same type", op)
        }
        if !is_unknown(left.type_name) && !is_unknown(right.type_name) && !nil_comparable_pair(left.type_name, right.type_name) {
            if !comparable_type(left.type_name) || !comparable_type(right.type_name) {
                errors = errors + add_error(source, diagnostics, "e3039", "equality compare requires comparable types", op)
            }
        }
        return check_result {
            type_name: "bool", errors errors,
        }
    }
    if op == "&&" || op == "||" {
        if !types_compatible("bool", left.type_name) || !types_compatible("bool", right.type_name) {
            errors = errors + add_error(source, diagnostics, "e3021", "logical op requires bool", op)
        }
        return check_result {
            type_name: "bool", errors errors,
        }
    }
    check_result {
        type_name: "unknown", errors errors,
    }
}

func lookup_functions(function_binding[] functions, string name) function_binding[] {
    out := function_binding[]()
    i := 0
    for i < len(functions) {
        if !functions[i].has_receiver && functions[i].name == name {
            out = append(out, functions[i]);
        }
        i = i + 1
    }
    out
}

func lookup_named_methods(function_binding[] functions, string receiver_type, string name) function_binding[] {
    out := function_binding[]()
    normalized_receiver := method_owner_type(receiver_type)
    i := 0
    for i < len(functions) {
        if functions[i].has_receiver && functions[i].owner_type == normalized_receiver && functions[i].name == name {
            out = append(out, functions[i]);
        }
        i = i + 1
    }
    out
}

func lookup_methods(function_binding[] functions, string receiver_type, string name, expr receiver_expr) function_binding[] {
    out := function_binding[]()
    normalized_receiver := method_owner_type(receiver_type)
    i := 0
    for i < len(functions) {
        if functions[i].has_receiver && functions[i].owner_type == normalized_receiver && functions[i].name == name {
            if receiver_allows_method(receiver_type, receiver_expr, functions[i].receiver_mode) {
                out = append(out, functions[i]);
            }
        }
        i = i + 1
    }
    out
}

func method_owner_type(string receiver_type) string {
    if starts_with(receiver_type, "&") {
        return slice(receiver_type, 5, len(receiver_type))
    }
    if starts_with(receiver_type, "&") {
        return slice(receiver_type, 1, len(receiver_type))
    }
    receiver_type
}

func receiver_allows_method(string receiver_type, expr receiver_expr, string receiver_mode) bool {
    if receiver_mode == "value" {
        return true
    }
    if receiver_mode == "mut_ref" {
        if starts_with(receiver_type, "&") {
            return true
        }
        return is_addressable_expr(receiver_expr
    }
    if receiver_mode == "ref" {
        if starts_with(receiver_type, "&") {
            return true
        }
        return is_addressable_expr(receiver_expr
    }
    false
}

func is_addressable_expr(expr value) bool {
    switch value {
        expr::name(_) : true,
        expr::member(_) : true,
        expr::index(_) : true,
        _ : false,
    }
}

func method_receiver_arg_type(string receiver_type, string receiver_mode) string {
    owner_type := method_owner_type(receiver_type)
    if receiver_mode == "mut_ref" {
        return "&" + owner_type
    }
    if receiver_mode == "ref" {
        return "&" + owner_type
    }
    owner_type
}

func receiver_requirement_message(string method_name, string receiver_mode) string {
    if receiver_mode == "mut_ref" {
        return "method " + method_name + " requires mutable receiver"
    }
    if receiver_mode == "ref" {
        return "method " + method_name + " requires addressable receiver"
    }
    "method " + method_name + " requires compatible receiver"
}

func try_match_signature(function_binding binding, string[] arg_types, function_binding[] functions, trait_binding[] traits) signature_match {
    if len(binding.param_types) != len(arg_types) {
        return signature_match {
            ok: false,
            return_type: "unknown", instance_name: "", score 0, generic_bind_count 0, unknown_arg_count 0,
        }
    }
    generic_bindings := type_binding[]()
    score := 0
    unknown_arg_count := 0
    i := 0
    for i < len(arg_types) {
        expected_ref := parse_type_ref(binding.param_types[i])
        actual_ref := parse_type_ref(arg_types[i])
        if is_unknown(actual_ref.canonical) {
            unknown_arg_count = unknown_arg_count + 1
        }
        matched := false
        trait_result := find_trait_binding(traits, expected_ref.canonical)
        if trait_result.is_some() {
            matched = receiver_type_implements_trait(actual_ref.canonical, trait_result.unwrap(), functions)
        } else {
            matched = match_type_pattern_ref(expected_ref, actual_ref, binding.generic_names, generic_bindings)
        }
        if !matched {
            return signature_match {
                ok: false,
                return_type: "unknown", instance_name: "", score 0, generic_bind_count 0, unknown_arg_count 0,
            }
        }
        score = score + match_specificity(expected_ref, actual_ref, binding.generic_names)
        i = i + 1
    }
    signature_match {
        ok: true, return_type instantiate_type(binding.return_type, binding.generic_names, generic_bindings), instance_name specialized_instance_name(binding, generic_bindings), score score, generic_bind_count len(generic_bindings), unknown_arg_count unknown_arg_count,
    }
}

func specialized_instance_name(function_binding binding, type_binding[] bindings) string {
    if len(binding.generic_names) == 0 {
        return binding.name
    }
    name := binding.name + "__mono"
    i := 0
    for i < len(binding.generic_names) {
        bound := lookup_name_type(bindings, binding.generic_names[i])
        if is_unknown(bound) {
            bound = "unknown"
        }
        name = name + "_" + mono_type_name(bound)
        i = i + 1
    }
    name
}

func mono_type_name(string type_name) string {
    out := ""
    i := 0
    for i < len(type_name) {
        ch := string(type_name[i])
        if ch == "&" { out = out + "ref"
        } else if ch == "[" { out = out + "arr"
        } else if ch == "]" { out = out + "end"
        } else if ch == " " || ch == "," { out = out + "_"
        } else { out = out + ch }
        i = i + 1
    }
    if out == "" { return "unknown" }
    out
}

func better_match(signature_match left, signature_match right) bool {
    if left.score != right.score {
        return left.score > right.score
    }
    if left.unknown_arg_count != right.unknown_arg_count {
        return left.unknown_arg_count < right.unknown_arg_count
    }
    if left.generic_bind_count != right.generic_bind_count {
        return left.generic_bind_count < right.generic_bind_count
    }
    false
}

func same_match_rank(signature_match left, signature_match right) bool {
    left.score == right.score
        && left.unknown_arg_count == right.unknown_arg_count
        && left.generic_bind_count == right.generic_bind_count
}

func match_type_pattern_ref(type_ref param_type, type_ref arg_type, string[] generic_names, type_binding[] generic_bindings) bool {
    p := param_type.canonical
    a := arg_type.canonical
    if is_generic_name(generic_names, p) {
        bound := lookup_name_type(generic_bindings, p)
        if is_unknown(bound) {
            generic_bindings.push(type_binding {
                name: p, type_name a,
            })
            ;
            return true
        }
        return same_type(bound, a
    }
    if param_type.is_ref != arg_type.is_ref {
        return false
    }
    if param_type.is_mut_ref != arg_type.is_mut_ref {
        return false
    }
    if param_type.is_slice != arg_type.is_slice {
        return false
    }
    if param_type.is_array != arg_type.is_array {
        return false
    }
    if param_type.is_array && param_type.array_len != arg_type.array_len {
        return false
    }
    if param_type.base != arg_type.base {
        return false
    }
    p_args := param_type.args
    a_args := arg_type.args
    if len(p_args) != len(a_args) {
        return same_type_ref(param_type, arg_type
    }
    i := 0
    for i < len(p_args) {
        p_next := parse_type_ref(p_args[i])
        a_next := parse_type_ref(a_args[i])
        if !match_type_pattern_ref(p_next, a_next, generic_names, generic_bindings) {
            return false
        }
        i = i + 1
    }
    true
}

func match_specificity(type_ref expected, type_ref actual, string[] generic_names) int {
    if same_type_ref(expected, actual) {
        return 5
    }
    if is_generic_name(generic_names, expected.canonical) {
        return 1
    }
    score := 0
    if expected.base == actual.base {
        score = score + 2
    }
    if expected.is_ref == actual.is_ref && expected.is_mut_ref == actual.is_mut_ref {
        score = score + 1
    }
    if expected.is_slice == actual.is_slice {
        score = score + 1
    }
    if expected.is_array == actual.is_array {
        score = score + 1
    }
    score
}

func instantiate_type(string ty, string[] generic_names, type_binding[] generic_bindings) string {
    clean := parse_type(ty)
    if is_generic_name(generic_names, clean) {
        bound := lookup_name_type(generic_bindings, clean)
        if !is_unknown(bound) {
            return bound
        }
    }
    if starts_with(clean, "&") {
        return "&" + instantiate_type(slice(clean, 5, len(clean)), generic_names, generic_bindings
    }
    if starts_with(clean, "&") {
        return "&" + instantiate_type(slice(clean, 1, len(clean)), generic_names, generic_bindings
    }
    if starts_with(clean, "[]") {
        return "[]" + instantiate_type(slice(clean, 2, len(clean)), generic_names, generic_bindings
    }
    if starts_with(clean, "[") {
        return array_prefix_text(clean) + instantiate_type(strip_array_prefix(clean), generic_names, generic_bindings
    }
    args := extract_type_args(clean)
    if len(args) == 0 {
        return clean
    }
    base := base_type_name(clean)
    built := base + "["
    i := 0
    for i < len(args) {
        if i > 0 {
            built = built + ", "
        }
        built = built + instantiate_type(args[i], generic_names, generic_bindings)
        i = i + 1
    }
    built + "]"
}

func type_contains_generic(string ty, string[] generic_names) bool {
    clean := parse_type(ty)
    if is_generic_name(generic_names, clean) {
        return true
    }
    if starts_with(clean, "&") {
        return type_contains_generic(slice(clean, 5, len(clean)), generic_names
    }
    if starts_with(clean, "&") {
        return type_contains_generic(slice(clean, 1, len(clean)), generic_names
    }
    if starts_with(clean, "[]") {
        return type_contains_generic(slice(clean, 2, len(clean)), generic_names
    }
    if starts_with(clean, "[") {
        return type_contains_generic(strip_array_prefix(clean), generic_names
    }
    args := extract_type_args(clean)
    i := 0
    for i < len(args) {
        if type_contains_generic(args[i], generic_names) {
            return true
        }
        i = i + 1
    }
    false
}

func is_generic_name(string[] generic_names, string name) bool {
    i := 0
    for i < len(generic_names) {
        if generic_names[i] == name {
            return true
        }
        i = i + 1
    }
    false
}

func strip_array_prefix(string ty) string {
    clean := parse_type(ty)
    if !starts_with(clean, "[") || starts_with(clean, "[]") {
        return clean
    }
    depth := 0
    i := 0
    for i < len(clean) {
        ch := char_at(clean, i)
        if ch == "[" {
            depth = depth + 1
        } else if ch == "]" {
            depth = depth - 1
            if depth == 0 {
                return parse_type(slice(clean, i + 1, len(clean)))
            }
        }
        i = i + 1
    }
    clean
}

func array_prefix_text(string ty) string {
    clean := parse_type(ty)
    tail := strip_array_prefix(clean)
    if tail == clean {
        return ""
    }
    slice(clean, 0, len(clean) - len(tail))
}

func generic_name(string raw) string {
    i := 0
    for i < len(raw) {
        if char_at(raw, i) == ":" {
            return trim_text(slice(raw, 0, i))
        }
        i = i + 1
    }
    trim_text(raw)
}

func clone_env(type_binding[] env) type_binding[] {
    out := type_binding[]()
    i := 0
    for i < len(env) {
        out = append(out, env[i]);
        i = i + 1
    }
    out
}

func lookup_name_type(type_binding[] env, string name) string {
    i := len(env)
    for i > 0 {
        i = i - 1
        if env[i].name == name {
            return env[i].type_name
        }
    }
    "unknown"
}

func ok_type(string type_name) check_result {
    check_result {
        type_name: parse_type(type_name), errors 0,
    }
}

func types_compatible(string left, string right) bool {
    if is_unknown(left) || is_unknown(right) {
        return is_unknown(left) && is_unknown(right
    }
    if is_nil(left) && is_nil(right) {
        return true
    }
    if is_nil(left) {
        return is_nilable_type(right
    }
    if is_nil(right) {
        return is_nilable_type(left
    }
    assignable_type(left, right) || compatible_type(left, right)
}

func nil_comparable_pair(string left, string right) bool {
    if is_nil(left) {
        return is_nil(right) || is_nilable_type(right
    }
    if is_nil(right) {
        return is_nilable_type(left
    }
    false
}

func is_nil(string type_name) bool {
    parse_type(type_name) == "nil"
}

func is_nilable_type(string type_name) bool {
    clean := parse_type(type_name)
    if clean == "fn" || clean == "map" {
        return true
    }
    if starts_with(clean, "[]") || starts_with(clean, "&") {
        return true
    }
    base := base_type_name(clean)
    base == "interface" || base == "trait"
}

func is_unknown(string type_name) bool {
    clean := parse_type(type_name)
    clean == "" || clean == "unknown"
}

func resolve_method_return(string target_type, string method_type) string {
    target_ref := parse_type_ref(target_type)
    if method_type == "t" {
        return type_arg(target_ref, 0
    }
    if method_type == "e" {
        return type_arg(target_ref, 1
    }
    if method_type == "option[t]" {
        arg := type_arg(target_ref, 0)
        if is_unknown(arg) {
            return "option[unknown]"
        }
        return "option[" + arg + "]"
    }
    parse_type(method_type)
}

func first_type_arg(string type_name) string {
    type_arg(parse_type_ref(type_name), 0)
}

func second_type_arg(string type_name) string {
    type_arg(parse_type_ref(type_name), 1)
}

func add_error(string source, semantic_error[] diagnostics, string code, string message, string anchor) int {
    recovery_anchor := resolve_recovery_anchor(source, anchor)
    chain_id := build_chain_id("semantic", code, recovery_anchor)
    pos := locate_anchor(source, recovery_anchor)
    severity := diagnostic_severity(code)
    tier := diagnostic_tier(code)
    hint := diagnostic_hint(code, recovery_anchor)
    diagnostics.push(semantic_error {
        code: code, message message,
        stage: "semantic", chain_id chain_id,
        upstream_code: "", severity severity, hint hint, anchor recovery_anchor, tier tier, repeat_count 1, line pos.line, column pos.column,
    })
    ;
    1
}

func build_chain_id(string stage, string code, string anchor) string {
    stage + ":" + code + ":" + sanitize_chain_anchor(anchor)
}

func chain_id_from_anchor(string anchor) string {
    build_chain_id("semantic", "s0001", anchor)
}

func sanitize_chain_anchor(string anchor) string {
    out := ""
    i := 0
    for i < len(anchor) {
        ch := slice(anchor, i, i + 1)
        if ch == " " || ch == "\t" || ch == "\n" || ch == "\r" {
            out = out + "_"
        } else {
            out = out + ch
        }
        i = i + 1
    }
    if out == "" {
        return "root"
    }
    out
}

func resolve_recovery_anchor(string source, string anchor) string {
    if anchor != "" && find_substring(source, anchor) >= 0 {
        return anchor
    }
    if find_substring(source, "return") >= 0 {
        return "return"
    }
    if find_substring(source, "switch") >= 0 {
        return "switch"
    }
    if find_substring(source, "func ") >= 0 {
        return "func"
    }
    "package"
}

func diagnostic_hint(string code, string anchor) string {
    if starts_with_text(code, "e100") {
        return "check overload candidates and argument types near " + anchor
    }
    if starts_with_text(code, "e200") {
        return "check switch exhaustiveness and pattern binding near " + anchor
    }
    if starts_with_text(code, "e300") {
        return "check declared vs inferred type around " + anchor
    }
    if starts_with_text(code, "e000") {
        return "fix parse/type-rule preconditions first"
    }
    "review surrounding declaration near " + anchor
}

func diagnostic_severity(string code) string {
    if starts_with_text(code, "e000") {
        return "fatal"
    }
    if starts_with_text(code, "e1") {
        return "warning"
    }
    "error"
}

func diagnostic_tier(string code) int {
    if starts_with_text(code, "e000") {
        return 0
    }
    if starts_with_text(code, "e1") {
        return 2
    }
    1
}

func starts_with_text(string text, string prefix) bool {
    if len(prefix) > len(text) {
        return false
    }
    slice(text, 0, len(prefix)) == prefix
}

func locate_anchor(string source, string anchor) source_pos {
    if anchor == "" {
        return source_pos {
            line: 0, column 0,
        }
    }
    idx := find_substring(source, anchor)
    if idx < 0 {
        return source_pos {
            line: 0, column 0,
        }
    }
    index_to_pos(source, idx)
}

func find_substring(string haystack, string needle) int {
    if needle == "" {
        return 0
    }
    if len(needle) > len(haystack) {
        return 0 - 1
    }
    i := 0
    for i + len(needle) <= len(haystack) {
        if slice(haystack, i, i + len(needle)) == needle {
            return i
        }
        i = i + 1
    }
    0 - 1
}

func index_to_pos(string source, int index) source_pos {
    line := 1
    column := 1
    i := 0
    for i < index {
        if char_at(source, i) == "\n" {
            line = line + 1
            column = 1
        } else {
            column = column + 1
        }
        i = i + 1
    }
    source_pos {
        line: line, column column,
    }
}

func starts_with(string text, string prefix) bool {
    if len(prefix) > len(text) {
        return false
    }
    slice(text, 0, len(prefix)) == prefix
}

func contains_token(string text, string token) bool {
    if token == "" {
        return true
    }
    index_of(text, token) >= 0
}

func find_char(string text, string needle) int {
    i := 0
    for i < len(text) {
        if char_at(text, i) == needle {
            return i
        }
        i = i + 1
    }
    0 - 1
}

func find_last_char(string text, string needle) int {
    i := len(text)
    for i > 0 {
        i = i - 1
        if char_at(text, i) == needle {
            return i
        }
    }
    0 - 1
}

func last_path_segment(string path) string {
    i := len(path)
    for i > 0 {
        i = i - 1
        if char_at(path, i) == "." {
            return slice(path, i + 1, len(path))
        }
    }
    path
}

func trim_text(string text) string {
    start := 0
    end := len(text)
    for start < end && is_space(char_at(text, start)) {
        start = start + 1
    }
    for end > start && is_space(char_at(text, end - 1)) {
        end = end - 1
    }
    slice(text, start, end)
}

func is_space(string ch) bool {
    ch == " " || ch == "\n" || ch == "\t" || ch == "\r"
}
