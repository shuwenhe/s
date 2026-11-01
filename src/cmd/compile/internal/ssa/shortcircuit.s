package compile.internal.ssa
func shortcircuit_module_name() string {
    "ssa/shortcircuit.s"
}

func shortcircuit_module_apply(ssa_func f) int {
    recompute_uses(f)
    0
}
