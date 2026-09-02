package middleend

// 控制流图 (CFG) - 用于分析程序控制流
struct control_flow_graph {
    function ir_function
    blocks cfg_block[]
    entry_block_id int
    exit_block_id int
    
    dominators int[][]
    post_dominators int[][]
    dominance_frontier int[][]
}

struct cfg_block {
    block_id int
    label string
    instructions ir_instruction[]
    
    predecessors int[]
    successors int[]
    
    // 循环相关
    is_loop_header int
    loop_id int
    
    // 支配信息
    idom int
    depth int
}

struct loop_info {
    loop_id int
    header_id int
    back_edges int[]
    body_blocks int[]
    exit_blocks int[]
}

// CFG 构造
func cfg_new(func ir_function) control_flow_graph {
    cfg := control_flow_graph {
        function: func,
        entry_block_id: 0
    }
    
    // 从 IR 函数构建 CFG 块
    for i := 0; i < func.basic_blocks.len(); i = i + 1 {
        ir_block := func.basic_blocks[i]
        cfg_block := cfg_block {
            block_id: ir_block.block_id,
            label: ir_block.label,
            instructions: ir_block.instructions,
            predecessors: ir_block.predecessors,
            successors: ir_block.successors
        }
        cfg.blocks = append(cfg.blocks, cfg_block)
    }
    
    cfg
}

// 计算支配树 (Dominator Tree)
func cfg_compute_dominators(cfg* control_flow_graph) {
    n := cfg.blocks.len()
    
    // 初始化
    doms := make(int[][], n)
    for i := 0; i < n; i = i + 1 {
        doms[i] = make(int[], n)
    }
    
    // 入口块只支配自己
    doms[0][0] = 1
    
    // 其他块初始化为所有块都支配它
    for i := 1; i < n; i = i + 1 {
        for j := 0; j < n; j = j + 1 {
            doms[i][j] = 1
        }
    }
    
    // 迭代计算到收敛
    for iteration := 0; iteration < 1000; iteration = iteration + 1 {
        changed := 0
        
        for i := 1; i < n; i = i + 1 {
            new_dom := make(int[], n)
            
            // 初始化为所有块
            for j := 0; j < n; j = j + 1 {
                new_dom[j] = 1
            }
            
            block := cfg.blocks[i]
            
            // 与前驱块的支配者取交集
            if block.predecessors.len() > 0 {
                for j := 0; j < block.predecessors.len(); j = j + 1 {
                    pred_id := block.predecessors[j]
                    for k := 0; k < n; k = k + 1 {
                        new_dom[k] = new_dom[k] * doms[pred_id][k]
                    }
                }
            }
            
            // 加上自己
            new_dom[i] = 1
            
            // 检查是否变化
            for j := 0; j < n; j = j + 1 {
                if new_dom[j] != doms[i][j] {
                    changed = 1
                }
            }
            
            doms[i] = new_dom
        }
        
        if changed == 0 {
            break
        }
    }
    
    cfg.dominators = doms
}

// 计算后支配树 (Post-dominator Tree)
func cfg_compute_post_dominators(cfg* control_flow_graph) {
    n := cfg.blocks.len()
    
    // 初始化
    post_doms := make(int[][], n)
    for i := 0; i < n; i = i + 1 {
        post_doms[i] = make(int[], n)
    }
    
    // 出口块只后支配自己
    if cfg.exit_block_id >= 0 && cfg.exit_block_id < n {
        post_doms[cfg.exit_block_id][cfg.exit_block_id] = 1
    }
    
    // 其他块初始化为所有块都后支配它
    for i := 0; i < n; i = i + 1 {
        if i != cfg.exit_block_id {
            for j := 0; j < n; j = j + 1 {
                post_doms[i][j] = 1
            }
        }
    }
    
    // 迭代计算到收敛
    for iteration := 0; iteration < 1000; iteration = iteration + 1 {
        changed := 0
        
        for i := 0; i < n; i = i + 1 {
            if i == cfg.exit_block_id {
                continue
            }
            
            new_post_dom := make(int[], n)
            
            // 初始化为所有块
            for j := 0; j < n; j = j + 1 {
                new_post_dom[j] = 1
            }
            
            block := cfg.blocks[i]
            
            // 与后继块的后支配者取交集
            if block.successors.len() > 0 {
                for j := 0; j < block.successors.len(); j = j + 1 {
                    succ_id := block.successors[j]
                    for k := 0; k < n; k = k + 1 {
                        new_post_dom[k] = new_post_dom[k] * post_doms[succ_id][k]
                    }
                }
            }
            
            // 加上自己
            new_post_dom[i] = 1
            
            // 检查是否变化
            for j := 0; j < n; j = j + 1 {
                if new_post_dom[j] != post_doms[i][j] {
                    changed = 1
                }
            }
            
            post_doms[i] = new_post_dom
        }
        
        if changed == 0 {
            break
        }
    }
    
    cfg.post_dominators = post_doms
}

