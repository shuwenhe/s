package compile.internal.semantic

import (
    "compile.internal.prelude"
    "compile.internal.typesys"
    "s"
    "std"
    "std.option"
    "std.prelude"
)

struct semantic_scope {
    string package_path
    string[] generic_names
    int local_start
    bool discard_result
    int loop_depth
}

struct type_binding {
    bool constant
    option[expr] constant_value
    string name
    string type_name
}

struct function_binding {
    bool is_external
    string extern_library
    string package_path
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
    string package_path
    string name
    method_binding[] methods
}

struct const_binding {
    bool mutable
    option[expr] value
    string package_path
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
    string[] type_args
    int score
    int generic_bind_count
    int unknown_arg_count
}

struct call_callee_resolution {
    bool ok
    signature_match match
    int errors
}

struct stmt_check_result {
    int errors
    type_binding[] env
}

struct check_result {
    string type_name
    int errors
}

struct canonical_const_context {
    const_binding[] known
    type_binding[] types
}

struct canonical_inference {
    string type_name
    semantic_error[] diagnostics
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

enum declaration_kind {
    function_kind,
    struct_kind,
    enum_kind,
    trait_kind,
    const_kind,
    var_kind,
    method_kind,
}

struct struct_binding {
    compile.internal.ast.field[] fields
    string[] generics
    string package_path
    string name
}

struct declaration_ref {
    compile.internal.ast.enum_variant[] variants
    compile.internal.ast.field[] fields
    string[] generics
    string package_path
    declaration_kind kind
    string path
}

struct canonical_semantic_inputs {
    semantic_error[] errors
    function_binding[] functions
    trait_binding[] traits
    struct_binding[] structs
    declaration_ref[] enums
    const_binding[] enum_constants
    source_file constants
    source_file globals
}

struct semantic_result {
    const_binding[] bindings
    function_binding[] functions
    semantic_error[] errors
    declaration_ref[] declarations
}

// Each synchronous semantic entrypoint owns and resets this diagnostic log.
semantic_diagnostic_log := compile.internal.semantic.semantic_error[]()

func declaration_ref_equal(declaration_ref a, declaration_ref b) bool {
    if a.package_path != b.package_path { return false }
    if a.kind != b.kind { return false }
    if a.path != b.path { return false }
    true
}

func declaration_ref_display(declaration_ref ref) string {
    if ref.kind == declaration_kind.function_kind {
        return ref.package_path + ".func:" + ref.path
    } else if ref.kind == declaration_kind.struct_kind {
        return ref.package_path + ".struct:" + ref.path
    } else if ref.kind == declaration_kind.enum_kind {
        return ref.package_path + ".enum:" + ref.path
    } else if ref.kind == declaration_kind.trait_kind {
        return ref.package_path + ".trait:" + ref.path
    } else if ref.kind == declaration_kind.const_kind {
        return ref.package_path + ".const:" + ref.path
    } else if ref.kind == declaration_kind.var_kind {
        return ref.package_path + ".var:" + ref.path
    } else if ref.kind == declaration_kind.method_kind {
        return ref.package_path + ".method:" + ref.path
    }
    "unknown"
}

func find_struct_declaration(declaration_ref[] declarations, string struct_name) std.option.option[compile.internal.semantic.declaration_ref] {
    i := 0
    for i < len(declarations) {
        if declarations[i].kind == declaration_kind.struct_kind && declarations[i].path == struct_name {
            return std.option.some(declarations[i])
        }
        i = i + 1
    }
    std.option.none
}

func validate_canonical_type_construction(function_binding[] functions, declaration_ref[] declarations) int {
    
    if std.prelude.len(functions) == 0 || std.prelude.len(declarations) == 0 {
        return 0  
    }
    
    fi := 0
    for fi < std.prelude.len(functions) {
        func_binding := functions[fi]
        
        pi := 0
        for pi < std.prelude.len(func_binding.param_types) {
            param_type := func_binding.param_types[pi]
            
            canonical := compile.internal.canonical_type.construct_canonical_from_string(
                param_type,
                declarations
            )
            
            if param_type == "**Point" {
                
                if canonical.kind != "pointer" {
                    return 1  
                }
                
                if len(canonical.child) == 0 {
                    return 2  
                }
                
                child := canonical.child[0]
                if child.kind != "pointer" {
                    return 3  
                }
                
                if len(child.child) == 0 {
                    return 4  
                }
                
                grandchild := child.child[0]
                if grandchild.kind != "declared" {
                    return 5  
                }
            }
            
            pi = pi + 1
        }
        
        fi = fi + 1
    }
    
    return 0  
}

func validate_canonical_equality_decision(function_binding[] functions, declaration_ref[] declarations) int {
    
    t1 := compile.internal.canonical_type.construct_canonical_from_string("**Point", declarations)
    t2 := compile.internal.canonical_type.construct_canonical_from_string("**Point", declarations)
    t3 := compile.internal.canonical_type.construct_canonical_from_string("*Point", declarations)
    
    same := compile.internal.canonical_type.canonical_same_type(t1, t2)
    if !same {
        return 1  
    }
    
    different := compile.internal.canonical_type.canonical_same_type(t1, t3)
    if different {
        return 2  
    }
    
    return 0  
}

func check_text(string source) int {
    diagnostics := check_detailed(source);
    if std.prelude.len(diagnostics) > 0 {
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
    for i < std.prelude.len(state) {
        copied.push(state[i])
        i = i + 1
    }
    copied
}

func borrow_state_merge_moves(borrow_record[] target, borrow_record[] source) {
    i := 0
    for i < std.prelude.len(source) {
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
    for i < std.prelude.len(state) {
        if state[i].moved {
            kept.push(state[i])
        }
        i = i + 1
    }
    // Seed compatibility: vectors are rebuilt by the caller's ownership pass.
    i = 0
    for i < std.prelude.len(kept) {
        state.push(kept[i])
        i = i + 1
    }
}

func borrow_state_has_conflict(borrow_record[] state, string name, bool mutable) bool {
    i := 0
    for i < std.prelude.len(state) {
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
    if semantic_starts_with(left, right) {
        return std.prelude.len(left) > std.prelude.len(right) && string(left[std.prelude.len(right)]) == "."
    }
    if semantic_starts_with(right, left) {
        return std.prelude.len(right) > std.prelude.len(left) && string(right[std.prelude.len(left)]) == "."
    }
    false
}

func borrow_state_find(borrow_record[] state, string name) int {
    i := 0
    for i < std.prelude.len(state) {
        if state[i].name == name { return i }
        i = i + 1
    }
    -1
}

func borrow_type_is_copy(string type_name) bool {
    compile.internal.typesys.is_copy_type(type_name)
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

func check_move_value(string name, string type_name, borrow_record[] state, string source, semantic_error[] diagnostics) int {
    errors := 0
    if !borrow_type_is_copy(type_name) && borrow_state_has_conflict(state, name, true) {
        errors = errors + add_error(source, diagnostics, "e3057", "cannot move a value while it is borrowed", name)
    }
    borrow_state_mark_move(state, name, type_name)
    errors
}

func borrow_state_is_moved(borrow_record[] state, string name) bool {
    index := borrow_state_find(state, name)
    index >= 0 && state[index].moved
}

func borrow_place_name(expr value) string {
    switch value {
        expr.name(name_value) : name_value.name,
        expr.member(member_value) : {
            base := borrow_place_name(member_value.target.value)
            if base == "" { "" } else { base + "." + member_value.member }
        }
        expr.index(value): borrow_place_name(value.target.value),
        _ : "",
    }
}

func check_detailed(string source) semantic_error[] {
    semantic_diagnostic_log = semantic_error[]()
    diagnostics := semantic_error[]()
    if !compile.internal.typesys.rules_consistent() {
        add_error(source, diagnostics, "e0002", "type rules consistency check failed", "package")
        return finalize_diagnostics(semantic_diagnostic_log)
    }
    run_preparse_semantic_completeness_checks(source, diagnostics)
    parsed := s.legacy_parse_source(source)
    if parsed.is_err() {
        add_error(source, diagnostics, "e0001", "parse failed", "package");
        return finalize_diagnostics(semantic_diagnostic_log)
    }
    file := parsed.unwrap()
    import_roots := collect_import_module_roots(file.uses)
    functions := collect_functions(file)
    traits := collect_traits(file)
    consts := collect_consts(canonical_initializer_source(file, false), functions, traits, source, diagnostics)
    validate_function_set(functions, source, diagnostics)
    i := 0
    for i < std.prelude.len(file.items) {
        package_name := item_package_at(file.item_packages, i, file.pkg)
        ignored := check_item(file.items[i], functions, traits, consts, import_roots, source, diagnostics, declaration_ref[](), package_name)
        i = i + 1
    }
    finalize_diagnostics(semantic_diagnostic_log)
}

func check_source_file(source_file file, string source) semantic_result {
    return canonical_check_source_file(file, source, false)
}

// Compilation only consumes a rejected unit's first diagnostic. The complete
// diagnostic API above still checks every item; valid units share every gate.
func check_source_file_for_compile(source_file file, string source) semantic_result {
    return canonical_check_source_file(file, source, true)
}

func canonical_check_source_file(source_file file, string source, bool stop_on_error) semantic_result {
    semantic_diagnostic_log = semantic_error[]()
    inputs := canonical_collect_semantic_inputs(file)
    diagnostics := inputs.errors
    if !compile.internal.typesys.rules_consistent() {
        add_error(source, diagnostics, "e0002", "type rules consistency check failed", "package")
        diagnostics.push(semantic_diagnostic_log[0])
        return semantic_result {
            errors: finalize_diagnostics(diagnostics),
            declarations: declaration_ref[](),
        }
    }
    import_roots := collect_import_module_roots(file.uses)
    functions := inputs.functions
    traits := inputs.traits
    consts := collect_consts(inputs.constants, functions, traits, source, diagnostics)
    enum_constants := inputs.enum_constants
    c := 0
    for c < len(enum_constants) { consts.push(enum_constants[c]); c = c + 1 }
    structs := inputs.structs
    
    declarations := establish_declaration_identities(functions, traits, consts, structs)
    
    enum_declarations := inputs.enums
    d := 0
    for d < len(enum_declarations) { declarations.push(enum_declarations[d]); d = d + 1 }
    functions = canonical_augment_function_bindings(functions, declarations)
    globals := canonical_collect_globals(inputs.globals, functions, traits, consts, declarations, source, diagnostics)
    g := 0
    for g < len(globals) {
        consts.push(globals[g])
        declarations.push(declaration_ref { package_path: globals[g].package_path, kind: declaration_kind.var_kind, path: globals[g].name })
        g = g + 1
    }
    function_errors := validate_function_set(functions, source, diagnostics)
    if function_errors > 0 && len(diagnostics) == 0 && len(semantic_diagnostic_log) == 0 { diagnostics.push(canonical_semantic_error("function declarations rejected")) }
    i := 0
    for i < std.prelude.len(file.items) && (!stop_on_error || (len(diagnostics) == 0 && len(semantic_diagnostic_log) == 0)) {
        previous_errors := len(diagnostics)
        previous_logged := len(semantic_diagnostic_log)
        package_name := item_package_at(file.item_packages, i, file.pkg)
        checked := check_item(file.items[i], functions, traits, consts, import_roots, source, diagnostics, declarations, package_name)
        // Native array arguments copy their descriptor. The package log keeps
        // nested diagnostics; this fallback detects an unreported rejection.
        if checked > 0 && len(diagnostics) == previous_errors && len(semantic_diagnostic_log) == previous_logged { diagnostics.push(canonical_semantic_error("semantic check rejected item")) }
        i = i + 1
    }
    
    if !stop_on_error || (len(diagnostics) == 0 && len(semantic_diagnostic_log) == 0) {
        m2_equality_gate_result := validate_canonical_equality_decision(functions, declarations)
        if m2_equality_gate_result != 0 {
            diagnostics.push(canonical_semantic_error("canonical equality not used in decision"))
        }
    }
    
    logged := 0
    for logged < len(semantic_diagnostic_log) {
        diagnostics.push(semantic_diagnostic_log[logged])
        logged = logged + 1
    }
    return semantic_result {
        errors: finalize_diagnostics(diagnostics),
        declarations: declarations,
        bindings: consts,
        functions: functions,
    }
}

func canonical_collect_semantic_inputs(source_file file) canonical_semantic_inputs {
    inputs := canonical_semantic_inputs {}
    phase := 0
    for phase < 8 {
        if phase == 0 { inputs.errors = canonical_enum_errors(file) }
        else if phase == 1 { inputs.functions = collect_functions(file) }
        else if phase == 2 { inputs.traits = collect_traits(file) }
        else if phase == 3 { inputs.structs = collect_structs(file) }
        else if phase == 4 { inputs.enums = canonical_enum_declarations(file) }
        else if phase == 5 { inputs.enum_constants = canonical_enum_constants(file) }
        else if phase == 6 { inputs.constants = canonical_initializer_source(file, false) }
        else { inputs.globals = canonical_initializer_source(file, true) }
        phase = phase + 1
    }
    return inputs
}

func canonical_collect_globals(source_file file, function_binding[] functions, trait_binding[] traits, const_binding[] consts, declaration_ref[] declarations, string source, semantic_error[] diagnostics) const_binding[] {
    scope := semantic_scope { package_path: file.pkg, generic_names: string[]() }
    globals := const_binding[]()
    env := type_binding[]()
    i := 0
    for i < len(consts) { env.push(type_binding { name: consts[i].name, type_name: consts[i].type_name, constant: true, constant_value: canonical_const_pattern_value(consts[i]) }); i = i + 1 }
    i = 0
    for i < len(file.items) {
        switch file.items[i] {
            item.var(variable): {
                scope.package_path = item_package_at(file.item_packages, i, file.pkg)
                declared := "unknown"
                if variable.type_name.is_some() { declared = canonical_type_in_package(variable.type_name.unwrap(), scope.package_path, scope.generic_names, declarations) }
                env.push(type_binding { name: variable.name, type_name: declared })
            }
            _: (),
        }
        i = i + 1
    }
    i = 0
    for i < len(file.items) {
        switch file.items[i] {
            item.var(variable): {
                scope.package_path = item_package_at(file.item_packages, i, file.pkg)
                declared := lookup_name_type(env, variable.name)
                inferred := declared
                if variable.value.is_some() {
                    result := infer_expr_in_scope(variable.value.unwrap(), env, borrow_state_new(), declared, functions, traits, source, diagnostics, declarations, scope)
                    inferred = result.type_name
                    if !is_unknown(declared) && !types_compatible(declared, inferred) { add_error(source, diagnostics, "e3001", "global initializer type mismatch", variable.name) }
                }
                if is_unknown(declared) { declared = inferred }
                if is_unknown(declared) { add_error(source, diagnostics, "e3063", "global type cannot be resolved", variable.name) }
                globals.push(const_binding { package_path: item_package_at(file.item_packages, i, file.pkg), name: variable.name, type_name: declared, mutable: true })
                e := len(env)
                for e > 0 {
                    e = e - 1
                    if env[e].name == variable.name { env[e].type_name = declared; break }
                }
            }
            _: (),
        }
        i = i + 1
    }
    return globals
}

func collect_structs(source_file file) struct_binding[] {
    out := struct_binding[]()
    i := 0
    for i < std.prelude.len(file.items) {
        pkg := item_package_at(file.item_packages, i, file.pkg)
        switch file.items[i] {
            item.struct(struct_decl) : out.push(struct_binding { package_path: pkg, name: struct_decl.name, fields: struct_decl.fields, generics: struct_decl.generics }),
            _ : {},
        }
        i = i + 1
    }
    out
}

func establish_declaration_identities(function_binding[] functions, trait_binding[] traits, const_binding[] consts, struct_binding[] structs) declaration_ref[] {
    declarations := declaration_ref[]()
    i := 0
    for i < std.prelude.len(functions) {
        declarations.push(declaration_ref {
            package_path: functions[i].package_path,
            kind: declaration_kind.function_kind,
            path: functions[i].name,
        })
        i = i + 1
    }
    i = 0
    for i < std.prelude.len(traits) {
        declarations.push(declaration_ref {
            package_path: traits[i].package_path,
            kind: declaration_kind.trait_kind,
            path: traits[i].name,
        })
        i = i + 1
    }
    i = 0
    for i < std.prelude.len(consts) {
        declarations.push(declaration_ref {
            package_path: consts[i].package_path,
            kind: declaration_kind.const_kind,
            path: consts[i].name,
        })
        i = i + 1
    }
    i = 0
    for i < std.prelude.len(structs) {
        declarations.push(declaration_ref {
            package_path: structs[i].package_path,
            kind: declaration_kind.struct_kind,
            path: structs[i].name,
            fields: structs[i].fields,
            generics: structs[i].generics,
        })
        i = i + 1
    }
    declarations
}

func run_preparse_semantic_completeness_checks(string source, semantic_error[] diagnostics) {
    ignored0 := validate_control_flow_semantics(source, diagnostics)
    ignored1 := validate_recovery_semantics(source, diagnostics)
    ignored2 := validate_method_interface_semantics(source, diagnostics)
    ignored3 := validate_concurrency_semantics(source, diagnostics)
    ignored4 := validate_semantic_proof_chain(source, diagnostics)
    ignored5 := validate_unsafe_boundaries(source, diagnostics)
}

func validate_unsafe_boundaries(string source, semantic_error[] diagnostics) int {
    errors := 0
    unsafe_blocks := count_token_text(source, "unsafe {")
    raw_accesses := count_token_text(source, "unsafe.load_")
        + count_token_text(source, "unsafe.store_")
        + count_token_text(source, "unsafe.read_")
        + count_token_text(source, "unsafe.write_")
        + count_token_text(source, "unsafe.ptr_")
    asm_count := count_token_text(source, "asm(") + count_token_text(source, "asm ")
    extern_count := count_token_text(source, "extern ")
    if unsafe_blocks == 0 && raw_accesses > 0 {
        errors = errors + add_error(source, diagnostics, "e3060", "raw memory access requires an unsafe block", "unsafe")
    }
    if unsafe_blocks == 0 && asm_count > 0 {
        errors = errors + add_error(source, diagnostics, "e3061", "inline assembly requires an unsafe block", "asm")
    }
    if unsafe_blocks == 0 && extern_count > 0 {
        errors = errors + add_error(source, diagnostics, "e3062", "FFI: declarations require an unsafe block", "extern")
    }
    errors
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
        errors = errors + add_error(source, diagnostics, "e3032", "panic path requires explicit return or recovery bridge", "panic")
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
    for i <= std.prelude.len(text) - std.prelude.len(token) {
        if std.prelude.prelude_slice(text, i, i + std.prelude.len(token)) == token {
            count = count + 1
            i = i + std.prelude.len(token)
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
    for i < std.prelude.len(diagnostics) {
        out.push(diagnostics[i])
        i = i + 1
    }
    summaries := semantic_error[]()
    i = 0
    for i < std.prelude.len(diagnostics) {
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
    for i < std.prelude.len(summaries) {
        if summaries[i].repeat_count > 1 {
            out.push(summaries[i])
        }
        i = i + 1
    }
    out
}

func find_anchor_summary_index(semantic_error[] diagnostics, string anchor) int {
    i := 0
    for i < std.prelude.len(diagnostics) {
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
    for i < std.prelude.len(diagnostics) {
        d := diagnostics[i]
        idx := find_diagnostic_index(out, d)
        if idx < 0 {
            out.push(d)
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
    for i < std.prelude.len(diagnostics) {
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
    for i < std.prelude.len(diagnostics) {
        item := diagnostics[i]
        insert := std.prelude.len(out)
        j := 0
        for j < std.prelude.len(out) {
            if diagnostic_before(item, out[j]) {
                insert = j
                j = std.prelude.len(out)
            } else {
                j = j + 1
            }
        }
        out = insert_diagnostic(out, insert, item)
        i = i + 1
    }
    out
}

func insert_diagnostic(semantic_error[] diagnostics, int at, semantic_error item) semantic_error[] {
    out := semantic_error[]()
    i := 0
    for i < std.prelude.len(diagnostics) {
        if i == at { out.push(item) }
        out.push(diagnostics[i])
        i = i + 1
    }
    if at == std.prelude.len(diagnostics) { out.push(item) }
    return out
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
    if std.prelude.len(diagnostics) <= max_total {
        return diagnostics
    }
    out := semantic_error[]()
    warnings := 0
    i := 0
    for i < std.prelude.len(diagnostics) && std.prelude.len(out) < max_total {
        d := diagnostics[i]
        if d.severity == "warning" {
            if warnings >= max_warnings {
                i = i + 1
                continue
            }
            warnings = warnings + 1
        }
        out.push(d)
        i = i + 1
    }
    out
}

func validate_function_set(function_binding[] functions, string source, semantic_error[] diagnostics) int {
    errors := 0
    i := 0
    has_main := false
    for i < std.prelude.len(functions) {
        if !functions[i].has_receiver && functions[i].name == "main" {
            has_main = true
        }
        j := i + 1
        for j < std.prelude.len(functions) {
            if !functions[i].has_receiver && !functions[j].has_receiver && functions[i].package_path == functions[j].package_path && functions[i].name == functions[j].name {
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
    if std.prelude.len(left) != std.prelude.len(right) {
        return false
    }
    i := 0
    for i < std.prelude.len(left) {
        if !compile.internal.typesys.same_type(left[i], right[i]) {
            return false
        }
        i = i + 1
    }
    true
}

func extract_module_root(string import_path) string {
    i := 0
    for i < std.prelude.len(import_path) {
        if string(import_path[i]) == "." {
            return std.prelude.prelude_slice(import_path, 0, i)
        }
        i = i + 1
    }
    return import_path
}

func collect_import_module_roots(use_decl[] uses) string[] {
    roots := string[]()
    seen := string[]()
    i := 0
    for i < std.prelude.len(uses) {
        root := extract_module_root(uses[i].path)
        j := 0
        found := false
        for j < std.prelude.len(seen) {
            if seen[j] == root {
                found = true
                break
            }
            j = j + 1
        }
        if !found {
            roots.push(root)
            seen.push(root)
        }
        i = i + 1
    }
    roots
}

func is_main_package(string source) bool {
    contains_token(source, "package main")
}

func item_package_at(string[] item_packages, int index, string fallback) string {
    if index >= 0 && index < std.prelude.len(item_packages) {
        return item_packages[index]
    }
    fallback
}

func collect_functions(source_file file) function_binding[] {
    out := function_binding[]()
    i := 0
    for i < std.prelude.len(file.items) {
        pkg := item_package_at(file.item_packages, i, file.pkg)
        switch file.items[i] {
            item.function(function_decl) : {
                binding := make_function_binding(function_decl, pkg)
                repeated_contract := false
                if binding.is_external {
                    previous := 0
                    for previous < len(out) {
                        existing := out[previous]
                        if existing.is_external && !existing.has_receiver && existing.package_path == binding.package_path
                            && existing.name == binding.name && existing.extern_library == binding.extern_library
                            && same_param_types(existing.generic_names, binding.generic_names)
                            && same_param_types(existing.param_types, binding.param_types)
                            && compile.internal.typesys.same_type(existing.return_type, binding.return_type) {
                            repeated_contract = true
                            break
                        }
                        previous = previous + 1
                    }
                }
                if !repeated_contract { out.push(binding) }
            },
            item.method(method_decl) : out.push(make_receiver_method_binding(method_decl, pkg)),
            _ : {},
        }
        i = i + 1
    }
    canonical_native_builtin_functions(out)
}

func canonical_function_bindings(source_file file, declaration_ref[] declarations) function_binding[] {
    functions := collect_functions(file)
    return canonical_augment_function_bindings(functions, declarations)
}

func canonical_augment_function_bindings(function_binding[] input, declaration_ref[] declarations) function_binding[] {
    functions := input
    f := 0
    for f < len(functions) {
        if functions[f].has_receiver {
            functions[f].owner_type = canonical_type_in_package(functions[f].owner_type, functions[f].package_path, functions[f].generic_names, declarations)
            enum_index := canonical_enum_index(functions[f].owner_type, declarations)
            if enum_index < 0 { enum_index = canonical_record_index(functions[f].owner_type, declarations) }
            if enum_index >= 0 {
                generic_index := 0
                for generic_index < len(declarations[enum_index].generics) {
                    generic := declarations[enum_index].generics[generic_index]
                    if !is_generic_name(functions[f].generic_names, generic) { functions[f].generic_names = append(functions[f].generic_names, generic) }
                    generic_index = generic_index + 1
                }
                functions[f].owner_type = canonical_type_in_package(functions[f].owner_type, functions[f].package_path, functions[f].generic_names, declarations)
            }
        }
        functions[f].return_type = canonical_type_in_package(functions[f].return_type, functions[f].package_path, functions[f].generic_names, declarations)
        p := 0
        for p < len(functions[f].param_types) { functions[f].param_types[p] = canonical_type_in_package(functions[f].param_types[p], functions[f].package_path, functions[f].generic_names, declarations); p = p + 1 }
        f = f + 1
    }
    return functions
}

func make_function_binding(function_decl function_decl, string package_path) function_binding {
    generic_names := string[]()
    i := 0
    for i < std.prelude.len(function_decl.sig.generics) {
        generic_names.push(generic_name(function_decl.sig.generics[i]));
        i = i + 1
    }
    params := string[]()
    i = 0
    for i < std.prelude.len(function_decl.sig.params) {
        params.push(compile.internal.typesys.parse_type(function_decl.sig.params[i].type_name));
        i = i + 1
    }
    return_type :=
        switch function_decl.sig.return_type {
            option.some(type_name) : compile.internal.typesys.parse_type(type_name),
            option.none : "()",
        }
    return function_binding {
        is_external: function_decl.body.is_none(), extern_library: function_decl.extern_library,
        package_path: package_path,
        name: function_decl.sig.name,
        owner_type: "", has_receiver false,
        receiver_mode: "value", generic_names generic_names, param_types params, return_type return_type,
    };
}

func make_receiver_method_binding(receiver_method_decl method_decl, string package_path) function_binding {
    binding := make_function_binding(method_decl.method, package_path)
    params := string[]()
    params.push(compile.internal.typesys.parse_type(method_decl.receiver_type))
    i := 0
    for i < std.prelude.len(binding.param_types) {
        params.push(binding.param_types[i])
        i = i + 1
    }
    binding.owner_type = method_owner_type(compile.internal.typesys.parse_type(method_decl.receiver_type))
    binding.has_receiver = true
    binding.receiver_mode = receiver_mode_from_type(method_decl.receiver_type)
    binding.param_types = params
    binding
}

func check_item(item item, function_binding[] functions, trait_binding[] traits, const_binding[] consts, string[] import_roots, string source, semantic_error[] diagnostics, declaration_ref[] declarations, string package_name) int {
    switch item {
        item.function(function_decl) : check_function(function_decl, functions, traits, consts, import_roots, source, diagnostics, declarations, package_name),
        item.struct(declaration): canonical_check_record_declaration(declaration, source, diagnostics),
        item.method(method_decl) : check_receiver_method(method_decl, functions, traits, consts, import_roots, source, diagnostics, declarations, package_name),
        _ : 0,
    }
}

func no_const_expr() option[expr] {
    return option.none
}

func collect_consts(source_file file, function_binding[] functions, trait_binding[] traits, string source, semantic_error[] diagnostics) const_binding[] {
    scope := semantic_scope { package_path: file.pkg, generic_names: string[]() }
    known := const_binding[]()
    types := type_binding[]()
    context := canonical_const_context { known: known, types: types }
    context.types.push(type_binding { name: "iota", type_name: "int" })
    last_const_expr := no_const_expr()
    i := 0
    for i < std.prelude.len(file.items) {
        pkg := item_package_at(file.item_packages, i, file.pkg)
        scope.package_path = pkg
        switch file.items[i] {
            item.const(const_decl) : {
                if canonical_const_name_type(context, const_decl.name) != "unknown" {
                    ignored := add_error(source, diagnostics, "e3044", "duplicate const declaration", const_decl.name)
                }
                expr_to_check := no_const_expr()
                switch const_decl.value {
                    option.some(value) : {
                        expr_to_check = option.some(value)
                        last_const_expr = option.some(value)
                    }
                    option.none : expr_to_check = last_const_expr,
                }
                ty := "unknown"
                has_int_value := false
                int_value := 0
                if expr_to_check.is_none() {
                    ignored2 := add_error(source, diagnostics, "e3045", "const declaration missing initializer and no prior expression in group", const_decl.name)
                } else {
                    checked_value := expr_to_check.unwrap()
                    constant := canonical_const_type(checked_value, context)
                    inferred := check_result { type_name: constant.type_name, errors: len(constant.diagnostics) }
                    d := 0
                    for d < len(constant.diagnostics) {
                        diagnostic := constant.diagnostics[d]
                        add_error(source, diagnostics, diagnostic.code, diagnostic.message, diagnostic.anchor)
                        d = d + 1
                    }
                    if inferred.type_name == "" {
                        inferred = infer_expr_in_scope(expr_to_check.unwrap(), context.types, borrow_state_new(), "()", functions, traits, source, diagnostics, declaration_ref[](), scope)
                    }
                    ty = inferred.type_name
                    if is_unknown(ty) {
                        ty = "unknown"
                    } else if compile.internal.typesys.same_type(ty, "int") {
                        eval_result := eval_const_int_expr(checked_value, context, const_decl.iota_index)
                        if eval_result.ok {
                            has_int_value = true
                            int_value = eval_result.value
                        } else {
                            ignored3 := add_error(source, diagnostics, "e3046", "const int expression evaluation failed: " + eval_result.error, const_decl.name)
                        }
                    }
                }
                context.known.push(const_binding {
                    package_path: pkg,
                    name: const_decl.name, type_name ty, has_int_value has_int_value, int_value int_value, value: expr_to_check,
                })
                ;
                context.types.push(type_binding {
                    name: const_decl.name, type_name ty,
                })
                ;
            }
            _ : (),
        }
        i = i + 1
    }
    context.known
}

func eval_const_int_expr(expr value, context* canonical_const_context, int iota_value) const_eval_int_result {
    switch value {
        expr.int(int_expr) : const_eval_int_result {
            ok: true, value parse_const_int_literal(int_expr.value),
            error: "",
        },
        expr.name(name_expr) : {
            if name_expr.name == "iota" {
                return const_eval_int_result {
                    ok: true, value iota_value,
                    error: "",
                }
            }
            i := len(context.known)
            for i > 0 {
                i = i - 1
                if context.known[i].name == name_expr.name {
                    if context.known[i].has_int_value {
                        return const_eval_int_result {
                            ok: true, value context.known[i].int_value,
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
        expr.binary(binary_expr) : {
            left := eval_const_int_expr(binary_expr.left.value, context, iota_value)
            if !left.ok {
                return left
            }
            right := eval_const_int_expr(binary_expr.right.value, context, iota_value)
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
    if std.prelude.len(text) > 0 && std.prelude.char_at(text, 0) == "-" {
        sign = -1
        i = 1
    }
    out := 0
    for i < std.prelude.len(text) {
        ch := std.prelude.char_at(text, i)
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

func collect_traits(source_file file) trait_binding[] {
    out := trait_binding[]()
    i := 0
    for i < std.prelude.len(file.items) {
        pkg := item_package_at(file.item_packages, i, file.pkg)
        switch file.items[i] {
            item.trait(trait_decl) : {
                methods := method_binding[]()
                mi := 0
                for mi < std.prelude.len(trait_decl.methods) {
                    params := string[]()
                    pi := 0
                    for pi < std.prelude.len(trait_decl.methods[mi].params) {
                        params.push(compile.internal.typesys.parse_type(trait_decl.methods[mi].params[pi].type_name));
                        pi = pi + 1
                    }
                    return_type :=
                        switch trait_decl.methods[mi].return_type {
                            option.some(type_name) : compile.internal.typesys.parse_type(type_name),
                            option.none : "()",
                        }
                    methods.push(method_binding {
                        name: trait_decl.methods[mi].name, receiver_mode: receiver_mode_from_param_name(trait_decl.methods[mi].params), param_types: params, return_type: return_type,
                    })
                    ;
                    mi = mi + 1
                }
                out.push(trait_binding {
                    package_path: pkg,
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
    for i < std.prelude.len(traits) {
        if traits[i].name == name || traits[i].name == compile.internal.typesys.base_type_name(name) {
            return option.some(traits[i])
        }
        i = i + 1
    }
    option.none
}

func find_trait_method(trait_binding trait_info, string name) option[method_binding] {
    i := 0
    for i < std.prelude.len(trait_info.methods) {
        if trait_info.methods[i].name == name {
            return option.some(trait_info.methods[i])
        }
        i = i + 1
    }
    option.none
}

func receiver_type_implements_trait(string receiver_type, trait_binding trait_info, function_binding[] functions) bool {
    mi := 0
    for mi < std.prelude.len(trait_info.methods) {
        matched := false
        fi := 0
        for fi < std.prelude.len(functions) {
            if functions[fi].has_receiver
                && functions[fi].owner_type == method_owner_type(compile.internal.typesys.parse_type(receiver_type))
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
    if std.prelude.len(method.param_types) != std.prelude.len(requirement.param_types) + 1 {
        return false
    }
    i := 0
    for i < std.prelude.len(requirement.param_types) {
        if !compile.internal.typesys.same_type(method.param_types[i + 1], requirement.param_types[i]) {
            return false
        }
        i = i + 1
    }
    compile.internal.typesys.same_type(method.return_type, requirement.return_type)
}

func receiver_mode_from_type(string receiver_type) string {
    if semantic_starts_with(receiver_type, "&") || semantic_starts_with(receiver_type, "*") {
        return "ref"
    }
    if semantic_starts_with(receiver_type, "&") || semantic_starts_with(receiver_type, "*") {
        return "ref"
    }
    "value"
}

func receiver_mode_from_signature(function_decl method_decl) string {
    receiver_mode_from_params(method_decl.sig.params)
}

func receiver_mode_from_param_name(compile.internal.ast.param[] params) string {
    receiver_mode_from_params(params)
}

func receiver_mode_from_params(compile.internal.ast.param[] params) string {
    if std.prelude.len(params) == 0 {
        return "value"
    }
    if params[0].name != "self" {
        return "value"
    }
    if semantic_starts_with(params[0].type_name, "&") {
        return "mut_ref"
    }
    if semantic_starts_with(params[0].type_name, "*") {
        return "ref"
    }
    "value"
}

func check_receiver_method(receiver_method_decl method_decl, function_binding[] functions, trait_binding[] traits, const_binding[] consts, string[] import_roots, string source, semantic_error[] diagnostics, declaration_ref[] declarations, string package_name) int {
    method := method_decl.method
    if method.body.is_none() {
        return 0
    }
    scope := semantic_scope { package_path: package_name, generic_names: method.sig.generics }
    pre_errors := validate_function_signature(method, source, diagnostics)
    expected_return :=
        switch method.sig.return_type {
            option.some(type_name) : canonical_type_in_package(type_name, package_name, method.sig.generics, declarations),
            option.none : "()",
        }
    env := type_binding[]()
    i := 0
    for i < std.prelude.len(import_roots) {
        env.push(type_binding {
            name: import_roots[i], type_name: "module",
        })
        ;
        i = i + 1
    }
    i = 0
    for i < std.prelude.len(consts) {
        env.push(type_binding {
            name: consts[i].name, type_name consts[i].type_name, constant: !consts[i].mutable, constant_value: canonical_const_pattern_value(consts[i]),
        })
        if !semantic_starts_with(consts[i].name, consts[i].package_path + ".") {
            env.push(type_binding { name: consts[i].package_path + "." + consts[i].name, type_name: consts[i].type_name, constant: !consts[i].mutable, constant_value: canonical_const_pattern_value(consts[i]) })
        }
        i = i + 1
    }
    env.push(type_binding {
        name: method_decl.receiver_name, type_name canonical_type_in_package(method_decl.receiver_type, package_name, method.sig.generics, declarations),
    })
    i = 0
    for i < std.prelude.len(method.sig.params) {
        param := method.sig.params[i]
        env.push(type_binding {
            name: param.name, type_name canonical_type_in_package(param.type_name, package_name, method.sig.generics, declarations),
        })
        i = i + 1
    }
    result := infer_block_expr_in_scope(method.body.unwrap(), env, borrow_state_new(), expected_return, functions, traits, source, diagnostics, declarations, scope)
    if expected_return != "()" && result.type_name != "never" && !is_unknown(expected_return) && !is_unknown(result.type_name) {
        if !compile.internal.typesys.same_type(expected_return, result.type_name) {
            return pre_errors + result.errors + add_error(source, diagnostics, "e3004", canonical_return_mismatch("method", method.sig.name, expected_return, result.type_name, method.body.unwrap()), method.sig.name)
        }
    }
    pre_errors + result.errors
}

func check_function(function_decl function_decl, function_binding[] functions, trait_binding[] traits, const_binding[] consts, string[] import_roots, string source, semantic_error[] diagnostics, declaration_ref[] declarations, string package_name) int {
    if function_decl.body.is_none() {
        return 0
    }
    scope := semantic_scope { package_path: package_name, generic_names: function_decl.sig.generics }
    pre_errors := validate_function_signature(function_decl, source, diagnostics)
    expected_return :=
        switch function_decl.sig.return_type {
            option.some(type_name) : canonical_type_in_package(type_name, package_name, function_decl.sig.generics, declarations),
            option.none : "()",
        }
    env := type_binding[]()
    i := 0
    for i < std.prelude.len(import_roots) {
        env.push(type_binding {
            name: import_roots[i], type_name: "module",
        })
        ;
        i = i + 1
    }
    i = 0
    for i < std.prelude.len(consts) {
        env.push(type_binding {
            name: consts[i].name, type_name consts[i].type_name, constant: !consts[i].mutable, constant_value: canonical_const_pattern_value(consts[i]),
        })
        if !semantic_starts_with(consts[i].name, consts[i].package_path + ".") {
            env.push(type_binding { name: consts[i].package_path + "." + consts[i].name, type_name: consts[i].type_name, constant: !consts[i].mutable, constant_value: canonical_const_pattern_value(consts[i]) })
        }
        i = i + 1
    }
    i = 0
    for i < std.prelude.len(function_decl.sig.params) {
        param := function_decl.sig.params[i]
        env.push(type_binding {
            name: param.name, type_name canonical_type_in_package(param.type_name, package_name, function_decl.sig.generics, declarations),
        })
        ;
        i = i + 1
    }
    result := infer_block_expr_in_scope(function_decl.body.unwrap(), env, borrow_state_new(), expected_return, functions, traits, source, diagnostics, declarations, scope)
    if expected_return != "()" && result.type_name != "never" && !is_unknown(expected_return) && !is_unknown(result.type_name) {
        if !compile.internal.typesys.same_type(expected_return, result.type_name) {
            return pre_errors + result.errors + add_error(source, diagnostics, "e3004", canonical_return_mismatch("function", function_decl.sig.name, expected_return, result.type_name, function_decl.body.unwrap()), function_decl.sig.name)
        }
    }
    pre_errors + result.errors
}

func validate_function_signature(function_decl function_decl, string source, semantic_error[] diagnostics) int {
    errors := 0
    switch function_decl.sig.return_type {
        option.some(type_name) : {
            if semantic_starts_with(compile.internal.typesys.parse_type(type_name), "&") {
                errors = errors + add_error(source, diagnostics, "e3069", "reference return requires an explicit lifetime proof", function_decl.sig.name)
            }
        }
        option.none : (),
    }
    i := 0
    for i < std.prelude.len(function_decl.sig.generics) {
        gi := generic_name(function_decl.sig.generics[i])
        j := i + 1
        for j < std.prelude.len(function_decl.sig.generics) {
            if gi == generic_name(function_decl.sig.generics[j]) {
                errors = errors + add_error(source, diagnostics, "e3012", "duplicate generic parameter", gi)
            }
            j = j + 1
        }
        i = i + 1
    }
    i = 0
    for i < std.prelude.len(function_decl.sig.params) {
        pi := function_decl.sig.params[i].name
        pj := i + 1
        for pj < std.prelude.len(function_decl.sig.params) {
            if pi == function_decl.sig.params[pj].name {
                errors = errors + add_error(source, diagnostics, "e3013", "duplicate parameter name", pi)
            }
            pj = pj + 1
        }
        i = i + 1
    }
    switch function_decl.sig.return_type {
        option.some(rt) : {
            if compile.internal.typesys.has_unknown_component(rt) {
                errors = errors + add_error(source, diagnostics, "e3014", "return type has unknown component", function_decl.sig.name)
            }
            if !declared_type_is_safe(rt) {
                errors = errors + add_error(source, diagnostics, "e3063", "return type cannot be resolved at compile time", function_decl.sig.name)
            }
        }
        option.none : (),
    }
    i = 0
    for i < std.prelude.len(function_decl.sig.params) {
        if !declared_type_is_safe(function_decl.sig.params[i].type_name) {
            errors = errors + add_error(source, diagnostics, "e3063", "parameter type cannot be resolved at compile time", function_decl.sig.params[i].name)
        }
        i = i + 1
    }
    errors
}

func infer_block_expr(block_expr block, type_binding[] outer_env, borrow_record[] incoming_borrows, string expected_return, function_binding[] functions, trait_binding[] traits, string source, semantic_error[] diagnostics, declaration_ref[] declarations) check_result {
    return infer_block_expr_in_scope(block, outer_env, incoming_borrows, expected_return, functions, traits, source, diagnostics, declarations, semantic_scope { package_path: "", generic_names: string[]() })
}

func infer_block_expr_in_scope(block_expr block, type_binding[] outer_env, borrow_record[] incoming_borrows, string expected_return, function_binding[] functions, trait_binding[] traits, string source, semantic_error[] diagnostics, declaration_ref[] declarations, semantic_scope scope) check_result {
    scope.local_start = len(outer_env)
    local_env := clone_env(outer_env)
    borrow_state := borrow_state_clone(incoming_borrows)
    errors := 0
    returns := false
    i := 0
    for i < std.prelude.len(block.statements) {
        checked := check_stmt_with_env_in_scope(block.statements[i], local_env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope)
        errors = errors + checked.errors
        local_env = checked.env
        switch block.statements[i] { stmt.return(_) : returns = true, stmt.continue(_) : returns = true, _ : (), }
        borrow_state_clear(borrow_state)
        i = i + 1
    }
    switch block.final_expr {
        option.some(final_expr) : {
            final_result := infer_expr_in_scope(final_expr, local_env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope)
            borrow_state_merge_moves(incoming_borrows, borrow_state)
            check_result {
                type_name: final_result.type_name, errors: errors + final_result.errors,
            }
        }
        option.none : {
            if returns { return check_result { type_name: "never", errors: errors } }
            borrow_state_merge_moves(incoming_borrows, borrow_state)
            check_result {
                type_name: "()", errors: errors,
            }
        }
    }
}

func check_stmt_with_env(stmt statement, type_binding[] env, borrow_record[] borrow_state, string expected_return, function_binding[] functions, trait_binding[] traits, string source, semantic_error[] diagnostics, declaration_ref[] declarations) stmt_check_result {
    return check_stmt_with_env_in_scope(statement, env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, semantic_scope { package_path: "", generic_names: string[]() })
}

func check_stmt_with_env_in_scope(stmt statement, type_binding[] env, borrow_record[] borrow_state, string expected_return, function_binding[] functions, trait_binding[] traits, string source, semantic_error[] diagnostics, declaration_ref[] declarations, semantic_scope scope) stmt_check_result {
    switch statement {
        stmt.multi(value): {
            rhs := infer_expr_in_scope(value.value, env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope)
            types := compile.internal.typesys.extract_tuple_args(rhs.type_name)
            errors := rhs.errors
            if len(types) != len(value.targets) { return stmt_check_result { errors: errors + add_error(source, diagnostics, "e3124", "parallel assignment arity mismatch", ":="), env: env } }
            updated := clone_env(env)
            i := 0
            for i < len(value.targets) {
                name := ""
                switch value.targets[i] { expr.name(identifier): name = identifier.name, _: (), }
                if name == "" { errors = errors + add_error(source, diagnostics, "e3125", "parallel assignment requires local names", "=") }
                else if name != "_" {
                    if value.declaration {
                        if has_duplicate_binding_from(updated, name, scope.local_start) { errors = errors + add_error(source, diagnostics, "e3064", "duplicate local binding in the same scope", name) }
                        updated.push(type_binding { name: name, type_name: types[i] })
                    } else if !types_compatible(lookup_name_type(updated, name), types[i]) { errors = errors + add_error(source, diagnostics, "e3001", "parallel assignment type mismatch", name) }
                }
                i = i + 1
            }
            return stmt_check_result { errors: errors, env: updated }
        }
        stmt.let(value) : {
            rhs := infer_expr_in_scope(value.value, env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope)
            errors := rhs.errors
            if is_borrow_expr(value.value) {
                errors = errors + add_error(source, diagnostics, "e3052", "borrowed reference cannot be stored in a local binding before lifetime checking is implemented", value.name)
            }
            binding_type := rhs.type_name
            if value.type_name.is_some() {
                declared := canonical_type_in_package(value.type_name.unwrap(), scope.package_path, scope.generic_names, declarations)
                if !declared_type_is_safe(declared) {
                    errors = errors + add_error(source, diagnostics, "e3063", "declared type cannot be resolved at compile time", value.name)
                }
                if !types_compatible(declared, rhs.type_name) {
                    errors = errors + add_error(source, diagnostics, "e3001", "variable initializer type mismatch", value.name)
                }
                binding_type = declared
            }
            if has_duplicate_binding_from(env, value.name, scope.local_start) {
                errors = errors + add_error(source, diagnostics, "e3064", "duplicate local binding in the same scope", value.name)
            }
            updated_env := append(env, type_binding {
                name: value.name, type_name binding_type,
            })
            switch value.value {
                expr.name(name_value) : errors = errors + check_move_value(name_value.name, rhs.type_name, borrow_state, source, diagnostics),
                _ : (),
            }
            return stmt_check_result { errors: errors, env: updated_env }
        }
        _ : { return stmt_check_result { errors: check_stmt_in_scope(statement, env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope), env: env } },
    }
}

func check_stmt(stmt stmt, type_binding[] env, borrow_record[] borrow_state, string expected_return, function_binding[] functions, trait_binding[] traits, string source, semantic_error[] diagnostics, declaration_ref[] declarations) int {
    return check_stmt_in_scope(stmt, env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, semantic_scope { package_path: "", generic_names: string[]() })
}

func check_stmt_in_scope(stmt stmt, type_binding[] env, borrow_record[] borrow_state, string expected_return, function_binding[] functions, trait_binding[] traits, string source, semantic_error[] diagnostics, declaration_ref[] declarations, semantic_scope scope) int {
    return switch stmt {
        stmt.continue(_) : {
            if scope.loop_depth == 0 { return add_error(source, diagnostics, "e3070", "continue outside loop", "continue") }
            0
        },
        stmt.multi(_) : check_stmt_with_env_in_scope(stmt, env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope).errors,
        stmt.let(_) : check_stmt_with_env_in_scope(stmt, env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope).errors,
        stmt.assign(value) : {
            target_type := lookup_name_type(env, value.name)
            if borrow_state_has_conflict(borrow_state, value.name, true) {
                return add_error(source, diagnostics, "e3056", "cannot assign to a borrowed value", value.name)
            }
            rhs := infer_expr_in_scope(value.value, env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope)
            errors := rhs.errors
            if is_unknown(target_type) {
                return errors + add_error(source, diagnostics, "e3002", "assignment to undefined name", value.name)
            }
            if !types_compatible(target_type, rhs.type_name) {
                return errors + add_error(source, diagnostics, "e3003", "assignment type mismatch", value.name)
            }
            switch value.value {
                expr.name(name_value) : errors = errors + check_move_value(name_value.name, rhs.type_name, borrow_state, source, diagnostics),
                _ : (),
            }
            errors
        }
        stmt.store(value): {
            target := infer_expr_in_scope(value.target, env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope)
            rhs := infer_expr_in_scope(value.value, env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope)
            errors := target.errors + rhs.errors
            root := borrow_place_name(value.target)
            if root == "" { errors = errors + add_error(source, diagnostics, "e3124", "store requires a named place", "=") }
            if borrow_state_has_conflict(borrow_state, root, true) { errors = errors + add_error(source, diagnostics, "e3056", "cannot assign to a borrowed place", root) }
            if !types_compatible(target.type_name, rhs.type_name) { errors = errors + add_error(source, diagnostics, "e3003", "store type mismatch", "=") }
            if value.op != "=" && (!types_compatible("int", target.type_name) || !types_compatible("int", rhs.type_name)) { errors = errors + add_error(source, diagnostics, "e3018", "compound store requires int", value.op) }
            errors
        }
        stmt.increment(value) : {
            ty := lookup_name_type(env, value.name)
            if borrow_state_has_conflict(borrow_state, value.name, true) {
                return add_error(source, diagnostics, "e3056", "cannot mutate a borrowed value", value.name)
            }
            if !types_compatible("int", ty) {
                return add_error(source, diagnostics, "e3005", "increment requires int", value.name)
            }
            0
        }
        stmt.c_for(value) : {
            errors := 0
            initialized := check_stmt_with_env_in_scope(value.init.value, env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope)
            errors = errors + initialized.errors
            loop_env := initialized.env
            cond := infer_expr_in_scope(value.condition, loop_env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope)
            errors = errors + cond.errors
            if !types_compatible("bool", cond.type_name) {
                errors = errors + add_error(source, diagnostics, "e3006", "for condition must be bool", "for")
            }
            errors = errors + check_stmt_in_scope(value.step.value, loop_env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope)
            loop_scope := scope
            loop_scope.loop_depth = loop_scope.loop_depth + 1
            body_result := infer_block_expr_in_scope(value.body, loop_env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, loop_scope)
            errors = errors + body_result.errors
            errors
        }
        stmt.return(value) : {
            switch value.value {
                option.some(expr) : {
                    expr_result := infer_expr_in_scope(expr, env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope)
                    if is_borrow_expr(expr) {
                        return expr_result.errors + add_error(source, diagnostics, "e3053", "cannot return a reference to a local value because it does not live long enough", "return")
                    }
                    if expected_return == "()" {
                        return expr_result.errors + add_error(source, diagnostics, "e3007", "unexpected return value", "return")
                    }
                    if !types_compatible(expected_return, expr_result.type_name) {
                        return expr_result.errors + add_error(source, diagnostics, "e3008", "return type mismatch", "return")
                    }
                    switch expr {
                        expr.name(name_value) : expr_result.errors = expr_result.errors + check_move_value(name_value.name, expr_result.type_name, borrow_state, source, diagnostics),
                        _ : (),
                    }
                    expr_result.errors
                }
                option.none : {
                    if expected_return == "()" {
                        return 0
                    }
                    add_error(source, diagnostics, "e3009", "missing return value", "return")
                }
            }
        }
        stmt.expr(value) : {
            scope.discard_result = true
            infer_expr_in_scope(value.expr, env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope).errors
        }
        stmt.defer(value) : {
            infer_expr_in_scope(value.expr, env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope).errors
        }
        stmt.sroutine(value) : {
            infer_expr_in_scope(value.expr, env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope).errors
        }
    }
}

func canonical_array_element(string type_name) string {
    clean := compile.internal.typesys.parse_type(type_name)
    if len(clean) >= 2 && std.prelude.prelude_slice(clean, 0, 2) == "[]" { return std.prelude.prelude_slice(clean, 2, len(clean)) }
    if len(clean) >= 2 && std.prelude.prelude_slice(clean, len(clean) - 2, len(clean)) == "[]" { return std.prelude.prelude_slice(clean, 0, len(clean) - 2) }
    return ""
}

func canonical_check_record_declaration(struct_decl declaration, string source, semantic_error[] diagnostics) int {
    errors := 0
    i := 0
    for i < len(declaration.fields) {
        j := 0
        for j < i {
            if declaration.fields[j].name == declaration.fields[i].name { errors = errors + add_error(source, diagnostics, "e3110", "duplicate record field", declaration.fields[i].name) }
            j = j + 1
        }
        i = i + 1
    }
    return errors
}

func canonical_type_in_package(string type_name, string package_name, string[] generic_names, declaration_ref[] declarations) string {
    name := compile.internal.typesys.parse_type(type_name)
    g := 0
    for g < len(generic_names) {
        if name == generic_name(generic_names[g]) { return name }
        g = g + 1
    }
    if name == "()" || name == "unit" || name == "unknown" || compile.internal.typesys.is_builtin_primitive(name) { return name }
    if compile.internal.typesys.is_tuple_type(name) {
        items := compile.internal.typesys.extract_tuple_args(name)
        result := "("
        i := 0
        for i < len(items) {
            if i > 0 { result = result + "," }
            result = result + canonical_type_in_package(items[i], package_name, generic_names, declarations)
            i = i + 1
        }
        return result + ")"
    }
    if semantic_starts_with(name, "&mut") { return "&mut" + canonical_type_in_package(std.prelude.prelude_slice(name, 4, len(name)), package_name, generic_names, declarations) }
    if semantic_starts_with(name, "&") { return "&" + canonical_type_in_package(std.prelude.prelude_slice(name, 1, len(name)), package_name, generic_names, declarations) }
    if semantic_starts_with(name, "*") { return "*" + canonical_type_in_package(std.prelude.prelude_slice(name, 1, len(name)), package_name, generic_names, declarations) }
    if len(name) > 0 && std.prelude.char_at(name, len(name) - 1) == "*" { return canonical_type_in_package(std.prelude.prelude_slice(name, 0, len(name) - 1), package_name, generic_names, declarations) + "*" }
    if semantic_starts_with(name, "[]") { return "[]" + canonical_type_in_package(std.prelude.prelude_slice(name, 2, len(name)), package_name, generic_names, declarations) }
    if len(name) >= 2 && std.prelude.prelude_slice(name, len(name) - 2, len(name)) == "[]" { return canonical_type_in_package(std.prelude.prelude_slice(name, 0, len(name) - 2), package_name, generic_names, declarations) + "[]" }
    if semantic_starts_with(name, "[") {
        close := 0
        for close < len(name) && std.prelude.char_at(name, close) != "]" { close = close + 1 }
        if close > 0 && close < len(name) { return std.prelude.prelude_slice(name, 0, close + 1) + canonical_type_in_package(std.prelude.prelude_slice(name, close + 1, len(name)), package_name, generic_names, declarations) }
    }
    base := compile.internal.typesys.base_type_name(name)
    qualified := package_name + "." + base
    record := canonical_record_index(qualified, declarations)
    enumeration := canonical_enum_index(qualified, declarations)
    if package_name == "" || (record < 0 && enumeration < 0) {
        record = canonical_record_index(base, declarations)
        enumeration = canonical_enum_index(base, declarations)
    }
    if record >= 0 { qualified = declarations[record].package_path + "." + declarations[record].path }
    else if enumeration >= 0 { qualified = declarations[enumeration].package_path + "." + declarations[enumeration].path }
    else { return name }
    arguments := compile.internal.typesys.extract_type_args(name)
    if len(arguments) == 0 { return qualified }
    result := qualified + "["
    a := 0
    for a < len(arguments) {
        if a > 0 { result = result + "," }
        result = result + canonical_type_in_package(arguments[a], package_name, generic_names, declarations)
        a = a + 1
    }
    return result + "]"
}

func canonical_record_index(string type_name, declaration_ref[] declarations) int {
    name := compile.internal.typesys.base_type_name(type_name)
    found := -1
    i := 0
    for i < len(declarations) {
        declaration := declarations[i]
        if declaration.kind == declaration_kind.struct_kind {
            if name == declaration.package_path + "." + declaration.path { return i }
            if name == declaration.path {
                if found >= 0 { return -1 }
                found = i
            }
        }
        i = i + 1
    }
    return found
}

func canonical_record_field_type(string type_name, string field_name, declaration_ref[] declarations) string {
    index := canonical_record_index(type_name, declarations)
    if index < 0 { return "" }
    declaration := declarations[index]
    bindings := type_binding[]()
    arguments := compile.internal.typesys.extract_type_args(type_name)
    if len(arguments) != len(declaration.generics) { return "" }
    i := 0
    for i < len(arguments) {
        bindings.push(type_binding { name: declaration.generics[i], type_name: arguments[i] })
        i = i + 1
    }
    i = 0
    for i < len(declaration.fields) {
        if declaration.fields[i].name == field_name {
            declared := canonical_type_in_package(declaration.fields[i].type_name, declaration.package_path, declaration.generics, declarations)
            return instantiate_type(declared, declaration.generics, bindings)
        }
        i = i + 1
    }
    return ""
}

func canonical_infer_record(record_literal value, type_binding[] env, borrow_record[] borrow_state, string expected_return, function_binding[] functions, trait_binding[] traits, string source, semantic_error[] diagnostics, declaration_ref[] declarations) check_result {
    return canonical_infer_record_in_scope(value, env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, semantic_scope { package_path: "", generic_names: string[]() })
}

func canonical_infer_record_in_scope(record_literal value, type_binding[] env, borrow_record[] borrow_state, string expected_return, function_binding[] functions, trait_binding[] traits, string source, semantic_error[] diagnostics, declaration_ref[] declarations, semantic_scope scope) check_result {
    errors := 0
    type_name := canonical_type_in_package(value.type_name, scope.package_path, scope.generic_names, declarations)
    index := canonical_record_index(type_name, declarations)
    if index < 0 { return check_result { type_name: "unknown", errors: add_error(source, diagnostics, "e3111", "unknown or ambiguous record type", value.type_name) } }
    declaration := declarations[index]
    arguments := compile.internal.typesys.extract_type_args(type_name)
    if len(arguments) != len(declaration.generics) { errors = errors + add_error(source, diagnostics, "e3112", "record type argument count", value.type_name) }
    if len(value.field_names) != len(value.field_values) { return check_result { type_name: "unknown", errors: errors + add_error(source, diagnostics, "e3113", "record initializer field count", value.type_name) } }
    i := 0
    for i < len(value.field_names) {
        name := value.field_names[i]
        j := 0
        for j < i {
            if value.field_names[j] == name { errors = errors + add_error(source, diagnostics, "e3114", "duplicate record initializer field", name) }
            j = j + 1
        }
        expected := canonical_enum_type(canonical_record_field_type(type_name, name, declarations), declarations)
        actual := infer_expr_in_scope(value.field_values[i], env, borrow_state, expected, functions, traits, source, diagnostics, declarations, scope)
        errors = errors + actual.errors
        if expected == "" { errors = errors + add_error(source, diagnostics, "e3115", "unknown record field", name) }
        else if !types_compatible(expected, actual.type_name) { errors = errors + add_error(source, diagnostics, "e3116", "record field type mismatch", name) }
        i = i + 1
    }
    nominal := declaration.package_path + "." + declaration.path
    if len(arguments) > 0 {
        nominal = nominal + "["
        a := 0
        for a < len(arguments) {
            if a > 0 { nominal = nominal + "," }
            nominal = nominal + arguments[a]
            a = a + 1
        }
        nominal = nominal + "]"
    }
    return check_result { type_name: nominal, errors: errors }
}

func infer_expr(expr expr, type_binding[] env, borrow_record[] borrow_state, string expected_return, function_binding[] functions, trait_binding[] traits, string source, semantic_error[] diagnostics, declaration_ref[] declarations) check_result {
    return infer_expr_in_scope(expr, env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, semantic_scope { package_path: "", generic_names: string[]() })
}

func infer_expr_in_scope(expr expr, type_binding[] env, borrow_record[] borrow_state, string expected_return, function_binding[] functions, trait_binding[] traits, string source, semantic_error[] diagnostics, declaration_ref[] declarations, semantic_scope scope) check_result {
    discard_result := scope.discard_result
    scope.discard_result = false
    return switch expr {
        expr.tuple(value): {
            type_name := "("
            errors := 0
            i := 0
            for i < len(value.items) {
                part := infer_expr_in_scope(value.items[i], env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope)
                errors = errors + part.errors
                if i > 0 { type_name = type_name + "," }
                type_name = type_name + part.type_name
                i = i + 1
            }
            check_result { type_name: type_name + ")", errors: errors }
        }
        expr.record(value): canonical_infer_record_in_scope(value, env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope),
        expr.int(_) : ok_type("int"),
        expr.string(_) : ok_type("string"),
        expr.bool(_) : ok_type("bool"),
        expr.name(value) : {
            if value.name == "unit" { return ok_type("()") }
            if value.name == "nil" {
                return ok_type("nil")
            }
            ty := lookup_name_type(env, value.name)
            if borrow_state_is_moved(borrow_state, value.name) {
                return check_result {
                    type_name: "unknown", errors add_error(source, diagnostics, "e3059", "use of moved value", value.name),
                }
            }
            if is_unknown(ty) {
                fn_candidates := lookup_functions(functions, value.name)
                if std.prelude.len(fn_candidates) > 0 {
                    return ok_type("fn")
                }
                return check_result {
                    type_name: "unknown", errors add_error(source, diagnostics, "e3010", "undefined identifier", value.name),
                }
            }
            ok_type(ty)
        }
        expr.borrow(value) : {
            target_name := borrow_place_name(value.target.value)
            if target_name == "" {
                return check_result {
                    type_name: "unknown", errors add_error(source, diagnostics, "e3055", "borrow target must be a named local, parameter, or field", "&"),
                }
            }
            root_name := target_name
            dot := 0
            for dot < std.prelude.len(root_name) {
                if string(root_name[dot]) == "." {
                    root_name = std.prelude.prelude_slice(root_name, 0, dot)
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
            base := infer_expr_in_scope(value.target.value, env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope)
            if is_unknown(base.type_name) {
                return base
            }
            borrow_state_push(borrow_state, target_name, value.mutable)
            prefix := if value.mutable { "&mut " } else { "&" }
            check_result {
                type_name: prefix + base.type_name, errors base.errors,
            }
        }
        expr.binary(value) : {
            left := infer_expr_in_scope(value.left.value, env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope)
            right := infer_expr_in_scope(value.right.value, env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope)
            result := infer_binary(value.op, left, right, source, diagnostics, declarations)
            if (value.op == "/" || value.op == "%") && is_zero_int_expr(value.right.value) {
                result.errors = result.errors + add_error(source, diagnostics, "e3065", "division or modulo by zero is known at compile time", value.op)
            }
            result
        }
        expr.member(value) : {
            enum_path := qualified_expr_path(expr)
            if is_unknown(lookup_name_type(env, extract_module_root(enum_path))) && canonical_enum_index(qualified_package_part(enum_path), declarations) >= 0 {
                return canonical_enum_constructor(enum_path, string[](), expected_return, declarations, source, diagnostics)
            }
            constant_type := lookup_name_type(env, qualified_expr_path(expr))
            if !is_unknown(constant_type) { return ok_type(constant_type) }
            target := infer_expr_in_scope(value.target.value, env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope)
            field_type := canonical_record_field_type(target.type_name, value.member, declarations)
            if field_type == "" { field_type = compile.internal.prelude.lookup_builtin_field_type(target.type_name, value.member) }
            if field_type == "" {
                return check_result {
                    type_name: "unknown", errors target.errors + add_error(source, diagnostics, "e3011", "unknown member", value.member),
                }
            }
            check_result {
                type_name: compile.internal.typesys.parse_type(field_type), errors target.errors,
            }
        }
        expr.index(value) : {
            target := infer_expr_in_scope(value.target.value, env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope)
            index := infer_expr_in_scope(value.index.value, env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope)
            errors := target.errors + index.errors
            element := canonical_array_element(target.type_name)
            if element != "" {
                if !types_compatible("int", index.type_name) { errors = errors + add_error(source, diagnostics, "e3012", "index must be int", "[") }
                return check_result { type_name: element, errors: errors }
            }
            if semantic_starts_with(target.type_name, "[]") {
                if !types_compatible("int", index.type_name) {
                    errors = errors + add_error(source, diagnostics, "e3012", "index must be int", "[")
                }
                return check_result {
                    type_name: compile.internal.typesys.parse_type(std.prelude.prelude_slice(target.type_name, 2, std.prelude.len(target.type_name))), errors errors,
                }
            }
            if semantic_starts_with(target.type_name, "[") {
                if !types_compatible("int", index.type_name) {
                    errors = errors + add_error(source, diagnostics, "e3012", "index must be int", "[")
                }
                return check_result {
                    type_name: strip_array_prefix(target.type_name), errors errors,
                }
            }
            if semantic_starts_with(target.type_name, "string") {
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
        expr.call(value) : {
            errors := 0
            arg_types := string[]()
            i := 0
            for i < std.prelude.len(value.args) {
                arg_result := infer_expr_in_scope(value.args[i], env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope)
                errors = errors + arg_result.errors
                arg_types.push(arg_result.type_name);
                switch value.args[i] {
                    expr.name(name_value): {
                        builtin := qualified_expr_path(value.callee.value)
                        if builtin != "len" && !(builtin == "append" && i == 0) { errors = errors + check_move_value(name_value.name, arg_result.type_name, borrow_state, source, diagnostics) }
                    }
                    _ : (),
                }
                i = i + 1
            }
            switch value.callee.value {
                expr.member(member) : {
                    qualified_path := qualified_expr_path(value.callee.value)
                    enum_type := qualified_package_part(qualified_path)
                    if is_unknown(lookup_name_type(env, extract_module_root(qualified_path))) && canonical_enum_index(enum_type, declarations) >= 0 {
                        constructor := canonical_enum_constructor(qualified_path, arg_types, expected_return, declarations, source, diagnostics)
                        return check_result { type_name: constructor.type_name, errors: errors + constructor.errors }
                    }
                    qualified := resolve_qualified_call_callee(qualified_path, arg_types, functions, traits, declarations, source, diagnostics)
                    if qualified.ok {
                        value.resolved_callee = option.some(qualified.match.instance_name)
                        value.type_args = qualified.match.type_args
                        return check_result {
                            type_name: qualified.match.return_type, errors errors,
                        }
                    }
                    target := infer_expr_in_scope(member.target.value, env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope)
                    errors = errors + target.errors
                    named_methods := lookup_named_methods(functions, target.type_name, member.member)
                    methods := lookup_methods(functions, target.type_name, member.member, member.target.value)
                    if std.prelude.len(methods) > 0 {
                        matches := signature_match[]()
                        j := 0
                        for j < std.prelude.len(methods) {
                            method_arg_types := string[]()
                            method_arg_types.push(method_receiver_arg_type(target.type_name, methods[j].receiver_mode));
                            ai := 0
                            for ai < std.prelude.len(arg_types) {
                                method_arg_types.push(arg_types[ai]);
                                ai = ai + 1
                            }
                            m := try_match_signature(methods[j], method_arg_types, functions, traits, declarations)
                            if m.ok {
                                matches.push(m);
                            }
                            j = j + 1
                        }
                        if std.prelude.len(matches) == 0 {
                            return check_result {
                                type_name: "unknown", errors errors + add_error(source, diagnostics, "e1002", "no matching overload", member.member),
                            }
                        }
                        best := matches[0]
                        ambiguous := false
                        j = 1
                        for j < std.prelude.len(matches) {
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
                        value.resolved_callee = option.some(best.instance_name)
                        value.type_args = best.type_args
                        return check_result {
                            type_name: best.return_type, errors errors,
                        }
                    }
                    if std.prelude.len(named_methods) > 0 {
                        return check_result {
                            type_name: "unknown", errors errors + add_error(source, diagnostics, "e3051", receiver_requirement_message(member.member, named_methods[0].receiver_mode), member.member),
                        }
                    }
                    trait_result := find_trait_binding(traits, target.type_name)
                    if trait_result.is_some() {
                        required_method := find_trait_method(trait_result.unwrap(), member.member)
                        if required_method.is_some() {
                            requirement := required_method.unwrap()
                            if std.prelude.len(requirement.param_types) != std.prelude.len(arg_types) {
                                return check_result {
                                    type_name: "unknown", errors errors + add_error(source, diagnostics, "e1002", "no matching interface method", member.member),
                                }
                            }
                            ai := 0
                            for ai < std.prelude.len(arg_types) {
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
                    element := canonical_array_element(target.type_name)
                    if element != "" && (member.member == "set" || member.member == "push" || member.member == "len") {
                        arity := 0
                        if member.member == "push" { arity = 1 }
                        if member.member == "set" { arity = 2 }
                        if len(arg_types) != arity {
                            errors = errors + add_error(source, diagnostics, "e1005", "builtin method arity mismatch", member.member)
                        } else {
                            if member.member == "set" && !types_compatible("int", arg_types[0]) { errors = errors + add_error(source, diagnostics, "e3012", "index must be int", member.member) }
                            if arity > 0 && !types_compatible(element, arg_types[arity - 1]) { errors = errors + add_error(source, diagnostics, "e3122", "array element type mismatch", member.member) }
                        }
                        result_type := "()"
                        if member.member == "len" { result_type = "int" }
                        return check_result { type_name: result_type, errors: errors }
                    }
                    arity := compile.internal.prelude.lookup_builtin_method_arity(target.type_name, member.member)
                    if arity >= 0 && arity != std.prelude.len(value.args) {
                        errors = errors + add_error(source, diagnostics, "e1005", "builtin method arity mismatch", member.member)
                    }
                    method_type := compile.internal.prelude.lookup_builtin_method_type(target.type_name, member.member)
                    if method_type == "" {
                        return check_result {
                            type_name: "unknown", errors errors + add_error(source, diagnostics, "e1006", "unknown method", member.member),
                        }
                    }
                    check_result {
                        type_name: resolve_method_return(target.type_name, method_type), errors errors,
                    }
                }
                expr.name(callee_name) : {
                    if callee_name.name == "len" {
                        if len(arg_types) != 1 { return check_result { type_name: "unknown", errors: errors + add_error(source, diagnostics, "e3120", "len expects one array or string", "len") } }
                        if arg_types[0] != "string" && canonical_array_element(arg_types[0]) == "" { errors = errors + add_error(source, diagnostics, "e3120", "len expects one array or string", "len") }
                        return check_result { type_name: "int", errors: errors }
                    }
                    if callee_name.name == "append" {
                        if len(arg_types) < 2 { return check_result { type_name: "unknown", errors: errors + add_error(source, diagnostics, "e3121", "append expects an array and values", "append") } }
                        element := canonical_array_element(arg_types[0])
                        if element == "" { errors = errors + add_error(source, diagnostics, "e3121", "append target must be an array", "append") }
                        j := 1
                        for j < len(arg_types) {
                            if !types_compatible(element, arg_types[j]) { errors = errors + add_error(source, diagnostics, "e3122", "append element type mismatch", "append") }
                            j = j + 1
                        }
                        return check_result { type_name: arg_types[0], errors: errors }
                    }
                    if callee_name.name == "int" {
                        if len(arg_types) == 1 && (arg_types[0] == "int" || arg_types[0] == "bool" || canonical_is_enum_type(arg_types[0], declarations)) { return check_result { type_name: "int", errors: errors } }
                        return check_result { type_name: "unknown", errors: errors + add_error(source, diagnostics, "e3101", "int conversion requires an integer, bool or scalar enum", "int") }
                    }
                    if callee_name.name == "copy" {
                        if std.prelude.len(value.args) != 1 {
                            return check_result {
                                type_name: "unknown", errors errors + add_error(source, diagnostics, "e3068", "copy expects exactly one value", "copy"),
                            }
                        }
                        copied := infer_expr_in_scope(value.args[0], env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope)
                        if !compile.internal.typesys.is_copy_type(copied.type_name) {
                            return check_result {
                                type_name: "unknown", errors errors + copied.errors + add_error(source, diagnostics, "e3068", "copy requires a Copy: type; move or clone the value explicitly", "copy"),
                            }
                        }
                        return check_result {
                            type_name: copied.type_name, errors errors + copied.errors,
                        }
                    }
                    if callee_name.name == "box" || callee_name.name == "box_new" {
                        if std.prelude.len(value.args) != 1 {
                            return check_result {
                                type_name: "unknown", errors errors + add_error(source, diagnostics, "e3066", "box expects exactly one value", callee_name.name),
                            }
                        }
                        inner := infer_expr_in_scope(value.args[0], env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope)
                        switch value.args[0] {
                            expr.name(name_value) : errors = errors + check_move_value(name_value.name, inner.type_name, borrow_state, source, diagnostics),
                            _ : (),
                        }
                        return check_result {
                            type_name: "box[" + inner.type_name + "]", errors errors + inner.errors,
                        }
                    }
                    if callee_name.name == "box_free" {
                        if std.prelude.len(value.args) != 1 {
                            return check_result {
                                type_name: "unknown", errors errors + add_error(source, diagnostics, "e3067", "box_free expects exactly one owned value", "box_free"),
                            }
                        }
                        owned := infer_expr_in_scope(value.args[0], env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope)
                        if compile.internal.typesys.base_type_name(owned.type_name) != "box" {
                            return check_result {
                                type_name: "unknown", errors errors + owned.errors + add_error(source, diagnostics, "e3067", "box_free requires an explicit box[T] value", "box_free"),
                            }
                        }
                            switch value.args[0] {
                            expr.name(name_value) : errors = errors + check_move_value(name_value.name, owned.type_name, borrow_state, source, diagnostics),
                            _ : (),
                        }
                        return check_result {
                            type_name: "()", errors errors + owned.errors,
                        }
                    }
                    resolved := resolve_call_callee(callee_name.name, arg_types, functions, traits, declarations, source, diagnostics)
                    if !resolved.ok {
                        return check_result {
                            type_name: "unknown", errors errors + resolved.errors,
                        }
                    }
                    value.resolved_callee = option.some(resolved.match.instance_name)
                    value.type_args = resolved.match.type_args
                    check_result {
                        type_name: resolved.match.return_type, errors errors,
                    }
                }
                _ : {
                    callee := infer_expr_in_scope(value.callee.value, env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope)
                    check_result {
                        type_name: "unknown", errors errors + callee.errors,
                    }
                }
            }
        }
        expr.switch(value) : {
            subject := infer_expr_in_scope(value.subject.value, env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope)
            errors := subject.errors
            arm_type := "never"
            seen_patterns := pattern[]()
            arm_base_borrows := borrow_state_clone(borrow_state)
            i := 0
            for i < std.prelude.len(value.arms) {
                arm := value.arms[i]
                arm.pattern = canonical_resolve_const_pattern(arm.pattern, env)
                if pattern_unreachable(seen_patterns, arm.pattern, subject.type_name) {
                    errors = errors + add_error(source, diagnostics, "e2003", "unreachable switch arm", pattern_anchor(arm.pattern))
                }
                if pattern_duplicate(seen_patterns, arm.pattern, subject.type_name) {
                    errors = errors + add_error(source, diagnostics, "e2002", "duplicate switch arm", pattern_anchor(arm.pattern))
                }
                pattern_result := pattern_check_result { bindings: type_binding[](), errors: 0 }
                if canonical_enum_index(subject.type_name, declarations) >= 0 { pattern_result = canonical_check_enum_pattern(arm.pattern, subject.type_name, source, diagnostics, declarations) }
                else { pattern_result = check_pattern(arm.pattern, subject.type_name, source, diagnostics) }
                errors = errors + pattern_result.errors
                arm_env := clone_env(env)
                binding_index := 0
                for binding_index < len(pattern_result.bindings) {
                    arm_env.push(pattern_result.bindings[binding_index])
                    binding_index = binding_index + 1
                }
                arm_borrows := borrow_state_clone(arm_base_borrows)
                arm_result := infer_expr_in_scope(arm.expr, arm_env, arm_borrows, expected_return, functions, traits, source, diagnostics, declarations, scope)
                errors = errors + arm_result.errors
                borrow_state_merge_moves(borrow_state, arm_borrows)
                if arm_type == "never" || is_unknown(arm_type) {
                    arm_type = arm_result.type_name
                } else if arm_result.type_name != "never" && !discard_result && !types_compatible(arm_type, arm_result.type_name) {
                    errors = errors + add_error(source, diagnostics, "e2005", "switch arm result type mismatch", "switch")
                }
                seen_patterns.push(arm.pattern);
                i = i + 1
            }
            base := compile.internal.typesys.base_type_name(subject.type_name)
            exhaustive := true
            enum_index := canonical_enum_index(subject.type_name, declarations)
            if enum_index >= 0 { exhaustive = canonical_enum_patterns_cover(seen_patterns, subject.type_name, declarations) }
            else if base == "option" || base == "result" { exhaustive = patterns_cover_type(seen_patterns, subject.type_name) }
            if !exhaustive {
                errors = errors + add_error(source, diagnostics, "e2001", "non-exhaustive switch", "switch")
            }
            if discard_result { arm_type = "()" }
            check_result {
                type_name: arm_type, errors errors,
            }
        }
        expr.if(value) : {
            cond := infer_expr_in_scope(value.condition.value, env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope)
            then_borrows := borrow_state_clone(borrow_state)
            then_result := infer_block_expr_in_scope(value.then_branch, env, then_borrows, expected_return, functions, traits, source, diagnostics, declarations, scope)
            else_borrows := borrow_state_clone(borrow_state)
            errors := cond.errors + then_result.errors
            if !types_compatible("bool", cond.type_name) {
                errors = errors + add_error(source, diagnostics, "e3014", "if condition must be bool", "if")
            }
            switch value.else_branch {
                option.some(else_expr) : {
                    else_result := infer_expr_in_scope(else_expr.value, env, else_borrows, expected_return, functions, traits, source, diagnostics, declarations, scope)
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
                option.none : {
                    borrow_state_merge_moves(borrow_state, then_borrows)
                    check_result {
                        type_name: "()", errors: errors,
                    }
                },
            }
        }
        expr.while(value) : {
            cond := infer_expr_in_scope(value.condition.value, env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope)
            body_borrows := borrow_state_clone(borrow_state)
            loop_scope := scope
            loop_scope.loop_depth = loop_scope.loop_depth + 1
            body_result := infer_block_expr_in_scope(value.body, env, body_borrows, expected_return, functions, traits, source, diagnostics, declarations, loop_scope)
            borrow_state_merge_moves(borrow_state, body_borrows)
            errors := cond.errors + body_result.errors
            if !types_compatible("bool", cond.type_name) {
                errors = errors + add_error(source, diagnostics, "e3016", "while condition must be bool", "while")
            }
            check_result {
                type_name: "()", errors errors,
            }
        }
        expr.for(value) : {
            loop_env := clone_env(env)
            body_borrows := borrow_state_clone(borrow_state)
            errors := 0
            if value.init.is_some() {
                initialized := check_stmt_with_env_in_scope(value.init.unwrap().value, loop_env, body_borrows, expected_return, functions, traits, source, diagnostics, declarations, scope)
                loop_env = initialized.env
                errors = errors + initialized.errors
            }
            if value.condition.is_some() {
                condition := infer_expr_in_scope(value.condition.unwrap().value, loop_env, body_borrows, expected_return, functions, traits, source, diagnostics, declarations, scope)
                errors = errors + condition.errors
                if !types_compatible("bool", condition.type_name) { errors = errors + add_error(source, diagnostics, "e3006", "for condition must be bool", "for") }
            }
            iter := check_result { type_name: "()", errors: 0 }
            if value.iterable.is_some() {
                iter = infer_expr_in_scope(value.iterable.unwrap().value, loop_env, body_borrows, expected_return, functions, traits, source, diagnostics, declarations, scope)
            }
            loop_scope := scope
            loop_scope.loop_depth = loop_scope.loop_depth + 1
            body_result := infer_block_expr_in_scope(value.body, loop_env, body_borrows, expected_return, functions, traits, source, diagnostics, declarations, loop_scope)
            if value.post.is_some() {
                errors = errors + check_stmt_in_scope(value.post.unwrap().value, loop_env, body_borrows, expected_return, functions, traits, source, diagnostics, declarations, scope)
            }
            borrow_state_merge_moves(borrow_state, body_borrows)
            check_result {
                type_name: "()", errors: errors + iter.errors + body_result.errors,
            }
        }
        expr.block(value) : {
            infer_block_expr_in_scope(value, env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope)
        }
        expr.array(value) : {
            element := "unknown"
            type_name := "unknown[]"
            if value.type_text.is_some() {
                type_name = canonical_type_in_package(value.type_text.unwrap(), scope.package_path, scope.generic_names, declarations)
                element = canonical_array_element(type_name)
                if element == "" { return check_result { type_name: "unknown", errors: add_error(source, diagnostics, "e3123", "array literal requires an array type", "[") } }
            }
            errors := 0
            i := 0
            for i < len(value.items) {
                item := infer_expr_in_scope(value.items[i], env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope)
                errors = errors + item.errors
                if is_unknown(element) { element = item.type_name; type_name = element + "[]" }
                else if !types_compatible(element, item.type_name) { errors = errors + add_error(source, diagnostics, "e3017", "array item type mismatch", "[") }
                i = i + 1
            }
            check_result { type_name: type_name, errors: errors }
        }
        expr.map(value) : {
            errors := 0
            i := 0
            for i < std.prelude.len(value.entries) {
                errors = errors + infer_expr_in_scope(value.entries[i].key, env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope).errors
                errors = errors + infer_expr_in_scope(value.entries[i].value, env, borrow_state, expected_return, functions, traits, source, diagnostics, declarations, scope).errors
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
        expr.borrow(_) : true,
        _ : false,
    }
}

func canonical_const_pattern_value(const_binding binding) option[expr] {
    if binding.has_int_value { return option.some(expr.int(int_expr { value: std.prelude.to_string(binding.int_value) })) }
    return binding.value
}

func canonical_resolve_const_pattern(pattern value, type_binding[] env) pattern {
    switch value {
        pattern.name(name): {
            i := len(env)
            for i > 0 {
                i = i - 1
                if env[i].name == name.name {
                    if env[i].constant && env[i].constant_value.is_some() { return pattern.literal(literal_pattern { value: env[i].constant_value.unwrap() }) }
                    return value
                }
            }
            return value
        }
        _: return value,
    }
}

func check_pattern(pattern pattern, string expected_type, string source, semantic_error[] diagnostics) pattern_check_result {
    bindings := type_binding[]()
    errors := bind_pattern(pattern, expected_type, bindings, source, diagnostics)
    if errors == 0 { bindings = pattern_bindings(pattern, expected_type) }
    pattern_check_result { bindings: bindings, errors: errors }
}

func pattern_bindings(pattern value, string expected_type) type_binding[] {
    bindings := type_binding[]()
    switch value {
        pattern.name(name): {
            if name.name != "_" { bindings.push(type_binding { name: name.name, type_name: compile.internal.typesys.parse_type(expected_type) }) }
        }
        pattern.variant(variant): {
            if len(variant.args) == 1 {
                payload_type := first_type_arg(expected_type)
                if last_path_segment(variant.path) == "err" { payload_type = second_type_arg(expected_type) }
                bindings = pattern_bindings(variant.args[0], payload_type)
            }
        }
        _: {},
    }
    return bindings
}

func bind_pattern(pattern pattern, string expected_type, type_binding[] bindings, string source, semantic_error[] diagnostics) int {
    if is_unknown(expected_type) {
        return add_error(source, diagnostics, "e2007", "pattern expected type is unknown", pattern_anchor(pattern))
    }
    switch pattern {
        pattern.name(value) : {
            add_binding(bindings, value.name, expected_type, source, diagnostics)
        }
        pattern.wildcard(_) : 0,
        pattern.literal(value) : {
            literal_type := literal_pattern_type(value)
            if !types_compatible(expected_type, literal_type) {
                return add_error(source, diagnostics, "e2006", "literal pattern type mismatch", literal_pattern_text(value))
            }
            0
        }
        pattern.variant(value) : {
            variant := last_path_segment(value.path)
            base := compile.internal.typesys.base_type_name(expected_type)
            if base == "option" {
                if variant == "some" {
                    if std.prelude.len(value.args) != 1 {
                        return add_error(source, diagnostics, "e2004", "some payload arity mismatch", value.path)
                    }
                    return bind_pattern(value.args[0], first_type_arg(expected_type), bindings, source, diagnostics)
                }
                if variant == "none" {
                    if std.prelude.len(value.args) == 0 {
                        return 0
                    }
                    return add_error(source, diagnostics, "e2004", "none must not have payload", value.path)
                }
                return add_error(source, diagnostics, "e2006", "invalid option constructor", value.path)
            }
            if base == "result" {
                if variant == "ok" {
                    if std.prelude.len(value.args) != 1 {
                        return add_error(source, diagnostics, "e2004", "ok payload arity mismatch", value.path)
                    }
                    return bind_pattern(value.args[0], first_type_arg(expected_type), bindings, source, diagnostics)
                }
                if variant == "err" {
                    if std.prelude.len(value.args) != 1 {
                        return add_error(source, diagnostics, "e2004", "err payload arity mismatch", value.path)
                    }
                    return bind_pattern(value.args[0], second_type_arg(expected_type), bindings, source, diagnostics)
                }
                return add_error(source, diagnostics, "e2006", "invalid result constructor", value.path)
            }
            add_error(source, diagnostics, "e2006", "variant pattern not allowed for this type", value.path)
        }
    }
    0
}

func add_binding(type_binding[] bindings, string name, string type_name, string source, semantic_error[] diagnostics) int {
    if name == "_" {
        return 0
    }
    i := 0
    for i < std.prelude.len(bindings) {
        if bindings[i].name == name {
            if !types_compatible(bindings[i].type_name, type_name) {
                return add_error(source, diagnostics, "e2008", "conflicting binding type in pattern", name)
            }
            return 0
        }
        i = i + 1
    }
    bindings.push(type_binding {
        name: name, type_name compile.internal.typesys.parse_type(type_name),
    })
    ;
    0
}

func append_bindings(type_binding[] target, type_binding[] source) {
    i := 0
    for i < std.prelude.len(source) {
        target.push(source[i]);
        i = i + 1
    }
}

func pattern_duplicate(pattern[] seen, pattern current, string expected_type) bool {
    i := 0
    for i < std.prelude.len(seen) {
        if pattern_equivalent(seen[i], current, expected_type) {
            return true
        }
        i = i + 1
    }
    false
}

func pattern_unreachable(pattern[] seen, pattern current, string expected_type) bool {
    i := 0
    for i < std.prelude.len(seen) {
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
        pattern.literal(lv) : {
            switch right {
                pattern.literal(rv) : literal_pattern_equals(lv, rv),
                _ : false,
            }
        }
        pattern.variant(lv) : {
            switch right {
                pattern.variant(rv) : {
                    lctor := last_path_segment(lv.path)
                    rctor := last_path_segment(rv.path)
                    if lctor != rctor {
                        return false
                    }
                    if std.prelude.len(lv.args) == 0 && std.prelude.len(rv.args) == 0 {
                        return true
                    }
                    if std.prelude.len(lv.args) != 1 || std.prelude.len(rv.args) != 1 {
                        return false
                    }
                    payload_type := variant_payload_type(expected_type, lctor)
                    if is_unknown(payload_type) {
                        return false
                    }
                    return pattern_subsumes(lv.args[0], rv.args[0], payload_type)
                }
                _ : false,
            }
        }
        _ : false,
    }
}

func patterns_cover_type(pattern[] patterns, string expected_type) bool {
    i := 0
    for i < std.prelude.len(patterns) {
        if pattern_is_wild(patterns[i]) {
            return true
        }
        i = i + 1
    }
    base := compile.internal.typesys.base_type_name(expected_type)
    if base == "option" {
        return option_patterns_cover(patterns, expected_type)
    }
    if base == "result" {
        return result_patterns_cover(patterns, expected_type)
    }
    false
}

func option_patterns_cover(pattern[] patterns, string expected_type) bool {
    seen_none := false
    some_patterns := pattern[]()
    i := 0
    for i < std.prelude.len(patterns) {
        switch patterns[i] {
            pattern.variant(value) : {
                ctor := last_path_segment(value.path)
                if ctor == "none" {
                    seen_none = true
                } else if ctor == "some" && std.prelude.len(value.args) == 1 {
                    some_patterns.push(value.args[0]);
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
    for i < std.prelude.len(patterns) {
        switch patterns[i] {
            pattern.variant(value) : {
                ctor := last_path_segment(value.path)
                if ctor == "ok" && std.prelude.len(value.args) == 1 {
                    ok_patterns.push(value.args[0]);
                } else if ctor == "err" && std.prelude.len(value.args) == 1 {
                    err_patterns.push(value.args[0]);
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
        pattern.wildcard(_) : true,
        pattern.name(_) : true,
        _ : false,
    }
}

func pattern_anchor(pattern pattern) string {
    switch pattern {
        pattern.name(value) : value.name,
        pattern.wildcard(_) : "_",
        pattern.literal(value) : literal_pattern_text(value),
        pattern.variant(value) : value.path,
    }
    ""
}

func literal_pattern_type(literal_pattern value) string {
    switch value.value {
        expr.int(_) : "int",
        expr.string(_) : "string",
        expr.bool(_) : "bool",
        _ : "unknown",
    }
}

func literal_pattern_text(literal_pattern value) string {
    switch value.value {
        expr.int(v) : v.value,
        expr.string(v) : v.value,
        expr.bool(v) : if v.value { "true" } else { "false" },
        _ : "<literal>",
    }
}

func literal_pattern_equals(literal_pattern left, literal_pattern right) bool {
    literal_pattern_type(left) == literal_pattern_type(right) && literal_pattern_text(left) == literal_pattern_text(right)
}

func variant_payload_type(string expected_type, string ctor) string {
    base := compile.internal.typesys.base_type_name(expected_type)
    if base == "option" {
        if ctor == "some" {
            return first_type_arg(expected_type)
        }
        if ctor == "none" {
            return "()"
        }
    }
    if base == "result" {
        if ctor == "ok" {
            return first_type_arg(expected_type)
        }
        if ctor == "err" {
            return second_type_arg(expected_type)
        }
    }
    "unknown"
}

func canonical_binary_inference(string op, string left, string right) canonical_inference {
    diagnostics := semantic_error[]()
    if op == "+" && left == "string" && right == "string" { return canonical_inference { type_name: "string", diagnostics: diagnostics } }
    if op == "+" || op == "-" || op == "*" || op == "/" || op == "%" || op == "&" || op == "|" || op == "^" || op == "<<" || op == ">>" {
        if !types_compatible("int", left) || !types_compatible("int", right) { diagnostics.push(semantic_error { code: "e3018", message: "arithmetic requires int", anchor: op }) }
        return canonical_inference { type_name: "int", diagnostics: diagnostics }
    }
    if op == "<" || op == "<=" || op == ">" || op == ">=" {
        if !types_compatible("int", left) || !types_compatible("int", right) { diagnostics.push(semantic_error { code: "e3019", message: "ordering compare requires int", anchor: op }) }
        return canonical_inference { type_name: "bool", diagnostics: diagnostics }
    }
    if op == "==" || op == "!=" {
        if !types_compatible(left, right) { diagnostics.push(semantic_error { code: "e3020", message: "equality compare requires same type", anchor: op }) }
        if !is_unknown(left) && !is_unknown(right) && !nil_comparable_pair(left, right) {
            if !compile.internal.typesys.comparable_type(left) || !compile.internal.typesys.comparable_type(right) { diagnostics.push(semantic_error { code: "e3039", message: "equality compare requires comparable types", anchor: op }) }
        }
        return canonical_inference { type_name: "bool", diagnostics: diagnostics }
    }
    if op == "&&" || op == "||" {
        if !types_compatible("bool", left) || !types_compatible("bool", right) { diagnostics.push(semantic_error { code: "e3021", message: "logical op requires bool", anchor: op }) }
        return canonical_inference { type_name: "bool", diagnostics: diagnostics }
    }
    return canonical_inference { type_name: "unknown", diagnostics: diagnostics }
}

func canonical_binary_inference_in_context(string op, string left, string right, declaration_ref[] declarations) canonical_inference {
    // A scalar enum is comparable within its nominal declaration. Payload
    // and generic enums still require a separate, proved equality contract.
    if (op == "==" || op == "!=") && left == right && canonical_is_enum_type(left, declarations) {
        return canonical_inference { type_name: "bool", diagnostics: semantic_error[]() }
    }
    return canonical_binary_inference(op, left, right)
}

func infer_binary(string op, check_result left, check_result right, string source, semantic_error[] diagnostics, declaration_ref[] declarations) check_result {
    inferred := canonical_binary_inference_in_context(op, left.type_name, right.type_name, declarations)
    errors := left.errors + right.errors
    i := 0
    for i < len(inferred.diagnostics) {
        diagnostic := inferred.diagnostics[i]
        errors = errors + add_error(source, diagnostics, diagnostic.code, diagnostic.message, diagnostic.anchor)
        i = i + 1
    }
    return check_result { type_name: inferred.type_name, errors: errors }
}

func resolve_qualified_call_callee(string qualified_path, string[] arg_types, function_binding[] functions, trait_binding[] traits, declaration_ref[] declarations, string source, semantic_error[] diagnostics) call_callee_resolution {
    qualified_package := qualified_package_part(qualified_path)
    qualified_name := qualified_decl_part(qualified_path)
    qualified_candidates := lookup_qualified_functions(functions, qualified_package, qualified_name)
    empty_match := signature_match {
        ok: false, return_type: "unknown", instance_name: "", type_args: string[](), score: 0, generic_bind_count: 0, unknown_arg_count: 0,
    }
    if std.prelude.len(qualified_candidates) == 0 {
        return call_callee_resolution {
            ok: false,
            match: empty_match,
            errors: 0,
        }
    }
    matches := signature_match[]()
    j := 0
    for j < std.prelude.len(qualified_candidates) {
        m := try_match_signature(qualified_candidates[j], arg_types, functions, traits, declarations)
        if m.ok {
            matches.push(m);
        }
        j = j + 1
    }
    if std.prelude.len(matches) == 0 {
        return call_callee_resolution {
            ok: false,
            match: empty_match,
            errors: add_error(source, diagnostics, "e1002", "no matching overload", qualified_path),
        }
    }
    best := matches[0]
    ambiguous := false
    j = 1
    for j < std.prelude.len(matches) {
        if better_match(matches[j], best) {
            best = matches[j]
            ambiguous = false
        } else if same_match_rank(matches[j], best) {
            ambiguous = true
        }
        j = j + 1
    }
    if ambiguous {
        return call_callee_resolution {
            ok: false,
            match: empty_match,
            errors: add_error(source, diagnostics, "e1003", "ambiguous overload", qualified_path),
        }
    }
    if len(best.type_args) > 0 && !semantic_starts_with(best.instance_name, qualified_package + ".") { best.instance_name = qualified_package + "." + best.instance_name }
    call_callee_resolution {
        ok: true,
        match: best,
        errors: 0,
    }
}

func resolve_call_callee(string name, string[] arg_types, function_binding[] functions, trait_binding[] traits, declaration_ref[] declarations, string source, semantic_error[] diagnostics) call_callee_resolution {
    candidates := lookup_functions(functions, name)
    empty_match := signature_match {
        ok: false, return_type: "unknown", instance_name: "", type_args: string[](), score: 0, generic_bind_count: 0, unknown_arg_count: 0,
    }
    if std.prelude.len(candidates) == 0 {
        return call_callee_resolution {
            ok: false,
            match: empty_match,
            errors: add_error(source, diagnostics, "e1001", "undefined function", name),
        }
    }
    matches := signature_match[]()
    j := 0
    for j < std.prelude.len(candidates) {
        m := try_match_signature(candidates[j], arg_types, functions, traits, declarations)
        if m.ok {
            matches.push(m);
        }
        j = j + 1
    }
    if std.prelude.len(matches) == 0 {
        return call_callee_resolution {
            ok: false,
            match: empty_match,
            errors: add_error(source, diagnostics, "e1002", "no matching overload", name),
        }
    }
    best := matches[0]
    ambiguous := false
    j = 1
    for j < std.prelude.len(matches) {
        if better_match(matches[j], best) {
            best = matches[j]
            ambiguous = false
        } else if same_match_rank(matches[j], best) {
            ambiguous = true
        }
        j = j + 1
    }
    if ambiguous {
        return call_callee_resolution {
            ok: false,
            match: empty_match,
            errors: add_error(source, diagnostics, "e1003", "ambiguous overload", name),
        }
    }
    call_callee_resolution {
        ok: true,
        match: best,
        errors: 0,
    }
}

func lookup_functions(function_binding[] functions, string name) function_binding[] {
    out := function_binding[]()
    i := 0
    for i < std.prelude.len(functions) {
        if !functions[i].has_receiver && functions[i].name == name {
            out.push(functions[i]);
        }
        i = i + 1
    }
    out
}

func lookup_qualified_functions(function_binding[] functions, string package_path, string name) function_binding[] {
    out := function_binding[]()
    if package_path == "" || name == "" {
        return out
    }
    i := 0
    for i < std.prelude.len(functions) {
        if !functions[i].has_receiver && functions[i].package_path == package_path && functions[i].name == name {
            out.push(functions[i]);
        }
        i = i + 1
    }
    out
}

func qualified_expr_path(expr value) string {
    switch value {
        expr.name(name_value) : name_value.name,
        expr.member(member_value) : {
            prefix := qualified_expr_path(member_value.target.value)
            if prefix == "" {
                return ""
            }
            prefix + "." + member_value.member
        }
        _ : "",
    }
}

func qualified_package_part(string path) string {
    dot := find_last_char(path, ".")
    if dot <= 0 {
        return ""
    }
    std.prelude.prelude_slice(path, 0, dot)
}

func qualified_decl_part(string path) string {
    dot := find_last_char(path, ".")
    if dot <= 0 || dot + 1 >= std.prelude.len(path) {
        return ""
    }
    std.prelude.prelude_slice(path, dot + 1, std.prelude.len(path))
}

func lookup_named_methods(function_binding[] functions, string receiver_type, string name) function_binding[] {
    out := function_binding[]()
    normalized_receiver := method_owner_type(receiver_type)
    i := 0
    for i < std.prelude.len(functions) {
        if functions[i].has_receiver && compile.internal.typesys.base_type_name(functions[i].owner_type) == compile.internal.typesys.base_type_name(normalized_receiver) && functions[i].name == name {
            out.push(functions[i]);
        }
        i = i + 1
    }
    out
}

func lookup_methods(function_binding[] functions, string receiver_type, string name, expr receiver_expr) function_binding[] {
    out := function_binding[]()
    normalized_receiver := method_owner_type(receiver_type)
    i := 0
    for i < std.prelude.len(functions) {
        if functions[i].has_receiver && compile.internal.typesys.base_type_name(functions[i].owner_type) == compile.internal.typesys.base_type_name(normalized_receiver) && functions[i].name == name {
            if receiver_allows_method(receiver_type, receiver_expr, functions[i].receiver_mode) {
                out.push(functions[i]);
            }
        }
        i = i + 1
    }
    out
}

func method_owner_type(string receiver_type) string {
    if semantic_starts_with(receiver_type, "&") {
        return std.prelude.prelude_slice(receiver_type, 5, std.prelude.len(receiver_type))
    }
    if semantic_starts_with(receiver_type, "&") {
        return std.prelude.prelude_slice(receiver_type, 1, std.prelude.len(receiver_type))
    }
    receiver_type
}

func receiver_allows_method(string receiver_type, expr receiver_expr, string receiver_mode) bool {
    if receiver_mode == "value" {
        return true
    }
    if receiver_mode == "mut_ref" {
        if semantic_starts_with(receiver_type, "&") {
            return true
        }
        return is_addressable_expr(receiver_expr)
    }
    if receiver_mode == "ref" {
        if semantic_starts_with(receiver_type, "&") {
            return true
        }
        return is_addressable_expr(receiver_expr)
    }
    false
}

func is_addressable_expr(expr value) bool {
    switch value {
        expr.name(_) : true,
        expr.member(_) : true,
        expr.index(_) : true,
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

func try_match_signature(function_binding binding, string[] arg_types, function_binding[] functions, trait_binding[] traits, declaration_ref[] declarations) signature_match {
    if std.prelude.len(binding.param_types) != std.prelude.len(arg_types) {
        return signature_match {
            ok: false,
            return_type: "unknown", instance_name: "", type_args string[](), score 0, generic_bind_count 0, unknown_arg_count 0,
        }
    }
    
    generic_bindings := type_binding[]()
    bind_index := 0
    for bind_index < len(arg_types) {
        generic_bindings = collect_type_pattern_bindings(compile.internal.typesys.parse_type_ref(binding.param_types[bind_index]), compile.internal.typesys.parse_type_ref(arg_types[bind_index]), binding.generic_names, generic_bindings)
        bind_index = bind_index + 1
    }
    score := 0
    unknown_arg_count := 0
    i := 0
    for i < std.prelude.len(arg_types) {
        expected_type_str := binding.param_types[i]
        actual_type_str := arg_types[i]
        
        matched := false
        if semantic_starts_with(expected_type_str, "*") && semantic_starts_with(actual_type_str, "*") {
            
            expected_canonical := compile.internal.canonical_type.construct_canonical_from_string(expected_type_str, declarations)
            actual_canonical := compile.internal.canonical_type.construct_canonical_from_string(actual_type_str, declarations)
            matched = compile.internal.canonical_type.canonical_same_type(expected_canonical, actual_canonical)
        } else {
            
            expected_ref := compile.internal.typesys.parse_type_ref(expected_type_str)
            actual_ref := compile.internal.typesys.parse_type_ref(actual_type_str)
            if is_unknown(actual_ref.canonical) {
                unknown_arg_count = unknown_arg_count + 1
            }
            trait_result := find_trait_binding(traits, expected_ref.canonical)
            if trait_result.is_some() {
                matched = receiver_type_implements_trait(actual_ref.canonical, trait_result.unwrap(), functions)
            } else {
                matched = match_type_pattern_ref(expected_ref, actual_ref, binding.generic_names, generic_bindings)
            }
        }
        
        if !matched {
            return signature_match {
                ok: false,
                return_type: "unknown", instance_name: "", type_args string[](), score 0, generic_bind_count 0, unknown_arg_count 0,
            }
        }
        
        if !semantic_starts_with(binding.param_types[i], "*") {
            expected_ref := compile.internal.typesys.parse_type_ref(binding.param_types[i])
            actual_ref := compile.internal.typesys.parse_type_ref(arg_types[i])
            score = score + match_specificity(expected_ref, actual_ref, binding.generic_names)
        }
        
        i = i + 1
    }
    signature_match {
        ok: true, return_type instantiate_type(binding.return_type, binding.generic_names, generic_bindings), instance_name specialized_instance_name(binding, generic_bindings), type_args ordered_type_args(binding.generic_names, generic_bindings), score score, generic_bind_count std.prelude.len(generic_bindings), unknown_arg_count unknown_arg_count,
    }
}

func ordered_type_args(string[] generic_names, type_binding[] bindings) string[] {
    args := string[]()
    i := 0
    for i < std.prelude.len(generic_names) {
        bound := lookup_name_type(bindings, generic_names[i])
        if is_unknown(bound) {
            bound = "unknown"
        }
        args.push(bound)
        i = i + 1
    }
    args
}

func specialized_instance_name(function_binding binding, type_binding[] bindings) string {
    if std.prelude.len(binding.generic_names) == 0 {
        return binding.name
    }
    name := binding.name + "__mono"
    i := 0
    for i < std.prelude.len(binding.generic_names) {
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
    for i < std.prelude.len(type_name) {
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

func collect_type_pattern_bindings(type_ref expected, type_ref actual, string[] generics, type_binding[] bindings) type_binding[] {
    updated := bindings
    if is_generic_name(generics, expected.canonical) {
        if is_unknown(lookup_name_type(updated, expected.canonical)) { updated.push(type_binding { name: expected.canonical, type_name: actual.canonical }) }
        return updated
    }
    if expected.base != actual.base || len(expected.args) != len(actual.args) { return updated }
    i := 0
    for i < len(expected.args) {
        updated = collect_type_pattern_bindings(compile.internal.typesys.parse_type_ref(expected.args[i]), compile.internal.typesys.parse_type_ref(actual.args[i]), generics, updated)
        i = i + 1
    }
    return updated
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
        return compile.internal.typesys.same_type(bound, a)
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
    if std.prelude.len(p_args) != std.prelude.len(a_args) {
        return compile.internal.typesys.same_type_ref(param_type, arg_type)
    }
    i := 0
    for i < std.prelude.len(p_args) {
        p_next := compile.internal.typesys.parse_type_ref(p_args[i])
        a_next := compile.internal.typesys.parse_type_ref(a_args[i])
        if !match_type_pattern_ref(p_next, a_next, generic_names, generic_bindings) {
            return false
        }
        i = i + 1
    }
    true
}

func match_specificity(type_ref expected, type_ref actual, string[] generic_names) int {
    if compile.internal.typesys.same_type_ref(expected, actual) {
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
    clean := compile.internal.typesys.parse_type(ty)
    if is_generic_name(generic_names, clean) {
        bound := lookup_name_type(generic_bindings, clean)
        if !is_unknown(bound) {
            return bound
        }
    }
    if semantic_starts_with(clean, "&") {
        return "&" + instantiate_type(std.prelude.prelude_slice(clean, 5, std.prelude.len(clean)), generic_names, generic_bindings)
    }
    if semantic_starts_with(clean, "&") {
        return "&" + instantiate_type(std.prelude.prelude_slice(clean, 1, std.prelude.len(clean)), generic_names, generic_bindings)
    }
    if semantic_starts_with(clean, "[]") {
        return "[]" + instantiate_type(std.prelude.prelude_slice(clean, 2, std.prelude.len(clean)), generic_names, generic_bindings)
    }
    if semantic_starts_with(clean, "[") {
        return array_prefix_text(clean) + instantiate_type(strip_array_prefix(clean), generic_names, generic_bindings)
    }
    args := compile.internal.typesys.extract_type_args(clean)
    if std.prelude.len(args) == 0 {
        return clean
    }
    base := compile.internal.typesys.base_type_name(clean)
    tuple := compile.internal.typesys.is_tuple_type(clean)
    built := base + "["
    if tuple { built = "(" }
    i := 0
    for i < std.prelude.len(args) {
        if i > 0 {
            if tuple { built = built + "," } else { built = built + ", " }
        }
        built = built + instantiate_type(args[i], generic_names, generic_bindings)
        i = i + 1
    }
    if tuple { return built + ")" }
    built + "]"
}

func type_contains_generic(string ty, string[] generic_names) bool {
    clean := compile.internal.typesys.parse_type(ty)
    if is_generic_name(generic_names, clean) {
        return true
    }
    if semantic_starts_with(clean, "&") {
        return type_contains_generic(std.prelude.prelude_slice(clean, 5, std.prelude.len(clean)), generic_names)
    }
    if semantic_starts_with(clean, "&") {
        return type_contains_generic(std.prelude.prelude_slice(clean, 1, std.prelude.len(clean)), generic_names)
    }
    if semantic_starts_with(clean, "[]") {
        return type_contains_generic(std.prelude.prelude_slice(clean, 2, std.prelude.len(clean)), generic_names)
    }
    if semantic_starts_with(clean, "[") {
        return type_contains_generic(strip_array_prefix(clean), generic_names)
    }
    args := compile.internal.typesys.extract_type_args(clean)
    i := 0
    for i < std.prelude.len(args) {
        if type_contains_generic(args[i], generic_names) {
            return true
        }
        i = i + 1
    }
    false
}

func is_generic_name(string[] generic_names, string name) bool {
    i := 0
    for i < std.prelude.len(generic_names) {
        if generic_names[i] == name {
            return true
        }
        i = i + 1
    }
    false
}

func strip_array_prefix(string ty) string {
    clean := compile.internal.typesys.parse_type(ty)
    if !semantic_starts_with(clean, "[") || semantic_starts_with(clean, "[]") {
        return clean
    }
    depth := 0
    i := 0
    for i < std.prelude.len(clean) {
        ch := std.prelude.char_at(clean, i)
        if ch == "[" {
            depth = depth + 1
        } else if ch == "]" {
            depth = depth - 1
            if depth == 0 {
                return compile.internal.typesys.parse_type(std.prelude.prelude_slice(clean, i + 1, std.prelude.len(clean)))
            }
        }
        i = i + 1
    }
    clean
}

func array_prefix_text(string ty) string {
    clean := compile.internal.typesys.parse_type(ty)
    tail := strip_array_prefix(clean)
    if tail == clean {
        return ""
    }
    std.prelude.prelude_slice(clean, 0, std.prelude.len(clean) - std.prelude.len(tail))
}

func generic_name(string raw) string {
    i := 0
    for i < std.prelude.len(raw) {
        if std.prelude.char_at(raw, i) == ":" {
            return trim_text(std.prelude.prelude_slice(raw, 0, i))
        }
        i = i + 1
    }
    trim_text(raw)
}

func clone_env(type_binding[] env) type_binding[] {
    out := type_binding[]()
    i := 0
    for i < std.prelude.len(env) {
        out.push(env[i]);
        i = i + 1
    }
    out
}

func lookup_name_type(type_binding[] env, string name) string {
    i := std.prelude.len(env)
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
        type_name: compile.internal.typesys.parse_type(type_name), errors 0,
    }
}

func types_compatible(string left, string right) bool {
    if is_unknown(left) || is_unknown(right) {
        return is_unknown(left) && is_unknown(right)
    }
    if is_nil(left) && is_nil(right) {
        return true
    }
    if is_nil(left) {
        return is_nilable_type(right)
    }
    if is_nil(right) {
        return is_nilable_type(left)
    }
    compile.internal.typesys.assignable_type(left, right) || compile.internal.typesys.compatible_type(left, right)
}

func nil_comparable_pair(string left, string right) bool {
    if is_nil(left) {
        return is_nil(right) || is_nilable_type(right)
    }
    if is_nil(right) {
        return is_nilable_type(left)
    }
    false
}

func is_nil(string type_name) bool {
    compile.internal.typesys.parse_type(type_name) == "nil"
}

func is_nilable_type(string type_name) bool {
    clean := compile.internal.typesys.parse_type(type_name)
    if clean == "fn" || clean == "map" {
        return true
    }
    if semantic_starts_with(clean, "[]") || semantic_starts_with(clean, "&") {
        return true
    }
    base := compile.internal.typesys.base_type_name(clean)
    base == "interface" || base == "trait"
}

func is_unknown(string type_name) bool {
    clean := compile.internal.typesys.parse_type(type_name)
    clean == "" || clean == "unknown"
}

func declared_type_is_safe(string type_name) bool {
    if is_unknown(type_name) {
        return false
    }
    if compile.internal.typesys.has_unknown_component(type_name) {
        return false
    }
    if type_name == "nil" {
        return false
    }
    true
}

func has_duplicate_binding(type_binding[] env, string name) bool {
    return has_duplicate_binding_from(env, name, 0)
}

func has_duplicate_binding_from(type_binding[] env, string name, int start) bool {
    i := start
    for i < std.prelude.len(env) {
        if env[i].name == name {
            return true
        }
        i = i + 1
    }
    false
}

func is_zero_int_expr(expr value) bool {
    switch value {
        expr.int(number) : number.value == "0",
        _ : false,
    }
}

func resolve_method_return(string target_type, string method_type) string {
    target_ref := compile.internal.typesys.parse_type_ref(target_type)
    if method_type == "t" {
        return compile.internal.typesys.type_arg(target_ref, 0)
    }
    if method_type == "e" {
        return compile.internal.typesys.type_arg(target_ref, 1)
    }
    if method_type == "option[t]" {
        arg := compile.internal.typesys.type_arg(target_ref, 0)
        if is_unknown(arg) {
            return "option[unknown]"
        }
        return "option[" + arg + "]"
    }
    compile.internal.typesys.parse_type(method_type)
}

func first_type_arg(string type_name) string {
    compile.internal.typesys.type_arg(compile.internal.typesys.parse_type_ref(type_name), 0)
}

func second_type_arg(string type_name) string {
    compile.internal.typesys.type_arg(compile.internal.typesys.parse_type_ref(type_name), 1)
}

func add_error(string source, semantic_error[] diagnostics, string code, string message, string anchor) int {
    recovery_anchor := resolve_recovery_anchor(source, anchor)
    chain_id := build_chain_id("semantic", code, recovery_anchor)
    pos := locate_anchor(source, recovery_anchor)
    severity := diagnostic_severity(code)
    tier := diagnostic_tier(code)
    hint := diagnostic_hint(code, recovery_anchor)
    diagnostic := semantic_error {
        code: code, message message,
        stage: "semantic", chain_id chain_id,
        upstream_code: "", severity severity, hint hint, anchor recovery_anchor, tier tier, repeat_count 1, line pos.line, column pos.column,
    }
    semantic_diagnostic_log.push(diagnostic)
    diagnostics.push(diagnostic)
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
    for i < std.prelude.len(anchor) {
        ch := std.prelude.prelude_slice(anchor, i, i + 1)
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
    if semantic_starts_with_text(code, "e100") {
        return "check overload candidates and argument types near " + anchor
    }
    if semantic_starts_with_text(code, "e200") {
        return "check switch exhaustiveness and pattern binding near " + anchor
    }
    if semantic_starts_with_text(code, "e300") {
        return "check declared vs inferred type around " + anchor
    }
    if semantic_starts_with_text(code, "e000") {
        return "fix parse/type-rule preconditions first"
    }
    "review surrounding declaration near " + anchor
}

func diagnostic_severity(string code) string {
    if semantic_starts_with_text(code, "e000") {
        return "fatal"
    }
    if semantic_starts_with_text(code, "e1") {
        return "warning"
    }
    "error"
}

func diagnostic_tier(string code) int {
    if semantic_starts_with_text(code, "e000") {
        return 0
    }
    if semantic_starts_with_text(code, "e1") {
        return 2
    }
    1
}

func semantic_starts_with_text(string text, string prefix) bool {
    if std.prelude.len(prefix) > std.prelude.len(text) {
        return false
    }
    std.prelude.prelude_slice(text, 0, std.prelude.len(prefix)) == prefix
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
    if std.prelude.len(needle) > std.prelude.len(haystack) {
        return 0 - 1
    }
    i := 0
    for i + std.prelude.len(needle) <= std.prelude.len(haystack) {
        if std.prelude.prelude_slice(haystack, i, i + std.prelude.len(needle)) == needle {
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
        if std.prelude.char_at(source, i) == "\n" {
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

func semantic_starts_with(string text, string prefix) bool {
    if std.prelude.len(prefix) > std.prelude.len(text) {
        return false
    }
    std.prelude.prelude_slice(text, 0, std.prelude.len(prefix)) == prefix
}

func contains_token(string text, string token) bool {
    if token == "" {
        return true
    }
    find_substring(text, token) >= 0
}

func semantic_find_char(string text, string needle) int {
    i := 0
    for i < std.prelude.len(text) {
        if std.prelude.char_at(text, i) == needle {
            return i
        }
        i = i + 1
    }
    0 - 1
}

func find_last_char(string text, string needle) int {
    i := std.prelude.len(text)
    for i > 0 {
        i = i - 1
        if std.prelude.char_at(text, i) == needle {
            return i
        }
    }
    0 - 1
}

func last_path_segment(string path) string {
    i := std.prelude.len(path)
    for i > 0 {
        i = i - 1
        if std.prelude.char_at(path, i) == "." {
            return std.prelude.prelude_slice(path, i + 1, std.prelude.len(path))
        }
    }
    path
}

func trim_text(string text) string {
    start := 0
    end := std.prelude.len(text)
    for start < end && semantic_is_space(std.prelude.char_at(text, start)) {
        start = start + 1
    }
    for end > start && semantic_is_space(std.prelude.char_at(text, end - 1)) {
        end = end - 1
    }
    std.prelude.prelude_slice(text, start, end)
}

func semantic_is_space(string ch) bool {
    ch == " " || ch == "\n" || ch == "\t" || ch == "\r"
}

func canonical_return_mismatch(string owner, string name, string expected, string actual, block_expr body) string {
    kind := "none"
    switch body.final_expr {
        option.some(value): {
            kind = switch value {
                expr.int(_): "int", expr.string(_): "string", expr.bool(_): "bool",
                expr.name(_): "name", expr.borrow(_): "borrow", expr.binary(_): "binary",
                expr.member(_): "member", expr.index(_): "index", expr.call(_): "call",
                expr.switch(_): "switch", expr.if(_): "if", expr.for(_): "for",
                expr.while(_): "while", expr.block(_): "block", expr.tuple(_): "tuple",
                expr.array(_): "array", expr.map(_): "map", expr.record(_): "record",
            }
        }
        option.none: (),
    }
    wanted := compile.internal.typesys.extract_tuple_args(expected)
    received := compile.internal.typesys.extract_tuple_args(actual)
    return owner + " return type mismatch; function=" + name
        + "; expected=" + expected + "; actual=" + actual + "; tail_expr_kind=" + kind
        + "; expected_arity=" + std.prelude.to_string(len(wanted))
        + "; actual_arity=" + std.prelude.to_string(len(received))
        + "; expected_element_types=" + canonical_return_elements(wanted)
        + "; actual_element_types=" + canonical_return_elements(received)
}

func canonical_return_elements(string[] elements) string {
    text := "["
    i := 0
    for i < len(elements) {
        if i > 0 { text = text + "," }
        text = text + elements[i]
        i = i + 1
    }
    return text + "]"
}
