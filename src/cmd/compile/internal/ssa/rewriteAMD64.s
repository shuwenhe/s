package compile.internal.ssa
func run_rewrite_amd64(ssa_func f) int {
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
                f.values[i].op = "AMD64INC"
                f.values[i].args = [v.args[0]]
                f.values[i].literal = ""
                changed = changed + 1
            } else if is_const_with(f, v.args[1], "-1") {
                f.values[i].op = "AMD64DEC"
                f.values[i].args = [v.args[0]]
                f.values[i].literal = ""
                changed = changed + 1
            } else if is_const_with(f, v.args[0], "1") {
                f.values[i].op = "AMD64INC"
                f.values[i].args = [v.args[1]]
                f.values[i].literal = ""
                changed = changed + 1
            }
        } else if v.op == op_mul() && len(v.args) == 2 {
            if is_const_with(f, v.args[1], "2") {
                f.values[i].op = "AMD64LEA2"
                f.values[i].args = [v.args[0]]
                f.values[i].literal = ""
                changed = changed + 1
            } else if is_const_with(f, v.args[1], "4") {
                f.values[i].op = "AMD64LEA4"
                f.values[i].args = [v.args[0]]
                f.values[i].literal = ""
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
