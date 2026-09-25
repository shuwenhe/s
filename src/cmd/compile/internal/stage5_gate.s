package compile.internal.semantic

import (
    "s"
    "std"
    "std.prelude"
)

// ============================================================
// Stage 5: Name Resolution Authority Gate
// ============================================================
// Purpose: Verify that every identifier in the canonical closure
// can be resolved to at least one declaration (and qualified names
// resolve to exactly one).
// ============================================================

struct name_resolution_candidate {
    string package_path
    string name
    string kind              // "function", "const", "struct", "trait", "local"
    string source_location   // For debugging
}

struct identifier_resolution {
    string identifier_text
    bool is_qualified       // true if std.env.args, false if args
    name_resolution_candidate[] candidates
    int errors
    string resolution_status  // "resolved_exact", "resolved_ambiguous", "unresolved"
}

struct name_resolution_gate_result {
    int total_identifiers
    int resolved_exact
    int resolved_ambiguous
    int unresolved
    int qualified_with_multiple_matches
    identifier_resolution[] details
    int gate_pass  // 1 if PASS, 0 if FAIL
}

// ============================================================
// Gate Entry Point
// ============================================================

func canonical_name_resolution_check(source_file file, function_binding[] functions, trait_binding[] traits, const_binding[] consts, struct_binding[] structs) name_resolution_gate_result {
    result := name_resolution_gate_result {
        total_identifiers: 0,
        resolved_exact: 0,
        resolved_ambiguous: 0,
        unresolved: 0,
        qualified_with_multiple_matches: 0,
        details: identifier_resolution[](),
        gate_pass: 1,
    }
    
    // Collect all identifiers from AST
    all_identifiers := collect_all_identifiers_from_items(file.items)
    
    result.total_identifiers = std.prelude.len(all_identifiers)
    
    // Resolve each identifier
    i := 0
    for i < std.prelude.len(all_identifiers) {
        id := all_identifiers[i]
        resolution := resolve_identifier_to_candidates(id.identifier_text, id.is_qualified, file.pkg, functions, traits, consts, structs)
        
        result.details = append(result.details, resolution)
        
        if resolution.resolution_status == "resolved_exact" {
            result.resolved_exact = result.resolved_exact + 1
        } else if resolution.resolution_status == "resolved_ambiguous" {
            result.resolved_ambiguous = result.resolved_ambiguous + 1
        } else if resolution.resolution_status == "unresolved" {
            result.unresolved = result.unresolved + 1
            result.gate_pass = 0
        }
        
        // Qualified names should resolve to exactly one
        if id.is_qualified && std.prelude.len(resolution.candidates) > 1 {
            result.qualified_with_multiple_matches = result.qualified_with_multiple_matches + 1
            result.gate_pass = 0
        }
        
        i = i + 1
    }
    
    result
}

// ============================================================
// Identifier Collection
// ============================================================

struct identifier_info {
    string identifier_text
    bool is_qualified
}

func collect_all_identifiers_from_items(item[] items) identifier_info[] {
    identifiers := identifier_info[]()
    
    i := 0
    for i < std.prelude.len(items) {
        identifiers_from_item := collect_identifiers_from_item(items[i])
        j := 0
        for j < std.prelude.len(identifiers_from_item) {
            identifiers = append(identifiers, identifiers_from_item[j])
            j = j + 1
        }
        i = i + 1
    }
    
    identifiers
}

func collect_identifiers_from_item(item it) identifier_info[] {
    identifiers := identifier_info[]()
    
    switch it {
        item::function(function_decl) : {
            identifiers = append_from_function_body(identifiers, function_decl.body)
        }
        item::method(method_decl) : {
            identifiers = append_from_function_body(identifiers, method_decl.method.body)
        }
        item::const(const_decl) : {
            switch const_decl.value {
                s.option::some(expr_val) : {
                    identifiers = append_from_expr(identifiers, expr_val)
                }
                s.option::none : {}
            }
        }
        _ : {}
    }
    
    identifiers
}

func append_from_function_body(identifier_info[] acc, s.option[s.block] body) identifier_info[] {
    switch body {
        s.option::some(block_val) : {
            return append_from_block(acc, block_val)
        }
        s.option::none : {}
    }
    acc
}

