package compile.internal.ssa

func critical_module_name() string {
    "ssa/critical.s"
}

func critical_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
