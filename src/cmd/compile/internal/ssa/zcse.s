package compile.internal.ssa

func zcse_module_name() string {
    "ssa/zcse.s"
}

func zcse_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
