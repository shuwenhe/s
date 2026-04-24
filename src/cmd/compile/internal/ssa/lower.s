package compile.internal.ssa

func lower_module_name() string {
    "ssa/lower.s"
}

func lower_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
