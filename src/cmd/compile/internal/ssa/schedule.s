package compile.internal.ssa

use std.vec.vec

func run_schedule(mut ssa_func f) int {
    let changed = 0
    let bi = 0
    while bi < f.blocks.len() {
        let vals = f.blocks[bi].values
        let i = 0
        while i < vals.len() {
            let j = i + 1
            while j < vals.len() {
                if vals[j] < vals[i] {
                    let t = vals[i]
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
