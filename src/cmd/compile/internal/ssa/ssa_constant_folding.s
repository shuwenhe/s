package internal.ssa

struct const_fold_rule {
    int id
    string name
    int priority
}

const_fold_rule*[] fold_rules
int fold_rule_count

func init_const_fold_rules() int {
    fold_rules = new const_fold_rule*[500]
    fold_rule_count = 0
    return 0
}

func add_fold_rule(string name, int priority) int {
    if fold_rule_count >= 500 {
        return -1
    }
    
    rule := const_fold_rule {
        id: fold_rule_count,
        name: name,
        priority: priority,
    }

    fold_rules[fold_rule_count] = &rule
    fold_rule_count = fold_rule_count + 1
    
    return rule.id
}

func const_fold_add(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 100 {
        return v
    }
    
    ssa_value* left = v.args[0]
    ssa_value* right = v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    
    if left.op == 1 && right.op == 1 {
        long result_val = left.aux_int[0] + right.aux_int[0]
        ssa_value* result = ssa_value_new_const(v.id + 5000000, 1, v.type_id)
        result.aux_int[0] = result_val
        return result
    }
    
    if right.op == 1 && right.aux_int[0] == 0 {
        return left
    }
    
    if left.op == 1 && left.aux_int[0] == 0 {
        return right
    }
    
    return v
}

func const_fold_sub(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 101 {
        return v
    }
    
    ssa_value* left = v.args[0]
    ssa_value* right = v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    
    if left.op == 1 && right.op == 1 {
        long result_val = left.aux_int[0] - right.aux_int[0]
        ssa_value* result = ssa_value_new_const(v.id + 5000001, 1, v.type_id)
        result.aux_int[0] = result_val
        return result
    }
    
    if right.op == 1 && right.aux_int[0] == 0 {
        return left
    }
    
    if left.op == 1 && left.aux_int[0] == 0 {
        ssa_value* neg = ssa_value_new_const(v.id + 5000002, 1, v.type_id)
        neg.aux_int[0] = -right.aux_int[0]
        return neg
    }
    
    return v
}

func const_fold_mul(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 102 {
        return v
    }
    
    ssa_value* left = v.args[0]
    ssa_value* right = v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    
    if left.op == 1 && right.op == 1 {
        long result_val = left.aux_int[0] * right.aux_int[0]
        ssa_value* result = ssa_value_new_const(v.id + 5000003, 1, v.type_id)
        result.aux_int[0] = result_val
        return result
    }
    
    if right.op == 1 {
        long rv = right.aux_int[0]
        if rv == 0 {
            return ssa_value_new_const(v.id + 5000004, 1, v.type_id)
        }
        if rv == 1 {
            return left
        }
        if rv == 2 {
            ssa_value* shifted = ssa_value_new_shift(v.id + 5000005, left, 1, v.type_id)
            return shifted
        }
    }
    
    if left.op == 1 {
        long lv = left.aux_int[0]
        if lv == 0 {
            return ssa_value_new_const(v.id + 5000006, 1, v.type_id)
        }
        if lv == 1 {
            return right
        }
        if lv == 2 {
            ssa_value* shifted = ssa_value_new_shift(v.id + 5000007, right, 1, v.type_id)
            return shifted
        }
    }
    
    return v
}

func const_fold_div(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 103 {
        return v
    }
    
    ssa_value* left = v.args[0]
    ssa_value* right = v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    
    if left.op == 1 && right.op == 1 {
        if right.aux_int[0] != 0 {
            long result_val = left.aux_int[0] / right.aux_int[0]
            ssa_value* result = ssa_value_new_const(v.id + 5000008, 1, v.type_id)
            result.aux_int[0] = result_val
            return result
        }
    }
    
    if left.op == 1 && left.aux_int[0] == 0 {
        return ssa_value_new_const(v.id + 5000009, 1, v.type_id)
    }
    
    if right.op == 1 && right.aux_int[0] == 1 {
        return left
    }
    
    return v
}

func const_fold_rem(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 104 {
        return v
    }
    
    ssa_value* left = v.args[0]
    ssa_value* right = v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    
    if left.op == 1 && right.op == 1 {
        if right.aux_int[0] != 0 {
            long result_val = left.aux_int[0] % right.aux_int[0]
            ssa_value* result = ssa_value_new_const(v.id + 5000010, 1, v.type_id)
            result.aux_int[0] = result_val
            return result
        }
    }
    
    if left.op == 1 && left.aux_int[0] == 0 {
        return ssa_value_new_const(v.id + 5000011, 1, v.type_id)
    }
    
    return v
}

