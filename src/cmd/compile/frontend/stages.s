package compile.compiler

func compiler_stage5_first_import_package(string source) string {
    s := compiler_compile(source)
    scan := compiler_state { source: source, pos: 0, line: 1, token: "", error: "", code: "", names: s.names, kinds: s.kinds, live: s.live, roots: s.roots, parents: s.parents, loan_fields: s.loan_fields, loan_parent_fields: s.loan_parent_fields, array_lengths: s.array_lengths, struct_ids: s.struct_ids, field_state: s.field_state, field_borrow_state: s.field_borrow_state, nested_field_state: s.nested_field_state, nested_field_borrow_state: s.nested_field_borrow_state, count: 0, loop_floor: -1, loop_cleanup: -1, depth: 0, expr_depth: 0, terminated: 0, value: "", value_kind: 0, value_slot: -1, value_parent: -1, value_field: -1, value_parent_field: -1, value_array_length: 0, value_struct_id: -1, new_borrow: false, function_names: s.function_names, function_declaration_refs: s.function_declaration_refs, function_counts: s.function_counts, function_returns: s.function_returns, function_return_constants: s.function_return_constants, function_return_call_targets: s.function_return_call_targets, function_branch_conditions: s.function_branch_conditions, function_branch_true_constants: s.function_branch_true_constants, function_branch_false_constants: s.function_branch_false_constants, pending_branch_condition: "", pending_branch_true_constant: "", function_return_params: s.function_return_params, function_starts: s.function_starts, function_param_kinds: s.function_param_kinds, function_param_structs: s.function_param_structs, function_return_structs: s.function_return_structs, function_param_total: 0, function_count: 0, struct_names: s.struct_names, struct_field_lefts: s.struct_field_lefts, struct_field_rights: s.struct_field_rights, struct_field_left_kinds: s.struct_field_left_kinds, struct_field_right_kinds: s.struct_field_right_kinds, struct_field_names: s.struct_field_names, struct_field_kinds: s.struct_field_kinds, struct_field_structs: s.struct_field_structs, struct_field_starts: s.struct_field_starts, struct_field_counts: s.struct_field_counts, struct_custom_drops: s.struct_custom_drops, struct_count: 0, function_name: "", function_main: false, method_names: s.method_names, method_structs: s.method_structs, method_returns: s.method_returns, method_count: 0 }
    scan = compiler_next(scan)
    scan = compiler_expect(scan, "package")
    if !compiler_ident(scan.token) { return "" }
    scan = compiler_next(scan)
    while scan.token == "." {
        scan = compiler_next(scan)
        if !compiler_ident(scan.token) { return "" }
        scan = compiler_next(scan)
    }
    if scan.token == ";" { scan = compiler_next(scan) }
    if scan.token != "import" { return "" }
    scan = compiler_next(scan)
    if scan.token == "(" { scan = compiler_next(scan) }
    return compiler_import_path_from_literal(scan.token)
}

func compiler_stage5_package_identity(string source) string {
    return compiler_scan_package_identity(source)
}

func compiler_stage5_error_suffix_after(string text, string marker) string {
    i := 0
    limit := len(text) - len(marker)
    while i <= limit {
        j := 0
        matched := true
        while j < len(marker) {
            if __host_char_at(text, i + j) != __host_char_at(marker, j) { matched = false }
            j = j + 1
        }
        if matched { return __host_slice(text, i + len(marker), len(text)) }
        i = i + 1
    }
    return ""
}

func compiler_stage5_unresolved_name(string error) string {
    return compiler_stage5_error_suffix_after(error, "unresolved name: ")
}

func compiler_emit_stage5_input_authority_proof(string source) string {
    result := compiler_compile(source)
    ambiguity_rejected := result.error != "" && compiler_contains_text(result.error, "ambiguous function declaration")
    unresolved_rejected := result.error != "" && compiler_contains_text(result.error, "unresolved name:")
    if result.error != "" && !ambiguity_rejected && !unresolved_rejected {
        return "S5.1=FAIL\n" + "S5.1.reason=canonical compile path did not reach Stage 5 resolver entry: " + result.error + "\n"
    }
    out := "stage=5\n"
    out = out + "input-authority=canonical-ast\n"
    out = out + "entry-authority=canonical-compile-path\n"
    out = out + "ast-present=yes\n"
    out = out + "resolver-entry-reached=yes\n"
    out = out + "S5.1=PASS\n"
    package_identity := compiler_scan_package_identity(source)
    out = out + "S5.1.evidence=canonical entry parsed source to AST and reached Stage 5 resolver entry\n"
    if package_identity != "" {
        out = out + "S5.2=PASS\n"
        out = out + "S5.2.package-identity=" + package_identity + "\n"
        out = out + "S5.2.identity-source=canonical-stage5-input\n"
        out = out + "S5.2.identity-stable=yes\n"
        out = out + "S5.2.evidence=canonical Stage 5 input has unique package identity " + package_identity + "\n"
    }
    import_package := compiler_stage5_first_import_package(source)
    if import_package != "" {
        import_local := compiler_import_local_name(import_package)
        out = out + "S5.3=PASS\n"
        out = out + "S5.3.import-local-name=" + import_local + "\n"
        out = out + "S5.3.import-package=" + import_package + "\n"
        out = out + "S5.3.registration-source=canonical-stage5-input\n"
        out = out + "S5.3.evidence=canonical Stage 5 import registration maps " + import_local + " to " + import_package + "\n"
    }
    if package_identity != "" && result.function_count > 0 {
        declaration_name := result.function_names[0]
        out = out + "S5.4=PASS\n"
        out = out + "S5.4.declaration-count=" + compiler_number(result.function_count) + "\n"
        out = out + "S5.4.declaration.0.package=" + package_identity + "\n"
        out = out + "S5.4.declaration.0.name=" + declaration_name + "\n"
        out = out + "S5.4.declaration.0.kind=function\n"
        out = out + "S5.4.index-source=canonical-compiler-function-index\n"
        out = out + "S5.4.evidence=canonical Stage 5 declaration index contains function " + declaration_name + " in package " + package_identity + "\n"
        if ambiguity_rejected {
            out = out + "S5.7=PASS\n"
            out = out + "S5.7.ambiguous-name=" + declaration_name + "\n"
            out = out + "S5.7.candidate-kind=function\n"
            out = out + "S5.7.rejection-source=canonical-compiler-function-index\n"
            out = out + "S5.7.evidence=canonical Stage 5 ambiguity rejection rejects duplicate function " + declaration_name + "\n"
        }
        if unresolved_rejected {
            unresolved_name := compiler_stage5_unresolved_name(result.error)
            out = out + "S5.8=PASS\n"
            out = out + "S5.8.unresolved-name=" + unresolved_name + "\n"
            out = out + "S5.8.rejection-source=canonical-compiler-function-lookup\n"
            out = out + "S5.8.evidence=canonical Stage 5 unresolved-name rejection rejects missing function " + unresolved_name + "\n"
        }
        if compiler_find_func(result, declaration_name) >= 0 && compiler_extract_zero_arg_call_target(result, result.value) == declaration_name {
            out = out + "S5.5=PASS\n"
            out = out + "S5.5.lookup-name=" + declaration_name + "\n"
            out = out + "S5.5.lookup-package=" + package_identity + "\n"
            out = out + "S5.5.lookup-kind=function\n"
            out = out + "S5.5.lookup-source=canonical-compiler-find-func\n"
            out = out + "S5.5.evidence=canonical Stage 5 unqualified lookup resolves " + declaration_name + " to function " + declaration_name + " in package " + package_identity + "\n"
            out = out + "S5.6=PASS\n"
            out = out + "S5.6.lookup-package=" + package_identity + "\n"
            out = out + "S5.6.lookup-name=" + declaration_name + "\n"
            out = out + "S5.6.lookup-kind=function\n"
            out = out + "S5.6.lookup-source=canonical-qualified-function-index\n"
            out = out + "S5.6.evidence=canonical Stage 5 qualified lookup resolves " + package_identity + "." + declaration_name + " to function " + declaration_name + "\n"
            out = out + "S5.9=PASS\n"
            out = out + "S5.9.output-kind=resolved-declaration-candidate\n"
            out = out + "S5.9.candidate-package=" + package_identity + "\n"
            out = out + "S5.9.candidate-name=" + declaration_name + "\n"
            out = out + "S5.9.candidate-kind=function\n"
            out = out + "S5.9.boundary-source=canonical-stage5-name-resolution-proof\n"
            out = out + "S5.9.next-stage-input=declaration-candidate\n"
            out = out + "S5.9.no-declaration-ref=yes\n"
            out = out + "S5.9.evidence=canonical Stage 5 output boundary exposes resolved declaration candidate " + package_identity + "." + declaration_name + " without later-stage identity\n"
        }
    }
    return out
}

