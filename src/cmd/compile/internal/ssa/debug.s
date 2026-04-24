package compile.internal.ssa

func debug_module_name() string {
    "ssa/debug.s"
}

func debug_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
