package compile.internal.ssa

func writebarrier_module_name() string {
    "ssa/writebarrier.s"
}

func writebarrier_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
