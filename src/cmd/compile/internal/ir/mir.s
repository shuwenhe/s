package compile.internal.ir.mir

use std.vec.vec

struct MirOperand {
    string kind,
    string value
    option[string] type_name
}

struct MirLocalSlot {
    int id
    string name
    option[string] type_name
}

struct MirAssignStmt {
    int target
    string op
    vec[string] args
}

struct MirEvalStmt {
    string op
    vec[string] args
}

enum MirStatement {
    assign(MirAssignStmt),
    eval(MirEvalStmt),
}

struct MirTerminator {
    string kind,
    vec[int] targets
}

struct MirBasicBlock {
    int id
    string label
    vec[MirStatement] statements
    MirTerminator terminator
}

struct MirFunction {
    string name
    vec[MirLocalSlot] locals
    vec[MirBasicBlock] blocks
    int entry
    int exit
}

func new_empty_function(string name) MirFunction {
    MirFunction { name: name, locals: vec[MirLocalSlot](), blocks: vec[MirBasicBlock](), entry: 0, exit: 0 }
}
