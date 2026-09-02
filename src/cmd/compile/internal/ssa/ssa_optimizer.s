package internal.ssa

struct ssa_optimizer {
    ssa_rule_engine rule_engine
    int optimization_level
    int iteration_count
    int max_iterations
}

func ssa_optimizer_new(int capacity, int opt_level) ssa_optimizer {
    optimizer := ssa_optimizer {
        rule_engine: ssa_rule_engine_new(capacity),
        optimization_level: opt_level,
        iteration_count: 0,
        max_iterations: 10
    }
    optimizer
}

func (optimizer* ssa_optimizer) register_constant_folding_rules() int {
    engine := optimizer.rule_engine
    
    engine.add_rule("add_const_const", 100)
    engine.add_rule("add_x_zero", 95)
    engine.add_rule("add_zero_x", 95)
    engine.add_rule("sub_const_const", 100)
    engine.add_rule("sub_x_zero", 95)
    engine.add_rule("sub_zero_x", 95)
    engine.add_rule("mul_const_const", 100)
    engine.add_rule("mul_x_zero", 95)
    engine.add_rule("mul_zero_x", 95)
    engine.add_rule("mul_x_one", 95)
    engine.add_rule("mul_one_x", 95)
    engine.add_rule("mul_x_two", 90)
    engine.add_rule("mul_two_x", 90)
    engine.add_rule("div_const_const", 100)
    engine.add_rule("div_zero_x", 95)
    engine.add_rule("div_x_one", 95)
    engine.add_rule("rem_const_const", 100)
    engine.add_rule("rem_zero_x", 95)
    engine.add_rule("rem_x_one", 95)
    engine.add_rule("and_x_zero", 95)
    engine.add_rule("and_zero_x", 95)
    engine.add_rule("and_x_x", 90)
    engine.add_rule("and_x_minus_one", 90)
    engine.add_rule("or_x_zero", 95)
    engine.add_rule("or_zero_x", 95)
    engine.add_rule("or_x_x", 90)
    engine.add_rule("or_x_minus_one", 95)
    engine.add_rule("xor_x_zero", 95)
    engine.add_rule("xor_zero_x", 95)
    engine.add_rule("xor_x_x", 90)
    engine.add_rule("shl_const_const", 100)
    engine.add_rule("shl_x_zero", 95)
    engine.add_rule("shr_const_const", 100)
    engine.add_rule("shr_x_zero", 95)
    engine.add_rule("neg_const", 100)
    engine.add_rule("neg_neg", 90)
    engine.add_rule("not_const", 100)
    engine.add_rule("not_not", 90)
    engine.add_rule("neg_zero", 95)
    engine.add_rule("cmp_const_const", 100)
    engine.add_rule("cmp_x_x", 90)
    engine.add_rule("commute_add", 50)
    engine.add_rule("commute_mul", 50)
    engine.add_rule("commute_and", 50)
    engine.add_rule("commute_or", 50)
    engine.add_rule("commute_xor", 50)
    engine.add_rule("add_mul_dist", 60)
    engine.add_rule("sub_mul_dist", 60)
    engine.add_rule("and_or_dist", 60)
    engine.add_rule("de_morgan_and", 70)
    engine.add_rule("de_morgan_or", 70)
    
    50
}

func (optimizer* ssa_optimizer) register_algebraic_simplification_rules() int {
    engine := optimizer.rule_engine
    
    starting_id := engine.rule_count
    
    engine.add_rule("mul_by_power_of_two_is_shift", 85)
    engine.add_rule("div_by_power_of_two_is_shift", 85)
    engine.add_rule("double_neg_cancel", 80)
    engine.add_rule("add_neg_is_sub", 80)
    engine.add_rule("sub_neg_is_add", 80)
    engine.add_rule("mul_neg_commute", 60)
    engine.add_rule("and_or_absorption_1", 75)
    engine.add_rule("and_or_absorption_2", 75)
    engine.add_rule("or_and_absorption_1", 75)
    engine.add_rule("or_and_absorption_2", 75)
    engine.add_rule("and_idempotent", 80)
    engine.add_rule("or_idempotent", 80)
    engine.add_rule("xor_idempotent", 80)
    engine.add_rule("add_associative_left", 70)
    engine.add_rule("mul_associative_left", 70)
    engine.add_rule("and_associative_left", 70)
    engine.add_rule("or_associative_left", 70)
    engine.add_rule("xor_associative_left", 70)
    engine.add_rule("shl_zero_shift", 95)
    engine.add_rule("shr_zero_shift", 95)
    engine.add_rule("shl_neg_right", 60)
    engine.add_rule("shr_neg_right", 60)
    engine.add_rule("not_by_xor_all_ones", 50)
    engine.add_rule("and_distribute_over_or", 65)
    engine.add_rule("or_distribute_over_and", 65)
    engine.add_rule("de_morgan_and_not", 70)
    engine.add_rule("de_morgan_or_not", 70)
    
    engine.rule_count - starting_id
}

func (optimizer* ssa_optimizer) optimize_value(v ssa_value*) ssa_value* {
    if v == 0 {
        return v
    }
    
    for optimizer.iteration_count < optimizer.max_iterations {
        old_id := v.id
        
        v = optimizer.rule_engine.apply_all(v)
        v = apply_algebraic_simplifications(v)
        
        if v.id == old_id {
            break
        }
        
        optimizer.iteration_count = optimizer.iteration_count + 1
    }
    
    optimizer.iteration_count = 0
    v
}

func (optimizer* ssa_optimizer) optimize_block(ssa_value*[] values) ssa_value*[] {
    optimized := ssa_value*[]()
    
    for i := 0; i < values.len(); i = i + 1 {
        v := values[i]
        if v != 0 {
            v = optimizer.optimize_value(v)
            optimized = append(optimized, v)
        }
    }
    
    optimized
}

func create_default_optimizer() ssa_optimizer {
    optimizer := ssa_optimizer_new(500, 2)
    optimizer.register_constant_folding_rules()
    optimizer.register_algebraic_simplification_rules()
    optimizer
}
