package compile.internal.ssa
use std.vec.vec

func run_deadcode(ssa_func f) int {
    recompute_uses(f)
    changed := 0
    i := 0
    for i < f.values.len() {
        v := f.values[i]
        if !v.removed {
            keep := op_has_side_effect(v.op) || v.uses > 0
            if !keep {
                f.values[i].removed = true
                changed = changed + 1
            }
        }
        i = i + 1
    }
    bi := 0
    for bi < f.blocks.len() {
        compact := vec[int]()
        j := 0
        for j < f.blocks[bi].values.len() {
            id := f.blocks[bi].values[j]
            if id >= 0 && id < f.values.len() && !f.values[id].removed {
                compact.push(id)
            }
            j = j + 1
        }
        f.blocks[bi].values = compact
        bi = bi + 1
    }
    changed
}
