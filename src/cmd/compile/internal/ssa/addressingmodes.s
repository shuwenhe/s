package compile.internal.ssa

func addressingmodes_module_name() string {
    "ssa/addressingmodes.s"
}

func addressingmodes_module_apply(ssa_func f) int {
    recompute_uses(f)
    0
}
