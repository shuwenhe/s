package internal.ssa

struct ssa_value {
    int id
    int op
    string op_name
    int type_id
    
    ssa_value*[] args
    int* aux_int
    string aux_string
    
    int line
    int column
}

struct ssa_block {
    int id
    string name
    
    ssa_value*[] values
    
    ssa_block*[] preds
    ssa_block*[] succs
    
    int pred_count
    int succ_count
}

struct ssa_function {
    int id
    string name
    
    ssa_block*[] blocks
    ssa_block* entry_block
    
    int block_count
    int value_count
    int max_id
}

struct rule_match {
    int pattern_id
    ssa_value* node
    ssa_value*[] captures
    int capture_count
    int cost
}

struct rule_result {
    ssa_value*[] replacements
    int replace_count
    int improvement
}

struct ssa_rule {
    int id
    string name
    string pattern
    int priority
    int enabled
}

ssa_function* current_func
ssa_rule*[] all_rules
int rule_count
int max_rules

func init_ssa() int {
    all_rules = new ssa_rule[10000]
    rule_count = 0
    max_rules = 10000
    return 0
}

func register_rule(string name, string pattern, int priority) int {
    if rule_count >= max_rules {
        return -1
    }
    
    ssa_rule* rule = &all_rules[rule_count]
    rule.id = rule_count
    rule.name = name
    rule.pattern = pattern
    rule.priority = priority
    rule.enabled = 1
    
    rule_count = rule_count + 1
    return rule.id
}

func ssa_value_new(int id, int op, int type_id) ssa_value* {
    ssa_value* v = new ssa_value
    v.id = id
    v.op = op
    v.type_id = type_id
    v.args = new ssa_value*[16]
    v.aux_int = new int[4]
    return v
}

func ssa_block_new(int id, string name) ssa_block* {
    ssa_block* b = new ssa_block
    b.id = id
    b.name = name
    b.values = new ssa_value*[1000]
    b.preds = new ssa_block*[10]
    b.succs = new ssa_block*[10]
    b.pred_count = 0
    b.succ_count = 0
    return b
}

func ssa_function_new(int id, string name) ssa_function* {
    ssa_function* f = new ssa_function
    f.id = id
    f.name = name
    f.blocks = new ssa_block*[100]
    f.block_count = 0
    f.value_count = 0
    f.max_id = 0
    return f
}

func match_pattern(ssa_value* node, string pattern) int {
    if node == 0 {
        return 0
    }
    
    return 1
}

func apply_constant_folding(ssa_value* v) ssa_value* {
    if v == 0 {
        return 0
    }
    
    if v.op == 1 {
        return v
    }
    
    if v.op == 100 {
        if v.args[0] != 0 && v.args[1] != 0 {
            if v.args[0].op == 1 && v.args[1].op == 1 {
                int a = v.args[0].aux_int[0]
                int b = v.args[1].aux_int[0]
                int result = a + b
                
                ssa_value* const_val = ssa_value_new(v.id + 1000000, 1, v.type_id)
                const_val.aux_int[0] = result
                return const_val
            }
        }
    }
    
    if v.op == 101 {
        if v.args[0] != 0 && v.args[1] != 0 {
            if v.args[0].op == 1 && v.args[1].op == 1 {
                int a = v.args[0].aux_int[0]
                int b = v.args[1].aux_int[0]
                int result = a - b
                
                ssa_value* const_val = ssa_value_new(v.id + 1000001, 1, v.type_id)
                const_val.aux_int[0] = result
                return const_val
            }
        }
    }
    
    if v.op == 102 {
        if v.args[0] != 0 && v.args[1] != 0 {
            if v.args[0].op == 1 && v.args[1].op == 1 {
                int a = v.args[0].aux_int[0]
                int b = v.args[1].aux_int[0]
                int result = a * b
                
                ssa_value* const_val = ssa_value_new(v.id + 1000002, 1, v.type_id)
                const_val.aux_int[0] = result
                return const_val
            }
        }
    }
    
    return v
}

