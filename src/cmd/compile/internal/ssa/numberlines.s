package compile.internal.ssa

func numberlines_module_name() string {
    "ssa/numberlines.s"
}

func numberlines_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
