package compile.internal.ssa

use std.vec.vec

struct ssa_block {
    int id
    string kind
    vec[int] values
    vec[int] preds
    vec[int] succs
    int control
}

func make_block(int id, string kind) ssa_block {
    ssa_block {
        id: id,
        kind: kind,
        values: vec[int](),
        preds: vec[int](),
        succs: vec[int](),
        control: -1,
    }
}

func block_set_control(mut ssa_block b, int value_id) ssa_block {
    b.control = value_id
    b
}
