package compile.internal.ssa

func html_module_name() string {
    "ssa/html.s"
}

func html_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