func append_from_block(identifier_info[] acc, s.block blk) identifier_info[] {
    i := 0
    for i < std.prelude.len(blk.statements) {
        acc = append_from_stmt(acc, blk.statements[i])
        i = i + 1
    }
    
    switch blk.final_expr {
        s.option::some(expr_val) : {
            acc = append_from_expr(acc, expr_val)
        }
        s.option::none : {}
    }
    
    acc
}

func append_from_stmt(identifier_info[] acc, s.stmt st) identifier_info[] {
    switch st {
        s.stmt::let(let_val) : {
            switch let_val.value {
                s.option::some(expr_val) : {
                    acc = append_from_expr(acc, expr_val)
                }
                s.option::none : {}
            }
        }
        s.stmt::assign(assign_val) : {
            acc = append_from_expr(acc, assign_val.target)
            acc = append_from_expr(acc, assign_val.value)
        }
        s.stmt::if_stmt(if_val) : {
            acc = append_from_expr(acc, if_val.condition)
            acc = append_from_block(acc, if_val.then_block)
            switch if_val.else_block {
                s.option::some(else_blk) : {
                    acc = append_from_block(acc, else_blk)
                }
                s.option::none : {}
            }
        }
        s.stmt::while_stmt(while_val) : {
            acc = append_from_expr(acc, while_val.condition)
            acc = append_from_block(acc, while_val.body)
        }
        s.stmt::for_stmt(for_val) : {
            acc = append_from_expr(acc, for_val.iterable)
            acc = append_from_block(acc, for_val.body)
        }
        s.stmt::return_stmt(return_val) : {
            switch return_val.value {
                s.option::some(expr_val) : {
                    acc = append_from_expr(acc, expr_val)
                }
                s.option::none : {}
            }
        }
        s.stmt::switch_stmt(switch_val) : {
            acc = append_from_expr(acc, switch_val.target)
            i := 0
            for i < std.prelude.len(switch_val.arms) {
                acc = append_from_expr(acc, switch_val.arms[i].pattern_expr)
                acc = append_from_block(acc, switch_val.arms[i].body)
                i = i + 1
            }
        }
        _ : {}
    }
    
    acc
}

func append_from_expr(identifier_info[] acc, s.expr e) identifier_info[] {
    switch e {
        s.expr::name(name_val) : {
            // Simple identifier
            acc = append(acc, identifier_info {
                identifier_text: name_val.name,
                is_qualified: false,
            })
        }
        s.expr::member(member_val) : {
            // Could be qualified: std.env.args
            path := qualified_expr_path_gate(member_val)
            if path != "" {
                acc = append(acc, identifier_info {
                    identifier_text: path,
                    is_qualified: true,
                })
            }
            acc = append_from_expr(acc, member_val.target.value)
        }
        s.expr::call(call_val) : {
            acc = append_from_expr(acc, call_val.callee.value)
            i := 0
            for i < std.prelude.len(call_val.args) {
                acc = append_from_expr(acc, call_val.args[i])
                i = i + 1
            }
        }
        s.expr::binary(binary_val) : {
            acc = append_from_expr(acc, binary_val.left.value)
            acc = append_from_expr(acc, binary_val.right.value)
        }
        s.expr::unary(unary_val) : {
            acc = append_from_expr(acc, unary_val.operand.value)
        }
        s.expr::index(index_val) : {
            acc = append_from_expr(acc, index_val.target.value)
            acc = append_from_expr(acc, index_val.index.value)
        }
        s.expr::borrow(borrow_val) : {
            acc = append_from_expr(acc, borrow_val.target.value)
        }
        s.expr::dereference(deref_val) : {
            acc = append_from_expr(acc, deref_val.target.value)
        }
        s.expr::cast(cast_val) : {
            acc = append_from_expr(acc, cast_val.target.value)
        }
        s.expr::struct_literal(struct_val) : {
            i := 0
            for i < std.prelude.len(struct_val.fields) {
                acc = append_from_expr(acc, struct_val.fields[i].value)
                i = i + 1
            }
        }
        s.expr::array_literal(array_val) : {
            i := 0
            for i < std.prelude.len(array_val.elements) {
                acc = append_from_expr(acc, array_val.elements[i])
                i = i + 1
            }
        }
        _ : {}
    }
    
    acc
}

// ============================================================
// Name Resolution
// ============================================================

