package internal.ssa

struct generic_rule {
    int id
    string name
    int pattern_op
    int* pattern_args
    int* result_op
    string description
}

generic_rule*[] generic_rules
int generic_rule_count

func init_generic_rules() int {
    generic_rules = generic_rule*[1000]
    generic_rule_count = 0
    return 0
}

func register_generic_rule(int pattern_op, int* pattern_args, int* result_op, string name) int {
    if generic_rule_count >= 1000 {
        return -1
    }
    
    generic_rule* rule = new generic_rule
    rule.id = generic_rule_count
    rule.pattern_op = pattern_op
    rule.pattern_args = pattern_args
    rule.result_op = result_op
    rule.name = name
    
    generic_rules[generic_rule_count] = rule
    generic_rule_count = generic_rule_count + 1
    
    return rule.id
}

func rule_const_add_zero(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 100 {
        return v
    }
    
    if v.args[1] == 0 {
        return v
    }
    
    if v.args[1].op == 1 && v.args[1].aux_int[0] == 0 {
        return v.args[0]
    }
    
    if v.args[0] == 0 {
        return v
    }
    
    if v.args[0].op == 1 && v.args[0].aux_int[0] == 0 {
        return v.args[1]
    }
    
    return v
}

func rule_const_mul_zero(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 102 {
        return v
    }
    
    if v.args[1] == 0 {
        return v
    }
    
    if v.args[1].op == 1 && v.args[1].aux_int[0] == 0 {
        ssa_value* zero = ssa_value_new(v.id + 3000000, 1, v.type_id)
        zero.aux_int[0] = 0
        return zero
    }
    
    if v.args[0] == 0 {
        return v
    }
    
    if v.args[0].op == 1 && v.args[0].aux_int[0] == 0 {
        ssa_value* zero = ssa_value_new(v.id + 3000001, 1, v.type_id)
        zero.aux_int[0] = 0
        return zero
    }
    
    return v
}

func rule_const_mul_one(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 102 {
        return v
    }
    
    if v.args[1] == 0 {
        return v
    }
    
    if v.args[1].op == 1 && v.args[1].aux_int[0] == 1 {
        return v.args[0]
    }
    
    if v.args[0] == 0 {
        return v
    }
    
    if v.args[0].op == 1 && v.args[0].aux_int[0] == 1 {
        return v.args[1]
    }
    
    return v
}

func rule_const_and_zero(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 110 {
        return v
    }
    
    if v.args[1] == 0 {
        return v
    }
    
    if v.args[1].op == 1 && v.args[1].aux_int[0] == 0 {
        ssa_value* zero = ssa_value_new(v.id + 3000002, 1, v.type_id)
        zero.aux_int[0] = 0
        return zero
    }
    
    if v.args[0] == 0 {
        return v
    }
    
    if v.args[0].op == 1 && v.args[0].aux_int[0] == 0 {
        ssa_value* zero = ssa_value_new(v.id + 3000003, 1, v.type_id)
        zero.aux_int[0] = 0
        return zero
    }
    
    return v
}

func rule_const_and_minus_one(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 110 {
        return v
    }
    
    if v.args[1] == 0 {
        return v
    }
    
    if v.args[1].op == 1 && v.args[1].aux_int[0] == -1 {
        return v.args[0]
    }
    
    if v.args[0] == 0 {
        return v
    }
    
    if v.args[0].op == 1 && v.args[0].aux_int[0] == -1 {
        return v.args[1]
    }
    
    return v
}

func rule_const_or_zero(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 111 {
        return v
    }
    
    if v.args[1] == 0 {
        return v
    }
    
    if v.args[1].op == 1 && v.args[1].aux_int[0] == 0 {
        return v.args[0]
    }
    
    if v.args[0] == 0 {
        return v
    }
    
    if v.args[0].op == 1 && v.args[0].aux_int[0] == 0 {
        return v.args[1]
    }
    
    return v
}

func rule_shift_optimization(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 103 {
        return v
    }
    
    if v.args[1] == 0 {
        return v
    }
    
    if v.args[1].op == 1 && v.args[1].aux_int[0] == 0 {
        return v.args[0]
    }
    
    return v
}

func rule_mul_shift_conversion(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 102 {
        return v
    }
    
    if v.args[1] == 0 {
        return v
    }
    
    if v.args[1].op == 1 {
        int const_val = v.args[1].aux_int[0]
        
        if const_val == 2 {
            ssa_value* shift = ssa_value_new(v.id + 3000004, 103, v.type_id)
            shift.args[0] = v.args[0]
            
            ssa_value* shift_count = ssa_value_new(v.id + 3000005, 1, v.type_id)
            shift_count.aux_int[0] = 1
            shift.args[1] = shift_count
            
            return shift
        }
        
        if const_val == 4 {
            ssa_value* shift = ssa_value_new(v.id + 3000006, 103, v.type_id)
            shift.args[0] = v.args[0]
            
            ssa_value* shift_count = ssa_value_new(v.id + 3000007, 1, v.type_id)
            shift_count.aux_int[0] = 2
            shift.args[1] = shift_count
            
            return shift
        }
        
        if const_val == 8 {
            ssa_value* shift = ssa_value_new(v.id + 3000008, 103, v.type_id)
            shift.args[0] = v.args[0]
            
            ssa_value* shift_count = ssa_value_new(v.id + 3000009, 1, v.type_id)
            shift_count.aux_int[0] = 3
            shift.args[1] = shift_count
            
            return shift
        }
    }
    
    return v
}

