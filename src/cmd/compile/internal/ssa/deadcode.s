package compile.internal.ssa

use std.vec.vec

func run_deadcode(mut ssa_func f) int {
    recompute_uses(f)
    let changed = 0
    let i = 0
    while i < f.values.len() {
        let v = f.values[i]
        if !v.removed {
            let keep = op_has_side_effect(v.op) || v.uses > 0
            if !keep {
                f.values[i].removed = true
                changed = changed + 1
            }
        }
        i = i + 1
    }

    let bi = 0
    while bi < f.blocks.len() {
        let compact = vec[int]()
        let j = 0
        while j < f.blocks[bi].values.len() {
            let id = f.blocks[bi].values[j]
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
