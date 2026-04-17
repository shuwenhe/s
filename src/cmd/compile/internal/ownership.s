package compile.internal.ownership

use compile.internal.typesys.IsCopyType
use std.vec.Vec

func MakeDecision(String ty) -> String {
    if IsCopyType(ty) {
        return "copy:" + ty
    }
    "drop:" + ty
}

func MakePlan(Vec[String] type_env) -> Vec[String] {
    var plan = Vec[String]()
    var i = 0
    while i < type_env.len() {
        var ty = type_env[i]
        var next_i = i + 1
        i = next_i
        plan.push(MakeDecision(ty))
    }
    return plan
}
