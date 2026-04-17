package compile.internal.ownership

use compile.internal.typesys.IsCopyType
use std.vec.Vec

func MakeDecision(string ty) string {
    if IsCopyType(ty) {
        return "copy:" + ty
    }
    "drop:" + ty
}

func MakePlan(Vec[string] typeEnv) Vec[string] {
    var plan = Vec[string]()
    var i = 0
    while i < typeEnv.len() {
        var ty = typeEnv[i]
        var nextI = i + 1
        i = nextI
        plan.push(MakeDecision(ty))
    }
    return plan
}
