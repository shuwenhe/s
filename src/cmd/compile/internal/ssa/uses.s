package compile.internal.ssa
use std.vec.vec

func recompute_uses(ssa_func f) {
    i := 0
    for i < f.values.len() {
        f.values[i].uses = 0
        i = i + 1
    }
    i = 0
    for i < f.values.len() {
        if !f.values[i].removed {
            j := 0
            for j < f.values[i].args.len() {
                id := f.values[i].args[j]
                if id >= 0 && id < f.values.len() {
                    f.values[id].uses = f.values[id].uses + 1
                }
                j = j + 1
            }
        }
        i = i + 1
    }
    bi := 0
    for bi < f.blocks.len() {
        ctrl := f.blocks[bi].control
        if ctrl >= 0 && ctrl < f.values.len() {
            f.values[ctrl].uses = f.values[ctrl].uses + 1
        }
        bi = bi + 1
    }
}

func rewrite_value_references(ssa_func f, int from_id, int to_id) int {
    changed := 0
    i := 0
    for i < f.values.len() {
        j := 0
        for j < f.values[i].args.len() {
            if f.values[i].args[j] == from_id {
                f.values[i].args[j] = to_id
                changed = changed + 1
            }
            j = j + 1
        }
        i = i + 1
    }
    bi := 0
    for bi < f.blocks.len() {
        if f.blocks[bi].control == from_id {
            f.blocks[bi].control = to_id
            changed = changed + 1
        }
        bi = bi + 1
    }
    changed
}
