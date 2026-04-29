package compile.internal.ssa

func run_rewrite_amd64(mut ssa_func f) int {
    let changed = 0
    let i = 0
    while i < f.values.len() {
        let v = f.values[i]
        if v.removed {
            i = i + 1
            continue
        }

        if v.op == op_add() && v.args.len() == 2 {
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
        } else if v.op == op_mul() && v.args.len() == 2 {
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
