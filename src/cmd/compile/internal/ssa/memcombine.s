package compile.internal.ssa

func memcombine_module_name() string {
    "ssa/memcombine.s"
}

func memcombine_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
