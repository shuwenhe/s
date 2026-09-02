package internal.ssa

func test_const_fold_add() int {
    two := ssa_value_new_const_int(1, 2, 0)
    three := ssa_value_new_const_int(2, 3, 0)
    add := ssa_value_new_binary_op(3, op_add, two, three, 0)
    
    result := rule_add_const_const(add)
    
    if result == 0 {
        return -1
    }
    if result.op != op_const {
        return -2
    }
    if result.aux_int != 5 {
        return -3
    }
    
    0
}

func test_add_x_zero() int {
    x := ssa_value_new_const_int(1, 42, 0)
    zero := ssa_value_new_const_int(2, 0, 0)
    add := ssa_value_new_binary_op(3, op_add, x, zero, 0)
    
    result := rule_add_x_zero(add)
    
    if result == 0 {
        return -1
    }
    if result.id != x.id {
        return -2
    }
    
    0
}

func test_mul_x_zero() int {
    x := ssa_value_new_const_int(1, 42, 0)
    zero := ssa_value_new_const_int(2, 0, 0)
    mul := ssa_value_new_binary_op(3, op_mul, x, zero, 0)
    
    result := rule_mul_x_zero(mul)
    
    if result == 0 {
        return -1
    }
    if result.op != op_const {
        return -2
    }
    if result.aux_int != 0 {
        return -3
    }
    
    0
}

func test_mul_x_one() int {
    x := ssa_value_new_const_int(1, 42, 0)
    one := ssa_value_new_const_int(2, 1, 0)
    mul := ssa_value_new_binary_op(3, op_mul, x, one, 0)
    
    result := rule_mul_x_one(mul)
    
    if result == 0 {
        return -1
    }
    if result.id != x.id {
        return -2
    }
    
    0
}

func test_mul_by_power_of_two() int {
    x := ssa_value_new_const_int(1, 42, 0)
    four := ssa_value_new_const_int(2, 4, 0)
    mul := ssa_value_new_binary_op(3, op_mul, x, four, 0)
    
    result := rule_mul_by_power_of_two_is_shift(mul)
    
    if result == 0 {
        return -1
    }
    if result.op != op_shl {
        return -2
    }
    
    0
}

func test_div_by_power_of_two() int {
    x := ssa_value_new_const_int(1, 42, 0)
    four := ssa_value_new_const_int(2, 4, 0)
    div := ssa_value_new_binary_op(3, op_div, x, four, 0)
    
    result := rule_div_by_power_of_two_is_shift(div)
    
    if result == 0 {
        return -1
    }
    if result.op != op_shr {
        return -2
    }
    
    0
}

func test_neg_neg() int {
    x := ssa_value_new_const_int(1, 42, 0)
    neg1 := ssa_value_new_unary_op(2, op_neg, x, 0)
    neg2 := ssa_value_new_unary_op(3, op_neg, neg1, 0)
    
    result := rule_double_neg_cancel(neg2)
    
    if result == 0 {
        return -1
    }
    if result.id != x.id {
        return -2
    }
    
    0
}

func test_and_x_x() int {
    x := ssa_value_new_const_int(1, 42, 0)
    and := ssa_value_new_binary_op(2, op_and, x, x, 0)
    
    result := rule_and_x_x(and)
    
    if result == 0 {
        return -1
    }
    if result.id != x.id {
        return -2
    }
    
    0
}

func test_or_x_x() int {
    x := ssa_value_new_const_int(1, 42, 0)
    or := ssa_value_new_binary_op(2, op_or, x, x, 0)
    
    result := rule_or_x_x(or)
    
    if result == 0 {
        return -1
    }
    if result.id != x.id {
        return -2
    }
    
    0
}

func test_xor_x_x() int {
    x := ssa_value_new_const_int(1, 42, 0)
    xor := ssa_value_new_binary_op(2, op_xor, x, x, 0)
    
    result := rule_xor_x_x(xor)
    
    if result == 0 {
        return -1
    }
    if result.op != op_const {
        return -2
    }
    if result.aux_int != 0 {
        return -3
    }
    
    0
}

func test_cmp_const_const() int {
    five := ssa_value_new_const_int(1, 5, 0)
    three := ssa_value_new_const_int(2, 3, 0)
    cmp := ssa_value_new_binary_op(3, op_lt, five, three, 0)
    
    result := rule_cmp_const_const(cmp)
    
    if result == 0 {
        return -1
    }
    if result.op != op_const {
        return -2
    }
    if result.aux_int != 0 {
        return -3
    }
    
    0
}

func test_cmp_x_x() int {
    x := ssa_value_new_const_int(1, 42, 0)
    cmp := ssa_value_new_binary_op(2, op_eq, x, x, 0)
    
    result := rule_cmp_x_x(cmp)
    
    if result == 0 {
        return -1
    }
    if result.op != op_const {
        return -2
    }
    if result.aux_int != 1 {
        return -3
    }
    
    0
}

func run_ssa_tests() int {
    tests := [](int) {
        test_const_fold_add,
        test_add_x_zero,
        test_mul_x_zero,
        test_mul_x_one,
        test_mul_by_power_of_two,
        test_div_by_power_of_two,
        test_neg_neg,
        test_and_x_x,
        test_or_x_x,
        test_xor_x_x,
        test_cmp_const_const,
        test_cmp_x_x
    }
    
    passed := 0
    failed := 0
    
    for i := 0; i < tests.len(); i = i + 1 {
        test := tests[i]
        if test() == 0 {
            passed = passed + 1
        } else {
            failed = failed + 1
        }
    }
    
    if failed > 0 {
        return -failed
    }
    
    passed
}
