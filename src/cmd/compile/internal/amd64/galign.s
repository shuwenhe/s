package compile.internal.amd64

var leaptr = "LEAQ"

func init_amd64(arch_info mut arch) arch_info {
    arch.link_arch = "amd64"
    arch.reg_sp = 7
    arch.max_width = 1 << 50
    arch.zero_range_hook = "zerorange"
    arch.ginsnop_hook = "ginsnop"
    arch.ssa_mark_moves_hook = "ssa_mark_moves"
    arch.ssa_gen_value_hook = "ssa_gen_value"
    arch.ssa_gen_block_hook = "ssa_gen_block"
    arch.load_reg_result_hook = "load_reg_result"
    arch.spill_arg_reg_hook = "spill_arg_reg"
    arch
}

func link_arch_name() string {
    "amd64"
}

func stack_pointer_register() int {
    7
}

func max_width_limit() int {
    1 << 50
}
