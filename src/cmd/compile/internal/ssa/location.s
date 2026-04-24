package compile.internal.ssa

func location_module_name() string {
    "ssa/location.s"
}

func location_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