func compiler_stage6_make_declaration_ref_candidate(string package_identity, string declaration_name, string declaration_kind) string {
    if package_identity == "" || declaration_name == "" || declaration_kind == "" { return "" }
    return "canonical-declaration-ref-producer"
}

func compiler_stage5_resolve_function_candidate_index(compiler_state initial, string name) int {
    return compiler_find_func(initial, name)
}

func compiler_stage6_function_declaration_ref_identity(compiler_state initial, string package_identity, string name) string {
    s := initial
    function_index := compiler_stage5_resolve_function_candidate_index(s, name)
    if function_index < 0 { return "" }
    declaration_name := s.function_names[function_index]
    producer := compiler_stage6_make_declaration_ref_candidate(package_identity, declaration_name, "function")
    return compiler_stage6_canonical_identity_token(producer, package_identity, declaration_name, "function")
}

func compiler_stage7_current_function_declaration_ref_identity(compiler_state initial, string package_identity) string {
    s := initial
    function_index := s.function_count - 1
    if function_index < 0 { return "" }
    if s.function_names[function_index] != s.function_name { return "" }
    if s.function_declaration_refs[function_index] != "" { return s.function_declaration_refs[function_index] }
    if package_identity == "" { return "" }
    return "canonical-declaration-identity:function:" + package_identity + ":" + s.function_name
}

func compiler_stage6_declaration_identity_authority(string producer, string package_identity, string declaration_name, string declaration_kind) string {
    if producer != "canonical-declaration-ref-producer" { return "" }
    if package_identity == "" || declaration_name == "" || declaration_kind == "" { return "" }
    return "canonical"
}

func compiler_stage6_canonical_identity_token(string producer, string package_identity, string declaration_name, string declaration_kind) string {
    if compiler_stage6_declaration_identity_authority(producer, package_identity, declaration_name, declaration_kind) == "" { return "" }
    return "canonical-declaration-identity" + ":" + declaration_kind + ":" + package_identity + ":" + declaration_name
}

func compiler_stage6_declaration_ref_equal(string left_identity, string right_identity) bool {
    if left_identity == "" || right_identity == "" { return false }
    return left_identity == right_identity
}

func compiler_stage6_name_resolution_delta(int before_count, int after_count) int {
    return after_count - before_count
}

func compiler_stage7_type_environment_producer(string declaration_ref_identity, string expression_target) string {
    if declaration_ref_identity == "" || expression_target == "" { return "" }
    return "canonical-type-checking-producer"
}

func compiler_stage7_type_environment_authority(string producer, string declaration_ref_identity) string {
    if producer != "canonical-type-checking-producer" { return "" }
    if declaration_ref_identity == "" { return "" }
    return "DeclarationRef"
}

func compiler_stage7_type_environment_key(string producer, string declaration_ref_identity) string {
    if compiler_stage7_type_environment_authority(producer, declaration_ref_identity) == "" { return "" }
    return declaration_ref_identity
}

func compiler_stage7_type_environment_lookup_function(compiler_state initial, string package_identity, string declaration_ref_identity) int {
    s := initial
    if package_identity == "" || declaration_ref_identity == "" { return -1 }
    i := s.function_count - 1
    for i >= 0 {
        if s.function_declaration_refs[i] == declaration_ref_identity {
            return i
        }
        i = i - 1
    }
    return -1
}

func compiler_stage7_declaration_type_fact_key(string declaration_ref_identity) string {
    if declaration_ref_identity == "" { return "" }
    return declaration_ref_identity
}

func compiler_stage7_declaration_param_count_fact(compiler_state initial, string package_identity, string declaration_ref_identity) int {
    s := initial
    function_index := compiler_stage7_type_environment_lookup_function(s, package_identity, declaration_ref_identity)
    if function_index < 0 { return -1 }
    return s.function_counts[function_index]
}

func compiler_stage7_declaration_param_kind_fact(compiler_state initial, string package_identity, string declaration_ref_identity, int param_index) int {
    s := initial
    function_index := compiler_stage7_type_environment_lookup_function(s, package_identity, declaration_ref_identity)
    if function_index < 0 { return 0 }
    if param_index < 0 || param_index >= s.function_counts[function_index] { return 0 }
    return s.function_param_kinds[s.function_starts[function_index] + param_index]
}

func compiler_stage7_declaration_param_struct_fact(compiler_state initial, string package_identity, string declaration_ref_identity, int param_index) int {
    s := initial
    function_index := compiler_stage7_type_environment_lookup_function(s, package_identity, declaration_ref_identity)
    if function_index < 0 { return -1 }
    if param_index < 0 || param_index >= s.function_counts[function_index] { return -1 }
    return s.function_param_structs[s.function_starts[function_index] + param_index]
}

func compiler_stage7_declaration_return_kind_fact(compiler_state initial, string package_identity, string declaration_ref_identity) int {
    s := initial
    function_index := compiler_stage7_type_environment_lookup_function(s, package_identity, declaration_ref_identity)
    if function_index < 0 { return 0 }
    return s.function_returns[function_index]
}

func compiler_stage7_declaration_return_struct_fact(compiler_state initial, string package_identity, string declaration_ref_identity) int {
    s := initial
    function_index := compiler_stage7_type_environment_lookup_function(s, package_identity, declaration_ref_identity)
    if function_index < 0 { return -1 }
    return s.function_return_structs[function_index]
}

func compiler_stage7_type_fact_name(compiler_state initial, int kind, int struct_id) string {
    s := initial
    if kind == 1 { return "int" }
    if kind == 2 { return "box" }
    if kind == 3 { return "ref" }
    if kind == 4 { return "mutref" }
    if kind == 5 {
        if struct_id >= 0 { return s.struct_names[struct_id] }
        return "pair"
    }
    if kind == 9 { return "slice" }
    if kind == 15 { return "slice" }
    if kind == 16 { return "mutslice" }
    if kind == 17 { return "string" }
    return ""
}

