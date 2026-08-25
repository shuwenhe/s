package compile.internal.ssa

func fuse_module_name() string {
    "ssa/fuse.s"
}

func fuse_module_apply(ssa_func f) int {
    recompute_uses(f)
    0
}
