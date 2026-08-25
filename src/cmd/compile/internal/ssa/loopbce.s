package compile.internal.ssa

func loopbce_module_name() string {
    "ssa/loopbce.s"
}

func loopbce_module_apply(ssa_func f) int {
    recompute_uses(f)
    0
}
