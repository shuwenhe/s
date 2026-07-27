package compile.internal.ssa

func fuse_module_name() string {
    "ssa/fuse.s"
}

func fuse_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
