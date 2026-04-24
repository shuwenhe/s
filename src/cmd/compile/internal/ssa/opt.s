package compile.internal.ssa

func opt_module_name() string {
    "ssa/opt.s"
}

func opt_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
