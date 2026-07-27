package compile.internal.ssa

func known_bits_module_name() string {
    "ssa/known_bits.s"
}

func known_bits_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
