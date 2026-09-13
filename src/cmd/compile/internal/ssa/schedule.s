package compile.internal.ssa
use std.slices
func run_schedule(ssa_func f) int {
    changed := 0
    bi := 0
    for bi < len(f.blocks) {
        vals := f.blocks[bi].values
        i := 0
        for i < len(vals) {
            j := i + 1
            for j < len(vals) {
                if vals[j] < vals[i] {
                    t := vals[i]
                    vals[i] = vals[j]
                    vals[j] = t
                    changed = changed + 1
                }
                j = j + 1
            }
            i = i + 1
        }
        f.blocks[bi].values = vals
        bi = bi + 1
    }
    changed
}
