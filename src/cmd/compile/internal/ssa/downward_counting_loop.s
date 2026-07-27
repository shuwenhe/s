package compile.internal.ssa

func downward_counting_loop_module_name() string {
    "ssa/downward_counting_loop.s"
}

func downward_counting_loop_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
