package compile.internal.ir.liveness_complete

struct live_range {
    i32 start_instr
    i32 end_instr
    string reason
}

struct liveness_info {
    i32 value_id
    bool[][] live_in
    bool[][] live_out
    live_range[] ranges
}

struct liveness_analyzer {
    liveness_info[] infos
    i32 num_values
    i32 num_blocks
    i32[][] gen_set
    i32[][] kill_set
}

func new_liveness_analyzer(num_values i32, num_blocks i32) liveness_analyzer* {
    la := new(liveness_analyzer)
    la.infos = make(liveness_info[], num_values)
    la.num_values = num_values
    la.num_blocks = num_blocks
    la.gen_set = make(i32[][], num_blocks)
    la.kill_set = make(i32[][], num_blocks)
    
    for i := i32(0); i < num_values; i += 1 {
        la.infos[i].value_id = i
        la.infos[i].live_in = make(bool[][], num_blocks)
        la.infos[i].live_out = make(bool[][], num_blocks)
        la.infos[i].ranges = new live_range[]()
        
        for j := i32(0); j < num_blocks; j += 1 {
            la.infos[i].live_in[j] = make(bool[], num_values)
            la.infos[i].live_out[j] = make(bool[], num_values)
        }
    }
    
    for j := i32(0); j < num_blocks; j += 1 {
        la.gen_set[j] = new i32[]()
        la.kill_set[j] = new i32[]()
    }
    
    la
}

func (la liveness_analyzer*) mark_use(block_id i32, value_id i32) {
    if block_id >= 0 && block_id < la.num_blocks && value_id >= 0 && value_id < la.num_values {
        found := false
        for v in la.gen_set[block_id] {
            if v == value_id {
                found = true
                break
            }
        }
        if !found {
            la.gen_set[block_id] = append(la.gen_set[block_id], value_id)
        }
    }
}

func (la liveness_analyzer*) mark_def(block_id i32, value_id i32) {
    if block_id >= 0 && block_id < la.num_blocks && value_id >= 0 && value_id < la.num_values {
        found := false
        for v in la.kill_set[block_id] {
            if v == value_id {
                found = true
                break
            }
        }
        if !found {
            la.kill_set[block_id] = append(la.kill_set[block_id], value_id)
        }
    }
}

func (la liveness_analyzer*) compute_liveness(succs i32[][]) {
    changed := true
    for changed {
        changed = false
        
        for b := i32(0); b < la.num_blocks; b += 1 {
            succ_list := succs[b]
            
            new_live_out := make(bool[], la.num_values)
            for s in succ_list {
                if s >= 0 && s < la.num_blocks {
                    for v := i32(0); v < la.num_values; v += 1 {
                        if la.infos[v].live_in[s][b] {
                            new_live_out[v] = true
                        }
                    }
                }
            }
            
            for v := i32(0); v < la.num_values; v += 1 {
                old_live_out := la.infos[v].live_out[b][0] != 0
                for i := i32(1); i < la.num_values; i += 1 {
                    old_live_out = old_live_out || (la.infos[v].live_out[b][i] != 0)
                }
                
                if new_live_out[v] != old_live_out {
                    changed = true
                }
                
                for i := i32(0); i < la.num_values; i += 1 {
                    if new_live_out[i] {
                        la.infos[v].live_out[b][i] = true
                    }
                }
            }
        }
        
        for b := i32(0); b < la.num_blocks; b += 1 {
            for v := i32(0); v < la.num_values; v += 1 {
                is_used := false
                for u in la.gen_set[b] {
                    if u == v {
                        is_used = true
                        break
                    }
                }
                
                is_defined := false
                for d in la.kill_set[b] {
                    if d == v {
                        is_defined = true
                        break
                    }
                }
                
                if is_used {
                    la.infos[v].live_in[b][v] = true
                } else {
                    for i := i32(0); i < la.num_values; i += 1 {
                        if la.infos[v].live_out[b][i] && !is_defined {
                            la.infos[v].live_in[b][i] = true
                        }
                    }
                }
            }
        }
    }
}

func (la liveness_analyzer*) is_live_at_point(value_id i32, block_id i32, instr_index i32) bool {
    if value_id >= 0 && value_id < la.num_values && block_id >= 0 && block_id < la.num_blocks {
        is_used := false
        for u in la.gen_set[block_id] {
            if u == value_id {
                is_used = true
                break
            }
        }
        
        if is_used {
            return true
        }
        
        return la.infos[value_id].live_out[block_id][0] != 0
    }
    false
}

func (la liveness_analyzer*) get_live_values(block_id i32) i32[] {
    i32[] result
    if block_id >= 0 && block_id < la.num_blocks {
        for v := i32(0); v < la.num_values; v += 1 {
            is_live := false
            for i := i32(0); i < la.num_values; i += 1 {
                if la.infos[v].live_in[block_id][i] != 0 || la.infos[v].live_out[block_id][i] != 0 {
                    is_live = true
                    break
                }
            }
            
            if is_live {
                result = append(result, v)
            }
        }
    }
    result
}

func (la liveness_analyzer*) get_live_in(block_id i32) i32[] {
    i32[] result
    if block_id >= 0 && block_id < la.num_blocks {
        for v := i32(0); v < la.num_values; v += 1 {
            if la.infos[v].live_in[block_id][0] != 0 {
                result = append(result, v)
            }
        }
    }
    result
}

func (la liveness_analyzer*) get_live_out(block_id i32) i32[] {
    i32[] result
    if block_id >= 0 && block_id < la.num_blocks {
        for v := i32(0); v < la.num_values; v += 1 {
            if la.infos[v].live_out[block_id][0] != 0 {
                result = append(result, v)
            }
        }
    }
    result
}

func (la liveness_analyzer*) to_string() string {
    s := "Liveness Analysis:\n"
    for b := i32(0); b < la.num_blocks; b += 1 {
        s += "Block " + string(b) + ":\n"
        s += "  Gen set: "
        for v in la.gen_set[b] {
            s += string(v) + " "
        }
        s += "\n  Kill set: "
        for v in la.kill_set[b] {
            s += string(v) + " "
        }
        s += "\n"
    }
    s
}
