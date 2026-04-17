package compile.internal.mir

use compile.internal.borrow.AnalyzeFunction as AnalyzeBorrowFunction
use s.BlockExpr
use s.FunctionDecl
use s.dump_expr
use s.dump_stmt
use std.option.Option
use std.vec.Vec

struct MirOperand {
    string kind,
    string value,
    string type_name,
}

struct MirLocalSlot {
    int32 id,
    string name,
    string kind,
    int32 version,
    string type_name,
    bool copyable,
}

struct MirAssignStmt {
    int32 target,
    string op,
    Vec[string] args,
}

struct MirEvalStmt {
    string op,
    Vec[string] args,
}

struct MirMoveStmt {
    int32 target,
    MirOperand source,
}

struct MirCopyStmt {
    int32 target,
    MirOperand source,
}

struct MirDropStmt {
    int32 slot,
}

enum MirStatement {
    Assign(MirAssignStmt),
    Eval(MirEvalStmt),
    Move(MirMoveStmt),
    Copy(MirCopyStmt),
    Drop(MirDropStmt),
}

struct MirControlEdge {
    string label,
    int32 target,
    Vec[MirOperand] args,
}

struct MirTerminator {
    string kind,
    Vec[MirControlEdge] edges,
}

struct MirBasicBlock {
    int32 id,
    string label,
    Vec[MirStatement] statements,
    MirTerminator terminator,
}

struct MIRGraph {
    Vec[string] blocks,
    Vec[string] locals,
    Vec[string] trace,
    int32 entry,
    int32 exit,
}

func LowerFunction(FunctionDecl function) string {
    if function.body.is_some() {
        var body = function.body.unwrap()
        return AnalyzeBorrowFunction(function.sig.name, Vec[string](), LowerBlock(body))
    }
    return AnalyzeBorrowFunction(function.sig.name, Vec[string](), "")
}

func LowerBlock(BlockExpr block) string {
    var text = "block"

    var index = 0
    while index < block.statements.len() {
        var stmt_text = join_text(dump_stmt(block.statements[index], indent(1)), " | ")
        text = text + " | " + indent(1) + stmt_text
        index = index + 1
    }

    if block.final_expr.is_some() {
        var tail = block.final_expr.unwrap()
        return text + " | " + indent(1) + "yield " + dump_expr(tail)
    } else {
        return text + " | " + indent(1) + "yield unit"
    }
}

func TraceBranch(string condition_text, string then_text, string else_text) string {
    if else_text == "" {
        return "branch " + condition_text + " | " + indent(1) + "then " + then_text + " | " + indent(1) + "else <missing>"
    }
    return "branch " + condition_text + " | " + indent(1) + "then " + then_text + " | " + indent(1) + "else " + else_text
}

func TraceLoop(string loop_kind, string condition_text, string body_text) string {
    return loop_kind + " " + condition_text + " | " + indent(1) + "body " + body_text
}

func TraceSwitch(string subject_text, string arms_text) string {
    if arms_text == "" {
        return "switch " + subject_text
    }
    return "switch " + subject_text + " | " + arms_text
}

func indent(int32 depth) string {
    var out = ""
    var i = 0
    while i < depth {
        out = out + "  "
        i = i + 1
    }
    return out
}

func join_text(Vec[string] values, string sep) string {
    var out = ""
    var i = 0
    while i < values.len() {
        if i > 0 {
            out = out + sep
        }
        out = out + values[i]
        i = i + 1
    }
    return out
}
