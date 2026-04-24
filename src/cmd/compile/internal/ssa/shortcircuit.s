package compile.internal.ssa

func shortcircuit_module_name() string {
    "ssa/shortcircuit.s"
}

func shortcircuit_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
