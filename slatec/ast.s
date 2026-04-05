package slatec.ast

use std.option.Option
use std.vec.Vec

struct StringLiteral {
    String value,
}

struct PrintlnStmt {
    StringLiteral value,
}

enum Stmt {
    Println(PrintlnStmt),
}

struct FunctionDecl {
    String name,
    Vec[Stmt] body,
}

struct SourceFile {
    String package_name,
    Vec[FunctionDecl] functions,
}

