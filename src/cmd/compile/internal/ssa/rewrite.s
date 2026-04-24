package compile.internal.ssa

func run_arch_rewrite(mut ssa_func f, string arch) int {
    if arch == "amd64" {
        return run_rewrite_amd64(f)
    }
    if arch == "arm64" {
        return run_rewrite_arm64(f)
    }
    if arch == "arm" {
        return run_rewrite_arm(f)
    }
    0
}

func run_rewrite(mut ssa_func f, string arch) int {
    var total = 0
    var rounds = 0
    while rounds < 6 {
        var g = run_rewrite_generic(f)
        var a = run_arch_rewrite(f, arch)
        var changed = g + a
        total = total + changed
        if changed == 0 {
            break
        }
        rounds = rounds + 1
    }
    total
}
