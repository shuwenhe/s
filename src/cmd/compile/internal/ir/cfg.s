package compile.internal.ir.cfg

struct cfg_edge {
    int from_block
    int to_block
    string edge_type
}

struct cfg_block {
    int id
    string label
    []int predecessors
    []int successors
    int loop_depth
    bool is_loop_header
    bool is_exception_handler
}

struct control_flow_graph {
    cfg_block[] blocks
    cfg_edge[] edges
    int entry_block
    int exit_block
    []int loop_headers
    []int[] dominator_tree
    []int[] post_dominator_tree
    []int immediate_dominator
    []int immediate_post_dominator
    []int[] dominance_frontier
}

func new_cfg() control_flow_graph {
    control_flow_graph {
        blocks: cfg_block[](),
        edges: cfg_edge[](),
        entry_block: 0,
        exit_block: -1,
        loop_headers: []int(),
        dominator_tree: []int[](),
        post_dominator_tree: []int[](),
        immediate_dominator: []int(),
        immediate_post_dominator: []int(),
        dominance_frontier: []int[]()
    }
}

func (cfg* control_flow_graph) add_block(int id, string label) cfg_block {
    block := cfg_block {
        id: id,
        label: label,
        predecessors: []int(),
        successors: []int(),
        loop_depth: 0,
        is_loop_header: false,
        is_exception_handler: false
    }
    cfg.blocks.push(block)
    block
}

func (cfg* control_flow_graph) add_edge(int from, int to, string edge_type) {
    edge := cfg_edge { from_block: from, to_block: to, edge_type: edge_type }
    cfg.edges.push(edge)
    if from < cfg.blocks.len() {
        cfg.blocks[from].successors.push(to)
    }
    if to < cfg.blocks.len() {
        cfg.blocks[to].predecessors.push(from)
    }
}

func (cfg* control_flow_graph) compute_dominators() {
    n := cfg.blocks.len()
    cfg.immediate_dominator = new int[n]
    cfg.dominator_tree = new []int[n]

    for i in 0..n {
        cfg.dominator_tree[i] = []int()
    }

    for i in 0..n {
        cfg.immediate_dominator[i] = -1
    }
    cfg.immediate_dominator[cfg.entry_block] = cfg.entry_block

    changed := true
    while changed {
        changed = false
        for i in 0..n {
            if i == cfg.entry_block {
                continue
            }
            new_idom := -1
            for p in cfg.blocks[i].predecessors {
                if cfg.immediate_dominator[p] != -1 {
                    if new_idom == -1 {
                        new_idom = p
                    } else {
                        new_idom = cfg.intersect_dominators(new_idom, p)
                    }
                }
            }
            if new_idom != cfg.immediate_dominator[i] {
                cfg.immediate_dominator[i] = new_idom
                changed = true
            }
        }
    }

    for i in 0..n {
        if cfg.immediate_dominator[i] != -1 && cfg.immediate_dominator[i] != i {
            cfg.dominator_tree[cfg.immediate_dominator[i]].push(i)
        }
    }
}

func (cfg* control_flow_graph) intersect_dominators(int b1, int b2) int {
    finger1 := b1
    finger2 := b2
    while finger1 != finger2 {
        while finger1 > finger2 {
            finger1 = cfg.immediate_dominator[finger1]
        }
        while finger2 > finger1 {
            finger2 = cfg.immediate_dominator[finger2]
        }
    }
    finger1
}

