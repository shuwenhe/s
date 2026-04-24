package compile.internal.ssa

func cache_module_name() string {
    "ssa/cache.s"
}

func cache_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
