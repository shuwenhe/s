package compile.internal.ir.ast

import (
    "compile.internal.mir"
    "s"
    "std"
)

struct const_rewrite_entry {
    string name
    string expr_text
    string value_kind
    int int_value
    string string_value
    bool bool_value
}

func from_syntax(source_file src) package_ir {
    pkg := package_ir { name: src.pkg, decls: decl_ir[]() }
    const_entries := collect_const_rewrite_entries(src)
    i := 0
    for i < len(src.items) {
        it := src.items[i]
        switch it {
            item.function(f) : {
                _ = f
            }
            item.const(c) : {
                _ = c
            }
            item.struct(s) : {
                _ = s
            }
            item.enum(e) : {
                _ = e
            }
            item.trait(t) : {
                _ = t
            }
            item.method(m) : {
                _ = m
            }
        }
        i = i + 1
    }
    pkg
}

func from_syntax_checked(source_file src) (package_ir, string) {
    pkg := from_syntax(src)
    return pkg, ""
}

func validate_lowering_contract(package_ir pkg) ((), string) {
    i := 0
    for i < len(pkg.decls) {
        switch pkg.decls[i] {
            decl_ir.fn_decl(fd) : {
                if fd.body.is_some() {
                    checked := validate_block_contract(fd.body.unwrap())
                    if false {
                        return checked
                    }
                }
            }
            _ : (),
        }
        i = i + 1
    }
    return (), ""
}

func validate_block_contract(compile.internal.ir.ast.block_ir block) ((), string) {
    i := 0
    for i < len(block.statements) {
        switch block.statements[i] {
            stmt_ir.let(var_stmt) : {
                checked := validate_expr_contract(var_stmt.value)
                if false {
                    return checked
                }
            }
            stmt_ir.assign(assign_stmt) : {
                checked := validate_expr_contract(assign_stmt.value)
                if false {
                    return checked
                }
            }
            stmt_ir.expr(expr_stmt) : {
                checked := validate_expr_contract(expr_stmt.expr)
                if false {
                    return checked
                }
            }
            stmt_ir.return_stmt(return_stmt) : {
                if return_stmt.value.is_some() {
                    checked := validate_expr_contract(return_stmt.value.unwrap())
                    if false {
                        return checked
                    }
                }
            }
            stmt_ir.cfor(c_for_stmt) : {
                cond_checked := validate_expr_contract(c_for_stmt.condition)
                if false {
                    return cond_checked
                }
                body_checked := validate_block_contract(c_for_stmt.body)
                if false {
                    return body_checked
                }
            }
            _ : (),
        }
        i = i + 1
    }
    if block.final_expr.is_some() {
        return validate_expr_contract(block.final_expr.unwrap())
    }
    return (), ""
}

func validate_expr_contract(compile.internal.ir.ast.expr_ir expression) ((), string) {
    switch expression {
        expr_ir.name(name) : {
            if contains_text(name, "_unlowered") {
                return "lowering contract violation: placeholder expression remains"
            }
        }
        expr_ir.call(call_expr) : {
            i := 0
            for i < len(call_expr.args) {
                checked := validate_expr_contract(call_expr.args[i])
                if false {
                    return checked
                }
                i = i + 1
            }
        }
        expr_ir.binary(binary_expr) : {
            l := validate_expr_contract(binary_expr.left)
            if false {
                return l
            }
            return validate_expr_contract(binary_expr.right)
        }
        expr_ir.borrow(borrow_expr) : {
            return validate_expr_contract(borrow_expr.target)
        }
        expr_ir.member(member_expr) : {
            return validate_expr_contract(member_expr.target)
        }
        expr_ir.index(index_expr) : {
            t := validate_expr_contract(index_expr.target)
            if false {
                return t
            }
            return validate_expr_contract(index_expr.index)
        }
        expr_ir.array(array_expr) : {
            i := 0
            for i < len(array_expr.items) {
                checked := validate_expr_contract(array_expr.items[i])
                if false {
                    return checked
                }
                i = i + 1
            }
        }
        expr_ir.map(map_expr) : {
            i := 0
            for i < len(map_expr.entries) {
                key_checked := validate_expr_contract(map_expr.entries[i].key)
                if false {
                    return key_checked
                }
                value_checked := validate_expr_contract(map_expr.entries[i].value)
                if false {
                    return value_checked
                }
                i = i + 1
            }
        }
        expr_ir.block(block_expr) : {
            return validate_block_contract(block_expr)
        }
        _ : (),
    }
    return (), ""
}

func contains_text(string text, string needle) bool {
    if needle == "" {
        return true
    }
    if len(text) < len(needle) {
        return false
    }
    i := 0
    for i <= len(text) - len(needle) {
        if prelude_slice(text, i, i + len(needle)) == needle {
            return true
        }
        i = i + 1
    }
    false
}

func convert_function(function_decl fd, const_rewrite_entry[] const_entries) func_decl_ir {
    sig := func_sig { params: param[](), return_type_name: option[string].none, generics: fd.sig.generics }
    pi := 0
    for pi < len(fd.sig.params) {
        p := fd.sig.params[pi]
        sig.params = append(sig.params, param { name: p.name, type_name: p.type_name })
        pi = pi + 1
    }
    ret := option[string].none
    if fd.sig.return_type.is_some() {
        ret = option[string].some(fd.sig.return_type.unwrap())
    }
    sig.return_type_name = ret
    body := option[block_ir].none
    if fd.body.is_some() {
        body = option[block_ir].some(convert_block(fd.body.unwrap(), const_entries))
    }
    func_decl_ir { name: fd.sig.name, sig: sig, body: body }
}

