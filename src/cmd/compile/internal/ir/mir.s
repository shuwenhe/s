package compile.internal.ir.mir
use std.slices
struct mir_operand {
    string kind,
    string value
    option[string] type_name
}

struct mir_local_slot {
    int id
    string name
    option[string] type_name
}

struct mir_assign_stmt {
    int target
    string op
    string[] args
}

struct mir_eval_stmt {
    string op
    string[] args
}
enum mir_statement {
    assign(mir_assign_stmt),
    eval(mir_eval_stmt),
}

struct mir_terminator {
    string kind,
    int[] targets
}

struct mir_basic_block {
    int id
    string label
    mir_statement[] statements
    mir_terminator terminator
}

struct mir_function {
    string name
    mir_local_slot[] locals
    mir_basic_block[] blocks
    int entry
    int exit
}

func new_empty_function(string name) mir_function {
    mir_function { name: name, locals mir_local_slot[](), blocks mir_basic_block[](), entry 0, exit 0 }
}
