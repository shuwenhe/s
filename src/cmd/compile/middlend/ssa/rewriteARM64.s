package compile.internal.ssa
func run_rewrite_arm64(ssa_func f) int {
    changed := 0
    i := 0
    for i < len(f.values) {
        v := f.values[i]
        if v.removed {
            i = i + 1
            continue
        }
        if v.op == op_add() && len(v.args) == 2 {
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
        } else if v.op == op_sub() && len(v.args) == 2 {
            if is_const_with(f, v.args[1], "1") {
                f.values[i].op = "ARM64SUB1"
                f.values[i].args = [v.args[0]]
                f.values[i].literal = ""
                changed = changed + 1
            }
        } else if v.op == op_mul() && len(v.args) == 2 {
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
