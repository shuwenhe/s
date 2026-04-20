package compile.internal.ir.mir

use std.vec.vec

// MIR（中间表示）草案 - 控制流图和基础块定义

struct MirOperand {
    string kind, // "local", "const", "arg"
    string value,
    option[string] type_name,
}

struct MirLocalSlot {
    int32 id,
    string name,
    option[string] type_name,
}

struct MirAssignStmt {
    int32 target,
    string op,
    vec[string] args,
}

struct MirEvalStmt {
    string op,
    vec[string] args,
}

enum MirStatement {
    assign(MirAssignStmt),
    eval(MirEvalStmt),
}

struct MirTerminator {
    string kind, // "return", "branch", "jump"
    vec[int32] targets,
}

struct MirBasicBlock {
    int32 id,
    string label,
    vec[MirStatement] statements,
    MirTerminator terminator,
}

struct MirFunction {
    string name,
    vec[MirLocalSlot] locals,
    vec[MirBasicBlock] blocks,
    int32 entry,
    int32 exit,
}

func new_empty_function(string name) MirFunction {
    MirFunction { name: name, locals: vec[MirLocalSlot](), blocks: vec[MirBasicBlock](), entry: 0, exit: 0 }
}
