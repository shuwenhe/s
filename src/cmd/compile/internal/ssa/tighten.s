package compile.internal.ssa

func tighten_module_name() string {
    "ssa/tighten.s"
}

func tighten_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
