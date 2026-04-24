package compile.internal.arm64

struct arch_info {
    string link_arch
    int reg_sp
    int max_width
    string pad_frame_hook
    string zero_range_hook
    string ginsnop_hook
    string ssa_mark_moves_hook
    string ssa_gen_value_hook
    string ssa_gen_block_hook
    string load_reg_result_hook
    string spill_arg_reg_hook
}

func init_arm64(arch_info mut arch) arch_info {
    arch.link_arch = "arm64"
    arch.reg_sp = 31
    arch.max_width = 1 << 50
    arch.pad_frame_hook = "padframe"
    arch.zero_range_hook = "zerorange"
    arch.ginsnop_hook = "ginsnop"
    arch.ssa_mark_moves_hook = "ssa_mark_moves"
    arch.ssa_gen_value_hook = "ssa_gen_value"
    arch.ssa_gen_block_hook = "ssa_gen_block"
    arch.load_reg_result_hook = "load_reg_result"
    arch.spill_arg_reg_hook = "spill_arg_reg"
    arch
}

func init_arch_info() arch_info {
    var info = arch_info {
        link_arch: "",
        reg_sp: 0,
        max_width: 0,
        pad_frame_hook: "",
        zero_range_hook: "",
        ginsnop_hook: "",
        ssa_mark_moves_hook: "",
        ssa_gen_value_hook: "",
        ssa_gen_block_hook: "",
        load_reg_result_hook: "",
        spill_arg_reg_hook: "",
    }
    init_arm64(info)
}

func link_arch_name() string {
    "arm64"
}

func stack_pointer_register() int {
    31
}

func max_width_limit() int {
    1 << 50
}
