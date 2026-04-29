package compile.internal.ssa

func check_func(ssa_func f) int {
    let i = 0
    while i < f.values.len() {
        let v = f.values[i]
        if v.id != i {
            return 1
        }
        let j = 0
        while j < v.args.len() {
            if v.args[j] < 0 || v.args[j] >= f.values.len() {
                return 2
            }
            j = j + 1
        }
        i = i + 1
    }

    let bi = 0
    while bi < f.blocks.len() {
        let b = f.blocks[bi]
        let k = 0
        while k < b.values.len() {
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
