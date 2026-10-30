package compile.internal.semantic

import (
    "compile.internal.ast"
    "std.option"
    "std.io"
    "std"
    "std.prelude"
)

struct name_resolution_candidate {
    string package_path
    string name
    string kind              
    string source_location   
}

struct identifier_resolution {
    string identifier_text
    bool is_qualified       
    name_resolution_candidate[] candidates
    int errors
    string resolution_status  
}

struct name_resolution_gate_result {
    int total_identifiers
    int resolved_exact
    int resolved_ambiguous
    int unresolved
    int qualified_with_multiple_matches
    identifier_resolution[] details
    int gate_pass  
}

func canonical_name_resolution_check(compile.internal.ast.source_file file, function_binding[] functions, trait_binding[] traits, const_binding[] consts, struct_binding[] structs) name_resolution_gate_result {
    result := name_resolution_gate_result {
        total_identifiers: 0,
        resolved_exact: 0,
        resolved_ambiguous: 0,
        unresolved: 0,
        qualified_with_multiple_matches: 0,
        details: identifier_resolution[](),
        gate_pass: 1,
    }
    
    
    all_identifiers := collect_all_identifiers_from_items(file.items)
    
    result.total_identifiers = std.prelude.len(all_identifiers)
    
    
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
        
        
        if id.is_qualified && std.prelude.len(resolution.candidates) > 1 {
            result.qualified_with_multiple_matches = result.qualified_with_multiple_matches + 1
            result.gate_pass = 0
        }
        
        i = i + 1
    }
    
    result
}

struct identifier_info {
    string identifier_text
    bool is_qualified
}

