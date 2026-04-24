package compile.internal.ssa

func cpufeatures_module_name() string {
    "ssa/cpufeatures.s"
}

func cpufeatures_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
