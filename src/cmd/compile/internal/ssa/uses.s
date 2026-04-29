package compile.internal.ssa

use std.vec.vec

func recompute_uses(mut ssa_func f) {
    let i = 0
    while i < f.values.len() {
        f.values[i].uses = 0
        i = i + 1
    }
    i = 0
    while i < f.values.len() {
        if !f.values[i].removed {
            let j = 0
            while j < f.values[i].args.len() {
                let id = f.values[i].args[j]
                if id >= 0 && id < f.values.len() {
                    f.values[id].uses = f.values[id].uses + 1
                }
                j = j + 1
            }
        }
        i = i + 1
    }
    let bi = 0
    while bi < f.blocks.len() {
        let ctrl = f.blocks[bi].control
        if ctrl >= 0 && ctrl < f.values.len() {
            f.values[ctrl].uses = f.values[ctrl].uses + 1
        }
        bi = bi + 1
    }
}

func rewrite_value_references(mut ssa_func f, int from_id, int to_id) int {
    let changed = 0
    let i = 0
    while i < f.values.len() {
        let j = 0
        while j < f.values[i].args.len() {
            if f.values[i].args[j] == from_id {
                f.values[i].args[j] = to_id
                changed = changed + 1
            }
            j = j + 1
        }
        i = i + 1
    }
    let bi = 0
    while bi < f.blocks.len() {
        if f.blocks[bi].control == from_id {
            f.blocks[bi].control = to_id
            changed = changed + 1
        }
        bi = bi + 1
    }
    changed
}
