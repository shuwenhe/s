package compiler.internal.typecheck

use std.option.Option
use std.vec.Vec
use s.BlockExpr
use s.Expr

struct BorrowDiagnostic {
    String message,
}

struct borrowState {
    String name,
    Type ty,
    bool moved,
    bool captured_by_defer,
}

func AnalyzeBlock(BlockExpr block, Vec[VarState] initial) Vec[BorrowDiagnostic] {
    var diagnostics = Vec[BorrowDiagnostic]()
    var scope = Vec[borrowState]()
    for entry in initial {
        scope.push(borrowState {
            name: entry.name,
            ty: entry.ty,
            moved: false,
            captured_by_defer: false,
        })
    }
    for stmt in block.statements {
        match stmt {
            s.Stmt::Var(value) => {
                inspectExpr(value.value, scope, diagnostics)
                // bind new variable in borrow scope
                scope.push(borrowState {
                    name: value.name,
                    ty: value.type_name.is_some() ? ParseType(value.type_name.unwrap()) : UnknownTypeOf("var"),
                    moved: false,
                    captured_by_defer: false,
                })
            }
            s.Stmt::Assign(value) => {
                inspectExpr(value.value, scope, diagnostics)
                // assignment reinitializes target (not a move)
                for i in 0..scope.len() {
                    if scope[i].name == value.name {
                        scope[i].moved = false
                    }
                }
            }
            s.Stmt::Defer(value) => {
                // collect names used by defer and mark captured
                var names = collectNames(value.expr)
                for n in names {
                    var idx = 0
                    while idx < scope.len() {
                        if scope[idx].name == n {
                            scope[idx].captured_by_defer = true
                        }
                        idx = idx + 1
                    }
                }
                // also inspect expression for immediate issues
                inspectExpr(value.expr, scope, diagnostics)
            }
            s.Stmt::Return(value) => {
                match value.value {
                    Option::Some(expr) => inspectExpr(expr, scope, diagnostics),
                    Option::None => (),
                }
            }
            s.Stmt::Expr(value) => inspectExpr(value.expr, scope, diagnostics),
            _ => (),
        }
    }
    match block.final_expr {
        Option::Some(expr) => inspectExpr(expr, scope, diagnostics),
        Option::None => (),
    }
    diagnostics
}

func inspectExpr(Expr expr, Vec[borrowState] scope, Vec[BorrowDiagnostic] diagnostics) () {
    match expr {
        Expr::Name(value) => consumeName(scope, diagnostics, value.name),
        Expr::Borrow(value) => {
            match value.target.value {
                Expr::Name(name_expr) => inspectName(scope, diagnostics, name_expr.name),
                other => inspectExpr(other, scope, diagnostics),
            }
        }
        Expr::Binary(value) => {
            inspectExpr(value.left.value, scope, diagnostics)
            inspectExpr(value.right.value, scope, diagnostics)
        }
        Expr::Call(value) => {
            inspectExpr(value.callee.value, scope, diagnostics)
            for arg in value.args {
                inspectExpr(arg, scope, diagnostics)
            }
        }
        Expr::Member(value) => inspectExpr(value.target.value, scope, diagnostics),
        Expr::Index(value) => {
            inspectExpr(value.target.value, scope, diagnostics)
            inspectExpr(value.index.value, scope, diagnostics)
        }
        Expr::Match(value) => {
            inspectExpr(value.subject.value, scope, diagnostics)
            for arm in value.arms {
                inspectExpr(arm.expr, scope, diagnostics)
            }
        }
        Expr::If(value) => {
            inspectExpr(value.condition.value, scope, diagnostics)
            AnalyzeBlock(value.then_branch, toVarState(scope))
            match value.else_branch {
                Option::Some(other) => inspectExpr(other.value, scope, diagnostics),
                Option::None => (),
            }
        }
        Expr::While(value) => {
            inspectExpr(value.condition.value, scope, diagnostics)
            AnalyzeBlock(value.body, toVarState(scope))
        }
        Expr::For(value) => {
            inspectExpr(value.iterable.value, scope, diagnostics)
            AnalyzeBlock(value.body, toVarState(scope))
        }
        Expr::Block(value) => {
            AnalyzeBlock(value, toVarState(scope))
        }
        _ => (),
    }
}

func consumeName(Vec[borrowState] scope, Vec[BorrowDiagnostic] diagnostics, String name) () {
    var index = 0
    while index < scope.len() {
        if scope[index].name == name {
            if scope[index].moved {
                diagnostics.push(BorrowDiagnostic {
                    message: "use of moved value " + name,
                })
                return
            }
            if !IsCopyType(scope[index].ty) {
                // moving a value: if it was captured by a defer, that's an error
                if scope[index].captured_by_defer {
                    diagnostics.push(BorrowDiagnostic {
                        message: "value " + name + " moved but captured by defer",
                    })
                }
                scope[index].moved = true
            }
            return
        }
        index = index + 1
    }
}

func inspectName(Vec[borrowState] scope, Vec[BorrowDiagnostic] diagnostics, String name) () {
    for entry in scope {
        if entry.name == name && entry.moved {
            diagnostics.push(BorrowDiagnostic {
                message: "borrow of moved value " + name,
            })
            return
        }
    }
}

func toVarState(Vec[borrowState] scope) Vec[VarState] {
    var out = Vec[VarState]()
    for entry in scope {
        out.push(VarState {
            name: entry.name,
            ty: entry.ty,
        })
    }
    out
}

func collectNames(Expr expr) Vec[String] {
    var out = Vec[String]()
    match expr {
        Expr::Name(value) => out.push(value.name),
        Expr::Borrow(value) => {
            match value.target.value {
                Expr::Name(name_expr) => out.push(name_expr.name),
                other => out = out + collectNames(other),
            }
        }
        Expr::Binary(value) => {
            out = out + collectNames(value.left.value)
            out = out + collectNames(value.right.value)
        }
        Expr::Call(value) => {
            out = out + collectNames(value.callee.value)
            for arg in value.args {
                out = out + collectNames(arg)
            }
        }
        Expr::Member(value) => out = out + collectNames(value.target.value),
        Expr::Index(value) => {
            out = out + collectNames(value.target.value)
            out = out + collectNames(value.index.value)
        }
        Expr::Match(value) => {
            out = out + collectNames(value.subject.value)
            for arm in value.arms {
                out = out + collectNames(arm.expr)
            }
        }
        Expr::If(value) => {
            out = out + collectNames(value.condition.value)
            out = out + collectNames(Expr::Block(value.then_branch))
            match value.else_branch {
                Option::Some(other) => out = out + collectNames(other.value),
                Option::None => (),
            }
        }
        Expr::While(value) => {
            out = out + collectNames(value.condition.value)
            out = out + collectNames(Expr::Block(value.body))
        }
        Expr::For(value) => {
            out = out + collectNames(value.iterable.value)
            out = out + collectNames(Expr::Block(value.body))
        }
        Expr::Block(value) => {
            for stmt in value.statements {
                match stmt {
                    Stmt::Var(v) => out = out + collectNames(v.value),
                    Stmt::Assign(a) => out = out + collectNames(a.value),
                    Stmt::Expr(e) => out = out + collectNames(e.expr),
                    Stmt::Return(r) => match r.value { Option::Some(expr) => out = out + collectNames(expr), Option::None => () },
                    _ => (),
                }
            }
            match value.final_expr { Option::Some(expr) => out = out + collectNames(expr), Option::None => () }
        }
        _ => (),
    }
    out
}