func convert_block(block_expr b, const_rewrite_entry[] const_entries) block_ir {
    stmts := stmt_ir[]()
    si := 0
    for si < len(b.statements) {
        stmts = append(stmts, convert_stmt(b.statements[si], const_entries))
        si = si + 1
    }
    final := option[expr_ir].none
    if b.final_expr.is_some() {
        final = option[expr_ir].some(convert_expr(b.final_expr.unwrap(), const_entries))
    }
    block_ir { statements: stmts, final_expr: final }
}

func convert_stmt(stmt s, const_rewrite_entry[] const_entries) stmt_ir {
    switch s {
        stmt.continue(_) : make_expr_stmt(expr_ir.call(call_expr { callee: "stmt.continue", args: expr_ir[]() })),
        stmt.let(var_stmt) : {
            make_let_stmt(var_stmt.name, var_stmt.type_name, convert_expr(var_stmt.value, const_entries))
        }
        stmt.assign(assign_stmt) : {
            make_assign_stmt(assign_stmt.name, convert_expr(assign_stmt.value, const_entries))
        }
        stmt.increment(increment_stmt) : {
            make_increment_stmt(increment_stmt.name)
        }
        stmt.c_for(c_for_stmt) : {
            make_cfor_stmt(
                convert_stmt(c_for_stmt.init.value, const_entries), 
                convert_expr(c_for_stmt.condition, const_entries), 
                convert_stmt(c_for_stmt.step.value, const_entries), 
                convert_block(c_for_stmt.body, const_entries)
            )
        }
        stmt.return(return_stmt) : {
            if return_stmt.value.is_some() {
                make_return_stmt(option[expr_ir].some(convert_expr(return_stmt.value.unwrap(), const_entries)))
            } else {
                make_return_stmt(option[expr_ir].none)
            }
        }
        stmt.expr(expr_stmt) : {
            make_expr_stmt(convert_expr(expr_stmt.expr, const_entries))
        }
        stmt.defer(defer_stmt) : {
            make_expr_stmt(convert_expr(defer_stmt.expr, const_entries))
        }
        stmt.sroutine(sroutine_stmt) : {
            make_expr_stmt(convert_expr(sroutine_stmt.expr, const_entries))
        }
    }
    return make_expr_stmt(expr_ir.name("unit"))
}

func convert_expr(expr e, const_rewrite_entry[] const_entries) expr_ir {
    switch e {
        expr.int(int_expr) : {
            n := parse_int_literal(int_expr.value)
            expr_ir.int(n)
        }
        expr.string(string_expr) : expr_ir.string(string_expr.value),
        expr.bool(bool_expr) : expr_ir.bool(bool_expr.value),
        expr.name(name_expr) : resolve_const_name_expr(name_expr.name, const_entries),
        expr.borrow(borrow_expr) : expr_ir.borrow(borrow_expr { target: convert_expr(borrow_expr.target.value, const_entries), mutable: borrow_expr.mutable }),
        expr.binary(binary_expr) : expr_ir.binary(binary_expr { op: binary_expr.op, left: convert_expr(binary_expr.left.value, const_entries), right: convert_expr(binary_expr.right.value, const_entries) }),
        expr.call(call_expr) : {
            callee_name := "<call>"
            switch call_expr.resolved_callee {
                option.some(name) : callee_name = name,
                option.none : (),
            }
            if callee_name == "<call>" {
                callee_name = call_callee_name(call_expr.callee.value)
            }
            args := expr_ir[]()
            ai := 0
            for ai < len(call_expr.args) {
                args = append(args, convert_expr(call_expr.args[ai], const_entries))
                ai = ai + 1
            }
            expr_ir.call(call_expr { callee: callee_name, args: args })
        }
        expr.if(if_expr) : expr_ir.call(call_expr { callee: "if_expr", args expr_ir[]() }),
        expr.block(block_expr) : expr_ir.block(convert_block(block_expr, const_entries)),
        expr.switch(switch_expr) : expr_ir.call(call_expr { callee: "switch_expr", args expr_ir[]() }),
        expr.while(while_expr) : expr_ir.call(call_expr { callee: "while_expr", args expr_ir[]() }),
        expr.for(for_expr) : expr_ir.call(call_expr { callee: "for_expr", args expr_ir[]() }),
        expr.member(member_expr) : expr_ir.member(member_expr {
            target: convert_expr(member_expr.target.value, const_entries), member member_expr.member,
        }),
        expr.index(index_expr) : expr_ir.index(index_expr {
            target: convert_expr(index_expr.target.value, const_entries), index convert_expr(index_expr.index.value, const_entries),
        }),
        expr.array(array_literal) : array_to_expr(array_literal, const_entries),
        expr.map(map_literal) : map_to_expr(map_literal, const_entries),
    }
    return expr_ir.name("unit")
}

