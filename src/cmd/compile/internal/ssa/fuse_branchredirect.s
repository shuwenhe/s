package compile.internal.ssa

func fuse_branchredirect_module_name() string {
    "ssa/fuse_branchredirect.s"
}

func fuse_branchredirect_module_apply(mut ssa_func f) int {
    recompute_uses(f)
    0
}
