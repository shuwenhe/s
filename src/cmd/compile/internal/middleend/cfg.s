package middleend

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


    is_loop_header int
    loop_id int


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

func cfg_new(func ir_function) control_flow_graph {
    cfg := control_flow_graph {
        function: func, entry_block_id 0
    }


    for i := 0; i < func.basic_blocks.len(); i = i + 1 {
        ir_block := func.basic_blocks[i]
        cfg_block := cfg_block {
            block_id: ir_block.block_id, label ir_block.label, instructions ir_block.instructions, predecessors ir_block.predecessors, successors ir_block.successors
        }
        cfg.blocks = append(cfg.blocks, cfg_block)
    }

    cfg
}

func cfg_compute_dominators(cfg* control_flow_graph) {
    n := cfg.blocks.len()


    doms := make(int[][], n)
    for i := 0; i < n; i = i + 1 {
        doms[i] = make(int[], n)
    }


    doms[0][0] = 1


    for i := 1; i < n; i = i + 1 {
        for j := 0; j < n; j = j + 1 {
            doms[i][j] = 1
        }
    }


    for iteration := 0; iteration < 1000; iteration = iteration + 1 {
        changed := 0

        for i := 1; i < n; i = i + 1 {
            new_dom := make(int[], n)


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

func cfg_compute_post_dominators(cfg* control_flow_graph) {
    n := cfg.blocks.len()


    post_doms := make(int[][], n)
    for i := 0; i < n; i = i + 1 {
        post_doms[i] = make(int[], n)
    }


    if cfg.exit_block_id >= 0 && cfg.exit_block_id < n {
        post_doms[cfg.exit_block_id][cfg.exit_block_id] = 1
    }


    for i := 0; i < n; i = i + 1 {
        if i != cfg.exit_block_id {
            for j := 0; j < n; j = j + 1 {
                post_doms[i][j] = 1
            }
        }
    }


    for iteration := 0; iteration < 1000; iteration = iteration + 1 {
        changed := 0

        for i := 0; i < n; i = i + 1 {
            if i == cfg.exit_block_id {
                continue
            }

            new_post_dom := make(int[], n)


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

func cfg_compute_dominance_frontier(cfg* control_flow_graph) {
    n := cfg.blocks.len()
    frontier := make(int[][], n)

    for i := 0; i < n; i = i + 1 {
        frontier[i] = make(int[], 0)
    }


    for x := 0; x < n; x = x + 1 {
        if cfg.blocks[x].predecessors.len() >= 2 {

            for i := 0; i < cfg.blocks[x].predecessors.len(); i = i + 1 {
                runner := cfg.blocks[x].predecessors[i]


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

func cfg_detect_loops(cfg* control_flow_graph) loop_info[] {
    loops := loop_info[]()



    for i := 0; i < cfg.blocks.len(); i = i + 1 {
        block := cfg.blocks[i]

        for j := 0; j < block.successors.len(); j = j + 1 {
            target_id := block.successors[j]


            if target_id < cfg.blocks.len() && cfg.dominators[i][target_id] != 0 {

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


    new_loop := loop_info {
        loop_id: loops.len(), header_id header_id
    }
    loops = append(loops, new_loop)
    loops.len() - 1
}

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

