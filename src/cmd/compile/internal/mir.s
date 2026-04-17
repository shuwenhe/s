package compile.internal.mir

use compile.internal.borrow.AnalyzeFunction as AnalyzeBorrowFunction
use s.BlockExpr
use s.FunctionDecl
use s.dumpExpr
use s.dumpStmt
use std.option.Option
use std.vec.Vec

struct MirOperand {
    string kind,
    string value,
    string typeName,
}

struct MirLocalSlot {
    int32 id,
    string name,
    string kind,
    int32 version,
    string typeName,
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
    if function.body.isSome() {
        var body = function.body.unwrap()
        return AnalyzeBorrowFunction(function.sig.name, Vec[string](), LowerBlock(body))
    }
    return AnalyzeBorrowFunction(function.sig.name, Vec[string](), "")
}

func LowerBlock(BlockExpr block) string {
    var text = "block"

    var index = 0
    while index < block.statements.len() {
        var stmtText = joinText(dumpStmt(block.statements[index], indent(1)), " | ")
        text = text + " | " + indent(1) + stmtText
        index = index + 1
    }

    if block.finalExpr.isSome() {
        var tail = block.finalExpr.unwrap()
        return text + " | " + indent(1) + "yield " + dumpExpr(tail)
    } else {
        return text + " | " + indent(1) + "yield unit"
    }
}

func TraceBranch(string conditionText, string thenText, string elseText) string {
    if elseText == "" {
        return "branch " + conditionText + " | " + indent(1) + "then " + thenText + " | " + indent(1) + "else <missing>"
    }
    return "branch " + conditionText + " | " + indent(1) + "then " + thenText + " | " + indent(1) + "else " + elseText
}

func TraceLoop(string loopKind, string conditionText, string bodyText) string {
    return loopKind + " " + conditionText + " | " + indent(1) + "body " + bodyText
}

func TraceSwitch(string subjectText, string armsText) string {
    if armsText == "" {
        return "switch " + subjectText
    }
    return "switch " + subjectText + " | " + armsText
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

func joinText(Vec[string] values, string sep) string {
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
