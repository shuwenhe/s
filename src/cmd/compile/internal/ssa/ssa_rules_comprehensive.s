package internal.ssa

struct ssa_rule {
    int id
    string name
    int priority
    int enabled
}

struct ssa_rule_engine {
    ssa_rule[] rules
    int rule_count
    int max_rules
}

func ssa_rule_engine_new(int capacity) ssa_rule_engine {
    engine := ssa_rule_engine {
        rules: ssa_rule[](),
        rule_count: 0,
        max_rules: capacity
    }
    engine
}

func (engine* ssa_rule_engine) add_rule(string name, int priority) int {
    if engine.rule_count >= engine.max_rules {
        return -1
    }
    
    rule := ssa_rule {
        id: engine.rule_count,
        name: name,
        priority: priority,
        enabled: 1
    }
    
    engine.rules = append(engine.rules, rule)
    engine.rule_count = engine.rule_count + 1
    return rule.id
}

func (engine* ssa_rule_engine) apply_all(ssa_value* v) ssa_value* {
    if v == 0 {
        return v
    }
    
    for i := 0; i < engine.rule_count; i = i + 1 {
        rule := engine.rules[i]
        if rule.enabled == 0 {
            continue
        }
        
        v = engine.apply_rule(v, rule.id)
    }
    
    v
}

func (engine* ssa_rule_engine) apply_rule(ssa_value* v, int rule_id) ssa_value* {
    switch rule_id {
    case 0 : v = rule_add_const_const(v)
    case 1 : v = rule_add_x_zero(v)
    case 2 : v = rule_add_zero_x(v)
    case 3 : v = rule_sub_const_const(v)
    case 4 : v = rule_sub_x_zero(v)
    case 5 : v = rule_sub_zero_x(v)
    case 6 : v = rule_mul_const_const(v)
    case 7 : v = rule_mul_x_zero(v)
    case 8 : v = rule_mul_zero_x(v)
    case 9 : v = rule_mul_x_one(v)
    case 10: v = rule_mul_one_x(v)
    case 11: v = rule_mul_x_two(v)
    case 12: v = rule_mul_two_x(v)
    case 13: v = rule_div_const_const(v)
    case 14: v = rule_div_zero_x(v)
    case 15: v = rule_div_x_one(v)
    case 16: v = rule_rem_const_const(v)
    case 17: v = rule_rem_zero_x(v)
    case 18: v = rule_rem_x_one(v)
    case 19: v = rule_and_x_zero(v)
    case 20: v = rule_and_zero_x(v)
    case 21: v = rule_and_x_x(v)
    case 22: v = rule_and_x_minus_one(v)
    case 23: v = rule_or_x_zero(v)
    case 24: v = rule_or_zero_x(v)
    case 25: v = rule_or_x_x(v)
    case 26: v = rule_or_x_minus_one(v)
    case 27: v = rule_xor_x_zero(v)
    case 28: v = rule_xor_zero_x(v)
    case 29: v = rule_xor_x_x(v)
    case 30: v = rule_shl_const_const(v)
    case 31: v = rule_shl_x_zero(v)
    case 32: v = rule_shr_const_const(v)
    case 33: v = rule_shr_x_zero(v)
    case 34: v = rule_neg_const(v)
    case 35: v = rule_neg_neg(v)
    case 36: v = rule_not_const(v)
    case 37: v = rule_not_not(v)
    case 38: v = rule_neg_zero(v)
    case 39: v = rule_cmp_const_const(v)
    case 40: v = rule_cmp_x_x(v)
    case 41: v = rule_commute_add(v)
    case 42: v = rule_commute_mul(v)
    case 43: v = rule_commute_and(v)
    case 44: v = rule_commute_or(v)
    case 45: v = rule_commute_xor(v)
    case 46: v = rule_add_mul_dist(v)
    case 47: v = rule_sub_mul_dist(v)
    case 48: v = rule_and_or_dist(v)
    case 49: v = rule_de_morgan_and(v)
    case 50: v = rule_de_morgan_or(v)
    }
    
    v
}

