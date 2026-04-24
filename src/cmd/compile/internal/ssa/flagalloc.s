package compile.internal.ssa

func flagalloc_module_name() string {
    "ssa/flagalloc.s"
}

func flagalloc_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
