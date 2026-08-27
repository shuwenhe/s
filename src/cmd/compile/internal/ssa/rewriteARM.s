package compile.internal.ssa

func run_rewrite_arm(ssa_func f) int {
    changed := 0
    i := 0
    for i < len(f.values) {
        v := f.values[i]
        if v.removed {
            i = i + 1
            continue
        }
        if v.op == op_add() && len(v.args) == 2 {
            if is_const_with(f, v.args[1], "1") {
                f.values[i].op = "ARMADD1"
                f.values[i].args = [v.args[0]]
                f.values[i].literal = ""
                changed = changed + 1
            }
        } else if v.op == op_sub() && len(v.args) == 2 {
            if is_const_with(f, v.args[1], "1") {
                f.values[i].op = "ARMSUB1"
                f.values[i].args = [v.args[0]]
                f.values[i].literal = ""
                changed = changed + 1
            }
        } else if v.op == op_mul() && len(v.args) == 2 {
            if is_const_with(f, v.args[1], "2") {
                f.values[i].op = "ARMLSL1"
                f.values[i].args = [v.args[0]]
                f.values[i].literal = "1"
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
