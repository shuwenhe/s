package compile.internal.ssa

func layout_module_name() string {
    "ssa/layout.s"
}

func layout_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
