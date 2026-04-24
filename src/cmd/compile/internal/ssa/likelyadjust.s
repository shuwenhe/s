package compile.internal.ssa

func likelyadjust_module_name() string {
    "ssa/likelyadjust.s"
}

func likelyadjust_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
