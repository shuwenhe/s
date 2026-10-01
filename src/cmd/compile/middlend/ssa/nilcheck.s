package compile.internal.ssa
func nilcheck_module_name() string {
    "ssa/nilcheck.s"
}

func nilcheck_module_apply(ssa_func f) int {
    recompute_uses(f)
    0
}
