package compile.internal.ssa

func lca_module_name() string {
    "ssa/lca.s"
}

func lca_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
