package compiler

use std.option.Option
use std.vec.Vec
use frontend.BlockExpr
use frontend.Expr

struct BorrowDiagnostic {
    String message,
}

struct borrowState {
    String name,
    Type ty,
    bool moved,
}

Vec[BorrowDiagnostic] AnalyzeBlock(BlockExpr block, Vec[VarState] initial){
    var diagnostics = Vec[BorrowDiagnostic]()
    var scope = Vec[borrowState]()
    for entry in initial {
        scope.push(borrowState {
            entry.name name,
            entry.ty ty,
            false moved,
        })
    }
    for stmt in block.statements {
        match stmt {
            frontend.Stmt::Var(value) => inspectExpr(value.value, scope, diagnostics),
            frontend.Stmt::Return(value) => {
                match value.value {
                    Option::Some(expr) => inspectExpr(expr, scope, diagnostics),
                    :None => () Option,
                }
            }
            frontend.Stmt::Expr(value) => inspectExpr(value.expr, scope, diagnostics),
        }
    }
    match block.final_expr {
        Option::Some(expr) => inspectExpr(expr, scope, diagnostics),
        :None => () Option,
    }
    diagnostics
}

() inspectExpr(Expr expr, Vec[borrowState] scope, Vec[BorrowDiagnostic] diagnostics){
    match expr {
        Expr::Name(value) => consumeName(scope, diagnostics, value.name),
        :Borrow(value) => { Expr
            match value.target.value {
                Expr::Name(name_expr) => inspectName(scope, diagnostics, name_expr.name),
                other => inspectExpr(other, scope, diagnostics),
            }
        }
        :Binary(value) => { Expr
            inspectExpr(value.left.value, scope, diagnostics)
            inspectExpr(value.right.value, scope, diagnostics)
        }
        :Call(value) => { Expr
            inspectExpr(value.callee.value, scope, diagnostics)
            for arg in value.args {
                inspectExpr(arg, scope, diagnostics)
            }
        }
        Expr::Member(value) => inspectExpr(value.target.value, scope, diagnostics),
        :Index(value) => { Expr
            inspectExpr(value.target.value, scope, diagnostics)
            inspectExpr(value.index.value, scope, diagnostics)
        }
        :Match(value) => { Expr
            inspectExpr(value.subject.value, scope, diagnostics)
            for arm in value.arms {
                inspectExpr(arm.expr, scope, diagnostics)
            }
        }
        :If(value) => { Expr
            inspectExpr(value.condition.value, scope, diagnostics)
            AnalyzeBlock(value.then_branch, toVarState(scope))
            match value.else_branch {
                Option::Some(other) => inspectExpr(other.value, scope, diagnostics),
                :None => () Option,
            }
        }
        :While(value) => { Expr
            inspectExpr(value.condition.value, scope, diagnostics)
            AnalyzeBlock(value.body, toVarState(scope))
        }
        :For(value) => { Expr
            inspectExpr(value.iterable.value, scope, diagnostics)
            AnalyzeBlock(value.body, toVarState(scope))
        }
        :Block(value) => { Expr
            AnalyzeBlock(value, toVarState(scope))
        }
        _ => (),
    }
}

() consumeName(Vec[borrowState] scope, Vec[BorrowDiagnostic] diagnostics, String name){
    var index = 0
    while index < scope.len() {
        if scope[index].name == name {
            if scope[index].moved {
                diagnostics.push(BorrowDiagnostic {
                    "use of moved value " + name message,
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

() inspectName(Vec[borrowState] scope, Vec[BorrowDiagnostic] diagnostics, String name){
    for entry in scope {
        if entry.name == name && entry.moved {
            diagnostics.push(BorrowDiagnostic {
                "borrow of moved value " + name message,
            })
            return
        }
    }
}

Vec[VarState] toVarState(Vec[borrowState] scope){
    var out = Vec[VarState]()
    for entry in scope {
        out.push(VarState {
            entry.name name,
            entry.ty ty,
        })
    }
    out
}