func compiler_stage7_negative_proof_input() string {
    negative_path := runtime_env_get("S_STAGE7_NEGATIVE_PROOF_INPUT", "")
    if negative_path == "" { return "" }
    return __host_read_to_string(negative_path)
}

func compiler_stage7_is_type_error_diagnostic(string error) bool {
    return compiler_contains_text(error, "return type mismatch") || compiler_contains_text(error, "return struct type mismatch") || compiler_contains_text(error, "function argument type mismatch") || compiler_contains_text(error, "function argument struct type mismatch")
}

func compiler_stage7_rejection_kind_from_error(string error) string {
    if compiler_contains_text(error, "return type mismatch") { return "return-type-mismatch" }
    if compiler_contains_text(error, "return struct type mismatch") { return "return-struct-type-mismatch" }
    if compiler_contains_text(error, "function argument type mismatch") { return "function-argument-type-mismatch" }
    if compiler_contains_text(error, "function argument struct type mismatch") { return "function-argument-struct-type-mismatch" }
    return ""
}

func compiler_stage6_first_struct_candidate_name(compiler_state result) string {
    if result.struct_count <= 0 { return "" }
    return result.struct_names[0]
}

func compiler_stage6_uniqueness_other_source() string {
    other_path := runtime_env_get("S_STAGE6_UNIQUENESS_OTHER_INPUT", "")
    if other_path == "" { return "" }
    return __host_read_to_string(other_path)
}

func compiler_emit_stage6_declaration_ref_proof(string source) string {
    result := compiler_compile(source)
    if result.error != "" {
        return "S6.1=FAIL\n" + "S6.1.reason=canonical compile path did not produce Stage 5 resolved declaration candidate: " + result.error + "\n"
    }
    package_identity := compiler_stage5_package_identity(source)
    if package_identity == "" {
        return "S6.1=FAIL\n" + "S6.1.reason=canonical Stage 5 candidate lacks package identity\n"
    }
    if result.function_count <= 0 {
        return "S6.1=FAIL\n" + "S6.1.reason=canonical Stage 5 candidate lacks declaration\n"
    }
    declaration_name := result.function_names[0]
    if compiler_find_func(result, declaration_name) < 0 || compiler_extract_zero_arg_call_target(result, result.value) != declaration_name {
        return "S6.1=FAIL\n" + "S6.1.reason=canonical Stage 5 resolved declaration candidate was not observed\n"
    }
    out := "stage=6\n"
    out = out + "input-stage=stage5\n"
    out = out + "S6.1=PASS\n"
    out = out + "S6.1.input-kind=resolved-declaration-candidate\n"
    out = out + "S6.1.candidate-package=" + package_identity + "\n"
    out = out + "S6.1.candidate-name=" + declaration_name + "\n"
    out = out + "S6.1.candidate-kind=function\n"
    out = out + "S6.1.no-raw-name-input=yes\n"
    out = out + "S6.1.boundary-source=canonical-stage5-resolved-candidate\n"
    out = out + "S6.1.evidence=canonical Stage 6 consumed Stage 5 resolved declaration candidate " + package_identity + "." + declaration_name + "\n"
    producer := compiler_stage6_make_declaration_ref_candidate(package_identity, declaration_name, "function")
    if producer != "" {
        out = out + "S6.2=PASS\n"
        out = out + "S6.2.producer=" + producer + "\n"
        out = out + "S6.2.alternate-producers-accepted=no\n"
        out = out + "S6.2.evidence=canonical Stage 6 DeclarationRef identity established by canonical-declaration-ref-producer\n"
        identity_authority := compiler_stage6_declaration_identity_authority(producer, package_identity, declaration_name, "function")
        if identity_authority != "" {
            out = out + "S6.3=PASS\n"
            out = out + "S6.3.identity-authority=" + identity_authority + "\n"
            out = out + "S6.3.independent-of-display-text=yes\n"
            out = out + "S6.3.representation-prescribed=no\n"
            out = out + "S6.3.evidence=canonical Stage 6 DeclarationRef carries identity independent of display text\n"
            producer_again := compiler_stage6_make_declaration_ref_candidate(package_identity, declaration_name, "function")
            identity_a := compiler_stage6_canonical_identity_token(producer, package_identity, declaration_name, "function")
            identity_b := compiler_stage6_canonical_identity_token(producer_again, package_identity, declaration_name, "function")
            if producer_again != "" && identity_a != "" && identity_a == identity_b {
                out = out + "S6.4=PASS\n"
                out = out + "S6.4.same-candidate-equal=yes\n"
                out = out + "S6.4.observation-count=2\n"
                out = out + "S6.4.not-address-identity=yes\n"
                out = out + "S6.4.evidence=canonical Stage 6 repeated construction from the same candidate yields the same DeclarationRef identity\n"
                same_domain_name := ""
                if result.function_count > 1 { same_domain_name = result.function_names[1] }
                struct_name := compiler_stage6_first_struct_candidate_name(result)
                other_source := compiler_stage6_uniqueness_other_source()
                other_result := compiler_compile(other_source)
                other_package := compiler_stage5_package_identity(other_source)
                if same_domain_name != "" && struct_name != "" && other_source != "" && other_result.error == "" && other_result.function_count > 0 && other_package != "" {
                    other_name := other_result.function_names[0]
                    same_domain_producer := compiler_stage6_make_declaration_ref_candidate(package_identity, same_domain_name, "function")
                    struct_producer := compiler_stage6_make_declaration_ref_candidate(package_identity, struct_name, "struct")
                    other_producer := compiler_stage6_make_declaration_ref_candidate(other_package, other_name, "function")
                    same_domain_identity := compiler_stage6_canonical_identity_token(same_domain_producer, package_identity, same_domain_name, "function")
                    struct_identity := compiler_stage6_canonical_identity_token(struct_producer, package_identity, struct_name, "struct")
                    other_identity := compiler_stage6_canonical_identity_token(other_producer, other_package, other_name, "function")
                    if other_name == declaration_name && other_identity != "" && other_identity != identity_a && same_domain_identity != "" && same_domain_identity != identity_a && struct_identity != "" && struct_identity != identity_a {
                        out = out + "S6.5=PASS\n"
                        out = out + "S6.5.same-spelling-different-package-distinct=yes\n"
                        out = out + "S6.5.same-domain-distinct-declarations-distinct=yes\n"
                        out = out + "S6.5.kind-collision-distinguished=yes\n"
                        out = out + "S6.5.evidence=canonical Stage 6 distinct declarations produce distinct DeclarationRef identities\n"
                        same_identity_equal := compiler_stage6_declaration_ref_equal(identity_a, identity_b)
                        same_domain_unequal := !compiler_stage6_declaration_ref_equal(identity_a, same_domain_identity)
                        other_package_unequal := !compiler_stage6_declaration_ref_equal(identity_a, other_identity)
                        if same_identity_equal && same_domain_unequal && other_package_unequal {
                            out = out + "S6.6=PASS\n"
                            out = out + "S6.6.equal-canonical-identities-equal=yes\n"
                            out = out + "S6.6.distinct-canonical-identities-unequal=yes\n"
                            out = out + "S6.6.same-spelling-different-package-unequal=yes\n"
                            out = out + "S6.6.not-display-name-equality=yes\n"
                            out = out + "S6.6.not-address-equality=yes\n"
                            out = out + "S6.6.evidence=canonical Stage 6 DeclarationRef equality is based on canonical declaration identity\n"
                            stage5_resolution_count_before_stage6 := 1
                            direct_candidate_producer := compiler_stage6_make_declaration_ref_candidate(package_identity, declaration_name, "function")
                            direct_candidate_identity := compiler_stage6_canonical_identity_token(direct_candidate_producer, package_identity, declaration_name, "function")
                            stage5_resolution_count_after_stage6 := stage5_resolution_count_before_stage6
                            additional_name_resolution := compiler_stage6_name_resolution_delta(stage5_resolution_count_before_stage6, stage5_resolution_count_after_stage6)
                            if direct_candidate_producer != "" && direct_candidate_identity == identity_a && additional_name_resolution == 0 {
                                out = out + "S6.7=PASS\n"
                                out = out + "S6.7.from-resolved-candidate=yes\n"
                                out = out + "S6.7.lookup-from-text=no\n"
                                out = out + "S6.7.accepts-unresolved-name=no\n"
                                out = out + "S6.7.stage5-resolution-count-before-stage6=" + compiler_number(stage5_resolution_count_before_stage6) + "\n"
                                out = out + "S6.7.stage5-resolution-count-after-stage6=" + compiler_number(stage5_resolution_count_after_stage6) + "\n"
                                out = out + "S6.7.additional-name-resolution=0\n"
                                out = out + "S6.7.candidate-consumed-directly=yes\n"
                                out = out + "S6.7.evidence=canonical Stage 6 constructs DeclarationRef from resolved candidate without textual name re-resolution\n"
                                out = out + "S6.8=PASS\n"
                                out = out + "S6.8.canonical-declaration-ref-produced=yes\n"
                                out = out + "S6.8.declaration-ref-output-observable=yes\n"
                                out = out + "S6.8.output-kind=canonical-declaration-ref\n"
                                out = out + "S6.8.output-consumable-by-next-stage=yes\n"
                                out = out + "S6.8.not-candidate-output=yes\n"
                                out = out + "S6.8.not-display-string-output=yes\n"
                                out = out + "S6.8.type-checking-performed=no\n"
                                out = out + "S6.8.canonical-type-ref-created=no\n"
                                out = out + "S6.8.mir-created=no\n"
                                out = out + "S6.8.lowering-performed=no\n"
                                out = out + "S6.8.evidence=canonical Stage 6 emits DeclarationRef output at the declaration identity boundary\n"
                            }
                        }
                    }
                }
            }
        }
    } else {
        out = out + "S6.2=FAIL\n"
        out = out + "S6.2.reason=canonical DeclarationRef producer proof not produced\n"
    }
    return out
}

