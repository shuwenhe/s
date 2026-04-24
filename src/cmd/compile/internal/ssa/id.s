package compile.internal.ssa

func id_module_name() string {
    "ssa/id.s"
}

func id_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