func const_fold_and(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 110 {
        return v
    }
    
    ssa_value* left = v.args[0]
    ssa_value* right = v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    
    if left.op == 1 && right.op == 1 {
        long result_val = left.aux_int[0] & right.aux_int[0]
        ssa_value* result = ssa_value_new_const(v.id + 5000012, 1, v.type_id)
        result.aux_int[0] = result_val
        return result
    }
    
    if left.op == 1 && left.aux_int[0] == 0 {
        return ssa_value_new_const(v.id + 5000013, 1, v.type_id)
    }
    
    if right.op == 1 && right.aux_int[0] == 0 {
        return ssa_value_new_const(v.id + 5000014, 1, v.type_id)
    }
    
    if left.op == 1 && left.aux_int[0] == -1 {
        return right
    }
    
    if right.op == 1 && right.aux_int[0] == -1 {
        return left
    }
    
    if left == right {
        return left
    }
    
    return v
}

func const_fold_or(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 111 {
        return v
    }
    
    ssa_value* left = v.args[0]
    ssa_value* right = v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    
    if left.op == 1 && right.op == 1 {
        long result_val = left.aux_int[0] | right.aux_int[0]
        ssa_value* result = ssa_value_new_const(v.id + 5000015, 1, v.type_id)
        result.aux_int[0] = result_val
        return result
    }
    
    if left.op == 1 && left.aux_int[0] == 0 {
        return right
    }
    
    if right.op == 1 && right.aux_int[0] == 0 {
        return left
    }
    
    if left.op == 1 && left.aux_int[0] == -1 {
        return ssa_value_new_const(v.id + 5000016, 1, v.type_id)
    }
    
    if right.op == 1 && right.aux_int[0] == -1 {
        return ssa_value_new_const(v.id + 5000017, 1, v.type_id)
    }
    
    if left == right {
        return left
    }
    
    return v
}

func const_fold_xor(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 112 {
        return v
    }
    
    ssa_value* left = v.args[0]
    ssa_value* right = v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    
    if left.op == 1 && right.op == 1 {
        long result_val = left.aux_int[0] ^ right.aux_int[0]
        ssa_value* result = ssa_value_new_const(v.id + 5000018, 1, v.type_id)
        result.aux_int[0] = result_val
        return result
    }
    
    if left.op == 1 && left.aux_int[0] == 0 {
        return right
    }
    
    if right.op == 1 && right.aux_int[0] == 0 {
        return left
    }
    
    if left == right {
        return ssa_value_new_const(v.id + 5000019, 1, v.type_id)
    }
    
    return v
}

func const_fold_shift_left(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 113 {
        return v
    }
    
    ssa_value* left = v.args[0]
    ssa_value* right = v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    
    if left.op == 1 && right.op == 1 {
        long result_val = left.aux_int[0] << right.aux_int[0]
        ssa_value* result = ssa_value_new_const(v.id + 5000020, 1, v.type_id)
        result.aux_int[0] = result_val
        return result
    }
    
    if right.op == 1 && right.aux_int[0] == 0 {
        return left
    }
    
    if left.op == 1 && left.aux_int[0] == 0 {
        return ssa_value_new_const(v.id + 5000021, 1, v.type_id)
    }
    
    return v
}

func const_fold_shift_right(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 114 {
        return v
    }
    
    ssa_value* left = v.args[0]
    ssa_value* right = v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    
    if left.op == 1 && right.op == 1 {
        long result_val = left.aux_int[0] >> right.aux_int[0]
        ssa_value* result = ssa_value_new_const(v.id + 5000022, 1, v.type_id)
        result.aux_int[0] = result_val
        return result
    }
    
    if right.op == 1 && right.aux_int[0] == 0 {
        return left
    }
    
    return v
}

func const_fold_comparison(ssa_value* v) ssa_value* {
    if v == 0 || (v.op < 200 || v.op > 210) {
        return v
    }
    
    ssa_value* left = v.args[0]
    ssa_value* right = v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    
    if left.op == 1 && right.op == 1 {
        long lv = left.aux_int[0]
        long rv = right.aux_int[0]
        int result_val = 0
        
        switch v.op {
        case 200 :
            result_val = lv == rv ? 1 : 0
        case 201 :
            result_val = lv != rv ? 1 : 0
        case 202 :
            result_val = lv < rv ? 1 : 0
        case 203 :
            result_val = lv <= rv ? 1 : 0
        case 204 :
            result_val = lv > rv ? 1 : 0
        case 205 :
            result_val = lv >= rv ? 1 : 0
        }
        
        ssa_value* result = ssa_value_new_const(v.id + 5000023, 1, v.type_id)
        result.aux_int[0] = result_val
        return result
    }
    
    return v
}

func apply_all_const_folding(ssa_value* v) ssa_value* {
    if v == 0 {
        return v
    }
    
    ssa_value* result = v
    
    result = const_fold_add(result)
    result = const_fold_sub(result)
    result = const_fold_mul(result)
    result = const_fold_div(result)
    result = const_fold_rem(result)
    result = const_fold_and(result)
    result = const_fold_or(result)
    result = const_fold_xor(result)
    result = const_fold_shift_left(result)
    result = const_fold_shift_right(result)
    result = const_fold_comparison(result)
    
    return result
}

func optimize_value_const_folding(ssa_value* v) int {
    if v == 0 {
        return 0
    }
    
    ssa_value* optimized = apply_all_const_folding(v)
    
    if optimized != v {
        return 1
    }
    
    return 0
}