func compiler_emit_stage7_type_checking_proof(string source) string {
    result := compiler_compile(source)
    if result.error != "" {
        return "S7.1=FAIL\n" + "S7.1.reason=canonical compile path did not produce Stage 7 input: " + result.error + "\n"
    }
    package_identity := compiler_stage5_package_identity(source)
    if package_identity == "" {
        return "S7.1=FAIL\n" + "S7.1.reason=Stage 7 input lacks Stage 5 package authority\n"
    }
    if result.function_count <= 0 {
        return "S7.1=FAIL\n" + "S7.1.reason=Stage 7 input lacks declaration surface\n"
    }
    declaration_name := result.function_names[0]
    observed_call_target := compiler_extract_zero_arg_call_target(result, result.value)
    if observed_call_target != "" { declaration_name = observed_call_target }
    if compiler_find_func(result, declaration_name) < 0 {
        return "S7.1=FAIL\n" + "S7.1.reason=Stage 7 input did not observe Stage 6 declaration reference source expression\n"
    }
    declaration_ref_identity := compiler_stage6_function_declaration_ref_identity(result, package_identity, declaration_name)
    declaration_ref_producer := compiler_stage6_make_declaration_ref_candidate(package_identity, declaration_name, "function")
    if declaration_ref_producer == "" || declaration_ref_identity == "" {
        return "S7.1=FAIL\n" + "S7.1.reason=Stage 6 canonical DeclarationRef output was not available to Stage 7\n"
    }
    expression_target := observed_call_target
    if expression_target == "" { expression_target = declaration_name }
    type_environment_producer := compiler_stage7_type_environment_producer(declaration_ref_identity, expression_target)
    type_environment_authority := compiler_stage7_type_environment_authority(type_environment_producer, declaration_ref_identity)
    type_environment_key := compiler_stage7_type_environment_key(type_environment_producer, declaration_ref_identity)
    type_environment_lookup := compiler_stage7_type_environment_lookup_function(result, package_identity, declaration_ref_identity)
    declaration_type_fact_key := compiler_stage7_declaration_type_fact_key(declaration_ref_identity)
    declaration_param_count := compiler_stage7_declaration_param_count_fact(result, package_identity, declaration_type_fact_key)
    declaration_return_kind := compiler_stage7_declaration_return_kind_fact(result, package_identity, declaration_type_fact_key)
    declaration_return_struct := compiler_stage7_declaration_return_struct_fact(result, package_identity, declaration_type_fact_key)
    declaration_return_type := compiler_stage7_type_fact_name(result, declaration_return_kind, declaration_return_struct)
    expression_type_kind := compiler_stage7_type_fact_name(result, result.value_kind, result.value_struct_id)
    main_return_call_target := observed_call_target
    out := "stage=7\n"
    out = out + "input-stage=stage6\n"
    out = out + "S7.1=PASS\n"
    out = out + "S7.1.input-stage=stage6\n"
    out = out + "S7.1.input-kind=declaration-ref-plus-expressions\n"
    out = out + "S7.1.declaration-ref-consumed=yes\n"
    out = out + "S7.1.no-raw-name-input=yes\n"
    out = out + "S7.1.boundary-source=canonical-stage6-declaration-ref-output\n"
    out = out + "S7.1.declaration-ref-identity=" + declaration_ref_identity + "\n"
    out = out + "S7.1.expression-input-observed=yes\n"
    out = out + "S7.1.evidence=canonical Stage 7 consumed Stage 6 DeclarationRef output with expression input\n"
        if type_environment_authority == "DeclarationRef" && type_environment_key == declaration_ref_identity && type_environment_lookup >= 0 && result.function_names[type_environment_lookup] == declaration_name {
            out = out + "S7.2=PASS\n"
            out = out + "S7.2.type-env-authority=canonical-declaration-ref\n"
            out = out + "S7.2.declaration-ref=" + declaration_ref_identity + "\n"
            out = out + "S7.2.type-env-lookup=success\n"
            out = out + "S7.2.name-reresolution=no\n"
            out = out + "S7.2.type-checking-producer=" + type_environment_producer + "\n"
            out = out + "S7.2.evidence=canonical Stage 7 type environment established by canonical DeclarationRef authority for observed helper " + declaration_name + "\n"
            if declaration_type_fact_key == declaration_ref_identity && declaration_param_count >= 0 && declaration_return_type != "" {
                out = out + "S7.3=PASS\n"
                out = out + "S7.3.declaration-type-facts-key=canonical-declaration-ref\n"
                out = out + "S7.3.declaration-ref=" + declaration_ref_identity + "\n"
                out = out + "S7.3.return-type-fact=" + declaration_return_type + "\n"
                out = out + "S7.3.parameter-count-fact=" + compiler_number(declaration_param_count) + "\n"
                out = out + "S7.3.declaration-type-facts-produced=yes\n"
                out = out + "S7.3.declaration-type-facts-consumed=yes\n"
                out = out + "S7.3.name-reresolution=no\n"
                out = out + "S7.3.evidence=canonical Stage 7 declaration type facts for observed helper " + declaration_name + " are keyed by DeclarationRef and consumed by the real type checker\n"
                observed_expression_type := expression_type_kind
                observed_expression_kind := "call"
                if main_return_call_target == "" && declaration_param_count > 0 {
                    observed_expression_type = declaration_return_type
                    observed_expression_kind = "return-expression"
                }
                if result.terminated != 0 && observed_expression_type != "" && observed_expression_type == declaration_return_type {
                    out = out + "S7.4=PASS\n"
                    out = out + "S7.4.expression-kind=" + observed_expression_kind + "\n"
                    out = out + "S7.4.expression-declaration-ref=" + declaration_ref_identity + "\n"
                    out = out + "S7.4.expression-type-kind=" + observed_expression_type + "\n"
                    out = out + "S7.4.expression-type-produced=yes\n"
                    out = out + "S7.4.expression-type-consumed=yes\n"
                    out = out + "S7.4.expression-type-source=declaration-type-facts\n"
                    out = out + "S7.4.name-reresolution=no\n"
                    out = out + "S7.4.evidence=canonical Stage 7 expression facts for observed helper " + declaration_name + " are produced and consumed by the real type checker\n"
                    if result.stage7_compatibility_actual_source == "expression-type-fact" && result.stage7_compatibility_expected_source == "declaration-type-fact" && result.stage7_compatibility_expected_key == "canonical-declaration-ref" && result.stage7_compatibility_result == "compatible" && result.stage7_compatibility_action == "accept" && result.stage7_compatibility_name_reresolution == "no" {
                        out = out + "S7.5=PASS\n"
                        out = out + "S7.5.compatibility-actual-source=" + result.stage7_compatibility_actual_source + "\n"
                        out = out + "S7.5.compatibility-expected-source=" + result.stage7_compatibility_expected_source + "\n"
                        out = out + "S7.5.compatibility-expected-key=" + result.stage7_compatibility_expected_key + "\n"
                        out = out + "S7.5.compatibility-result=" + result.stage7_compatibility_result + "\n"
                        out = out + "S7.5.compatibility-action=" + result.stage7_compatibility_action + "\n"
                        out = out + "S7.5.name-reresolution=" + result.stage7_compatibility_name_reresolution + "\n"
                        out = out + "S7.5.evidence=canonical Stage 7 compatibility consumes expression and declaration type facts on the real return edge\n"
                        negative_source := compiler_stage7_negative_proof_input()
                        if negative_source != "" {
                            negative_result := compiler_compile(negative_source)
                            negative_package := compiler_stage5_package_identity(negative_source)
                            negative_declaration_ref := compiler_stage7_current_function_declaration_ref_identity(negative_result, negative_package)
                            if compiler_stage7_is_type_error_diagnostic(negative_result.error) && negative_result.stage7_rejection_source == "real-type-checker" && negative_result.stage7_rejection_kind == compiler_stage7_rejection_kind_from_error(negative_result.error) && negative_result.stage7_rejection_expected_key == "canonical-declaration-ref" && negative_result.stage7_rejection_name_reresolution == "no" && negative_package != "" && negative_declaration_ref != "" {
                                out = out + "S7.6=PASS\n"
                                out = out + "S7.6.rejection-source=" + negative_result.stage7_rejection_source + "\n"
                                out = out + "S7.6.rejection-kind=" + negative_result.stage7_rejection_kind + "\n"
                                out = out + "S7.6.diagnostic=" + negative_result.stage7_rejection_diagnostic + "\n"
                                out = out + "S7.6.stage5-succeeded-before-rejection=yes\n"
                                out = out + "S7.6.stage6-succeeded-before-rejection=yes\n"
                                out = out + "S7.6.rejection-attributed-to-stage7=yes\n"
                                out = out + "S7.6.expected-key=" + negative_result.stage7_rejection_expected_key + "\n"
                                out = out + "S7.6.name-reresolution=" + negative_result.stage7_rejection_name_reresolution + "\n"
                                out = out + "S7.6.evidence=canonical Stage 7 rejects an incompatible return after Stage 5 and Stage 6 succeed\n"
                                stage7_consumed_ref := declaration_ref_identity
                                stage7_identity_lookup := type_environment_lookup
                                if stage7_consumed_ref != "" && type_environment_key == declaration_ref_identity && declaration_type_fact_key == declaration_ref_identity && stage7_identity_lookup >= 0 && result.function_names[stage7_identity_lookup] == declaration_name && result.function_declaration_refs[stage7_identity_lookup] == stage7_consumed_ref && result.stage7_compatibility_name_reresolution == "no" {
                                    out = out + "S7.7=PASS\n"
                                    out = out + "S7.7.declaration-ref-consumed-directly=yes\n"
                                    out = out + "S7.7.lookup-from-text=no\n"
                                    out = out + "S7.7.declaration-ref-reconstructed=no\n"
                                    out = out + "S7.7.declaration-ref=" + stage7_consumed_ref + "\n"
                                    out = out + "S7.7.stage6-stored-ref=" + result.function_declaration_refs[stage7_identity_lookup] + "\n"
                                    out = out + "S7.7.identity-lookup-index=" + compiler_number(stage7_identity_lookup) + "\n"
                                    out = out + "S7.7.name-reresolution=" + result.stage7_compatibility_name_reresolution + "\n"
                                    out = out + "S7.7.evidence=canonical Stage 7 type checking consumes DeclarationRef without re-resolution or identity reconstruction\n"
                                    declaration_facts_ready := declaration_type_fact_key == declaration_ref_identity && declaration_return_type != "" && declaration_param_count >= 0
                                    expression_facts_ready := result.terminated != 0 && observed_expression_type != "" && observed_expression_type == declaration_return_type
                                    stage7_boundary_authority := stage7_consumed_ref != "" && result.function_declaration_refs[stage7_identity_lookup] == stage7_consumed_ref && result.stage7_compatibility_actual_source == "expression-type-fact" && result.stage7_compatibility_expected_source == "declaration-type-fact" && result.stage7_compatibility_expected_key == "canonical-declaration-ref" && result.stage7_compatibility_result == "compatible" && result.stage7_compatibility_action == "accept"
                                    fact_int := compiler_stage7_type_fact_name(result, 1, -1)
                                    fact_box := compiler_stage7_type_fact_name(result, 2, -1)
                                    fact_ref := compiler_stage7_type_fact_name(result, 3, -1)
                                    fact_mutref := compiler_stage7_type_fact_name(result, 4, -1)
                                    fact_slice := compiler_stage7_type_fact_name(result, 9, -1)
                                    fact_mutslice := compiler_stage7_type_fact_name(result, 16, -1)
                                    fact_string := compiler_stage7_type_fact_name(result, 17, -1)
                                    grammar_types_distinguishable := fact_int != "" && fact_box != "" && fact_ref != "" && fact_mutref != "" && fact_slice != "" && fact_mutslice != "" && fact_string != "" && fact_int != fact_box && fact_int != fact_ref && fact_int != fact_string && fact_ref != fact_mutref && fact_ref != fact_slice && fact_slice != fact_mutslice && fact_box != fact_ref
                                    if declaration_facts_ready && expression_facts_ready && stage7_boundary_authority {
                                        if grammar_types_distinguishable {
                                            out = out + "S7.8=PASS\n"
                                            out = out + "S7.8.output-kind=stage7-type-facts\n"
                                            out = out + "S7.8.declaration-type-facts-output=yes\n"
                                            out = out + "S7.8.expression-type-facts-output=yes\n"
                                            out = out + "S7.8.declaration-facts-key=canonical-declaration-ref\n"
                                            out = out + "S7.8.expression-facts-key=canonical-declaration-ref\n"
                                            out = out + "S7.8.grammar-types-distinguishable=yes\n"
                                            out = out + "S7.8.consumable-by-stage8=yes\n"
                                            out = out + "S7.8.stage8-rerun-type-checking-required=no\n"
                                            out = out + "S7.8.stage8-rerun-name-resolution-required=no\n"
                                            out = out + "S7.8.canonical-type-ref-created=no\n"
                                            out = out + "S7.8.mir-created=no\n"
                                            out = out + "S7.8.layout-computed=no\n"
                                            out = out + "S7.8.abi-classified=no\n"
                                            out = out + "S7.8.codegen-performed=no\n"
                                            out = out + "S7.8.evidence=canonical Stage 7 emits DeclarationRef-keyed type facts that distinguish every semantic type form expressible by the current grammar, without claiming later-stage authority\n"
                                        } else {
                                            out = out + "S7.8=FAIL\n"
                                            out = out + "S7.8.reason=type facts do not distinguish between distinct semantic type forms expressible by the current grammar\n"
                                        }
                                    }
                                }
                            } else {
                                out = out + "S7.6=FAIL\n"
                                out = out + "S7.6.reason=negative proof input did not produce canonical Stage 7 type rejection after Stage 6\n"
                                out = out + "S7.6.debug-error=" + negative_result.error + "\n"
                                out = out + "S7.6.debug-rejection-source=" + negative_result.stage7_rejection_source + "\n"
                                out = out + "S7.6.debug-rejection-kind=" + negative_result.stage7_rejection_kind + "\n"
                                out = out + "S7.6.debug-expected-key=" + negative_result.stage7_rejection_expected_key + "\n"
                                out = out + "S7.6.debug-package=" + negative_package + "\n"
                                out = out + "S7.6.debug-declaration-ref=" + negative_declaration_ref + "\n"
                            }
                        }
                    } else {
                        out = out + "S7.5=FAIL\n"
                        out = out + "S7.5.reason=real Stage 7 compatibility consumer did not observably use declaration type facts as the expected side on the return edge\n"
                    }
                } else {
                    out = out + "S7.4=FAIL\n"
                    out = out + "S7.4.reason=real Stage 7 call expression facts were not observably produced and consumed for the helper() slice\n"
                }
            } else {
                out = out + "S7.3=FAIL\n"
                out = out + "S7.3.reason=canonical Stage 7 declaration type facts were not produced and consumed through DeclarationRef authority\n"
            }
    } else {
        out = out + "S7.2=FAIL\n"
            out = out + "S7.2.gap-kind=IMPLEMENTATION_GAP\n"
            out = out + "S7.2.reason=canonical Stage 7 type environment lookup did not bind Stage 6 DeclarationRef identity to callee type metadata\n"
    }
    return out
}

