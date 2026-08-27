package compile.internal.ssa

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
            j = j + 1
        }
        i = i + 1
    }
    bi := 0
    for bi < len(f.blocks) {
        b := f.blocks[bi]
        k := 0
        for k < len(b.values) {
            if b.values[k] < 0 || b.values[k] >= len(f.values) {
                return 3
            }
            k = k + 1
        }
        if b.control >= len(f.values) {
            return 4
        }
        bi = bi + 1
    }
    0
}
