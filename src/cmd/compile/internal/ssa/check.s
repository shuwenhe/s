package compile.internal
// check_func validates structural invariants of an ssa_func, mirroring the
// sanity checks performed by the Go compiler's ssa checkFunc. It returns 0
// when every invariant holds, or a distinct non-zero code identifying the
// first violated invariant:
//   1  value id does not match its slot index
//   2  value argument references a value out of range
//   3  block value id references a value out of range
//   4  block control references a value out of range
//   5  two blocks share the same id (a block appears twice)
//   6  a successor edge references a block that does not exist
//   7  a predecessor edge references a block that does not exist
//   8  successor and predecessor edges are not crosslinked
//   9  a value is scheduled into more than one block
//   10 the entry block id does not reference an existing block
//   11 a fixed-arity operation has the wrong number of arguments
//   12 a Phi has an argument count that differs from its block's pred count
//   13 a non-Phi value lists itself as an argument (circular definition)

func count_int(int[] xs, int x) int {
    n := 0
    i := 0
    for i < len(xs) {
        if xs[i] == x {
            n = n + 1
        }
        i = i + 1
    }
    n
}

// value_block_index returns the index of the block whose value list contains
// value_id, or -1 when the value is not scheduled into any block.
func value_block_index(ssa_func f, int value_id) int {
    bi := 0
    for bi < len(f.blocks) {
        if count_int(f.blocks[bi].values, value_id) > 0 {
            return bi
        }
        bi = bi + 1
    }
    -1
}

// op_expected_arity reports the exact argument count required by op, or -1 for
// operations whose arity is variable or context dependent and therefore not
// checked here (Phi, Call, Load, Store, Return, Branch, Invalid).
func op_expected_arity(string op) int {
    if op == op_const() {
        return 0
    }
    if op == op_copy() {
        return 1
    }
    if op == op_add() {
        return 2
    }
    if op == op_sub() {
        return 2
    }
    if op == op_mul() {
        return 2
    }
    if op == op_div() {
        return 2
    }
    -1
}

func check_func(ssa_func f) int {
    i := 0
    for i < len(f.values) {
        v := f.values[i]
        if v.id != i {
            return 1
        }
        j := 0
        for j < len(v.args) {
            if v.args[j] < 0 || v.args[j] >= len(f.values) {
                return 2
            }
            if !v.removed && v.op != op_phi() && v.args[j] == v.id {
                return 13
            }
            j = j + 1
        }
        i = i + 1
    }
    bi := 0
    for bi < len(f.blocks) {
        b := f.blocks[bi]
        bj := bi + 1
        for bj < len(f.blocks) {
            if f.blocks[bj].id == b.id {
                return 5
            }
            bj = bj + 1
        }
        k := 0
        for k < len(b.values) {
            if b.values[k] < 0 || b.values[k] >= len(f.values) {
                return 3
            }
            k = k + 1
        }
        if b.control < 0 || b.control >= len(f.values) {
            return 4
        }
        s := 0
        for s < len(b.succs) {
            si := func_find_block_index(f, b.succs[s])
            if si < 0 {
                return 6
            }
            if count_int(f.blocks[si].preds, b.id) == 0 {
                return 8
            }
            s = s + 1
        }
        p := 0
        for p < len(b.preds) {
            pi := func_find_block_index(f, b.preds[p])
            if pi < 0 {
                return 7
            }
            if count_int(f.blocks[pi].succs, b.id) == 0 {
                return 8
            }
            p = p + 1
        }
        bi = bi + 1
    }
    vi := 0
    for vi < len(f.values) {
        seen := 0
        bb := 0
        for bb < len(f.blocks) {
            seen = seen + count_int(f.blocks[bb].values, vi)
            bb = bb + 1
        }
        if seen > 1 {
            return 9
        }
        vi = vi + 1
    }
    if func_find_block_index(f, f.entry) < 0 {
        return 10
    }
    ai := 0
    for ai < len(f.values) {
        v := f.values[ai]
        if !v.removed {
            want := op_expected_arity(v.op)
            if want >= 0 && len(v.args) != want {
                return 11
            }
        }
        ai = ai + 1
    }
    qi := 0
    for qi < len(f.values) {
        pv := f.values[qi]
        if !pv.removed && pv.op == op_phi() {
            home := value_block_index(f, pv.id)
            if home >= 0 && len(pv.args) != len(f.blocks[home].preds) {
                return 12
            }
        }
        qi = qi + 1
    }
    0
}
