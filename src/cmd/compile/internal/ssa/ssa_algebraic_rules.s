package internal.ssa

func rule_mul_by_power_of_two_is_shift(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_mul {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if right == 0 || right.op != op_const {
        return v
    }
    
    power := 0
    val := right.aux_int
    
    if val <= 0 {
        return v
    }
    
    for val > 1 {
        if val % 2 != 0 {
            return v
        }
        val = val / 2
        power = power + 1
    }
    
    shift_amount := ssa_value_new_const_int(v.id + 2000000, power, v.type_id)
    ssa_value_new_binary_op(v.id + 2000001, op_shl, left, shift_amount, v.type_id)
}

func rule_div_by_power_of_two_is_shift(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_div {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if right == 0 || right.op != op_const {
        return v
    }
    
    power := 0
    val := right.aux_int
    
    if val <= 0 {
        return v
    }
    
    for val > 1 {
        if val % 2 != 0 {
            return v
        }
        val = val / 2
        power = power + 1
    }
    
    shift_amount := ssa_value_new_const_int(v.id + 2000010, power, v.type_id)
    ssa_value_new_binary_op(v.id + 2000011, op_shr, left, shift_amount, v.type_id)
}

func rule_double_neg_cancel(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_neg {
        return v
    }
    if v.arg_count != 1 {
        return v
    }
    
    inner := v.args[0]
    if inner == 0 || inner.op != op_neg {
        return v
    }
    if inner.arg_count != 1 {
        return v
    }
    
    inner.args[0]
}

func rule_add_neg_is_sub(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_add {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if right == 0 || right.op != op_neg {
        return v
    }
    if right.arg_count != 1 {
        return v
    }
    
    inner := right.args[0]
    ssa_value_new_binary_op(v.id + 2000020, op_sub, left, inner, v.type_id)
}

func rule_sub_neg_is_add(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_sub {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if right == 0 || right.op != op_neg {
        return v
    }
    if right.arg_count != 1 {
        return v
    }
    
    inner := right.args[0]
    ssa_value_new_binary_op(v.id + 2000021, op_add, left, inner, v.type_id)
}

func rule_mul_neg_commute(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_mul {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if right == 0 || right.op != op_neg {
        return v
    }
    
    if left.op == op_neg {
        return v
    }
    
    swapped := ssa_value_new_binary_op(v.id + 2000030, op_mul, right, left, v.type_id)
    swapped
}

func rule_and_or_absorption_1(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_and {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if right == 0 || right.op != op_or {
        return v
    }
    if right.arg_count != 2 {
        return v
    }
    
    or_left := right.args[0]
    if or_left == 0 || or_left.id != left.id {
        return v
    }
    
    left
}

func rule_and_or_absorption_2(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_and {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if right == 0 || right.op != op_or {
        return v
    }
    if right.arg_count != 2 {
        return v
    }
    
    or_right := right.args[1]
    if or_right == 0 || or_right.id != left.id {
        return v
    }
    
    left
}

func rule_or_and_absorption_1(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_or {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if right == 0 || right.op != op_and {
        return v
    }
    if right.arg_count != 2 {
        return v
    }
    
    and_left := right.args[0]
    if and_left == 0 || and_left.id != left.id {
        return v
    }
    
    left
}

func rule_or_and_absorption_2(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_or {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if right == 0 || right.op != op_and {
        return v
    }
    if right.arg_count != 2 {
        return v
    }
    
    and_right := right.args[1]
    if and_right == 0 || and_right.id != left.id {
        return v
    }
    
    left
}

func rule_and_idempotent(v ssa_value*) ssa_value* {
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

func rule_or_idempotent(v ssa_value*) ssa_value* {
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

func rule_xor_idempotent(v ssa_value*) ssa_value* {
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
        return ssa_value_new_const_int(v.id + 2000100, 0, v.type_id)
    }
    
    v
}

func rule_add_associative_left(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_add {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if left == 0 || left.op != op_add {
        return v
    }
    if left.arg_count != 2 {
        return v
    }
    
    a := left.args[0]
    b := left.args[1]
    c := right
    
    if b == 0 || c == 0 {
        return v
    }
    
    if b.op == op_const && c.op == op_const {
        bc_sum := ssa_value_new_const_int(v.id + 2000101, b.aux_int + c.aux_int, v.type_id)
        result := ssa_value_new_binary_op(v.id + 2000102, op_add, a, bc_sum, v.type_id)
        return result
    }
    
    v
}

func rule_mul_associative_left(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_mul {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if left == 0 || left.op != op_mul {
        return v
    }
    if left.arg_count != 2 {
        return v
    }
    
    a := left.args[0]
    b := left.args[1]
    c := right
    
    if b == 0 || c == 0 {
        return v
    }
    
    if b.op == op_const && c.op == op_const {
        bc_prod := ssa_value_new_const_int(v.id + 2000103, b.aux_int * c.aux_int, v.type_id)
        result := ssa_value_new_binary_op(v.id + 2000104, op_mul, a, bc_prod, v.type_id)
        return result
    }
    
    v
}

func rule_and_associative_left(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_and {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if left == 0 || left.op != op_and {
        return v
    }
    if left.arg_count != 2 {
        return v
    }
    
    a := left.args[0]
    b := left.args[1]
    c := right
    
    if b == 0 || c == 0 {
        return v
    }
    
    if b.op == op_const && c.op == op_const {
        bc_and := ssa_value_new_const_int(v.id + 2000105, b.aux_int & c.aux_int, v.type_id)
        result := ssa_value_new_binary_op(v.id + 2000106, op_and, a, bc_and, v.type_id)
        return result
    }
    
    v
}

func rule_or_associative_left(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_or {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if left == 0 || left.op != op_or {
        return v
    }
    if left.arg_count != 2 {
        return v
    }
    
    a := left.args[0]
    b := left.args[1]
    c := right
    
    if b == 0 || c == 0 {
        return v
    }
    
    if b.op == op_const && c.op == op_const {
        bc_or := ssa_value_new_const_int(v.id + 2000107, b.aux_int | c.aux_int, v.type_id)
        result := ssa_value_new_binary_op(v.id + 2000108, op_or, a, bc_or, v.type_id)
        return result
    }
    
    v
}

func rule_xor_associative_left(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_xor {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if left == 0 || left.op != op_xor {
        return v
    }
    if left.arg_count != 2 {
        return v
    }
    
    a := left.args[0]
    b := left.args[1]
    c := right
    
    if b == 0 || c == 0 {
        return v
    }
    
    if b.op == op_const && c.op == op_const {
        bc_xor := ssa_value_new_const_int(v.id + 2000109, b.aux_int ^ c.aux_int, v.type_id)
        result := ssa_value_new_binary_op(v.id + 2000110, op_xor, a, bc_xor, v.type_id)
        return result
    }
    
    v
}

func rule_shl_zero_shift(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_shl {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if right == 0 || right.op != op_const {
        return v
    }
    if right.aux_int != 0 {
        return v
    }
    
    left
}

func rule_shr_zero_shift(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_shr {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if right == 0 || right.op != op_const {
        return v
    }
    if right.aux_int != 0 {
        return v
    }
    
    left
}

func rule_shl_neg_right(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_shl {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    right := v.args[1]
    
    if right == 0 || right.op != op_const {
        return v
    }
    if right.aux_int >= 0 {
        return v
    }
    
    left := v.args[0]
    shift_amount := ssa_value_new_const_int(v.id + 2000111, -right.aux_int, v.type_id)
    ssa_value_new_binary_op(v.id + 2000112, op_shr, left, shift_amount, v.type_id)
}

func rule_shr_neg_right(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_shr {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    right := v.args[1]
    
    if right == 0 || right.op != op_const {
        return v
    }
    if right.aux_int >= 0 {
        return v
    }
    
    left := v.args[0]
    shift_amount := ssa_value_new_const_int(v.id + 2000113, -right.aux_int, v.type_id)
    ssa_value_new_binary_op(v.id + 2000114, op_shl, left, shift_amount, v.type_id)
}

func rule_not_by_xor_all_ones(v ssa_value*) ssa_value* {
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
    
    all_ones := ssa_value_new_const_int(v.id + 2000115, -1, v.type_id)
    ssa_value_new_binary_op(v.id + 2000116, op_xor, arg, all_ones, v.type_id)
}

func rule_and_distribute_over_or(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_and {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if left == 0 || left.op != op_or {
        return v
    }
    if left.arg_count != 2 {
        return v
    }
    
    a := left.args[0]
    b := left.args[1]
    c := right
    
    if a == 0 || b == 0 || c == 0 {
        return v
    }
    
    ac := ssa_value_new_binary_op(v.id + 2000117, op_and, a, c, v.type_id)
    bc := ssa_value_new_binary_op(v.id + 2000118, op_and, b, c, v.type_id)
    ssa_value_new_binary_op(v.id + 2000119, op_or, ac, bc, v.type_id)
}

func rule_or_distribute_over_and(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_or {
        return v
    }
    if v.arg_count != 2 {
        return v
    }
    
    left := v.args[0]
    right := v.args[1]
    
    if left == 0 || left.op != op_and {
        return v
    }
    if left.arg_count != 2 {
        return v
    }
    
    a := left.args[0]
    b := left.args[1]
    c := right
    
    if a == 0 || b == 0 || c == 0 {
        return v
    }
    
    ac := ssa_value_new_binary_op(v.id + 2000120, op_or, a, c, v.type_id)
    bc := ssa_value_new_binary_op(v.id + 2000121, op_or, b, c, v.type_id)
    ssa_value_new_binary_op(v.id + 2000122, op_and, ac, bc, v.type_id)
}

func rule_de_morgan_and_not(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_not {
        return v
    }
    if v.arg_count != 1 {
        return v
    }
    
    arg := v.args[0]
    
    if arg == 0 || arg.op != op_and {
        return v
    }
    if arg.arg_count != 2 {
        return v
    }
    
    a := arg.args[0]
    b := arg.args[1]
    
    if a == 0 || b == 0 {
        return v
    }
    
    not_a := ssa_value_new_unary_op(v.id + 2000123, op_not, a, v.type_id)
    not_b := ssa_value_new_unary_op(v.id + 2000124, op_not, b, v.type_id)
    ssa_value_new_binary_op(v.id + 2000125, op_or, not_a, not_b, v.type_id)
}

func rule_de_morgan_or_not(v ssa_value*) ssa_value* {
    if v == 0 || v.op != op_not {
        return v
    }
    if v.arg_count != 1 {
        return v
    }
    
    arg := v.args[0]
    
    if arg == 0 || arg.op != op_or {
        return v
    }
    if arg.arg_count != 2 {
        return v
    }
    
    a := arg.args[0]
    b := arg.args[1]
    
    if a == 0 || b == 0 {
        return v
    }
    
    not_a := ssa_value_new_unary_op(v.id + 2000126, op_not, a, v.type_id)
    not_b := ssa_value_new_unary_op(v.id + 2000127, op_not, b, v.type_id)
    ssa_value_new_binary_op(v.id + 2000128, op_and, not_a, not_b, v.type_id)
}

func apply_algebraic_simplifications(v ssa_value*) ssa_value* {
    if v == 0 {
        return v
    }
    
    v = rule_mul_by_power_of_two_is_shift(v)
    v = rule_div_by_power_of_two_is_shift(v)
    v = rule_double_neg_cancel(v)
    v = rule_add_neg_is_sub(v)
    v = rule_sub_neg_is_add(v)
    v = rule_mul_neg_commute(v)
    v = rule_and_or_absorption_1(v)
    v = rule_and_or_absorption_2(v)
    v = rule_or_and_absorption_1(v)
    v = rule_or_and_absorption_2(v)
    v = rule_and_idempotent(v)
    v = rule_or_idempotent(v)
    v = rule_xor_idempotent(v)
    v = rule_add_associative_left(v)
    v = rule_mul_associative_left(v)
    v = rule_and_associative_left(v)
    v = rule_or_associative_left(v)
    v = rule_xor_associative_left(v)
    v = rule_shl_zero_shift(v)
    v = rule_shr_zero_shift(v)
    v = rule_shl_neg_right(v)
    v = rule_shr_neg_right(v)
    v = rule_not_by_xor_all_ones(v)
    
    v
}