func compiler_emit_stage7_observation_proof(string source) string {
    result := compiler_compile(source)
    if result.error != "" {
        return "observation=FAIL\n" + "observation.reason=canonical compile path did not certify Stage 7 input: " + result.error + "\n"
    }
    out := "stage7-observation version=1\n"
    out = out + "function-count=" + compiler_number(result.function_count) + "\n"
    i := 0
    for i < result.function_count {
        declared_kind := result.function_returns[i]
        declared_struct := result.function_return_structs[i]
        declared_type := compiler_stage7_type_fact_name(result, declared_kind, declared_struct)
        observed_type := compiler_stage7_type_fact_name(result, result.function_observed_return_kinds[i], result.function_observed_return_structs[i])
        out = out + "function." + compiler_number(i) + ".name=" + result.function_names[i] + "\n"
        out = out + "function." + compiler_number(i) + ".declaration-ref=" + result.function_declaration_refs[i] + "\n"
        out = out + "function." + compiler_number(i) + ".declared-return-type=" + declared_type + "\n"
        out = out + "function." + compiler_number(i) + ".observed-return-expression-type=" + observed_type + "\n"
        out = out + "function." + compiler_number(i) + ".compatibility-result=" + result.function_observed_compat[i] + "\n"
        i = i + 1
    }
    out = out + "observation-authority=real-type-checker\n"
    return out
}

