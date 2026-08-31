package compile.internal.ssa
use std.slices

func run_deadcode(ssa_func f) int {
    recompute_uses(f)
    changed := 0
    i := 0
    for i < len(f.values) {
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
    for bi < len(f.blocks) {
        compact := int[]()
        j := 0
        for j < len(f.blocks[bi].values) {
            id := f.blocks[bi].values[j]
            if id >= 0 && id < len(f.values) && !f.values[id].removed {
                compact = append(compact, id)
            }
            j = j + 1
        }
        f.blocks[bi].values = compact
        bi = bi + 1
    }
    changed
}
