package compile.internal.ssa

func stackalloc_module_name() string {
    "ssa/stackalloc.s"
}

func stackalloc_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
