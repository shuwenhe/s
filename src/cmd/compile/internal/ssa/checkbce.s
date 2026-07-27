package compile.internal.ssa

func checkbce_module_name() string {
    "ssa/checkbce.s"
}

func checkbce_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
