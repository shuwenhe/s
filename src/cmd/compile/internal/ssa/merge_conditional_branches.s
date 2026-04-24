package compile.internal.ssa

func merge_conditional_branches_module_name() string {
    "ssa/merge_conditional_branches.s"
}

func merge_conditional_branches_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
