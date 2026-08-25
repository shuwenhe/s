package compile.internal.ssa

func run_copyelim(mut ssa_func f) int {
    changed := 0
    i := 0
    while i < f.values.len() {
        v := f.values[i]
        if !v.removed && v.op == op_copy() && v.args.len() == 1 {
            src := v.args[0]
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
