package compile.internal.ssa

func branchelim_module_name() string {
    "ssa/branchelim.s"
}

func branchelim_module_apply(ssa_func f) int {
    recompute_uses(f)
    0
}