func collect_all_identifiers_from_items(compile.internal.ast.item[] items) identifier_info[] {
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

func collect_identifiers_from_item(compile.internal.ast.item it) identifier_info[] {
    identifiers := identifier_info[]()
    
    switch it {
        item.function(function_decl) : {
            identifiers = append_from_function_body(identifiers, function_decl.body)
        }
        item.method(method_decl) : {
            identifiers = append_from_function_body(identifiers, method_decl.method.body)
        }
        item.const(const_decl) : {
            switch const_decl.value {
                option.some(expr_val) : {
                    identifiers = append_from_expr(identifiers, expr_val)
                }
                option.none : {}
            }
        }
        _ : {}
    }
    
    identifiers
}

func append_from_function_body(identifier_info[] initial_values, option[block_expr] body) identifier_info[] {
    acc := initial_values
    switch body {
        option.some(value): return append_from_block(acc, value),
        option.none: (),
    }
    acc
}

func append_from_block(identifier_info[] initial_values, compile.internal.ast.block_expr block) identifier_info[] {
    acc := initial_values
    i := 0
    for i < len(block.statements) {
        acc = append_from_stmt(acc, block.statements[i])
        i = i + 1
    }
    switch block.final_expr {
        option.some(value): acc = append_from_expr(acc, value),
        option.none: (),
    }
    acc
}

func append_from_stmt(identifier_info[] initial_values, compile.internal.ast.stmt statement) identifier_info[] {
    acc := initial_values
    switch statement {
        stmt.store(value): {
            acc = append_from_expr(acc, value.target)
            acc = append_from_expr(acc, value.value)
        }
        stmt.multi(value): {
            i := 0
            for i < len(value.targets) {
                acc = append_from_expr(acc, value.targets[i])
                i = i + 1
            }
            acc = append_from_expr(acc, value.value)
        }
        stmt.continue(_) : (),
        stmt.break(_) : (),
        stmt.let(value): acc = append_from_expr(acc, value.value),
        stmt.assign(value): {
            acc = append(acc, identifier_info { identifier_text: value.name, is_qualified: false })
            acc = append_from_expr(acc, value.value)
        }
        stmt.increment(value): acc = append(acc, identifier_info { identifier_text: value.name, is_qualified: false }),
        stmt.c_for(value): {
            acc = append_from_stmt(acc, value.init.value)
            acc = append_from_expr(acc, value.condition)
            acc = append_from_stmt(acc, value.step.value)
            acc = append_from_block(acc, value.body)
        }
        stmt.return(value): {
            switch value.value {
                option.some(expression): acc = append_from_expr(acc, expression),
                option.none: (),
            }
        }
        stmt.expr(value): acc = append_from_expr(acc, value.expr),
        stmt.defer(value): acc = append_from_expr(acc, value.expr),
        stmt.sroutine(value): acc = append_from_expr(acc, value.expr),
    }
    acc
}

func append_from_expr(identifier_info[] initial_values, compile.internal.ast.expr expression) identifier_info[] {
    acc := initial_values
    switch expression {
        expr.tuple(value): {
            i := 0
            for i < len(value.items) { acc = append_from_expr(acc, value.items[i]); i = i + 1 }
        }
        expr.record(value): {
            loop_var_2 := 0
            for loop_var_2 < len(value.field_values) { acc = append_from_expr(acc, value.field_values[loop_var_2]); loop_var_2 = loop_var_2 + 1 }
        }
        expr.name(value): acc = append(acc, identifier_info { identifier_text: value.name, is_qualified: false }),
        expr.member(value): {
            path := qualified_expr_path_gate(value)
            if path != "" { acc = append(acc, identifier_info { identifier_text: path, is_qualified: true }) }
            acc = append_from_expr(acc, value.target.value)
        }
        expr.call(value): {
            acc = append_from_expr(acc, value.callee.value)
            loop_var_3 := 0
            for loop_var_3 < len(value.args) {
                acc = append_from_expr(acc, value.args[loop_var_3])
                loop_var_3 = loop_var_3 + 1
            }
        }
        expr.binary(value): {
            acc = append_from_expr(acc, value.left.value)
            acc = append_from_expr(acc, value.right.value)
        }
        expr.borrow(value): acc = append_from_expr(acc, value.target.value),
        expr.index(value): {
            acc = append_from_expr(acc, value.target.value)
            acc = append_from_expr(acc, value.index.value)
        }
        expr.block(value): acc = append_from_block(acc, value),
        expr.if(value): {
            acc = append_from_expr(acc, value.condition.value)
            acc = append_from_block(acc, value.then_branch)
            switch value.else_branch {
                option.some(other): acc = append_from_expr(acc, other.value),
                option.none: (),
            }
        }
        expr.while(value): {
            acc = append_from_expr(acc, value.condition.value)
            acc = append_from_block(acc, value.body)
        }
        expr.for(value): {
            switch value.init { option.some(initial): acc = append_from_stmt(acc, initial.value), option.none: (), }
            switch value.condition { option.some(condition): acc = append_from_expr(acc, condition.value), option.none: (), }
            switch value.post { option.some(post): acc = append_from_stmt(acc, post.value), option.none: (), }
            switch value.iterable { option.some(iterable): acc = append_from_expr(acc, iterable.value), option.none: (), }
            acc = append_from_block(acc, value.body)
        }
        expr.switch(value): {
            acc = append_from_expr(acc, value.subject.value)
            loop_var_4 := 0
            for loop_var_4 < len(value.arms) {
                acc = append_from_expr(acc, value.arms[loop_var_4].expr)
                loop_var_4 = loop_var_4 + 1
            }
        }
        expr.array(value): {
            loop_var_5 := 0
            for loop_var_5 < len(value.items) {
                acc = append_from_expr(acc, value.items[loop_var_5])
                loop_var_5 = loop_var_5 + 1
            }
        }
        expr.map(value): {
            loop_var_6 := 0
            for loop_var_6 < len(value.entries) {
                acc = append_from_expr(acc, value.entries[loop_var_6].key)
                acc = append_from_expr(acc, value.entries[loop_var_6].value)
                loop_var_6 = loop_var_6 + 1
            }
        }
        _ : (),
    }
    acc
}

func resolve_identifier_to_candidates(string identifier, bool is_qualified, string current_package, function_binding[] functions, trait_binding[] traits, const_binding[] consts, struct_binding[] structs) identifier_resolution {
    candidates := name_resolution_candidate[]()
    
    if is_qualified {
        
        pkg_part := qualified_package_part(identifier)
        name_part := qualified_decl_part(identifier)
        
        
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
        
        
        matched_functions := lookup_functions(functions, identifier)
        loop_var_2 := 0
        for loop_var_2 < std.prelude.len(matched_functions) {
            candidates = append(candidates, name_resolution_candidate {
                package_path: matched_functions[loop_var_2].package_path,
                name: matched_functions[loop_var_2].name,
                kind: "function",
                source_location: "",
            })
            loop_var_2 = loop_var_2 + 1
        }
        
        
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
    
    status := "resolved_ambiguous"
    if std.prelude.len(candidates) == 0 {
        status = "unresolved"
    } else if std.prelude.len(candidates) == 1 {
        status = "resolved_exact"
    }
    
    identifier_resolution {
        identifier_text: identifier,
        is_qualified: is_qualified,
        candidates: candidates,
        errors: 0,
        resolution_status: status,
    }
}

func print_name_resolution_gate_result(name_resolution_gate_result result) {
    std.io.println("canonical-name-resolution-check")
    std.io.println("  total-identifiers       = " + to_string(result.total_identifiers))
    std.io.println("  resolved-exact          = " + to_string(result.resolved_exact))
    std.io.println("  resolved-ambiguous      = " + to_string(result.resolved_ambiguous))
    std.io.println("  unresolved              = " + to_string(result.unresolved))
    std.io.println("  qualified-multi-match   = " + to_string(result.qualified_with_multiple_matches))
    
    if result.gate_pass == 1 {
        std.io.println("  result                  = PASS")
    } else {
        std.io.println("  result                  = FAIL")
        
        
        i := 0
        for i < std.prelude.len(result.details) {
            if result.details[i].resolution_status != "resolved_exact" {
                std.io.println("  first-blocker           = " + result.details[i].identifier_text + " (" + result.details[i].resolution_status + ")")
                break
            }
            i = i + 1
        }
    }
}

func qualified_expr_path_gate(compile.internal.ast.member_expr member_val) string {
    switch member_val.target.value {
        expr.name(name_val) : {
            return name_val.name + "." + member_val.member
        }
        expr.member(nested_member) : {
            prefix := qualified_expr_path_gate(nested_member)
            if prefix != "" {
                return prefix + "." + member_val.member
            }
            return ""
        }
        _ : return ""
    }
}
