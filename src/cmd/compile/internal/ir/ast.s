package compile.internal.ir.ast

use std.vec.vec
use compile.internal.ir.types

// Typed AST core node definitions (草案)

struct Program {
    string package_name
    vec[Package] packages
}

struct Package {
    string name
    vec[Decl] decls
}

enum Decl {
    func(FuncDecl),
    r#type(TypeDecl),
    var(VarDecl),
    const(ConstDecl),
    impl(ImplDecl),
}

struct FuncDecl {
    string name
    FuncSig sig
    option[Block] body
}

struct FuncSig {
    vec[Param] params
    option[string] return_type_name
    vec[string] generics
}

struct Param { string name, string type_name }

struct TypeDecl { string name, string type_expr }

struct VarDecl { string name, string type_name, option[string] init }

struct ConstDecl { string name, string value }

struct ImplDecl { string type_name, vec[FuncDecl] methods }

struct Block { vec[Stmt] statements, option[Expr] final_expr }

enum Stmt {
    var(VarStmt),
    assign(AssignStmt),
    increment(IncrementStmt),
    expr(ExprStmt),
    r#return(ReturnStmt),
}

struct VarStmt { string name, option[string] type_name, Expr value }
struct AssignStmt { string name, Expr value }
struct IncrementStmt { string name }
struct ExprStmt { Expr expr }
struct ReturnStmt { option[Expr] value }

// Minimal expression enum; each Expr should carry a resolved `types.Type` at semantic phase.
enum Expr {
    int(int32),
    string(string),
    bool(bool),
    name(string),
    binary(BinaryExpr),
    call(CallExpr),
    borrow(BorrowExpr),
}

struct BinaryExpr { string op, Expr left, Expr right }
struct CallExpr { string callee, vec[Expr] args }
struct BorrowExpr { Expr target, bool mutable }

// Helpers
func make_empty_package(string name) Package {
    Package { name: name, decls: vec[Decl]() }
}
