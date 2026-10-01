package compile.internal.ssa
func flagalloc_module_name() string {
    "ssa/flagalloc.s"
}

func flagalloc_module_apply(ssa_func f) int {
    recompute_uses(f)
    0
}
