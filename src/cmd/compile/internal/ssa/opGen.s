package compile.internal.ssa
func op_gen_module_name() string {
    "ssa/opGen.s"
}

func op_gen_module_apply(ssa_func f) int {
    recompute_uses(f)
    0
}
