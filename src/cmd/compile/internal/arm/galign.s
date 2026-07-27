package compile.internal.arm

struct arch_info {
    string link_arch
    int reg_sp
    int max_width
    bool soft_float
    string zero_range_hook
    string ginsnop_hook
    string ssa_mark_moves_hook
    string ssa_gen_value_hook
    string ssa_gen_block_hook
}

func init() () {
}

func init_arm(arch_info mut arch) arch_info {
    arch.link_arch = "arm"
    arch.reg_sp = 13
    arch.max_width = (1 << 32) - 1
    arch.soft_float = false
    arch.zero_range_hook = "zerorange"
    arch.ginsnop_hook = "ginsnop"
    arch.ssa_mark_moves_hook = "ssa_mark_moves"
    arch.ssa_gen_value_hook = "ssa_gen_value"
    arch.ssa_gen_block_hook = "ssa_gen_block"
    arch
}

func init_arch_info() arch_info {
    let info = arch_info {
        link_arch: "",
        reg_sp: 0,
        max_width: 0,
        soft_float: false,
        zero_range_hook: "",
        ginsnop_hook: "",
        ssa_mark_moves_hook: "",
        ssa_gen_value_hook: "",
        ssa_gen_block_hook: "",
    }
    init_arm(info)
}

func link_arch_name() string {
    "arm"
}

func stack_pointer_register() int {
    13
}

func max_width_limit() int {
    (1 << 32) - 1
}
