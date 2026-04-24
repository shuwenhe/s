package compile.internal.ssa

func biasedsparsemap_module_name() string {
    "ssa/biasedsparsemap.s"
}

func biasedsparsemap_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
