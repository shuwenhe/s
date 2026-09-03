package internal.ssa

struct liveness_set {
    int*[] gen
    int*[] kill
    int*[] in_set
    int*[] out_set
    int block_count
    int value_count
}

struct stack_slot {
    int var_id
    int start_pos
    int end_pos
    int size
    int offset
    int is_live_at[1000]
}

struct stack_frame {
    stack_slot*[] slots
    int slot_count
    int total_size
    int alignment
}

func liveness_set_new(int block_count, int value_count) liveness_set* {
    liveness_set* lv = new liveness_set
    
    lv.gen = int*[block_count]
    lv.kill = int*[block_count]
    lv.in_set = int*[block_count]
    lv.out_set = int*[block_count]
    
    int i = 0
    for i = 0; i < block_count; i = i + 1 {
        lv.gen[i] = int[value_count]
        lv.kill[i] = int[value_count]
        lv.in_set[i] = int[value_count]
        lv.out_set[i] = int[value_count]
        
        int j = 0
        for j = 0; j < value_count; j = j + 1 {
            lv.gen[i][j] = 0
            lv.kill[i][j] = 0
            lv.in_set[i][j] = 0
            lv.out_set[i][j] = 0
        }
    }
    
    lv.block_count = block_count
    lv.value_count = value_count
    
    return lv
}

func analyze_block_liveness(ssa_block* block, int block_id, liveness_set* lv) int {
    if block == 0 || block.values == 0 || lv == 0 {
        return 0
    }
    
    int i = 0
    int live_out = 0
    
    for i = 999; i >= 0; i = i - 1 {
        if block.values[i] == 0 {
            continue
        }
        
        ssa_value* v = block.values[i]
        
        if v.op == 200 {
            if v.args[1] != 0 {
                int addr_id = v.args[1].id % 1000
                lv.gen[block_id][addr_id] = 1
            }
        } else if v.op == 201 {
            if v.args[1] != 0 {
                int addr_id = v.args[1].id % 1000
                lv.gen[block_id][addr_id] = 1
            }
            if v.args[2] != 0 {
                int val_id = v.args[2].id % 1000
                lv.gen[block_id][val_id] = 1
            }
        } else if v.op >= 100 && v.op <= 112 {
            if v.args[0] != 0 {
                int arg0_id = v.args[0].id % 1000
                lv.gen[block_id][arg0_id] = 1
            }
            if v.args[1] != 0 {
                int arg1_id = v.args[1].id % 1000
                lv.gen[block_id][arg1_id] = 1
            }
        }
        
        int var_id = v.id % 1000
        lv.kill[block_id][var_id] = 1
    }
    
    return 1
}

func compute_liveness(ssa_function* func, liveness_set* lv) int {
    if func == 0 || func.blocks == 0 || lv == 0 {
        return 0
    }
    
    int i = 0
    for i = 0; i < func.block_count; i = i + 1 {
        analyze_block_liveness(func.blocks[i], i, lv)
    }
    
    int changed = 1
    int iterations = 0
    int max_iterations = 100
    
    for iterations = 0; iterations < max_iterations && changed == 1; iterations = iterations + 1 {
        changed = 0
        
        for i = 0; i < func.block_count; i = i + 1 {
            int j = 0
            
            for j = 0; j < lv.value_count; j = j + 1 {
                int old_in = lv.in_set[i][j]
                
                lv.in_set[i][j] = lv.gen[i][j]
                
                int k = 0
                for k = 0; k < func.block_count; k = k + 1 {
                    if func.blocks[i].succs != 0 && func.blocks[i].succ_count > 0 {
                        int succ_found = 0
                        int s = 0
                        for s = 0; s < func.blocks[i].succ_count; s = s + 1 {
                            if func.blocks[i].succs[s] != 0 && func.blocks[i].succs[s].id == k {
                                succ_found = 1
                                break
                            }
                        }
                        
                        if succ_found == 1 {
                            int old_out = lv.out_set[i][j]
                            lv.out_set[i][j] = lv.out_set[i][j] | lv.in_set[k][j]
                            
                            if lv.out_set[i][j] != old_out {
                                changed = 1
                            }
                        }
                    }
                }
                
                if (lv.in_set[i][j] | (lv.out_set[i][j] & (~lv.kill[i][j]))) != old_in {
                    changed = 1
                    lv.in_set[i][j] = lv.in_set[i][j] | (lv.out_set[i][j] & (~lv.kill[i][j]))
                }
            }
        }
    }
    
    return iterations
}

