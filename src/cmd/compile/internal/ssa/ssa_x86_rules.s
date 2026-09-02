package ssa_x86_rules

struct X86Rule {
    int id
    int pattern_op
    int x86_opcode
    int priority
    int cpu_flags
}

struct AddressMode {
    int base_reg
    int index_reg
    int scale
    int offset
    int size
}

struct X86RuleEngine {
    int rule_count
    x86_rule[] rules
    int pattern_count
}

func X86RuleEngine_new() X86RuleEngine* {
    engine := new X86RuleEngine
    engine.rule_count = 0
    engine.pattern_count = 0
    engine.rules = new x86_rule[256]
    engine
}

func (engine* X86RuleEngine) register_x86_rule(int id, int pattern_op, int x86_opcode, int priority) int {
    idx := engine.rule_count
    engine.rule_count = engine.rule_count + 1
    
    rule := new X86Rule
    rule.id = id
    rule.pattern_op = pattern_op
    rule.x86_opcode = x86_opcode
    rule.priority = priority
    rule.cpu_flags = 0
    
    engine.rules[idx] = rule
    idx
}

func (engine* X86RuleEngine) match_lea_pattern(int op, int[] args) (int, int, int) {
    base := 0
    offset := 0
    scale := 0
    
    if op == OP_ADD {
        base = args[0]
        offset = args[1]
    } else {
        if op == OP_MUL {
            base = args[0]
            scale = args[1]
        }
    }
    
    return base, offset, scale
}

func (engine* X86RuleEngine) match_shift_pattern(int op, int[] args) (int, int) {
    value := args[0]
    shift_amount := args[1]
    
    return value, shift_amount
}

func (engine* X86RuleEngine) match_mul_to_shift(int op, int shift_amount) int {
    if op == OP_MUL {
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

func (engine* X86RuleEngine) match_div_to_shift(int op, int shift_amount) int {
    if op == OP_DIV {
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

func (engine* X86RuleEngine) match_addressing_mode(int base, int index, int scale, int offset) AddressMode* {
    mode := new AddressMode
    mode.base_reg = base
    mode.index_reg = index
    mode.scale = scale
    mode.offset = offset
    mode.size = 8
    mode
}

func (engine* X86RuleEngine) is_power_of_2(int n) int {
    if n <= 0 {
        return 0
    }
    
    if n & (n - 1) == 0 {
        return 1
    }
    
    return 0
}

func (engine* X86RuleEngine) log2_value(int n) int {
    result := 0
    
    i := 1
    for i < n {
        i = i * 2
        result = result + 1
    }
    
    result
}

func (engine* X86RuleEngine) optimize_mul_to_lea(int base, int shift_amount) int {
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

func (engine* X86RuleEngine) optimize_add_to_lea(int base, int offset) int {
    if offset == 0 {
        return 0
    }
    if offset < -2147483648 || offset > 2147483647 {
        return 0
    }
    
    return 1
}

func (engine* X86RuleEngine) optimize_compare_and_branch(int cmp_op, int branch_cond) (int, int) {
    x86_cond := 0
    
    if branch_cond == COND_EQ {
        x86_cond = X86_JE
    } else {
        if branch_cond == COND_NE {
            x86_cond = X86_JNE
        } else {
            if branch_cond == COND_LT {
                x86_cond = X86_JL
            } else {
                if branch_cond == COND_LE {
                    x86_cond = X86_JLE
                } else {
                    if branch_cond == COND_GT {
                        x86_cond = X86_JG
                    } else {
                        if branch_cond == COND_GE {
                            x86_cond = X86_JGE
                        }
                    }
                }
            }
        }
    }
    
    return x86_cond, 1
}

func (engine* X86RuleEngine) fuse_load_op(int load_op, int op, int store_op) (int, int) {
    if op == OP_ADD {
        if load_op == X86_MOV && store_op == X86_MOV {
            return X86_ADD, 1
        }
    } else {
        if op == OP_SUB {
            return X86_SUB, 1
        } else {
            if op == OP_AND {
                return X86_AND, 1
            } else {
                if op == OP_OR {
                    return X86_OR, 1
                } else {
                    if op == OP_XOR {
                        return X86_XOR, 1
                    }
                }
            }
        }
    }
    
    return 0, 0
}

func (engine* X86RuleEngine) optimize_push_pop(int pop_reg, int push_reg) int {
    if pop_reg == push_reg {
        return 1
    }
    
    return 0
}

func (engine* X86RuleEngine) optimize_register_move(int src_reg, int dst_reg) int {
    if src_reg == dst_reg {
        return 1
    }
    
    return 0
}

func (engine* X86RuleEngine) optimize_zero_extension(int size) int {
    if size == 1 || size == 2 || size == 4 {
        return 1
    }
    
    return 0
}

func (engine* X86RuleEngine) optimize_sign_extension(int size) int {
    if size == 1 || size == 2 || size == 4 {
        return 1
    }
    
    return 0
}

func (engine* X86RuleEngine) optimize_memory_access(int addr_base, int offset) int {
    if offset >= -128 && offset <= 127 {
        return 1
    }
    
    return 0
}

func (engine* X86RuleEngine) fuse_compare_branch(int cmp_op, int branch_op) int {
    if cmp_op == OP_CMP && branch_op == OP_BRANCH {
        return 1
    }
    
    return 0
}

const OP_ADD = 3
const OP_SUB = 4
const OP_MUL = 5
const OP_DIV = 6
const OP_MOD = 7
const OP_AND = 8
const OP_OR = 9
const OP_XOR = 10
const OP_SHL = 11
const OP_SHR = 12
const OP_LOAD = 13
const OP_STORE = 14
const OP_CALL = 15
const OP_CMP = 19
const OP_BRANCH = 17

const X86_MOV = 0x88
const X86_ADD = 0x01
const X86_SUB = 0x29
const X86_MUL = 0xF7
const X86_DIV = 0xF7
const X86_AND = 0x21
const X86_OR = 0x09
const X86_XOR = 0x31
const X86_SHL = 0xC1
const X86_SHR = 0xC1
const X86_SAR = 0xC1
const X86_LEA = 0x8D
const X86_CMP = 0x39
const X86_JE = 0x74
const X86_JNE = 0x75
const X86_JL = 0x7C
const X86_JLE = 0x7E
const X86_JG = 0x7F
const X86_JGE = 0x7D

const COND_EQ = 1
const COND_NE = 2
const COND_LT = 3
const COND_LE = 4
const COND_GT = 5
const COND_GE = 6

func init_x86_rules(engine* X86RuleEngine) int {
    engine.register_x86_rule(1, OP_ADD, X86_ADD, 10)
    engine.register_x86_rule(2, OP_SUB, X86_SUB, 10)
    engine.register_x86_rule(3, OP_MUL, X86_MUL, 20)
    engine.register_x86_rule(4, OP_DIV, X86_DIV, 20)
    engine.register_x86_rule(5, OP_AND, X86_AND, 10)
    engine.register_x86_rule(6, OP_OR, X86_OR, 10)
    engine.register_x86_rule(7, OP_XOR, X86_XOR, 10)
    engine.register_x86_rule(8, OP_SHL, X86_SHL, 15)
    engine.register_x86_rule(9, OP_SHR, X86_SHR, 15)
    engine.register_x86_rule(10, OP_LOAD, X86_MOV, 5)
    engine.register_x86_rule(11, OP_STORE, X86_MOV, 5)
    engine.register_x86_rule(12, OP_CMP, X86_CMP, 8)
    
    0
}
