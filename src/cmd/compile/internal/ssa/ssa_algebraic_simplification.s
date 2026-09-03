package internal.ssa

struct algebraic_rule {
    int id
    string name
    int priority
}

algebraic_rule*[] algebra_rules
int algebra_rule_count

func init_algebraic_rules() int {
    algebra_rules = algebraic_rule*[500]
    algebra_rule_count = 0
    return 0
}

func add_algebra_rule(string name, int priority) int {
    if algebra_rule_count >= 500 {
        return -1
    }
    
    algebraic_rule* rule = new algebraic_rule
    rule.id = algebra_rule_count
    rule.name = name
    rule.priority = priority
    
    algebra_rules[algebra_rule_count] = rule
    algebra_rule_count = algebra_rule_count + 1
    
    return rule.id
}

func algebraic_mul_to_shift(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 102 {
        return v
    }
    
    ssa_value* left = v.args[0]
    ssa_value* right = v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    
    if right.op == 1 {
        long rv = right.aux_int[0]
        if rv == 2 {
            ssa_value* shift = ssa_value_new_op(v.id + 6000000, 113, left, ssa_value_new_const_value(v.id + 6000001, 1, 0), v.type_id)
            return shift
        }
        if rv == 4 {
            ssa_value* shift = ssa_value_new_op(v.id + 6000002, 113, left, ssa_value_new_const_value(v.id + 6000003, 1, 2), v.type_id)
            return shift
        }
        if rv == 8 {
            ssa_value* shift = ssa_value_new_op(v.id + 6000004, 113, left, ssa_value_new_const_value(v.id + 6000005, 1, 3), v.type_id)
            return shift
        }
        if rv == 16 {
            ssa_value* shift = ssa_value_new_op(v.id + 6000006, 113, left, ssa_value_new_const_value(v.id + 6000007, 1, 4), v.type_id)
            return shift
        }
    }
    
    if left.op == 1 {
        long lv = left.aux_int[0]
        if lv == 2 {
            ssa_value* shift = ssa_value_new_op(v.id + 6000008, 113, right, ssa_value_new_const_value(v.id + 6000009, 1, 1), v.type_id)
            return shift
        }
        if lv == 4 {
            ssa_value* shift = ssa_value_new_op(v.id + 6000010, 113, right, ssa_value_new_const_value(v.id + 6000011, 1, 2), v.type_id)
            return shift
        }
        if lv == 8 {
            ssa_value* shift = ssa_value_new_op(v.id + 6000012, 113, right, ssa_value_new_const_value(v.id + 6000013, 1, 3), v.type_id)
            return shift
        }
        if lv == 16 {
            ssa_value* shift = ssa_value_new_op(v.id + 6000014, 113, right, ssa_value_new_const_value(v.id + 6000015, 1, 4), v.type_id)
            return shift
        }
    }
    
    return v
}

func algebraic_div_to_shift(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 103 {
        return v
    }
    
    ssa_value* left = v.args[0]
    ssa_value* right = v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    
    if right.op == 1 {
        long rv = right.aux_int[0]
        if rv == 2 {
            ssa_value* shift = ssa_value_new_op(v.id + 6000100, 114, left, ssa_value_new_const_value(v.id + 6000101, 1, 1), v.type_id)
            return shift
        }
        if rv == 4 {
            ssa_value* shift = ssa_value_new_op(v.id + 6000102, 114, left, ssa_value_new_const_value(v.id + 6000103, 1, 2), v.type_id)
            return shift
        }
        if rv == 8 {
            ssa_value* shift = ssa_value_new_op(v.id + 6000104, 114, left, ssa_value_new_const_value(v.id + 6000105, 1, 3), v.type_id)
            return shift
        }
        if rv == 16 {
            ssa_value* shift = ssa_value_new_op(v.id + 6000106, 114, left, ssa_value_new_const_value(v.id + 6000107, 1, 4), v.type_id)
            return shift
        }
    }
    
    return v
}

func algebraic_commutativity(ssa_value* v) ssa_value* {
    if v == 0 || v.op < 100 || v.op > 115 {
        return v
    }
    
    ssa_value* left = v.args[0]
    ssa_value* right = v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    
    if left.op != 1 && right.op == 1 {
        switch v.op {
        case 100 :
        case 102 :
        case 110 :
        case 111 :
        case 112 :
            ssa_value* swapped = ssa_value_new_op(v.id + 6000200, v.op, right, left, v.type_id)
            return swapped
        }
    }
    
    return v
}

func algebraic_neg_neg(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 401 {
        return v
    }
    
    ssa_value* arg = v.args[0]
    
    if arg == 0 {
        return v
    }
    
    if arg.op == 401 {
        return arg.args[0]
    }
    
    return v
}

func algebraic_not_not(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 402 {
        return v
    }
    
    ssa_value* arg = v.args[0]
    
    if arg == 0 {
        return v
    }
    
    if arg.op == 402 {
        return arg.args[0]
    }
    
    return v
}

