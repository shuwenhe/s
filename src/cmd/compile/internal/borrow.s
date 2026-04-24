package compile.internal.borrow

use std.prelude.len
use std.prelude.slice
use std.vec.vec

func analyze_block() int {
    return 0
}

func analyze_trace(string scope, vec[string] type_env, string block_text) string {
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

func analyze_function(string name, vec[string] type_env, string body_text) string {
    return analyze_trace(name, type_env, body_text)
}

func analyze_expr(string scope, string expr_text) string {
    if expr_text == "" {
        return "expr " + scope + " | <empty>"
    }
    return "expr " + scope + " | " + expr_text
}

func join_text(vec[string] values, string sep) string {
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

func make_plan_trace(vec[string] type_env) vec[string] {
    var plan = vec[string]()
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

func starts_with(string text, string prefix) bool {
    var prefix_len = len(prefix)
    if prefix_len > len(text) {
        return false
    }
    return slice(text, 0, prefix_len) == prefix
}
