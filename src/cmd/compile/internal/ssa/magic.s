package compile.internal.ssa

func magic_module_name() string {
    "ssa/magic.s"
}

func magic_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
