package liveness_analysis

struct liveness_set {
    []int live_in
    []int live_out
    int num_vars
}

struct liveness_analyzer {
    int block_count
    int instr_count
    int var_count
    liveness_set[] block_liveness
    []int[] block_killed
    []int[] block_used
}

struct stack_frame {
    int total_size
    int spill_area_offset
    int callee_saved_offset
    int local_vars_offset
    int arg_area_offset
    []int slot_to_var
    int slot_count
}

const callee_saved_rbx = 0x1
const callee_saved_r12 = 0x2
const callee_saved_r13 = 0x4
const callee_saved_r14 = 0x8
const callee_saved_r15 = 0x10
const callee_saved_rbp = 0x20

func liveness_analyzer_new(int block_count, int var_count) liveness_analyzer* {
    analyzer := liveness_analyzer {
        block_count: block_count,
        var_count: var_count,
        block_liveness: new liveness_set[block_count],
        block_killed: new []int[block_count],
        block_used: new []int[block_count],
    }

    i := 0
    for i < block_count {
        analyzer.block_liveness[i].live_in = new int[var_count]
        analyzer.block_liveness[i].live_out = new int[var_count]
        analyzer.block_liveness[i].num_vars = var_count

        analyzer.block_killed[i] = new int[var_count]
        analyzer.block_used[i] = new int[var_count]

        j := 0
        for j < var_count {
            analyzer.block_liveness[i].live_in[j] = 0
            analyzer.block_liveness[i].live_out[j] = 0
            analyzer.block_killed[i][j] = 0
            analyzer.block_used[i][j] = 0
            j = j + 1
        }

        i = i + 1
    }

    &analyzer
}

func (analyzer* liveness_analyzer) compute_block_gen_kill(block[] blocks, int block_id) int {
    block := blocks[block_id]
    
    i := 0
    for i < len(block.values) {
        v := block.values[i]
        
        j := 0
        for j < len(v.args) {
            arg_id := v.args[j]
            if arg_id >= 0 && arg_id < analyzer.var_count {
                if analyzer.block_killed[block_id][arg_id] == 0 {
                    analyzer.block_used[block_id][arg_id] = 1
                }
            }
            j = j + 1
        }
        
        if v.id >= 0 && v.id < analyzer.var_count {
            analyzer.block_killed[block_id][v.id] = 1
        }
        
        i = i + 1
    }
    
    0
}

func (analyzer* liveness_analyzer) compute_live_ranges_iterative(block[] blocks) int {
    changed := 1
    
    for changed == 1 {
        changed = 0
        
        i := 0
        for i < analyzer.block_count {
            block := blocks[i]
            
            new_live_in := new int[analyzer.var_count]
            new_live_out := new int[analyzer.var_count]
            
            j := 0
            for j < analyzer.var_count {
                new_live_in[j] = analyzer.block_used[i][j]
                new_live_out[j] = 0
                j = j + 1
            }
            
            j = 0
            for j < len(block.values) {
                v := block.values[j]
                if v.id >= 0 && v.id < analyzer.var_count {
                    new_live_in[v.id] = 0
                }
                j = j + 1
            }
            
            succ_idx := 0
            for succ_idx < len(block.succs) {
                succ_id := block.succs[succ_idx]
                
                k := 0
                for k < analyzer.var_count {
                    if analyzer.block_liveness[succ_id].live_in[k] == 1 {
                        new_live_out[k] = 1
                    }
                    k = k + 1
                }
                
                succ_idx = succ_idx + 1
            }
            
            k := 0
            for k < analyzer.var_count {
                if new_live_in[k] != analyzer.block_liveness[i].live_in[k] {
                    changed = 1
                }
                if new_live_out[k] != analyzer.block_liveness[i].live_out[k] {
                    changed = 1
                }
                k = k + 1
            }
            
            analyzer.block_liveness[i].live_in = new_live_in
            analyzer.block_liveness[i].live_out = new_live_out
            
            i = i + 1
        }
    }
    
    0
}

func (analyzer* liveness_analyzer) analyze(block[] blocks) int {
    i := 0
    for i < analyzer.block_count {
        analyzer.compute_block_gen_kill(blocks, i)
        i = i + 1
    }
    
    analyzer.compute_live_ranges_iterative(blocks)
    
    0
}

func (analyzer* liveness_analyzer) is_live_at_point(int var_id, int block_id, int instr_id) int {
    if analyzer.block_liveness[block_id].live_in[var_id] == 1 {
        return 1
    }
    
    if analyzer.block_liveness[block_id].live_out[var_id] == 1 {
        return 1
    }
    
    return 0
}

func stack_frame_new(int num_spills, int num_locals, int num_args) stack_frame* {
    frame := stack_frame {
        total_size: 0,
        spill_area_offset: 0,
        callee_saved_offset: 0,
        local_vars_offset: 0,
        arg_area_offset: 0,
        slot_to_var: new int[256],
        slot_count: 0,
    }

    return_addr_size := 8
    frame.arg_area_offset = 0

    callee_saved_count := count_callee_saved_regs()
    frame.callee_saved_offset = frame.arg_area_offset + num_args * 8

    frame.local_vars_offset = frame.callee_saved_offset + callee_saved_count * 8

    frame.spill_area_offset = frame.local_vars_offset + num_locals * 8

    frame.total_size = frame.spill_area_offset + num_spills * 8

    frame.total_size = align_to_16(frame.total_size)

    &frame
}

func count_callee_saved_regs() int {
    return 6
}

func align_to_16(int size) int {
    remainder := size & 15
    if remainder != 0 {
        size = size + (16 - remainder)
    }
    return size
}

func (frame* stack_frame) get_var_stack_location(int var_id) int {
    i := 0
    for i < frame.slot_count {
        if frame.slot_to_var[i] == var_id {
            return frame.spill_area_offset + i * 8
        }
        i = i + 1
    }
    
    frame.slot_to_var[frame.slot_count] = var_id
    slot_offset := frame.spill_area_offset + frame.slot_count * 8
    frame.slot_count = frame.slot_count + 1
    
    slot_offset
}

func (frame* stack_frame) eliminate_dead_slots() int {
    live_vars := new int[256]
    
    i := 0
    for i < frame.slot_count {
        live_vars[i] = 1
        i = i + 1
    }
    
    i = 0
    for i < frame.slot_count {
        if live_vars[i] == 0 {
            frame.slot_count = frame.slot_count - 1
        }
        i = i + 1
    }
    
    frame.total_size = frame.spill_area_offset + frame.slot_count * 8
    frame.total_size = align_to_16(frame.total_size)
    
    0
}

func (frame* stack_frame) omit_frame_pointer() int {
    if frame.total_size <= 128 {
        return 1
    }
    
    return 0
}

func (frame* stack_frame) compute_cfi_directives() string {
    return ""
}

func (frame* stack_frame) verify_alignment() int {
    if frame.total_size & 15 == 0 {
        return 1
    }
    
    return 0
}
