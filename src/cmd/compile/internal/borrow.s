package compile.internal.borrow

use std.prelude.len
use std.prelude.slice
use std.vec.Vec

func AnalyzeBlock() -> i32 {
    return 0
}

func AnalyzeTrace(String scope, Vec[String] type_env, String block_text) -> String {
    var plan = make_plan_trace(type_env)
    var text = "borrow " + scope
    if block_text != "" {
        text = text + " | " + block_text
    }
    if plan.len() == 0 {
        return text + " | plan <empty>"
    }
    return text + " | plan " + join_text(plan, ", ")
}

func AnalyzeFunction(String name, Vec[String] type_env, String body_text) -> String {
    return AnalyzeTrace(name, type_env, body_text)
}

func AnalyzeExpr(String scope, String expr_text) -> String {
    if expr_text == "" {
        return "expr " + scope + " | <empty>"
    }
    return "expr " + scope + " | " + expr_text
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

func make_plan_trace(Vec[String] type_env) -> Vec[String] {
    var plan = Vec[String]()
    var i = 0
    while i < type_env.len() {
        var ty = type_env[i]
        if ty == "" {
            plan.push("borrow:<empty>")
        } else if starts_with(ty, "&") {
            plan.push("copy:" + ty)
        } else {
            plan.push("drop:" + ty)
        }
        i = i + 1
    }
    return plan
}

func starts_with(String text, String prefix) -> bool {
    var prefix_len = len(prefix)
    if prefix_len > len(text) {
        return false
    }
    return slice(text, 0, prefix_len) == prefix
}