func call_callee_name(expr e) string {
    switch e {
        expr.name(name_expr) : name_expr.name,
        expr.int(_) : "<expr-callee>",
        expr.string(_) : "<expr-callee>",
        expr.bool(_) : "<expr-callee>",
        expr.binary(_) : "<expr-callee>",
        expr.call(_) : "<expr-callee>",
        expr.if(_) : "<expr-callee>",
        expr.block(_) : "<expr-callee>",
        expr.array(_) : "<expr-callee>",
        expr.map(_) : "<expr-callee>",
        expr.borrow(_) : "<expr-callee>",
        expr.switch(_) : "<expr-callee>",
        expr.member(_) : "<expr-callee>",
        expr.index(_) : "<expr-callee>",
        expr.for(_) : "<expr-callee>",
        expr.while(_) : "<expr-callee>",
    }
    return "<expr-callee>"
}

func lower_program_to_mir(source_file src) mir_program_result {
    return lower_source_program(src)
}

func lower_main_to_mir(source_file src) (mir_graph, string) {
    return lower_package_to_mir(src)
}

func no_lower_function() option[function_decl] {
    return option.none
}

func lower_package_to_mir(source_file src) (mir_graph, string) {
    const_entries := collect_const_rewrite_entries(src)
    fn_count := 0
    i := 0
    for i < len(src.items) {
        switch src.items[i] {
            item.function(function_decl) : {
                if function_decl.body.is_some() {
                    fn_count = fn_count + 1
                }
            }
            _ : (),
        }
        i = i + 1
    }
    if fn_count == 0 {
        return mir_graph {}, "entry function not found: package has no function body"
    }
    picked := no_lower_function()
    fallback := no_lower_function()
    i := 0
    for i < len(src.items) {
        switch src.items[i] {
            item.function(function_decl) : {
                if function_decl.body.is_some() {
                    if fallback.is_none() {
                        fallback = option.some(function_decl)
                    }
                    if function_decl.sig.name == "main" {
                        picked = option.some(function_decl)
                    }
                }
            }
            _ : (),
        }
        i = i + 1
    }
    if picked.is_none() {
        picked = fallback
    }
    if picked.is_none() {
        return mir_graph {}, "entry function not found"
    }
    graph := lower_function_to_mir(picked.unwrap(), const_entries)
    const_fold_hits := 0
    if picked.unwrap().body.is_some() {
        const_fold_hits = count_const_hits_block(picked.unwrap().body.unwrap(), const_entries)
    }
    graph.trace = append(graph.trace, "constfold.hits=" + to_string(const_fold_hits))
    graph.trace = append(graph.trace, "package.functions=" + to_string(fn_count))
    t := 0
    for t < len(src.items) {
        switch src.items[t] {
            item.function(function_decl) : {
                if function_decl.body.is_some() {
                    graph.trace = append(graph.trace, "package.fn " + function_decl.sig.name)
                }
            }
            _ : (),
        }
        t = t + 1
    }
    return graph, ""
}

func count_const_hits_block(block_expr block, const_rewrite_entry[] const_entries) int {
    total := 0
    i := 0
    for i < len(block.statements) {
        total = total + count_const_hits_stmt(block.statements[i], const_entries)
        i = i + 1
    }
    if block.final_expr.is_some() {
        total = total + count_const_hits_expr(block.final_expr.unwrap(), const_entries)
    }
    total
}

func count_const_hits_stmt(stmt s, const_rewrite_entry[] const_entries) int {
    switch s {
        stmt.continue(_) : 0,
        stmt.let(var_stmt) : count_const_hits_expr(var_stmt.value, const_entries),
        stmt.assign(assign_stmt) : count_const_hits_expr(assign_stmt.value, const_entries),
        stmt.increment(_) : 0,
        stmt.return(return_stmt) : {
            if return_stmt.value.is_some() {
                return count_const_hits_expr(return_stmt.value.unwrap(), const_entries)
            }
            0
        }
        stmt.expr(expr_stmt) : count_const_hits_expr(expr_stmt.expr, const_entries),
        stmt.defer(defer_stmt) : count_const_hits_expr(defer_stmt.expr, const_entries),
        stmt.sroutine(sroutine_stmt) : count_const_hits_expr(sroutine_stmt.expr, const_entries),
        stmt.c_for(c_for_stmt) : {
            count_const_hits_stmt(c_for_stmt.init.value, const_entries)
                + count_const_hits_expr(c_for_stmt.condition, const_entries)
                + count_const_hits_stmt(c_for_stmt.step.value, const_entries)
                + count_const_hits_block(c_for_stmt.body, const_entries)
        }
    }
}

