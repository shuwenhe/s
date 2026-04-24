package compile.internal.ssa

func opGen_module_name() string {
    "ssa/opGen.s"
}

func opGen_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
