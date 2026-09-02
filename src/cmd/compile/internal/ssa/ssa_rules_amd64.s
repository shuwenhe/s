package internal.ssa

struct amd64_rule {
    int id
    string pattern
    string instruction
    int latency
    int throughput
}

amd64_rule*[] amd64_rules
int amd64_rule_count

func init_amd64_rules() int {
    amd64_rules = new amd64_rule*[500]
    amd64_rule_count = 0
    return 0
}

func rule_lea_pattern(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 100 {
        return v
    }
    
    if v.args[0] == 0 || v.args[1] == 0 {
        return v
    }
    
    if v.args[0].op == 100 && v.args[1].op == 102 {
        ssa_value* inner_add = v.args[0]
        ssa_value* mul = v.args[1]
        
        if inner_add.args[0] == 0 || inner_add.args[1] == 0 {
            return v
        }
        
        if mul.args[1] != 0 && mul.args[1].op == 1 {
            int scale = mul.args[1].aux_int[0]
            
            if scale == 2 || scale == 4 || scale == 8 {
                ssa_value* lea_node = ssa_value_new(v.id + 4000000, 350, v.type_id)
                lea_node.args[0] = inner_add.args[0]
                lea_node.args[1] = inner_add.args[1]
                lea_node.args[2] = mul.args[0]
                
                ssa_value* scale_const = ssa_value_new(v.id + 4000001, 1, v.type_id)
                scale_const.aux_int[0] = scale
                lea_node.args[3] = scale_const
                
                return lea_node
            }
        }
    }
    
    return v
}

func rule_lea_base_offset(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 100 {
        return v
    }
    
    if v.args[0] == 0 || v.args[1] == 0 {
        return v
    }
    
    if v.args[1].op == 1 {
        int offset = v.args[1].aux_int[0]
        
        if offset >= -128 && offset <= 127 {
            ssa_value* lea_node = ssa_value_new(v.id + 4000002, 351, v.type_id)
            lea_node.args[0] = v.args[0]
            
            ssa_value* offset_const = ssa_value_new(v.id + 4000003, 1, v.type_id)
            offset_const.aux_int[0] = offset
            lea_node.args[1] = offset_const
            
            return lea_node
        }
    }
    
    return v
}

func rule_shift_immediates(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 103 {
        return v
    }
    
    if v.args[1] == 0 {
        return v
    }
    
    if v.args[1].op == 1 {
        int shift_amount = v.args[1].aux_int[0]
        
        if shift_amount >= 1 && shift_amount <= 63 {
            ssa_value* shift_imm = ssa_value_new(v.id + 4000004, 360, v.type_id)
            shift_imm.args[0] = v.args[0]
            
            ssa_value* imm = ssa_value_new(v.id + 4000005, 1, v.type_id)
            imm.aux_int[0] = shift_amount
            shift_imm.args[1] = imm
            
            return shift_imm
        }
    }
    
    return v
}

func rule_imul_constants(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 102 {
        return v
    }
    
    if v.args[1] == 0 {
        return v
    }
    
    if v.args[1].op == 1 {
        int const_val = v.args[1].aux_int[0]
        
        if const_val >= -128 && const_val <= 127 {
            ssa_value* imul = ssa_value_new(v.id + 4000006, 370, v.type_id)
            imul.args[0] = v.args[0]
            
            ssa_value* imm = ssa_value_new(v.id + 4000007, 1, v.type_id)
            imm.aux_int[0] = const_val
            imul.args[1] = imm
            
            return imul
        }
    }
    
    return v
}

func rule_mov_zero(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 1 {
        return v
    }
    
    if v.aux_int[0] == 0 {
        ssa_value* xor_zero = ssa_value_new(v.id + 4000008, 371, v.type_id)
        ssa_value* reg = ssa_value_new(v.id + 4000009, 1, v.type_id)
        reg.aux_int[0] = 0
        xor_zero.args[0] = reg
        xor_zero.args[1] = reg
        
        return xor_zero
    }
    
    return v
}

func rule_load_store_elimination(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 200 {
        return v
    }
    
    if v.args[0] == 0 {
        return v
    }
    
    if v.args[0].op == 201 {
        ssa_value* prev_store = v.args[0]
        
        if prev_store.args[1] == v.args[1] {
            return prev_store.args[2]
        }
    }
    
    return v
}