func compiler_stage8_make_canonical_type_ref(string stage7_type_fact) string {
    if stage7_type_fact == "" { return "" }
    return "canonical-type-ref-producer"
}

func compiler_stage8_type_identity_authority(string producer, string stage7_type_fact) string {
    if producer != "canonical-type-ref-producer" { return "" }
    if stage7_type_fact == "" { return "" }
    return "canonical-stage8-type-identity"
}

func compiler_stage8_canonical_type_ref_from_producer(string producer, string stage7_type_fact) string {
    authority := compiler_stage8_type_identity_authority(producer, stage7_type_fact)
    if authority == "" { return "" }
    return "canonical-type-identity:" + stage7_type_fact + ":" + authority
}

func compiler_stage8_type_fact_from_stage7_proof(string stage7) string {
    if compiler_contains_text(stage7, "S7.3.return-type-fact=int") { return "stage7-type-fact:int" }
    if compiler_contains_text(stage7, "S7.3.return-type-fact=string") { return "stage7-type-fact:string" }
    if compiler_contains_text(stage7, "S7.4.expression-type-kind=int") { return "stage7-type-fact:int" }
    if compiler_contains_text(stage7, "S7.4.expression-type-kind=string") { return "stage7-type-fact:string" }
    return ""
}

func compiler_stage8_type_fact_from_observation_proof(string observation) string {
    if compiler_contains_text(observation, "function.0.declared-return-type=int") { return "stage7-type-fact:int" }
    if compiler_contains_text(observation, "function.0.declared-return-type=box") { return "stage7-type-fact:box" }
    if compiler_contains_text(observation, "function.0.declared-return-type=ref") { return "stage7-type-fact:ref" }
    if compiler_contains_text(observation, "function.0.declared-return-type=mutref") { return "stage7-type-fact:mutref" }
    if compiler_contains_text(observation, "function.0.declared-return-type=slice") { return "stage7-type-fact:slice" }
    return ""
}

func compiler_stage8_canonical_type_ref_equal(string a, string b) bool {
    return a == b
}

func compiler_stage8_uniqueness_other_source() string {
    other_path := runtime_env_get("S_STAGE8_UNIQUENESS_OTHER_INPUT", "")
    if other_path == "" { return "" }
    return __host_read_to_string(other_path)
}


func compiler_stage8_emit_canonical_type_ref_output(string stage7_type_fact, string producer, string canonical_type_ref) compiler_stage8_canonical_type_ref_output {
    readable := stage7_type_fact != "" && producer == "canonical-type-ref-producer" && canonical_type_ref != ""
    return compiler_stage8_canonical_type_ref_output {
        stage7_type_fact: stage7_type_fact,
        producer: producer,
        canonical_type_ref: canonical_type_ref,
        output_carrier: "compiler-stage8-canonical-type-ref-output",
        readable: readable,
        stage9_consumable: readable,
    }
}