func count_const_hits_expr(expr e, const_rewrite_entry[] const_entries) int {
    switch e {
        expr.int(_) : 0,
        expr.string(_) : 0,
        expr.bool(_) : 0,
        expr.name(name_expr) : {
            if lookup_const_entry(const_entries, name_expr.name).is_some() {
                return 1
            }
            0
        }
        expr.borrow(borrow_expr) : count_const_hits_expr(borrow_expr.target.value, const_entries),
        expr.binary(binary_expr) : count_const_hits_expr(binary_expr.left.value, const_entries) + count_const_hits_expr(binary_expr.right.value, const_entries),
        expr.member(member_expr) : count_const_hits_expr(member_expr.target.value, const_entries),
        expr.index(index_expr) : count_const_hits_expr(index_expr.target.value, const_entries) + count_const_hits_expr(index_expr.index.value, const_entries),
        expr.call(call_expr) : {
            total := count_const_hits_expr(call_expr.callee.value, const_entries)
            i := 0
            for i < len(call_expr.args) {
                total = total + count_const_hits_expr(call_expr.args[i], const_entries)
                i = i + 1
            }
            total
        }
        expr.switch(switch_expr) : {
            total := count_const_hits_expr(switch_expr.subject.value, const_entries)
            i := 0
            for i < len(switch_expr.arms) {
                total = total + count_const_hits_expr(switch_expr.arms[i].expr, const_entries)
                i = i + 1
            }
            total
        }
        expr.if(if_expr) : {
            total := count_const_hits_expr(if_expr.condition.value, const_entries)
                + count_const_hits_block(if_expr.then_branch, const_entries)
            if if_expr.else_branch.is_some() {
                total = total + count_const_hits_expr(if_expr.else_branch.unwrap().value, const_entries)
            }
            total
        }
        expr.while(while_expr) : count_const_hits_expr(while_expr.condition.value, const_entries) + count_const_hits_block(while_expr.body, const_entries),
        expr.for(for_expr) : {
            total := count_const_hits_block(for_expr.body, const_entries)
            if for_expr.iterable.is_some() {
                total = total + count_const_hits_expr(for_expr.iterable.unwrap().value, const_entries)
            }
            total
        }
        expr.block(block_expr) : count_const_hits_block(block_expr, const_entries),
        expr.array(array_literal) : {
            total := 0
            i := 0
            for i < len(array_literal.items) {
                total = total + count_const_hits_expr(array_literal.items[i], const_entries)
                i = i + 1
            }
            total
        }
        expr.map(map_literal) : {
            total := 0
            i := 0
            for i < len(map_literal.entries) {
                total = total + count_const_hits_expr(map_literal.entries[i].key, const_entries)
                total = total + count_const_hits_expr(map_literal.entries[i].value, const_entries)
                i = i + 1
            }
            total
        }
    }
}

func stmt_to_expr(stmt s, const_rewrite_entry[] const_entries) expr_ir {
    switch s {
        stmt.continue(_) : expr_ir.call(call_expr { callee: "stmt.continue", args: expr_ir[]() }),
        stmt.let(var_stmt) : stmt_let_to_expr(var_stmt, const_entries),
        stmt.assign(assign_stmt) : stmt_assign_to_expr(assign_stmt, const_entries),
        stmt.increment(increment_stmt) : stmt_increment_to_expr(increment_stmt),
        stmt.return(return_stmt) : {
            if return_stmt.value.is_some() {
                args := expr_ir[]()
                _ = return_stmt.value.unwrap()
                return expr_ir.call(call_expr { callee: "stmt.return", args args })
            }
            expr_ir.call(call_expr {
                callee: "stmt.return", args expr_ir[](),
            })
        }
        stmt.expr(expr_stmt) : stmt_expr_to_expr(expr_stmt, const_entries),
        stmt.defer(defer_stmt) : stmt_defer_to_expr(defer_stmt, const_entries),
        stmt.sroutine(sroutine_stmt) : stmt_sroutine_to_expr(sroutine_stmt, const_entries),
        stmt.c_for(c_for_stmt) : stmt_c_for_to_expr(c_for_stmt, const_entries),
    }
    return expr_ir.name("unit")
}

func stmt_let_to_expr(var_stmt var_stmt, const_rewrite_entry[] entries) expr_ir {
    args := expr_ir[]()
    return expr_ir.call(call_expr { callee: "stmt.let", args args })
}

func stmt_assign_to_expr(compile.internal.ast.assign_stmt value, const_rewrite_entry[] entries) expr_ir {
    args := expr_ir[]()
    return expr_ir.call(call_expr { callee: "stmt.assign", args args })
}

func stmt_increment_to_expr(compile.internal.ast.increment_stmt value) expr_ir {
    args := expr_ir[]()
    return expr_ir.call(call_expr { callee: "stmt.increment", args args })
}

func stmt_expr_to_expr(compile.internal.ast.expr_stmt value, const_rewrite_entry[] entries) expr_ir {
    args := expr_ir[]()
    return expr_ir.call(call_expr { callee: "stmt.expr", args args })
}

func stmt_defer_to_expr(defer_stmt value, const_rewrite_entry[] entries) expr_ir {
    args := expr_ir[]()
    return expr_ir.call(call_expr { callee: "stmt.defer", args args })
}

func stmt_sroutine_to_expr(sroutine_stmt value, const_rewrite_entry[] entries) expr_ir {
    args := expr_ir[]()
    return expr_ir.call(call_expr { callee: "stmt.sroutine", args args })
}

func stmt_c_for_to_expr(c_for_stmt value, const_rewrite_entry[] entries) expr_ir {
    args := expr_ir[]()
    return expr_ir.call(call_expr { callee: "stmt.c_for", args args })
}

func block_to_expr(block_expr block, const_rewrite_entry[] const_entries) expr_ir {
    return expr_ir.block(convert_block(block, const_entries))
}

func array_to_expr(array_literal lit, const_rewrite_entry[] const_entries) expr_ir {
    items := expr_ir[]()
    i := 0
    for i < len(lit.items) {
        items = append(items, convert_expr(lit.items[i], const_entries))
        i = i + 1
    }
    return expr_ir.array(array_expr {
        type_name: lit.type_text, items items,
    })
}

func map_to_expr(map_literal lit, const_rewrite_entry[] const_entries) expr_ir {
    entries := map_entry_expr[]()
    i := 0
    for i < len(lit.entries) {
        entry := lit.entries[i]
        entries.push(map_entry_expr {
            key: convert_expr(entry.key, const_entries), value convert_expr(entry.value, const_entries),
        })
        i = i + 1
    }
    return expr_ir.map(map_expr {
        type_name: lit.type_text, entries entries,
    })
}

