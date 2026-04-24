package compile.internal.ssa

func softfloat_module_name() string {
    "ssa/softfloat.s"
}

func softfloat_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