func stack_frame_new(int value_count) stack_frame* {
    stack_frame* frame = new stack_frame
    frame.slots = stack_slot*[value_count]
    frame.slot_count = 0
    frame.total_size = 0
    frame.alignment = 8
    
    return frame
}

func can_reuse_stack_slot(stack_slot* slot, int start_pos, int end_pos, liveness_set* lv, int block_id) int {
    if slot == 0 {
        return 0
    }
    
    int i = 0
    
    for i = start_pos; i < end_pos; i = i + 1 {
        if i >= 1000 {
            break
        }
        
        if slot.is_live_at[i] == 1 {
            return 0
        }
    }
    
    return 1
}

func optimize_stack_frame(ssa_function* func, liveness_set* lv) stack_frame* {
    if func == 0 || lv == 0 {
        return 0
    }
    
    stack_frame* frame = stack_frame_new(func.value_count)
    
    int i = 0
    for i = 0; i < func.block_count; i = i + 1 {
        ssa_block* block = func.blocks[i]
        
        if block == 0 || block.values == 0 {
            continue
        }
        
        int j = 0
        for j = 0; j < 1000; j = j + 1 {
            if block.values[j] == 0 {
                break
            }
            
            ssa_value* v = block.values[j]
            
            if v.op >= 100 && v.op <= 201 {
                int var_id = v.id % 100
                
                stack_slot* best_slot = 0
                int k = 0
                
                for k = 0; k < frame.slot_count; k = k + 1 {
                    if can_reuse_stack_slot(frame.slots[k], j, j + 10, lv, i) == 1 {
                        best_slot = frame.slots[k]
                        break
                    }
                }
                
                if best_slot == 0 {
                    stack_slot* new_slot = new stack_slot
                    new_slot.var_id = var_id
                    new_slot.start_pos = j
                    new_slot.end_pos = j + 10
                    new_slot.size = 8
                    new_slot.offset = frame.total_size
                    
                    int m = 0
                    for m = 0; m < 1000; m = m + 1 {
                        new_slot.is_live_at[m] = 0
                    }
                    
                    frame.slots[frame.slot_count] = new_slot
                    frame.slot_count = frame.slot_count + 1
                    frame.total_size = frame.total_size + 8
                } else {
                    best_slot.end_pos = j + 10
                }
            }
        }
    }
    
    frame.total_size = (frame.total_size + (frame.alignment - 1)) / frame.alignment * frame.alignment
    
    return frame
}

func compute_gc_pointer_map(ssa_function* func, liveness_set* lv) int*[] {
    if func == 0 || lv == 0 {
        return 0
    }
    
    int*[] pointer_maps = int*[func.block_count]
    
    int i = 0
    for i = 0; i < func.block_count; i = i + 1 {
        pointer_maps[i] = int[1000]
        
        int j = 0
        for j = 0; j < lv.value_count; j = j + 1 {
            if lv.out_set[i][j] == 1 {
                if j >= 100 && j < 200 {
                    pointer_maps[i][j] = 1
                }
            }
        }
    }
    
    return pointer_maps
}

func liveness_optimize_all(ssa_function* func) int {
    if func == 0 {
        return -1
    }
    
    liveness_set* lv = liveness_set_new(func.block_count, func.value_count)
    
    int iterations = compute_liveness(func, lv)
    
    stack_frame* frame = optimize_stack_frame(func, lv)
    
    if frame != 0 {
        return frame.total_size
    }
    
    return 0
}