func rule_add_const_const(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_add {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    if left.op != op_const || right.op != op_const {
        return v
    }
    
    result_val := left.aux_int + right.aux_int
    result := ssa_value_new_const_int(v.id + 1000000, result_val, v.type_id)
    result
}

func rule_add_x_zero(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_add {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    if right.op != op_const {
        return v
    }
    if right.aux_int != 0 {
        return v
    }
    
    left
}

func rule_add_zero_x(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_add {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    if left.op != op_const {
        return v
    }
    if left.aux_int != 0 {
        return v
    }
    
    right
}

func rule_sub_const_const(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_sub {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    if left.op != op_const || right.op != op_const {
        return v
    }
    
    result_val := left.aux_int - right.aux_int
    result := ssa_value_new_const_int(v.id + 1000001, result_val, v.type_id)
    result
}

func rule_sub_x_zero(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_sub {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    if right.op != op_const {
        return v
    }
    if right.aux_int != 0 {
        return v
    }
    
    left
}

func rule_sub_zero_x(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_sub {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    if left.op != op_const {
        return v
    }
    if left.aux_int != 0 {
        return v
    }
    
    neg_result := ssa_value_new_const_int(v.id + 1000002, -right.aux_int, v.type_id)
    neg_result
}

func rule_mul_const_const(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_mul {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    if left.op != op_const || right.op != op_const {
        return v
    }
    
    result_val := left.aux_int * right.aux_int
    result := ssa_value_new_const_int(v.id + 1000003, result_val, v.type_id)
    result
}

func rule_mul_x_zero(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_mul {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if right == 0 {
        return v
    }
    if right.op != op_const {
        return v
    }
    if right.aux_int != 0 {
        return v
    }
    
    ssa_value_new_const_int(v.id + 1000004, 0, v.type_id)
}

func rule_mul_zero_x(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_mul {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if left == 0 {
        return v
    }
    if left.op != op_const {
        return v
    }
    if left.aux_int != 0 {
        return v
    }
    
    ssa_value_new_const_int(v.id + 1000005, 0, v.type_id)
}

func rule_mul_x_one(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_mul {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if right == 0 {
        return v
    }
    if right.op != op_const {
        return v
    }
    if right.aux_int != 1 {
        return v
    }
    
    left
}

func rule_mul_one_x(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_mul {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if left == 0 {
        return v
    }
    if left.op != op_const {
        return v
    }
    if left.aux_int != 1 {
        return v
    }
    
    right
}

func rule_mul_x_two(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_mul {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if right == 0 {
        return v
    }
    if right.op != op_const {
        return v
    }
    if right.aux_int != 2 {
        return v
    }
    
    shift_val := ssa_value_new_const_int(v.id + 1000006, 1, v.type_id)
    shift_result := ssa_value_new_binary_op(v.id + 1000007, op_shl, left, shift_val, v.type_id)
    shift_result
}

func rule_mul_two_x(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_mul {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if left == 0 {
        return v
    }
    if left.op != op_const {
        return v
    }
    if left.aux_int != 2 {
        return v
    }
    
    shift_val := ssa_value_new_const_int(v.id + 1000008, 1, v.type_id)
    shift_result := ssa_value_new_binary_op(v.id + 1000009, op_shl, right, shift_val, v.type_id)
    shift_result
}

func rule_div_const_const(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_div {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    if left.op != op_const || right.op != op_const {
        return v
    }
    if right.aux_int == 0 {
        return v
    }
    
    result_val := left.aux_int / right.aux_int
    result := ssa_value_new_const_int(v.id + 1000010, result_val, v.type_id)
    result
}

func rule_div_zero_x(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_div {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if left == 0 {
        return v
    }
    if left.op != op_const {
        return v
    }
    if left.aux_int != 0 {
        return v
    }
    
    ssa_value_new_const_int(v.id + 1000011, 0, v.type_id)
}

func rule_div_x_one(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_div {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if right == 0 {
        return v
    }
    if right.op != op_const {
        return v
    }
    if right.aux_int != 1 {
        return v
    }
    
    left
}

func rule_rem_const_const(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_rem {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    if left.op != op_const || right.op != op_const {
        return v
    }
    if right.aux_int == 0 {
        return v
    }
    
    result_val := left.aux_int % right.aux_int
    result := ssa_value_new_const_int(v.id + 1000012, result_val, v.type_id)
    result
}

func rule_rem_zero_x(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_rem {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if left == 0 {
        return v
    }
    if left.op != op_const {
        return v
    }
    if left.aux_int != 0 {
        return v
    }
    
    ssa_value_new_const_int(v.id + 1000013, 0, v.type_id)
}

func rule_rem_x_one(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_rem {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if right == 0 {
        return v
    }
    if right.op != op_const {
        return v
    }
    if right.aux_int != 1 {
        return v
    }
    
    ssa_value_new_const_int(v.id + 1000014, 0, v.type_id)
}

func rule_and_x_zero(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_and {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if right == 0 {
        return v
    }
    if right.op != op_const {
        return v
    }
    if right.aux_int != 0 {
        return v
    }
    
    ssa_value_new_const_int(v.id + 1000015, 0, v.type_id)
}

func rule_and_zero_x(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_and {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if left == 0 {
        return v
    }
    if left.op != op_const {
        return v
    }
    if left.aux_int != 0 {
        return v
    }
    
    ssa_value_new_const_int(v.id + 1000016, 0, v.type_id)
}

func rule_and_x_x(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_and {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    
    if left.id == right.id {
        return left
    }
    
    v
}

func rule_and_x_minus_one(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_and {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if right == 0 {
        return v
    }
    if right.op != op_const {
        return v
    }
    if right.aux_int != -1 {
        return v
    }
    
    left
}

func rule_or_x_zero(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_or {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if right == 0 {
        return v
    }
    if right.op != op_const {
        return v
    }
    if right.aux_int != 0 {
        return v
    }
    
    left
}

func rule_or_zero_x(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_or {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if left == 0 {
        return v
    }
    if left.op != op_const {
        return v
    }
    if left.aux_int != 0 {
        return v
    }
    
    right
}

func rule_or_x_x(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_or {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    
    if left.id == right.id {
        return left
    }
    
    v
}

func rule_or_x_minus_one(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_or {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if right == 0 {
        return v
    }
    if right.op != op_const {
        return v
    }
    if right.aux_int != -1 {
        return v
    }
    
    ssa_value_new_const_int(v.id + 1000017, -1, v.type_id)
}

func rule_xor_x_zero(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_xor {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if right == 0 {
        return v
    }
    if right.op != op_const {
        return v
    }
    if right.aux_int != 0 {
        return v
    }
    
    left
}

func rule_xor_zero_x(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_xor {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if left == 0 {
        return v
    }
    if left.op != op_const {
        return v
    }
    if left.aux_int != 0 {
        return v
    }
    
    right
}

func rule_xor_x_x(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_xor {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    
    if left.id == right.id {
        return ssa_value_new_const_int(v.id + 1000018, 0, v.type_id)
    }
    
    v
}

func rule_shl_const_const(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_shl {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    if left.op != op_const || right.op != op_const {
        return v
    }
    
    result_val := left.aux_int << right.aux_int
    result := ssa_value_new_const_int(v.id + 1000019, result_val, v.type_id)
    result
}

func rule_shl_x_zero(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_shl {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if right == 0 {
        return v
    }
    if right.op != op_const {
        return v
    }
    if right.aux_int != 0 {
        return v
    }
    
    left
}

func rule_shr_const_const(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_shr {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    if left.op != op_const || right.op != op_const {
        return v
    }
    
    result_val := left.aux_int >> right.aux_int
    result := ssa_value_new_const_int(v.id + 1000020, result_val, v.type_id)
    result
}

func rule_shr_x_zero(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_shr {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if right == 0 {
        return v
    }
    if right.op != op_const {
        return v
    }
    if right.aux_int != 0 {
        return v
    }
    
    left
}

func rule_neg_const(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_neg {
        return v
    }
    if v.arg_count != 1 {
        return v
    }
    
    arg := v.args[0]
    
    if arg == 0 {
        return v
    }
    if arg.op != op_const {
        return v
    }
    
    result_val := -arg.aux_int
    result := ssa_value_new_const_int(v.id + 1000021, result_val, v.type_id)
    result
}

func rule_neg_neg(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_neg {
        return v
    }
    if v.arg_count != 1 {
        return v
    }
    
    arg := v.args[0]
    
    if arg == 0 {
        return v
    }
    if arg.op != op_neg {
        return v
    }
    
    if arg.arg_count != 1 {
        return v
    }
    
    arg.args[0]
}

func rule_not_const(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_not {
        return v
    }
    if v.arg_count != 1 {
        return v
    }
    
    arg := v.args[0]
    
    if arg == 0 {
        return v
    }
    if arg.op != op_const {
        return v
    }
    
    result_val := ^arg.aux_int
    result := ssa_value_new_const_int(v.id + 1000022, result_val, v.type_id)
    result
}

func rule_not_not(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_not {
        return v
    }
    if v.arg_count != 1 {
        return v
    }
    
    arg := v.args[0]
    
    if arg == 0 {
        return v
    }
    if arg.op != op_not {
        return v
    }
    
    if arg.arg_count != 1 {
        return v
    }
    
    arg.args[0]
}

func rule_neg_zero(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_neg {
        return v
    }
    if v.arg_count != 1 {
        return v
    }
    
    arg := v.args[0]
    
    if arg == 0 {
        return v
    }
    if arg.op != op_const {
        return v
    }
    if arg.aux_int != 0 {
        return v
    }
    
    ssa_value_new_const_int(v.id + 1000023, 0, v.type_id)
}

func rule_cmp_const_const(v ssa_value*) ssa_value* {
    if v == 0 {
        return v
    }
    
    if v.op < op_eq || v.op > op_ge {
        return v
    }
    
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    if left.op != op_const || right.op != op_const {
        return v
    }
    
    lv := left.aux_int
    rv := right.aux_int
    result := 0
    
    switch v.op {
    case op_eq:
        result = (lv == rv) ? 1 : 0
    case op_ne:
        result = (lv != rv) ? 1 : 0
    case op_lt:
        result = (lv < rv) ? 1 : 0
    case op_le:
        result = (lv <= rv) ? 1 : 0
    case op_gt:
        result = (lv > rv) ? 1 : 0
    case op_ge:
        result = (lv >= rv) ? 1 : 0
    }
    
    ssa_value_new_const_int(v.id + 1000024, result, v.type_id)
}

func rule_cmp_x_x(v ssa_value*) ssa_value* {
    if v == 0 {
        return v
    }
    
    if v.op < op_eq || v.op > op_ge {
        return v
    }
    
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if left == 0 || right == 0 {
        return v
    }
    if left.id != right.id {
        return v
    }
    
    result := 0
    
    switch v.op {
    case op_eq:
        result = 1
    case op_ne:
        result = 0
    case op_lt:
        result = 0
    case op_le:
        result = 1
    case op_gt:
        result = 0
    case op_ge:
        result = 1
    }
    
    ssa_value_new_const_int(v.id + 1000025, result, v.type_id)
}

func rule_commute_add(v ssa_value*) ssa_value* {
    v
}

func rule_commute_mul(v ssa_value*) ssa_value* {
    v
}

func rule_commute_and(v ssa_value*) ssa_value* {
    v
}

func rule_commute_or(v ssa_value*) ssa_value* {
    v
}

func rule_commute_xor(v ssa_value*) ssa_value* {
    v
}

func rule_add_mul_dist(v ssa_value*) ssa_value* {
    v
}

func rule_sub_mul_dist(v ssa_value*) ssa_value* {
    v
}

func rule_and_or_dist(v ssa_value*) ssa_value* {
    v
}

func rule_de_morgan_and(v ssa_value*) ssa_value* {
    v
}

func rule_de_morgan_or(v ssa_value*) ssa_value* {
    v
}
