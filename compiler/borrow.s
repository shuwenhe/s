package compiler

use std.vec.Vec
use frontend.BinaryExpr
use frontend.BlockExpr
use frontend.BorrowExpr
use frontend.CallExpr
use frontend.Expr
use frontend.IndexExpr
use frontend.MatchExpr
use frontend.MemberExpr
use frontend.NameExpr

pub struct BorrowDiagnostic {
    message: String,
}

pub struct BorrowState {
    name: String,
    ty: Type,
    moved: bool,
}

pub fn analyze_block(block: BlockExpr, initial: Vec[VarState]) -> Vec[BorrowDiagnostic] {
    let diagnostics = Vec[BorrowDiagnostic]()
    let scope = Vec[BorrowState]()
    for entry in initial {
        scope.push(BorrowState {
            name: entry.name,
            ty: entry.ty,
            moved: false,
        })
    }
    for stmt in block.statements {
        match stmt {
            frontend.Stmt::Let(value) => inspect_expr(value.value, scope, diagnostics),
            frontend.Stmt::Return(value) => {
                match value.value {
                    Option::Some(expr) => inspect_expr(expr, scope, diagnostics),
                    Option::None => (),
                }
            }
            frontend.Stmt::Expr(value) => inspect_expr(value.expr, scope, diagnostics),
        }
    }
    match block.final_expr {
        Option::Some(expr) => inspect_expr(expr, scope, diagnostics),
        Option::None => (),
    }
    diagnostics
}

pub fn inspect_expr(expr: Expr, scope: Vec[BorrowState], diagnostics: Vec[BorrowDiagnostic]) -> () {
    match expr {
        Expr::Name(value) => consume_name(scope, diagnostics, value.name),
        Expr::Borrow(value) => {
            match value.target.value {
                Expr::Name(name_expr) => inspect_name(scope, diagnostics, name_expr.name),
                other => inspect_expr(other, scope, diagnostics),
            }
        }
        Expr::Binary(value) => {
            inspect_expr(value.left.value, scope, diagnostics)
            inspect_expr(value.right.value, scope, diagnostics)
        }
        Expr::Call(value) => {
            inspect_expr(value.callee.value, scope, diagnostics)
            for arg in value.args {
                inspect_expr(arg, scope, diagnostics)
            }
        }
        Expr::Member(value) => inspect_expr(value.target.value, scope, diagnostics),
        Expr::Index(value) => {
            inspect_expr(value.target.value, scope, diagnostics)
            inspect_expr(value.index.value, scope, diagnostics)
        }
        Expr::Match(value) => {
            inspect_expr(value.subject.value, scope, diagnostics)
            for arm in value.arms {
                inspect_expr(arm.expr, scope, diagnostics)
            }
        }
        Expr::If(value) => {
            inspect_expr(value.condition.value, scope, diagnostics)
            analyze_block(value.then_branch, to_var_state(scope))
            match value.else_branch {
                Option::Some(other) => inspect_expr(other.value, scope, diagnostics),
                Option::None => (),
            }
        }
        Expr::While(value) => {
            inspect_expr(value.condition.value, scope, diagnostics)
            analyze_block(value.body, to_var_state(scope))
        }
        Expr::For(value) => {
            inspect_expr(value.iterable.value, scope, diagnostics)
            analyze_block(value.body, to_var_state(scope))
        }
        Expr::Block(value) => {
            analyze_block(value, to_var_state(scope))
        }
        _ => (),
    }
}

pub fn consume_name(scope: Vec[BorrowState], diagnostics: Vec[BorrowDiagnostic], name: String) -> () {
    let index = 0
    while index < scope.len() {
        if scope[index].name == name {
            if scope[index].moved {
                diagnostics.push(BorrowDiagnostic {
                    message: "use of moved value " + name,
                })
                return
            }
            if !is_copy_type(scope[index].ty) {
                scope[index].moved = true
            }
            return
        }
        index = index + 1
    }
}

pub fn inspect_name(scope: Vec[BorrowState], diagnostics: Vec[BorrowDiagnostic], name: String) -> () {
    for entry in scope {
        if entry.name == name && entry.moved {
            diagnostics.push(BorrowDiagnostic {
                message: "borrow of moved value " + name,
            })
            return
        }
    }
}

pub fn to_var_state(scope: Vec[BorrowState]) -> Vec[VarState] {
    let out = Vec[VarState]()
    for entry in scope {
        out.push(VarState {
            name: entry.name,
            ty: entry.ty,
        })
    }
    out
}