func algebraic_double_negation(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 403 {
        return v
    }
    
    ssa_value* arg = v.args[0]
    
    if arg == 0 {
        return v
    }
    
    if arg.op == 403 {
        return arg.args[0]
    }
    
    return v
}

func algebraic_a_minus_a(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 101 {
        return v
    }
    
    ssa_value* left = v.args[0]
    ssa_value* right = v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    
    if left == right {
        return ssa_value_new_const(v.id + 6000300, 1, v.type_id)
    }
    
    return v
}

func algebraic_a_xor_a(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 112 {
        return v
    }
    
    ssa_value* left = v.args[0]
    ssa_value* right = v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    
    if left == right {
        return ssa_value_new_const(v.id + 6000301, 1, v.type_id)
    }
    
    return v
}

func algebraic_a_or_a(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 111 {
        return v
    }
    
    ssa_value* left = v.args[0]
    ssa_value* right = v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    
    if left == right {
        return left
    }
    
    return v
}

func algebraic_a_and_a(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 110 {
        return v
    }
    
    ssa_value* left = v.args[0]
    ssa_value* right = v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    
    if left == right {
        return left
    }
    
    return v
}

func algebraic_de_morgan_and(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 111 {
        return v
    }
    
    ssa_value* left = v.args[0]
    ssa_value* right = v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    
    if left.op == 402 && right.op == 402 {
        ssa_value* or_op = ssa_value_new_op(v.id + 6000302, 111, left.args[0], right.args[0], v.type_id)
        ssa_value* not_op = ssa_value_new_op(v.id + 6000303, 402, or_op, 0, v.type_id)
        return not_op
    }
    
    return v
}

func algebraic_de_morgan_or(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 110 {
        return v
    }
    
    ssa_value* left = v.args[0]
    ssa_value* right = v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    
    if left.op == 402 && right.op == 402 {
        ssa_value* and_op = ssa_value_new_op(v.id + 6000304, 110, left.args[0], right.args[0], v.type_id)
        ssa_value* not_op = ssa_value_new_op(v.id + 6000305, 402, and_op, 0, v.type_id)
        return not_op
    }
    
    return v
}

func algebraic_add_neg_to_sub(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 100 {
        return v
    }
    
    ssa_value* left = v.args[0]
    ssa_value* right = v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    
    if right.op == 401 {
        ssa_value* sub = ssa_value_new_op(v.id + 6000306, 101, left, right.args[0], v.type_id)
        return sub
    }
    
    if left.op == 401 {
        ssa_value* sub = ssa_value_new_op(v.id + 6000307, 101, right, left.args[0], v.type_id)
        return sub
    }
    
    return v
}

func algebraic_associativity_constants(ssa_value* v) ssa_value* {
    if v == 0 || (v.op < 100 || v.op > 102) {
        return v
    }
    
    ssa_value* left = v.args[0]
    ssa_value* right = v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    
    if left.op == 100 || left.op == 101 || left.op == 102 {
        ssa_value* left_left = left.args[0]
        ssa_value* left_right = left.args[1]
        
        if left_left == 0 || left_right == 0 {
            return v
        }
        
        if left_left.op == 1 && right.op == 1 {
            long combined = 0
            
            if v.op == 100 && left.op == 100 {
                combined = left_left.aux_int[0] + left_right.aux_int[0] + right.aux_int[0]
            } else if v.op == 102 && left.op == 102 {
                combined = left_left.aux_int[0] * left_right.aux_int[0] * right.aux_int[0]
            }
            
            if combined != 0 {
                ssa_value* const_val = ssa_value_new_const(v.id + 6000308, 1, v.type_id)
                const_val.aux_int[0] = combined
                
                ssa_value* reassoc = ssa_value_new_op(v.id + 6000309, v.op, left_right, const_val, v.type_id)
                return reassoc
            }
        }
    }
    
    return v
}

func apply_all_algebraic_simplifications(ssa_value* v) ssa_value* {
    if v == 0 {
        return v
    }
    
    ssa_value* result = v
    
    result = algebraic_mul_to_shift(result)
    result = algebraic_div_to_shift(result)
    result = algebraic_commutativity(result)
    result = algebraic_neg_neg(result)
    result = algebraic_not_not(result)
    result = algebraic_double_negation(result)
    result = algebraic_a_minus_a(result)
    result = algebraic_a_xor_a(result)
    result = algebraic_a_or_a(result)
    result = algebraic_a_and_a(result)
    result = algebraic_de_morgan_and(result)
    result = algebraic_de_morgan_or(result)
    result = algebraic_add_neg_to_sub(result)
    result = algebraic_associativity_constants(result)
    
    return result
}

func optimize_value_algebraic(ssa_value* v) int {
    if v == 0 {
        return 0
    }
    
    ssa_value* optimized = apply_all_algebraic_simplifications(v)
    
    if optimized != v {
        return 1
    }
    
    return 0
}
