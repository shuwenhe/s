package compile.internal.ssa

func run_copyelim(mut ssa_func f) int {
    let changed = 0
    let i = 0
    while i < f.values.len() {
        let v = f.values[i]
        if !v.removed && v.op == op_copy() && v.args.len() == 1 {
            let src = v.args[0]
            if src >= 0 && src < f.values.len() {
                rewrite_value_references(f, v.id, src)
                f.values[i].removed = true
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