func rule_idempotent_and(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 110 {
        return v
    }
    
    if v.args[0] == v.args[1] {
        return v.args[0]
    }
    
    return v
}

func rule_idempotent_or(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 111 {
        return v
    }
    
    if v.args[0] == v.args[1] {
        return v.args[0]
    }
    
    return v
}

func rule_commutative_folding(ssa_value* v) ssa_value* {
    if v == 0 {
        return v
    }
    
    if v.op >= 100 && v.op <= 102 {
        if v.args[0] != 0 && v.args[1] != 0 {
            if v.args[0].op == 1 && v.args[1].op == 1 {
                int a = v.args[0].aux_int[0]
                int b = v.args[1].aux_int[0]
                int result = 0
                
                if v.op == 100 {
                    result = a + b
                } else if v.op == 101 {
                    if a >= b {
                        result = a - b
                    } else {
                        return v
                    }
                } else if v.op == 102 {
                    result = a * b
                }
                
                ssa_value* const_val = ssa_value_new(v.id + 3000010, 1, v.type_id)
                const_val.aux_int[0] = result
                return const_val
            }
        }
    }
    
    return v
}

func rule_load_load_merge(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 200 {
        return v
    }
    
    if v.args[0] == 0 {
        return v
    }
    
    if v.args[0].op == 200 {
        if v.args[1] == v.args[0].args[1] {
            return v.args[0]
        }
    }
    
    return v
}

func rule_store_of_store(ssa_value* v, ssa_block* block) int {
    if v == 0 || v.op != 201 {
        return 0
    }
    
    if block == 0 || block.values == 0 {
        return 0
    }
    
    int i = 0
    int found_idx = -1
    
    for i = 0; i < 1000; i = i + 1 {
        if block.values[i] == 0 {
            break
        }
        
        if block.values[i] == v {
            found_idx = i
            break
        }
    }
    
    if found_idx <= 0 {
        return 0
    }
    
    ssa_value* prev = block.values[found_idx - 1]
    
    if prev != 0 && prev.op == 201 {
        if v.args[0] == prev.args[0] && v.args[1] == prev.args[1] {
            return 1
        }
    }
    
    return 0
}

func rule_useless_phi(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 250 {
        return v
    }
    
    if v.args[0] == 0 {
        return v
    }
    
    int all_same = 1
    ssa_value* first = v.args[0]
    int i = 1
    
    for i = 1; i < 16; i = i + 1 {
        if v.args[i] == 0 {
            break
        }
        
        if v.args[i] != first {
            all_same = 0
            break
        }
    }
    
    if all_same == 1 {
        return first
    }
    
    return v
}

func rule_zero_extension(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 300 {
        return v
    }
    
    if v.args[0] == 0 {
        return v
    }
    
    if v.args[0].op == 1 && v.args[0].aux_int[0] == 0 {
        ssa_value* zero = ssa_value_new(v.id + 3000011, 1, v.type_id)
        zero.aux_int[0] = 0
        return zero
    }
    
    return v
}

func apply_all_generic_rules(ssa_value* v) ssa_value* {
    if v == 0 {
        return 0
    }
    
    ssa_value* result = v
    
    result = rule_const_add_zero(result)
    result = rule_const_mul_zero(result)
    result = rule_const_mul_one(result)
    result = rule_const_and_zero(result)
    result = rule_const_and_minus_one(result)
    result = rule_const_or_zero(result)
    result = rule_shift_optimization(result)
    result = rule_mul_shift_conversion(result)
    result = rule_idempotent_and(result)
    result = rule_idempotent_or(result)
    result = rule_commutative_folding(result)
    result = rule_load_load_merge(result)
    result = rule_useless_phi(result)
    result = rule_zero_extension(result)
    
    return result
}

func optimize_block_with_generic_rules(ssa_block* block) int {
    if block == 0 || block.values == 0 {
        return 0
    }
    
    int i = 0
    int changed = 1
    int iterations = 0
    int max_iterations = 10
    
    for iterations = 0; iterations < max_iterations; iterations = iterations + 1 {
        changed = 0
        
        for i = 0; i < 1000; i = i + 1 {
            if block.values[i] == 0 {
                break
            }
            
            ssa_value* optimized = apply_all_generic_rules(block.values[i])
            
            if optimized != block.values[i] {
                block.values[i] = optimized
                changed = 1
            }
        }
        
        if changed == 0 {
            break
        }
    }
    
    return iterations
}
