package compile.internal.ssa
func poset_module_name() string {
    "ssa/poset.s"
}

func poset_module_apply(ssa_func f) int {
    recompute_uses(f)
    0
}
