package compile.internal.ssa

func allocators_module_name() string {
    "ssa/allocators.s"
}

func allocators_module_apply(ssa_func f) int {
    recompute_uses(f)
    0
}
