package main

struct reg_amounts {
    int int_regs
    int float_regs
}

struct abi_config {
    int offset_for_locals
    reg_amounts reg_amounts
    int which
}

func make_config(int i_regs_count, int f_regs_count, int offset_for_locals, int which) abi_config {
    abi_config {
        offset_for_locals: offset_for_locals, reg_amounts reg_amounts {
            int_regs: i_regs_count, float_regs f_regs_count,
        }, which which,
    }
}
