package compile.internal.ssa

func licm_module_name() string {
    "ssa/licm.s"
}

func licm_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
