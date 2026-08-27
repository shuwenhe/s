package compile.internal.ssa

func run_cse(ssa_func f) int {
    changed := 0
    i := 0
    for i < len(f.values) {
        if f.values[i].removed || !(op_is_pure(f.values[i].op)) {
            i = i + 1
            continue
        }
        key_i := value_key(f.values[i])
        j := 0
        for j < i {
            if !f.values[j].removed && op_is_pure(f.values[j].op) {
                if value_key(f.values[j]) == key_i {
                    rewrite_value_references(f, i, j)
                    f.values[i].removed = true
                    changed = changed + 1
                    break
                }
            }
            j = j + 1
        }
        i = i + 1
    }
    if changed > 0 {
        recompute_uses(f)
    }
    changed
}
