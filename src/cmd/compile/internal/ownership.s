package compile.internal.ownership

use compile.internal.typesys.IsCopyType
use std.vec.Vec

func MakeDecision(string ty) string {
    if IsCopyType(ty) {
        return "copy:" + ty
    }
    "drop:" + ty
}

func MakePlan(Vec[string] type_env) Vec[string] {
    var plan = Vec[string]()
    var i = 0
    while i < type_env.len() {
        var ty = type_env[i]
        var next_i = i + 1
        i = next_i
        plan.push(MakeDecision(ty))
    }
    return plan
}
