package ssa_x86_rules

struct x86_rule {
    int id
    int pattern_op
    int x86_opcode
    int priority
    int cpu_flags
}

struct address_mode {
    int base_reg
    int index_reg
    int scale
    int offset
    int size
}

struct x86_rule_engine {
    int rule_count
    x86_rule[] rules
    int pattern_count
}

func x86_rule_engine_new() x86_rule_engine* {
    engine := x86_rule_engine {
        rule_count: 0,
        rules: new x86_rule[256],
        pattern_count: 0,
    }
    &engine
}

func (engine* x86_rule_engine) register_x86_rule(int id, int pattern_op, int x86_opcode, int priority) int {
    idx := engine.rule_count
    engine.rule_count = engine.rule_count + 1
    
    rule := x86_rule {
        id: id,
        pattern_op: pattern_op,
        x86_opcode: x86_opcode,
        priority: priority,
        cpu_flags: 0,
    }

    engine.rules[idx] = &rule
    idx
}

func (engine* x86_rule_engine) match_lea_pattern(int op, int[] args) (int, int, int) {
    base := 0
    offset := 0
    scale := 0
    
    if op == op_add {
        base = args[0]
        offset = args[1]
    } else {
        if op == op_mul {
            base = args[0]
            scale = args[1]
        }
    }
    
    return base, offset, scale
}

func (engine* x86_rule_engine) match_shift_pattern(int op, int[] args) (int, int) {
    value := args[0]
    shift_amount := args[1]
    
    return value, shift_amount
}

func (engine* x86_rule_engine) match_mul_to_shift(int op, int shift_amount) int {
    if op == op_mul {
        if shift_amount == 2 {
            return 1
        }
        if shift_amount == 4 {
            return 2
        }
        if shift_amount == 8 {
            return 3
        }
    }
    
    return 0
}

func (engine* x86_rule_engine) match_div_to_shift(int op, int shift_amount) int {
    if op == op_div {
        if shift_amount == 2 {
            return 1
        }
        if shift_amount == 4 {
            return 2
        }
        if shift_amount == 8 {
            return 3
        }
    }
    
    return 0
}

func (engine* x86_rule_engine) match_addressing_mode(int base, int index, int scale, int offset) address_mode* {
    mode := address_mode {
        base_reg: base,
        index_reg: index,
        scale: scale,
        offset: offset,
        size: 8,
    }
    &mode
}

func (engine* x86_rule_engine) is_power_of_2(int n) int {
    if n <= 0 {
        return 0
    }
    
    if n & (n - 1) == 0 {
        return 1
    }
    
    return 0
}

func (engine* x86_rule_engine) log2_value(int n) int {
    result := 0
    
    i := 1
    for i < n {
        i = i * 2
        result = result + 1
    }
    
    result
}

func (engine* x86_rule_engine) optimize_mul_to_lea(int base, int shift_amount) int {
    if shift_amount == 1 {
        return 1
    }
    if shift_amount == 2 {
        return 1
    }
    if shift_amount == 4 {
        return 1
    }
    if shift_amount == 8 {
        return 1
    }
    
    return 0
}

func (engine* x86_rule_engine) optimize_add_to_lea(int base, int offset) int {
    if offset == 0 {
        return 0
    }
    if offset < -2147483648 || offset > 2147483647 {
        return 0
    }
    
    return 1
}

func (engine* x86_rule_engine) optimize_compare_and_branch(int cmp_op, int branch_cond) (int, int) {
    x86_cond := 0
    
    if branch_cond == cond_eq {
        x86_cond = x86_je
    } else {
        if branch_cond == cond_ne {
            x86_cond = x86_jne
        } else {
            if branch_cond == cond_lt {
                x86_cond = x86_jl
            } else {
                if branch_cond == cond_le {
                    x86_cond = x86_jle
                } else {
                    if branch_cond == cond_gt {
                        x86_cond = x86_jg
                    } else {
                        if branch_cond == cond_ge {
                            x86_cond = x86_jge
                        }
                    }
                }
            }
        }
    }
    
    return x86_cond, 1
}

func (engine* x86_rule_engine) fuse_load_op(int load_op, int op, int store_op) (int, int) {
    if op == op_add {
        if load_op == x86_mov && store_op == x86_mov {
            return x86_add, 1
        }
    } else {
        if op == op_sub {
            return x86_sub, 1
        } else {
            if op == op_and {
                return x86_and, 1
            } else {
                if op == op_or {
                    return x86_or, 1
                } else {
                    if op == op_xor {
                        return x86_xor, 1
                    }
                }
            }
        }
    }
    
    return 0, 0
}

func (engine* x86_rule_engine) optimize_push_pop(int pop_reg, int push_reg) int {
    if pop_reg == push_reg {
        return 1
    }
    
    return 0
}

func (engine* x86_rule_engine) optimize_register_move(int src_reg, int dst_reg) int {
    if src_reg == dst_reg {
        return 1
    }
    
    return 0
}

func (engine* x86_rule_engine) optimize_zero_extension(int size) int {
    if size == 1 || size == 2 || size == 4 {
        return 1
    }
    
    return 0
}

func (engine* x86_rule_engine) optimize_sign_extension(int size) int {
    if size == 1 || size == 2 || size == 4 {
        return 1
    }
    
    return 0
}

func (engine* x86_rule_engine) optimize_memory_access(int addr_base, int offset) int {
    if offset >= -128 && offset <= 127 {
        return 1
    }
    
    return 0
}

func (engine* x86_rule_engine) fuse_compare_branch(int cmp_op, int branch_op) int {
    if cmp_op == op_cmp && branch_op == op_branch {
        return 1
    }
    
    return 0
}

const op_add = 3
const op_sub = 4
const op_mul = 5
const op_div = 6
const op_mod = 7
const op_and = 8
const op_or = 9
const op_xor = 10
const op_shl = 11
const op_shr = 12
const op_load = 13
const op_store = 14
const op_call = 15
const op_cmp = 19
const op_branch = 17

const x86_mov = 0x88
const x86_add = 0x01
const x86_sub = 0x29
const x86_mul = 0x_f7
const x86_div = 0x_f7
const x86_and = 0x21
const x86_or = 0x09
const x86_xor = 0x31
const x86_shl = 0x_c1
const x86_shr = 0x_c1
const x86_sar = 0x_c1
const x86_lea = 0x8_d
const x86_cmp = 0x39
const x86_je = 0x74
const x86_jne = 0x75
const x86_jl = 0x7_c
const x86_jle = 0x7_e
const x86_jg = 0x7_f
const x86_jge = 0x7_d

const cond_eq = 1
const cond_ne = 2
const cond_lt = 3
const cond_le = 4
const cond_gt = 5
const cond_ge = 6

func init_x86_rules(engine* x86_rule_engine) int {
    engine.register_x86_rule(1, op_add, x86_add, 10)
    engine.register_x86_rule(2, op_sub, x86_sub, 10)
    engine.register_x86_rule(3, op_mul, x86_mul, 20)
    engine.register_x86_rule(4, op_div, x86_div, 20)
    engine.register_x86_rule(5, op_and, x86_and, 10)
    engine.register_x86_rule(6, op_or, x86_or, 10)
    engine.register_x86_rule(7, op_xor, x86_xor, 10)
    engine.register_x86_rule(8, op_shl, x86_shl, 15)
    engine.register_x86_rule(9, op_shr, x86_shr, 15)
    engine.register_x86_rule(10, op_load, x86_mov, 5)
    engine.register_x86_rule(11, op_store, x86_mov, 5)
    engine.register_x86_rule(12, op_cmp, x86_cmp, 8)
    
    0
}
