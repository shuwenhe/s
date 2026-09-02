package middleend

// 数据流分析框架
struct dataflow_analysis {
    function ir_function
    cfg control_flow_graph
    
    // 活跃变量分析
    liveness liveness_info[]
    
    // 可达定义分析
    reaching_defs reaching_def_info[]
    
    // 使用-定义链
    use_def_chains use_def_chain[]
}

struct liveness_info {
    block_id int
    live_in int_set
    live_out int_set
}

struct reaching_def_info {
    block_id int
    def_in int_set
    def_out int_set
}

struct use_def_chain {
    use_instr_id int
    def_instr_ids int[]
}

struct int_set {
    values int[]
}

// 集合操作
func int_set_new() int_set {
    int_set { values: int[]() }
}

func int_set_add(set* int_set, value int) {
    for i := 0; i < set.values.len(); i = i + 1 {
        if set.values[i] == value {
            return
        }
    }
    set.values = append(set.values, value)
}

func int_set_contains(set int_set, value int) int {
    for i := 0; i < set.values.len(); i = i + 1 {
        if set.values[i] == value {
            return 1
        }
    }
    0
}

func int_set_union(set1 int_set, set2 int_set) int_set {
    result := set1
    for i := 0; i < set2.values.len(); i = i + 1 {
        int_set_add(&result, set2.values[i])
    }
    result
}

func int_set_intersect(set1 int_set, set2 int_set) int_set {
    result := int_set_new()
    for i := 0; i < set1.values.len(); i = i + 1 {
        if int_set_contains(set2, set1.values[i]) != 0 {
            int_set_add(&result, set1.values[i])
        }
    }
    result
}

func int_set_difference(set1 int_set, set2 int_set) int_set {
    result := int_set_new()
    for i := 0; i < set1.values.len(); i = i + 1 {
        if int_set_contains(set2, set1.values[i]) == 0 {
            int_set_add(&result, set1.values[i])
        }
    }
    result
}

// 活跃变量分析 (Liveness Analysis)
// 变量在某个点是活跃的，当且仅当沿着某条路径，
// 该变量的当前值会被之后使用，而在这之间不会被重新定义
func dfa_analyze_liveness(cfg* control_flow_graph) liveness_info[] {
    liveness := liveness_info[]()
    
    n := cfg.blocks.len()
    
    // 初始化所有块的活跃性信息
    for i := 0; i < n; i = i + 1 {
        liveness = append(liveness, liveness_info {
            block_id: i, live_in int_set_new(), live_out int_set_new()
        })
    }
    
    // 反复迭代直到收敛
    for iteration := 0; iteration < 1000; iteration = iteration + 1 {
        changed := 0
        
        // 后向遍历
        for i := n - 1; i >= 0; i = i - 1 {
            block := cfg.blocks[i]
            old_live_in := liveness[i].live_in
            
            // live_out = union(live_in of successors)
            new_live_out := int_set_new()
            for j := 0; j < block.successors.len(); j = j + 1 {
                succ_id := block.successors[j]
                new_live_out = int_set_union(new_live_out, liveness[succ_id].live_in)
            }
            liveness[i].live_out = new_live_out
            
            // live_in = use(block) ∪ (live_out - def(block))
            new_live_in := dfa_compute_use_def(block)
            new_live_in = int_set_union(new_live_in, 
                                        int_set_difference(new_live_out, dfa_compute_def(block)))
            liveness[i].live_in = new_live_in
            
            // 检查是否变化
            if old_live_in.values.len() != new_live_in.values.len() {
                changed = 1
            }
        }
        
        if changed == 0 {
            break
        }
    }
    
    liveness
}

func dfa_compute_use_def(block cfg_block) int_set {
    use_set := int_set_new()
    
    for i := 0; i < block.instructions.len(); i = i + 1 {
        instr := block.instructions[i]
        
        // 收集使用的值
        for j := 0; j < instr.operands.len(); j = j + 1 {
            operand := instr.operands[j]
            if operand.value_type == IR_VALUE_VAR || operand.value_type == IR_VALUE_PARAM {
                int_set_add(&use_set, operand.value_id)
            }
        }
    }
    
    use_set
}

func dfa_compute_def(block cfg_block) int_set {
    def_set := int_set_new()
    
    for i := 0; i < block.instructions.len(); i = i + 1 {
        instr := block.instructions[i]
        
        // 收集定义的值
        if instr.result.value_id != 0 {
            int_set_add(&def_set, instr.result.value_id)
        }
    }
    
    def_set
}