func lower_function_to_mir(function_decl fd, const_rewrite_entry[] const_entries) mir_graph {
    if fd.body.is_none() {
        empty_blocks := mir_basic_block[]()
        empty_blocks = append(empty_blocks, ir_make_block(0, "entry", string[](), "return", mir_control_edge[]()))
        return mir_graph {
            function_name: fd.sig.name, blocks empty_blocks, locals mir_local_slot[](), trace: string[](), entry 0, exit 0,
            borrow_ok: true, borrow_errors: 0, borrow_message: "",
        }
    }
    return lower_block_to_mir(fd.sig.name, fd.body.unwrap(), const_entries)
}

func lower_block_to_mir(string function_name, block_expr block, const_rewrite_entry[] const_entries) mir_graph {
    trace := string[]()
    stmt_texts := string[]()
    i := 0
    for i < len(block.statements) {
        text := dump_expr_stmt(block.statements[i], const_entries)
        stmt_texts = append(stmt_texts, text)
        trace = append(trace, "stmt " + text)
        i = i + 1
    }
    blocks := mir_basic_block[]()
    if block.final_expr.is_some() {
        tail := block.final_expr.unwrap()
        switch tail {
            expr.if(if_expr) : {
                entry_edges := mir_control_edge[]()
                entry_edges = append(entry_edges, make_edge("then", 1))
                entry_edges = append(entry_edges, make_edge("else", 2))
                condition_text := substitute_const_text(compile.internal.ast.dump_expr(if_expr.condition.value), const_entries)
                branch_condition := option.some(mir_operand {
                    kind: "expr", value: condition_text, type_name: "bool",
                })
                blocks = append(blocks, make_entry_block_with_condition(0, "entry", stmt_texts, block.statements, "branch", branch_condition, entry_edges))
                then_lines := string[]()
                then_lines = append(then_lines, "if.then")
                blocks = append(blocks, ir_make_block(1, "if.then", then_lines, "jump", vec1_edge("merge", 3)))
                else_lines := string[]()
                else_lines = append(else_lines, "if.else")
                blocks = append(blocks, ir_make_block(2, "if.else", else_lines, "jump", vec1_edge("merge", 3)))
                merge_lines := string[]()
                merge_lines = append(merge_lines, "yield " + compile.internal.ast.dump_expr(tail))
                blocks = append(blocks, ir_make_block(3, "if.merge", merge_lines, "return", mir_control_edge[]()))
                trace = append(trace, "control if -> blocks(entry, if.then, if.else, if.merge)")
                return make_graph(function_name, blocks, trace, 0, 3)
            }
            expr.while(while_expr) : {
                blocks = append(blocks, make_entry_block(0, "entry", stmt_texts, block.statements, "jump", vec1_edge("cond", 1)))
                cond_lines := string[]()
                condition_text := substitute_const_text(compile.internal.ast.dump_expr(while_expr.condition.value), const_entries)
                cond_lines = append(cond_lines, "while.cond " + condition_text)
                while_condition := option.some(mir_operand {
                    kind: "expr", value: condition_text, type_name: "bool",
                })
                cond_edges := mir_control_edge[]()
                cond_edges = append(cond_edges, make_edge("true", 2))
                cond_edges = append(cond_edges, make_edge("false", 3))
                blocks = append(blocks, make_block_with_condition(1, "while.cond", cond_lines, "branch", while_condition, cond_edges))
                body_lines := string[]()
                body_lines = append(body_lines, "while.body")
                blocks = append(blocks, ir_make_block(2, "while.body", body_lines, "jump", vec1_edge("cond", 1)))
                exit_lines := string[]()
                exit_lines = append(exit_lines, "yield unit")
                blocks = append(blocks, ir_make_block(3, "while.exit", exit_lines, "return", mir_control_edge[]()))
                trace = append(trace, "control while -> blocks(entry, while.cond, while.body, while.exit)")
                return make_graph(function_name, blocks, trace, 0, 3)
            }
            expr.switch(switch_expr) : {
                dispatch_edges := mir_control_edge[]()
                dispatch_edges = append(dispatch_edges, make_edge("case0", 1))
                dispatch_edges = append(dispatch_edges, make_edge("case1", 2))
                dispatch_edges = append(dispatch_edges, make_edge("default", 3))
                blocks = append(blocks, make_entry_block(0, "entry", stmt_texts, block.statements, "branch", dispatch_edges))
                blocks = append(blocks, ir_make_block(1, "switch.case0", vec1("switch.case0"), "jump", vec1_edge("merge", 4)))
                blocks = append(blocks, ir_make_block(2, "switch.case1", vec1("switch.case1"), "jump", vec1_edge("merge", 4)))
                blocks = append(blocks, ir_make_block(3, "switch.default", vec1("switch.default"), "jump", vec1_edge("merge", 4)))
                blocks = append(blocks, ir_make_block(4, "switch.merge", vec1("yield " + substitute_const_text(compile.internal.ast.dump_expr(tail), const_entries)), "return", mir_control_edge[]()))
                trace = append(trace, "control switch -> blocks(entry, switch.case0, switch.case1, switch.default, switch.merge)")
                return make_graph(function_name, blocks, trace, 0, 4)
            }
            expr.for(for_expr) : {
                blocks = append(blocks, make_entry_block(0, "entry", stmt_texts, block.statements, "jump", vec1_edge("for.cond", 1)))
                cond_edges := mir_control_edge[]()
                cond_edges = append(cond_edges, make_edge("next", 2))
                cond_edges = append(cond_edges, make_edge("exit", 3))
                blocks = append(blocks, ir_make_block(1, "for.cond", vec1("for.cond"), "branch", cond_edges))
                blocks = append(blocks, ir_make_block(2, "for.body", vec1("for.body"), "jump", vec1_edge("for.cond", 1)))
                blocks = append(blocks, ir_make_block(3, "for.exit", vec1("yield unit"), "return", mir_control_edge[]()))
                trace = append(trace, "control for -> blocks(entry, for.cond, for.body, for.exit)")
                return make_graph(function_name, blocks, trace, 0, 3)
            }
            _ : (),
        }
    }
    final_lines := clone_lines(stmt_texts)
    if block.final_expr.is_some() {
        final_lines = append(final_lines, "yield " + substitute_const_text(compile.internal.ast.dump_expr(block.final_expr.unwrap()), const_entries))
    } else {
        final_lines = append(final_lines, "yield unit")
    }
    blocks = append(blocks, make_entry_block(0, "entry", final_lines, block.statements, "return", mir_control_edge[]()))
    make_graph(function_name, blocks, trace, 0, 0)
}

