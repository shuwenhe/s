package compile.internal.ownership
use compile.internal.typesys.is_copy_type
use std.slices

func make_decision(string ty) string {
    if is_copy_type(ty) {
        return "copy:" + ty
    }
    "drop:" + ty
}

func make_plan(string[] type_env) string[] {
    plan := string[]()
    i := 0
    for i < len(type_env) {
        ty := type_env[i]
        next_i := i + 1
        i = next_i
        plan = append(plan, make_decision(ty))
    }
    return plan
}
