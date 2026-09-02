package compile.internal.ir.mir
use std.slices
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
    string[] args
}

struct MirEvalStmt {
    string op
    string[] args
}
enum MirStatement {
    assign(MirAssignStmt),
    eval(MirEvalStmt),
}

struct MirTerminator {
    string kind,
    int[] targets
}

struct MirBasicBlock {
    int id
    string label
    MirStatement[] statements
    MirTerminator terminator
}

struct MirFunction {
    string name
    MirLocalSlot[] locals
    MirBasicBlock[] blocks
    int entry
    int exit
}

func new_empty_function(string name) MirFunction {
    MirFunction { name: name, locals MirLocalSlot[](), blocks MirBasicBlock[](), entry 0, exit 0 }
}