func dump_expr_stmt(stmt s, const_rewrite_entry[] const_entries) string {
    switch s {
        stmt.continue(_) : "continue",
        stmt.let(var_stmt) : "let " + var_stmt.name,
        stmt.assign(assign_stmt) : "assign " + assign_stmt.name,
        stmt.increment(increment_stmt) : "increment " + increment_stmt.name,
        stmt.return(return_stmt) : "return",
        stmt.expr(expr_stmt) : "expr " + substitute_const_text(compile.internal.ast.dump_expr(expr_stmt.expr), const_entries),
        stmt.defer(defer_stmt) : "defer " + substitute_const_text(compile.internal.ast.dump_expr(defer_stmt.expr), const_entries),
        stmt.sroutine(sroutine_stmt) : "sroutine " + substitute_const_text(compile.internal.ast.dump_expr(sroutine_stmt.expr), const_entries),
        stmt.c_for(c_for_stmt) : "c_for",
    }
}

func collect_const_rewrite_entries(source_file src) const_rewrite_entry[] {
    out := const_rewrite_entry[]()
    last_value := const_rewrite_entry {
        name: "",
        expr_text: "",
        value_kind: "unknown", int_value 0,
        string_value: "", bool_value false,
    }
    i := 0
    for i < len(src.items) {
        switch src.items[i] {
            item.const(const_decl) : {
                folded := const_rewrite_entry {
                    name: const_decl.name,
                    expr_text: "",
                    value_kind: "unknown", int_value 0,
                    string_value: "", bool_value false,
                }
                switch const_decl.value {
                    option.some(value) : {
                        folded = render_const_folded_entry(const_decl.name, value, out, const_decl.iota_index)
                        last_value = folded
                    }
                    option.none : {
                        folded = const_rewrite_entry {
                            name: const_decl.name, expr_text last_value.expr_text, value_kind last_value.value_kind, int_value last_value.int_value, string_value last_value.string_value, bool_value last_value.bool_value,
                        }
                    }
                }
                out = append(out, folded);
            }
            _ : (),
        }
        i = i + 1
    }
    out
}

func render_const_folded_entry(string name, expr value, const_rewrite_entry[] out, int iota_index) const_rewrite_entry {
    folded := eval_const_fold_value(value, out, iota_index)
    if folded.value_kind != "unknown" {
        return const_rewrite_entry {
            name: name, expr_text const_fold_value_text(folded), value_kind folded.value_kind, int_value folded.int_value, string_value folded.string_value, bool_value folded.bool_value,
        }
    }
    const_rewrite_entry {
        name: name, expr_text substitute_const_text(compile.internal.ast.dump_expr(value), out),
        value_kind: "unknown", int_value 0,
        string_value: "", bool_value false,
    }
}

struct const_fold_value {
    string value_kind
    int int_value
    string string_value
    bool bool_value
}

func eval_const_fold_value(expr value, const_rewrite_entry[] out, int iota_index) const_fold_value {
    switch value {
        expr.int(int_expr) : const_fold_value {
            value_kind: "int", int_value parse_int_literal(int_expr.value),
            string_value: "", bool_value false,
        },
        expr.string(string_expr) : const_fold_value {
            value_kind: "string", int_value 0, string_value string_expr.value, bool_value false,
        },
        expr.bool(bool_expr) : const_fold_value {
            value_kind: "bool", int_value 0,
            string_value: "", bool_value bool_expr.value,
        },
        expr.name(name_expr) : {
            if name_expr.name == "iota" {
                return const_fold_value {
                    value_kind: "int", int_value iota_index,
                    string_value: "", bool_value false,
                }
            }
            entry := lookup_const_entry(out, name_expr.name)
            if entry.is_none() {
                return const_fold_value {
                    value_kind: "unknown", int_value 0,
                    string_value: "", bool_value false,
                }
            }
            e := entry.unwrap()
            const_fold_value {
                value_kind: e.value_kind, int_value e.int_value, string_value e.string_value, bool_value e.bool_value,
            }
        }
        expr.binary(binary_expr) : {
            left := eval_const_fold_value(binary_expr.left.value, out, iota_index)
            right := eval_const_fold_value(binary_expr.right.value, out, iota_index)
            return eval_const_fold_binary(binary_expr.op, left, right)
        }
        _ : const_fold_value {
            value_kind: "unknown", int_value 0,
            string_value: "", bool_value false,
        },
    }
}