// 计算支配边界 (Dominance Frontier)
func cfg_compute_dominance_frontier(cfg* control_flow_graph) {
    n := cfg.blocks.len()
    frontier := make(int[][], n)
    
    for i := 0; i < n; i = i + 1 {
        frontier[i] = make(int[], 0)
    }
    
    // 对每个块
    for x := 0; x < n; x = x + 1 {
        if cfg.blocks[x].predecessors.len() >= 2 {
            // x 是 join 节点
            for i := 0; i < cfg.blocks[x].predecessors.len(); i = i + 1 {
                runner := cfg.blocks[x].predecessors[i]
                
                // 遍历从 runner 到 x 的支配路径
                for loop_count := 0; loop_count < n; loop_count = loop_count + 1 {
                    if cfg.dominators[x][runner] != 0 {
                        break
                    }
                    
                    frontier[runner] = append(frontier[runner], x)
                    
                    // 找下一个前驱
                    if cfg.blocks[runner].predecessors.len() > 0 {
                        runner = cfg.blocks[runner].predecessors[0]
                    } else {
                        break
                    }
                }
            }
        }
    }
    
    cfg.dominance_frontier = frontier
}

// 循环检测
func cfg_detect_loops(cfg* control_flow_graph) loop_info[] {
    loops := loop_info[]()
    
    // 查找所有后向边 (back edges)
    // 后向边定义为：指向已访问节点（即支配当前节点的节点）的边
    
    for i := 0; i < cfg.blocks.len(); i = i + 1 {
        block := cfg.blocks[i]
        
        for j := 0; j < block.successors.len(); j = j + 1 {
            target_id := block.successors[j]
            
            // 如果 target 支配 block，那么这是一条后向边
            if target_id < cfg.blocks.len() && cfg.dominators[i][target_id] != 0 {
                // 找到循环头是 target
                loop_id := cfg.find_or_create_loop(loops, target_id)
                loops[loop_id].back_edges = append(loops[loop_id].back_edges, i)
            }
        }
    }
    
    loops
}

func cfg_find_or_create_loop(loops loop_info[], header_id int) int {
    for i := 0; i < loops.len(); i = i + 1 {
        if loops[i].header_id == header_id {
            return i
        }
    }
    
    // 创建新循环
    new_loop := loop_info {
        loop_id: loops.len(),
        header_id: header_id
    }
    loops = append(loops, new_loop)
    loops.len() - 1
}

// CFG 验证和打印
func cfg_dump(cfg* control_flow_graph) string {
    result := "Control Flow Graph:\n"
    
    for i := 0; i < cfg.blocks.len(); i = i + 1 {
        block := cfg.blocks[i]
        result = result + "Block " + block.block_id + " (" + block.label + "):\n"
        
        result = result + "  Predecessors: "
        for j := 0; j < block.predecessors.len(); j = j + 1 {
            result = result + block.predecessors[j] + " "
        }
        result = result + "\n"
        
        result = result + "  Successors: "
        for j := 0; j < block.successors.len(); j = j + 1 {
            result = result + block.successors[j] + " "
        }
        result = result + "\n"
        
        result = result + "  Instructions: " + block.instructions.len() + "\n"
    }
    
    result
}

