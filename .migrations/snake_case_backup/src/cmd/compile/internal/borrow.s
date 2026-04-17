package compile.internal.borrow

use std.prelude.len
use std.prelude.slice
use std.vec.Vec

func AnalyzeBlock() int32 {
    return 0
}

func AnalyzeTrace(string scope, Vec[string] typeEnv, string blockText) string {
    var plan = makePlanTrace(typeEnv)
    var text = "borrow " + scope
    if blockText != "" {
        text = text + " | " + blockText
    }
    if plan.len() == 0 {
        return text + " | plan <empty>"
    }
    return text + " | plan " + joinText(plan, ", ")
}

func AnalyzeFunction(string name, Vec[string] typeEnv, string bodyText) string {
    return AnalyzeTrace(name, typeEnv, bodyText)
}

func AnalyzeExpr(string scope, string exprText) string {
    if exprText == "" {
        return "expr " + scope + " | <empty>"
    }
    return "expr " + scope + " | " + exprText
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

func makePlanTrace(Vec[string] typeEnv) Vec[string] {
    var plan = Vec[string]()
    var i = 0
    while i < typeEnv.len() {
        var ty = typeEnv[i]
        if ty == "" {
            plan.push("borrow:<empty>")
        } else if startsWith(ty, "&") {
            plan.push("copy:" + ty)
        } else {
            plan.push("drop:" + ty)
        }
        i = i + 1
    }
    return plan
}

func startsWith(string text, string prefix) bool {
    var prefixLen = len(prefix)
    if prefixLen > len(text) {
        return false
    }
    return slice(text, 0, prefixLen) == prefix
}
