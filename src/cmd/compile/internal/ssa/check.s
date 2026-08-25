package compile.internal.ssa

func check_func(ssa_func f) int {
    i := 0
    for i < f.values.len() {
        v := f.values[i]
        if v.id != i {
            return 1
        }
        j := 0
        for j < v.args.len() {
            if v.args[j] < 0 || v.args[j] >= f.values.len() {
                return 2
            }
            j = j + 1
        }
        i = i + 1
    }
    bi := 0
    for bi < f.blocks.len() {
        b := f.blocks[bi]
        k := 0
        for k < b.values.len() {
            if b.values[k] < 0 || b.values[k] >= f.values.len() {
                return 3
            }
            k = k + 1
        }
        if b.control >= f.values.len() {
            return 4
        }
        bi = bi + 1
    }
    0
}
