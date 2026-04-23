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

func from_syntax(source_file src) ir_ast.Package {
    var pkg = ir_ast.Package { name: src.pkg, decls: vec[ir_ast.Decl]() }

    var i = 0
    while i < src.items.len() {
        var it = src.items[i]
        switch it {
            item.function(function_decl) : {
                var fd = convert_function(function_decl)
                pkg.decls.push(ir_ast.Decl::func(fd))
            }
            item.struct(struct_decl) : {
                pkg.decls.push(ir_ast.Decl::r#type(ir_ast.TypeDecl { name: struct_decl.name, type_expr: "struct" }))
            }
            item.enum(enum_decl) : {
                pkg.decls.push(ir_ast.Decl::r#type(ir_ast.TypeDecl { name: enum_decl.name, type_expr: "enum" }))
            }
            item.trait(trait_decl) : {
                pkg.decls.push(ir_ast.Decl::r#type(ir_ast.TypeDecl { name: trait_decl.name, type_expr: "trait" }))
            }
            item.impl(impl_decl) : {
                var methods = vec[ir_ast.FuncDecl]()
                var mi = 0
                while mi < impl_decl.methods.len() {
                    methods.push(convert_function(impl_decl.methods[mi]))
                    mi = mi + 1
                }
                pkg.decls.push(ir_ast.Decl::impl(ir_ast.ImplDecl { type_name: impl_decl.target, methods: methods }))
            }
        }
        i = i + 1
    }

    pkg
}

func convert_function(function_decl fd) ir_ast.FuncDecl {
    var sig = ir_ast.FuncSig { params: vec[ir_ast.Param](), return_type_name: option[string].none, generics: fd.sig.generics }
    var pi = 0
    while pi < fd.sig.params.len() {
        var p = fd.sig.params[pi]
        sig.params.push(ir_ast.Param { name: p.name, type_name: p.type_name })
        pi = pi + 1
    }
    var ret = option[string].none
    if fd.sig.return_type.is_some() {
        ret = option[string].some(fd.sig.return_type.unwrap())
    }
    sig.return_type_name = ret

    var body = option[ir_ast.Block].none
    if fd.body.is_some() {
        body = option[ir_ast.Block].some(convert_block(fd.body.unwrap()))
    }

    ir_ast.FuncDecl { name: fd.sig.name, sig: sig, body: body }
}

func convert_block(block_expr b) ir_ast.Block {
    var stmts = vec[ir_ast.Stmt]()
    var si = 0
    while si < b.statements.len() {
        stmts.push(convert_stmt(b.statements[si]))
        si = si + 1
    }

    var final = option[ir_ast.Expr].none
    if b.final_expr.is_some() {
        final = option[ir_ast.Expr].some(convert_expr(b.final_expr.unwrap()))
    }
    ir_ast.Block { statements: stmts, final_expr: final }
}

func convert_stmt(stmt s) ir_ast.Stmt {
    switch s {
        stmt.var(var_stmt) : {
            ir_ast.Stmt::var(ir_ast.VarStmt { name: var_stmt.name, type_name: var_stmt.type_name, value: convert_expr(var_stmt.value) })
        }
        stmt.assign(assign_stmt) : {
            ir_ast.Stmt::assign(ir_ast.AssignStmt { name: assign_stmt.name, value: convert_expr(assign_stmt.value) })
        }
        stmt.increment(increment_stmt) : {
            ir_ast.Stmt::increment(ir_ast.IncrementStmt { name: increment_stmt.name })
        }
        stmt.c_for(c_for_stmt) : {

            ir_ast.Stmt::expr(ir_ast.ExprStmt { expr: ir_ast.Expr::name("<c_for_unlowered>") })
        }
        stmt.return(return_stmt) : {
            if return_stmt.value.is_some() {
                ir_ast.Stmt::r#return(ir_ast.ReturnStmt { value: option[ir_ast.Expr].some(convert_expr(return_stmt.value.unwrap())) })
            } else {
                ir_ast.Stmt::r#return(ir_ast.ReturnStmt { value: option[ir_ast.Expr].none })
            }
        }
        stmt.expr(expr_stmt) : {
            ir_ast.Stmt::expr(ir_ast.ExprStmt { expr: convert_expr(expr_stmt.expr) })
        }
        stmt.defer(defer_stmt) : {
            ir_ast.Stmt::expr(ir_ast.ExprStmt { expr: convert_expr(defer_stmt.expr) })
        }
    }
}

func convert_expr(expr e) ir_ast.Expr {
    switch e {
        expr.int(int_expr) : {
            var n = parse_int_literal(int_expr.value)
            ir_ast.Expr::int(n)
        }
        expr.string(string_expr) : ir_ast.Expr::string(string_expr.value),
        expr.bool(bool_expr) : ir_ast.Expr::bool(bool_expr.value),
        expr.name(name_expr) : ir_ast.Expr::name(name_expr.name),
        expr.borrow(borrow_expr) : ir_ast.Expr::borrow(ir_ast.BorrowExpr { target: convert_expr(borrow_expr.target.unwrap()), mutable: borrow_expr.mutable }),
        expr.binary(binary_expr) : ir_ast.Expr::binary(ir_ast.BinaryExpr { op: binary_expr.op, left: convert_expr(binary_expr.left.unwrap()), right: convert_expr(binary_expr.right.unwrap()) }),
        expr.call(call_expr) : {

            var callee_name = "<call>"
            switch call_expr.callee.unwrap() {
                expr.name(name_expr) : callee_name = name_expr.name,
                _ : callee_name = "<expr-callee>",
            }
            var args = vec[ir_ast.Expr]()
            var ai = 0
            while ai < call_expr.args.len() {
                args.push(convert_expr(call_expr.args[ai]))
                ai = ai + 1
            }
            ir_ast.Expr::call(ir_ast.CallExpr { callee: callee_name, args: args })
        }
        expr.if(if_expr) : ir_ast.Expr::call(ir_ast.CallExpr { callee: "if_expr", args: vec[ir_ast.Expr]() }),
        expr.block(block_expr) : ir_ast.Expr::name("<block-expr-unlowered>"),
        expr.switch(switch_expr) : ir_ast.Expr::call(ir_ast.CallExpr { callee: "switch_expr", args: vec[ir_ast.Expr]() }),
        expr.while(while_expr) : ir_ast.Expr::call(ir_ast.CallExpr { callee: "while_expr", args: vec[ir_ast.Expr]() }),
        expr.for(for_expr) : ir_ast.Expr::call(ir_ast.CallExpr { callee: "for_expr", args: vec[ir_ast.Expr]() }),
        expr.member(member_expr) : ir_ast.Expr::name("<member-expr-unlowered>"),
        expr.index(index_expr) : ir_ast.Expr::name("<index-expr-unlowered>"),
        expr.array(array_literal) : ir_ast.Expr::name("<array-expr-unlowered>"),
        expr.map(map_literal) : ir_ast.Expr::name("<map-expr-unlowered>"),
    }
}

func lower_main_to_mir(source_file src) result[mir_graph, string] {
    var i = 0
    while i < src.items.len() {
        switch src.items[i] {
            item.function(function_decl) : {
                if function_decl.sig.name == "main" {
                    return result::ok(lower_function_to_mir(function_decl))
                }
            }
            _ : (),
        }
        i = i + 1
    }

    result::err("entry function main not found")
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
