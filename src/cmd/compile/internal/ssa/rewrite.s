package compile.internal.ssa

func run_rewrite(mut ssa_func f) int {
    var total = 0
    var rounds = 0
    while rounds < 6 {
        var changed = run_rewrite_generic(f)
        total = total + changed
        if changed == 0 {
            break
        }
        rounds = rounds + 1
    }
    total
}
