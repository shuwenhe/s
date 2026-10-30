package compile.internal.ir

struct control_flow_graph {
    ir_function function
    cfg_block[] blocks
    int entry_block_id
    int exit_block_id

    int[][] dominators
    int[][] post_dominators
    int[][] dominance_frontier
}

struct cfg_block {
    int block_id
    string label
    ir_instruction[] instructions

    int[] predecessors
    int[] successors

    int is_loop_header
    int loop_id

    int idom
    int depth
}

struct loop_info {
    int loop_id
    int header_id
    int[] back_edges
    int[] body_blocks
    int[] exit_blocks
}

struct loop_info_result {
    loop_info[] loops
    int loop_id
}

func cfg_new(ir_function ir_func) control_flow_graph {
    cfg := control_flow_graph {
        function: ir_func, entry_block_id 0
    }

    i := 0
    {
        n := len(ir_func.basic_blocks)
        for i < n {
            ir_block := ir_func.basic_blocks[i]
            cfg_block := cfg_block {
                block_id: ir_block.block_id, label: "", instructions: ir_block.instructions, predecessors: int[](), successors: int[]()
            }
            cfg.blocks = append(cfg.blocks, cfg_block)
            i = i + 1
        }
    }

    cfg
}

// These legacy CFG passes need sized zero-filled integer arrays. Build them
// with the production array operations rather than an undeclared make API.
func cfg_zero_row(int count) int[] {
    if count < 0 { panic("negative CFG array length") }
    row := int[]()
    i := 0
    for i < count { row.push(0); i = i + 1 }
    return row
}

func cfg_empty_rows(int count) int[][] {
    if count < 0 { panic("negative CFG array length") }
    rows := int[][]()
    i := 0
    for i < count { row := int[](); rows.push(row); i = i + 1 }
    return rows
}

func cfg_compute_dominators(control_flow_graph* cfg) {
    n := cfg.blocks.len()

    doms := cfg_empty_rows(n)
    for i := 0; i < n; i = i + 1 {
        doms[i] = cfg_zero_row(n)
    }

    doms[0][0] = 1

    for loop_var_2 := 1; i < n; i = i + 1 {
        for j := 0; j < n; j = j + 1 {
            doms[loop_var_2][j] = 1
        }
    }

    for iteration := 0; iteration < 1000; iteration = iteration + 1 {
        changed := 0

        for loop_var_3 := 1; i < n; i = i + 1 {
            new_dom := cfg_zero_row(n)

            for j := 0; j < n; j = j + 1 {
                new_dom[j] = 1
            }

            block := cfg.blocks[i]

            if block.predecessors.len() > 0 {
                for j := 0; j < block.predecessors.len(); j = j + 1 {
                    pred_id := block.predecessors[j]
                    for k := 0; k < n; k = k + 1 {
                        new_dom[k] = new_dom[k] * doms[pred_id][k]
                    }
                }
            }

            new_dom[i] = 1

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

func cfg_compute_post_dominators(control_flow_graph* cfg) {
    n := cfg.blocks.len()

    post_doms := cfg_empty_rows(n)
    for i := 0; i < n; i = i + 1 {
        post_doms[i] = cfg_zero_row(n)
    }

    if cfg.exit_block_id >= 0 && cfg.exit_block_id < n {
        post_doms[cfg.exit_block_id][cfg.exit_block_id] = 1
    }

    for loop_var_2 := 0; i < n; i = i + 1 {
        if loop_var_2 != cfg.exit_block_id {
            for j := 0; j < n; j = j + 1 {
                post_doms[loop_var_2][j] = 1
            }
        }
    }

    for iteration := 0; iteration < 1000; iteration = iteration + 1 {
        changed := 0

        for loop_var_3 := 0; i < n; i = i + 1 {
            if loop_var_3 == cfg.exit_block_id {
                continue
            }

            new_post_dom := cfg_zero_row(n)

            for j := 0; j < n; j = j + 1 {
                new_post_dom[j] = 1
            }

            block := cfg.blocks[i]

            if block.successors.len() > 0 {
                for j := 0; j < block.successors.len(); j = j + 1 {
                    succ_id := block.successors[j]
                    for k := 0; k < n; k = k + 1 {
                        new_post_dom[k] = new_post_dom[k] * post_doms[succ_id][k]
                    }
                }
            }

            new_post_dom[i] = 1

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

func cfg_compute_dominance_frontier(control_flow_graph* cfg) {
    n := cfg.blocks.len()
    frontier := cfg_empty_rows(n)

    for i := 0; i < n; i = i + 1 {
        frontier[i] = cfg_zero_row(0)
    }

    for x := 0; x < n; x = x + 1 {
        if cfg.blocks[x].predecessors.len() >= 2 {

            for loop_var_2 := 0; i < cfg.blocks[x].predecessors.len(); i = i + 1 {
                runner := cfg.blocks[x].predecessors[loop_var_2]

                for loop_count := 0; loop_count < n; loop_count = loop_count + 1 {
                    if cfg.dominators[x][runner] != 0 {
                        break
                    }

                    frontier[runner] = append(frontier[runner], x)

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

func cfg_detect_loops(control_flow_graph* cfg) loop_info[] {
    loops := loop_info[]()

    for i := 0; i < cfg.blocks.len(); i = i + 1 {
        block := cfg.blocks[i]

        for j := 0; j < block.successors.len(); j = j + 1 {
            target_id := block.successors[j]

            if target_id < cfg.blocks.len() && cfg.dominators[i][target_id] != 0 {
                result := cfg_find_or_create_loop(loops, target_id)
                loop_id := result.loop_id
                loops[loop_id].back_edges = append(loops[loop_id].back_edges, i)
            }
        }
    }

    return loops
}

func cfg_find_or_create_loop(loop_info[] loops, int header_id) loop_info_result {
    for i := 0; i < loops.len(); i = i + 1 {
        if loops[i].header_id == header_id {
            return loop_info_result {
                loops: loops, loop_id: i
            }
        }
    }

    new_loop := loop_info {
        loop_id: loops.len(), header_id: header_id
    }
    updated := append(loops, new_loop)
    return loop_info_result {
        loops: updated, loop_id: len(updated) - 1
    }
}

func cfg_dump(control_flow_graph* cfg) string {
    result := "Control Flow Graph:\n"

    for i := 0; i < cfg.blocks.len(); i = i + 1 {
        block := cfg.blocks[i]
        result = result + "Block " + to_string(block.block_id) + " (" + block.label + "):\n"

        result = result + "  Predecessors: "
        for j := 0; j < block.predecessors.len(); j = j + 1 {
            result = result + to_string(block.predecessors[j]) + " "
        }
        result = result + "\n"

        result = result + "  Successors: "
        for j := 0; j < block.successors.len(); j = j + 1 {
            result = result + to_string(block.successors[j]) + " "
        }
        result = result + "\n"

        result = result + "  Instructions: " + to_string(block.instructions.len()) + "\n"
    }

    result
}