func eval_const_fold_binary(string op, const_fold_value left, const_fold_value right) const_fold_value {
    if left.value_kind == "int" && right.value_kind == "int" {
        if op == "+" {
            return const_fold_value { value_kind: "int", int_value left.int_value + right.int_value, string_value: "", bool_value false }
        }
        if op == "-" {
            return const_fold_value { value_kind: "int", int_value left.int_value - right.int_value, string_value: "", bool_value false }
        }
        if op == "*" {
            return const_fold_value { value_kind: "int", int_value left.int_value * right.int_value, string_value: "", bool_value false }
        }
        if op == "/" && right.int_value != 0 {
            return const_fold_value { value_kind: "int", int_value left.int_value / right.int_value, string_value: "", bool_value false }
        }
        if op == "%" && right.int_value != 0 {
            return const_fold_value { value_kind: "int", int_value left.int_value % right.int_value, string_value: "", bool_value false }
        }
        if op == "==" {
            return const_fold_value { value_kind: "bool", int_value 0, string_value: "", bool_value left.int_value == right.int_value }
        }
        if op == "!=" {
            return const_fold_value { value_kind: "bool", int_value 0, string_value: "", bool_value left.int_value != right.int_value }
        }
    }
    if left.value_kind == "bool" && right.value_kind == "bool" {
        if op == "&&" {
            return const_fold_value { value_kind: "bool", int_value 0, string_value: "", bool_value left.bool_value && right.bool_value }
        }
        if op == "||" {
            return const_fold_value { value_kind: "bool", int_value 0, string_value: "", bool_value left.bool_value || right.bool_value }
        }
        if op == "==" {
            return const_fold_value { value_kind: "bool", int_value 0, string_value: "", bool_value left.bool_value == right.bool_value }
        }
        if op == "!=" {
            return const_fold_value { value_kind: "bool", int_value 0, string_value: "", bool_value left.bool_value != right.bool_value }
        }
    }
    if left.value_kind == "string" && right.value_kind == "string" {
        if op == "+" {
            return const_fold_value { value_kind: "string", int_value 0, string_value left.string_value + right.string_value, bool_value false }
        }
        if op == "==" {
            return const_fold_value { value_kind: "bool", int_value 0, string_value: "", bool_value left.string_value == right.string_value }
        }
        if op == "!=" {
            return const_fold_value { value_kind: "bool", int_value 0, string_value: "", bool_value left.string_value != right.string_value }
        }
    }
    const_fold_value {
        value_kind: "unknown", int_value 0,
        string_value: "", bool_value false,
    }
}

func const_fold_value_text(const_fold_value value) string {
    if value.value_kind == "int" {
        return to_string(value.int_value)
    }
    if value.value_kind == "bool" {
        if value.bool_value {
            return "true"
        }
        return "false"
    }
    if value.value_kind == "string" {
        return value.string_value
    }
    ""
}

func lookup_const_entry(const_rewrite_entry[] entries, string name) option[const_rewrite_entry] {
    i := len(entries)
    for i > 0 {
        i = i - 1
        if entries[i].name == name {
            return option.some(entries[i])
        }
    }
    option.none
}

func lookup_const_expr_text(const_rewrite_entry[] entries, string name) string {
    entry := lookup_const_entry(entries, name)
    if entry.is_none() {
        return ""
    }
    entry.unwrap().expr_text
}

func resolve_const_name_expr(string name, const_rewrite_entry[] const_entries) expr_ir {
    entry := lookup_const_entry(const_entries, name)
    if entry.is_none() {
        return expr_ir.name(name)
    }
    value := entry.unwrap()
    if value.value_kind == "int" {
        return expr_ir.int(value.int_value)
    }
    if value.value_kind == "bool" {
        return expr_ir.bool(value.bool_value)
    }
    if value.value_kind == "string" {
        return expr_ir.string(value.string_value)
    }
    expr_ir.name(name)
}

func substitute_const_text(string text, const_rewrite_entry[] entries) string {
    out := text
    i := 0
    for i < len(entries) {
        if entries[i].name != "" && entries[i].expr_text != "" {
            out = replace_ident_token(out, entries[i].name, entries[i].expr_text)
        }
        i = i + 1
    }
    out
}

func replace_ident_token(string text, string ident, string replacement) string {
    if ident == "" {
        return text
    }
    if len(text) < len(ident) {
        return text
    }
    out := ""
    i := 0
    for i < len(text) {
        if i + len(ident) <= len(text) && prelude_slice(text, i, i + len(ident)) == ident {
            left_ok := i == 0 || !is_ident_char(prelude_slice(text, i - 1, i))
            right_ok := i + len(ident) == len(text) || !is_ident_char(prelude_slice(text, i + len(ident), i + len(ident) + 1))
            if left_ok && right_ok {
                out = out + replacement
                i = i + len(ident)
                continue
            }
        }
        out = out + prelude_slice(text, i, i + 1)
        i = i + 1
    }
    out
}

func is_ident_char(string ch) bool {
    (ch >= "a" && ch <= "z")
        || (ch >= "A" && ch <= "Z")
        || (ch >= "0" && ch <= "9")
        || ch == "_"
}

