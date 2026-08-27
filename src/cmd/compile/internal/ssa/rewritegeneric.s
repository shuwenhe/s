package compile.internal.ssa

func is_const_with(ssa_func f, int id, string lit) bool {
    if id < 0 || id >= len(f.values) {
        return false
    }
    v := f.values[id]
    v.op == op_const() && v.literal == lit
}

func rewrite_value_generic(ssa_func f, int id) bool {
    if id < 0 || id >= len(f.values) {
        return false
    }
    v := f.values[id]
    if v.removed {
        return false
    }
    if v.op == op_add() && len(v.args) == 2 {
        if is_const_with(f, v.args[1], "0") {
            f.values[id].op = op_copy()
            f.values[id].args = [v.args[0]]
            f.values[id].literal = ""
            return true
        }
        if is_const_with(f, v.args[0], "0") {
            f.values[id].op = op_copy()
            f.values[id].args = [v.args[1]]
            f.values[id].literal = ""
            return true
        }
    }
    if v.op == op_sub() && len(v.args) == 2 {
        if is_const_with(f, v.args[1], "0") {
            f.values[id].op = op_copy()
            f.values[id].args = [v.args[0]]
            f.values[id].literal = ""
            return true
        }
    }
    if v.op == op_mul() && len(v.args) == 2 {
        if is_const_with(f, v.args[0], "1") {
            f.values[id].op = op_copy()
            f.values[id].args = [v.args[1]]
            f.values[id].literal = ""
            return true
        }
        if is_const_with(f, v.args[1], "1") {
            f.values[id].op = op_copy()
            f.values[id].args = [v.args[0]]
            f.values[id].literal = ""
            return true
        }
        if is_const_with(f, v.args[0], "0") || is_const_with(f, v.args[1], "0") {
            f.values[id].op = op_const()
            f.values[id].args = []
            f.values[id].literal = "0"
            return true
        }
    }
    if v.op == op_div() && len(v.args) == 2 {
        if is_const_with(f, v.args[1], "1") {
            f.values[id].op = op_copy()
            f.values[id].args = [v.args[0]]
            f.values[id].literal = ""
            return true
        }
    }
    false
}

func run_rewrite_generic(ssa_func f) int {
    changed := 0
    i := 0
    for i < len(f.values) {
        if rewrite_value_generic(f, i) {
            changed = changed + 1
        }
        i = i + 1
    }
    if changed > 0 {
        recompute_uses(f)
    }
    changed
}
