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
}

func AnalyzeBlock(BlockExpr block, Vec[VarState] initial) -> Vec[BorrowDiagnostic] {
    var diagnostics = Vec[BorrowDiagnostic]()
    var scope = Vec[borrowState]()
    for entry in initial {
        scope.push(borrowState {
            name: entry.name,
            ty: entry.ty,
            moved: false,
        })
    }
    for stmt in block.statements {
        match stmt {
            s.Stmt::Var(value) => inspectExpr(value.value, scope, diagnostics),
            s.Stmt::Return(value) => {
                match value.value {
                    Option::Some(expr) => inspectExpr(expr, scope, diagnostics),
                    Option::None => (),
                }
            }
            s.Stmt::Expr(value) => inspectExpr(value.expr, scope, diagnostics),
        }
    }
    match block.final_expr {
        Option::Some(expr) => inspectExpr(expr, scope, diagnostics),
        Option::None => (),
    }
    diagnostics
}

func inspectExpr(Expr expr, Vec[borrowState] scope, Vec[BorrowDiagnostic] diagnostics) -> () {
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

func consumeName(Vec[borrowState] scope, Vec[BorrowDiagnostic] diagnostics, String name) -> () {
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
                scope[index].moved = true
            }
            return
        }
        index = index + 1
    }
}

func inspectName(Vec[borrowState] scope, Vec[BorrowDiagnostic] diagnostics, String name) -> () {
    for entry in scope {
        if entry.name == name && entry.moved {
            diagnostics.push(BorrowDiagnostic {
                message: "borrow of moved value " + name,
            })
            return
        }
    }
}

func toVarState(Vec[borrowState] scope) -> Vec[VarState] {
    var out = Vec[VarState]()
    for entry in scope {
        out.push(VarState {
            name: entry.name,
            ty: entry.ty,
        })
    }
    out
}