func (cfg* control_flow_graph) compute_post_dominators() {
    n := cfg.blocks.len()
    cfg.immediate_post_dominator = new int[n]
    cfg.post_dominator_tree = new []int[n]

    for i in 0..n {
        cfg.post_dominator_tree[i] = []int()
    }

    for i in 0..n {
        cfg.immediate_post_dominator[i] = -1
    }
    cfg.immediate_post_dominator[cfg.exit_block] = cfg.exit_block

    changed := true
    while changed {
        changed = false
        for i in 0..n {
            if i == cfg.exit_block {
                continue
            }
            new_ipdom := -1
            for s in cfg.blocks[i].successors {
                if cfg.immediate_post_dominator[s] != -1 {
                    if new_ipdom == -1 {
                        new_ipdom = s
                    } else {
                        new_ipdom = cfg.intersect_post_dominators(new_ipdom, s)
                    }
                }
            }
            if new_ipdom != cfg.immediate_post_dominator[i] {
                cfg.immediate_post_dominator[i] = new_ipdom
                changed = true
            }
        }
    }

    for i in 0..n {
        if cfg.immediate_post_dominator[i] != -1 && cfg.immediate_post_dominator[i] != i {
            cfg.post_dominator_tree[cfg.immediate_post_dominator[i]].push(i)
        }
    }
}

func (cfg* control_flow_graph) intersect_post_dominators(int b1, int b2) int {
    finger1 := b1
    finger2 := b2
    while finger1 != finger2 {
        while finger1 > finger2 {
            finger1 = cfg.immediate_post_dominator[finger1]
        }
        while finger2 > finger1 {
            finger2 = cfg.immediate_post_dominator[finger2]
        }
    }
    finger1
}

func (cfg* control_flow_graph) compute_dominance_frontier() {
    n := cfg.blocks.len()
    cfg.dominance_frontier = new []int[n]

    for i in 0..n {
        cfg.dominance_frontier[i] = []int()
    }

    for x in 0..n {
        if cfg.blocks[x].predecessors.len() >= 2 {
            for p in cfg.blocks[x].predecessors {
                runner := p
                while runner != cfg.immediate_dominator[x] {
                    found := false
                    for df in cfg.dominance_frontier[runner] {
                        if df == x {
                            found = true
                            break
                        }
                    }
                    if !found {
                        cfg.dominance_frontier[runner].push(x)
                    }
                    runner = cfg.immediate_dominator[runner]
                    if runner == -1 {
                        break
                    }
                }
            }
        }
    }
}

func (cfg* control_flow_graph) detect_loops() {
    n := cfg.blocks.len()
    cfg.loop_headers = []int()

    visited := new bool[n]
    for i in 0..n {
        visited[i] = false
    }

    func detect_loop_dfs(int block) {
        visited[block] = true
        for succ in cfg.blocks[block].successors {
            if !visited[succ] {
                detect_loop_dfs(succ)
            } else {
                if succ <= block {
                    is_header := false
                    for h in cfg.loop_headers {
                        if h == succ {
                            is_header = true
                            break
                        }
                    }
                    if !is_header {
                        cfg.loop_headers.push(succ)
                        cfg.blocks[succ].is_loop_header = true
                    }
                }
            }
        }
    }

    detect_loop_dfs(cfg.entry_block)
}

func (cfg* control_flow_graph) compute_loop_depths() {
    n := cfg.blocks.len()
    for i in 0..n {
        cfg.blocks[i].loop_depth = 0
    }

    changed := true
    while changed {
        changed = false
        for i in 0..n {
            for p in cfg.blocks[i].predecessors {
                if cfg.blocks[p].is_loop_header && cfg.blocks[p].loop_depth >= cfg.blocks[i].loop_depth {
                    cfg.blocks[i].loop_depth = cfg.blocks[p].loop_depth + 1
                    changed = true
                }
            }
        }
    }
}

func (cfg* control_flow_graph) get_loop_body(int loop_header) []int {
    body := []int()
    body.push(loop_header)

    worklist := []int()
    for succ in cfg.blocks[loop_header].successors {
        worklist.push(succ)
    }

    while worklist.len() > 0 {
        block := worklist[0]
        worklist[0] = worklist[worklist.len() - 1]
        worklist = worklist[0..worklist.len() - 1]

        found := false
        for b in body {
            if b == block {
                found = true
                break
            }
        }

        if !found {
            body.push(block)
            for s in cfg.blocks[block].successors {
                worklist.push(s)
            }
        }
    }

    body
}
