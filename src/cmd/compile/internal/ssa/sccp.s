package compile.internal.ssa
func sccp_module_name() string {
    "ssa/sccp.s"
}

func sccp_module_apply(ssa_func f) int {
    recompute_uses(f)
    0
}
