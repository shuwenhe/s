package compile.internal.ssa

func run_rewrite_arm64(mut ssa_func f) int {
    var changed = 0
    var i = 0
    while i < f.values.len() {
        var v = f.values[i]
        if v.removed {
            i = i + 1
            continue
        }

        if v.op == op_add() && v.args.len() == 2 {
            if is_const_with(f, v.args[1], "0") {
                f.values[i].op = op_copy()
                f.values[i].args = [v.args[0]]
                f.values[i].literal = ""
                changed = changed + 1
            } else if is_const_with(f, v.args[1], "4095") {
                f.values[i].op = "ARM64ADDconst12"
                f.values[i].args = [v.args[0]]
                f.values[i].literal = "4095"
                changed = changed + 1
            }
        } else if v.op == op_sub() && v.args.len() == 2 {
            if is_const_with(f, v.args[1], "1") {
                f.values[i].op = "ARM64SUB1"
                f.values[i].args = [v.args[0]]
                f.values[i].literal = ""
                changed = changed + 1
            }
        } else if v.op == op_mul() && v.args.len() == 2 {
            if is_const_with(f, v.args[1], "2") {
                f.values[i].op = "ARM64LSL1"
                f.values[i].args = [v.args[0]]
                f.values[i].literal = "1"
                changed = changed + 1
            } else if is_const_with(f, v.args[1], "4") {
                f.values[i].op = "ARM64LSL2"
                f.values[i].args = [v.args[0]]
                f.values[i].literal = "2"
                changed = changed + 1
            }
        }
        i = i + 1
    }
    if changed > 0 {
        recompute_uses(f)
    }
    changed
}