// 可达定义分析 (Reaching Definitions Analysis)
// 在某个点，一个定义是可达的，如果从该定义到该点
// 存在某条路径，且沿着该路径变量没有被重新定义
func dfa_analyze_reaching_defs(cfg* control_flow_graph) reaching_def_info[] {
    reaching_defs := reaching_def_info[]()
    
    n := cfg.blocks.len()
    
    // 初始化
    for i := 0; i < n; i = i + 1 {
        reaching_defs = append(reaching_defs, reaching_def_info {
            block_id: i, def_in int_set_new(), def_out int_set_new()
        })
    }
    
    // 前向遍历直到收敛
    for iteration := 0; iteration < 1000; iteration = iteration + 1 {
        changed := 0
        
        for i := 0; i < n; i = i + 1 {
            block := cfg.blocks[i]
            old_def_out := reaching_defs[i].def_out
            
            // def_in = union(def_out of predecessors)
            new_def_in := int_set_new()
            for j := 0; j < block.predecessors.len(); j = j + 1 {
                pred_id := block.predecessors[j]
                new_def_in = int_set_union(new_def_in, reaching_defs[pred_id].def_out)
            }
            reaching_defs[i].def_in = new_def_in
            
            // def_out = gen(block) ∪ (def_in - kill(block))
            gen := dfa_compute_gen(block)
            kill := dfa_compute_kill(block)
            new_def_out := int_set_union(gen, int_set_difference(new_def_in, kill))
            reaching_defs[i].def_out = new_def_out
            
            // 检查是否变化
            if old_def_out.values.len() != new_def_out.values.len() {
                changed = 1
            }
        }
        
        if changed == 0 {
            break
        }
    }
    
    reaching_defs
}

func dfa_compute_gen(block cfg_block) int_set {
    gen := int_set_new()
    
    for i := 0; i < block.instructions.len(); i = i + 1 {
        instr := block.instructions[i]
        if instr.result.value_id != 0 {
            int_set_add(&gen, instr.result.value_id)
        }
    }
    
    gen
}

func dfa_compute_kill(block cfg_block) int_set {
    // Kill 集合包含在块内被重新定义的所有指令 ID
    kill := int_set_new()
    
    for i := 0; i < block.instructions.len(); i = i + 1 {
        instr := block.instructions[i]
        if instr.result.value_id != 0 {
            // 所有之前定义该值的指令都被 kill
            for j := 0; j < i; j = j + 1 {
                prev_instr := block.instructions[j]
                if prev_instr.result.value_id == instr.result.value_id {
                    int_set_add(&kill, prev_instr.result.value_id)
                }
            }
        }
    }
    
    kill
}

// 构建使用-定义链 (Use-Def Chains)
func dfa_build_use_def_chains(cfg* control_flow_graph, reaching_defs reaching_def_info[]) use_def_chain[] {
    chains := use_def_chain[]()
    
    for block_idx := 0; block_idx < cfg.blocks.len(); block_idx = block_idx + 1 {
        block := cfg.blocks[block_idx]
        
        for instr_idx := 0; instr_idx < block.instructions.len(); instr_idx = instr_idx + 1 {
            instr := block.instructions[instr_idx]
            
            // 对每个使用的值
            for op_idx := 0; op_idx < instr.operands.len(); op_idx = op_idx + 1 {
                operand := instr.operands[op_idx]
                
                if operand.value_type == IR_VALUE_VAR || operand.value_type == IR_VALUE_PARAM {
                    chain := use_def_chain {
                        use_instr_id: instr.result.value_id, def_instr_ids int[]()
                    }
                    
                    // 找到所有可达的定义
                    for def_id := 0; def_id < reaching_defs[block_idx].def_in.values.len(); def_id = def_id + 1 {
                        if reaching_defs[block_idx].def_in.values[def_id] == operand.value_id {
                            chain.def_instr_ids = append(chain.def_instr_ids, operand.value_id)
                        }
                    }
                    
                    chains = append(chains, chain)
                }
            }
        }
    }
    
    chains
}

// DFA 分析驱动
func dfa_analyze(cfg* control_flow_graph) dataflow_analysis {
    analysis := dataflow_analysis {
        cfg: cfg
    }
    
    analysis.liveness = dfa_analyze_liveness(&cfg)
    analysis.reaching_defs = dfa_analyze_reaching_defs(&cfg)
    analysis.use_def_chains = dfa_build_use_def_chains(&cfg, analysis.reaching_defs)
    
    analysis
}

