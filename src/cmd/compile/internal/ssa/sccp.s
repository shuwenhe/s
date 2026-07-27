package compile.internal.ssa

func sccp_module_name() string {
    "ssa/sccp.s"
}

func sccp_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
