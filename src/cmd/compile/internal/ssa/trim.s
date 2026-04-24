package compile.internal.ssa

func trim_module_name() string {
    "ssa/trim.s"
}

func trim_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
