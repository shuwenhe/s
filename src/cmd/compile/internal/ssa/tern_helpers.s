package compile.internal.ssa

func tern_helpers_module_name() string {
    "ssa/tern_helpers.s"
}

func tern_helpers_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
