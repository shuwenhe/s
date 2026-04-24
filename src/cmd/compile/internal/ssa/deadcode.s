package compile.internal.ssa

use std.vec.vec

func run_deadcode(mut ssa_func f) int {
    recompute_uses(f)
    var changed = 0
    var i = 0
    while i < f.values.len() {
        var v = f.values[i]
        if !v.removed {
            var keep = op_has_side_effect(v.op) || v.uses > 0
            if !keep {
                f.values[i].removed = true
                changed = changed + 1
            }
        }
        i = i + 1
    }

    var bi = 0
    while bi < f.blocks.len() {
        var compact = vec[int]()
        var j = 0
        while j < f.blocks[bi].values.len() {
            var id = f.blocks[bi].values[j]
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