func resolve_identifier_to_candidates(string identifier, bool is_qualified, string current_package, function_binding[] functions, trait_binding[] traits, const_binding[] consts, struct_binding[] structs) identifier_resolution {
    candidates := name_resolution_candidate[]()
    
    if is_qualified {
        // Qualified name: package.name or package.Type.method
        pkg_part := qualified_package_part(identifier)
        name_part := qualified_decl_part(identifier)
        
        // Look in functions
        matched_functions := lookup_qualified_functions(functions, pkg_part, name_part)
        i := 0
        for i < std.prelude.len(matched_functions) {
            candidates = append(candidates, name_resolution_candidate {
                package_path: matched_functions[i].package_path,
                name: matched_functions[i].name,
                kind: "function",
                source_location: "",
            })
            i = i + 1
        }
        
        // Look in consts
        i = 0
        for i < std.prelude.len(consts) {
            if consts[i].package_path == pkg_part && consts[i].name == name_part {
                candidates = append(candidates, name_resolution_candidate {
                    package_path: consts[i].package_path,
                    name: consts[i].name,
                    kind: "const",
                    source_location: "",
                })
            }
            i = i + 1
        }
        
        // Look in structs
        i = 0
        for i < std.prelude.len(structs) {
            if structs[i].package_path == pkg_part && structs[i].name == name_part {
                candidates = append(candidates, name_resolution_candidate {
                    package_path: structs[i].package_path,
                    name: structs[i].name,
                    kind: "struct",
                    source_location: "",
                })
            }
            i = i + 1
        }
        
    } else {
        // Unqualified name: just "args"
        // First check functions
        matched_functions := lookup_functions(functions, identifier)
        i := 0
        for i < std.prelude.len(matched_functions) {
            candidates = append(candidates, name_resolution_candidate {
                package_path: matched_functions[i].package_path,
                name: matched_functions[i].name,
                kind: "function",
                source_location: "",
            })
            i = i + 1
        }
        
        // Check consts
        i = 0
        for i < std.prelude.len(consts) {
            if consts[i].name == identifier {
                candidates = append(candidates, name_resolution_candidate {
                    package_path: consts[i].package_path,
                    name: consts[i].name,
                    kind: "const",
                    source_location: "",
                })
            }
            i = i + 1
        }
        
        // Check structs
        i = 0
        for i < std.prelude.len(structs) {
            if structs[i].name == identifier {
                candidates = append(candidates, name_resolution_candidate {
                    package_path: structs[i].package_path,
                    name: structs[i].name,
                    kind: "struct",
                    source_location: "",
                })
            }
            i = i + 1
        }
    }
    
    status := if std.prelude.len(candidates) == 0 { "unresolved" 
              } else if std.prelude.len(candidates) == 1 { "resolved_exact" 
              } else { "resolved_ambiguous" }
    
    identifier_resolution {
        identifier_text: identifier,
        is_qualified: is_qualified,
        candidates: candidates,
        errors: 0,
        resolution_status: status,
    }
}

// ============================================================
// Gate Reporting
// ============================================================

func print_name_resolution_gate_result(name_resolution_gate_result result) {
    std.prelude.println("canonical-name-resolution-check")
    std.prelude.println("  total-identifiers       = " + to_string(result.total_identifiers))
    std.prelude.println("  resolved-exact          = " + to_string(result.resolved_exact))
    std.prelude.println("  resolved-ambiguous      = " + to_string(result.resolved_ambiguous))
    std.prelude.println("  unresolved              = " + to_string(result.unresolved))
    std.prelude.println("  qualified-multi-match   = " + to_string(result.qualified_with_multiple_matches))
    
    if result.gate_pass == 1 {
        std.prelude.println("  result                  = PASS")
    } else {
        std.prelude.println("  result                  = FAIL")
        
        // Print first blocker
        i := 0
        for i < std.prelude.len(result.details) {
            if result.details[i].resolution_status != "resolved_exact" {
                std.prelude.println("  first-blocker           = " + result.details[i].identifier_text + " (" + result.details[i].resolution_status + ")")
                break
            }
            i = i + 1
        }
    }
}

// ============================================================
// Helper: Extract qualified path from member expression
// ============================================================

func qualified_expr_path_gate(s.expr_member member_val) string {
    switch member_val.target.value {
        s.expr::name(name_val) : {
            return name_val.name + "." + member_val.member
        }
        s.expr::member(nested_member) : {
            prefix := qualified_expr_path_gate(nested_member)
            if prefix != "" {
                return prefix + "." + member_val.member
            }
            return ""
        }
        _ : return ""
    }
}
