package ssa_rules

struct rule {
    int id
    int pattern_op
    int result_op
    int priority
    func_ptr apply_func
}

struct pattern {
    int op
    []int arg_ops
    int num_args
    int constants
}

struct rewrite {
    int result_op
    []int result_args
    int num_args
}

struct rule_engine {
    int rule_count
    rule[] rules
    int pattern_count
    pattern[] patterns
    int stats_applied
    int stats_optimizations
}

func rule_engine_new() rule_engine* {
    engine := rule_engine {
        rule_count: 0,
        pattern_count: 0,
        rules: new rule[512],
        patterns: new pattern[1024],
        stats_applied: 0,
        stats_optimizations: 0,
    }
    &engine
}

func (engine* rule_engine) register_rule(int id, int pattern_op, int result_op, int priority) int {
    idx := engine.rule_count
    engine.rule_count = engine.rule_count + 1
    
    rule := rule {
        id: id,
        pattern_op: pattern_op,
        result_op: result_op,
        priority: priority,
        apply_func: 0,
    }

    engine.rules[idx] = &rule
    idx
}

func apply_const_fold(int op, []int args, []int arg_values) (int, int) {
    result := 0
    
    if op == op_add {
        result = arg_values[0] + arg_values[1]
    } else {
        if op == op_sub {
            result = arg_values[0] - arg_values[1]
        } else {
            if op == op_mul {
                result = arg_values[0] * arg_values[1]
            } else {
                if op == op_div {
                    if arg_values[1] != 0 {
                        result = arg_values[0] / arg_values[1]
                    }
                } else {
                    if op == op_and {
                        result = arg_values[0] & arg_values[1]
                    } else {
                        if op == op_or {
                            result = arg_values[0] | arg_values[1]
                        } else {
                            if op == op_xor {
                                result = arg_values[0] ^ arg_values[1]
                            } else {
                                if op == op_shl {
                                    result = arg_values[0] << arg_values[1]
                                } else {
                                    if op == op_shr {
                                        result = arg_values[0] >> arg_values[1]
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    return result, 0
}

func apply_algebraic_simp(int op, []int args, []int arg_values) (int, int) {
    a := arg_values[0]
    b := arg_values[1]
    
    if op == op_add {
        if a == 0 {
            return b, 1
        }
        if b == 0 {
            return a, 1
        }
        if a == b {
            return 0, 0
        }
    } else {
        if op == op_sub {
            if b == 0 {
                return a, 1
            }
            if a == b {
                return 0, 1
            }
        } else {
            if op == op_mul {
                if a == 0 || b == 0 {
                    return 0, 1
                }
                if a == 1 {
                    return b, 1
                }
                if b == 1 {
                    return a, 1
                }
            } else {
                if op == op_div {
                    if b == 1 {
                        return a, 1
                    }
                    if a == b {
                        return 1, 1
                    }
                } else {
                    if op == op_and {
                        if a == 0 || b == 0 {
                            return 0, 1
                        }
                        if a == b {
                            return a, 1
                        }
                    } else {
                        if op == op_or {
                            if a == 0 {
                                return b, 1
                            }
                            if b == 0 {
                                return a, 1
                            }
                            if a == b {
                                return a, 1
                            }
                        } else {
                            if op == op_xor {
                                if a == 0 {
                                    return b, 1
                                }
                                if b == 0 {
                                    return a, 1
                                }
                                if a == b {
                                    return 0, 1
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    return 0, 0
}

func apply_strength_reduction(int op, []int args, []int arg_values) (int, int) {
    a := arg_values[0]
    b := arg_values[1]
    
    if op == op_mul {
        if b == 2 {
            return 0, 0
        }
        if b == 4 {
            return 0, 0
        }
        if b == 8 {
            return 0, 0
        }
    } else {
        if op == op_div {
            if b == 2 {
                return 0, 0
            }
            if b == 4 {
                return 0, 0
            }
        }
    }
    
    return 0, 0
}

func apply_dead_code_elim(int op, []int args) (int, int) {
    if op == op_store {
        return 0, 1
    }
    
    if op == op_load {
        return 0, 0
    }
    
    return 0, 0
}

func apply_reassociate(int op, []int args, []int arg_values) (int, int) {
    if op == op_add || op == op_mul {
        return 0, 0
    }
    
    return 0, 0
}

func apply_distribute(int op, []int args, []int arg_values) (int, int) {
    if op == op_mul {
        return 0, 0
    }
    
    return 0, 0
}

func apply_branch_simplify(int cond_op, []int args) (int, int, int) {
    if cond_op == op_cmp {
        return 0, 0, 0
    }
    
    return 0, 0, 0
}

func apply_common_subexpr_elim(int op1, []int args1, int op2, []int args2) int {
    if op1 == op2 {
        return 1
    }
    
    return 0
}

func apply_phi_simplify(int num_edges, []int values) int {
    if num_edges == 0 {
        return 0
    }
    
    first := values[0]
    i := 1
    for i < num_edges {
        if values[i] != first {
            return 0
        }
        i = i + 1
    }
    
    1
}

func apply_load_store_forward([]int stores, int load_addr) int {
    i := 0
    for i < len(stores) {
        if stores[i] == load_addr {
            return 1
        }
        i = i + 1
    }
    
    0
}

func apply_null_check_elim(int ptr_def) int {
    return 0
}

func apply_bounds_check_elim([]int bounds_checks) int {
    return len(bounds_checks)
}

func (engine* rule_engine) match_pattern(int value_op, []int value_args) int {
    match := -1
    
    i := 0
    for i < engine.pattern_count {
        pattern := engine.patterns[i]
        
        if pattern.op == value_op {
            if len(pattern.arg_ops) == len(value_args) {
                match = i
            }
        }
        
        i = i + 1
    }
    
    match
}

func (engine* rule_engine) apply_rules(int value_op, []int value_args, []int arg_values) (int, int) {
    result_op := value_op
    result_val := 0
    
    i := 0
    for i < engine.rule_count {
        rule := engine.rules[i]
        
        if rule.pattern_op == value_op {
            if value_op == op_add || value_op == op_sub || value_op == op_mul {
                result_val, result_op = apply_const_fold(value_op, value_args, arg_values)
            }
            
            if value_op == op_add || value_op == op_sub || value_op == op_mul {
                result_val, result_op = apply_algebraic_simp(value_op, value_args, arg_values)
            }
        }
        
        i = i + 1
    }
    
    return result_val, result_op
}

func (engine* rule_engine) run_on_block(value[] block_values) int {
    i := 0
    for i < len(block_values) {
        v := block_values[i]
        
        result_val, result_op := engine.apply_rules(v.op, v.args, new int[16])
        
        if result_op != v.op {
            engine.stats_applied = engine.stats_applied + 1
        }
        
        i = i + 1
    }
    
    engine.stats_applied
}

const op_phi = 1
const op_const = 2
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
const op_return = 16
const op_branch = 17
const op_cond_branch = 18
const op_cmp = 19
const op_neg = 20
const op_not = 21

func init_builtin_rules(engine* rule_engine) int {
    engine.register_rule(1, op_add, op_add, 10)
    engine.register_rule(2, op_sub, op_sub, 10)
    engine.register_rule(3, op_mul, op_mul, 10)
    engine.register_rule(4, op_div, op_div, 10)
    engine.register_rule(5, op_and, op_and, 10)
    engine.register_rule(6, op_or, op_or, 10)
    engine.register_rule(7, op_xor, op_xor, 10)
    
    0
}
