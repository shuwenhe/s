package compile.internal.ssa
use std.slices
struct ssa_block {
    id int
    kind string
    int[] values
    int[] preds
    int[] succs
    control int
}

func make_block(int id, string kind) ssa_block {
    ssa_block {
        id: id, kind kind, values int[](), preds int[](), succs int[](),
        control: -1,
    }
}

func block_set_control(ssa_block b, int value_id) ssa_block {
    b.control = value_id
    b
}