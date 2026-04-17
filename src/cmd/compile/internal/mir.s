package compile.internal.mir

use compile.internal.borrow.AnalyzeFunction as AnalyzeBorrowFunction
use s.BlockExpr
use s.FunctionDecl
use s.dump_expr
use s.dump_stmt
use std.option.Option
use std.vec.Vec

struct MirOperand {
    String kind,
    String value,
    String type_name,
}

struct MirLocalSlot {
    int32 id,
    String name,
    String kind,
    int32 version,
    String type_name,
    bool copyable,
}

struct MirAssignStmt {
    int32 target,
    String op,
    Vec[String] args,
}

struct MirEvalStmt {
    String op,
    Vec[String] args,
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
    String label,
    int32 target,
    Vec[MirOperand] args,
}

struct MirTerminator {
    String kind,
    Vec[MirControlEdge] edges,
}

struct MirBasicBlock {
    int32 id,
    String label,
    Vec[MirStatement] statements,
    MirTerminator terminator,
}

struct MIRGraph {
    Vec[String] blocks,
    Vec[String] locals,
    Vec[String] trace,
    int32 entry,
    int32 exit,
}

func LowerFunction(FunctionDecl function) -> String {
    if function.body.is_some() {
        var body = function.body.unwrap()
        return AnalyzeBorrowFunction(function.sig.name, Vec[String](), LowerBlock(body))
    }
    return AnalyzeBorrowFunction(function.sig.name, Vec[String](), "")
}

func LowerBlock(BlockExpr block) -> String {
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

func TraceBranch(String condition_text, String then_text, String else_text) -> String {
    if else_text == "" {
        return "branch " + condition_text + " | " + indent(1) + "then " + then_text + " | " + indent(1) + "else <missing>"
    }
    return "branch " + condition_text + " | " + indent(1) + "then " + then_text + " | " + indent(1) + "else " + else_text
}

func TraceLoop(String loop_kind, String condition_text, String body_text) -> String {
    return loop_kind + " " + condition_text + " | " + indent(1) + "body " + body_text
}

func TraceMatch(String subject_text, String arms_text) -> String {
    if arms_text == "" {
        return "match " + subject_text
    }
    return "match " + subject_text + " | " + arms_text
}

func indent(i32 depth) -> String {
    var out = ""
    var i = 0
    while i < depth {
        out = out + "  "
        i = i + 1
    }
    return out
}

func join_text(Vec[String] values, String sep) -> String {
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
