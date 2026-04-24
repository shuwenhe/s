package compile.internal.ssa

func fuse_comparisons_module_name() string {
    "ssa/fuse_comparisons.s"
}

func fuse_comparisons_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