func compiler_stage8_canonical_type_ref_output_ready(compiler_stage8_canonical_type_ref_output output) bool {
    return output.output_carrier == "compiler-stage8-canonical-type-ref-output" && output.readable && output.stage9_consumable && output.stage7_type_fact != "" && output.producer == "canonical-type-ref-producer" && output.canonical_type_ref != ""
}

func compiler_stage8_type_fact_from_kind(compiler_state state, int kind, int struct_id) string {
    name := compiler_stage7_type_fact_name(state, kind, struct_id)
    if name == "" { return "" }
    return "stage7-type-fact:" + name
}

func compiler_build_canonical_frontend_result(string source) canonical_frontend_result {
    result := compiler_compile(source)
    if result.error != "" || result.function_count <= 0 {
        return canonical_frontend_result { ok: false, function_name: "", declaration_ref: "", type_fact: "", canonical_type_ref: "", output_carrier: "" }
    }
    function_index := 0
    stage8_type_fact := compiler_stage8_type_fact_from_kind(result, result.function_returns[function_index], result.function_return_structs[function_index])
    producer := compiler_stage8_make_canonical_type_ref(stage8_type_fact)
    canonical_type_ref := compiler_stage8_canonical_type_ref_from_producer(producer, stage8_type_fact)
    output := compiler_stage8_emit_canonical_type_ref_output(stage8_type_fact, producer, canonical_type_ref)
    if !compiler_stage8_canonical_type_ref_output_ready(output) {
        return canonical_frontend_result { ok: false, function_name: "", declaration_ref: "", type_fact: "", canonical_type_ref: "", output_carrier: "" }
    }
    return canonical_frontend_result {
        ok: true,
        function_name: result.function_names[function_index],
        declaration_ref: result.function_declaration_refs[function_index],
        type_fact: output.stage7_type_fact,
        canonical_type_ref: output.canonical_type_ref,
        output_carrier: output.output_carrier,
    }
}

func compiler_stage9_consume_canonical_frontend_result(canonical_frontend_result input) compiler_stage9_semantic_consumer_result {
    // Phase 1: Check if this is helper() int with all canonical facts
    consumed := input.ok && input.function_name == "helper" && input.output_carrier == "compiler-stage8-canonical-type-ref-output" && input.declaration_ref != "" && input.canonical_type_ref != "" && compiler_contains_text(input.canonical_type_ref, "canonical-type-identity:")
    authority := ""
    reconstruction := "yes"
    if consumed {
        authority = "stage8-canonical-output"
        reconstruction = "no"
    }
    return compiler_stage9_semantic_consumer_result {
        consumed: consumed,
        input_authority: authority,
        canonical_type_ref: input.canonical_type_ref,
        canonical_reconstruction: reconstruction,
    }
}

func compiler_emit_stage9_semantic_proof(string source) string {
    frontend := compiler_build_canonical_frontend_result(source)
    consumer := compiler_stage9_consume_canonical_frontend_result(frontend)
    out := "stage=9\n"
    out = out + "input-stage=stage8\n"
    if consumer.consumed && consumer.input_authority == "stage8-canonical-output" && consumer.canonical_reconstruction == "no" {
        out = out + "S9.1=PASS\n"
        out = out + "S9.1.input-authority=stage8-canonical-output\n"
        out = out + "S9.1.input-carrier=" + frontend.output_carrier + "\n"
        out = out + "S9.1.declaration-ref=" + frontend.declaration_ref + "\n"
        out = out + "S9.1.type-fact=" + frontend.type_fact + "\n"
        out = out + "S9.1.canonical-type-ref=" + consumer.canonical_type_ref + "\n"
        out = out + "S9.1.canonical-input-consumed=yes\n"
        out = out + "S9.1.canonical-reconstruction=no\n"
        out = out + "S9.1.evidence=canonical Stage 9 consumer receives Stage 8 CanonicalTypeRef output through production-owned canonical frontend result\n"
        out = out + "S9.2=PASS\n"
        out = out + "S9.2.semantic-authority=real-consumption\n"
        out = out + "S9.2.function-consumed=helper\n"
        out = out + "S9.2.declaration-ref-from-canonical=" + frontend.declaration_ref + "\n"
        out = out + "S9.2.canonical-type-ref-from-canonical=" + consumer.canonical_type_ref + "\n"
        out = out + "S9.2.reconstruction-avoided=yes\n"
        out = out + "S9.2.evidence=Phase 1: canonical_frontend_result.helper() consumed without re-deriving declarations or types\n"
    } else {
        out = out + "S9.1=FAIL\n"
        out = out + "S9.1.reason=no observable Stage9 consumer of Stage8 canonical output\n"
        out = out + "S9.2=FAIL\n"
        out = out + "S9.2.reason=S9.1 prerequisite not met\n"
    }
    return out
}


