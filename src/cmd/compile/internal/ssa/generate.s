package compile.internal.ssa

func generate_module_name() string {
    "ssa/generate.s"
}

func generate_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