func rule_add_sub_optimization(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 101 {
        return v
    }
    
    if v.args[0] == 0 {
        return v
    }
    
    if v.args[0].op == 100 {
        ssa_value* inner_add = v.args[0]
        
        if inner_add.args[1] != 0 && inner_add.args[1].op == 1 {
            if v.args[1] != 0 && v.args[1].op == 1 {
                int a = inner_add.args[1].aux_int[0]
                int b = v.args[1].aux_int[0]
                int result = a - b
                
                ssa_value* optimized_add = ssa_value_new(v.id + 4000010, 100, v.type_id)
                optimized_add.args[0] = inner_add.args[0]
                
                ssa_value* const_val = ssa_value_new(v.id + 4000011, 1, v.type_id)
                const_val.aux_int[0] = result
                optimized_add.args[1] = const_val
                
                return optimized_add
            }
        }
    }
    
    return v
}

func rule_xor_same_register(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 112 {
        return v
    }
    
    if v.args[0] == 0 || v.args[1] == 0 {
        return v
    }
    
    if v.args[0] == v.args[1] {
        ssa_value* zero = ssa_value_new(v.id + 4000012, 1, v.type_id)
        zero.aux_int[0] = 0
        return zero
    }
    
    return v
}

func rule_cmp_with_zero(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 400 {
        return v
    }
    
    if v.args[1] == 0 {
        return v
    }
    
    if v.args[1].op == 1 && v.args[1].aux_int[0] == 0 {
        ssa_value* test = ssa_value_new(v.id + 4000013, 401, v.type_id)
        test.args[0] = v.args[0]
        
        return test
    }
    
    return v
}

func rule_memory_addressing_modes(ssa_value* v) ssa_value* {
    if v == 0 || v.op != 200 {
        return v
    }
    
    if v.args[0] == 0 || v.args[1] == 0 {
        return v
    }
    
    if v.args[1].op == 100 {
        ssa_value* add_expr = v.args[1]
        
        if add_expr.args[0] != 0 && add_expr.args[1] != 0 {
            if add_expr.args[0].op == 1 && add_expr.args[1].op == 1 {
                int base = add_expr.args[0].aux_int[0]
                int offset = add_expr.args[1].aux_int[0]
                
                if base >= -128 && base <= 127 && offset >= -128 && offset <= 127 {
                    ssa_value* load_indexed = ssa_value_new(v.id + 4000014, 410, v.type_id)
                    load_indexed.args[0] = v.args[0]
                    
                    ssa_value* base_const = ssa_value_new(v.id + 4000015, 1, v.type_id)
                    base_const.aux_int[0] = base
                    load_indexed.args[1] = base_const
                    
                    ssa_value* offset_const = ssa_value_new(v.id + 4000016, 1, v.type_id)
                    offset_const.aux_int[0] = offset
                    load_indexed.args[2] = offset_const
                    
                    return load_indexed
                }
            }
        }
    }
    
    return v
}

func rule_bswap_pattern(ssa_value* v) ssa_value* {
    if v == 0 {
        return v
    }
    
    if v.op == 112 {
        ssa_value* xor1 = v
        
        if xor1.args[0] == 0 || xor1.args[1] == 0 {
            return v
        }
        
        ssa_value* val = xor1.args[0]
        
        if val.op == 103 {
            if val.args[1] != 0 && val.args[1].op == 1 {
                if val.args[1].aux_int[0] == 8 {
                    ssa_value* bswap = ssa_value_new(v.id + 4000017, 420, v.type_id)
                    bswap.args[0] = val.args[0]
                    
                    return bswap
                }
            }
        }
    }
    
    return v
}

func optimize_block_amd64(ssa_block* block) int {
    if block == 0 || block.values == 0 {
        return 0
    }
    
    int i = 0
    int changed = 1
    int iterations = 0
    int max_iterations = 5
    
    for iterations = 0; iterations < max_iterations; iterations = iterations + 1 {
        changed = 0
        
        for i = 0; i < 1000; i = i + 1 {
            if block.values[i] == 0 {
                break
            }
            
            ssa_value* optimized = block.values[i]
            
            optimized = rule_lea_pattern(optimized)
            optimized = rule_lea_base_offset(optimized)
            optimized = rule_shift_immediates(optimized)
            optimized = rule_imul_constants(optimized)
            optimized = rule_mov_zero(optimized)
            optimized = rule_load_store_elimination(optimized)
            optimized = rule_add_sub_optimization(optimized)
            optimized = rule_xor_same_register(optimized)
            optimized = rule_cmp_with_zero(optimized)
            optimized = rule_memory_addressing_modes(optimized)
            optimized = rule_bswap_pattern(optimized)
            
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

func optimize_function_amd64(ssa_function* func) int {
    if func == 0 {
        return -1
    }
    
    int i = 0
    int total_passes = 0
    
    for i = 0; i < func.block_count; i = i + 1 {
        int passes = optimize_block_amd64(func.blocks[i])
        total_passes = total_passes + passes
    }
    
    return total_passes
}
