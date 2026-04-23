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
use std.vec.vec

func from_syntax(source_file src) ir_ast.package_ir {
    var pkg = ir_ast.package_ir { name: src.pkg, decls: vec[ir_ast.decl_ir]() }

    var i = 0
    while i < src.items.len() {
        var it = src.items[i]
        switch it {
            item.function(function_decl) : {
                var fd = convert_function(function_decl)
                pkg.decls.push(ir_ast.decl_ir::func(fd))
            }
            item.struct(struct_decl) : {
                pkg.decls.push(ir_ast.decl_ir::r#type(ir_ast.type_decl { name: struct_decl.name, type_expr: "struct" }))
            }
            item.enum(enum_decl) : {
                pkg.decls.push(ir_ast.decl_ir::r#type(ir_ast.type_decl { name: enum_decl.name, type_expr: "enum" }))
            }
            item.trait(trait_decl) : {
                pkg.decls.push(ir_ast.decl_ir::r#type(ir_ast.type_decl { name: trait_decl.name, type_expr: "trait" }))
            }
            item.impl(impl_decl) : {
                var methods = vec[ir_ast.func_decl]()
                var mi = 0
                while mi < impl_decl.methods.len() {
                    methods.push(convert_function(impl_decl.methods[mi]))
                    mi = mi + 1
                }
                pkg.decls.push(ir_ast.decl_ir::impl(ir_ast.impl_decl { type_name: impl_decl.target, methods: methods }))
            }
        }
        i = i + 1
    }

    pkg
}

func from_syntax_checked(source_file src) result[ir_ast.package_ir, string] {
    var pkg = from_syntax(src)
    var check = validate_lowering_contract(pkg)
    if check.is_err() {
        return result::err(check.unwrap_err())
    }
    result::ok(pkg)
}

func validate_lowering_contract(ir_ast.package_ir pkg) result[(), string] {
    var i = 0
    while i < pkg.decls.len() {
        switch pkg.decls[i] {
            ir_ast.decl_ir::func(fd) : {
                if fd.body.is_some() {
                    var checked = validate_block_contract(fd.body.unwrap())
                    if checked.is_err() {
                        return checked
                    }
                }
            }
            _ : (),
        }
        i = i + 1
    }
    result::ok(())
}

func validate_block_contract(ir_ast.block_ir block) result[(), string] {
    var i = 0
    while i < block.statements.len() {
        switch block.statements[i] {
            ir_ast.stmt_ir::var(var_stmt) : {
                var checked = validate_expr_contract(var_stmt.value)
                if checked.is_err() {
                    return checked
                }
            }
            ir_ast.stmt_ir::assign(assign_stmt) : {
                var checked = validate_expr_contract(assign_stmt.value)
                if checked.is_err() {
                    return checked
                }
            }
            ir_ast.stmt_ir::expr(expr_stmt) : {
                var checked = validate_expr_contract(expr_stmt.expr)
                if checked.is_err() {
                    return checked
                }
            }
            ir_ast.stmt_ir::r#return(return_stmt) : {
                if return_stmt.value.is_some() {
                    var checked = validate_expr_contract(return_stmt.value.unwrap())
                    if checked.is_err() {
                        return checked
                    }
                }
            }
            ir_ast.stmt_ir::cfor(c_for_stmt) : {
                var cond_checked = validate_expr_contract(c_for_stmt.condition)
                if cond_checked.is_err() {
                    return cond_checked
                }
                var body_checked = validate_block_contract(c_for_stmt.body)
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
    result::ok(())
}

func validate_expr_contract(ir_ast.expr_ir expression) result[(), string] {
    switch expression {
        ir_ast.expr_ir::name(name) : {
            if contains_text(name, "_unlowered") {
                return result::err("lowering contract violation: placeholder expression remains")
            }
        }
        ir_ast.expr_ir::call(call_expr) : {
            var i = 0
            while i < call_expr.args.len() {
                var checked = validate_expr_contract(call_expr.args[i])
                if checked.is_err() {
                    return checked
                }
                i = i + 1
            }
        }
        ir_ast.expr_ir::binary(binary_expr) : {
            var l = validate_expr_contract(binary_expr.left)
            if l.is_err() {
                return l
            }
            return validate_expr_contract(binary_expr.right)
        }
        ir_ast.expr_ir::borrow(borrow_expr) : {
            return validate_expr_contract(borrow_expr.target)
        }
        ir_ast.expr_ir::member(member_expr) : {
            return validate_expr_contract(member_expr.target)
        }
        ir_ast.expr_ir::index(index_expr) : {
            var t = validate_expr_contract(index_expr.target)
            if t.is_err() {
                return t
            }
            return validate_expr_contract(index_expr.index)
        }
        ir_ast.expr_ir::array(array_expr) : {
            var i = 0
            while i < array_expr.items.len() {
                var checked = validate_expr_contract(array_expr.items[i])
                if checked.is_err() {
                    return checked
                }
                i = i + 1
            }
        }
        ir_ast.expr_ir::map(map_expr) : {
            var i = 0
            while i < map_expr.entries.len() {
                var key_checked = validate_expr_contract(map_expr.entries[i].key)
                if key_checked.is_err() {
                    return key_checked
                }
                var value_checked = validate_expr_contract(map_expr.entries[i].value)
                if value_checked.is_err() {
                    return value_checked
                }
                i = i + 1
            }
        }
        ir_ast.expr_ir::block(block_expr) : {
            return validate_block_contract(block_expr)
        }
        _ : (),
    }
    result::ok(())
}

func contains_text(string text, string needle) bool {
    if needle == "" {
        return true
    }
    if text.len() < needle.len() {
        return false
    }
    var i = 0
    while i <= text.len() - needle.len() {
        if slice(text, i, i + needle.len()) == needle {
            return true
        }
        i = i + 1
    }
    false
}

func convert_function(function_decl fd) ir_ast.func_decl {
    var sig = ir_ast.func_sig { params: vec[ir_ast.param](), return_type_name: option[string].none, generics: fd.sig.generics }
    var pi = 0
    while pi < fd.sig.params.len() {
        var p = fd.sig.params[pi]
        sig.params.push(ir_ast.param { name: p.name, type_name: p.type_name })
        pi = pi + 1
    }
    var ret = option[string].none
    if fd.sig.return_type.is_some() {
        ret = option[string].some(fd.sig.return_type.unwrap())
    }
    sig.return_type_name = ret

    var body = option[ir_ast.block_ir].none
    if fd.body.is_some() {
        body = option[ir_ast.block_ir].some(convert_block(fd.body.unwrap()))
    }

    ir_ast.func_decl { name: fd.sig.name, sig: sig, body: body }
}

func convert_block(block_expr b) ir_ast.block_ir {
    var stmts = vec[ir_ast.stmt_ir]()
    var si = 0
    while si < b.statements.len() {
        stmts.push(convert_stmt(b.statements[si]))
        si = si + 1
    }

    var final = option[ir_ast.expr_ir].none
    if b.final_expr.is_some() {
        final = option[ir_ast.expr_ir].some(convert_expr(b.final_expr.unwrap()))
    }
    ir_ast.block_ir { statements: stmts, final_expr: final }
}

func convert_stmt(stmt s) ir_ast.stmt_ir {
    switch s {
        stmt.var(var_stmt) : {
            ir_ast.stmt_ir::var(ir_ast.var_stmt { name: var_stmt.name, type_name: var_stmt.type_name, value: convert_expr(var_stmt.value) })
        }
        stmt.assign(assign_stmt) : {
            ir_ast.stmt_ir::assign(ir_ast.assign_stmt { name: assign_stmt.name, value: convert_expr(assign_stmt.value) })
        }
        stmt.increment(increment_stmt) : {
            ir_ast.stmt_ir::increment(ir_ast.increment_stmt { name: increment_stmt.name })
        }
        stmt.c_for(c_for_stmt) : {
            ir_ast.stmt_ir::cfor(ir_ast.c_for_stmt {
                init: convert_stmt(c_for_stmt.init.value),
                condition: convert_expr(c_for_stmt.condition),
                step: convert_stmt(c_for_stmt.step.value),
                body: convert_block(c_for_stmt.body),
            })
        }
        stmt.return(return_stmt) : {
            if return_stmt.value.is_some() {
                ir_ast.stmt_ir::r#return(ir_ast.return_stmt { value: option[ir_ast.expr_ir].some(convert_expr(return_stmt.value.unwrap())) })
            } else {
                ir_ast.stmt_ir::r#return(ir_ast.return_stmt { value: option[ir_ast.expr_ir].none })
            }
        }
        stmt.expr(expr_stmt) : {
            ir_ast.stmt_ir::expr(ir_ast.expr_stmt { expr: convert_expr(expr_stmt.expr) })
        }
        stmt.defer(defer_stmt) : {
            ir_ast.stmt_ir::expr(ir_ast.expr_stmt { expr: convert_expr(defer_stmt.expr) })
        }
    }
}

func convert_expr(expr e) ir_ast.expr_ir {
    switch e {
        expr.int(int_expr) : {
            var n = parse_int_literal(int_expr.value)
            ir_ast.expr_ir::int(n)
        }
        expr.string(string_expr) : ir_ast.expr_ir::string(string_expr.value),
        expr.bool(bool_expr) : ir_ast.expr_ir::bool(bool_expr.value),
        expr.name(name_expr) : ir_ast.expr_ir::name(name_expr.name),
        expr.borrow(borrow_expr) : ir_ast.expr_ir::borrow(ir_ast.borrow_expr { target: convert_expr(borrow_expr.target.unwrap()), mutable: borrow_expr.mutable }),
        expr.binary(binary_expr) : ir_ast.expr_ir::binary(ir_ast.binary_expr { op: binary_expr.op, left: convert_expr(binary_expr.left.unwrap()), right: convert_expr(binary_expr.right.unwrap()) }),
        expr.call(call_expr) : {

            var callee_name = "<call>"
            switch call_expr.callee.unwrap() {
                expr.name(name_expr) : callee_name = name_expr.name,
                _ : callee_name = "<expr-callee>",
            }
            var args = vec[ir_ast.expr_ir]()
            var ai = 0
            while ai < call_expr.args.len() {
                args.push(convert_expr(call_expr.args[ai]))
                ai = ai + 1
            }
            ir_ast.expr_ir::call(ir_ast.call_expr { callee: callee_name, args: args })
        }
        expr.if(if_expr) : ir_ast.expr_ir::call(ir_ast.call_expr { callee: "if_expr", args: vec[ir_ast.expr_ir]() }),
        expr.block(block_expr) : ir_ast.expr_ir::block(convert_block(block_expr)),
        expr.switch(switch_expr) : ir_ast.expr_ir::call(ir_ast.call_expr { callee: "switch_expr", args: vec[ir_ast.expr_ir]() }),
        expr.while(while_expr) : ir_ast.expr_ir::call(ir_ast.call_expr { callee: "while_expr", args: vec[ir_ast.expr_ir]() }),
        expr.for(for_expr) : ir_ast.expr_ir::call(ir_ast.call_expr { callee: "for_expr", args: vec[ir_ast.expr_ir]() }),
        expr.member(member_expr) : ir_ast.expr_ir::member(ir_ast.member_expr {
            target: convert_expr(member_expr.target.value),
            member: member_expr.member,
        }),
        expr.index(index_expr) : ir_ast.expr_ir::index(ir_ast.index_expr {
            target: convert_expr(index_expr.target.value),
            index: convert_expr(index_expr.index.value),
        }),
        expr.array(array_literal) : array_to_expr(array_literal),
        expr.map(map_literal) : map_to_expr(map_literal),
    }
}

func lower_main_to_mir(source_file src) result[mir_graph, string] {
    return lower_package_to_mir(src)
}

func lower_package_to_mir(source_file src) result[mir_graph, string] {
    var fn_count = 0
    var i = 0
    while i < src.items.len() {
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
        return result::err("entry function not found: package has no function body")
    }

    var picked = option[function_decl].none
    var fallback = option[function_decl].none
    var i = 0
    while i < src.items.len() {
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
        return result::err("entry function not found")
    }

    var graph = lower_function_to_mir(picked.unwrap())
    graph.trace.push("package.functions=" + to_string(fn_count))
    var t = 0
    while t < src.items.len() {
        switch src.items[t] {
            item.function(function_decl) : {
                if function_decl.body.is_some() {
                    graph.trace.push("package.fn " + function_decl.sig.name)
                }
            }
            _ : (),
        }
        t = t + 1
    }
    result::ok(graph)
}

func stmt_to_expr(stmt s) ir_ast.expr_ir {
    switch s {
        stmt.var(var_stmt) : ir_ast.expr_ir::call(ir_ast.call_expr {
            callee: "stmt.var",
            args: vec[ir_ast.expr_ir] { ir_ast.expr_ir::string(var_stmt.name), convert_expr(var_stmt.value) },
        }),
        stmt.assign(assign_stmt) : ir_ast.expr_ir::call(ir_ast.call_expr {
            callee: "stmt.assign",
            args: vec[ir_ast.expr_ir] { ir_ast.expr_ir::string(assign_stmt.name), convert_expr(assign_stmt.value) },
        }),
        stmt.increment(increment_stmt) : ir_ast.expr_ir::call(ir_ast.call_expr {
            callee: "stmt.increment",
            args: vec[ir_ast.expr_ir] { ir_ast.expr_ir::string(increment_stmt.name) },
        }),
        stmt.return(return_stmt) : {
            if return_stmt.value.is_some() {
                return ir_ast.expr_ir::call(ir_ast.call_expr {
                    callee: "stmt.return",
                    args: vec[ir_ast.expr_ir] { convert_expr(return_stmt.value.unwrap()) },
                })
            }
            ir_ast.expr_ir::call(ir_ast.call_expr {
                callee: "stmt.return",
                args: vec[ir_ast.expr_ir](),
            })
        }
        stmt.expr(expr_stmt) : ir_ast.expr_ir::call(ir_ast.call_expr {
            callee: "stmt.expr",
            args: vec[ir_ast.expr_ir] { convert_expr(expr_stmt.expr) },
        }),
        stmt.defer(defer_stmt) : ir_ast.expr_ir::call(ir_ast.call_expr {
            callee: "stmt.defer",
            args: vec[ir_ast.expr_ir] { convert_expr(defer_stmt.expr) },
        }),
        stmt.c_for(c_for_stmt) : ir_ast.expr_ir::call(ir_ast.call_expr {
            callee: "stmt.c_for",
            args: vec[ir_ast.expr_ir] {
                stmt_to_expr(c_for_stmt.init.value),
                convert_expr(c_for_stmt.condition),
                stmt_to_expr(c_for_stmt.step.value),
                block_to_expr(c_for_stmt.body),
            },
        }),
    }
}

func block_to_expr(block_expr block) ir_ast.expr_ir {
    ir_ast.expr_ir::block(convert_block(block))
}

func array_to_expr(array_literal lit) ir_ast.expr_ir {
    var items = vec[ir_ast.expr_ir]()
    var i = 0
    while i < lit.items.len() {
        items.push(convert_expr(lit.items[i]))
        i = i + 1
    }

    ir_ast.expr_ir::array(ir_ast.array_expr {
        type_name: lit.type_text,
        items: items,
    })
}

func map_to_expr(map_literal lit) ir_ast.expr_ir {
    var entries = vec[ir_ast.map_entry_expr]()
    var i = 0
    while i < lit.entries.len() {
        var entry = lit.entries[i]
        entries.push(ir_ast.map_entry_expr {
            key: convert_expr(entry.key),
            value: convert_expr(entry.value),
        })
        i = i + 1
    }

    ir_ast.expr_ir::map(ir_ast.map_expr {
        type_name: lit.type_text,
        entries: entries,
    })
}

func lower_function_to_mir(function_decl fd) mir_graph {
    if fd.body.is_none() {
        var empty_blocks = vec[mir_basic_block]()
        empty_blocks.push(make_block(0, "entry", vec[string](), "return", vec[mir_control_edge]()))
        return mir_graph {
            function_name: fd.sig.name,
            blocks: empty_blocks,
            locals: vec[mir_local_slot](),
            trace: vec[string](),
            entry: 0,
            exit: 0,
        }
    }

    return lower_block_to_mir(fd.sig.name, fd.body.unwrap())
}

func lower_block_to_mir(string function_name, block_expr block) mir_graph {
    var trace = vec[string]()
    var stmt_texts = vec[string]()

    var i = 0
    while i < block.statements.len() {
        var text = dump_expr_stmt(block.statements[i])
        stmt_texts.push(text)
        trace.push("stmt " + text)
        i = i + 1
    }

    var blocks = vec[mir_basic_block]()

    if block.final_expr.is_some() {
        var tail = block.final_expr.unwrap()
        switch tail {
            expr.if(if_expr) : {
                var entry_edges = vec[mir_control_edge]()
                entry_edges.push(make_edge("then", 1))
                entry_edges.push(make_edge("else", 2))
                blocks.push(make_block(0, "entry", stmt_texts, "branch", entry_edges))

                var then_lines = vec[string]()
                then_lines.push("if.then")
                blocks.push(make_block(1, "if.then", then_lines, "jump", vec1_edge("merge", 3)))

                var else_lines = vec[string]()
                else_lines.push("if.else")
                blocks.push(make_block(2, "if.else", else_lines, "jump", vec1_edge("merge", 3)))

                var merge_lines = vec[string]()
                merge_lines.push("yield " + dump_expr(tail))
                blocks.push(make_block(3, "if.merge", merge_lines, "return", vec[mir_control_edge]()))

                trace.push("control if -> blocks(entry, if.then, if.else, if.merge)")
                return make_graph(function_name, blocks, trace, 0, 3)
            }
            expr.while(while_expr) : {
                blocks.push(make_block(0, "entry", stmt_texts, "jump", vec1_edge("cond", 1)))

                var cond_lines = vec[string]()
                cond_lines.push("while.cond " + dump_expr(while_expr.condition.value))
                var cond_edges = vec[mir_control_edge]()
                cond_edges.push(make_edge("true", 2))
                cond_edges.push(make_edge("false", 3))
                blocks.push(make_block(1, "while.cond", cond_lines, "branch", cond_edges))

                var body_lines = vec[string]()
                body_lines.push("while.body")
                blocks.push(make_block(2, "while.body", body_lines, "jump", vec1_edge("cond", 1)))

                var exit_lines = vec[string]()
                exit_lines.push("yield unit")
                blocks.push(make_block(3, "while.exit", exit_lines, "return", vec[mir_control_edge]()))

                trace.push("control while -> blocks(entry, while.cond, while.body, while.exit)")
                return make_graph(function_name, blocks, trace, 0, 3)
            }
            expr.switch(switch_expr) : {
                var dispatch_edges = vec[mir_control_edge]()
                dispatch_edges.push(make_edge("case0", 1))
                dispatch_edges.push(make_edge("case1", 2))
                dispatch_edges.push(make_edge("default", 3))
                blocks.push(make_block(0, "entry", stmt_texts, "branch", dispatch_edges))

                blocks.push(make_block(1, "switch.case0", vec1("switch.case0"), "jump", vec1_edge("merge", 4)))
                blocks.push(make_block(2, "switch.case1", vec1("switch.case1"), "jump", vec1_edge("merge", 4)))
                blocks.push(make_block(3, "switch.default", vec1("switch.default"), "jump", vec1_edge("merge", 4)))
                blocks.push(make_block(4, "switch.merge", vec1("yield " + dump_expr(tail)), "return", vec[mir_control_edge]()))

                trace.push("control switch -> blocks(entry, switch.case0, switch.case1, switch.default, switch.merge)")
                return make_graph(function_name, blocks, trace, 0, 4)
            }
            expr.for(for_expr) : {
                blocks.push(make_block(0, "entry", stmt_texts, "jump", vec1_edge("for.cond", 1)))
                var cond_edges = vec[mir_control_edge]()
                cond_edges.push(make_edge("next", 2))
                cond_edges.push(make_edge("exit", 3))
                blocks.push(make_block(1, "for.cond", vec1("for.cond"), "branch", cond_edges))
                blocks.push(make_block(2, "for.body", vec1("for.body"), "jump", vec1_edge("for.cond", 1)))
                blocks.push(make_block(3, "for.exit", vec1("yield unit"), "return", vec[mir_control_edge]()))

                trace.push("control for -> blocks(entry, for.cond, for.body, for.exit)")
                return make_graph(function_name, blocks, trace, 0, 3)
            }
            _ : (),
        }
    }

    var final_lines = clone_lines(stmt_texts)
    if block.final_expr.is_some() {
        final_lines.push("yield " + dump_expr(block.final_expr.unwrap()))
    } else {
        final_lines.push("yield unit")
    }
    blocks.push(make_block(0, "entry", final_lines, "return", vec[mir_control_edge]()))
    make_graph(function_name, blocks, trace, 0, 0)
}

func dump_expr_stmt(stmt s) string {
    switch s {
        stmt.var(var_stmt) : "var " + var_stmt.name,
        stmt.assign(assign_stmt) : "assign " + assign_stmt.name,
        stmt.increment(increment_stmt) : "increment " + increment_stmt.name,
        stmt.return(return_stmt) : "return",
        stmt.expr(expr_stmt) : "expr " + dump_expr(expr_stmt.expr),
        stmt.defer(defer_stmt) : "defer " + dump_expr(defer_stmt.expr),
        stmt.c_for(c_for_stmt) : "c_for",
    }
}

func vec1(string text) vec[string] {
    var out = vec[string]()
    out.push(text)
    out
}

func clone_lines(vec[string] lines) vec[string] {
    var out = vec[string]()
    var i = 0
    while i < lines.len() {
        out.push(lines[i])
        i = i + 1
    }
    out
}

func make_edge(string label, int32 target) mir_control_edge {
    mir_control_edge {
        label: label,
        target: target,
        args: vec[mir_operand](),
    }
}

func vec1_edge(string label, int32 target) vec[mir_control_edge] {
    var edges = vec[mir_control_edge]()
    edges.push(make_edge(label, target))
    edges
}

func make_block(int32 id, string label, vec[string] lines, string term_kind, vec[mir_control_edge] edges) mir_basic_block {
    var statements = vec[mir_statement]()
    var i = 0
    while i < lines.len() {
        var args = vec[string]()
        args.push(lines[i])
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

func make_graph(string function_name, vec[mir_basic_block] blocks, vec[string] trace, int32 entry, int32 exit) mir_graph {
    mir_graph {
        function_name: function_name,
        blocks: blocks,
        locals: vec[mir_local_slot](),
        trace: trace,
        entry: entry,
        exit: exit,
    }
}
