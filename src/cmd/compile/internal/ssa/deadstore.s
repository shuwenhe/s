package compile.internal.ssa

func deadstore_module_name() string {
    "ssa/deadstore.s"
}

func deadstore_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
