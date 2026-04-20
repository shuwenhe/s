package compile.internal.ir.lower

use s.source_file
use s.expr
use s.stmt
use s.block_expr
use s.function_decl
use compile.internal.ir.ast as ir_ast
use compile.internal.backend_elf64.parse_int_literal as parse_int_literal
use std.vec.vec

// 从 syntax.source_file 降级到 ir.ast.Package 的基本实现（草案）

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
            // c_for lowering not implemented yet - emit an expr placeholder
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
            // only handle simple callee names for now
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
        expr.if(if_expr) : ir_ast.Expr::name("<if-expr-unlowered>"),
        expr.block(block_expr) : ir_ast.Expr::name("<block-expr-unlowered>"),
        expr.switch(switch_expr) : ir_ast.Expr::name("<switch-expr-unlowered>"),
        expr.while(while_expr) : ir_ast.Expr::name("<while-expr-unlowered>"),
        expr.for(for_expr) : ir_ast.Expr::name("<for-expr-unlowered>"),
        expr.member(member_expr) : ir_ast.Expr::name("<member-expr-unlowered>"),
        expr.index(index_expr) : ir_ast.Expr::name("<index-expr-unlowered>"),
        expr.array(array_literal) : ir_ast.Expr::name("<array-expr-unlowered>"),
        expr.map(map_literal) : ir_ast.Expr::name("<map-expr-unlowered>"),
    }
}