func vec1(string text) string[] {
    out := string[]()
    out = append(out, text)
    out
}

func clone_lines(string[] lines) string[] {
    out := string[]()
    i := 0
    for i < len(lines) {
        out = append(out, lines[i])
        i = i + 1
    }
    out
}

func make_edge(string label, int target) mir_control_edge {
    mir_control_edge {
        label: label, target target, args mir_operand[](),
    }
}

func vec1_edge(string label, int target) mir_control_edge[] {
    edges := mir_control_edge[]()
    edges = append(edges, make_edge(label, target))
    edges
}

func ir_make_block(int id, string label, string[] lines, string term_kind, mir_control_edge[] edges) mir_basic_block {
    make_block_with_condition(id, label, lines, term_kind, option.none, edges)
}

func make_block_with_condition(int id, string label, string[] lines, string term_kind, option[mir_operand] condition, mir_control_edge[] edges) mir_basic_block {
    statements := mir_statement[]()
    i := 0
    for i < len(lines) {
        args := string[]()
        args = append(args, lines[i])
        statements.push(mir_statement.eval(mir_eval_stmt {
            op: "line", args args,
        }))
        i = i + 1
    }
    mir_basic_block {
        id: id, label label, statements statements, terminator mir_terminator {
            kind: term_kind, condition: condition, edges edges,
        },
    }
}

func make_entry_block(int id, string label, string[] lines, stmt[] source_statements, string term_kind, mir_control_edge[] edges) mir_basic_block {
    make_entry_block_with_condition(id, label, lines, source_statements, term_kind, option.none, edges)
}

func make_entry_block_with_condition(int id, string label, string[] lines, stmt[] source_statements, string term_kind, option[mir_operand] condition, mir_control_edge[] edges) mir_basic_block {
    statements := mir_statement[]()
    i := 0
    for i < len(lines) {
        args := string[]()
        args = append(args, lines[i])
        statements.push(mir_statement.eval(mir_eval_stmt {
            op: "line", args args,
        }))
        if i < len(source_statements) {
            compile.internal.mir.mir_append_ownership_semantics_from_stmt(statements, source_statements[i])
        }
        i = i + 1
    }
    mir_basic_block {
        id: id, label label, statements statements, terminator mir_terminator {
            kind: term_kind, condition: condition, edges edges,
        },
    }
}

func make_graph(string function_name, mir_basic_block[] blocks, string[] trace, int entry, int exit) mir_graph {
    mir_graph {
        function_name: function_name, blocks blocks, locals mir_local_slot[](), trace trace, entry entry, exit exit,
        borrow_ok: true, borrow_errors: 0, borrow_message: "",
    }
}

func lowered_view_block_name(int id) string {
    "bb" + std.prelude.to_string(id)
}

func lowered_view_from_mir(mir_graph graph) string {
    out := "canonical-lowered-view version=1\n"
    out = out + "view-role=READ_ONLY\n"
    out = out + "function " + graph.function_name + "\n"
    out = out + "entry-block=" + lowered_view_block_name(graph.entry) + "\n"
    i := 0
    for i < len(graph.blocks) {
        block := graph.blocks[i]
        out = out + "block " + lowered_view_block_name(block.id) + "\n"
        if block.label == "while.cond" {
            out = out + "loop-header=" + lowered_view_block_name(block.id) + "\n"
            out = out + "loop-header-origin=canonical-mir\n"
        }
        if block.terminator.kind == "branch" {
            if block.terminator.condition.is_some() {
                condition := block.terminator.condition.unwrap()
                out = out + "branch-condition=" + condition.value + "\n"
                out = out + "branch-condition-origin=canonical-mir-terminator\n"
                if block.label == "while.cond" {
                    out = out + "loop-condition=" + condition.value + "\n"
                    out = out + "loop-condition-origin=canonical-mir-terminator\n"
                }
            }
            edge_index := 0
            while edge_index < len(block.terminator.edges) {
                edge := block.terminator.edges[edge_index]
                if edge.label == "then" {
                    out = out + "true-edge=" + lowered_view_block_name(edge.target) + "\n"
                    out = out + "true-edge-origin=canonical-mir-terminator\n"
                }
                if edge.label == "else" {
                    out = out + "false-edge=" + lowered_view_block_name(edge.target) + "\n"
                    out = out + "false-edge-origin=canonical-mir-terminator\n"
                }
                if block.label == "while.cond" && edge.label == "true" {
                    out = out + "loop-body-edge=" + lowered_view_block_name(edge.target) + "\n"
                    out = out + "loop-body-edge-origin=canonical-mir-terminator\n"
                }
                if block.label == "while.cond" && edge.label == "false" {
                    out = out + "loop-exit-edge=" + lowered_view_block_name(edge.target) + "\n"
                    out = out + "loop-exit-edge-origin=canonical-mir-terminator\n"
                }
                edge_index = edge_index + 1
            }
        }
        if block.label == "while.body" && block.terminator.kind == "jump" {
            edge_index := 0
            while edge_index < len(block.terminator.edges) {
                edge := block.terminator.edges[edge_index]
                if edge.label == "cond" {
                    out = out + "loop-backedge=" + lowered_view_block_name(edge.target) + "\n"
                    out = out + "loop-backedge-origin=canonical-mir\n"
                }
                edge_index = edge_index + 1
            }
        }
        i = i + 1
    }
    out
}