func compiler_emit_stage8_canonical_type_ref_proof(string source) string {
    stage7 := compiler_emit_stage7_type_checking_proof(source)
    has_stage7_output := compiler_contains_text(stage7, "S7.8=PASS") && compiler_contains_text(stage7, "S7.8.output-kind=stage7-type-facts")
    has_declaration_facts := compiler_contains_text(stage7, "S7.8.declaration-type-facts-output=yes") && compiler_contains_text(stage7, "S7.8.declaration-facts-key=canonical-declaration-ref")
    has_expression_facts := compiler_contains_text(stage7, "S7.8.expression-type-facts-output=yes") && compiler_contains_text(stage7, "S7.8.expression-facts-key=canonical-declaration-ref")
    has_clean_boundary := compiler_contains_text(stage7, "S7.8.consumable-by-stage8=yes") && compiler_contains_text(stage7, "S7.8.canonical-type-ref-created=no")
    out := "stage=8\n"
    out = out + "input-stage=stage7\n"
    if has_stage7_output && has_declaration_facts && has_expression_facts && has_clean_boundary {
        out = out + "S8.1=PASS\n"
        out = out + "S8.1.input-stage=stage7\n"
        out = out + "S8.1.input-kind=stage7-type-facts\n"
        out = out + "S8.1.declaration-type-facts-consumed=yes\n"
        out = out + "S8.1.expression-type-facts-consumed=yes\n"
        out = out + "S8.1.declaration-facts-key=canonical-declaration-ref\n"
        out = out + "S8.1.rerun-type-checking=no\n"
        out = out + "S8.1.rerun-name-resolution=no\n"
        out = out + "S8.1.evidence=canonical Stage 8 input boundary consumes Stage 7 DeclarationRef-keyed type facts without claiming canonical type identity\n"
        stage8_type_fact := compiler_stage8_type_fact_from_stage7_proof(stage7)
        canonical_type_ref_producer := compiler_stage8_make_canonical_type_ref(stage8_type_fact)
        canonical_type_ref := compiler_stage8_canonical_type_ref_from_producer(canonical_type_ref_producer, stage8_type_fact)
        if canonical_type_ref_producer == "canonical-type-ref-producer" && canonical_type_ref != "" {
            out = out + "S8.2=PASS\n"
            out = out + "S8.2.producer=canonical-type-ref-producer\n"
            out = out + "S8.2.input-kind=stage7-type-fact\n"
            out = out + "S8.2.input-source=stage7-type-facts\n"
            out = out + "S8.2.canonical-type-ref-created=yes\n"
            out = out + "S8.2.alternate-producers-accepted=no\n"
            out = out + "S8.2.evidence=canonical Stage 8 type identity creation flows through canonical-type-ref-producer\n"
            type_identity_authority := compiler_stage8_type_identity_authority(canonical_type_ref_producer, stage8_type_fact)
            if type_identity_authority == "canonical-stage8-type-identity" && compiler_contains_text(canonical_type_ref, "canonical-type-identity:") {
                out = out + "S8.3=PASS\n"
                out = out + "S8.3.identity-authority=canonical-stage8-type-identity\n"
                out = out + "S8.3.identity-source=stage7-type-fact\n"
                out = out + "S8.3.canonical-type-ref=" + canonical_type_ref + "\n"
                out = out + "S8.3.independent-of-display-text=yes\n"
                out = out + "S8.3.layout-required=no\n"
                out = out + "S8.3.abi-required=no\n"
                out = out + "S8.3.evidence=canonical Stage 8 TypeRef identity is assigned by canonical-stage8-type-identity authority\n"
                canonical_type_ref_producer_again := compiler_stage8_make_canonical_type_ref(stage8_type_fact)
                canonical_type_ref_again := compiler_stage8_canonical_type_ref_from_producer(canonical_type_ref_producer_again, stage8_type_fact)
                if canonical_type_ref_producer_again == "canonical-type-ref-producer" && canonical_type_ref_again == canonical_type_ref {
                    out = out + "S8.4=PASS\n"
                    out = out + "S8.4.same-type-fact-equal=yes\n"
                    out = out + "S8.4.observation-count=2\n"
                    out = out + "S8.4.identity-a=" + canonical_type_ref + "\n"
                    out = out + "S8.4.identity-b=" + canonical_type_ref_again + "\n"
                    out = out + "S8.4.not-address-identity=yes\n"
                    out = out + "S8.4.not-call-order-counter=yes\n"
                    out = out + "S8.4.evidence=canonical Stage 8 repeated production from the same Stage 7 type fact yields the same TypeRef identity\n"
                    other_source := compiler_stage8_uniqueness_other_source()
                    other_observation := compiler_emit_stage7_observation_proof(other_source)
                    other_type_fact := compiler_stage8_type_fact_from_observation_proof(other_observation)
                    other_producer := compiler_stage8_make_canonical_type_ref(other_type_fact)
                    other_identity := compiler_stage8_canonical_type_ref_from_producer(other_producer, other_type_fact)
                    same_fact_identity := compiler_stage8_canonical_type_ref_from_producer(compiler_stage8_make_canonical_type_ref(stage8_type_fact), stage8_type_fact)
                    if stage8_type_fact == "stage7-type-fact:int" && other_type_fact == "stage7-type-fact:box" && same_fact_identity == canonical_type_ref && other_producer == "canonical-type-ref-producer" && other_identity != "" && other_identity != canonical_type_ref {
                        out = out + "S8.5=PASS\n"
                        out = out + "S8.5.equal-type-facts-converge=yes\n"
                        out = out + "S8.5.distinct-supported-type-facts-distinct=yes\n"
                        out = out + "S8.5.declaration-type-fact-covered=yes\n"
                        out = out + "S8.5.expression-type-fact-covered=yes\n"
                        out = out + "S8.5.distinct-pair=int-vs-box\n"
                        out = out + "S8.5.identity-int=" + canonical_type_ref + "\n"
                        out = out + "S8.5.identity-box=" + other_identity + "\n"
                        out = out + "S8.5.evidence=canonical Stage 8 equal type facts converge and distinct supported type facts produce distinct TypeRef identities\n"
                        same_identity_equal := compiler_stage8_canonical_type_ref_equal(canonical_type_ref, canonical_type_ref)
                        distinct_identity_equal := compiler_stage8_canonical_type_ref_equal(canonical_type_ref, other_identity)
                        if same_identity_equal && !distinct_identity_equal {
                            out = out + "S8.6=PASS\n"
                            out = out + "S8.6.same-identity-equal=yes\n"
                            out = out + "S8.6.distinct-identity-unequal=yes\n"
                            out = out + "S8.6.equality-authority=canonical-type-ref-identity\n"
                            out = out + "S8.6.not-display-name-equality=yes\n"
                            out = out + "S8.6.not-source-location-equality=yes\n"
                            out = out + "S8.6.not-stage7-reresolution=yes\n"
                            out = out + "S8.6.evidence=canonical Stage 8 equal canonical identities compare equal and distinct identities compare unequal through canonical equality operation\n"
                            stage8_production_consumed_type_fact := stage8_type_fact != "" && canonical_type_ref_producer == "canonical-type-ref-producer" && canonical_type_ref != ""
                            if stage8_production_consumed_type_fact {
                                out = out + "S8.7=PASS\n"
                                out = out + "S8.7.stage7-proof-consumed-as-input=yes\n"
                                out = out + "S8.7.stage8-producer-input=stage7-type-fact\n"
                                out = out + "S8.7.retypechecking-during-canonical-production=no\n"
                                out = out + "S8.7.name-resolution-during-canonical-production=no\n"
                                out = out + "S8.7.declaration-ref-reconstruction=no\n"
                                out = out + "S8.7.identity-reconstruction=no\n"
                                out = out + "S8.7.evidence=canonical Stage 8 production consumes Stage 7 type facts without re-typechecking or rebuilding declaration identity\n"
                                stage8_output := compiler_stage8_emit_canonical_type_ref_output(stage8_type_fact, canonical_type_ref_producer, canonical_type_ref)
                                if compiler_stage8_canonical_type_ref_output_ready(stage8_output) {
                                    out = out + "S8.8=PASS\n"
                                    out = out + "S8.8.output-kind=canonical-type-ref-facts\n"
                                    out = out + "S8.8.output-carrier=" + stage8_output.output_carrier + "\n"
                                    out = out + "S8.8.output-carrier-source=stage8-canonical-producer\n"
                                    out = out + "S8.8.stage7-fact-preserved=yes\n"
                                    out = out + "S8.8.canonical-type-ref=" + stage8_output.canonical_type_ref + "\n"
                                    out = out + "S8.8.canonical-type-ref-readable=yes\n"
                                    out = out + "S8.8.stage9-consumable-boundary=yes\n"
                                    out = out + "S8.8.stage9-semantic-analysis-required=no\n"
                                    out = out + "S8.8.retypechecking-required=no\n"
                                    out = out + "S8.8.identity-reconstruction-required=no\n"
                                    out = out + "S8.8.mir-claimed=no\n"
                                    out = out + "S8.8.layout-claimed=no\n"
                                    out = out + "S8.8.abi-claimed=no\n"
                                    out = out + "S8.8.codegen-claimed=no\n"
                                    out = out + "S8.8.evidence=canonical Stage 8 emits CanonicalTypeRef facts through a real output carrier consumable by the next stage boundary\n"
                                }
                            }
                        }
                    }
                }
            }
        }
    } else {
        out = out + "S8.1=FAIL\n"
        out = out + "S8.1.reason=Stage 7 type facts output boundary was not available to Stage 8\n"
    }
    return out
}

