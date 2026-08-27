package compile.internal.ir.lower
use s.source_file
use s.expr
use s.stmt
use s.block_expr
use s.function_decl
use s.item
use s.dump_expr
use compile.internal.ir.ast as ir_ast
use compile.internal.mir.mir_graph
use compile.internal.mir.mir_basic_block
use compile.internal.mir.mir_statement
use compile.internal.mir.mir_eval_stmt
use compile.internal.mir.mir_terminator
use compile.internal.mir.mir_control_edge
use compile.internal.mir.mir_local_slot
use compile.internal.mir.mir_operand
use compile.internal.backend_elf64.parse_int_literal as parse_int_literal
use std.slices

struct const_rewrite_entry {
    string name
    string expr_text
    string value_kind
    int int_value
    string string_value
    bool bool_value
}

func from_syntax(source_file src) ir_ast.package_ir {
    pkg := ir_ast.package_ir { name: src.pkg, decls: ir_ast.decl_ir[]() }
    const_entries := collect_const_rewrite_entries(src)
    i := 0
    for i < len(src.items) {
        it := src.items[i]
        switch it {
            item.function(function_decl) : {
                fd := convert_function(function_decl, const_entries)
                pkg.decls = append(pkg.decls, ir_ast.decl_ir::func(fd))
            }
            item.const(const_decl) : {
                value_text := lookup_const_expr_text(const_entries, const_decl.name)
                pkg.decls.push(ir_ast.decl_ir::const(ir_ast.const_decl {
                    name: const_decl.name,
                    value: value_text,
                }))
            }
            item.struct(struct_decl) : {
                pkg.decls = append(pkg.decls, ir_ast.decl_ir::r#type(ir_ast.type_decl { name: struct_decl.name, type_expr: "struct" }))
            }
            item.enum(enum_decl) : {
                pkg.decls = append(pkg.decls, ir_ast.decl_ir::r#type(ir_ast.type_decl { name: enum_decl.name, type_expr: "enum" }))
            }
            item.trait(trait_decl) : {
                pkg.decls = append(pkg.decls, ir_ast.decl_ir::r#type(ir_ast.type_decl { name: trait_decl.name, type_expr: "trait" }))
            }
            item.method(method_decl) : {
                pkg.decls.push(ir_ast.decl_ir::method(ir_ast.method_decl {
                    receiver_name: method_decl.receiver_name,
                    receiver_type: method_decl.receiver_type,
                    method: convert_function(method_decl.method, const_entries),
                }))
            }
        }
        i = i + 1
    }
    pkg
}

func from_syntax_checked(source_file src) (ir_ast.package_ir, string) {
    pkg := from_syntax(src)
    check := validate_lowering_contract(pkg)
    if check.is_err() {
        return check.unwrap_err()
    }
    pkg
}

func validate_lowering_contract(ir_ast.package_ir pkg) ((), string) {
    i := 0
    for i < len(pkg.decls) {
        switch pkg.decls[i] {
            ir_ast.decl_ir::func(fd) : {
                if fd.body.is_some() {
                    checked := validate_block_contract(fd.body.unwrap())
                    if checked.is_err() {
                        return checked
                    }
                }
            }
            _ : (),
        }
        i = i + 1
    }
    ()
}

func validate_block_contract(ir_ast.block_ir block) ((), string) {
    i := 0
    for i < len(block.statements) {
        switch block.statements[i] {
            ir_ast.stmt_ir::let(var_stmt) : {
                checked := validate_expr_contract(var_stmt.value)
                if checked.is_err() {
                    return checked
                }
            }
            ir_ast.stmt_ir::assign(assign_stmt) : {
                checked := validate_expr_contract(assign_stmt.value)
                if checked.is_err() {
                    return checked
                }
            }
            ir_ast.stmt_ir::expr(expr_stmt) : {
                checked := validate_expr_contract(expr_stmt.expr)
                if checked.is_err() {
                    return checked
                }
            }
            ir_ast.stmt_ir::r#return(return_stmt) : {
                if return_stmt.value.is_some() {
                    checked := validate_expr_contract(return_stmt.value.unwrap())
                    if checked.is_err() {
                        return checked
                    }
                }
            }
            ir_ast.stmt_ir::cfor(c_for_stmt) : {
                cond_checked := validate_expr_contract(c_for_stmt.condition)
                if cond_checked.is_err() {
                    return cond_checked
                }
                body_checked := validate_block_contract(c_for_stmt.body)
                if body_checked.is_err() {
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
    ()
}

func validate_expr_contract(ir_ast.expr_ir expression) ((), string) {
    switch expression {
        ir_ast.expr_ir::name(name) : {
            if contains_text(name, "_unlowered") {
                return "lowering contract violation: placeholder expression remains"
            }
        }
        ir_ast.expr_ir::call(call_expr) : {
            i := 0
            for i < len(call_expr.args) {
                checked := validate_expr_contract(call_expr.args[i])
                if checked.is_err() {
                    return checked
                }
                i = i + 1
            }
        }
        ir_ast.expr_ir::binary(binary_expr) : {
            l := validate_expr_contract(binary_expr.left)
            if l.is_err() {
                return l
            }
            return validate_expr_contract(binary_expr.right
        }
        ir_ast.expr_ir::borrow(borrow_expr) : {
            return validate_expr_contract(borrow_expr.target
        }
        ir_ast.expr_ir::member(member_expr) : {
            return validate_expr_contract(member_expr.target
        }
        ir_ast.expr_ir::index(index_expr) : {
            t := validate_expr_contract(index_expr.target)
            if t.is_err() {
                return t
            }
            return validate_expr_contract(index_expr.index
        }
        ir_ast.expr_ir::array(array_expr) : {
            i := 0
            for i < len(array_expr.items) {
                checked := validate_expr_contract(array_expr.items[i])
                if checked.is_err() {
                    return checked
                }
                i = i + 1
            }
        }
        ir_ast.expr_ir::map(map_expr) : {
            i := 0
            for i < len(map_expr.entries) {
                key_checked := validate_expr_contract(map_expr.entries[i].key)
                if key_checked.is_err() {
                    return key_checked
                }
                value_checked := validate_expr_contract(map_expr.entries[i].value)
                if value_checked.is_err() {
                    return value_checked
                }
                i = i + 1
            }
        }
        ir_ast.expr_ir::block(block_expr) : {
            return validate_block_contract(block_expr
        }
        _ : (),
    }
    ()
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
        if slice(text, i, i + len(needle)) == needle {
            return true
        }
        i = i + 1
    }
    false
}

func convert_function(function_decl fd, const_rewrite_entry[] const_entries) ir_ast.func_decl {
    sig := ir_ast.func_sig { params: ir_ast.param[](), return_type_name: option[string].none, generics: fd.sig.generics }
    pi := 0
    for pi < len(fd.sig.params) {
        p := fd.sig.params[pi]
        sig.params = append(sig.params, ir_ast.param { name: p.name, type_name: p.type_name })
        pi = pi + 1
    }
    ret := option[string].none
    if fd.sig.return_type.is_some() {
        ret = option[string].some(fd.sig.return_type.unwrap())
    }
    sig.return_type_name = ret
    body := option[ir_ast.block_ir].none
    if fd.body.is_some() {
        body = option[ir_ast.block_ir].some(convert_block(fd.body.unwrap(), const_entries))
    }
    ir_ast.func_decl { name: fd.sig.name, sig: sig, body: body }
}

func convert_block(block_expr b, const_rewrite_entry[] const_entries) ir_ast.block_ir {
    stmts := ir_ast.stmt_ir[]()
    si := 0
    for si < len(b.statements) {
        stmts = append(stmts, convert_stmt(b.statements[si], const_entries))
        si = si + 1
    }
    final := option[ir_ast.expr_ir].none
    if b.final_expr.is_some() {
        final = option[ir_ast.expr_ir].some(convert_expr(b.final_expr.unwrap(), const_entries))
    }
    ir_ast.block_ir { statements: stmts, final_expr: final }
}

func convert_stmt(stmt s, const_rewrite_entry[] const_entries) ir_ast.stmt_ir {
    switch s {
        stmt.let(var_stmt) : {
            ir_ast.stmt_ir::let(ir_ast.var_stmt { name: var_stmt.name, type_name: var_stmt.type_name, value: convert_expr(var_stmt.value, const_entries) })
        }
        stmt.assign(assign_stmt) : {
            ir_ast.stmt_ir::assign(ir_ast.assign_stmt { name: assign_stmt.name, value: convert_expr(assign_stmt.value, const_entries) })
        }
        stmt.increment(increment_stmt) : {
            ir_ast.stmt_ir::increment(ir_ast.increment_stmt { name: increment_stmt.name })
        }
        stmt.c_for(c_for_stmt) : {
            ir_ast.stmt_ir::cfor(ir_ast.c_for_stmt {
                init: convert_stmt(c_for_stmt.init.value, const_entries),
                condition: convert_expr(c_for_stmt.condition, const_entries),
                step: convert_stmt(c_for_stmt.step.value, const_entries),
                body: convert_block(c_for_stmt.body, const_entries),
            })
        }
        stmt.return(return_stmt) : {
            if return_stmt.value.is_some() {
                ir_ast.stmt_ir::r#return(ir_ast.return_stmt { value: option[ir_ast.expr_ir].some(convert_expr(return_stmt.value.unwrap(), const_entries)) })
            } else {
                ir_ast.stmt_ir::r#return(ir_ast.return_stmt { value: option[ir_ast.expr_ir].none })
            }
        }
        stmt.expr(expr_stmt) : {
            ir_ast.stmt_ir::expr(ir_ast.expr_stmt { expr: convert_expr(expr_stmt.expr, const_entries) })
        }
        stmt.defer(defer_stmt) : {
            ir_ast.stmt_ir::expr(ir_ast.expr_stmt { expr: convert_expr(defer_stmt.expr, const_entries) })
        }
        stmt.sroutine(sroutine_stmt) : {
            ir_ast.stmt_ir::expr(ir_ast.expr_stmt { expr: convert_expr(sroutine_stmt.expr, const_entries) })
        }
    }
}

func convert_expr(expr e, const_rewrite_entry[] const_entries) ir_ast.expr_ir {
    switch e {
        expr.int(int_expr) : {
            n := parse_int_literal(int_expr.value)
            ir_ast.expr_ir::int(n)
        }
        expr.string(string_expr) : ir_ast.expr_ir::string(string_expr.value),
        expr.bool(bool_expr) : ir_ast.expr_ir::bool(bool_expr.value),
        expr.name(name_expr) : resolve_const_name_expr(name_expr.name, const_entries),
        expr.borrow(borrow_expr) : ir_ast.expr_ir::borrow(ir_ast.borrow_expr { target: convert_expr(borrow_expr.target.unwrap(), const_entries), mutable: borrow_expr.mutable }),
        expr.binary(binary_expr) : ir_ast.expr_ir::binary(ir_ast.binary_expr { op: binary_expr.op, left: convert_expr(binary_expr.left.unwrap(), const_entries), right: convert_expr(binary_expr.right.unwrap(), const_entries) }),
        expr.call(call_expr) : {
            callee_name := "<call>"
            switch call_expr.callee.unwrap() {
                expr.name(name_expr) : callee_name = name_expr.name,
                _ : callee_name = "<expr-callee>",
            }
            args := ir_ast.expr_ir[]()
            ai := 0
            for ai < len(call_expr.args) {
                args = append(args, convert_expr(call_expr.args[ai], const_entries))
                ai = ai + 1
            }
            ir_ast.expr_ir::call(ir_ast.call_expr { callee: callee_name, args: args })
        }
        expr.if(if_expr) : ir_ast.expr_ir::call(ir_ast.call_expr { callee: "if_expr", args: ir_ast.expr_ir[]() }),
        expr.block(block_expr) : ir_ast.expr_ir::block(convert_block(block_expr, const_entries)),
        expr.switch(switch_expr) : ir_ast.expr_ir::call(ir_ast.call_expr { callee: "switch_expr", args: ir_ast.expr_ir[]() }),
        expr.while(while_expr) : ir_ast.expr_ir::call(ir_ast.call_expr { callee: "while_expr", args: ir_ast.expr_ir[]() }),
        expr.for(for_expr) : ir_ast.expr_ir::call(ir_ast.call_expr { callee: "for_expr", args: ir_ast.expr_ir[]() }),
        expr.member(member_expr) : ir_ast.expr_ir::member(ir_ast.member_expr {
            target: convert_expr(member_expr.target.value, const_entries),
            member: member_expr.member,
        }),
        expr.index(index_expr) : ir_ast.expr_ir::index(ir_ast.index_expr {
            target: convert_expr(index_expr.target.value, const_entries),
            index: convert_expr(index_expr.index.value, const_entries),
        }),
        expr.array(array_literal) : array_to_expr(array_literal, const_entries),
        expr.map(map_literal) : map_to_expr(map_literal, const_entries),
    }
}

func lower_main_to_mir(source_file src) (mir_graph, string) {
    return lower_package_to_mir(src
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
        return "entry function not found: package has no function body"
    }
    picked := option[function_decl].none
    fallback := option[function_decl].none
    i := 0
    for i < len(src.items) {
        switch src.items[i] {
            item.function(function_decl) : {
                if function_decl.body.is_some() {
                    if fallback.is_none() {
                        fallback = option[function_decl].some(function_decl)
                    }
                    if function_decl.sig.name == "main" {
                        picked = option[function_decl].some(function_decl)
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
        return "entry function not found"
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
    graph
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
        stmt.let(var_stmt) : count_const_hits_expr(var_stmt.value, const_entries),
        stmt.assign(assign_stmt) : count_const_hits_expr(assign_stmt.value, const_entries),
        stmt.increment(_) : 0,
        stmt.return(return_stmt) : {
            if return_stmt.value.is_some() {
                return count_const_hits_expr(return_stmt.value.unwrap(), const_entries
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
        expr.for(for_expr) : count_const_hits_expr(for_expr.iterable.value, const_entries) + count_const_hits_block(for_expr.body, const_entries),
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

func stmt_to_expr(stmt s, const_rewrite_entry[] const_entries) ir_ast.expr_ir {
    switch s {
        stmt.let(var_stmt) : ir_ast.expr_ir::call(ir_ast.call_expr {
            callee: "stmt.let",
            args: ir_ast.expr_ir[] { ir_ast.expr_ir::string(var_stmt.name), convert_expr(var_stmt.value, const_entries) },
        }),
        stmt.assign(assign_stmt) : ir_ast.expr_ir::call(ir_ast.call_expr {
            callee: "stmt.assign",
            args: ir_ast.expr_ir[] { ir_ast.expr_ir::string(assign_stmt.name), convert_expr(assign_stmt.value, const_entries) },
        }),
        stmt.increment(increment_stmt) : ir_ast.expr_ir::call(ir_ast.call_expr {
            callee: "stmt.increment",
            args: ir_ast.expr_ir[] { ir_ast.expr_ir::string(increment_stmt.name) },
        }),
        stmt.return(return_stmt) : {
            if return_stmt.value.is_some() {
                return ir_ast.expr_ir::call(ir_ast.call_expr {
                    callee: "stmt.return",
                    args: ir_ast.expr_ir[] { convert_expr(return_stmt.value.unwrap(), const_entries) },
                })
            }
            ir_ast.expr_ir::call(ir_ast.call_expr {
                callee: "stmt.return",
                args: ir_ast.expr_ir[](),
            })
        }
        stmt.expr(expr_stmt) : ir_ast.expr_ir::call(ir_ast.call_expr {
            callee: "stmt.expr",
            args: ir_ast.expr_ir[] { convert_expr(expr_stmt.expr, const_entries) },
        }),
        stmt.defer(defer_stmt) : ir_ast.expr_ir::call(ir_ast.call_expr {
            callee: "stmt.defer",
            args: ir_ast.expr_ir[] { convert_expr(defer_stmt.expr, const_entries) },
        }),
        stmt.sroutine(sroutine_stmt) : ir_ast.expr_ir::call(ir_ast.call_expr {
            callee: "stmt.sroutine",
            args: ir_ast.expr_ir[] { convert_expr(sroutine_stmt.expr, const_entries) },
        }),
        stmt.c_for(c_for_stmt) : ir_ast.expr_ir::call(ir_ast.call_expr {
            callee: "stmt.c_for",
            args: ir_ast.expr_ir[] {
                stmt_to_expr(c_for_stmt.init.value, const_entries),
                convert_expr(c_for_stmt.condition, const_entries),
                stmt_to_expr(c_for_stmt.step.value, const_entries),
                block_to_expr(c_for_stmt.body, const_entries),
            },
        }),
    }
}

func block_to_expr(block_expr block, const_rewrite_entry[] const_entries) ir_ast.expr_ir {
    ir_ast.expr_ir::block(convert_block(block, const_entries))
}

func array_to_expr(array_literal lit, const_rewrite_entry[] const_entries) ir_ast.expr_ir {
    items := ir_ast.expr_ir[]()
    i := 0
    for i < len(lit.items) {
        items = append(items, convert_expr(lit.items[i], const_entries))
        i = i + 1
    }
    ir_ast.expr_ir::array(ir_ast.array_expr {
        type_name: lit.type_text,
        items: items,
    })
}

func map_to_expr(map_literal lit, const_rewrite_entry[] const_entries) ir_ast.expr_ir {
    entries := ir_ast.map_entry_expr[]()
    i := 0
    for i < len(lit.entries) {
        entry := lit.entries[i]
        entries.push(ir_ast.map_entry_expr {
            key: convert_expr(entry.key, const_entries),
            value: convert_expr(entry.value, const_entries),
        })
        i = i + 1
    }
    ir_ast.expr_ir::map(ir_ast.map_expr {
        type_name: lit.type_text,
        entries: entries,
    })
}

func lower_function_to_mir(function_decl fd, const_rewrite_entry[] const_entries) mir_graph {
    if fd.body.is_none() {
        empty_blocks := mir_basic_block[]()
        empty_blocks = append(empty_blocks, make_block(0, "entry", string[](), "return", mir_control_edge[]()))
        return mir_graph {
            function_name: fd.sig.name,
            blocks: empty_blocks,
            locals: mir_local_slot[](),
            trace: string[](),
            entry: 0,
            exit: 0,
        }
    }
    return lower_block_to_mir(fd.sig.name, fd.body.unwrap(), const_entries
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
                blocks = append(blocks, make_block(0, "entry", stmt_texts, "branch", entry_edges))
                then_lines := string[]()
                then_lines = append(then_lines, "if.then")
                blocks = append(blocks, make_block(1, "if.then", then_lines, "jump", vec1_edge("merge", 3)))
                else_lines := string[]()
                else_lines = append(else_lines, "if.else")
                blocks = append(blocks, make_block(2, "if.else", else_lines, "jump", vec1_edge("merge", 3)))
                merge_lines := string[]()
                merge_lines = append(merge_lines, "yield " + dump_expr(tail))
                blocks = append(blocks, make_block(3, "if.merge", merge_lines, "return", mir_control_edge[]()))
                trace = append(trace, "control if -> blocks(entry, if.then, if.else, if.merge)")
                return make_graph(function_name, blocks, trace, 0, 3
            }
            expr.while(while_expr) : {
                blocks = append(blocks, make_block(0, "entry", stmt_texts, "jump", vec1_edge("cond", 1)))
                cond_lines := string[]()
                cond_lines = append(cond_lines, "while.cond " + substitute_const_text(dump_expr(while_expr.condition.value), const_entries))
                cond_edges := mir_control_edge[]()
                cond_edges = append(cond_edges, make_edge("true", 2))
                cond_edges = append(cond_edges, make_edge("false", 3))
                blocks = append(blocks, make_block(1, "while.cond", cond_lines, "branch", cond_edges))
                body_lines := string[]()
                body_lines = append(body_lines, "while.body")
                blocks = append(blocks, make_block(2, "while.body", body_lines, "jump", vec1_edge("cond", 1)))
                exit_lines := string[]()
                exit_lines = append(exit_lines, "yield unit")
                blocks = append(blocks, make_block(3, "while.exit", exit_lines, "return", mir_control_edge[]()))
                trace = append(trace, "control while -> blocks(entry, while.cond, while.body, while.exit)")
                return make_graph(function_name, blocks, trace, 0, 3
            }
            expr.switch(switch_expr) : {
                dispatch_edges := mir_control_edge[]()
                dispatch_edges = append(dispatch_edges, make_edge("case0", 1))
                dispatch_edges = append(dispatch_edges, make_edge("case1", 2))
                dispatch_edges = append(dispatch_edges, make_edge("default", 3))
                blocks = append(blocks, make_block(0, "entry", stmt_texts, "branch", dispatch_edges))
                blocks = append(blocks, make_block(1, "switch.case0", vec1("switch.case0"), "jump", vec1_edge("merge", 4)))
                blocks = append(blocks, make_block(2, "switch.case1", vec1("switch.case1"), "jump", vec1_edge("merge", 4)))
                blocks = append(blocks, make_block(3, "switch.default", vec1("switch.default"), "jump", vec1_edge("merge", 4)))
                blocks = append(blocks, make_block(4, "switch.merge", vec1("yield " + substitute_const_text(dump_expr(tail), const_entries)), "return", mir_control_edge[]()))
                trace = append(trace, "control switch -> blocks(entry, switch.case0, switch.case1, switch.default, switch.merge)")
                return make_graph(function_name, blocks, trace, 0, 4
            }
            expr.for(for_expr) : {
                blocks = append(blocks, make_block(0, "entry", stmt_texts, "jump", vec1_edge("for.cond", 1)))
                cond_edges := mir_control_edge[]()
                cond_edges = append(cond_edges, make_edge("next", 2))
                cond_edges = append(cond_edges, make_edge("exit", 3))
                blocks = append(blocks, make_block(1, "for.cond", vec1("for.cond"), "branch", cond_edges))
                blocks = append(blocks, make_block(2, "for.body", vec1("for.body"), "jump", vec1_edge("for.cond", 1)))
                blocks = append(blocks, make_block(3, "for.exit", vec1("yield unit"), "return", mir_control_edge[]()))
                trace = append(trace, "control for -> blocks(entry, for.cond, for.body, for.exit)")
                return make_graph(function_name, blocks, trace, 0, 3
            }
            _ : (),
        }
    }
    final_lines := clone_lines(stmt_texts)
    if block.final_expr.is_some() {
        final_lines = append(final_lines, "yield " + substitute_const_text(dump_expr(block.final_expr.unwrap()), const_entries))
    } else {
        final_lines = append(final_lines, "yield unit")
    }
    blocks = append(blocks, make_block(0, "entry", final_lines, "return", mir_control_edge[]()))
    make_graph(function_name, blocks, trace, 0, 0)
}

func dump_expr_stmt(stmt s, const_rewrite_entry[] const_entries) string {
    switch s {
        stmt.let(var_stmt) : "let " + var_stmt.name,
        stmt.assign(assign_stmt) : "assign " + assign_stmt.name,
        stmt.increment(increment_stmt) : "increment " + increment_stmt.name,
        stmt.return(return_stmt) : "return",
        stmt.expr(expr_stmt) : "expr " + substitute_const_text(dump_expr(expr_stmt.expr), const_entries),
        stmt.defer(defer_stmt) : "defer " + substitute_const_text(dump_expr(defer_stmt.expr), const_entries),
        stmt.sroutine(sroutine_stmt) : "sroutine " + substitute_const_text(dump_expr(sroutine_stmt.expr), const_entries),
        stmt.c_for(c_for_stmt) : "c_for",
    }
}

func collect_const_rewrite_entries(source_file src) const_rewrite_entry[] {
    out := const_rewrite_entry[]()
    last_value := const_rewrite_entry {
        name: "",
        expr_text: "",
        value_kind: "unknown",
        int_value: 0,
        string_value: "",
        bool_value: false,
    }
    i := 0
    for i < len(src.items) {
        switch src.items[i] {
            item.const(const_decl) : {
                folded := const_rewrite_entry {
                    name: const_decl.name,
                    expr_text: "",
                    value_kind: "unknown",
                    int_value: 0,
                    string_value: "",
                    bool_value: false,
                }
                switch const_decl.value {
                    option.some(value) : {
                        folded = render_const_folded_entry(const_decl.name, value, out, const_decl.iota_index)
                        last_value = folded
                    }
                    option.none : {
                        folded = const_rewrite_entry {
                            name: const_decl.name,
                            expr_text: last_value.expr_text,
                            value_kind: last_value.value_kind,
                            int_value: last_value.int_value,
                            string_value: last_value.string_value,
                            bool_value: last_value.bool_value,
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
            name: name,
            expr_text: const_fold_value_text(folded),
            value_kind: folded.value_kind,
            int_value: folded.int_value,
            string_value: folded.string_value,
            bool_value: folded.bool_value,
        }
    }
    const_rewrite_entry {
        name: name,
        expr_text: substitute_const_text(dump_expr(value), out),
        value_kind: "unknown",
        int_value: 0,
        string_value: "",
        bool_value: false,
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
            value_kind: "int",
            int_value: parse_int_literal(int_expr.value),
            string_value: "",
            bool_value: false,
        },
        expr.string(string_expr) : const_fold_value {
            value_kind: "string",
            int_value: 0,
            string_value: string_expr.value,
            bool_value: false,
        },
        expr.bool(bool_expr) : const_fold_value {
            value_kind: "bool",
            int_value: 0,
            string_value: "",
            bool_value: bool_expr.value,
        },
        expr.name(name_expr) : {
            if name_expr.name == "iota" {
                return const_fold_value {
                    value_kind: "int",
                    int_value: iota_index,
                    string_value: "",
                    bool_value: false,
                }
            }
            entry := lookup_const_entry(out, name_expr.name)
            if entry.is_none() {
                return const_fold_value {
                    value_kind: "unknown",
                    int_value: 0,
                    string_value: "",
                    bool_value: false,
                }
            }
            e := entry.unwrap()
            const_fold_value {
                value_kind: e.value_kind,
                int_value: e.int_value,
                string_value: e.string_value,
                bool_value: e.bool_value,
            }
        }
        expr.binary(binary_expr) : {
            left := eval_const_fold_value(binary_expr.left.value, out, iota_index)
            right := eval_const_fold_value(binary_expr.right.value, out, iota_index)
            return eval_const_fold_binary(binary_expr.op, left, right
        }
        _ : const_fold_value {
            value_kind: "unknown",
            int_value: 0,
            string_value: "",
            bool_value: false,
        },
    }
}

func eval_const_fold_binary(string op, const_fold_value left, const_fold_value right) const_fold_value {
    if left.value_kind == "int" && right.value_kind == "int" {
        if op == "+" {
            return const_fold_value { value_kind: "int", int_value: left.int_value + right.int_value, string_value: "", bool_value: false }
        }
        if op == "-" {
            return const_fold_value { value_kind: "int", int_value: left.int_value - right.int_value, string_value: "", bool_value: false }
        }
        if op == "*" {
            return const_fold_value { value_kind: "int", int_value: left.int_value * right.int_value, string_value: "", bool_value: false }
        }
        if op == "/" && right.int_value != 0 {
            return const_fold_value { value_kind: "int", int_value: left.int_value / right.int_value, string_value: "", bool_value: false }
        }
        if op == "%" && right.int_value != 0 {
            return const_fold_value { value_kind: "int", int_value: left.int_value % right.int_value, string_value: "", bool_value: false }
        }
        if op == "==" {
            return const_fold_value { value_kind: "bool", int_value: 0, string_value: "", bool_value: left.int_value == right.int_value }
        }
        if op == "!=" {
            return const_fold_value { value_kind: "bool", int_value: 0, string_value: "", bool_value: left.int_value != right.int_value }
        }
    }
    if left.value_kind == "bool" && right.value_kind == "bool" {
        if op == "&&" {
            return const_fold_value { value_kind: "bool", int_value: 0, string_value: "", bool_value: left.bool_value && right.bool_value }
        }
        if op == "||" {
            return const_fold_value { value_kind: "bool", int_value: 0, string_value: "", bool_value: left.bool_value || right.bool_value }
        }
        if op == "==" {
            return const_fold_value { value_kind: "bool", int_value: 0, string_value: "", bool_value: left.bool_value == right.bool_value }
        }
        if op == "!=" {
            return const_fold_value { value_kind: "bool", int_value: 0, string_value: "", bool_value: left.bool_value != right.bool_value }
        }
    }
    if left.value_kind == "string" && right.value_kind == "string" {
        if op == "+" {
            return const_fold_value { value_kind: "string", int_value: 0, string_value: left.string_value + right.string_value, bool_value: false }
        }
        if op == "==" {
            return const_fold_value { value_kind: "bool", int_value: 0, string_value: "", bool_value: left.string_value == right.string_value }
        }
        if op == "!=" {
            return const_fold_value { value_kind: "bool", int_value: 0, string_value: "", bool_value: left.string_value != right.string_value }
        }
    }
    const_fold_value {
        value_kind: "unknown",
        int_value: 0,
        string_value: "",
        bool_value: false,
    }
}

func const_fold_value_text(const_fold_value value) string {
    if value.value_kind == "int" {
        return to_string(value.int_value
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
            return option::some(entries[i]
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

func resolve_const_name_expr(string name, const_rewrite_entry[] const_entries) ir_ast.expr_ir {
    entry := lookup_const_entry(const_entries, name)
    if entry.is_none() {
        return ir_ast.expr_ir::name(name
    }
    value := entry.unwrap()
    if value.value_kind == "int" {
        return ir_ast.expr_ir::int(value.int_value
    }
    if value.value_kind == "bool" {
        return ir_ast.expr_ir::bool(value.bool_value
    }
    if value.value_kind == "string" {
        return ir_ast.expr_ir::string(value.string_value
    }
    ir_ast.expr_ir::name(name)
}
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
        if i + len(ident) <= len(text) && slice(text, i, i + len(ident)) == ident {
            left_ok := i == 0 || !is_ident_char(slice(text, i - 1, i))
            right_ok := i + len(ident) == len(text) || !is_ident_char(slice(text, i + len(ident), i + len(ident) + 1))
            if left_ok && right_ok {
                out = out + replacement
                i = i + len(ident)
                continue
            }
        }
        out = out + slice(text, i, i + 1)
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
        label: label,
        target: target,
        args: mir_operand[](),
    }
}

func vec1_edge(string label, int target) mir_control_edge[] {
    edges := mir_control_edge[]()
    edges = append(edges, make_edge(label, target))
    edges
}

func make_block(int id, string label, string[] lines, string term_kind, mir_control_edge[] edges) mir_basic_block {
    statements := mir_statement[]()
    i := 0
    for i < len(lines) {
        args := string[]()
        args = append(args, lines[i])
        statements.push(mir_statement::eval(mir_eval_stmt {
            op: "line",
            args: args,
        }))
        i = i + 1
    }
    mir_basic_block {
        id: id,
        label: label,
        statements: statements,
        terminator: mir_terminator {
            kind: term_kind,
            edges: edges,
        },
    }
}

func make_graph(string function_name, mir_basic_block[] blocks, string[] trace, int entry, int exit) mir_graph {
    mir_graph {
        function_name: function_name,
        blocks: blocks,
        locals: mir_local_slot[](),
        trace: trace,
        entry: entry,
        exit: exit,
    }
}
