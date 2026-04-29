package compile.internal.ssa

func is_const_with(ssa_func f, int id, string lit) bool {
    if id < 0 || id >= f.values.len() {
        return false
    }
    let v = f.values[id]
    v.op == op_const() && v.literal == lit
}

func rewrite_value_generic(mut ssa_func f, int id) bool {
    if id < 0 || id >= f.values.len() {
        return false
    }
    let v = f.values[id]
    if v.removed {
        return false
    }

    if v.op == op_add() && v.args.len() == 2 {
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

    if v.op == op_sub() && v.args.len() == 2 {
        if is_const_with(f, v.args[1], "0") {
            f.values[id].op = op_copy()
            f.values[id].args = [v.args[0]]
            f.values[id].literal = ""
            return true
        }
    }

    if v.op == op_mul() && v.args.len() == 2 {
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

    if v.op == op_div() && v.args.len() == 2 {
        if is_const_with(f, v.args[1], "1") {
            f.values[id].op = op_copy()
            f.values[id].args = [v.args[0]]
            f.values[id].literal = ""
            return true
        }
    }

    false
}

func run_rewrite_generic(mut ssa_func f) int {
    let changed = 0
    let i = 0
    while i < f.values.len() {
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
