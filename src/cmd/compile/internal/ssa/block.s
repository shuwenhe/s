package compile.internal
struct ssa_bb {
    int id
    string kind
    int[] values
    int[] preds
    int[] succs
    int control
}

func make_block(int id, string kind) ssa_bb {
    values := []int{}
    preds := []int{}
    succs := []int{}
    return ssa_bb {
        id id, kind kind, values values, preds preds, succs succs,
        control 0
    }
}

func block_set_control(ssa_bb b, int value_id) ssa_bb {
    b.control = value_id
    b
}