func apply_algebraic_simplification(ssa_value* v) ssa_value* {
    if v == 0 {
        return 0
    }
    
    if v.op == 100 {
        if v.args[1] != 0 && v.args[1].op == 1 && v.args[1].aux_int[0] == 0 {
            return v.args[0]
        }
    }
    
    if v.op == 101 {
        if v.args[1] != 0 && v.args[1].op == 1 && v.args[1].aux_int[0] == 0 {
            return v.args[0]
        }
    }
    
    if v.op == 102 {
        if v.args[1] != 0 && v.args[1].op == 1 && v.args[1].aux_int[0] == 0 {
            ssa_value* zero = ssa_value_new(v.id + 2000000, 1, v.type_id)
            zero.aux_int[0] = 0
            return zero
        }
        
        if v.args[1] != 0 && v.args[1].op == 1 && v.args[1].aux_int[0] == 1 {
            return v.args[0]
        }
    }
    
    if v.op == 103 {
        if v.args[1] != 0 && v.args[1].op == 1 {
            int shift = v.args[1].aux_int[0]
            if shift == 0 {
                return v.args[0]
            }
            
            if shift == 1 {
                if v.args[0].op == 102 {
                    ssa_value* new_mul = ssa_value_new(v.id + 2000001, 102, v.type_id)
                    new_mul.args[0] = v.args[0].args[0]
                    
                    ssa_value* two = ssa_value_new(v.id + 2000002, 1, v.type_id)
                    two.aux_int[0] = 2
                    new_mul.args[1] = two
                    
                    return new_mul
                }
            }
        }
    }
    
    return v
}

func apply_gvn_elimination(ssa_block* block) int {
    if block == 0 || block.values == 0 {
        return 0
    }
    
    int i = 0
    int j = 0
    
    for i = 0; i < 1000; i = i + 1 {
        if block.values[i] == 0 {
            break
        }
        
        j = i + 1
        for j = i + 1; j < 1000; j = j + 1 {
            if block.values[j] == 0 {
                break
            }
            
            if block.values[i].op == block.values[j].op {
                if block.values[i].op >= 100 && block.values[i].op <= 110 {
                    if block.values[i].args[0] == block.values[j].args[0] &&
                       block.values[i].args[1] == block.values[j].args[1] {
                        block.values[j] = block.values[i]
                    }
                }
            }
        }
    }
    
    return 0
}

func eliminate_dead_code(ssa_block* block) int {
    if block == 0 || block.values == 0 {
        return 0
    }
    
    int i = 0
    int used_count = 0
    
    for i = 0; i < 1000; i = i + 1 {
        if block.values[i] == 0 {
            break
        }
        
        int is_used = 0
        int j = 0
        
        for j = 0; j < 1000; j = j + 1 {
            if block.values[j] == 0 {
                break
            }
            
            if i == j {
                continue
            }
            
            int k = 0
            for k = 0; k < 16; k = k + 1 {
                if block.values[j].args[k] == block.values[i] {
                    is_used = 1
                }
            }
        }
        
        if is_used == 1 || block.values[i].op == 200 {
            block.values[used_count] = block.values[i]
            used_count = used_count + 1
        }
    }
    
    block.values[used_count] = 0
    return 0
}

func propagate_constants(ssa_block* block) int {
    if block == 0 || block.values == 0 {
        return 0
    }
    
    int changed = 1
    
    for changed == 1; changed == 1 {
        changed = 0
        int i = 0
        
        for i = 0; i < 1000; i = i + 1 {
            if block.values[i] == 0 {
                break
            }
            
            if block.values[i].op == 1 {
                continue
            }
            
            int arg_is_const = 1
            if block.values[i].args[0] == 0 || block.values[i].args[0].op != 1 {
                arg_is_const = 0
            }
            if block.values[i].args[1] == 0 || block.values[i].args[1].op != 1 {
                arg_is_const = 0
            }
            
            if arg_is_const == 1 {
                int a = block.values[i].args[0].aux_int[0]
                int b = block.values[i].args[1].aux_int[0]
                int result = 0
                
                if block.values[i].op == 100 {
                    result = a + b
                } else if block.values[i].op == 101 {
                    result = a - b
                } else if block.values[i].op == 102 {
                    result = a * b
                }
                
                block.values[i].op = 1
                block.values[i].aux_int[0] = result
                changed = 1
            }
        }
    }
    
    return 0
}

func optimize_block(ssa_block* block) int {
    if block == 0 {
        return -1
    }
    
    eliminate_dead_code(block)
    apply_gvn_elimination(block)
    propagate_constants(block)
    
    int i = 0
    for i = 0; i < 1000; i = i + 1 {
        if block.values[i] == 0 {
            break
        }
        
        ssa_value* folded = apply_constant_folding(block.values[i])
        if folded != block.values[i] {
            block.values[i] = folded
        }
        
        ssa_value* simplified = apply_algebraic_simplification(block.values[i])
        if simplified != block.values[i] {
            block.values[i] = simplified
        }
    }
    
    return 0
}

func optimize_function(ssa_function* func) int {
    if func == 0 {
        return -1
    }
    
    int i = 0
    for i = 0; i < func.block_count; i = i + 1 {
        optimize_block(func.blocks[i])
    }
    
    return 0
}

func ssa_optimize_all(ssa_function* func) int {
    if func == 0 {
        return -1
    }
    
    current_func = func
    
    int pass = 0
    int max_passes = 10
    
    for pass = 0; pass < max_passes; pass = pass + 1 {
        optimize_function(func)
    }
    
    return 0
}
