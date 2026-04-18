package compile.internal.ownership

use compile.internal.typesys.is_copy_type
use std.vec.vec

func make_decision(string ty) string {
    if is_copy_type(ty) {
        return "copy:" + ty
    }
    "drop:" + ty
}

func make_plan(vec[string] type_env) vec[string] {
    var plan = vec[string]()
    var i = 0
    while i < type_env.len() {
        var ty = type_env[i]
        var next_i = i + 1
        i = next_i
        plan.push(make_decision(ty))
    }
    return plan
}
