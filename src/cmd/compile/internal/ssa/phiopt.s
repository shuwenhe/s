package compile.internal.ssa

func phiopt_module_name() string {
    "ssa/phiopt.s"
}

func phiopt_module_apply(ssa_func f) int {
    recompute_uses(f)
    0
}
